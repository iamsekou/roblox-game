-- The clash duel (owner request 2026-09-29). Every clash (three M1 trades in a row, or the same attack started at
-- each other; triggers in AbilityService) becomes a duel:
--   1. Lift: both fighters rise CLASH_FLOAT_HEIGHT into the air, face to face, inside a force field.
--   2. Slow punch: one slow blow each, until the fists meet (a shockwave).
--   3. Barrage: the fists keep flying while single digits pop up for each fighter, one at a time; type each one
--      before its window closes. Windows shrink. The first mistake (wrong digit or too slow) loses
--      (rules in Lib/DuelRules).
--   4. The winner's final punch eliminates the loser (credited like a code elimination) and blows everything
--      nearby back. Nobody slipping within CLASH_DUEL_MAX_SECONDS is a draw: both thrown apart, nobody dies.
-- While dueling, both are out of reach of codes (MatchCore.setDueling), abilities and punches, and can't use them.
-- Only the two fighters get the cutscene camera and the digits (AbilityEffect "clash" + ClashDigit); everyone
-- else sees the fight from their own camera (AbilityFX "clash_duel" / "clash_tick" / "clash_duel_end").
-- The server alone judges every digit; a client only sends (step, digit).
--
-- Studio-only test switch (Constants.DEV_DUEL_ATTRIBUTE): a duel against a bot opponent, since a duel needs two
-- fighters and Studio's test automation drives one player.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ClashRules = require(script.Parent.Parent.Lib.ClashRules)
local DuelRules = require(script.Parent.Parent.Lib.DuelRules)
local RoundManager = require(script.Parent.RoundManager)
local EliminationService = require(script.Parent.EliminationService)
local MovementGuard = require(script.Parent.MovementGuard)

local ClashDuelService = {}

export type Fighter = {
	id: number, -- user id (or a bot's id)
	player: Player?,
	model: Model,
	lifeId: number?, -- the life the duel started in (players in a match)
	bot: { failAt: number? }?, -- Studio test bot: slips on digit `failAt` (nil = never)
}

type Duel = {
	a: Fighter,
	b: Fighter,
	match: any,
	startAt: number,
	slowAt: number,
	barrageAt: number,
	limitAt: number,
	midpoint: Vector3,
	axis: Vector3, -- from a toward b
	state: DuelRules.State?,
	over: boolean,
	onEnd: () -> (),
	character: string,
	slot: string,
}

local PARAMS: DuelRules.Params = {
	firstWindow = Constants.CLASH_DUEL_FIRST_WINDOW,
	decay = Constants.CLASH_DUEL_WINDOW_DECAY,
	minWindow = Constants.CLASH_DUEL_MIN_WINDOW,
	grace = Constants.CLASH_DUEL_GRACE,
}
local TICK = 0.05
local BOT_ID_BASE = -1500000000 -- far below user ids (Studio test players are -1, -2, ...) and clone ids
local UP = Vector3.yAxis

local duels: { [number]: Duel } = {} -- fighter id -> their duel
local nextBot = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- A shove, heard by the movement check first (like every game-applied movement).
local function knockback(f: Fighter, velocity: Vector3)
	if f.player then
		local payload = { kind = "knockback", velocity = velocity }
		MovementGuard.expect(f.player, payload)
		Remotes.AbilityEffect:FireClient(f.player, payload)
	else
		local root = rootOf(f.model)
		if root then
			root.AssemblyLinearVelocity = velocity
		end
	end
end

-- Still in the fight: the same character and life, in the same match (bots: still in the world).
local function valid(duel: Duel, f: Fighter): boolean
	if not f.model.Parent or not rootOf(f.model) then
		return false
	end
	if not f.player then
		return true
	end
	if not f.player.Parent or f.player.Character ~= f.model then
		return false
	end
	if duel.match then
		local p = duel.match.participants[f.id]
		return RoundManager.getMatch() == duel.match and not duel.match.ended and p ~= nil and p.alive and p.lifeId == f.lifeId
	end
	return true
end

local function setFloating(f: Fighter, on: boolean)
	local root = rootOf(f.model)
	if root then
		root.Anchored = on
		root.AssemblyLinearVelocity = Vector3.zero
	end
	if f.player then
		MovementGuard.reset(f.player) -- a server-placed position, not a cheat
	end
end

local function event(duel: Duel, kind: string, extra: { [string]: any }?): { [string]: any }
	local payload = {
		kind = kind,
		a = duel.a.id,
		b = duel.b.id,
		aModel = duel.a.model, -- lets clients find a bot (tests); players are also found by id
		bModel = duel.b.model,
		midpoint = duel.midpoint,
	}
	for key, value in extra or {} do
		payload[key] = value
	end
	return payload
end

local function sendDigit(duel: Duel, f: Fighter)
	local state = duel.state
	local entry = state and state.fighters[f.id]
	if f.player and entry and entry.failedAt == nil then
		Remotes.ClashDigit:FireClient(f.player, { step = entry.step, digit = entry.digit, deadline = entry.deadline })
	end
end

local function fighterOf(duel: Duel, id: number?): Fighter?
	if id == duel.a.id then
		return duel.a
	elseif id == duel.b.id then
		return duel.b
	end
	return nil
end

-- Ends the duel: nobody is dueling any more, both drop out of the air, the trigger hears it's over.
local function finish(duel: Duel)
	for _, f in { duel.a, duel.b } do
		if duels[f.id] == duel then
			duels[f.id] = nil
		end
		if f.player and duel.match then
			duel.match:setDueling(f.id, false)
		end
		if f.model.Parent then
			setFloating(f, false)
		end
		if f.player and f.player.Parent then
			Remotes.AbilityEffect:FireClient(f.player, { kind = "clash_end" })
		end
	end
	local ok, err = pcall(duel.onEnd)
	if not ok then
		warn("[NAU] clash end hook failed: " .. tostring(err))
	end
end

-- Someone left, died another way, or the round ended: no winner, nobody eliminated.
local function abort(duel: Duel)
	if duel.over then
		return
	end
	duel.over = true
	Remotes.AbilityFX:FireAllClients(event(duel, "clash_duel_end", { aborted = true }))
	finish(duel)
	if RunService:IsStudio() then
		print("[NAU] clash duel aborted")
	end
end

local function resolve(duel: Duel, result: DuelRules.Result)
	if duel.over then
		return
	end
	duel.over = true
	local winner, loser = fighterOf(duel, result.winner), fighterOf(duel, result.loser)
	for _, f in { duel.a, duel.b } do
		if f.player and f.player.Parent then
			local outcome = if result.draw then "draw" elseif f == winner then "win" else "lose"
			Remotes.ClashDigit:FireClient(f.player, { result = outcome })
		end
	end
	if RunService:IsStudio() then
		local state = duel.state
		print(string.format("[NAU] clash duel over: %s (typed %d / %d)",
			if result.draw then "draw" else string.format("%s won", tostring(winner and winner.model.Name)),
			state and state.fighters[duel.a.id].typed or 0, state and state.fighters[duel.b.id].typed or 0))
	end

	if result.draw or not winner or not loser then
		Remotes.AbilityFX:FireAllClients(event(duel, "clash_duel_end", { draw = true }))
		finish(duel)
		knockback(duel.a, -duel.axis * Constants.CLASH_KNOCKBACK + UP * Constants.CLASH_LAUNCH)
		knockback(duel.b, duel.axis * Constants.CLASH_KNOCKBACK + UP * Constants.CLASH_LAUNCH)
		return
	end

	-- The final punch: winds up, lands, and blows everything back.
	local finalAt = now() + Constants.CLASH_FINAL_WINDUP
	Remotes.AbilityFX:FireAllClients(event(duel, "clash_duel_end", {
		winner = winner.id,
		loser = loser.id,
		winnerModel = winner.model,
		loserModel = loser.model,
		finalAt = finalAt,
		radius = Constants.CLASH_BLAST_RADIUS,
	}))
	task.wait(Constants.CLASH_FINAL_WINDUP)
	local winnerRoot, loserRoot = rootOf(winner.model), rootOf(loser.model)
	local away = if winnerRoot and loserRoot then Vector3.new(loserRoot.Position.X - winnerRoot.Position.X, 0, loserRoot.Position.Z - winnerRoot.Position.Z) else Vector3.zero
	away = if away.Magnitude > 0.05 then away.Unit else (if loser == duel.b then duel.axis else -duel.axis)
	finish(duel)
	knockback(loser, away * Constants.CLASH_LOSER_LAUNCH + UP * 45)
	if loser.player then
		EliminationService.clashElimination(winner.player, loser.id)
	else
		task.delay(1.5, function()
			if loser.model.Parent then
				loser.model:Destroy()
			end
		end)
	end
	-- Everyone else nearby is blown back, harder the closer they were.
	for _, player in Players:GetPlayers() do
		if player ~= winner.player and player ~= loser.player then
			local root = rootOf(player.Character)
			local offset = if root then root.Position - duel.midpoint else nil
			if offset and offset.Magnitude <= Constants.CLASH_BLAST_RADIUS then
				local flat = Vector3.new(offset.X, 0, offset.Z)
				local dir = if flat.Magnitude > 0.05 then flat.Unit else away
				local strength = Constants.CLASH_BLAST_SPEED * (1 - 0.6 * offset.Magnitude / Constants.CLASH_BLAST_RADIUS)
				knockback({ id = player.UserId, player = player, model = player.Character :: Model }, dir * strength + UP * Constants.CLASH_BLAST_LIFT)
			end
		end
	end
end

-- Judges the duel now (after an answer, and every tick).
local function check(duel: Duel)
	if duel.over or not duel.state then
		return
	end
	local result = DuelRules.result(duel.state, now())
	if result then
		task.spawn(resolve, duel, result)
	elseif now() >= duel.limitAt then
		task.spawn(resolve, duel, { winner = nil, loser = nil, draw = true })
	end
end

local function onInput(duel: Duel, f: Fighter, step: any, digit: any)
	if duel.over or not duel.state then
		return
	end
	local status = DuelRules.input(duel.state, f.id, step, digit, now())
	if RunService:IsStudio() and f.player then
		print(string.format("[NAU] clash input from %s: step %s digit %s -> %s", f.player.Name, tostring(step), tostring(digit), status))
	end
	if status == "ok" then
		sendDigit(duel, f)
		local entry = duel.state.fighters[f.id]
		Remotes.AbilityFX:FireAllClients(event(duel, "clash_tick", { who = f.id, typed = entry.typed }))
	end
	if status == "ok" or status == "wrong" then
		check(duel)
	end
end

-- Studio bot: answers each digit after a human-like pause, slipping on digit `failAt`.
local function runBot(duel: Duel, f: Fighter)
	local rng = Random.new()
	while not duel.over and duel.state do
		local entry = duel.state.fighters[f.id]
		if entry.failedAt then
			return
		end
		local window = entry.deadline - now()
		task.wait(math.clamp(rng:NextNumber(0.3, 0.55), 0.05, math.max(0.05, window * 0.6)))
		if duel.over then
			return
		end
		local slip = f.bot and f.bot.failAt ~= nil and entry.step >= (f.bot.failAt :: number)
		onInput(duel, f, entry.step, if slip then (entry.digit + 1) % 10 else entry.digit)
	end
end

local function run(duel: Duel)
	-- Lift and slow punch: nothing to judge yet, just keep checking both are still here.
	while now() < duel.barrageAt do
		if not valid(duel, duel.a) or not valid(duel, duel.b) then
			abort(duel)
			return
		end
		task.wait(TICK)
	end
	duel.state = DuelRules.new({ duel.a.id, duel.b.id }, now(), PARAMS, DuelRules.randomDigits(Random.new()))
	for _, f in { duel.a, duel.b } do
		sendDigit(duel, f)
		if f.bot then
			task.spawn(runBot, duel, f)
		end
	end
	while not duel.over do
		task.wait(TICK)
		if duel.over then
			return
		end
		if not valid(duel, duel.a) or not valid(duel, duel.b) then
			abort(duel)
			return
		end
		check(duel)
	end
end

-- Starts a duel between two fighters. `onEnd` runs once it's over, whatever the outcome. Returns false (nothing
-- changed) if either is already dueling or can't be placed.
function ClashDuelService.start(a: Fighter, b: Fighter, info: { character: string, slot: string, onEnd: () -> () }): boolean
	if duels[a.id] or duels[b.id] or a.id == b.id then
		return false
	end
	local rootA, rootB = rootOf(a.model), rootOf(b.model)
	if not rootA or not rootB then
		return false
	end
	local match = RoundManager.getMatch()
	for _, f in { a, b } do
		if f.player and match then
			local p = match.participants[f.id]
			f.lifeId = p and p.lifeId
		end
	end
	local standA, standB, axis = ClashRules.stances(rootA.Position, rootB.Position, Constants.CLASH_DISTANCE)
	local lift = UP * Constants.CLASH_FLOAT_HEIGHT
	local posA, posB = standA + lift, standB + lift
	local t0 = now()
	local slowAt = t0 + Constants.CLASH_LIFT_SECONDS
	local barrageAt = slowAt + Constants.CLASH_SLOW_PUNCH_SECONDS
	local duel: Duel = {
		a = a,
		b = b,
		match = match,
		startAt = t0,
		slowAt = slowAt,
		barrageAt = barrageAt,
		limitAt = barrageAt + Constants.CLASH_DUEL_MAX_SECONDS,
		midpoint = (posA + posB) / 2,
		axis = axis,
		state = nil,
		over = false,
		onEnd = info.onEnd,
		character = info.character,
		slot = info.slot,
	}
	duels[a.id] = duel
	duels[b.id] = duel
	for _, pair in { { a, posA, posB }, { b, posB, posA } } do
		local f, at, other = pair[1], pair[2], pair[3]
		if f.player and match then
			match:setDueling(f.id, true)
		end
		f.model:PivotTo(CFrame.lookAt(at, Vector3.new(other.X, at.Y, other.Z)))
		setFloating(f, true)
	end
	local untilTime = duel.limitAt + Constants.CLASH_FINAL_WINDUP + 2
	for _, pair in { { a, b, posB }, { b, a, posA } } do
		local f, other, face = pair[1], pair[2], pair[3]
		if f.player then
			Remotes.AbilityEffect:FireClient(f.player, {
				kind = "clash",
				duel = true,
				cinematic = true,
				untilTime = untilTime,
				face = face,
				partner = other.id,
				partnerModel = other.model,
				startAt = t0,
				slowAt = slowAt,
				barrageAt = barrageAt,
			})
		end
	end
	Remotes.AbilityFX:FireAllClients(event(duel, "clash_duel", {
		character = info.character,
		slot = info.slot,
		startAt = t0,
		slowAt = slowAt,
		barrageAt = barrageAt,
		radius = Constants.CLASH_FORCEFIELD_RADIUS,
	}))
	if RunService:IsStudio() then
		print(string.format("[NAU] clash duel: %s vs %s (%s.%s)", a.model.Name, b.model.Name, info.character, info.slot))
	end
	task.spawn(run, duel)
	return true
end

function ClashDuelService.isDueling(id: number): boolean
	return duels[id] ~= nil
end

-- Studio test bots: copies of `player`'s avatar standing at `cframe`.
local function makeBot(player: Player, cframe: CFrame, name: string, failAt: number?): Fighter?
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local ok, desc = false, nil
	if humanoid then
		ok, desc = pcall(humanoid.GetAppliedDescription, humanoid)
	end
	local made, model = false, nil
	if ok then
		made, model = pcall(Players.CreateHumanoidModelFromDescription, Players, desc, Enum.HumanoidRigType.R15)
	end
	if not made or not model then
		warn("[NAU] duel test: couldn't build a bot")
		return nil
	end
	nextBot += 1
	model.Name = name
	local botHumanoid = model:FindFirstChildOfClass("Humanoid")
	if botHumanoid then
		botHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	model:PivotTo(cframe)
	model.Parent = workspace
	local botRoot = rootOf(model)
	if botRoot then
		botRoot:SetNetworkOwner(nil)
	end
	return { id = BOT_ID_BASE - nextBot, model = model, bot = { failAt = failAt } }
end

local function removeLater(models: { Model })
	task.delay(3, function()
		for _, model in models do
			if model.Parent then
				model:Destroy()
			end
		end
	end)
end

-- Studio test (see Constants.DEV_DUEL_ATTRIBUTE): a duel against a bot in front of `player`, or with "watch",
-- two bots dueling in front of them (the spectators' view).
local function devDuel(player: Player, spec: any)
	local root = rootOf(player.Character)
	if not root then
		warn("[NAU] duel test: no character")
		return
	end
	local info = { character = "Melee", slot = "m1", onEnd = function() end }
	if spec == "watch" then
		local center = root.CFrame * CFrame.new(0, 0, -16)
		local a = makeBot(player, center * CFrame.new(-4, 0, 0) * CFrame.Angles(0, math.rad(-90), 0), "DuelBotA", nil)
		local b = makeBot(player, center * CFrame.new(4, 0, 0) * CFrame.Angles(0, math.rad(90), 0), "DuelBotB", 6)
		if not a or not b then
			return
		end
		info.onEnd = function()
			removeLater({ a.model, b.model })
		end
		if not ClashDuelService.start(a, b, info) then
			a.model:Destroy()
			b.model:Destroy()
		end
		return
	end
	local failAt = if spec == "lose" then 4 elseif type(spec) == "number" then spec else nil
	local bot = makeBot(player, root.CFrame * CFrame.new(0, 0, -6) * CFrame.Angles(0, math.pi, 0), "DuelBot", failAt)
	if not bot then
		return
	end
	info.onEnd = function()
		removeLater({ bot.model })
	end
	local me: Fighter = { id = player.UserId, player = player, model = player.Character :: Model }
	if not ClashDuelService.start(me, bot, info) then
		bot.model:Destroy()
		warn("[NAU] duel test: couldn't start (already dueling?)")
	end
end

function ClashDuelService.Init()
	Remotes.ClashInput.OnServerEvent:Connect(function(player: Player, step: any, digit: any)
		local duel = duels[player.UserId]
		local f = duel and fighterOf(duel, player.UserId)
		if duel and f and f.player == player then
			onInput(duel, f, step, digit)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local duel = duels[player.UserId]
		if duel then
			abort(duel)
		end
	end)
	if RunService:IsStudio() then
		local function watch(player: Player)
			player:GetAttributeChangedSignal(Constants.DEV_DUEL_ATTRIBUTE):Connect(function()
				local spec = player:GetAttribute(Constants.DEV_DUEL_ATTRIBUTE)
				if spec == nil then
					return
				end
				player:SetAttribute(Constants.DEV_DUEL_ATTRIBUTE, nil)
				task.spawn(devDuel, player, spec)
			end)
		end
		Players.PlayerAdded:Connect(watch)
		for _, player in Players:GetPlayers() do
			watch(player)
		end
	end
end

return ClashDuelService
