-- Owns characters: manual spawning (lobby or arena), death detection, and the void check.
-- It never decides what a death *means*; RoundManager registers onDied and applies the rules.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local MapService = require(script.Parent.MapService)
local MovementGuard = require(script.Parent.MovementGuard)

local PlayerLifeService = {}

-- Set by RoundManager. Called once per death of a player's current character.
PlayerLifeService.onDied = nil :: ((player: Player) -> ())?

local VOID_Y = -40
local VOID_CHECK_INTERVAL = 0.5

local spawnTokens: { [Player]: number } = {}
local brokenReported: { [Player]: Model } = {} -- player -> a character that lost its root/Humanoid, already sent down

-- The template SpawnLocation hands out a 10-second ForceField. Nothing in NAU is damage-based,
-- and a bubble would wrongly suggest the player can't be eliminated.
local function removeSpawnForceFields(character: Model)
	for _, child in character:GetChildren() do
		if child:IsA("ForceField") then
			child:Destroy()
		end
	end
	local connection = character.ChildAdded:Connect(function(child)
		if child:IsA("ForceField") then
			task.defer(child.Destroy, child)
		end
	end)
	task.delay(2, function()
		connection:Disconnect()
	end)
end

-- Spawns (or respawns) the player's character at `cframe`. Yields while the character loads.
-- Returns the character, or nil if the player left or a newer spawn request replaced this one.
function PlayerLifeService.spawnAt(player: Player, cframe: CFrame, options: { arena: boolean? }?): Model?
	if not player.Parent then
		return nil
	end
	local token = (spawnTokens[player] or 0) + 1
	spawnTokens[player] = token

	pcall(function()
		player:RequestStreamAroundAsync(cframe.Position)
	end)
	if spawnTokens[player] ~= token or not player.Parent then
		return nil
	end

	player:LoadCharacter()
	local character = player.Character
	if not character or spawnTokens[player] ~= token then
		return nil
	end

	character:PivotTo(cframe + Vector3.new(0, 3, 0))
	MovementGuard.reset(player) -- a server teleport, not a cheat
	removeSpawnForceFields(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Constants.MOVE_SPEED
		humanoid.BreakJointsOnDeath = false -- eliminations fade the body out instead of breaking it apart
		-- In the arena the only overhead label is each observer's own number plate.
		humanoid.DisplayDistanceType = if options and options.arena
			then Enum.HumanoidDisplayDistanceType.None
			else Enum.HumanoidDisplayDistanceType.Viewer
	end
	return character
end

function PlayerLifeService.kill(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0
	end
end

local function watchCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	-- Once: a humanoid dies once, and the connection (holding this player and character) goes with it.
	humanoid.Died:Once(function()
		if player.Character == character and PlayerLifeService.onDied then
			PlayerLifeService.onDied(player)
		end
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)
	if player.Character then
		task.spawn(watchCharacter, player, player.Character)
	end
	PlayerLifeService.spawnAt(player, MapService.getLobbySpawn())
end

function PlayerLifeService.Init()
	Players.CharacterAutoLoads = false
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		spawnTokens[player] = nil
		brokenReported[player] = nil
	end)
end

-- Characters that lost their root part or their Humanoid (audit fix, 2026-09-28). A client can delete parts of
-- its own character and the deletion reaches the server: without a root nobody could read that fighter's number
-- or hit them, so they'd be unkillable while still eliminating others. Such a character dies through the normal
-- death path (no credit to anyone, same respawn rules). Reported once per character.
local function checkPlayer(player: Player)
	local character = player.Character
	if not character or not character.Parent or brokenReported[player] == character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return -- already dead: the Died path handles it
	end
	if not humanoid or not root or not root:IsA("BasePart") then
		brokenReported[player] = character
		if humanoid then
			humanoid.Health = 0 -- fires Died -> onDied
		elseif PlayerLifeService.onDied then
			PlayerLifeService.onDied(player) -- no Humanoid left to fire Died
		end
		return
	end
	-- Anyone who falls far below the map dies through the normal death path.
	if root.Position.Y < VOID_Y then
		humanoid.Health = 0
	end
end

function PlayerLifeService.Start()
	while true do
		task.wait(VOID_CHECK_INTERVAL)
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(checkPlayer, player)
			if not ok then
				warn("[NAU] life check failed: " .. tostring(err))
			end
		end
	end
end

return PlayerLifeService
