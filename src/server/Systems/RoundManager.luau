-- Round flow: always-on rounds (owner, 2026-09-30). The arena runs on its own schedule whether or not anyone
-- pressed FIGHT, and anyone can join at any time (straight into a running round, or at the next start):
--
--   Intermission (15 s) --> InRound (time cap, sudden death on a tie) --> RoundEnd (6 s) --> Intermission --> ...
--
-- A round never ends early for lack of fighters; one nobody joined ends as a draw at its time cap. Players in the
-- lobby hear every step through their HUD (HUDController's lobby announcements).
--
-- The rules of a round live in Lib/MatchCore (pure, unit-tested). This module turns them into spawns,
-- timers and broadcasts. Modes: FFA and Team6v6 (team rules in Lib/TeamRules).
--
-- Training Grounds (2026-09-29): on a training server (ServerMode) the round is FFA in the dojo, starts with one
-- player and never runs out (TrainingService sets its length), and TrainingService adds training dummies. Dummies
-- are match participants like players (FighterRegistry, "bots" in the code); TrainingService spawns their bodies
-- through setBotHooks.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local MapRegistry = require(ReplicatedStorage.Shared.Modules.MapRegistry)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MatchCore = require(script.Parent.Parent.Lib.MatchCore)
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)
local RoundTimer = require(script.Parent.Parent.Lib.RoundTimer)
local TeamRules = require(script.Parent.Parent.Lib.TeamRules)
local EconomyService = require(script.Parent.EconomyService)
local MapService = require(script.Parent.MapService)
local NumberAssignmentService = require(script.Parent.NumberAssignmentService)
local PlayerLifeService = require(script.Parent.PlayerLifeService)
local ServerMode = require(script.Parent.ServerMode)
local FighterRegistry = require(script.Parent.FighterRegistry)

local RoundManager = {}

local TICK_SECONDS = 0.25

local state = {
	phase = "Waiting", -- "Waiting" (only until the first tick) | "Intermission" | "InRound" | "RoundEnd"
	endsAt = 0,
	mode = nil :: string?,
	mapId = nil :: string?,
	match = nil :: any,
	result = nil :: any,
	seq = 0,
	warnedFor = nil :: number?, -- the end time the last "time left" alert was sent for
}

local queued: { [Player]: number } = {} -- player -> time they queued (earliest first)
local pendingRespawn: { [Player]: number } = {} -- player -> lifeId whose respawn is already scheduled
local pendingBotRespawn: { [number]: number } = {} -- bot id -> lifeId whose respawn is already scheduled

-- Training Grounds: TrainingService's round length and extra round-state fields.
local trainingRoundSeconds: () -> number = function()
	return Constants.TRAINING_FREE_ROUND_SECONDS
end
local trainingInfo: () -> any = function()
	return nil
end

-- Bots (TrainingService): `spawn(id, cframe)` puts the bot's body at cframe (false if it couldn't);
-- `lifeLost(id)` plays its death. RoundManager does the rules, the feed and the respawn timing.
type BotHooks = { spawn: (id: number, cframe: CFrame) -> boolean, lifeLost: (id: number) -> () }
local botHooks: BotHooks? = nil
local roundStartedHandlers: { (match: any) -> () } = {}
local lifeStartedHandlers: { (player: Player, match: any, lifeId: number) -> () } = {}
local stateRequests = RateLimiter.new(Constants.ROUND_STATE_MIN_INTERVAL)
local lastState: any = nil -- the latest RoundState broadcast (answers GetRoundState requests that come too fast)
local lastPurge = 0

-- Other systems (AbilityService) hear about every new arena life: round start, respawn, mid-round join.
function RoundManager.onLifeStarted(handler: (player: Player, match: any, lifeId: number) -> ())
	table.insert(lifeStartedHandlers, handler)
end

-- XpService hears how each round ended: `winner` is MatchCore's { kind, id?, team?, reason } (a draw has neither).
local roundFinishedHandlers: { (match: any, winner: any) -> () } = {}
function RoundManager.onRoundFinished(handler: (match: any, winner: any) -> ())
	table.insert(roundFinishedHandlers, handler)
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function devLog(...)
	if RunService:IsStudio() then
		print("[NAU]", ...)
	end
end

local TEAM_NAMES = {}
for _, team in Constants.TEAMS do
	table.insert(TEAM_NAMES, team.name)
end

-- Uniform random among the enabled modes; team battle only with enough fighters queued (Lib/TeamRules).
local function pickMode(queuedCount: number): string
	if ServerMode.isTraining then
		return "FFA"
	end
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
	if ServerMode.isTraining then
		return trainingRoundSeconds()
	end
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

-- `bump`: a broadcast (a new state). A reply to GetRoundState doesn't bump the sequence number: it's the same
-- state, and bumping on every request let one client push everyone's sequence along.
local function buildState(bump: boolean)
	if bump then
		state.seq += 1
	end
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
		mode = state.mode,
		mapName = if mapDef then mapDef.displayName else nil,
		suddenDeath = match ~= nil and match.suddenDeath == true,
		maxPlayers = Constants.MAX_PLAYERS,
		participants = participants,
		queued = queue,
		scores = scores,
		teamScores = if match and match.mode == "Team6v6" then match.teamScores else nil, -- team name -> eliminations
		result = state.result,
		names = if ServerMode.isTraining then FighterRegistry.botNames() else nil, -- bots' shown names (tostring(id) -> name)
		training = if ServerMode.isTraining then trainingInfo() else nil, -- { bots } (the dummy count)
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
		lastState = buildState(true)
		Remotes.RoundState:FireAllClients(lastState)
	end)
end

-- Random, unmarked spawn anywhere on the map (owner rule), kept away from living opponents.
local function pickArenaSpawn(match: any, forUserId: number): CFrame
	local threats = {}
	for id, p in match.participants do
		if id ~= forUserId and p.alive and not match:isTeammate(id, forUserId) then
			local fighter = FighterRegistry.get(id) -- a player or a training bot
			local root = fighter and fighter.Character and fighter.Character:FindFirstChild("HumanoidRootPart")
			if root then
				table.insert(threats, (root :: BasePart).Position)
			end
		end
	end
	return MapService.findArenaSpawn(threats)
end

-- Spawn protection (approved): for SPAWN_PROTECTION_SECONDS after a spawn the fighter has no plate
-- for anyone and sees no plates. MatchCore enforces it; this lifts it on time for that life only.
local function scheduleProtectionRelease(fighter: any, match: any, lifeId: number)
	local id = fighter.UserId
	task.delay(Constants.SPAWN_PROTECTION_SECONDS, function()
		local p = match.participants[id]
		if state.match ~= match or match.ended or not p or p.lifeId ~= lifeId then
			return
		end
		if match:releaseProtection(id, now()) then
			if not FighterRegistry.isBot(fighter) then
				devLog(string.format("protection over for %s at t=%.2f", fighter.Name, os.clock()))
				if fighter.Parent then
					Remotes.LifeState:FireClient(fighter, { alive = true, inMatch = true })
				end
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

-- A bot's new life: TrainingService places its body, then the same rules as a player's spawn (a fresh life,
-- spawn protection, the feed, and every life-started handler with the bot's handle).
local function spawnBot(id: number, cframe: CFrame?)
	local match = state.match
	local handle = FighterRegistry.bot(id)
	local p = match and match.participants[id]
	if not match or match.ended or not p or p.alive or not handle or not botHooks then
		return
	end
	if not botHooks.spawn(id, cframe or pickArenaSpawn(match, id)) then
		return
	end
	if state.match ~= match or match.ended or not match.participants[id] then
		return
	end
	local lifeId = match:spawn(id, now())
	if not lifeId then
		return
	end
	Remotes.MatchFeed:FireAllClients({ kind = "spawned", userId = id })
	for _, handler in lifeStartedHandlers do
		task.spawn(handler, handle, match, lifeId)
	end
	scheduleProtectionRelease(handle, match, lifeId)
	broadcast()
end

local function scheduleBotRespawn(id: number, lifeId: number)
	if pendingBotRespawn[id] == lifeId then
		return
	end
	pendingBotRespawn[id] = lifeId
	local match = state.match
	task.delay(Constants.RESPAWN_SECONDS, function()
		if pendingBotRespawn[id] == lifeId then
			pendingBotRespawn[id] = nil
		end
		local p = match and match.participants[id]
		if match and state.match == match and not match.ended and p and not p.alive and p.lifeId == lifeId then
			spawnBot(id)
		end
	end)
end

-- Training Grounds ------------------------------------------------------------------------------------------

-- TrainingService: the bots' bodies, the round length, and what the round state says about training.
function RoundManager.setBotHooks(hooks: BotHooks)
	botHooks = hooks
end

function RoundManager.setTrainingRules(roundSeconds: () -> number, info: () -> any)
	trainingRoundSeconds = roundSeconds
	trainingInfo = info
end

-- Called with the match whenever a round starts (TrainingService adds its bots then).
function RoundManager.onRoundStarted(handler: (match: any) -> ())
	table.insert(roundStartedHandlers, handler)
end

-- A bot joins the running round (and spawns). False if there's no round or it's full.
function RoundManager.addBot(id: number): boolean
	local match = state.match
	if state.phase ~= "InRound" or not match or match.ended or not FighterRegistry.bot(id) then
		return false
	end
	if not match:addParticipant(id, nil, now()) then
		return false
	end
	task.spawn(spawnBot, id)
	broadcast()
	return true
end

-- A bot leaves the round (fewer bots chosen, or the round is being rebuilt).
function RoundManager.removeBot(id: number)
	pendingBotRespawn[id] = nil
	local match = state.match
	if match and match.participants[id] then
		local winner = match:removeParticipant(id, now())
		if winner and state.phase == "InRound" and state.match == match then
			RoundManager.finish(winner)
		end
		broadcast()
	end
end

-- A bot died outside the rules (fell off the map): like a player's reset, no credit to anyone.
function RoundManager.botDied(id: number)
	local match = state.match
	local p = match and not match.ended and match.participants[id]
	if p and p.alive then
		match:markDead(id, now())
		RoundManager.onLifeLost(id, { cause = "fell" })
	end
end

-- Re-send the round state (TrainingService changed a setting the state shows).
function RoundManager.refresh()
	broadcast()
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

-- Every lost life in a round goes through here: code eliminations, strike-outs, and falls. The victim and the
-- attacker may each be a player or a training bot.
function RoundManager.onLifeLost(victimId: number, info: { cause: string, attacker: any? })
	local match = state.match
	local p = match and match.participants[victimId]
	local victim = Players:GetPlayerByUserId(victimId)
	local bot = if victim then nil else FighterRegistry.bot(victimId)
	if not match or not p or (not victim and not bot) then
		return
	end
	local attacker = info.attacker
	if attacker and not FighterRegistry.isBot(attacker) then
		local attackerState = match.participants[attacker.UserId]
		if attackerState then
			setElims(attacker, attackerState.score)
		end
	end
	NumberAssignmentService.endLife(victimId) -- reading exceptions end with the life
	devLog(string.format("life lost: %s cause=%s t=%.2f", (victim or bot :: any).Name, info.cause, os.clock()))
	Remotes.MatchFeed:FireAllClients({
		kind = "eliminated",
		victim = victimId,
		attacker = if attacker then attacker.UserId else nil,
		cause = info.cause,
	})
	if victim then
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
	else
		if botHooks then
			task.spawn(botHooks.lifeLost, victimId)
		end
		if not match.ended then
			scheduleBotRespawn(victimId, p.lifeId)
		end
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
		local p = match.participants[winner.id]
		result.userId = winner.id
		result.name = FighterRegistry.displayName(winner.id) or "A fighter"
		result.score = if p then p.score else nil
	end
	state.result = result
	state.phase = "RoundEnd"
	state.endsAt = now() + Constants.ROUND_END_SECONDS
	-- Everyone who fought is queued for the next round automatically; they can leave the queue in the lobby.
	local t = now()
	for id in match.participants do
		local player = Players:GetPlayerByUserId(id)
		if player and not queued[player] then
			queued[player] = t
		end
	end
	devLog("round finished:", result.kind, result.reason, result.name or result.team or "")
	for _, handler in roundFinishedHandlers do
		task.spawn(handler, match, winner)
	end
	broadcast()
end

local function startRound()
	-- Uniform random mode and map every round; back-to-back repeats are allowed (approved). Team battle needs
	-- TEAM_MODE_MIN_PLAYERS queued.
	local mode = pickMode(#queuedPlayers())
	local maps = MapRegistry.enabled()
	local mapDef = if ServerMode.isTraining then MapRegistry.get(Constants.TRAINING_MAP) :: any else maps[math.random(1, #maps)]
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
	for _, handler in roundStartedHandlers do
		task.spawn(handler, match)
	end
end

local function intermissionSeconds(): number
	return if ServerMode.isTraining then Constants.TRAINING_INTERMISSION_SECONDS else Constants.INTERMISSION_SECONDS
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
	-- Always-on rounds (owner, 2026-09-30): straight into the next break, whoever is around.
	state.phase = "Intermission"
	state.endsAt = now() + intermissionSeconds()
	table.clear(pendingRespawn)
	table.clear(pendingBotRespawn)
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
		-- Only when the server has just started: the first break begins at once.
		state.phase = "Intermission"
		state.endsAt = t + intermissionSeconds()
		broadcast()
	elseif phase == "Intermission" then
		if t >= state.endsAt then
			startRound() -- with whoever pressed FIGHT, or nobody: the arena runs either way
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
		-- Always-on rounds (owner, 2026-09-30): a round runs its full time however few fighters are in it (anyone
		-- can drop in); it never ends early for lack of fighters.
		if t - lastPurge >= Constants.CODE_PURGE_SECONDS then
			lastPurge = t
			match:purge(t)
		end
		alertTimeLeft(match, t)
		if t >= state.endsAt then
			if match:count() == 0 then
				RoundManager.finish(match:endAsDraw("no_fighters")) -- nobody joined (or everyone left): no sudden death
			elseif match.suddenDeath then
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

-- Queue requests re-broadcast the round state to everyone, so one player can't ask more than every
-- QUEUE_MIN_INTERVAL seconds (Phase 4 security review).
local lastQueueRequest: { [Player]: number } = {}
local function queueRateLimited(player: Player): boolean
	local t = os.clock()
	local last = lastQueueRequest[player]
	if last and t - last < Constants.QUEUE_MIN_INTERVAL then
		return true
	end
	lastQueueRequest[player] = t
	return false
end

function RoundManager.requestFight(player: Player)
	if queueRateLimited(player) then
		return { status = "rate_limited" }
	end
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
	if queueRateLimited(player) then
		return { status = "rate_limited" }
	end
	if not queued[player] then
		return { status = "not_queued" }
	end
	queued[player] = nil
	broadcast()
	return { status = "left_queue" }
end

-- BACK TO LOBBY (owner, 2026-09-30: "i need to be able to go back to the lobby when i am in an arena match", then
-- "only when they are dead"): an eliminated player waiting to respawn leaves the running round exactly as if
-- they'd left the game (their numbers retire, their clones pop; in sudden death a sole leader left behind wins),
-- and stands in the lobby, out of the queue, instead of respawning. FIGHT brings them back any time. A living
-- fighter can't leave.
function RoundManager.leaveMatch(player: Player)
	if ServerMode.isTraining then
		return { status = "training" } -- the dojo has no lobby: LEAVE DOJO goes back to one
	end
	if queueRateLimited(player) then
		return { status = "rate_limited" }
	end
	local match = state.match
	local p = match and state.phase == "InRound" and not match.ended and match.participants[player.UserId]
	if not p then
		return { status = "not_in_match" }
	end
	if p.alive then
		return { status = "alive" } -- only once eliminated, while waiting to respawn
	end
	queued[player] = nil
	pendingRespawn[player] = nil
	local winner = match:removeParticipant(player.UserId, now())
	NumberAssignmentService.endLife(player.UserId)
	devLog(string.format("%s went back to the lobby", player.Name))
	Remotes.LifeState:FireClient(player, { alive = true, inMatch = false })
	task.spawn(PlayerLifeService.spawnAt, player, MapService.getLobbySpawn())
	if winner and state.match == match then
		RoundManager.finish(winner)
	end
	broadcast()
	return { status = "left" }
end

function RoundManager.Init()
	PlayerLifeService.onDied = onDied
	Remotes.RequestFight.OnServerInvoke = RoundManager.requestFight
	Remotes.LeaveQueue.OnServerInvoke = RoundManager.leaveQueue
	Remotes.LeaveMatch.OnServerInvoke = RoundManager.leaveMatch
	Remotes.GetRoundState.OnServerInvoke = function(player: Player)
		if lastState and not RateLimiter.allow(stateRequests, player, os.clock()) then
			return lastState
		end
		return buildState(false)
	end
	Players.PlayerRemoving:Connect(function(player)
		queued[player] = nil
		pendingRespawn[player] = nil
		lastQueueRequest[player] = nil
		RateLimiter.forget(stateRequests, player)
		local match = state.match
		if match and match.participants[player.UserId] then
			-- In sudden death, a tied fighter leaving can leave a sole leader: they win now.
			local winner = match:removeParticipant(player.UserId, now())
			if winner and state.phase == "InRound" and state.match == match then
				RoundManager.finish(winner)
			end
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
