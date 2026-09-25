-- Map 1 builder: "The Proving Grounds" (v2), an open-air martial-arts examination stadium.
--
-- A circular grass-and-dirt field (terrain) inside a tall stone stadium wall, with tiered spectator
-- stands, a roofed north stand, barred entrance gates east and west, a proctor's balcony flanked by
-- guardian statues, and a battle-scarred field: a raised sparring platform in the centre, a ring of
-- broken pillars, rock outcrops, trees, training posts, low wall ruins and craters.
-- Numbers are only readable face-to-face within ~11 studs, so the field is dense with things to round
-- a corner on. Every piece is solid and exterior-only: you hide behind things, never inside them.
--
-- Cover heights (avatar ~5 studs; the plate floats just above the head):
--   TALL (>= 8 studs) hides a fighter and their plate.   LOW (3-4.5 studs) hides the body only.
--
-- Map contract (every map provides it; see docs/DESIGN.md):
--   <Map>.PrimaryPart   unrotated root at floor level, so PivotTo places the map exactly
--   <Map>/SpawnArea/*   invisible boxes; spawns are sampled at random inside them on open ground
--                        (terrain, or parts with attribute Walkable = true). Nothing marks a spawn.
--   buildTerrain / clearTerrain(origin)   terrain is global, so the map adds and removes its own
-- Built around the origin; MapService pivots it. -Z = north (balcony), +X = east gate.
-- All parts are anchored static geometry. Layout randomness uses a fixed seed, so it is the same every build.

local ProvingGrounds = {}

local FIELD_RADIUS = 72
local WALL_THICKNESS = 3
local WALL_HEIGHT = 20
local WALL_SEGMENTS = 48
local BARRIER_HEIGHT = 70
local GATE_ANGLES = { 0, 180 } -- degrees; 0 = east, 90 = south, 270 = north
local BALCONY_ANGLE = 270
local STAND_ROWS = 6 -- spectator rows in the bowl (owner, 2026-09-23: filled colosseum)
local STAND_ROW_DEPTH = 2.4
local STAND_ROW_RISE = 1.5
local PLATFORM_RADIUS = 12
local PLATFORM_HEIGHT = 1.2
local SEED = 20260923

local PALETTE = {
	Wall = Color3.fromRGB(168, 158, 142),
	WallBase = Color3.fromRGB(118, 108, 98),
	Trim = Color3.fromRGB(196, 188, 172),
	StandA = Color3.fromRGB(150, 140, 124),
	StandB = Color3.fromRGB(166, 156, 138),
	Roof = Color3.fromRGB(150, 62, 46),
	Wood = Color3.fromRGB(118, 84, 56),
	WoodDark = Color3.fromRGB(84, 60, 42),
	Iron = Color3.fromRGB(52, 54, 60),
	Doorway = Color3.fromRGB(28, 26, 26),
	Platform = Color3.fromRGB(182, 174, 160),
	PlatformRing = Color3.fromRGB(128, 70, 56),
	Pillar = Color3.fromRGB(204, 196, 178),
	Rock = Color3.fromRGB(122, 118, 110),
	Trunk = Color3.fromRGB(92, 68, 48),
	Leaf = Color3.fromRGB(70, 122, 60),
	Leaf2 = Color3.fromRGB(92, 142, 70),
	Bush = Color3.fromRGB(64, 104, 54),
	Statue = Color3.fromRGB(140, 134, 124),
	Flame = Color3.fromRGB(255, 176, 96),
	Red = Color3.fromRGB(190, 58, 52),
	Blue = Color3.fromRGB(58, 96, 190),
	Gold = Color3.fromRGB(222, 176, 70),
}

local function block(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Upright cylinder (Roblox cylinders run along X, so roll it 90 degrees).
local function column(parent: Instance, name: string, height: number, diameter: number, base: Vector3, color: Color3, material: Enum.Material): Part
	local part = block(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	part.Shape = Enum.PartType.Cylinder
	return part
end

local function ball(parent: Instance, name: string, diameter: number, center: Vector3, color: Color3, material: Enum.Material): Part
	local part = block(parent, name, Vector3.one * diameter, CFrame.new(center), color, material)
	part.Shape = Enum.PartType.Ball
	return part
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function decor(part: BasePart): BasePart
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	return part
end

local function hide(part: BasePart): BasePart
	part.Transparency = 1
	part.CastShadow = false
	return part
end

local function polar(radius: number, degrees: number, y: number): Vector3
	local r = math.rad(degrees)
	return Vector3.new(math.cos(r) * radius, y, math.sin(r) * radius)
end

-- A block on a ring, its local Z pointing at the centre (so X runs along the ring).
local function ringBlock(parent: Instance, name: string, radius: number, degrees: number, y: number, size: Vector3, color: Color3, material: Enum.Material): Part
	local position = polar(radius, degrees, y)
	return block(parent, name, size, CFrame.lookAt(position, Vector3.new(0, y, 0)), color, material)
end

local function tagCover(part: BasePart, class: string): BasePart
	part:SetAttribute("CoverClass", class)
	return part
end

local function nearAngle(degrees: number, targets: { number }, within: number): boolean
	for _, target in targets do
		local delta = math.abs(((degrees - target + 180) % 360) - 180)
		if delta <= within then
			return true
		end
	end
	return false
end

local function buildStadium(model: Model)
	local stadium = folder(model, "Stadium")
	local wallRadius = FIELD_RADIUS + WALL_THICKNESS / 2
	local segmentLength = 2 * math.pi * wallRadius / WALL_SEGMENTS + 0.5
	for i = 0, WALL_SEGMENTS - 1 do
		local degrees = (i + 0.5) * 360 / WALL_SEGMENTS
		if not nearAngle(degrees, GATE_ANGLES, 5) then
			ringBlock(stadium, "Wall", wallRadius, degrees, WALL_HEIGHT / 2, Vector3.new(segmentLength, WALL_HEIGHT, WALL_THICKNESS), PALETTE.Wall, Enum.Material.Cobblestone)
			decor(ringBlock(stadium, "WallBase", wallRadius - 0.3, degrees, 1.5, Vector3.new(segmentLength, 3, WALL_THICKNESS + 0.6), PALETTE.WallBase, Enum.Material.Slate))
		end
		ringBlock(stadium, "WallCap", wallRadius, degrees, WALL_HEIGHT + 0.6, Vector3.new(segmentLength, 1.2, WALL_THICKNESS + 1.2), PALETTE.Trim, Enum.Material.Limestone)
	end
	-- Invisible barrier above the wall, so future mobility abilities can't leave the arena.
	for i = 0, 23 do
		local barrier = ringBlock(stadium, "Barrier", wallRadius, (i + 0.5) * 15, WALL_HEIGHT + (BARRIER_HEIGHT - WALL_HEIGHT) / 2, Vector3.new(2 * math.pi * wallRadius / 24 + 1, BARRIER_HEIGHT - WALL_HEIGHT, WALL_THICKNESS), PALETTE.Wall, Enum.Material.SmoothPlastic)
		hide(barrier)
		barrier.CanQuery = false
	end

	-- Spectator stands (owner-approved 2026-09-23: a filled colosseum): a bowl of stepped rows rising behind
	-- the wall, each row one line of spectators. The crowd itself is built by each client
	-- (CrowdController) from the Crowd/Row* configurations below, so the server never replicates it.
	local rowInner = wallRadius + WALL_THICKNESS / 2
	local function rowRadius(row: number): number
		return rowInner + (row + 0.5) * STAND_ROW_DEPTH
	end
	local function rowTop(row: number): number
		return WALL_HEIGHT + 1.2 + (row + 1) * STAND_ROW_RISE
	end
	for row = 0, STAND_ROWS - 1 do
		local radius, top = rowRadius(row), rowTop(row)
		local length = 2 * math.pi * radius / WALL_SEGMENTS + 0.6
		for i = 0, WALL_SEGMENTS - 1 do
			local degrees = (i + 0.5) * 360 / WALL_SEGMENTS
			ringBlock(stadium, "Stand" .. (row + 1), radius, degrees, top / 2, Vector3.new(length, top, STAND_ROW_DEPTH), if row % 2 == 0 then PALETTE.StandA else PALETTE.StandB, Enum.Material.Concrete)
		end
	end
	-- A parapet closing the back of the bowl.
	local backRadius = rowInner + STAND_ROWS * STAND_ROW_DEPTH + 0.6
	local backTop = rowTop(STAND_ROWS - 1) + 4
	for i = 0, WALL_SEGMENTS - 1 do
		local degrees = (i + 0.5) * 360 / WALL_SEGMENTS
		ringBlock(stadium, "StandBack", backRadius, degrees, backTop / 2, Vector3.new(2 * math.pi * backRadius / WALL_SEGMENTS + 0.6, backTop, 1.2), PALETTE.Wall, Enum.Material.Cobblestone)
		ringBlock(stadium, "StandBackCap", backRadius, degrees, backTop + 0.4, Vector3.new(2 * math.pi * backRadius / WALL_SEGMENTS + 0.8, 0.8, 1.8), PALETTE.Trim, Enum.Material.Limestone)
	end

	-- Roofed north stand: posts on the second-highest row and a terracotta awning tilted toward the field.
	local roofRadius = wallRadius + 9
	local postRow = STAND_ROWS - 2
	local postAngles = {}
	for degrees = 215, 325, 22 do
		column(stadium, "RoofPost", 16, 1.6, polar(rowRadius(postRow), degrees, rowTop(postRow)), PALETTE.Wood, Enum.Material.Wood)
		table.insert(postAngles, degrees)
	end

	-- Where the crowd sits (read by CrowdController on each client). Seats to leave empty: the gates (whose
	-- lintels hide the lowest rows), the proctor's balcony canopy, and the roof posts.
	local crowd = folder(model, "Crowd")
	for row = 0, STAND_ROWS - 1 do
		local config = Instance.new("Configuration")
		config.Name = "Row" .. (row + 1)
		config:SetAttribute("Radius", rowRadius(row))
		config:SetAttribute("Y", rowTop(row))
		local avoid = {}
		if row <= 1 then
			for _, a in GATE_ANGLES do
				table.insert(avoid, string.format("%d:9", a))
			end
			table.insert(avoid, string.format("%d:12", BALCONY_ANGLE))
		end
		if row == postRow then
			for _, a in postAngles do
				table.insert(avoid, string.format("%d:1.6", a))
			end
		end
		config:SetAttribute("Avoid", table.concat(avoid, ",")) -- "degrees:half-width" pairs
		config.Parent = crowd
	end
	for degrees = 212, 328, 8 do
		local position = polar(roofRadius, degrees, WALL_HEIGHT + 26)
		local length = 2 * math.pi * roofRadius / 45 + 0.8
		local cf = CFrame.lookAt(position, Vector3.new(0, position.Y, 0)) * CFrame.Angles(math.rad(-12), 0, 0)
		block(stadium, "Roof", Vector3.new(length, 0.8, 18), cf, PALETTE.Roof, Enum.Material.Slate)
	end

	-- Entrance gates: tall pillars, a lintel, a dark barred doorway (sealed during a match).
	for _, degrees in GATE_ANGLES do
		local gate = Instance.new("Model")
		gate.Name = "Gate" .. degrees
		local center = polar(wallRadius, degrees, 0)
		local base = CFrame.lookAt(center, Vector3.new(0, 0, 0))
		for _, side in { -1, 1 } do
			block(gate, "GatePillar", Vector3.new(4, 26, 5), base * CFrame.new(side * 7, 13, 0), PALETTE.Trim, Enum.Material.Limestone)
		end
		block(gate, "GateLintel", Vector3.new(18, 3, 5), base * CFrame.new(0, 24.5, 0), PALETTE.Trim, Enum.Material.Limestone)
		block(gate, "Doorway", Vector3.new(10, 18, WALL_THICKNESS), base * CFrame.new(0, 9, 0.5), PALETTE.Doorway, Enum.Material.Slate)
		for bar = -4, 4, 1 do
			decor(block(gate, "Bar", Vector3.new(0.4, 18, 0.4), base * CFrame.new(bar, 9, -1.3), PALETTE.Iron, Enum.Material.Metal))
		end
		decor(block(gate, "Crossbar", Vector3.new(10, 0.5, 0.5), base * CFrame.new(0, 12, -1.3), PALETTE.Iron, Enum.Material.Metal))
		gate.Parent = stadium
	end

	-- Proctor's balcony on the north wall, flanked by two guardian statues.
	local balcony = Instance.new("Model")
	balcony.Name = "ProctorBalcony"
	local anchor = CFrame.lookAt(polar(FIELD_RADIUS, BALCONY_ANGLE, 0), Vector3.new(0, 0, 0))
	block(balcony, "Floor", Vector3.new(20, 1, 6), anchor * CFrame.new(0, 13, -3), PALETTE.Trim, Enum.Material.Limestone)
	decor(block(balcony, "Rail", Vector3.new(20, 1.2, 0.6), anchor * CFrame.new(0, 14.1, -5.7), PALETTE.Wood, Enum.Material.Wood))
	for _, x in { -9, 9 } do
		block(balcony, "Post", Vector3.new(1, 8, 1), anchor * CFrame.new(x, 17.5, -5.5), PALETTE.Wood, Enum.Material.Wood)
	end
	block(balcony, "Canopy", Vector3.new(22, 0.8, 8), anchor * CFrame.new(0, 21.8, -3) * CFrame.Angles(math.rad(8), 0, 0), PALETTE.Roof, Enum.Material.Slate)
	decor(block(balcony, "Banner", Vector3.new(8, 9, 0.3), anchor * CFrame.new(0, 7.5, -0.4), PALETTE.Gold, Enum.Material.Fabric))
	balcony.Parent = stadium
	for _, offset in { -20, 20 } do
		local statue = Instance.new("Model")
		statue.Name = "GuardianStatue"
		local spot = polar(FIELD_RADIUS - 4, BALCONY_ANGLE + offset, 0)
		tagCover(block(statue, "Pedestal", Vector3.new(6, 3, 6), CFrame.new(spot + Vector3.new(0, 1.5, 0)), PALETTE.WallBase, Enum.Material.Slate), "Tall")
		tagCover(block(statue, "Body", Vector3.new(3.5, 11, 3), CFrame.lookAt(spot + Vector3.new(0, 8.5, 0), Vector3.new(0, 8.5, 0)), PALETTE.Statue, Enum.Material.Rock), "Tall")
		ball(statue, "Orb", 4.5, spot + Vector3.new(0, 16.2, 0), PALETTE.Statue, Enum.Material.Rock)
		statue.Parent = stadium
	end

	-- Banners and torches around the inner wall.
	for i = 0, 7 do
		local degrees = 22.5 + i * 45
		if not nearAngle(degrees, { BALCONY_ANGLE }, 10) then
			local color = if i % 2 == 0 then PALETTE.Red else PALETTE.Blue
			decor(ringBlock(stadium, "Banner", FIELD_RADIUS - 0.2, degrees, 13, Vector3.new(5, 11, 0.3), color, Enum.Material.Fabric))
		end
	end
	for i = 0, 11 do
		local degrees = i * 30 + 15
		local torchBase = polar(FIELD_RADIUS - 0.6, degrees, WALL_HEIGHT - 3)
		local bracket = block(stadium, "TorchBracket", Vector3.new(1, 1, 1.4), CFrame.lookAt(torchBase, Vector3.new(0, torchBase.Y, 0)), PALETTE.Iron, Enum.Material.Metal)
		decor(bracket)
		local flame = decor(block(stadium, "TorchFlame", Vector3.new(0.9, 1.4, 0.9), CFrame.new(torchBase + Vector3.new(0, 1.2, 0)), PALETTE.Flame, Enum.Material.Neon))
		local light = Instance.new("PointLight")
		light.Color = PALETTE.Flame
		light.Range = 16
		light.Brightness = 1.4
		light.Parent = flame
	end
end

local function buildPlatform(model: Model)
	local platform = folder(model, "SparringPlatform")
	local top = column(platform, "Platform", PLATFORM_HEIGHT, PLATFORM_RADIUS * 2, Vector3.new(0, 0, 0), PALETTE.Platform, Enum.Material.Slate)
	top:SetAttribute("Walkable", true)
	local ring = decor(column(platform, "Ring", 0.05, PLATFORM_RADIUS * 2 - 2, Vector3.new(0, PLATFORM_HEIGHT, 0), PALETTE.PlatformRing, Enum.Material.Slate))
	ring.Transparency = 0
	decor(column(platform, "RingInner", 0.06, PLATFORM_RADIUS * 2 - 4, Vector3.new(0, PLATFORM_HEIGHT, 0), PALETTE.Platform, Enum.Material.Slate))
	-- Four stone lanterns just off the platform edge.
	for _, degrees in { 45, 135, 225, 315 } do
		local spot = polar(PLATFORM_RADIUS + 2.5, degrees, 0)
		block(platform, "LanternBase", Vector3.new(1.6, 3, 1.6), CFrame.new(spot + Vector3.new(0, 1.5, 0)), PALETTE.WallBase, Enum.Material.Slate)
		local flame = decor(block(platform, "LanternFlame", Vector3.new(0.7, 0.8, 0.7), CFrame.new(spot + Vector3.new(0, 3.4, 0)), PALETTE.Flame, Enum.Material.Neon))
		flame.Transparency = 0.15
		decor(block(platform, "LanternCap", Vector3.new(2, 0.4, 2), CFrame.new(spot + Vector3.new(0, 4, 0)), PALETTE.WallBase, Enum.Material.Slate))
		local light = Instance.new("PointLight")
		light.Color = PALETTE.Flame
		light.Range = 12
		light.Parent = flame
	end
end

local function buildField(model: Model, rng: Random)
	local field = folder(model, "Field")

	-- Broken pillars ringing the centre (a mix of tall and low stumps), two toppled.
	local pillarHeights = { 11, 4, 9, 3.5, 8, 5 }
	for i, height in pillarHeights do
		local degrees = 30 + (i - 1) * 60
		local spot = polar(30, degrees, 0)
		local pillar = column(field, "BrokenPillar", height, 3.6, spot, PALETTE.Pillar, Enum.Material.Limestone)
		tagCover(pillar, if height >= 8 then "Tall" else "Low")
		if height < 6 then
			local fallen = block(field, "FallenDrum", Vector3.new(5, 3.2, 3.2), CFrame.new(spot + polar(4.5, degrees + 70, 1.6)) * CFrame.Angles(0, math.rad(degrees + 160), 0) * CFrame.Angles(0, 0, 0), PALETTE.Pillar, Enum.Material.Limestone)
			fallen.Shape = Enum.PartType.Cylinder
			tagCover(fallen, "Low")
		end
	end

	-- Rock outcrops: clusters of tilted boulders.
	local outcrops = { { 52, 70 }, { 46, 150 }, { 55, 205 }, { 48, 300 }, { 26, 110 }, { 26, 290 } }
	for i, spec in outcrops do
		local cluster = Instance.new("Model")
		cluster.Name = "Outcrop" .. i
		local center = polar(spec[1], spec[2], 0)
		for r = 1, 4 do
			local size = Vector3.new(rng:NextNumber(4, 8), rng:NextNumber(3, 9.5), rng:NextNumber(4, 7))
			local offset = Vector3.new(rng:NextNumber(-4, 4), size.Y / 2 - 0.8, rng:NextNumber(-4, 4))
			local rock = block(cluster, "Boulder", size, CFrame.new(center + offset) * CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, math.pi), rng:NextNumber(-0.25, 0.25)), PALETTE.Rock, Enum.Material.Rock)
			tagCover(rock, if size.Y >= 8 then "Tall" else "Low")
		end
		cluster.Parent = field
	end

	-- Trees: the trunks are cover, the canopies are high overhead.
	local trees = { { 58, 30 }, { 50, 110 }, { 60, 165 }, { 56, 235 }, { 44, 330 } }
	for i, spec in trees do
		local tree = Instance.new("Model")
		tree.Name = "Tree" .. i
		local base = polar(spec[1], spec[2], 0)
		tagCover(column(tree, "Trunk", 15, 3.2, base, PALETTE.Trunk, Enum.Material.Wood), "Tall")
		for root = 0, 2 do
			local angle = root * 120 + spec[2]
			decor(block(tree, "Root", Vector3.new(4, 1.2, 1.4), CFrame.new(base + polar(1.8, angle, 0.5)) * CFrame.Angles(0, math.rad(-angle), math.rad(-15)), PALETTE.Trunk, Enum.Material.Wood))
		end
		decor(ball(tree, "Canopy", 12, base + Vector3.new(0, 17, 0), PALETTE.Leaf, Enum.Material.Grass))
		decor(ball(tree, "Canopy", 9, base + Vector3.new(4, 15.5, 2), PALETTE.Leaf2, Enum.Material.Grass))
		decor(ball(tree, "Canopy", 8, base + Vector3.new(-3.5, 15, -3), PALETTE.Leaf, Enum.Material.Grass))
		for bush = 1, 2 do
			local spot = base + polar(4.5, spec[2] + 100 * bush, 0)
			tagCover(ball(tree, "Bush", 5, spot + Vector3.new(0, 1, 0), PALETTE.Bush, Enum.Material.Grass), "Low")
		end
		tree.Parent = field
	end

	-- Training posts: rows of wooden practice logs.
	for _, spec in { { 36, 20 }, { 38, 200 } } do
		local yard = Instance.new("Model")
		yard.Name = "TrainingPosts"
		for n = -1, 1 do
			local spot = polar(spec[1], spec[2] + n * 5, 0)
			tagCover(column(yard, "Post", 5, 1.6, spot, PALETTE.Wood, Enum.Material.Wood), "Low")
			decor(column(yard, "Binding", 0.5, 1.8, spot + Vector3.new(0, 3.2, 0), PALETTE.WoodDark, Enum.Material.Fabric))
		end
		yard.Parent = field
	end

	-- Low wall ruins (L-shaped), waist high: bodies hide, plates don't.
	for _, degrees in { 45, 135, 225, 315 } do
		local ruin = Instance.new("Model")
		ruin.Name = "WallRuin"
		local spot = polar(40, degrees, 0)
		local facing = CFrame.lookAt(spot, Vector3.new(0, 0, 0))
		tagCover(block(ruin, "Long", Vector3.new(10, 4, 2), facing * CFrame.new(0, 2, 0), PALETTE.WallBase, Enum.Material.Cobblestone), "Low")
		tagCover(block(ruin, "Short", Vector3.new(2, 3, 6), facing * CFrame.new(4, 1.5, 4), PALETTE.WallBase, Enum.Material.Cobblestone), "Low")
		ruin.Parent = field
	end
end

-- Craters: where they sit, and the rocks thrown up around each rim.
local CRATERS = { { 21, 175, 6.5 }, { 36, 250, 6 }, { 58, 355, 6.5 } } -- { radius from centre, degrees, crater radius }

local function buildCraterRims(model: Model, rng: Random)
	local rims = folder(model, "Craters")
	for _, spec in CRATERS do
		local center = polar(spec[1], spec[2], 0)
		for n = 0, 5 do
			local angle = n * 60 + rng:NextNumber(-15, 15)
			local spot = center + polar(spec[3] + 0.8, angle, 0.4)
			decor(block(rims, "RimRock", Vector3.new(rng:NextNumber(1.2, 2.4), rng:NextNumber(0.8, 1.6), rng:NextNumber(1.2, 2.2)), CFrame.new(spot) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 3), rng:NextNumber(-0.5, 0.5)), PALETTE.Rock, Enum.Material.Rock))
		end
	end
end

local function buildSpawnArea(model: Model)
	local area = folder(model, "SpawnArea")
	local box = block(area, "Field", Vector3.new(FIELD_RADIUS * 2, 24, FIELD_RADIUS * 2), CFrame.new(0, 12, 0), PALETTE.Wall, Enum.Material.SmoothPlastic)
	hide(decor(box))
end

function ProvingGrounds.build(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Arena_ProvingGrounds"
	model:SetAttribute("DisplayName", "The Proving Grounds")

	local root = block(model, "Root", Vector3.one, CFrame.new(0, 0, 0), PALETTE.Wall, Enum.Material.SmoothPlastic)
	hide(decor(root))
	model.PrimaryPart = root

	local rng = Random.new(SEED)
	buildStadium(model)
	buildPlatform(model)
	buildField(model, rng)
	buildCraterRims(model, rng)
	buildSpawnArea(model)

	model.Parent = parent
	return model
end

-- Terrain floor: grass with a packed-dirt centre, dirt patches, and craters from past fights.
-- Fills stop 2 studs below the arena floor: with the origin at y = 2 (MapService), the half-covered
-- voxel rounds up and the grass surfaces exactly at the floor, level with every part's base.
local TERRAIN_TOP = -2

function ProvingGrounds.buildTerrain(origin: CFrame)
	local terrain = workspace.Terrain
	local center = TERRAIN_TOP - 4 -- 8-stud-tall fills centred here end at TERRAIN_TOP
	terrain:FillCylinder(origin * CFrame.new(0, center, 0), 8, FIELD_RADIUS + 10, Enum.Material.Grass)
	terrain:FillCylinder(origin * CFrame.new(0, center, 0), 8.2, 26, Enum.Material.Ground)
	for _, spec in { { 50, 90, 8 }, { 45, 190, 7 }, { 52, 320, 9 }, { 34, 140, 6 } } do
		terrain:FillCylinder(origin * CFrame.new(polar(spec[1], spec[2], center)), 8.1, spec[3], Enum.Material.Ground)
	end
	for _, spec in CRATERS do
		local spot = polar(spec[1], spec[2], 0)
		terrain:FillCylinder(origin * CFrame.new(spot + Vector3.new(0, center, 0)), 8.2, spec[3] + 1.5, Enum.Material.Ground)
		terrain:FillBall((origin * CFrame.new(spot + Vector3.new(0, spec[3] - 3, 0))).Position, spec[3], Enum.Material.Air)
	end
end

function ProvingGrounds.clearTerrain(origin: CFrame)
	workspace.Terrain:FillBlock(origin * CFrame.new(0, 10, 0), Vector3.new((FIELD_RADIUS + 40) * 2, 60, (FIELD_RADIUS + 40) * 2), Enum.Material.Air)
end

return ProvingGrounds
