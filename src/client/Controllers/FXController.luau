-- Glue between server events and the animator's effect modules in ReplicatedStorage.Animations.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Constants = require(Shared:WaitForChild("Modules"):WaitForChild("Constants"))
local AnimControllers = ReplicatedStorage:WaitForChild("Animations"):WaitForChild("Controllers")
local EliminationFX = require(AnimControllers:WaitForChild("EliminationFX"))
local SpawnFX = require(AnimControllers:WaitForChild("SpawnFX"))
local PortalFX = require(AnimControllers:WaitForChild("PortalFX"))
local RunFOV = require(AnimControllers:WaitForChild("RunFOV"))
local SprintFX = require(AnimControllers:WaitForChild("SprintFX"))
local LightingFX = require(AnimControllers:WaitForChild("LightingFX"))
local Crowd = require(AnimControllers:WaitForChild("Crowd"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local FXController = {}

local function characterOf(userId: number?, timeout: number): Model?
	local player = userId and Players:GetPlayerByUserId(userId)
	if not player then
		return nil
	end
	local deadline = os.clock() + timeout
	while true do
		local character = player.Character
		if character and character:FindFirstChild("HumanoidRootPart") then
			return character
		end
		if os.clock() >= deadline then
			return nil
		end
		task.wait(0.05)
	end
end

function FXController.Start()
	RunFOV.start({
		base = Constants.BASE_FOV,
		run = Constants.RUN_FOV,
		response = Constants.FOV_RESPONSE,
		minSpeed = Constants.RUN_FOV_MIN_SPEED,
	})
	SprintFX.start({
		minSpeed = Constants.RUN_FOV_MIN_SPEED,
		fullSpeed = Constants.SPRINT_FULL_SPEED,
		leanDegrees = Constants.SPRINT_LEAN_DEGREES,
		armsBackDegrees = Constants.SPRINT_ARMS_BACK_DEGREES,
		rollDegrees = Constants.SPRINT_CAMERA_ROLL_DEGREES,
		bob = Constants.SPRINT_CAMERA_BOB,
	})

	-- Lobby grade outside a match, the arena's own look inside one (dead-and-waiting counts as inside).
	local function lightingPreset(): string
		return if ClientState.life.inMatch then "Arena" else "Lobby"
	end
	LightingFX.start(lightingPreset())
	Crowd.start() -- builds the colosseum crowd whenever an arena with Crowd rows appears
	ClientState.Changed:Connect(function(kind)
		if kind == "life" then
			LightingFX.apply(lightingPreset())
		end
	end)

	Remotes.MatchFeed.OnClientEvent:Connect(function(event)
		if type(event) ~= "table" then
			return
		end
		if event.kind == "eliminated" then
			local character = characterOf(event.victim, 0)
			if character then
				local root = character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					Crowd.react(root.Position) -- the stands erupt, loudest nearest the kill
				end
				EliminationFX.play(character)
			end
		elseif event.kind == "spawned" then
			task.spawn(function()
				local character = characterOf(event.userId, 2)
				if character then
					SpawnFX.play(character, event.userId == Players.LocalPlayer.UserId)
				end
			end)
		end
	end)

	task.spawn(function()
		local world = workspace:WaitForChild("NAUWorld", 30)
		local lobby = world and world:WaitForChild("Lobby", 30)
		local portal = lobby and lobby:WaitForChild("FightPortal", 30)
		if portal then
			PortalFX.start(portal)
		end
	end)
end

return FXController
