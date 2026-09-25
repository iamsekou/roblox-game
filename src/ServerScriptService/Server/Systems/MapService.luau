-- Builds the lobby once and the round's arena on demand, from the builders in ServerStorage.Assets.
-- Maps follow the map contract in docs/DESIGN.md (an unrotated PrimaryPart, a SpawnArea folder of
-- invisible boxes, optional buildTerrain/clearTerrain), so adding a map never touches this file or
-- the round system.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local MapRegistry = require(ReplicatedStorage.Shared.Modules.MapRegistry)

local Builders = ServerStorage:WaitForChild("Assets"):WaitForChild("Builders")

local MapService = {}

-- The place's template Baseplate covers the origin, so the game world is built well away from it.
local LOBBY_CFRAME = CFrame.new(0, 0, 3000)
-- y = 2 on purpose: terrain voxels are 4-stud cells centred on multiples of 4, so a terrain floor
-- filled up to y = 0 surfaces at y = 2. Placing the arena origin there puts the grass exactly at the
-- arena's floor level (see ProvingGrounds.buildTerrain).
local ARENA_CFRAME = CFrame.new(0, 2, 4400)

local worldFolder: Folder
local lobby: Model
local arena: Model? = nil
local arenaId: string? = nil
local arenaBuilder: any = nil

-- Small maps are sent to every client up front, so nobody spawns onto unstreamed ground.
local function makePersistent(model: Model)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
end

local function spawnParts(model: Model?): { BasePart }
	local folder = model and model:FindFirstChild("SpawnPoints")
	local parts = {}
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(parts, child)
			end
		end
	end
	return parts
end

function MapService.Init()
	worldFolder = Instance.new("Folder")
	worldFolder.Name = "NAUWorld"
	worldFolder.Parent = workspace

	local LobbyBuilder = require(Builders:WaitForChild("Lobby"))
	lobby = LobbyBuilder.build(worldFolder)
	lobby:PivotTo(LOBBY_CFRAME)
	makePersistent(lobby)
	if LobbyBuilder.buildTerrain then
		LobbyBuilder.buildTerrain(LOBBY_CFRAME)
	end
end

function MapService.loadMap(mapId: string): Model
	if arena and arenaId == mapId and arena.Parent then
		return arena
	end
	if arena then
		arena:Destroy()
		if arenaBuilder and arenaBuilder.clearTerrain then
			arenaBuilder.clearTerrain(ARENA_CFRAME)
		end
	end
	local def = MapRegistry.get(mapId)
	assert(def, "MapService: unknown map " .. tostring(mapId))
	local builder = require(Builders:WaitForChild(def.builder))
	local newArena: Model = builder.build(worldFolder)
	newArena:PivotTo(ARENA_CFRAME)
	newArena:SetAttribute("MapId", mapId)
	makePersistent(newArena)
	if builder.buildTerrain then
		builder.buildTerrain(ARENA_CFRAME)
	end
	arena, arenaId, arenaBuilder = newArena, mapId, builder
	return newArena
end

local function characterList(): { Instance }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	local decoys = worldFolder and worldFolder:FindFirstChild("Decoys") -- Naruto's clones never block a spawn
	if decoys then
		table.insert(list, decoys)
	end
	return list
end

-- A random, unmarked arena spawn (owner rule): sample points inside the map's SpawnArea boxes, keep only
-- open ground (terrain or parts tagged Walkable, with room for an avatar), and prefer the point farthest
-- from `avoid` (living opponents), accepting the first one at least SPAWN_MIN_DISTANCE_FROM_OPPONENTS away.
-- Returns a CFrame at spawn-marker height, facing the arena centre.
function MapService.findArenaSpawn(avoid: { Vector3 }): CFrame
	assert(arena, "MapService: no arena loaded")
	return MapService.findSpawnIn(arena, avoid)
end

-- The sampler itself, for any built map (also used by tests against the live arena).
function MapService.findSpawnIn(map: Model, avoid: { Vector3 }): CFrame
	local folder = map:FindFirstChild("SpawnArea")
	local areas = {}
	local totalArea = 0
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(areas, child)
				totalArea += child.Size.X * child.Size.Z
			end
		end
	end
	assert(#areas > 0, "MapService: arena has no SpawnArea")

	local characters = characterList()
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = characters
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local overlapParams = OverlapParams.new()
	local ignore = table.clone(characters)
	table.insert(ignore, workspace.Terrain)
	overlapParams.FilterDescendantsInstances = ignore
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.RespectCanCollide = true

	local center = map:GetPivot().Position
	local best: Vector3? = nil
	local bestScore = -1
	for _ = 1, Constants.SPAWN_SAMPLE_ATTEMPTS do
		local pick = math.random() * totalArea
		local area = areas[#areas]
		for _, candidate in areas do
			pick -= candidate.Size.X * candidate.Size.Z
			if pick <= 0 then
				area = candidate
				break
			end
		end
		local top = area.CFrame:PointToWorldSpace(Vector3.new(
			(math.random() - 0.5) * area.Size.X,
			area.Size.Y / 2,
			(math.random() - 0.5) * area.Size.Z
		))
		local hit = workspace:Raycast(top, Vector3.new(0, -(area.Size.Y + 12), 0), rayParams)
		local walkable = hit and (hit.Instance:IsA("Terrain") or hit.Instance:GetAttribute("Walkable") == true)
		if hit and walkable and hit.Normal.Y > 0.7 then
			local feet = hit.Position
			local blocked = workspace:GetPartBoundsInBox(CFrame.new(feet + Vector3.new(0, 3.2, 0)), Vector3.new(4, 5.6, 4), overlapParams)
			if #blocked == 0 then
				local score = math.huge
				for _, position in avoid do
					score = math.min(score, (position - feet).Magnitude)
				end
				if score > bestScore then
					best, bestScore = feet, score
				end
				if score >= Constants.SPAWN_MIN_DISTANCE_FROM_OPPONENTS then
					break
				end
			end
		end
	end

	local feet = best or (center + Vector3.new(0, 1, 0))
	local marker = feet + Vector3.new(0, 0.5, 0)
	local lookAt = Vector3.new(center.X, marker.Y, center.Z)
	if (lookAt - marker).Magnitude < 1 then
		lookAt = marker + Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(marker, lookAt)
end

local function insideSpawnArea(map: Model, point: Vector3): boolean
	local folder = map:FindFirstChild("SpawnArea")
	for _, box in if folder then folder:GetChildren() else {} do
		if box:IsA("BasePart") then
			local lp = box.CFrame:PointToObjectSpace(point)
			if math.abs(lp.X) <= box.Size.X / 2 and math.abs(lp.Z) <= box.Size.Z / 2 then
				return true
			end
		end
	end
	return false
end

-- A random open spot about `distance` studs from `center` inside the loaded arena (Gokai's Phase
-- Shift): same open-ground rules as spawning (walkable, room for an avatar, never inside cover,
-- never outside the map's SpawnArea). Tries directions in a random order; nil if nowhere fits.
function MapService.findSpotNear(center: Vector3, distance: number, ignore: { Instance }): CFrame?
	if not arena then
		return nil
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = ignore
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local overlapParams = OverlapParams.new()
	local overlapIgnore = table.clone(ignore)
	table.insert(overlapIgnore, workspace.Terrain)
	overlapParams.FilterDescendantsInstances = overlapIgnore
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.RespectCanCollide = true

	local start = math.random() * math.pi * 2
	local tries = 16
	for i = 0, tries - 1 do
		local angle = start + i * (math.pi * 2 / tries)
		local r = distance + (math.random() - 0.5) * 2 -- a little spread so it doesn't feel like a fixed ring
		local probe = center + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		if insideSpawnArea(arena, probe) then
			local hit = workspace:Raycast(probe + Vector3.new(0, 25, 0), Vector3.new(0, -60, 0), rayParams)
			local walkable = hit and (hit.Instance:IsA("Terrain") or hit.Instance:GetAttribute("Walkable") == true)
			if hit and walkable and hit.Normal.Y > 0.7 and math.abs(hit.Position.Y - center.Y) < 12 then
				local feet = hit.Position
				local blocked = workspace:GetPartBoundsInBox(CFrame.new(feet + Vector3.new(0, 3.2, 0)), Vector3.new(4, 5.6, 4), overlapParams)
				if #blocked == 0 then
					local heading = Vector3.new(feet.X - center.X, 0, feet.Z - center.Z)
					local marker = feet + Vector3.new(0, 3, 0)
					return CFrame.lookAt(marker, marker + (if heading.Magnitude > 0.1 then heading.Unit else Vector3.zAxis))
				end
			end
		end
	end
	return nil
end

-- Can an avatar stand with its feet at `feet` (Gojo's Blink)? Inside the arena's SpawnArea and with
-- room for an avatar (no cover in the way). Returns a CFrame facing `heading`, or nil.
function MapService.openSpotAt(feet: Vector3, ignore: { Instance }, heading: Vector3): CFrame?
	if not arena or not insideSpawnArea(arena, feet) then
		return nil
	end
	local overlapParams = OverlapParams.new()
	local overlapIgnore = table.clone(ignore)
	table.insert(overlapIgnore, workspace.Terrain)
	overlapParams.FilterDescendantsInstances = overlapIgnore
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.RespectCanCollide = true
	local blocked = workspace:GetPartBoundsInBox(CFrame.new(feet + Vector3.new(0, 3.2, 0)), Vector3.new(3, 5.2, 3), overlapParams)
	if #blocked > 0 then
		return nil
	end
	local marker = feet + Vector3.new(0, 3, 0)
	local flat = Vector3.new(heading.X, 0, heading.Z)
	return CFrame.lookAt(marker, marker + (if flat.Magnitude > 0.1 then flat.Unit else Vector3.zAxis))
end

function MapService.getLobbySpawn(): CFrame
	local parts = spawnParts(lobby)
	assert(#parts > 0, "MapService: lobby has no SpawnPoints")
	return parts[math.random(1, #parts)].CFrame
end

function MapService.getLobby(): Model
	return lobby
end

return MapService
