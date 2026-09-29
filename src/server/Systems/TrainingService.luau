-- Training Grounds (owner, 2026-09-29): practise alone in the dojo against training dummies, with the real rules.
--
-- Public servers: EnterTraining reserves a private server of this same place and teleports the player there.
-- Training servers (ServerMode): LeaveTraining sends them back to a public server (the lobby) the same way. Either
-- way the player's profile is saved and released first, so the next server loads it at once.
--
-- On a training server the player waits in the dojo hall and fights on the training ground (MapService,
-- RoundManager: one endless Free-play round). This service owns the dummies:
--   * the training menu's setting (TrainingConfig): how many dummies, 0-11;
--   * their bodies: plain dojo students in gi colours with a headband in their fighter's aura colour, each shown
--     as a random roster character (aura + name chip, like any opponent);
--   * their behaviour (Lib/BotRules): stand on the training ground and turn to a new heading every few seconds,
--     so you have to step in front of one to read its number. They never read, type or punch. Type a dummy's
--     number to eliminate it; it respawns like anyone. Knockbacks from your abilities and punches move them.
-- Training pays XP at XP_TRAINING_MULTIPLIER and never credits or leaderboard kills (EliminationService).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local CharacterDefs = require(ReplicatedStorage.Shared.Modules.CharacterDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local BotRules = require(script.Parent.Parent.Lib.BotRules)
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)
local ServerMode = require(script.Parent.ServerMode)
local FighterRegistry = require(script.Parent.FighterRegistry)
local RoundManager = require(script.Parent.RoundManager)
local NumberAssignmentService = require(script.Parent.NumberAssignmentService)
local AbilityService = require(script.Parent.AbilityService)
local MeleeService = require(script.Parent.MeleeService)
local XpService = require(script.Parent.XpService)
local ProfileService = require(script.Parent.ProfileService)

local TrainingService = {}

local TURN_SPEED = 3 -- radians/second a dummy turns toward its new heading
local SKIN = { Color3.fromRGB(234, 196, 160), Color3.fromRGB(198, 150, 110), Color3.fromRGB(150, 104, 72), Color3.fromRGB(96, 64, 44) }
local GI = { Color3.fromRGB(236, 234, 226), Color3.fromRGB(34, 36, 44), Color3.fromRGB(40, 56, 96) }

type Dummy = {
	handle: any,
	model: Model?,
	root: BasePart?,
	humanoid: Humanoid?,
	idle: AnimationTrack?,
	heading: Vector3,
	turnAt: number,
	rng: Random,
}

local config = BotRules.defaultConfig(Constants.TRAINING_DEFAULT_BOTS)
local dummies: { [number]: Dummy } = {} -- dummy id -> dummy
local configRequests = RateLimiter.new(Constants.TRAINING_CONFIG_MIN_INTERVAL)
local teleportRequests = RateLimiter.new(Constants.TRAINING_TELEPORT_MIN_INTERVAL)

local function now(): number
	return workspace:GetServerTimeNow()
end

local function log(message: string)
	if RunService:IsStudio() then
		print("[NAU] training: " .. message)
	end
end

-- Teleports (lobby <-> training) ---------------------------------------------------------------------------

local function teleport(player: Player, options: TeleportOptions?): { status: string }
	ProfileService.releaseForTeleport(player)
	local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { player }, options)
	if not ok then
		warn("[NAU] training teleport failed: " .. tostring(err))
		ProfileService.reclaimAfterTeleport(player)
		return { status = "failed" }
	end
	return { status = "teleporting" }
end

local function handleEnter(player: Player)
	if ServerMode.isTraining then
		return { status = "already_training" }
	end
	if not RateLimiter.allow(teleportRequests, player, os.clock()) then
		return { status = "rate_limited" }
	end
	if RunService:IsStudio() then
		return { status = "studio" } -- teleports don't run in Studio: use the NAU_DevTraining switch
	end
	local match = RoundManager.getMatch()
	local p = match and match.participants[player.UserId]
	if p and p.alive then
		return { status = "in_round" }
	end
	local ok, code = pcall(TeleportService.ReserveServer, TeleportService, game.PlaceId)
	if not ok then
		warn("[NAU] couldn't reserve a training server: " .. tostring(code))
		return { status = "failed" }
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = code
	return teleport(player, options)
end

local function handleLeave(player: Player)
	if not ServerMode.isTraining then
		return { status = "not_training" }
	end
	if not RateLimiter.allow(teleportRequests, player, os.clock()) then
		return { status = "rate_limited" }
	end
	if RunService:IsStudio() then
		return { status = "studio" }
	end
	return teleport(player, nil) -- no access code: Roblox picks a public server (the lobby)
end

-- Dummy bodies --------------------------------------------------------------------------------------------

local function describe(dummy: Dummy): HumanoidDescription
	local rng = dummy.rng
	local desc = Instance.new("HumanoidDescription")
	local skin = SKIN[rng:NextInteger(1, #SKIN)]
	local gi = GI[rng:NextInteger(1, #GI)]
	desc.HeadColor = skin
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	desc.TorsoColor = gi
	desc.LeftLegColor = gi
	desc.RightLegColor = gi
	return desc
end

-- A headband in the fighter's aura colour (a red one for the dark aura, so it shows).
local function addHeadband(model: Model, fighter: string)
	local head = model:FindFirstChild("Head")
	local def = CharacterDefs.byId[fighter]
	if not head or not head:IsA("BasePart") or not def then
		return
	end
	local band = Instance.new("Part")
	band.Name = "Headband"
	band.Size = Vector3.new(head.Size.X + 0.08, 0.28, head.Size.Z + 0.08)
	band.Color = if def.auraDark then Color3.fromRGB(200, 40, 40) else def.aura :: Color3
	band.Material = Enum.Material.Fabric
	band.CanCollide = false
	band.CanQuery = false
	band.CanTouch = false
	band.Massless = true
	band.CFrame = head.CFrame * CFrame.new(0, head.Size.Y * 0.18, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = band
	weld.Parent = band
	band.Parent = model
end

-- The avatar's own idle animation (a real id that ships inside the rig's Animate script).
local function loadIdle(model: Model, humanoid: Humanoid): AnimationTrack?
	local animate = model:FindFirstChild("Animate")
	local holder = animate and animate:FindFirstChild("idle")
	local animation = holder and holder:FindFirstChildWhichIsA("Animation")
	local track = nil
	if animation then
		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
		local ok, loaded = pcall(animator.LoadAnimation, animator, animation)
		if ok and loaded then
			loaded.Looped = true
			loaded:Play()
			track = loaded
		end
	end
	if animate then
		animate:Destroy() -- a LocalScript: it never runs on an NPC
	end
	return track
end

-- A fresh body for this dummy's new life (every life gets a new body, like a player's character: clients fade
-- an eliminated body out on their side, so a reused one would stay invisible).
local function buildBody(dummy: Dummy): boolean
	local handle = dummy.handle
	local ok, model = pcall(Players.CreateHumanoidModelFromDescription, Players, describe(dummy), Enum.HumanoidRigType.R15)
	if not ok or not model then
		warn("[NAU] training: couldn't build a dummy body: " .. tostring(model))
		return false
	end
	if dummy.model then
		dummy.model:Destroy()
	end
	model.Name = handle.DisplayName
	model:SetAttribute("BotId", handle.UserId)
	model:SetAttribute(Constants.FIGHTER_ATTRIBUTE, handle.fighter)
	model:SetAttribute(Constants.PRESTIGE_ATTRIBUTE, 0)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- the arena shows plates, not names
	humanoid.BreakJointsOnDeath = false
	humanoid.AutoRotate = false -- it turns on its own schedule
	addHeadband(model, handle.fighter)
	model.Parent = FighterRegistry.folder()
	root:SetNetworkOwner(nil) -- the server moves it
	dummy.idle = loadIdle(model, humanoid)
	humanoid.Died:Connect(function()
		if dummy.humanoid == humanoid then
			RoundManager.botDied(handle.UserId) -- fell off the world: no credit to anyone
		end
	end)
	dummy.model, dummy.root, dummy.humanoid = model, root, humanoid
	handle.Character = model
	return true
end

-- RoundManager's hook: a fresh body at `cframe` for a new life.
local function spawnBody(id: number, cframe: CFrame): boolean
	local dummy = dummies[id]
	if not dummy or not buildBody(dummy) then
		return false
	end
	(dummy.model :: Model):PivotTo(cframe + Vector3.new(0, 3, 0))
	dummy.heading, dummy.turnAt = BotRules.nextTurn(dummy.rng, now())
	return true
end

-- RoundManager's hook: this dummy's life ended (every client plays the elimination on its body). The body goes
-- once that has played; the respawn builds a new one.
local function onLifeLost(id: number)
	local dummy = dummies[id]
	local body = dummy and dummy.model
	if not dummy or not body then
		return
	end
	task.wait(1.6)
	if dummy.model == body then
		dummy.model, dummy.root, dummy.humanoid, dummy.idle = nil, nil, nil, nil
		dummy.handle.Character = nil
		body:Destroy()
	end
end

-- Effects of abilities and punches on a dummy (what a player's client does for its own character): knockbacks
-- move it. Locks, blinds and hidden plates are enforced by the rules and the plate gate themselves.
local function onEffect(dummy: Dummy, payload: { [string]: any })
	local root, humanoid = dummy.root, dummy.humanoid
	if payload.kind == "knockback" and typeof(payload.velocity) == "Vector3" and root and humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		root.AssemblyLinearVelocity = payload.velocity
	end
end

-- Dummies in and out --------------------------------------------------------------------------------------

local function removeDummy(id: number)
	local dummy = dummies[id]
	dummies[id] = nil
	RoundManager.removeBot(id)
	if dummy then
		AbilityService.forget(dummy.handle)
		if dummy.model then
			dummy.model:Destroy()
		end
	end
	MeleeService.forget(id)
	NumberAssignmentService.forget(id)
	FighterRegistry.unregisterBot(id)
end

local function addDummy(index: number)
	local id = FighterRegistry.BOT_ID_BASE - index
	if dummies[id] then
		return
	end
	local rng = Random.new()
	local fighters = CharacterDefs.list
	local dummy: Dummy
	local handle = {
		UserId = id,
		Name = "Dummy" .. index,
		DisplayName = BotRules.NAMES[(index - 1) % #BotRules.NAMES + 1] .. " (dummy)",
		Character = nil,
		Parent = workspace,
		IsBot = true,
		fighter = fighters[rng:NextInteger(1, #fighters)].id,
		onEffect = function(payload)
			onEffect(dummy, payload)
		end,
	}
	dummy = { handle = handle, heading = Vector3.zAxis, turnAt = 0, rng = rng }
	dummies[id] = dummy
	FighterRegistry.registerBot(handle :: any)
	if not RoundManager.addBot(id) then
		removeDummy(id)
	end
end

-- Brings the dummies in the round to `config.bots`.
local function syncDummies()
	if not RoundManager.getMatch() then
		return
	end
	for index = 1, Constants.TRAINING_MAX_BOTS do
		local id = FighterRegistry.BOT_ID_BASE - index
		if index <= config.bots then
			addDummy(index)
		elseif dummies[id] then
			removeDummy(id)
		end
	end
end

local function removeAllDummies()
	for id in dummies do
		removeDummy(id)
	end
end

-- Every tick: each dummy turns smoothly toward its heading and picks a new one every few seconds.
local function tick(dt: number)
	local t = now()
	for _, dummy in dummies do
		local root, humanoid = dummy.root, dummy.humanoid
		if root and humanoid and humanoid.Health > 0 and not AbilityService.isClashing(dummy.handle) then
			if t >= dummy.turnAt then
				dummy.heading, dummy.turnAt = BotRules.nextTurn(dummy.rng, t)
			end
			local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			if look.Magnitude > 0.1 then
				local current = math.atan2(-look.X, -look.Z)
				local target = math.atan2(-dummy.heading.X, -dummy.heading.Z)
				local delta = (target - current + math.pi) % (2 * math.pi) - math.pi
				local step = math.clamp(delta, -TURN_SPEED * dt, TURN_SPEED * dt)
				if math.abs(step) > 1e-3 then
					root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, current + step, 0)
				end
			end
		end
	end
end

-- The training menu ---------------------------------------------------------------------------------------

local function info()
	return { bots = config.bots }
end

local function handleConfig(player: Player, changes: any)
	if not ServerMode.isTraining then
		return { status = "not_training", config = info() }
	end
	if not RateLimiter.allow(configRequests, player, os.clock()) then
		return { status = "rate_limited", config = info() }
	end
	local updated, ok = BotRules.applyConfig(config, changes, Constants.TRAINING_MAX_BOTS)
	if not ok then
		return { status = "malformed", config = info() }
	end
	config = updated
	log(string.format("%s set %d dummies", player.Name, config.bots))
	syncDummies()
	RoundManager.refresh()
	return { status = "ok", config = info() }
end

function TrainingService.Init()
	Remotes.EnterTraining.OnServerInvoke = handleEnter
	Remotes.LeaveTraining.OnServerInvoke = handleLeave
	Remotes.TrainingConfig.OnServerInvoke = handleConfig
	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		warn(string.format("[NAU] teleport for %s failed: %s %s", player.Name, tostring(result), tostring(message)))
		task.spawn(ProfileService.reclaimAfterTeleport, player)
		Remotes.TrainingNotice:FireClient(player, { kind = "teleport_failed" })
	end)
	Players.PlayerRemoving:Connect(function(player)
		RateLimiter.forget(configRequests, player)
		RateLimiter.forget(teleportRequests, player)
	end)
	if not ServerMode.isTraining then
		return
	end

	log("this is a training server")
	XpService.setScale(Constants.XP_TRAINING_MULTIPLIER)
	RoundManager.setTrainingRules(function()
		return Constants.TRAINING_FREE_ROUND_SECONDS -- Free play: the round never runs out
	end, info)
	RoundManager.setBotHooks({ spawn = spawnBody, lifeLost = onLifeLost })
	RoundManager.onRoundStarted(syncDummies)
	RoundManager.onRoundFinished(function()
		task.delay(Constants.ROUND_END_SECONDS - 0.5, removeAllDummies) -- they stay for the results, then go
	end)
	-- Straight into training: queue every arrival (a round starts a few seconds later).
	local function arrive(player: Player)
		task.spawn(function()
			if not player.Character then
				player.CharacterAdded:Wait()
			end
			RoundManager.requestFight(player)
		end)
	end
	Players.PlayerAdded:Connect(arrive)
	for _, player in Players:GetPlayers() do
		arrive(player)
	end
end

function TrainingService.Start()
	if not ServerMode.isTraining then
		return
	end
	local last = os.clock()
	while true do
		task.wait(Constants.DUMMY_TICK_SECONDS)
		local t = os.clock()
		local ok, err = pcall(tick, t - last)
		last = t
		if not ok then
			warn("[NAU] dummy tick failed: " .. tostring(err))
		end
	end
end

return TrainingService
