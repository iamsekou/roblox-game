-- Training Grounds map (owner, 2026-09-29): "a fully fleshed out dojo with an open training ground".
--
-- A walled compound. North: the dojo hall, a raised wooden hall with a tatami floor, pillars, shoji walls and
-- sliding doors, a gabled tile roof; inside, hanging scrolls, a shrine shelf, weapon racks, a taiko drum, paper
-- lanterns and the TRAINING BOARD (the training menu's prompt). Fighters wait in the hall between rounds
-- (SpawnPoints). South: the open training ground on sand, where every fight happens: a stone sparring ring in
-- the middle, two roped wooden platforms, straw practice dummies, bamboo groves, rock outcrops, low wooden
-- fences, a well, archery targets, a field of stepping posts, cherry trees shedding petals, stone lanterns along the path, and a koi pond crossed by an
-- arched red bridge. A torii and the closed gate stand in the south wall; invisible barriers keep everyone in.
--
-- Scale: avatar ~5 studs, doors ~13 studs tall (fighters run at 24 studs/s, so spaces are generous).
-- Cover heights: TALL (>= 8 studs: rocks, bamboo, platforms' corners no) hides a fighter and plate; LOW hides the body.
--
-- Map contract (docs/DESIGN.md): unrotated PrimaryPart at floor level; SpawnArea boxes over the training ground
-- (spawns only on terrain or parts tagged Walkable); buildTerrain / clearTerrain. Also: SpawnPoints (the hall,
-- where fighters wait between rounds) and TrainingBoard (a ProximityPrompt with Action = "Training").
-- Built around the origin; MapService pivots it. -Z = north (the hall), +Z = south (the gate).
-- All parts are anchored static geometry. Randomness uses a fixed seed: the same map every build.

local Dojo = {}

local HALL_X = 42 -- half width of the hall
local HALL_NORTH, HALL_SOUTH = -94, -44 -- the hall's back and front walls (z)
local DECK = 1.5 -- the hall floor's height
local WALL_TOP = 19.5 -- top of the hall's walls
local RIDGE = 34 -- roof ridge height
local EAVE = 4 -- roof overhang
local YARD_X, YARD_NORTH, YARD_SOUTH = 90, -100, 100 -- the compound wall's centre lines
local COMPOUND_WALL = 14
local BARRIER_HEIGHT = 80
local POND = { x = 54, z = 64, radius = 13 }
local SEED = 20260929

local PALETTE = {
	Wood = Color3.fromRGB(150, 104, 64),
	WoodDark = Color3.fromRGB(74, 50, 36),
	Plaster = Color3.fromRGB(234, 228, 214),
	Stone = Color3.fromRGB(128, 124, 116),
	StoneLight = Color3.fromRGB(168, 162, 150),
	Tile = Color3.fromRGB(58, 62, 72),
	Tatami = Color3.fromRGB(198, 186, 124),
	TatamiEdge = Color3.fromRGB(52, 58, 44),
	Shoji = Color3.fromRGB(244, 240, 226),
	Lacquer = Color3.fromRGB(176, 42, 36),
	Ink = Color3.fromRGB(26, 24, 24),
	Straw = Color3.fromRGB(206, 176, 104),
	Bamboo = Color3.fromRGB(110, 152, 72),
	BambooLeaf = Color3.fromRGB(82, 128, 58),
	Trunk = Color3.fromRGB(88, 60, 48),
	Blossom = Color3.fromRGB(246, 184, 206),
	Blossom2 = Color3.fromRGB(232, 150, 182),
	Rock = Color3.fromRGB(116, 112, 104),
	Water = Color3.fromRGB(64, 128, 150),
	Mud = Color3.fromRGB(70, 66, 52),
	Lantern = Color3.fromRGB(255, 214, 150),
	Koi = Color3.fromRGB(240, 120, 40),
}

-- Helpers ---------------------------------------------------------------------------------------------

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

local function wedge(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): WedgePart
	local part = Instance.new("WedgePart")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
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

local function blocksSight(part: BasePart): BasePart
	part:SetAttribute("BlocksSight", true)
	return part
end

local function hide(part: BasePart): BasePart
	part.Transparency = 1
	part.CastShadow = false
	return part
end

local function walkable(part: BasePart): BasePart
	part:SetAttribute("Walkable", true)
	return part
end

local function light(part: BasePart, range: number, brightness: number)
	local lamp = Instance.new("PointLight")
	lamp.Color = PALETTE.Lantern
	lamp.Range = range
	lamp.Brightness = brightness
	lamp.Shadows = false
	lamp.Parent = part
end

-- The dojo hall -----------------------------------------------------------------------------------------

local function buildHallShell(hall: Instance)
	local depth = HALL_SOUTH - HALL_NORTH
	local midZ = (HALL_NORTH + HALL_SOUTH) / 2
	local width = HALL_X * 2

	-- Deck and its front steps.
	walkable(block(hall, "Deck", Vector3.new(width + 4, DECK, depth + 4), CFrame.new(0, DECK / 2, midZ), PALETTE.Wood, Enum.Material.WoodPlanks))
	for i, rise in { DECK * 2 / 3, DECK / 3 } do
		walkable(block(hall, "Step" .. i, Vector3.new(width - 8, rise, 2), CFrame.new(0, rise / 2, HALL_SOUTH + 2 + i * 2), PALETTE.WoodDark, Enum.Material.WoodPlanks))
	end

	-- Tatami: 8 x 4 mats with dark borders, alternating direction by row.
	local mats = folder(hall, "Tatami")
	local z = HALL_NORTH + 4
	local row = 0
	while z + 4 <= HALL_SOUTH - 4 do
		row += 1
		local x = -HALL_X + 4
		while x + 8 <= HALL_X - 4 do
			local c = CFrame.new(x + 4, DECK + 0.05, z + 2)
			decor(block(mats, "Mat", Vector3.new(7.8, 0.1, 3.8), c, PALETTE.Tatami, Enum.Material.Fabric))
			decor(block(mats, "Edge", Vector3.new(8, 0.08, 4), c * CFrame.new(0, -0.02, 0), PALETTE.TatamiEdge, Enum.Material.Fabric))
			x += 8
		end
		z += 4
	end

	-- Pillars round the walls every ~12 studs, a top plate on them, and the ceiling.
	local pillars = folder(hall, "Pillars")
	local function pillar(px: number, pz: number)
		block(pillars, "Pillar", Vector3.new(1.4, WALL_TOP - DECK, 1.4), CFrame.new(px, DECK + (WALL_TOP - DECK) / 2, pz), PALETTE.WoodDark, Enum.Material.Wood)
	end
	local bays = 7
	for i = 0, bays do
		local px = -HALL_X + i * (width / bays)
		pillar(px, HALL_NORTH)
		pillar(px, HALL_SOUTH)
	end
	for i = 1, 3 do
		local pz = HALL_NORTH + i * (depth / 4)
		pillar(-HALL_X, pz)
		pillar(HALL_X, pz)
	end
	for _, pz in { HALL_NORTH, HALL_SOUTH } do
		block(hall, "TopPlate", Vector3.new(width + 1.6, 1.2, 1.6), CFrame.new(0, WALL_TOP - 0.6, pz), PALETTE.WoodDark, Enum.Material.Wood)
	end
	for _, px in { -HALL_X, HALL_X } do
		block(hall, "TopPlate", Vector3.new(1.6, 1.2, depth + 1.6), CFrame.new(px, WALL_TOP - 0.6, midZ), PALETTE.WoodDark, Enum.Material.Wood)
	end
	block(hall, "Ceiling", Vector3.new(width, 0.4, depth), CFrame.new(0, WALL_TOP - 1, midZ), PALETTE.Wood, Enum.Material.WoodPlanks)
	for i = 1, 6 do
		decor(block(hall, "CeilingBeam", Vector3.new(width, 0.8, 0.8), CFrame.new(0, WALL_TOP - 1.6, HALL_NORTH + i * (depth / 7)), PALETTE.WoodDark, Enum.Material.Wood))
	end

	-- Back wall: plaster over a wooden wainscot.
	local wallH = WALL_TOP - DECK - 1.2
	block(hall, "BackWall", Vector3.new(width, wallH, 0.8), CFrame.new(0, DECK + wallH / 2, HALL_NORTH - 0.2), PALETTE.Plaster, Enum.Material.Plaster)
	decor(block(hall, "BackWainscot", Vector3.new(width, 4, 0.2), CFrame.new(0, DECK + 2, HALL_NORTH + 0.3), PALETTE.Wood, Enum.Material.WoodPlanks))

	-- Side walls: wainscot, plaster, and a band of shoji windows.
	for _, side in { -1, 1 } do
		local px = side * HALL_X
		block(hall, "SideWall", Vector3.new(0.8, wallH, depth), CFrame.new(px + side * 0.2, DECK + wallH / 2, midZ), PALETTE.Plaster, Enum.Material.Plaster)
		decor(block(hall, "SideWainscot", Vector3.new(0.2, 4, depth), CFrame.new(px - side * 0.3, DECK + 2, midZ), PALETTE.Wood, Enum.Material.WoodPlanks))
		for i = 0, 3 do
			local wz = HALL_NORTH + depth * (i + 0.5) / 4
			local windowCF = CFrame.new(px - side * 0.35, DECK + 10, wz)
			decor(block(hall, "Window", Vector3.new(0.1, 5, 8), windowCF, PALETTE.Shoji, Enum.Material.SmoothPlastic))
			for k = -1, 1 do
				decor(block(hall, "WindowBar", Vector3.new(0.15, 5, 0.15), windowCF * CFrame.new(-side * 0.05, 0, k * 2.6), PALETTE.WoodDark, Enum.Material.Wood))
			end
			decor(block(hall, "WindowBar", Vector3.new(0.15, 0.15, 8), windowCF * CFrame.new(-side * 0.05, 0, 0), PALETTE.WoodDark, Enum.Material.Wood))
		end
	end

	-- Front: sliding shoji doors in the outer bays; the three middle bays stand open.
	local bayWidth = width / bays
	for i = 0, bays - 1 do
		if i < 2 or i > 4 then
			local cx = -HALL_X + (i + 0.5) * bayWidth
			local doorH = wallH
			for half = -1, 1, 2 do
				local cf = CFrame.new(cx + half * bayWidth / 4, DECK + doorH / 2, HALL_SOUTH + half * 0.15)
				block(hall, "ShojiDoor", Vector3.new(bayWidth / 2, doorH, 0.25), cf, PALETTE.Shoji, Enum.Material.SmoothPlastic)
				for k = -1, 1 do
					decor(block(hall, "DoorBar", Vector3.new(0.15, doorH, 0.35), cf * CFrame.new(k * bayWidth / 6, 0, 0), PALETTE.WoodDark, Enum.Material.Wood))
				end
				for k = 1, 3 do
					decor(block(hall, "DoorBar", Vector3.new(bayWidth / 2, 0.15, 0.35), cf * CFrame.new(0, -doorH / 2 + k * doorH / 4, 0), PALETTE.WoodDark, Enum.Material.Wood))
				end
			end
		end
	end
	-- A lintel over the open middle with the hall's name board.
	local sign = block(hall, "NameBoard", Vector3.new(14, 2.6, 0.4), CFrame.new(0, WALL_TOP - 3, HALL_SOUTH + 0.6), PALETTE.WoodDark, Enum.Material.Wood)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- faces south, toward the training ground
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = sign
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = "道場  ·  TRAINING GROUNDS"
	text.TextColor3 = Color3.fromRGB(236, 214, 150)
	text.TextScaled = true
	text.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
	text.Parent = gui

	-- Gabled tile roof along X, with gable ends and a ridge.
	local run = (depth / 2) + EAVE
	local rise = RIDGE - (WALL_TOP + 0.4)
	local slope = math.atan2(rise, run)
	local length = math.sqrt(run * run + rise * rise) + 0.6
	local roofWidth = width + EAVE * 2 + 2
	local eaveY = WALL_TOP + 0.4
	local north = Vector3.new(0, eaveY + rise / 2, HALL_NORTH - EAVE + run / 2)
	local south = Vector3.new(0, eaveY + rise / 2, HALL_SOUTH + EAVE - run / 2)
	local roof = folder(hall, "Roof")
	block(roof, "RoofNorth", Vector3.new(roofWidth, 0.8, length), CFrame.new(north) * CFrame.Angles(-slope, 0, 0), PALETTE.Tile, Enum.Material.Slate)
	block(roof, "RoofSouth", Vector3.new(roofWidth, 0.8, length), CFrame.new(south) * CFrame.Angles(slope, 0, 0), PALETTE.Tile, Enum.Material.Slate)
	block(roof, "Ridge", Vector3.new(roofWidth + 1, 1.4, 1.8), CFrame.new(0, RIDGE + 0.3, midZ), PALETTE.Ink, Enum.Material.Slate)
	for _, px in { -1, 1 } do
		-- Upturned ridge ends.
		block(roof, "RidgeEnd", Vector3.new(1.8, 2.6, 1.8), CFrame.new(px * (roofWidth / 2 + 0.4), RIDGE + 1, midZ) * CFrame.Angles(0, 0, math.rad(-px * 20)), PALETTE.Ink, Enum.Material.Slate)
	end
	-- Tile rows: thin dark strips running down each slope.
	for i = -8, 8 do
		local rx = i * (roofWidth / 17)
		decor(block(roof, "TileRow", Vector3.new(0.35, 0.3, length), CFrame.new(north + Vector3.new(rx, 0.5, 0)) * CFrame.Angles(-slope, 0, 0), PALETTE.Ink, Enum.Material.Slate))
		decor(block(roof, "TileRow", Vector3.new(0.35, 0.3, length), CFrame.new(south + Vector3.new(rx, 0.5, 0)) * CFrame.Angles(slope, 0, 0), PALETTE.Ink, Enum.Material.Slate))
	end
	-- Gable triangles (the tall side of a wedge is its back, +Z).
	local gableH = RIDGE - WALL_TOP
	for _, px in { -HALL_X, HALL_X } do
		wedge(roof, "Gable", Vector3.new(0.6, gableH, depth / 2), CFrame.new(px, WALL_TOP + gableH / 2, HALL_NORTH + depth / 4), PALETTE.Plaster, Enum.Material.Plaster)
		wedge(roof, "Gable", Vector3.new(0.6, gableH, depth / 2), CFrame.new(px, WALL_TOP + gableH / 2, HALL_SOUTH - depth / 4) * CFrame.Angles(0, math.pi, 0), PALETTE.Plaster, Enum.Material.Plaster)
	end
end

local function buildHallInterior(hall: Instance, model: Model)
	local props = folder(hall, "Props")

	-- Shrine shelf (kamidana) on the back wall, centre.
	local shelfZ = HALL_NORTH + 1
	block(props, "Kamidana", Vector3.new(8, 0.5, 2), CFrame.new(0, 12, shelfZ), PALETTE.Wood, Enum.Material.Wood)
	block(props, "Shrine", Vector3.new(3, 2.4, 1.6), CFrame.new(0, 13.45, shelfZ), PALETTE.Wood, Enum.Material.Wood)
	wedge(props, "ShrineRoof", Vector3.new(3.8, 1, 1), CFrame.new(0, 15.15, shelfZ - 0.4), PALETTE.Tile, Enum.Material.Slate)
	wedge(props, "ShrineRoof", Vector3.new(3.8, 1, 1), CFrame.new(0, 15.15, shelfZ + 0.4) * CFrame.Angles(0, math.pi, 0), PALETTE.Tile, Enum.Material.Slate)
	decor(block(props, "Rope", Vector3.new(7, 0.4, 0.4), CFrame.new(0, 11.4, shelfZ + 1.1), PALETTE.Straw, Enum.Material.Fabric))

	-- Hanging scrolls: paper, a dark roller, and a few brush strokes.
	for i, sx in { -24, -12, 12, 24 } do
		local cf = CFrame.new(sx, 10, HALL_NORTH + 0.35)
		decor(block(props, "Scroll", Vector3.new(3.2, 9, 0.1), cf, PALETTE.Shoji, Enum.Material.Fabric))
		decor(block(props, "Roller", Vector3.new(3.8, 0.35, 0.35), cf * CFrame.new(0, 4.6, 0), PALETTE.WoodDark, Enum.Material.Wood))
		decor(block(props, "Roller", Vector3.new(3.8, 0.35, 0.35), cf * CFrame.new(0, -4.6, 0), PALETTE.WoodDark, Enum.Material.Wood))
		local rng = Random.new(SEED + i)
		for k = 1, 3 do
			local strokeCF = cf * CFrame.new(rng:NextNumber(-0.6, 0.6), 2.8 - k * 1.8, 0.07) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-35, 35)))
			decor(block(props, "Stroke", Vector3.new(rng:NextNumber(1.2, 2.2), 0.28, 0.05), strokeCF, PALETTE.Ink, Enum.Material.SmoothPlastic))
		end
	end

	-- Weapon racks along both side walls: a frame and wooden practice swords.
	for _, side in { -1, 1 } do
		for i = 0, 2 do
			local rz = HALL_NORTH + 10 + i * 15
			local rx = side * (HALL_X - 1.6)
			local rack = CFrame.new(rx, DECK, rz)
			block(props, "RackFoot", Vector3.new(1.4, 0.4, 6), rack * CFrame.new(0, 0.2, 0), PALETTE.WoodDark, Enum.Material.Wood)
			for _, oz in { -2.6, 2.6 } do
				block(props, "RackPost", Vector3.new(0.4, 5, 0.4), rack * CFrame.new(0, 2.7, oz), PALETTE.WoodDark, Enum.Material.Wood)
			end
			block(props, "RackBar", Vector3.new(0.5, 0.3, 5.6), rack * CFrame.new(0, 4.4, 0), PALETTE.WoodDark, Enum.Material.Wood)
			for k = -2, 2 do
				decor(block(props, "Bokken", Vector3.new(0.25, 4.6, 0.3), rack * CFrame.new(side * 0.3, 2.6, k * 1) * CFrame.Angles(0, 0, math.rad(side * 8)), PALETTE.Wood, Enum.Material.Wood))
			end
		end
	end

	-- Taiko drum on a stand by the back wall.
	local drumCF = CFrame.new(-32, DECK, HALL_NORTH + 6)
	block(props, "DrumStand", Vector3.new(4, 2.2, 1), drumCF * CFrame.new(0, 1.1, 0), PALETTE.WoodDark, Enum.Material.Wood)
	local drum = block(props, "Taiko", Vector3.new(2.8, 4.4, 4.4), drumCF * CFrame.new(0, 4.4, 0), PALETTE.Lacquer, Enum.Material.Wood)
	drum.Shape = Enum.PartType.Cylinder
	drum.CFrame = drumCF * CFrame.new(0, 4.4, 0) * CFrame.Angles(0, math.rad(90), 0)
	for _, off in { -1.45, 1.45 } do
		local head = block(props, "DrumHead", Vector3.new(0.1, 4.2, 4.2), drum.CFrame * CFrame.new(off, 0, 0), PALETTE.Straw, Enum.Material.Fabric)
		head.Shape = Enum.PartType.Cylinder
		decor(head)
	end

	-- Paper lanterns hanging from the ceiling, lit.
	for _, lx in { -26, 0, 26 } do
		for _, lz in { HALL_NORTH + 14, HALL_SOUTH - 14 } do
			decor(block(props, "Cord", Vector3.new(0.1, 3, 0.1), CFrame.new(lx, WALL_TOP - 3, lz), PALETTE.Ink, Enum.Material.SmoothPlastic))
			local lantern = decor(ball(props, "Lantern", 2.4, Vector3.new(lx, WALL_TOP - 5.4, lz), PALETTE.Lantern, Enum.Material.Neon))
			lantern.Size = Vector3.new(2.2, 2.8, 2.2)
			decor(block(props, "LanternCap", Vector3.new(1.4, 0.3, 1.4), CFrame.new(lx, WALL_TOP - 3.9, lz), PALETTE.Ink, Enum.Material.Wood))
			light(lantern, 22, 1.2)
		end
	end

	-- The training board: two posts and a double-sided sign; its prompt opens the training menu.
	local boardCF = CFrame.new(0, DECK, HALL_SOUTH - 12)
	local board = Instance.new("Model")
	board.Name = "TrainingBoard"
	for _, ox in { -3.6, 3.6 } do
		block(board, "Post", Vector3.new(0.6, 7, 0.6), boardCF * CFrame.new(ox, 3.5, 0), PALETTE.WoodDark, Enum.Material.Wood)
	end
	local panel = block(board, "Panel", Vector3.new(7.8, 4, 0.4), boardCF * CFrame.new(0, 5, 0), PALETTE.Plaster, Enum.Material.Plaster)
	block(board, "Frame", Vector3.new(8.4, 4.6, 0.3), boardCF * CFrame.new(0, 5, 0), PALETTE.WoodDark, Enum.Material.Wood)
	block(board, "Cap", Vector3.new(9, 0.5, 1.2), boardCF * CFrame.new(0, 7.45, 0), PALETTE.Tile, Enum.Material.Slate)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local signGui = Instance.new("SurfaceGui")
		signGui.Face = face
		signGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		signGui.PixelsPerStud = 40
		signGui.LightInfluence = 0
		signGui.Parent = panel
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.RichText = true
		label.Text = '<font size="54">TRAINING BOARD</font>\n<font size="22" color="#8A2A24">DUMMIES · FIGHTER · HOW TO PLAY</font>'
		label.TextColor3 = Color3.fromRGB(28, 22, 18)
		label.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
		label.TextSize = 54
		label.Parent = signGui
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TrainingPrompt"
	prompt.ActionText = "Training menu"
	prompt.ObjectText = "Training board"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Action", "Training")
	prompt.Parent = panel
	board.PrimaryPart = panel
	board.Parent = model

	-- Where fighters wait between rounds: the back half of the hall, facing the entrance.
	local points = folder(model, "SpawnPoints")
	for i, spot in { { -18, -80 }, { -6, -82 }, { 6, -82 }, { 18, -80 }, { -12, -72 }, { 12, -72 } } do
		local marker = hide(decor(block(points, "Spawn" .. i, Vector3.new(4, 1, 4), CFrame.lookAt(Vector3.new(spot[1], DECK + 0.5, spot[2]), Vector3.new(spot[1], DECK + 0.5, 100)), PALETTE.Wood, Enum.Material.SmoothPlastic)))
		marker.Name = "Spawn" .. i
	end
end

-- The training ground ------------------------------------------------------------------------------------

local function dummy(parent: Instance, base: Vector3, facing: number)
	local cf = CFrame.new(base) * CFrame.Angles(0, math.rad(facing), 0)
	local m = folder(parent, "Dummy")
	block(m, "Foot", Vector3.new(2.4, 0.4, 2.4), cf * CFrame.new(0, 0.2, 0), PALETTE.WoodDark, Enum.Material.Wood)
	local post = column(m, "Post", 6, 0.8, base, PALETTE.WoodDark, Enum.Material.Wood)
	post.CFrame = cf * CFrame.new(0, 3, 0) * CFrame.Angles(0, 0, math.rad(90))
	local body = column(m, "Straw", 2.6, 1.8, base, PALETTE.Straw, Enum.Material.Fabric)
	body.CFrame = cf * CFrame.new(0, 3.6, 0) * CFrame.Angles(0, 0, math.rad(90))
	block(m, "Arms", Vector3.new(4.6, 0.4, 0.4), cf * CFrame.new(0, 4.4, 0), PALETTE.WoodDark, Enum.Material.Wood)
	for _, ax in { -2.3, 2.3 } do
		block(m, "Fist", Vector3.new(0.7, 0.7, 0.7), cf * CFrame.new(ax, 4.4, 0), PALETTE.Straw, Enum.Material.Fabric)
	end
	ball(m, "Head", 1.4, (cf * CFrame.new(0, 5.6, 0)).Position, PALETTE.Straw, Enum.Material.Fabric)
	decor(block(m, "Headband", Vector3.new(1.5, 0.25, 1.5), cf * CFrame.new(0, 5.8, 0), PALETTE.Lacquer, Enum.Material.Fabric))
end

local function bambooGrove(parent: Instance, center: Vector3, radius: number, count: number, rng: Random)
	local grove = folder(parent, "BambooGrove")
	for _ = 1, count do
		local angle = rng:NextNumber(0, math.pi * 2)
		local r = math.sqrt(rng:NextNumber()) * radius
		local base = center + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		local height = rng:NextNumber(16, 26)
		column(grove, "Stalk", height, rng:NextNumber(0.7, 1.05), base, PALETTE.Bamboo, Enum.Material.SmoothPlastic)
		for k = 1, math.floor(height / 4) do
			decor(block(grove, "Node", Vector3.new(1.1, 0.12, 1.1), CFrame.new(base + Vector3.new(0, k * 4, 0)), PALETTE.BambooLeaf, Enum.Material.SmoothPlastic))
		end
		local leaves = decor(ball(grove, "Leaves", rng:NextNumber(3, 4.5), base + Vector3.new(rng:NextNumber(-1, 1), height - 1, rng:NextNumber(-1, 1)), PALETTE.BambooLeaf, Enum.Material.Grass))
		leaves.Size = Vector3.new(leaves.Size.X * 1.3, leaves.Size.Y * 0.7, leaves.Size.Z * 1.3)
	end
end

local function rockCluster(parent: Instance, center: Vector3, rng: Random, big: boolean)
	local rocks = folder(parent, "Rocks")
	local main = if big then Vector3.new(9, 9, 8) else Vector3.new(5, 3.6, 4.5)
	block(rocks, "Rock", main, CFrame.new(center + Vector3.new(0, main.Y / 2 - 0.4, 0)) * CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), math.rad(rng:NextNumber(0, 90)), math.rad(rng:NextNumber(-8, 8))), PALETTE.Rock, Enum.Material.Rock)
	for _ = 1, 3 do
		local size = Vector3.new(rng:NextNumber(2.5, 4.5), rng:NextNumber(1.6, 3.5), rng:NextNumber(2.5, 4))
		local offset = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit * (main.X / 2 + 1)
		block(rocks, "Rock", size, CFrame.new(center + offset + Vector3.new(0, size.Y / 2 - 0.3, 0)) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 90)), math.rad(rng:NextNumber(-12, 12))), PALETTE.StoneLight, Enum.Material.Rock)
	end
end

local function cherryTree(parent: Instance, base: Vector3, rng: Random)
	local tree = folder(parent, "CherryTree")
	column(tree, "Trunk", 9, 1.6, base, PALETTE.Trunk, Enum.Material.Wood)
	for k = 1, 3 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dir = Vector3.new(math.cos(angle), 0.8, math.sin(angle)).Unit
		local from = base + Vector3.new(0, 6 + k, 0)
		block(tree, "Branch", Vector3.new(0.7, 0.7, 5), CFrame.lookAt(from + dir * 2.5, from + dir * 5), PALETTE.Trunk, Enum.Material.Wood)
	end
	local canopy = folder(tree, "Canopy")
	for k = 1, 5 do
		local c = base + Vector3.new(rng:NextNumber(-3.5, 3.5), rng:NextNumber(9.5, 13), rng:NextNumber(-3.5, 3.5))
		blocksSight(decor(ball(canopy, "Blossom", rng:NextNumber(5, 7.5), c, if k % 2 == 0 then PALETTE.Blossom2 else PALETTE.Blossom, Enum.Material.Grass)))
	end
	-- Petals drifting down (the engine's own sparkle texture, tinted pink).
	local source = decor(hide(block(tree, "PetalSource", Vector3.new(10, 1, 10), CFrame.new(base + Vector3.new(0, 12, 0)), PALETTE.Blossom, Enum.Material.SmoothPlastic)))
	local petals = Instance.new("ParticleEmitter")
	petals.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	petals.Color = ColorSequence.new(PALETTE.Blossom)
	petals.LightEmission = 0.2
	petals.Rate = 4
	petals.Lifetime = NumberRange.new(5, 8)
	petals.Speed = NumberRange.new(0.5, 1.5)
	petals.Acceleration = Vector3.new(0.6, -0.8, 0.3)
	petals.SpreadAngle = Vector2.new(60, 60)
	petals.EmissionDirection = Enum.NormalId.Bottom
	petals.RotSpeed = NumberRange.new(-60, 60)
	petals.Size = NumberSequence.new(0.35)
	petals.Parent = source
end

local function stoneLantern(parent: Instance, base: Vector3)
	local l = folder(parent, "StoneLantern")
	block(l, "Base", Vector3.new(2.4, 0.8, 2.4), CFrame.new(base + Vector3.new(0, 0.4, 0)), PALETTE.StoneLight, Enum.Material.Slate)
	column(l, "Post", 3, 1, base + Vector3.new(0, 0.8, 0), PALETTE.StoneLight, Enum.Material.Slate)
	local box = block(l, "Light", Vector3.new(1.8, 1.6, 1.8), CFrame.new(base + Vector3.new(0, 4.6, 0)), PALETTE.Lantern, Enum.Material.Neon)
	light(box, 14, 0.8)
	block(l, "Roof", Vector3.new(3, 0.6, 3), CFrame.new(base + Vector3.new(0, 5.7, 0)) * CFrame.Angles(0, math.rad(45), 0), PALETTE.StoneLight, Enum.Material.Slate)
	ball(l, "Knob", 0.8, base + Vector3.new(0, 6.3, 0), PALETTE.StoneLight, Enum.Material.Slate)
end

local function sparringPlatform(parent: Instance, center: Vector3)
	local p = folder(parent, "SparringPlatform")
	local size = 16
	walkable(block(p, "Floor", Vector3.new(size, 1.2, size), CFrame.new(center + Vector3.new(0, 0.6, 0)), PALETTE.Wood, Enum.Material.WoodPlanks))
	decor(block(p, "Trim", Vector3.new(size + 0.4, 0.3, size + 0.4), CFrame.new(center + Vector3.new(0, 0.15, 0)), PALETTE.WoodDark, Enum.Material.Wood))
	local corners = {}
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local post = center + Vector3.new(sx * (size / 2 - 0.5), 1.2, sz * (size / 2 - 0.5))
			block(p, "Post", Vector3.new(0.8, 4, 0.8), CFrame.new(post + Vector3.new(0, 2, 0)), PALETTE.Lacquer, Enum.Material.Wood)
			table.insert(corners, post)
		end
	end
	-- Ropes between neighbouring posts (1-2, 2-4, 4-3, 3-1), at two heights.
	for _, pair in { { 1, 2 }, { 2, 4 }, { 4, 3 }, { 3, 1 } } do
		local a, b = corners[pair[1]], corners[pair[2]]
		for _, h in { 1.6, 3 } do
			local from, to = a + Vector3.new(0, h, 0), b + Vector3.new(0, h, 0)
			decor(block(p, "Rope", Vector3.new(0.2, 0.2, (to - from).Magnitude), CFrame.lookAt((from + to) / 2, to), PALETTE.Straw, Enum.Material.Fabric))
		end
	end
end

local function sparringRing(parent: Instance, center: Vector3)
	local ring = folder(parent, "SparringRing")
	local radius = 12
	walkable(column(ring, "Floor", 0.6, radius * 2, center, PALETTE.StoneLight, Enum.Material.Slate))
	decor(column(ring, "Circle", 0.05, radius * 2 - 3, center + Vector3.new(0, 0.6, 0), PALETTE.Lacquer, Enum.Material.Slate))
	decor(column(ring, "CircleInner", 0.06, radius * 2 - 4, center + Vector3.new(0, 0.6, 0), PALETTE.StoneLight, Enum.Material.Slate))
	for i = 0, 7 do
		local angle = math.rad(i * 45 + 22.5)
		local spot = center + Vector3.new(math.cos(angle) * (radius + 1.5), 0, math.sin(angle) * (radius + 1.5))
		block(ring, "Marker", Vector3.new(1.4, 2.6, 1.4), CFrame.new(spot + Vector3.new(0, 1.3, 0)), PALETTE.Stone, Enum.Material.Slate)
	end
end

local function stepPosts(parent: Instance, origin: Vector3, rng: Random)
	local field = folder(parent, "StepPosts")
	for ix = 0, 3 do
		for iz = 0, 2 do
			local h = rng:NextNumber(1.5, 6)
			column(field, "Post", h, 1.8, origin + Vector3.new(ix * 3.4, 0, iz * 3.4), PALETTE.WoodDark, Enum.Material.Wood)
		end
	end
end

local function koiPond(parent: Instance, rng: Random)
	local pond = folder(parent, "KoiPond")
	local c = Vector3.new(POND.x, 0, POND.z)
	-- The basin is carved out of the terrain (buildTerrain); its floor and water are parts, so spawns never pick
	-- the water (only terrain and Walkable parts are open ground).
	-- Shallow (2 studs): anyone who steps in can hop straight back out.
	block(pond, "Bed", Vector3.new(POND.radius * 2 + 2, 0.4, POND.radius * 2 + 2), CFrame.new(c + Vector3.new(0, -2.2, 0)), PALETTE.Mud, Enum.Material.Mud)
	local water = decor(column(pond, "Water", 0.2, POND.radius * 2 + 1, c + Vector3.new(0, -0.9, 0), PALETTE.Water, Enum.Material.Glass))
	water.Transparency = 0.35
	for i = 0, 17 do
		local angle = math.rad(i * 20 + rng:NextNumber(-6, 6))
		local spot = c + Vector3.new(math.cos(angle) * (POND.radius + 0.6), 0, math.sin(angle) * (POND.radius + 0.6))
		local size = Vector3.new(rng:NextNumber(1.8, 3), rng:NextNumber(0.9, 1.6), rng:NextNumber(1.8, 3))
		block(pond, "EdgeStone", size, CFrame.new(spot + Vector3.new(0, size.Y / 2 - 0.5, 0)) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 90)), 0), PALETTE.StoneLight, Enum.Material.Rock)
	end
	for k = 1, 5 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(2, POND.radius - 3)
		decor(block(pond, "Koi", Vector3.new(0.5, 0.2, 1.4), CFrame.new(c + Vector3.new(math.cos(angle) * r, -1.3, math.sin(angle) * r)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), if k % 2 == 0 then PALETTE.Plaster else PALETTE.Koi, Enum.Material.SmoothPlastic))
	end
	-- An arched red bridge across it, east to west.
	local span = POND.radius * 2 + 6
	local segments = 10
	local arch = 3
	local prev: Vector3? = nil
	for i = 0, segments do
		local t = i / segments
		local point = c + Vector3.new(-span / 2 + t * span, math.sin(t * math.pi) * arch + 0.3, 0)
		if prev then
			local mid = (prev + point) / 2
			walkable(block(pond, "Deck", Vector3.new(5, 0.5, (point - prev).Magnitude + 0.1), CFrame.lookAt(mid, point), PALETTE.Wood, Enum.Material.WoodPlanks))
			for _, side in { -1, 1 } do
				decor(block(pond, "Rail", Vector3.new(0.3, 0.3, (point - prev).Magnitude + 0.1), CFrame.lookAt(mid + Vector3.new(0, 2.6, side * 2.4), point + Vector3.new(0, 2.6, side * 2.4)), PALETTE.Lacquer, Enum.Material.Wood))
			end
		end
		if i % 2 == 0 then
			for _, side in { -1, 1 } do
				block(pond, "RailPost", Vector3.new(0.4, 2.8, 0.4), CFrame.new(point + Vector3.new(0, 1.4, side * 2.4)), PALETTE.Lacquer, Enum.Material.Wood)
			end
		end
		prev = point
	end
end

-- A low wooden fence: LOW cover (hides the body, not the plate).
local function fence(parent: Instance, center: Vector3, degrees: number)
	local f = folder(parent, "Fence")
	local cf = CFrame.new(center) * CFrame.Angles(0, math.rad(degrees), 0)
	local length = 12
	for i = -2, 2 do
		block(f, "Post", Vector3.new(0.6, 3.8, 0.6), cf * CFrame.new(i * length / 4, 1.9, 0), PALETTE.WoodDark, Enum.Material.Wood)
	end
	for _, h in { 1.2, 2.6 } do
		block(f, "Rail", Vector3.new(length, 0.9, 0.4), cf * CFrame.new(0, h, 0), PALETTE.Wood, Enum.Material.WoodPlanks)
	end
end

local function well(parent: Instance, center: Vector3)
	local w = folder(parent, "Well")
	local ringParts = 10
	for i = 0, ringParts - 1 do
		local angle = i * math.pi * 2 / ringParts
		local spot = center + Vector3.new(math.cos(angle) * 2.6, 1.4, math.sin(angle) * 2.6)
		block(w, "Stone", Vector3.new(1.8, 2.8, 1.4), CFrame.lookAt(spot, Vector3.new(center.X, spot.Y, center.Z)), PALETTE.StoneLight, Enum.Material.Rock)
	end
	decor(column(w, "Water", 0.1, 4, center + Vector3.new(0, 1.8, 0), PALETTE.Water, Enum.Material.Glass))
	for _, side in { -1, 1 } do
		block(w, "Post", Vector3.new(0.5, 6, 0.5), CFrame.new(center + Vector3.new(side * 3.2, 3, 0)), PALETTE.WoodDark, Enum.Material.Wood)
	end
	block(w, "Beam", Vector3.new(7, 0.5, 0.5), CFrame.new(center + Vector3.new(0, 6.1, 0)), PALETTE.WoodDark, Enum.Material.Wood)
	wedge(w, "Roof", Vector3.new(7.6, 1.4, 2.4), CFrame.new(center + Vector3.new(0, 7, -1.2)), PALETTE.Tile, Enum.Material.Slate)
	wedge(w, "Roof", Vector3.new(7.6, 1.4, 2.4), CFrame.new(center + Vector3.new(0, 7, 1.2)) * CFrame.Angles(0, math.pi, 0), PALETTE.Tile, Enum.Material.Slate)
	decor(block(w, "Bucket", Vector3.new(0.9, 1, 0.9), CFrame.new(center + Vector3.new(0.4, 4.2, 0)), PALETTE.Wood, Enum.Material.Wood))
end

local function archeryTarget(parent: Instance, base: Vector3, facing: number)
	local t = folder(parent, "ArcheryTarget")
	local cf = CFrame.new(base) * CFrame.Angles(0, math.rad(facing), 0)
	for _, side in { -1, 1 } do
		block(t, "Leg", Vector3.new(0.4, 6, 0.4), cf * CFrame.new(side * 1.6, 3, 0.8) * CFrame.Angles(math.rad(-12), 0, 0), PALETTE.WoodDark, Enum.Material.Wood)
	end
	local face = block(t, "Straw", Vector3.new(0.8, 5, 5), cf * CFrame.new(0, 4.4, 0) * CFrame.Angles(0, math.rad(90), 0), PALETTE.Straw, Enum.Material.Fabric)
	face.Shape = Enum.PartType.Cylinder
	for i, spec in { { 3.6, PALETTE.Plaster }, { 2.4, PALETTE.Lacquer }, { 1, PALETTE.Ink } } do
		local ring = decor(block(t, "Ring", Vector3.new(0.05, spec[1], spec[1]), face.CFrame * CFrame.new(-0.42 - i * 0.01, 0, 0), spec[2], Enum.Material.Fabric))
		ring.Shape = Enum.PartType.Cylinder
	end
end

local function buildGround(model: Model, rng: Random)
	local ground = folder(model, "TrainingGround")
	-- The stone path from the hall steps to the gate.
	local z = HALL_SOUTH + 6
	while z < YARD_SOUTH - 6 do
		if math.abs(z - 30) > 13 then -- the sparring ring interrupts it
			walkable(block(ground, "PathStone", Vector3.new(rng:NextNumber(5.5, 7), 0.3, 2.6), CFrame.new(rng:NextNumber(-0.4, 0.4), 0.15, z) * CFrame.Angles(0, math.rad(rng:NextNumber(-4, 4)), 0), PALETTE.StoneLight, Enum.Material.Slate))
		end
		z += 3.4
	end
	sparringRing(ground, Vector3.new(0, 0, 30))
	sparringPlatform(ground, Vector3.new(-54, 0, -6))
	sparringPlatform(ground, Vector3.new(54, 0, -6))
	for _, dx in { -34, -26, -18, 18, 26, 34 } do
		dummy(ground, Vector3.new(dx, 0, -26), 0)
	end
	for _, spot in { { -62, 54 }, { -54, 60 }, { 22, 76 } } do
		dummy(ground, Vector3.new(spot[1], 0, spot[2]), rng:NextNumber(-30, 30))
	end
	bambooGrove(ground, Vector3.new(-76, 0, -28), 6, 14, rng)
	bambooGrove(ground, Vector3.new(76, 0, -28), 6, 14, rng)
	bambooGrove(ground, Vector3.new(-56, 0, 30), 5, 11, rng)
	bambooGrove(ground, Vector3.new(80, 0, 40), 5, 11, rng)
	bambooGrove(ground, Vector3.new(-20, 0, 86), 5, 10, rng)
	rockCluster(ground, Vector3.new(-30, 0, 6), rng, true)
	rockCluster(ground, Vector3.new(32, 0, 8), rng, true)
	rockCluster(ground, Vector3.new(-30, 0, 62), rng, true)
	rockCluster(ground, Vector3.new(26, 0, 50), rng, false)
	rockCluster(ground, Vector3.new(-78, 0, 8), rng, false)
	rockCluster(ground, Vector3.new(66, 0, 18), rng, false)
	rockCluster(ground, Vector3.new(10, 0, 70), rng, true)
	stepPosts(ground, Vector3.new(-72, 0, 70), rng)
	fence(ground, Vector3.new(-42, 0, 18), 30)
	fence(ground, Vector3.new(-16, 0, 46), -20)
	fence(ground, Vector3.new(46, 0, 30), 70)
	fence(ground, Vector3.new(-66, 0, -14), 90)
	well(ground, Vector3.new(-18, 0, 30))
	archeryTarget(ground, Vector3.new(76, 0, -4), -90)
	archeryTarget(ground, Vector3.new(76, 0, 6), -90)
	for _, spot in { { -80, 90 }, { -44, 92 }, { 82, 88 }, { 34, 92 }, { -84, -34 }, { 84, 6 } } do
		cherryTree(ground, Vector3.new(spot[1], 0, spot[2]), rng)
	end
	for _, lz in { -32, -6, 52, 78 } do
		for _, lx in { -8, 8 } do
			stoneLantern(ground, Vector3.new(lx, 0, lz))
		end
	end
	koiPond(ground, rng)
end

-- The compound wall, gate and barriers ---------------------------------------------------------------------

local function wallRun(parent: Instance, from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	local mid = (from + to) / 2
	local cf = CFrame.lookAt(mid, to)
	block(parent, "WallBase", Vector3.new(3.4, 5, length), cf * CFrame.new(0, 2.5, 0), PALETTE.Stone, Enum.Material.Cobblestone)
	block(parent, "WallPlaster", Vector3.new(3, COMPOUND_WALL - 6.2, length), cf * CFrame.new(0, 5 + (COMPOUND_WALL - 6.2) / 2, 0), PALETTE.Plaster, Enum.Material.Plaster)
	block(parent, "WallCap", Vector3.new(4.6, 1.2, length + 1), cf * CFrame.new(0, COMPOUND_WALL - 0.6, 0), PALETTE.Tile, Enum.Material.Slate)
	block(parent, "WallRidge", Vector3.new(1, 0.8, length + 1), cf * CFrame.new(0, COMPOUND_WALL + 0.4, 0), PALETTE.Ink, Enum.Material.Slate)
end

local function buildCompound(model: Model)
	local walls = folder(model, "Compound")
	local gateHalf = 9
	wallRun(walls, Vector3.new(-YARD_X, 0, YARD_NORTH), Vector3.new(YARD_X, 0, YARD_NORTH))
	wallRun(walls, Vector3.new(-YARD_X, 0, YARD_NORTH), Vector3.new(-YARD_X, 0, YARD_SOUTH))
	wallRun(walls, Vector3.new(YARD_X, 0, YARD_NORTH), Vector3.new(YARD_X, 0, YARD_SOUTH))
	wallRun(walls, Vector3.new(-YARD_X, 0, YARD_SOUTH), Vector3.new(-gateHalf, 0, YARD_SOUTH))
	wallRun(walls, Vector3.new(gateHalf, 0, YARD_SOUTH), Vector3.new(YARD_X, 0, YARD_SOUTH))

	-- The gate: closed wooden doors with iron studs, a roof over them, and a red torii just inside.
	local gate = folder(walls, "Gate")
	for _, side in { -1, 1 } do
		local door = block(gate, "Door", Vector3.new(gateHalf, 12, 1), CFrame.new(side * gateHalf / 2, 6, YARD_SOUTH), PALETTE.WoodDark, Enum.Material.WoodPlanks)
		for k = 1, 3 do
			decor(block(gate, "Band", Vector3.new(gateHalf, 0.4, 1.1), door.CFrame * CFrame.new(0, -6 + k * 3, 0), PALETTE.Ink, Enum.Material.Metal))
		end
	end
	block(gate, "GateRoof", Vector3.new(gateHalf * 2 + 6, 1.2, 6), CFrame.new(0, 13, YARD_SOUTH), PALETTE.Tile, Enum.Material.Slate)
	block(gate, "GateBeam", Vector3.new(gateHalf * 2 + 2, 1.4, 1.4), CFrame.new(0, 12.3, YARD_SOUTH), PALETTE.WoodDark, Enum.Material.Wood)
	local toriiZ = YARD_SOUTH - 10
	for _, side in { -1, 1 } do
		column(gate, "ToriiPillar", 17, 1.6, Vector3.new(side * 9, 0, toriiZ), PALETTE.Lacquer, Enum.Material.Wood)
		block(gate, "ToriiFoot", Vector3.new(2.2, 1, 2.2), CFrame.new(side * 9, 0.5, toriiZ), PALETTE.Ink, Enum.Material.Wood)
	end
	block(gate, "Nuki", Vector3.new(22, 0.9, 0.9), CFrame.new(0, 13.4, toriiZ), PALETTE.Lacquer, Enum.Material.Wood)
	block(gate, "Kasagi", Vector3.new(27, 1.2, 1.8), CFrame.new(0, 17.4, toriiZ), PALETTE.Ink, Enum.Material.Wood)
	block(gate, "Shimaki", Vector3.new(25, 0.9, 1.5), CFrame.new(0, 16.4, toriiZ), PALETTE.Lacquer, Enum.Material.Wood)
	block(gate, "Gakuzuka", Vector3.new(0.8, 3, 0.8), CFrame.new(0, 14.9, toriiZ), PALETTE.Lacquer, Enum.Material.Wood)

	-- Invisible barriers: nobody leaves the compound (they take no raycasts, so aiming ignores them).
	local barriers = folder(model, "Barriers")
	local spans = {
		{ Vector3.new(YARD_X * 2 + 4, BARRIER_HEIGHT, 1), Vector3.new(0, BARRIER_HEIGHT / 2, YARD_NORTH) },
		{ Vector3.new(YARD_X * 2 + 4, BARRIER_HEIGHT, 1), Vector3.new(0, BARRIER_HEIGHT / 2, YARD_SOUTH) },
		{ Vector3.new(1, BARRIER_HEIGHT, YARD_SOUTH - YARD_NORTH + 4), Vector3.new(-YARD_X, BARRIER_HEIGHT / 2, 0) },
		{ Vector3.new(1, BARRIER_HEIGHT, YARD_SOUTH - YARD_NORTH + 4), Vector3.new(YARD_X, BARRIER_HEIGHT / 2, 0) },
	}
	for i, spec in spans do
		local wall = hide(block(barriers, "Barrier" .. i, spec[1], CFrame.new(spec[2]), PALETTE.Stone, Enum.Material.SmoothPlastic))
		wall.CanQuery = false
		wall.CanTouch = false
	end
end

local function buildSpawnArea(model: Model)
	local area = folder(model, "SpawnArea")
	-- The open training ground only (the hall is where fighters wait between rounds).
	local north, south = HALL_SOUTH + 8, YARD_SOUTH - 6
	local box = block(area, "Ground", Vector3.new(YARD_X * 2 - 8, 24, south - north), CFrame.new(0, 12, (north + south) / 2), PALETTE.Stone, Enum.Material.SmoothPlastic)
	hide(decor(box))
end

function Dojo.build(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Arena_Dojo"
	model:SetAttribute("DisplayName", "The Training Grounds")

	local root = block(model, "Root", Vector3.one, CFrame.new(0, 0, 0), PALETTE.Stone, Enum.Material.SmoothPlastic)
	hide(decor(root))
	model.PrimaryPart = root

	local rng = Random.new(SEED)
	local hall = folder(model, "Hall")
	buildHallShell(hall)
	buildHallInterior(hall, model)
	buildGround(model, rng)
	buildCompound(model)
	buildSpawnArea(model)

	model.Parent = parent
	return model
end

-- Terrain: packed earth across the training ground, grass along the walls and under the hall, the pond's basin carved
-- out. Fills stop 2 studs below the floor (MapService puts the origin at y = 2, so the surface lands at y = 0).
local TERRAIN_TOP = -2

function Dojo.buildTerrain(origin: CFrame)
	local terrain = workspace.Terrain
	local center = TERRAIN_TOP - 4
	local size = Vector3.new(YARD_X * 2 + 30, 8, YARD_SOUTH - YARD_NORTH + 30)
	terrain:FillBlock(origin * CFrame.new(0, center, 0), size, Enum.Material.Grass)
	-- Packed earth, not sand: the engine's sand renders near-white and washed out plates and pale auras.
	terrain:FillBlock(origin * CFrame.new(0, center + 0.1, (HALL_SOUTH + 4 + YARD_SOUTH - 8) / 2), Vector3.new(YARD_X * 2 - 16, 8.2, YARD_SOUTH - 8 - (HALL_SOUTH + 4)), Enum.Material.Ground)
	-- The pond basin: 4 studs of air under the water.
	terrain:FillCylinder(origin * CFrame.new(POND.x, -2, POND.z), 4, POND.radius + 1, Enum.Material.Air)
end

function Dojo.clearTerrain(origin: CFrame)
	workspace.Terrain:FillBlock(origin * CFrame.new(0, 10, 0), Vector3.new(YARD_X * 2 + 60, 60, YARD_SOUTH - YARD_NORTH + 60), Enum.Material.Air)
end

return Dojo
