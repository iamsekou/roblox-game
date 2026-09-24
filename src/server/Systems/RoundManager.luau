-- Round flow: lobby queue -> intermission -> round -> results -> everyone back to the lobby.
--
--   Waiting --(>= MIN queued)--> Intermission --(15s)--> InRound --(win / cap / too few)--> RoundEnd --(6s)--> Waiting
--        ^------(queue drops below MIN)------'
--
-- The rules of a round live in Lib/MatchCore (pure, unit-tested). This module turns them into spawns,
-- timers and broadcasts. Modes: FFA and Team6v6 (team rules in Lib/TeamRules).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local MapRegistry = require(ReplicatedStorage.Shared.Modules.MapRegistry)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MatchCore = require(script.Parent.Parent.Lib.MatchCore)
local RoundTimer = require(script.Parent.Parent.Lib.RoundTimer)
local TeamRules = require(script.Parent.Parent.Lib.TeamRules)
local EconomyService = require(script.Parent.EconomyService)
local MapService = require(script.Parent.MapService)
local NumberAssignmentService = require(script.Parent.NumberAssignmentService)
local PlayerLifeService = require(script.Parent.PlayerLifeService)

local RoundManager = {}

local TICK_SECONDS = 0.25

local state = {
	phase = "Waiting", -- "Waiting" | "Intermission" | "InRound" | "RoundEnd"
	endsAt = 0,
	graceEndsAt = nil :: number?,
	mode = nil :: string?,
	mapId = nil :: string?,
	match = nil :: any,
	result = nil :: any,
	seq = 0,
	warnedFor = nil :: number?, -- the end time the last "time left" alert was sent for
}

local queued: { [Player]: number } = {} -- player -> time they queued (earliest first)
local pendingRespawn: { [Player]: number } = {} -- player -> lifeId whose respawn is already scheduled
local lifeStartedHandlers: { (player: Player, match: any, lifeId: number) -> () } = {}

-- Other systems (AbilityService) hear about every new arena life: round start, respawn, mid-round join.
function RoundManager.onLifeStarted(handler: (player: Player, match: any, lifeId: number) -> ())
	table.insert(lifeStartedHandlers, handler)
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function devLog(...)
	if RunService:IsStudio() then
		print("[NAU]", ...)
	end
end

local function minPlayers(): number
	if RunService:IsStudio() then
		local override = ServerScriptService:GetAttribute(Constants.DEV_MIN_PLAYERS_ATTRIBUTE)
		if typeof(override) == "number" and override >= 1 then
			return math.floor(override)
		end
	end
	return Constants.MIN_PLAYERS_TO_START
end

local TEAM_NAMES = {}
for _, team in Constants.TEAMS do
	table.insert(TEAM_NAMES, team.name)
end

-- Uniform random among the enabled modes; team battle only with enough fighters queued (Lib/TeamRules).
local function pickMode(queuedCount: number): string
	if RunService:IsStudio() then
		local forced = ServerScriptService:GetAttribute(Constants.DEV_MODE_ATTRIBUTE)
		if forced == "FFA" or forced == "Team6v6" then
			return forced
		end
	end
	return TeamRules.pickMode(Constants.ENABLED_MODES, queuedCount, Constants.TEAM_MODE_MIN_PLAYERS, math.random())
end

-- Team battle: the team a mid-round joiner goes to (the smaller one; on a tie, the one behind).
local function teamForJoiner(match: any): string
	local sizes = {}
	for _, p in match.participants do
		if p.team then
			sizes[p.team] = (sizes[p.team] or 0) + 1
		end
	end
	return TeamRules.teamForJoiner(TEAM_NAMES, sizes, match.teamScores)
end

local function roundTimeCap(): number
	if RunService:IsStudio() then
		local override = ServerScriptService:GetAttribute(Constants.DEV_ROUND_SECONDS_ATTRIBUTE)
		if typeof(override) == "number" and override >= 1 then
			return override
		end
	end
	return Constants.ROUND_TIME_CAP
end

-- Owner, 2026-09-23: everyone in the match hears when ROUND_WARNING_SECONDS are left (regular time, and
-- again in sudden death, which has its own end time).
local function alertTimeLeft(match: any, t: number)
	if not RoundTimer.warningDue(state.endsAt, t, Constants.ROUND_WARNING_SECONDS, state.warnedFor) then
		return
	end
	state.warnedFor = state.endsAt
	local payload = { kind = "time_left", seconds = math.ceil(state.endsAt - t), suddenDeath = match.suddenDeath == true }
	for id in match.participants do
		local player = Players:GetPlayerByUserId(id)
		if player then
			Remotes.RoundAlert:FireClient(player, payload)
		end
	end
	devLog(string.format("%d seconds left alert sent%s", payload.seconds, if payload.suddenDeath then " (sudden death)" else ""))
end

local function queuedPlayers(): { Player }
	local list = {}
	for player in queued do
		if player.Parent then
			table.insert(list, player)
		end
	end
	table.sort(list, function(a, b)
		return queued[a] < queued[b]
	end)
	return list
end

local function setElims(player: Player, value: number)
	EconomyService.leaderstat(player, "Elims").Value = value
end

local function buildState()
	state.seq += 1
	local match = state.match
	local participants, scores = {}, {}
	if match then
		for id, p in match.participants do
			table.insert(participants, id)
			-- protected: public (it only hides a blank plate), lets clients drop that fighter's plate
			table.insert(scores, { userId = id, score = p.score, alive = p.alive, protected = p.protectedUntil ~= nil, team = p.team })
		end
	end
	local queue = {}
	for _, player in queuedPlayers() do
		table.insert(queue, player.UserId)
	end
	local mapDef = state.mapId and MapRegistry.get(state.mapId)
	return {
		seq = state.seq,
		phase = state.phase,
		endsAt = state.endsAt,
		graceEndsAt = state.graceEndsAt,
		mode = state.mode,
		mapName = if mapDef then mapDef.displayName else nil,
		suddenDeath = match ~= nil and match.suddenDeath == true,
		maxPlayers = Constants.MAX_PLAYERS,
		minPlayers = minPlayers(),
		participants = participants,
		queued = queue,
		scores = scores,
		teamScores = if match and match.mode == "Team6v6" then match.teamScores else nil, -- team name -> eliminations
		result = state.result,
	}
end

local broadcastScheduled = false
local function broadcast()
	if broadcastScheduled then
		return
	end
	broadcastScheduled = true
	task.defer(function()
		broadcastScheduled = false
		Remotes.RoundState:FireAllClients(buildState())
	end)
end

-- Random, unmarked spawn anywhere on the map (owner rule), kept away from living opponents.
local function pickArenaSpawn(match: any, forUserId: number): CFrame
	local threats = {}
	for id, p in match.participants do
		if id ~= forUserId and p.alive and not match:isTeammate(id, forUserId) then
			local player = Players:GetPlayerByUserId(id)
			local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				table.insert(threats, (root :: BasePart).Position)
			end
		end
	end
	return MapService.findArenaSpawn(threats)
end

-- Spawn protection (approved): for SPAWN_PROTECTION_SECONDS after a spawn the fighter has no plate
-- for anyone and sees no plates. MatchCore enforces it; this lifts it on time for that life only.
local function scheduleProtectionRelease(player: Player, match: any, lifeId: number)
	task.delay(Constants.SPAWN_PROTECTION_SECONDS, function()
		local p = match.participants[player.UserId]
		if state.match ~= match or match.ended or not p or p.lifeId ~= lifeId then
			return
		end
		if match:releaseProtection(player.UserId, now()) then
			devLog(string.format("protection over for %s at t=%.2f", player.Name, os.clock()))
			if player.Parent then
				Remotes.LifeState:FireClient(player, { alive = true, inMatch = true })
			end
			broadcast()
		end
	end)
end

-- Puts a participant into the arena for a new life. Codes for this life are issued only once the
-- character is standing in the arena and spawn protection is over.
local function spawnIntoArena(player: Player, cframe: CFrame?)
	local match = state.match
	if not match or match.ended or not match.participants[player.UserId] then
		return
	end
	local character = PlayerLifeService.spawnAt(player, cframe or pickArenaSpawn(match, player.UserId), { arena = true })
	if not character or state.match ~= match or match.ended then
		return
	end
	local p = match.participants[player.UserId]
	if not p or p.alive then
		return
	end
	local t = now()
	local lifeId = match:spawn(player.UserId, t)
	if not lifeId then
		return
	end
	devLog(string.format("spawned %s in arena (life %d) at t=%.2f", player.Name, lifeId, os.clock()))
	Remotes.LifeState:FireClient(player, {
		alive = true,
		inMatch = true,
		protectedUntil = if Constants.SPAWN_PROTECTION_SECONDS > 0 then t + Constants.SPAWN_PROTECTION_SECONDS else nil,
	})
	Remotes.MatchFeed:FireAllClients({ kind = "spawned", userId = player.UserId })
	for _, handler in lifeStartedHandlers do
		task.spawn(handler, player, match, lifeId)
	end
	scheduleProtectionRelease(player, match, lifeId)
	broadcast()
end

local function scheduleRespawn(player: Player, lifeId: number)
	if pendingRespawn[player] == lifeId then
		return -- already scheduled for this death
	end
	pendingRespawn[player] = lifeId
	local match = state.match
	task.delay(Constants.RESPAWN_SECONDS, function()
		if pendingRespawn[player] == lifeId then
			pendingRespawn[player] = nil
		end
		if not match or state.match ~= match or match.ended or not player.Parent then
			return
		end
		local p = match.participants[player.UserId]
		if p and not p.alive and p.lifeId == lifeId then
			spawnIntoArena(player)
		end
	end)
end

local function joinMidRound(player: Player): boolean
	local match = state.match
	local team = if match.mode == "Team6v6" then teamForJoiner(match) else nil
	if not match:addParticipant(player.UserId, team, now()) then
		return false
	end
	queued[player] = nil
	setElims(player, 0)
	task.spawn(spawnIntoArena, player)
	broadcast()
	return true
end

-- Every lost life in a round goes through here: code eliminations, strike-outs, and falls.
function RoundManager.onLifeLost(victimId: number, info: { cause: string, attacker: Player? })
	local match = state.match
	local p = match and match.participants[victimId]
	local victim = Players:GetPlayerByUserId(victimId)
	if not match or not p or not victim then
		return
	end
	local attacker = info.attacker
	if attacker then
		local attackerState = match.participants[attacker.UserId]
		if attackerState then
			setElims(attacker, attackerState.score)
		end
	end
	devLog(string.format("life lost: %s cause=%s t=%.2f", victim.Name, info.cause, os.clock()))
	Remotes.MatchFeed:FireAllClients({
		kind = "eliminated",
		victim = victimId,
		attacker = if attacker then attacker.UserId else nil,
		cause = info.cause,
	})
	Remotes.LifeState:FireClient(victim, {
		alive = false,
		inMatch = true,
		cause = info.cause,
		byName = if attacker then attacker.DisplayName else nil,
		respawnAt = if match.ended then nil else now() + Constants.RESPAWN_SECONDS,
	})
	PlayerLifeService.kill(victim)
	if not match.ended then
		scheduleRespawn(victim, p.lifeId)
	end
	broadcast()
end

local function onDied(player: Player)
	local match = state.match
	local p = match and not match.ended and match.participants[player.UserId]
	if p then
		if p.alive then
			-- Not an elimination (fell into the void, used Reset): no credit to anyone, same respawn rules.
			match:markDead(player.UserId, now())
			RoundManager.onLifeLost(player.UserId, { cause = "fell" })
		else
			scheduleRespawn(player, p.lifeId) -- no-op if the elimination path already scheduled it
		end
		return
	end
	-- Died in the lobby, or after the round ended: back to the lobby shortly.
	task.delay(Constants.RESPAWN_SECONDS, function()
		local current = state.match
		local inActiveRound = current and not current.ended and current.participants[player.UserId]
		if player.Parent and not inActiveRound then
			PlayerLifeService.spawnAt(player, MapService.getLobbySpawn())
		end
	end)
end

function RoundManager.finish(winner: any)
	if state.phase ~= "InRound" or not state.match then
		return
	end
	local match = state.match
	local result = { kind = winner.kind, reason = winner.reason, team = winner.team }
	if winner.id then
		local player = Players:GetPlayerByUserId(winner.id)
		local p = match.participants[winner.id]
		result.userId = winner.id
		result.name = if player then player.DisplayName else "A fighter"
		result.score = if p then p.score else nil
	end
	state.result = result
	state.phase = "RoundEnd"
	state.endsAt = now() + Constants.ROUND_END_SECONDS
	state.graceEndsAt = nil
	-- Everyone who fought is queued for the next round automatically; they can leave the queue in the lobby.
	local t = now()
	for id in match.participants do
		local player = Players:GetPlayerByUserId(id)
		if player and not queued[player] then
			queued[player] = t
		end
	end
	devLog("round finished:", result.kind, result.reason, result.name or result.team or "")
	broadcast()
end

local function startRound()
	-- Uniform random mode and map every round; back-to-back repeats are allowed (approved). Team battle needs
	-- TEAM_MODE_MIN_PLAYERS queued.
	local mode = pickMode(#queuedPlayers())
	local maps = MapRegistry.enabled()
	local mapDef = maps[math.random(1, #maps)]
	MapService.loadMap(mapDef.id)

	local match = MatchCore.new({
		mode = mode,
		maxPlayers = Constants.MAX_PLAYERS,
		strikeLimit = Constants.WRONG_SUBMISSION_LIMIT,
		debounce = Constants.SUBMISSION_DEBOUNCE,
		staleWindow = Constants.STALE_CODE_GRACE,
		reuseCooldown = Constants.CODE_REUSE_COOLDOWN,
		protectionSeconds = Constants.SPAWN_PROTECTION_SECONDS,
		maxInputLock = Constants.MAX_INPUT_LOCK,
		codeLength = Constants.CODE_LENGTH,
		onCodeChange = NumberAssignmentService.onCodeChange,
	})
	state.match = match
	state.mode = mode
	state.mapId = mapDef.id
	state.result = nil
	state.graceEndsAt = nil
	NumberAssignmentService.attach(match)

	local t = now()
	-- Team battle: the first MAX_PLAYERS queued are shuffled and dealt onto the teams in turn.
	local teams: { [number]: string } = {}
	if mode == "Team6v6" then
		local ids = {}
		for i, player in queuedPlayers() do
			if i > Constants.MAX_PLAYERS then
				break
			end
			table.insert(ids, player.UserId)
		end
		for i = #ids, 2, -1 do
			local j = math.random(1, i)
			ids[i], ids[j] = ids[j], ids[i]
		end
		teams = TeamRules.split(ids, TEAM_NAMES)
		for _, name in TEAM_NAMES do
			match:addTeam(name)
		end
	end
	local roster = {}
	for _, player in queuedPlayers() do
		if match:addParticipant(player.UserId, teams[player.UserId], t) then
			queued[player] = nil
			setElims(player, 0)
			table.insert(roster, player)
		end
	end
	state.phase = "InRound"
	state.endsAt = t + roundTimeCap()
	state.warnedFor = nil
	devLog(string.format("round started: %s on %s with %d fighters", mode, mapDef.id, #roster))
	for _, player in roster do
		local p = match.participants[player.UserId]
		if p and p.team then
			devLog(string.format("  %s is on %s", player.Name, p.team))
		end
	end
	broadcast()

	-- Opening wave: random spots across the map, each kept away from the spots already handed out.
	local taken = {}
	for _, player in roster do
		local spawnCFrame = MapService.findArenaSpawn(taken)
		table.insert(taken, spawnCFrame.Position)
		task.spawn(spawnIntoArena, player, spawnCFrame)
	end
end

local function returnToLobby()
	local match = state.match
	local roster = {}
	if match then
		for id in match.participants do
			local player = Players:GetPlayerByUserId(id)
			if player then
				table.insert(roster, player)
			end
		end
	end
	state.match = nil
	state.mode = nil
	state.mapId = nil
	state.result = nil
	state.phase = "Waiting"
	state.endsAt = 0
	table.clear(pendingRespawn)
	NumberAssignmentService.detach()
	for _, player in roster do
		Remotes.LifeState:FireClient(player, { alive = true, inMatch = false })
		task.spawn(PlayerLifeService.spawnAt, player, MapService.getLobbySpawn())
	end
	broadcast()
end

local function tick()
	local t = now()
	local phase = state.phase
	if phase == "Waiting" then
		if #queuedPlayers() >= minPlayers() then
			state.phase = "Intermission"
			state.endsAt = t + Constants.INTERMISSION_SECONDS
			broadcast()
		end
	elseif phase == "Intermission" then
		if #queuedPlayers() < minPlayers() then
			state.phase = "Waiting"
			state.endsAt = 0
			broadcast()
		elseif t >= state.endsAt then
			startRound()
		end
	elseif phase == "InRound" then
		local match = state.match
		if match.ended then
			RoundManager.finish(match.winner) -- backstop; the elimination path normally finishes first
			return
		end
		-- Players waiting because the match was full drop in as slots open.
		for _, player in queuedPlayers() do
			if not match:canJoin() then
				break
			end
			joinMidRound(player)
		end
		-- Too few fighters: wait a grace period for someone to join, then end with no winner.
		if match:count() < minPlayers() then
			if not state.graceEndsAt then
				state.graceEndsAt = t + Constants.UNDERPOPULATED_GRACE
				broadcast()
			elseif t >= state.graceEndsAt then
				RoundManager.finish(match:endAsDraw("not_enough_players"))
				return
			end
		elseif state.graceEndsAt then
			state.graceEndsAt = nil
			broadcast()
		end
		alertTimeLeft(match, t)
		if t >= state.endsAt then
			if match.suddenDeath then
				RoundManager.finish(match:endAsDraw("sudden_death_expired"))
			else
				local winner = match:resolveTimeCap()
				if winner then
					RoundManager.finish(winner)
				else
					state.endsAt = t + Constants.SUDDEN_DEATH_SECONDS
					devLog("time cap reached with a tie: sudden death")
					broadcast()
				end
			end
		end
	elseif phase == "RoundEnd" then
		if t >= state.endsAt then
			returnToLobby()
		end
	end
end

function RoundManager.getMatch(): any
	if state.phase == "InRound" then
		return state.match
	end
	return nil
end

function RoundManager.requestFight(player: Player)
	local match = state.match
	if match and not match.ended and match.participants[player.UserId] then
		return { status = "already_in_match" }
	end
	if state.phase == "InRound" and match and not match.ended then
		if match:canJoin() and joinMidRound(player) then
			return { status = "joined" }
		end
		if queued[player] then
			return { status = "already_queued" }
		end
		queued[player] = now()
		broadcast()
		return { status = "queued_match_full" }
	end
	if queued[player] then
		return { status = "already_queued" }
	end
	if #queuedPlayers() >= Constants.MAX_PLAYERS then
		return { status = "queue_full" }
	end
	queued[player] = now()
	broadcast()
	return { status = if state.phase == "RoundEnd" then "queued_round_ending" else "queued" }
end

function RoundManager.leaveQueue(player: Player)
	if not queued[player] then
		return { status = "not_queued" }
	end
	queued[player] = nil
	broadcast()
	return { status = "left_queue" }
end

function RoundManager.Init()
	PlayerLifeService.onDied = onDied
	Remotes.RequestFight.OnServerInvoke = RoundManager.requestFight
	Remotes.LeaveQueue.OnServerInvoke = RoundManager.leaveQueue
	Remotes.GetRoundState.OnServerInvoke = function()
		return buildState()
	end
	Players.PlayerRemoving:Connect(function(player)
		queued[player] = nil
		pendingRespawn[player] = nil
		local match = state.match
		if match and match.participants[player.UserId] then
			match:removeParticipant(player.UserId, now())
			broadcast()
		end
	end)
end

function RoundManager.Start()
	broadcast()
	while true do
		local ok, err = pcall(tick)
		if not ok then
			warn("[NAU] round tick failed: " .. tostring(err))
		end
		task.wait(TICK_SECONDS)
	end
end

return RoundManager
