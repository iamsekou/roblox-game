-- Lobby builder: "The Still Harbor", rebuilt 2026-09-23 (owner: "cleaner 3D models", water on the
-- sides "covered off", stone colonnade walls). A walled limestone courtyard: a paved avenue runs
-- north from the arrival plaza, past the character pedestals and cypress planters, under three stone
-- arches, to the FIGHT gate set into the north wall. Covered colonnades line both long sides and
-- tall walls close all four sides, so no water shows from the courtyard.
--
-- Top-down (+Z = south): arrival plaza at the south end, avenue running north, gate at the north end.
-- Bubbles are camera-facing BillboardGuis (name / portrait circle / price), so they read from anywhere
-- on the avenue. Built around the origin; MapService pivots it into place.
-- Scale: a default R15 avatar is ~5 studs tall; doors and colonnade openings clear 15+ studs.
--
-- Contract used by the game code:
--   Lobby.PrimaryPart     unrotated root at ground level (so PivotTo places the lobby exactly)
--   Lobby/SpawnPoints/*   invisible marker parts on the arrival plaza
--   Lobby/Podiums/*       one Model per roster slot; its "Dais" part holds a ProximityPrompt (attribute CharacterId)
--   Lobby/FightPortal     part "PortalGlow" holds a ProximityPrompt (attribute Action = "Fight")
-- Everything is anchored static scenery. Purely decorative pieces don't collide or take raycasts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CharacterDefs =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("CharacterDefs"))

local Lobby = {}

-- Dimensions (studs)
local PATH_WIDTH = 14
local PATH_NORTH, PATH_SOUTH = -100, 106
local COLUMN_X = 30 -- colonnade column line (both sides)
local WALL_X = 38 -- inner face of the long side walls
local WALL_THICKNESS = 4
local WALL_HEIGHT = 32
local Z_NORTH, Z_SOUTH = -118, 114 -- inner faces of the end walls
local BAY = 12 -- column / pilaster spacing
local FIRST_COLUMN_Z, LAST_COLUMN_Z = -106, 98
local WALK_STEP = 0.6 -- the covered walkway is one low step up
local SHAFT_HEIGHT = 15
local PEDESTAL_X = 17
local PEDESTAL_ZS = { 62, 38, 14, -10, -34 } -- south to north; odd slots west, even slots east
local CYPRESS_ZS = { 74, 50, 26, 2, -22, -46 } -- between the pedestals, same line
local LAMP_X = PATH_WIDTH / 2 + 1.6
local LAMP_ZS = { 74, 50, 26, 2, -22, -46, -70, -94 }
local ARCH_ZS = { 86, 2, -70 } -- must be column z's: the arches spring from the colonnade
local ARCH_RISE = 8
local ARCH_SEGMENTS = 12
local ARRIVAL_Z = 96
local GATE_Z = -112
local BUBBLE_STUDS = 9
local FLAGSTONE = 8 -- flagstone joint spacing on the courtyard floor

-- Column stack, bottom to top (heights).
local COLUMN_PLINTH, COLUMN_TORUS, COLUMN_ECHINUS, COLUMN_ABACUS = 0.8, 0.5, 0.5, 0.7
local COLUMN_TOP = WALK_STEP + COLUMN_PLINTH + COLUMN_TORUS + SHAFT_HEIGHT + COLUMN_ECHINUS + COLUMN_ABACUS
local ARCHITRAVE_H, FRIEZE_H, CORNICE_H = 1.8, 1.4, 0.7
local ENTABLATURE_TOP = COLUMN_TOP + ARCHITRAVE_H + FRIEZE_H + CORNICE_H

-- A small, coherent palette: warm limestone, dark basalt trim, marble, iron and brass, deep crimson cloth.
local PALETTE = {
	Floor = Color3.fromRGB(158, 150, 138),
	FloorJoint = Color3.fromRGB(118, 111, 102),
	Avenue = Color3.fromRGB(188, 180, 164),
	Trim = Color3.fromRGB(58, 56, 54),
	Wall = Color3.fromRGB(196, 181, 154),
	WallLight = Color3.fromRGB(214, 202, 178),
	Marble = Color3.fromRGB(226, 221, 211),
	Iron = Color3.fromRGB(38, 38, 40),
	Brass = Color3.fromRGB(170, 136, 78),
	Banner = Color3.fromRGB(112, 26, 30),
	LampGlow = Color3.fromRGB(255, 190, 130), -- light colour
	LampGlass = Color3.fromRGB(214, 150, 96), -- the glass itself: dimmer, so bloom doesn't blow it out to white
	Leaf = Color3.fromRGB(52, 78, 50),
	Leaf2 = Color3.fromRGB(62, 92, 58),
	Soil = Color3.fromRGB(52, 42, 34),
	Wood = Color3.fromRGB(70, 48, 34),
	Portal = Color3.fromRGB(255, 120, 50),
	PortalCore = Color3.fromRGB(96, 22, 10),
}

local TIER_COLORS = {
	Free = Color3.fromRGB(116, 196, 136),
	Yen = Color3.fromRGB(214, 180, 96),
	Robux = Color3.fromRGB(160, 130, 220),
}

local DISPLAY_FONT = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)

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

-- Roblox cylinders run along the part's X axis; this stands one upright as a disc/column.
local function disc(parent: Instance, name: string, height: number, diameter: number, center: Vector3, color: Color3, material: Enum.Material): Part
	local part = block(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), color, material)
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

-- Non-physical decoration: nothing to trip over, nothing for raycasts to hit.
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

local function glow(part: BasePart, color: Color3, range: number, brightness: number): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = part
	return light
end

local function formatNumber(n: number): string
	local digits = tostring(math.floor(n))
	local result = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if result:sub(1, 1) == "," then
		result = result:sub(2)
	end
	return result
end

local function initials(name: string): string
	local letters = {}
	for word in string.gmatch(name, "%a+") do
		table.insert(letters, string.sub(word, 1, 1))
	end
	return string.upper(string.sub(table.concat(letters), 1, 2))
end

local function columnZs(): { number }
	local zs = {}
	for z = FIRST_COLUMN_Z, LAST_COLUMN_Z, BAY do
		table.insert(zs, z)
	end
	return zs
end

-- Floor ------------------------------------------------------------------------------------------

local function buildFloor(model: Model)
	local floor = folder(model, "Floor")
	local length = Z_SOUTH - Z_NORTH
	local midZ = (Z_NORTH + Z_SOUTH) / 2
	local halfOuter = WALL_X + WALL_THICKNESS
	block(floor, "Slab", Vector3.new(halfOuter * 2, 2, length + WALL_THICKNESS * 2), CFrame.new(0, -1, midZ), PALETTE.Floor, Enum.Material.Pavement)

	-- Flagstone joints on the courtyard either side of the avenue.
	local joints = folder(floor, "Joints")
	local sideInner, sideOuter = PATH_WIDTH / 2 + 0.6, COLUMN_X - 2
	for _, sx in { -1, 1 } do
		for x = sideInner + FLAGSTONE, sideOuter - 1, FLAGSTONE do
			decor(block(joints, "JointZ", Vector3.new(0.15, 0.04, length), CFrame.new(sx * x, 0.02, midZ), PALETTE.FloorJoint, Enum.Material.Slate))
		end
		for z = Z_NORTH + FLAGSTONE, Z_SOUTH - 1, FLAGSTONE do
			decor(block(joints, "JointX", Vector3.new(sideOuter - sideInner, 0.04, 0.15), CFrame.new(sx * (sideInner + sideOuter) / 2, 0.02, z), PALETTE.FloorJoint, Enum.Material.Slate))
		end
	end

	-- The avenue: large slate slabs between basalt curbs, with basalt inlay bands at each pedestal row.
	local avenue = folder(floor, "Avenue")
	local avenueLength = PATH_SOUTH - PATH_NORTH
	local avenueZ = (PATH_NORTH + PATH_SOUTH) / 2
	block(avenue, "Paving", Vector3.new(PATH_WIDTH, 0.12, avenueLength), CFrame.new(0, 0.06, avenueZ), PALETTE.Avenue, Enum.Material.Slate)
	decor(block(avenue, "CenterJoint", Vector3.new(0.12, 0.02, avenueLength), CFrame.new(0, 0.13, avenueZ), PALETTE.FloorJoint, Enum.Material.Slate))
	for z = PATH_NORTH + 4, PATH_SOUTH - 1, 4 do
		decor(block(avenue, "CrossJoint", Vector3.new(PATH_WIDTH, 0.02, 0.12), CFrame.new(0, 0.13, z), PALETTE.FloorJoint, Enum.Material.Slate))
	end
	for _, sx in { -1, 1 } do
		block(avenue, "Curb", Vector3.new(0.6, 0.25, avenueLength), CFrame.new(sx * (PATH_WIDTH / 2 + 0.3), 0.125, avenueZ), PALETTE.Trim, Enum.Material.Basalt)
	end
	for _, z in PEDESTAL_ZS do
		decor(block(avenue, "Inlay", Vector3.new(PATH_WIDTH, 0.03, 0.6), CFrame.new(0, 0.135, z), PALETTE.Trim, Enum.Material.Basalt))
		decor(block(avenue, "InlayBrass", Vector3.new(PATH_WIDTH, 0.035, 0.14), CFrame.new(0, 0.14, z), PALETTE.Brass, Enum.Material.Metal))
	end
end

local function buildArrival(model: Model)
	local plaza = folder(model, "Arrival")
	decor(disc(plaza, "Ring", 0.16, 23, Vector3.new(0, 0.08, ARRIVAL_Z), PALETTE.Trim, Enum.Material.Basalt))
	decor(disc(plaza, "Plaza", 0.2, 21, Vector3.new(0, 0.1, ARRIVAL_Z), PALETTE.Avenue, Enum.Material.Slate))
	decor(disc(plaza, "BrassRing", 0.24, 8, Vector3.new(0, 0.12, ARRIVAL_Z), PALETTE.Brass, Enum.Material.Metal))
	decor(disc(plaza, "Center", 0.26, 7.4, Vector3.new(0, 0.13, ARRIVAL_Z), PALETTE.Marble, Enum.Material.Marble))
	decor(block(plaza, "Compass", Vector3.new(3, 0.28, 3), CFrame.new(0, 0.14, ARRIVAL_Z) * CFrame.Angles(0, math.rad(45), 0), PALETTE.Brass, Enum.Material.Metal))

	local spawns = folder(model, "SpawnPoints")
	local offsets = { Vector3.new(-4, 0, -2), Vector3.new(4, 0, -2), Vector3.new(-4, 0, 3), Vector3.new(4, 0, 3) }
	for i, offset in offsets do
		-- Face north, straight down the avenue toward the bubbles and the gate.
		local position = Vector3.new(0, 0.8, ARRIVAL_Z) + offset
		local marker = block(spawns, "LobbySpawn" .. i, Vector3.new(2, 1, 2), CFrame.lookAt(position, position + Vector3.new(0, 0, -1)), PALETTE.Avenue, Enum.Material.SmoothPlastic)
		hide(decor(marker))
	end
end

-- Walls and colonnades ---------------------------------------------------------------------------

local function sconce(parent: Instance, position: Vector3, outward: Vector3)
	-- `outward` points from the wall into the courtyard.
	decor(block(parent, "SconceBracket", Vector3.new(0.3, 0.3, 0.3) + outward:Abs() * 0.8, CFrame.new(position + outward * 0.5), PALETTE.Iron, Enum.Material.Metal))
	local lamp = decor(block(parent, "SconceGlass", Vector3.new(0.7, 1, 0.7), CFrame.new(position + outward * 1.1 + Vector3.new(0, 0.5, 0)), PALETTE.LampGlass, Enum.Material.Neon))
	lamp.Transparency = 0.35
	glow(lamp, PALETTE.LampGlow, 12, 0.9)
	decor(block(parent, "SconceCap", Vector3.new(0.95, 0.2, 0.95), CFrame.new(position + outward * 1.1 + Vector3.new(0, 1.1, 0)), PALETTE.Iron, Enum.Material.Metal))
end

local function banner(parent: Instance, x: number, z: number, sx: number)
	-- Hangs flat against the side wall at `x` (the wall face), `sx` = -1 west wall, +1 east wall.
	local inward = -sx
	decor(block(parent, "BannerRod", Vector3.new(0.35, 0.35, 5), CFrame.new(x + inward * 0.5, 16.8, z), PALETTE.Iron, Enum.Material.Metal))
	decor(block(parent, "Banner", Vector3.new(0.2, 9, 4.2), CFrame.new(x + inward * 0.2, 12, z), PALETTE.Banner, Enum.Material.Fabric))
	decor(block(parent, "BannerTrim", Vector3.new(0.24, 0.35, 4.26), CFrame.new(x + inward * 0.2, 8.2, z), PALETTE.Brass, Enum.Material.Fabric))
	decor(block(parent, "BannerEmblem", Vector3.new(0.26, 1.6, 1.6), CFrame.new(x + inward * 0.25, 12.8, z) * CFrame.Angles(math.rad(45), 0, 0), PALETTE.Brass, Enum.Material.Metal))
end

local function column(parent: Instance, x: number, z: number)
	local y = WALK_STEP
	block(parent, "ColumnPlinth", Vector3.new(3, COLUMN_PLINTH, 3), CFrame.new(x, y + COLUMN_PLINTH / 2, z), PALETTE.Trim, Enum.Material.Basalt)
	y += COLUMN_PLINTH
	disc(parent, "ColumnTorus", COLUMN_TORUS, 2.8, Vector3.new(x, y + COLUMN_TORUS / 2, z), PALETTE.Marble, Enum.Material.Marble)
	y += COLUMN_TORUS
	disc(parent, "ColumnShaft", SHAFT_HEIGHT, 2.2, Vector3.new(x, y + SHAFT_HEIGHT / 2, z), PALETTE.Marble, Enum.Material.Marble)
	y += SHAFT_HEIGHT
	disc(parent, "ColumnEchinus", COLUMN_ECHINUS, 2.8, Vector3.new(x, y + COLUMN_ECHINUS / 2, z), PALETTE.Marble, Enum.Material.Marble)
	y += COLUMN_ECHINUS
	block(parent, "ColumnAbacus", Vector3.new(3.2, COLUMN_ABACUS, 3.2), CFrame.new(x, y + COLUMN_ABACUS / 2, z), PALETTE.WallLight, Enum.Material.Limestone)
end

-- One long side: wall, covered walkway, column row with entablature, pilasters, banners and sconces.
local function buildColonnade(parent: Instance, sx: number)
	local side = Instance.new("Model")
	side.Name = if sx < 0 then "ColonnadeWest" else "ColonnadeEast"
	local length = Z_SOUTH - Z_NORTH
	local midZ = (Z_NORTH + Z_SOUTH) / 2

	block(side, "Wall", Vector3.new(WALL_THICKNESS, WALL_HEIGHT, length + WALL_THICKNESS * 2), CFrame.new(sx * (WALL_X + WALL_THICKNESS / 2), WALL_HEIGHT / 2, midZ), PALETTE.Wall, Enum.Material.Limestone)
	block(side, "WallCornice", Vector3.new(WALL_THICKNESS + 2, 1.2, length + WALL_THICKNESS * 2), CFrame.new(sx * (WALL_X + WALL_THICKNESS / 2 - 1), WALL_HEIGHT + 0.6, midZ), PALETTE.WallLight, Enum.Material.Limestone)
	block(side, "WallPlinth", Vector3.new(0.8, 2.4, length), CFrame.new(sx * (WALL_X - 0.4), WALK_STEP + 1.2, midZ), PALETTE.Trim, Enum.Material.Basalt)
	block(side, "StringCourse", Vector3.new(0.8, 0.8, length), CFrame.new(sx * (WALL_X - 0.4), 22, midZ), PALETTE.WallLight, Enum.Material.Limestone)

	-- Covered walkway: one low step up, roofed at entablature height.
	local walkInner = COLUMN_X - 2
	block(side, "Walkway", Vector3.new(WALL_X - walkInner, WALK_STEP, length), CFrame.new(sx * (walkInner + WALL_X) / 2, WALK_STEP / 2, midZ), PALETTE.Avenue, Enum.Material.Slate)
	-- The nosing stands 0.05 proud of the step face: coplanar faces z-fight (flicker) in the renderer.
	block(side, "WalkwayNosing", Vector3.new(0.5, WALK_STEP + 0.05, length), CFrame.new(sx * (walkInner + 0.2), (WALK_STEP + 0.05) / 2, midZ), PALETTE.Trim, Enum.Material.Basalt)
	local roofY = COLUMN_TOP + ARCHITRAVE_H + FRIEZE_H / 2
	block(side, "WalkwayRoof", Vector3.new(WALL_X - COLUMN_X, 0.8, length), CFrame.new(sx * (COLUMN_X + WALL_X) / 2, roofY, midZ), PALETTE.Wall, Enum.Material.Limestone)

	-- Entablature carried by the columns.
	local y = COLUMN_TOP
	block(side, "Architrave", Vector3.new(3.2, ARCHITRAVE_H, length), CFrame.new(sx * COLUMN_X, y + ARCHITRAVE_H / 2, midZ), PALETTE.WallLight, Enum.Material.Limestone)
	y += ARCHITRAVE_H
	block(side, "Frieze", Vector3.new(2.8, FRIEZE_H, length), CFrame.new(sx * COLUMN_X, y + FRIEZE_H / 2, midZ), PALETTE.Wall, Enum.Material.Limestone)
	y += FRIEZE_H
	block(side, "Cornice", Vector3.new(4, CORNICE_H, length), CFrame.new(sx * COLUMN_X, y + CORNICE_H / 2, midZ), PALETTE.WallLight, Enum.Material.Limestone)

	local pilasterBottom, pilasterTop = WALK_STEP + 2.4, 21.6
	for i, z in columnZs() do
		column(side, sx * COLUMN_X, z)
		block(side, "Pilaster", Vector3.new(0.8, pilasterTop - pilasterBottom, 2.4), CFrame.new(sx * (WALL_X - 0.4), (pilasterBottom + pilasterTop) / 2, z), PALETTE.WallLight, Enum.Material.Limestone)
		local bayZ = z + BAY / 2
		if i % 2 == 0 and bayZ < Z_SOUTH - 2 then
			banner(side, sx * WALL_X, bayZ, sx)
		elseif i % 2 == 1 then
			sconce(side, Vector3.new(sx * (WALL_X - 0.8), 9, z), Vector3.new(-sx, 0, 0))
		end
	end
	side.Parent = parent
end

-- An end wall across the courtyard. `innerZ` is its courtyard face, `inward` points into the courtyard.
local function buildEndWall(parent: Instance, name: string, innerZ: number, inward: number, gapHalfWidth: number)
	local wall = Instance.new("Model")
	wall.Name = name
	local width = (WALL_X + WALL_THICKNESS) * 2
	block(wall, "Wall", Vector3.new(width, WALL_HEIGHT, WALL_THICKNESS), CFrame.new(0, WALL_HEIGHT / 2, innerZ - inward * WALL_THICKNESS / 2), PALETTE.Wall, Enum.Material.Limestone)
	block(wall, "WallCornice", Vector3.new(width + 2, 1.2, WALL_THICKNESS + 2), CFrame.new(0, WALL_HEIGHT + 0.6, innerZ - inward * (WALL_THICKNESS / 2 - 1)), PALETTE.WallLight, Enum.Material.Limestone)
	block(wall, "WallPlinth", Vector3.new(WALL_X * 2, 2.4, 0.8), CFrame.new(0, 1.2, innerZ + inward * 0.4), PALETTE.Trim, Enum.Material.Basalt)
	block(wall, "StringCourse", Vector3.new(WALL_X * 2, 0.8, 0.8), CFrame.new(0, 22, innerZ + inward * 0.4), PALETTE.WallLight, Enum.Material.Limestone)
	for x = -COLUMN_X + BAY / 2, COLUMN_X - BAY / 2, BAY do
		if math.abs(x) > gapHalfWidth then
			block(wall, "Pilaster", Vector3.new(2.4, 19.2, 0.8), CFrame.new(x, 12, innerZ + inward * 0.4), PALETTE.WallLight, Enum.Material.Limestone)
		end
	end
	wall.Parent = parent
	return wall
end

-- The sealed harbour gate in the south wall (decorative).
local function buildSouthGate(parent: Instance)
	local gate = Instance.new("Model")
	gate.Name = "HarborGate"
	local inward = -1
	local faceZ = Z_SOUTH
	for _, sx in { -1, 1 } do
		block(gate, "Jamb", Vector3.new(2.4, 18, 1.6), CFrame.new(sx * 7.2, 9, faceZ + inward * 0.8), PALETTE.WallLight, Enum.Material.Limestone)
		sconce(gate, Vector3.new(sx * 9.6, 10, faceZ + inward * 0.2), Vector3.new(0, 0, inward)) -- between jamb and pilaster
	end
	block(gate, "Lintel", Vector3.new(17, 2.4, 1.8), CFrame.new(0, 19.2, faceZ + inward * 0.9), PALETTE.WallLight, Enum.Material.Limestone)
	block(gate, "LintelBand", Vector3.new(17.1, 0.3, 1.9), CFrame.new(0, 18.1, faceZ + inward * 0.9), PALETTE.Brass, Enum.Material.Metal)
	block(gate, "Door", Vector3.new(12, 18, 0.5), CFrame.new(0, 9, faceZ + inward * 0.25), PALETTE.Wood, Enum.Material.WoodPlanks)
	for _, y in { 3.5, 9, 14.5 } do
		decor(block(gate, "DoorBand", Vector3.new(12.06, 0.4, 0.6), CFrame.new(0, y, faceZ + inward * 0.3), PALETTE.Iron, Enum.Material.Metal))
	end
	decor(block(gate, "DoorSeam", Vector3.new(0.2, 18, 0.6), CFrame.new(0, 9, faceZ + inward * 0.3), PALETTE.Iron, Enum.Material.Metal))
	gate.Parent = parent
end

-- Segmental stone arch spanning the avenue from colonnade to colonnade.
local function buildArch(parent: Instance, index: number, z: number)
	local arch = Instance.new("Model")
	arch.Name = "Arch" .. index
	local halfSpan = COLUMN_X
	local radius = (halfSpan * halfSpan + ARCH_RISE * ARCH_RISE) / (2 * ARCH_RISE)
	local springY = ENTABLATURE_TOP + 1.4
	local centerY = springY + ARCH_RISE - radius
	local theta = math.asin(halfSpan / radius)
	local segment = 2 * theta * radius / ARCH_SEGMENTS
	for _, sx in { -1, 1 } do
		decor(block(arch, "Springer", Vector3.new(3.6, 1.4, 3.6), CFrame.new(sx * halfSpan, ENTABLATURE_TOP + 0.7, z), PALETTE.WallLight, Enum.Material.Limestone))
	end
	for s = 0, ARCH_SEGMENTS - 1 do
		local a = -theta + (s + 0.5) * (2 * theta / ARCH_SEGMENTS)
		local position = Vector3.new(radius * math.sin(a), centerY + radius * math.cos(a), z)
		-- Rotating about Z by -a lays the block's X axis along the arch's tangent.
		decor(block(arch, "Voussoir" .. s, Vector3.new(segment + 0.15, 2.2, 3), CFrame.new(position) * CFrame.Angles(0, 0, -a), PALETTE.WallLight, Enum.Material.Limestone))
	end
	decor(block(arch, "Keystone", Vector3.new(2.2, 3.2, 3.6), CFrame.new(0, springY + ARCH_RISE, z), PALETTE.Marble, Enum.Material.Marble))
	arch.Parent = parent
end

-- Courtyard furniture ----------------------------------------------------------------------------

local function cypress(parent: Instance, name: string, x: number, z: number)
	local tree = Instance.new("Model")
	tree.Name = name
	block(tree, "Planter", Vector3.new(3.6, 1.2, 3.6), CFrame.new(x, 0.6, z), PALETTE.Wall, Enum.Material.Limestone)
	block(tree, "PlanterRim", Vector3.new(3.9, 0.25, 3.9), CFrame.new(x, 1.3, z), PALETTE.Trim, Enum.Material.Basalt)
	decor(block(tree, "Soil", Vector3.new(3.2, 0.1, 3.2), CFrame.new(x, 1.35, z), PALETTE.Soil, Enum.Material.Ground))
	decor(disc(tree, "Trunk", 2.4, 0.5, Vector3.new(x, 2.5, z), PALETTE.Wood, Enum.Material.Wood))
	-- A tall, narrow evergreen: overlapping foliage masses that taper toward the tip.
	local masses = { { 3.6, 4.6 }, { 3.3, 6.8 }, { 2.9, 8.8 }, { 2.4, 10.6 }, { 1.8, 12.1 } }
	for i, mass in masses do
		local nudge = ((i * 3 + math.floor(z)) % 3 - 1) * 0.15 -- small deterministic irregularity
		decor(ball(tree, "Foliage" .. i, mass[1], Vector3.new(x + nudge, mass[2], z - nudge), if i % 2 == 0 then PALETTE.Leaf2 else PALETTE.Leaf, Enum.Material.Grass))
	end
	tree.Parent = parent
end

local function lampPost(parent: Instance, name: string, x: number, z: number)
	local lamp = Instance.new("Model")
	lamp.Name = name
	block(lamp, "Base", Vector3.new(1.2, 0.5, 1.2), CFrame.new(x, 0.25, z), PALETTE.Trim, Enum.Material.Basalt)
	block(lamp, "Pole", Vector3.new(0.35, 7, 0.35), CFrame.new(x, 4, z), PALETTE.Iron, Enum.Material.Metal)
	decor(block(lamp, "Collar", Vector3.new(0.6, 0.2, 0.6), CFrame.new(x, 7.45, z), PALETTE.Iron, Enum.Material.Metal))
	local glass = decor(block(lamp, "Glass", Vector3.new(0.9, 1.2, 0.9), CFrame.new(x, 8.15, z), PALETTE.LampGlass, Enum.Material.Neon))
	glass.Transparency = 0.35
	glow(glass, PALETTE.LampGlow, 18, 1.2)
	decor(block(lamp, "Cap", Vector3.new(1.2, 0.25, 1.2), CFrame.new(x, 8.88, z), PALETTE.Iron, Enum.Material.Metal))
	decor(ball(lamp, "Finial", 0.35, Vector3.new(x, 9.15, z), PALETTE.Iron, Enum.Material.Metal))
	lamp.Parent = parent
end

-- Character bubbles and pedestals ----------------------------------------------------------------

local function buildBubble(anchor: BasePart, def: any)
	local tierColor = TIER_COLORS[def.tier]
	local gui = Instance.new("BillboardGui")
	gui.Name = "Bubble"
	-- BillboardGui scale units are studs: 9 wide, 12.4 tall (name + circle + price).
	gui.Size = UDim2.fromScale(BUBBLE_STUDS, BUBBLE_STUDS * 1.38)
	gui.LightInfluence = 0
	gui.MaxDistance = 220
	gui.AlwaysOnTop = false
	gui.ClipsDescendants = false -- long names may run slightly wider than the bubble
	gui.Adornee = anchor
	gui.Parent = anchor

	local nameText = Instance.new("TextLabel")
	nameText.Name = "Name"
	nameText.BackgroundTransparency = 1
	nameText.Size = UDim2.fromScale(1.3, 0.14)
	nameText.Position = UDim2.fromScale(-0.15, 0)
	nameText.FontFace = DISPLAY_FONT
	nameText.TextScaled = true
	nameText.TextColor3 = Color3.fromRGB(236, 236, 232)
	nameText.TextStrokeTransparency = 0.35
	nameText.Text = string.upper(def.name)
	nameText.Parent = gui

	local circle = Instance.new("Frame")
	circle.Name = "Circle"
	circle.Size = UDim2.fromScale(1, 1 / 1.38)
	circle.Position = UDim2.fromScale(0, 0.145)
	circle.BackgroundColor3 = Color3.new(1, 1, 1)
	circle.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = circle
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(def.bubbleCenter, def.bubbleEdge)
	gradient.Rotation = 90
	gradient.Parent = circle
	local ring = Instance.new("UIStroke")
	ring.Color = Color3.new(1, 1, 1)
	ring.Thickness = 4
	ring.Parent = circle
	-- Fallback until the portrait is uploaded: big initials on the bubble colours.
	local fallback = Instance.new("TextLabel")
	fallback.Name = "Initials"
	fallback.BackgroundTransparency = 1
	fallback.Size = UDim2.fromScale(0.7, 0.7)
	fallback.Position = UDim2.fromScale(0.15, 0.15)
	fallback.FontFace = DISPLAY_FONT
	fallback.TextScaled = true
	fallback.TextColor3 = Color3.new(1, 1, 1)
	fallback.TextStrokeTransparency = 0.3
	fallback.Text = initials(def.name)
	fallback.Parent = circle
	local portrait = Instance.new("ImageLabel")
	portrait.Name = "Portrait"
	portrait.BackgroundTransparency = 1
	portrait.Size = UDim2.fromScale(1, 1)
	portrait.ScaleType = Enum.ScaleType.Fit
	portrait.Image = def.portrait or ""
	portrait.Visible = def.portrait ~= nil
	portrait.Parent = circle
	if def.portrait then
		fallback.Visible = false
		ring.Enabled = false -- the portrait image carries its own ring
		circle.BackgroundTransparency = 1
		gradient.Enabled = false
	end

	local price = Instance.new("TextLabel")
	price.Name = "Price"
	price.BackgroundTransparency = 1
	price.Size = UDim2.fromScale(1, 0.12)
	price.Position = UDim2.fromScale(0, 0.88)
	price.FontFace = DISPLAY_FONT
	price.TextScaled = true
	price.TextColor3 = tierColor
	price.TextStrokeTransparency = 0.35
	price.Text = if def.tier == "Free"
		then "FREE"
		elseif def.tier == "Robux" then "ROBUX"
		else formatNumber(def.yenPrice) .. " ¥"
	price.Parent = gui
end

-- Limestone pedestal on a basalt plinth, with a thin tier-coloured inlay line, a marble dais,
-- a bubble above it and an Inspect prompt.
local function buildPedestal(parent: Instance, def: any, position: Vector3)
	local model = Instance.new("Model")
	model.Name = string.format("Podium%02d_%s", def.slot, def.id)
	model:SetAttribute("CharacterId", def.id)
	model:SetAttribute("Slot", def.slot)
	model:SetAttribute("Tier", def.tier)

	local raise = if def.tier == "Robux" then 0.8 else 0
	local plinthH = 0.8 + raise
	block(model, "Plinth", Vector3.new(9, plinthH, 9), CFrame.new(position + Vector3.new(0, plinthH / 2, 0)), PALETTE.Trim, Enum.Material.Basalt)
	local bodyBottom = plinthH
	block(model, "Body", Vector3.new(7, 3, 7), CFrame.new(position + Vector3.new(0, bodyBottom + 1.5, 0)), PALETTE.Wall, Enum.Material.Limestone)
	decor(block(model, "Skirting", Vector3.new(7.2, 0.4, 7.2), CFrame.new(position + Vector3.new(0, bodyBottom + 0.2, 0)), PALETTE.Trim, Enum.Material.Basalt))
	decor(block(model, "TierInlay", Vector3.new(7.14, 0.16, 7.14), CFrame.new(position + Vector3.new(0, bodyBottom + 2.55, 0)), TIER_COLORS[def.tier], Enum.Material.Neon))
	local top = bodyBottom + 3
	local dais = block(model, "Dais", Vector3.new(8.2, 0.6, 8.2), CFrame.new(position + Vector3.new(0, top + 0.3, 0)), PALETTE.Marble, Enum.Material.Marble)

	-- The bubble hovers above the pedestal.
	local anchor = block(model, "BubbleAnchor", Vector3.one, CFrame.new(position + Vector3.new(0, top + 0.6 + BUBBLE_STUDS * 0.69 + 0.5, 0)), PALETTE.Wall, Enum.Material.SmoothPlastic)
	hide(decor(anchor))
	buildBubble(anchor, def)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Inspect"
	prompt.ObjectText = def.name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 13
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("CharacterId", def.id)
	prompt.Parent = dais

	model.PrimaryPart = dais
	model.Parent = parent
end

-- The FIGHT gate ---------------------------------------------------------------------------------

local function brazier(parent: Instance, x: number, z: number, groundY: number)
	block(parent, "BrazierStand", Vector3.new(1.8, 3, 1.8), CFrame.new(x, groundY + 1.5, z), PALETTE.Trim, Enum.Material.Basalt)
	decor(disc(parent, "BrazierBowl", 0.8, 3, Vector3.new(x, groundY + 3.4, z), PALETTE.Iron, Enum.Material.Metal))
	decor(disc(parent, "BrazierEmbers", 0.3, 2.4, Vector3.new(x, groundY + 3.85, z), PALETTE.PortalCore, Enum.Material.Neon))
	local flame = decor(ball(parent, "BrazierFlame", 1.4, Vector3.new(x, groundY + 4.4, z), PALETTE.Portal, Enum.Material.Neon))
	flame.Transparency = 0.3
	glow(flame, PALETTE.Portal, 16, 1.5)
end

local function buildPortal(model: Model)
	local portal = Instance.new("Model")
	portal.Name = "FightPortal"

	-- Three broad steps up to the gate, set against the north wall.
	local steps = { { 26, 18 }, { 22, 15 }, { 18, 12 } }
	for i, step in steps do
		local depth = step[2]
		block(portal, "Step" .. i, Vector3.new(step[1], 0.5, depth), CFrame.new(0, 0.25 + (i - 1) * 0.5, Z_NORTH + depth / 2), PALETTE.Avenue, Enum.Material.Slate)
		-- Slightly wider and deeper than the step so no face is coplanar with it (no z-fighting).
		decor(block(portal, "StepNosing" .. i, Vector3.new(step[1] + 0.06, 0.52, 0.34), CFrame.new(0, 0.26 + (i - 1) * 0.5, Z_NORTH + depth - 0.15), PALETTE.Trim, Enum.Material.Basalt))
	end
	local floorY = 0.5 * #steps

	-- Two pylons and a lintel frame the portal field.
	local pylonX, pylonH = 9.5, 20
	for _, sx in { -1, 1 } do
		block(portal, "PylonBase", Vector3.new(5, 1.6, 6), CFrame.new(sx * pylonX, floorY + 0.8, GATE_Z), PALETTE.Trim, Enum.Material.Basalt)
		block(portal, "Pylon", Vector3.new(4, pylonH, 5), CFrame.new(sx * pylonX, floorY + 1.6 + pylonH / 2, GATE_Z), PALETTE.WallLight, Enum.Material.Limestone)
		block(portal, "PylonCapital", Vector3.new(5, 1.2, 6), CFrame.new(sx * pylonX, floorY + 1.6 + pylonH + 0.6, GATE_Z), PALETTE.Wall, Enum.Material.Limestone)
		block(portal, "Jamb", Vector3.new(0.8, 21.8, 1.2), CFrame.new(sx * 7.1, floorY + 10.9, GATE_Z), PALETTE.Trim, Enum.Material.Basalt)
		brazier(portal, sx * 12, -104, 0.5) -- on the bottom step, clear of the upper steps and the pylon base
	end
	local lintelY = floorY + 1.6 + pylonH + 1.2 + 1.5
	local lintel = block(portal, "Lintel", Vector3.new(24, 3, 6), CFrame.new(0, lintelY, GATE_Z), PALETTE.WallLight, Enum.Material.Limestone)
	decor(block(portal, "LintelBand", Vector3.new(24.2, 0.34, 6.2), CFrame.new(0, lintelY - 1.35, GATE_Z), PALETTE.Brass, Enum.Material.Metal))
	block(portal, "FrameHead", Vector3.new(15, 0.8, 1.2), CFrame.new(0, floorY + 21.4, GATE_Z), PALETTE.Trim, Enum.Material.Basalt)

	-- The field: a shimmering energy surface (ForceField material animates on its own) over a dark
	-- ember core, so the doorway has depth instead of reading as a flat orange slab.
	local fieldH = 21
	local field = block(portal, "PortalGlow", Vector3.new(13.4, fieldH, 0.4), CFrame.new(0, floorY + fieldH / 2, GATE_Z), PALETTE.Portal, Enum.Material.ForceField)
	field.Transparency = 0
	field.CanCollide = false
	glow(field, PALETTE.Portal, 26, 3)
	decor(block(portal, "PortalCore", Vector3.new(13.4, fieldH, 0.3), CFrame.new(0, floorY + fieldH / 2, GATE_Z - 0.5), PALETTE.PortalCore, Enum.Material.Neon))

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Join the fight"
	prompt.ObjectText = "FIGHT"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Action", "Fight")
	prompt.Parent = field

	-- Sign on the lintel face that looks back down the avenue (+Z is the part's Back face).
	local sign = Instance.new("SurfaceGui")
	sign.Face = Enum.NormalId.Back
	sign.LightInfluence = 0
	sign.PixelsPerStud = 40
	sign.Parent = lintel
	local signText = Instance.new("TextLabel")
	signText.BackgroundTransparency = 1
	signText.Size = UDim2.fromScale(1, 0.8)
	signText.Position = UDim2.fromScale(0, 0.1)
	signText.FontFace = DISPLAY_FONT
	signText.TextScaled = true
	signText.TextColor3 = Color3.fromRGB(58, 40, 30)
	signText.Text = "FIGHT"
	signText.Parent = sign

	-- Floating marker so the call to action reads from the arrival plaza.
	local beacon = Instance.new("BillboardGui")
	beacon.Name = "Beacon"
	beacon.Size = UDim2.fromOffset(160, 44)
	beacon.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	beacon.MaxDistance = 300
	beacon.LightInfluence = 0
	beacon.Parent = lintel
	local beaconText = Instance.new("TextLabel")
	beaconText.BackgroundTransparency = 1
	beaconText.Size = UDim2.fromScale(1, 1)
	beaconText.FontFace = DISPLAY_FONT
	beaconText.TextScaled = true
	beaconText.TextColor3 = PALETTE.Portal
	beaconText.TextStrokeTransparency = 0.4
	beaconText.Text = "FIGHT"
	beaconText.Parent = beacon

	portal.PrimaryPart = lintel
	portal.Parent = model
end

function Lobby.build(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Lobby"
	model:SetAttribute("DisplayName", "The Still Harbor")

	local root = block(model, "Root", Vector3.one, CFrame.new(0, 0, 0), PALETTE.Avenue, Enum.Material.SmoothPlastic)
	hide(decor(root))
	model.PrimaryPart = root

	buildFloor(model)
	buildArrival(model)

	-- Walls on all four sides (owner: no water visible from the courtyard).
	local walls = folder(model, "Walls")
	buildColonnade(walls, -1)
	buildColonnade(walls, 1)
	buildEndWall(walls, "NorthWall", Z_NORTH, 1, 12)
	buildEndWall(walls, "SouthWall", Z_SOUTH, -1, 9)
	buildSouthGate(walls)

	local arches = folder(model, "Arches")
	for i, z in ARCH_ZS do
		buildArch(arches, i, z)
	end

	local podiums = folder(model, "Podiums")
	for _, def in CharacterDefs.list do
		local row = math.ceil(def.slot / 2)
		local side = if def.slot % 2 == 1 then -1 else 1 -- odd slots west, even slots east
		buildPedestal(podiums, def, Vector3.new(side * PEDESTAL_X, 0, PEDESTAL_ZS[row]))
	end

	local garden = folder(model, "Cypresses")
	for i, z in CYPRESS_ZS do
		cypress(garden, "CypressW" .. i, -PEDESTAL_X, z)
		cypress(garden, "CypressE" .. i, PEDESTAL_X, z)
	end

	local lamps = folder(model, "Lamps")
	for i, z in LAMP_ZS do
		lampPost(lamps, "LampW" .. i, -LAMP_X, z)
		lampPost(lamps, "LampE" .. i, LAMP_X, z)
	end

	buildPortal(model)

	model.Parent = parent
	return model
end

-- Sea around the harbour. Terrain is global, so this is separate from build(). The walls hide it
-- from the courtyard; it only shows if the camera is pulled far up.
function Lobby.buildTerrain(origin: CFrame)
	workspace.Terrain:FillBlock(origin * CFrame.new(0, -9, 0), Vector3.new(900, 16, 900), Enum.Material.Water)
end

return Lobby
