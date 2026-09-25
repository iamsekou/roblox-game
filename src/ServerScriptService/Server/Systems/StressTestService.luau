-- Studio-only 12-player stress test (Phase 4). During a round, set NAU_DevStressBots = N (1-11) on
-- ServerScriptService and N bot fighters wearing the first player's avatar run around the arena at fighter
-- speed with the avatar's own run animation; 0 removes them. Bots aren't players (no codes, plates or
-- abilities): they load the server and the network like moving fighters, and the client's sprint effects
-- dress them like fighters (animations/Controllers/SprintFX), so frame cost is comparable. Does nothing live.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local MapService = require(script.Parent.MapService)

local StressTestService = {}

local MAX_BOTS = Constants.MAX_PLAYERS - 1
local RETARGET_SECONDS = { 1.5, 3.5 } -- a bot picks a new spot this often
local JUMP_CHANCE = 0.15 -- per retarget

local folder: Folder? = nil
local generation = 0

local function clear()
	generation += 1
	if folder then
		folder:Destroy()
		folder = nil
	end
end

local function description(): HumanoidDescription?
	for _, player in Players:GetPlayers() do
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local ok, desc = pcall(humanoid.GetAppliedDescription, humanoid)
			if ok then
				return desc
			end
		end
	end
	return nil
end

-- The run animation from the rig's own Animate script (a real id that ships with the avatar).
local function runAnimation(bot: Model): Animation?
	local animate = bot:FindFirstChild("Animate")
	local run = animate and animate:FindFirstChild("run")
	local anim = run and run:FindFirstChildWhichIsA("Animation")
	return anim
end

local function spawnBot(desc: HumanoidDescription, index: number, myGeneration: number)
	local ok, bot = pcall(Players.CreateHumanoidModelFromDescription, Players, desc, Enum.HumanoidRigType.R15)
	if not ok or not bot or myGeneration ~= generation or not folder then
		return
	end
	bot.Name = "Bot" .. index
	local humanoid = bot:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = bot:FindFirstChild("HumanoidRootPart") :: BasePart
	humanoid.WalkSpeed = Constants.MOVE_SPEED
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	local spot = MapService.findArenaSpawn({})
	bot:PivotTo(spot + Vector3.new(0, 3, 0))
	bot.Parent = folder
	root:SetNetworkOwner(nil)
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local anim = runAnimation(bot)
	if anim then
		local track = animator:LoadAnimation(anim)
		track.Looped = true
		track:Play()
	end
	local rng = Random.new(index * 7919)
	task.spawn(function()
		while myGeneration == generation and bot.Parent and humanoid.Health > 0 do
			local okSpot, target = pcall(MapService.findArenaSpawn, {})
			if okSpot then
				humanoid:MoveTo(target.Position)
			end
			if rng:NextNumber() < JUMP_CHANCE then
				humanoid.Jump = true
			end
			task.wait(rng:NextNumber(RETARGET_SECONDS[1], RETARGET_SECONDS[2]))
		end
	end)
end

local function apply()
	clear()
	local count = ServerScriptService:GetAttribute(Constants.DEV_STRESS_BOTS_ATTRIBUTE)
	if typeof(count) ~= "number" or count < 1 then
		print("[NAU] stress test: bots removed")
		return
	end
	count = math.clamp(math.floor(count), 1, MAX_BOTS)
	local desc = description()
	local okArena = pcall(MapService.findArenaSpawn, {})
	if not desc or not okArena then
		warn("[NAU] stress test needs a player in the game and a round running (the arena loaded)")
		return
	end
	local myGeneration = generation
	local newFolder = Instance.new("Folder")
	newFolder.Name = "NAU_StressBots"
	newFolder.Parent = workspace
	folder = newFolder
	for i = 1, count do
		task.spawn(spawnBot, desc, i, myGeneration)
	end
	print(string.format("[NAU] stress test: %d bots running", count))
end

function StressTestService.Init()
	if not RunService:IsStudio() then
		return
	end
	ServerScriptService:GetAttributeChangedSignal(Constants.DEV_STRESS_BOTS_ATTRIBUTE):Connect(apply)
end

return StressTestService
