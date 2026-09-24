-- The yen shop building (Phase 3 item 5, approved 2026-09-23): a storybook cottage on stilts, inspired by
-- the owner's reference (cream walls, red roof and trim, red diamond windows, an arched blue door, vines,
-- red-railed stairs up to a wraparound deck, big dark trees framing it) with our own details. Inside, the
-- cosy shell hides a high-tech room: dark panels, neon strips and a hologram projector pad where the
-- shopper's character is shown while the menu is open (anime tech-behind-a-cottage-door).
--
-- Built around the origin, front facing -Z; the lobby pivots it into its garden. Scale: a default R15
-- avatar is ~5 studs tall; the doorway is 5 x 8.
--
-- Contract used by the game code:
--   ShopHouse.PrimaryPart   unrotated root at ground level under the house
--   ShopHouse/ShopDoor      hidden part in the doorway holding the ProximityPrompt (attribute Action = "Shop")
--   ShopHouse/ShopCamera    hidden part: where the menu's camera sits, looking at the stage
--   ShopHouse/ShopStage     hidden part on the projector pad: where the preview character stands, facing -Z
-- Everything is anchored static scenery. Purely decorative pieces don't collide or take raycasts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Currency = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Currency"))

local ShopHouse = {}

-- Dimensions (studs)
local DECK_H = 5 -- deck floor height
local DECK_W, DECK_D = 32, 20 -- deck spans x -16..16, z -10..10
local HOUSE_W, HOUSE_D, HOUSE_Z = 22, 13, 2.5 -- house spans x -11..11, z -4..9
local WALL_H, WALL_T = 11, 1
local DOOR_W, DOOR_H = 5, 8
local STAIR_W, STEPS, STEP_RUN = 6, 7, 1.1
local RAIL_H = 3
local STAGE_Z = 4.5

local FRONT_Z = HOUSE_Z - HOUSE_D / 2 -- -4, the front wall's outer face
local BACK_Z = HOUSE_Z + HOUSE_D / 2 -- 9
local FLOOR = DECK_H -- the room's floor

local PALETTE = {
	Cream = Color3.fromRGB(236, 224, 196),
	CreamShade = Color3.fromRGB(214, 200, 172),
	Red = Color3.fromRGB(178, 38, 46),
	RedDark = Color3.fromRGB(128, 24, 32),
	Blue = Color3.fromRGB(58, 104, 196),
	BlueDark = Color3.fromRGB(34, 62, 130),
	Wood = Color3.fromRGB(112, 78, 52),
	WoodDark = Color3.fromRGB(62, 43, 30),
	Bark = Color3.fromRGB(52, 38, 32),
	Leaf = Color3.fromRGB(70, 122, 62),
	LeafDark = Color3.fromRGB(40, 78, 46),
	Canopy = Color3.fromRGB(34, 58, 42),
	Purple = Color3.fromRGB(92, 60, 124),
	PurpleDark = Color3.fromRGB(60, 38, 90),
	Glass = Color3.fromRGB(46, 74, 86),
	Iron = Color3.fromRGB(40, 40, 44),
	LampGlass = Color3.fromRGB(214, 150, 96),
	LampGlow = Color3.fromRGB(255, 190, 130),
	Panel = Color3.fromRGB(24, 26, 34),
	PanelEdge = Color3.fromRGB(44, 48, 62),
	Holo = Color3.fromRGB(80, 230, 255),
	HoloPink = Color3.fromRGB(255, 90, 200),
}

local SIGN_FONT = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)

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

-- Roblox cylinders run along the part's X axis; this stands one upright.
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

-- A block stretched between two points (rails, stair stringers).
local function beam(parent: Instance, name: string, from: Vector3, to: Vector3, thickness: number, color: Color3, material: Enum.Material): Part
	local span = to - from
	return block(parent, name, Vector3.new(thickness, thickness, span.Magnitude), CFrame.lookAt(from + span / 2, to), color, material)
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

local function glow(part: BasePart, color: Color3, range: number, brightness: number): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = part
	return light
end

-- Small deterministic "random" in 0..1, so the build is identical every time.
local function hash(a: number, b: number): number
	local x = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return x - math.floor(x)
end

-- Stilts, deck, railing and stairs -----------------------------------------------------------------

local function buildDeck(model: Model)
	local deck = folder(model, "Deck")
	for _, x in { -15, -5, 5, 15 } do
		for _, z in { -9, 9 } do
			block(deck, "Stilt", Vector3.new(1.4, DECK_H, 1.4), CFrame.new(x, DECK_H / 2, z), PALETTE.WoodDark, Enum.Material.Wood)
		end
	end
	for _, x in { -15, 15 } do
		block(deck, "Stilt", Vector3.new(1.4, DECK_H, 1.4), CFrame.new(x, DECK_H / 2, 0), PALETTE.WoodDark, Enum.Material.Wood)
	end
	-- Cross braces between the front stilts.
	for _, pair in { { -15, -5 }, { 5, 15 } } do
		decor(beam(deck, "Brace", Vector3.new(pair[1], 0.6, -9), Vector3.new(pair[2], DECK_H - 1.2, -9), 0.35, PALETTE.WoodDark, Enum.Material.Wood))
	end
	block(deck, "Deck", Vector3.new(DECK_W, 0.8, DECK_D), CFrame.new(0, DECK_H - 0.4, 0), PALETTE.Wood, Enum.Material.WoodPlanks)
	-- Red fascia around the deck edge (slightly proud of it, so no faces are coplanar).
	decor(block(deck, "FasciaFront", Vector3.new(DECK_W + 0.1, 0.7, 0.3), CFrame.new(0, DECK_H - 0.75, -DECK_D / 2 - 0.15), PALETTE.Red, Enum.Material.SmoothPlastic))
	for _, sx in { -1, 1 } do
		decor(block(deck, "FasciaSide", Vector3.new(0.3, 0.7, DECK_D + 0.1), CFrame.new(sx * (DECK_W / 2 + 0.15), DECK_H - 0.75, 0), PALETTE.Red, Enum.Material.SmoothPlastic))
	end

	-- Railing: red cap rail (solid, so nobody walks off the deck) on cream balusters.
	local rail = folder(deck, "Railing")
	local edgeZ = -DECK_D / 2 + 0.4
	local edgeX = DECK_W / 2 - 0.4
	local segments = {
		{ Vector3.new(-edgeX, 0, edgeZ), Vector3.new(-STAIR_W / 2 - 0.3, 0, edgeZ) },
		{ Vector3.new(STAIR_W / 2 + 0.3, 0, edgeZ), Vector3.new(edgeX, 0, edgeZ) },
		{ Vector3.new(-edgeX, 0, edgeZ), Vector3.new(-edgeX, 0, DECK_D / 2 - 0.4) },
		{ Vector3.new(edgeX, 0, edgeZ), Vector3.new(edgeX, 0, DECK_D / 2 - 0.4) },
	}
	for i, seg in segments do
		local a, b = seg[1] + Vector3.new(0, FLOOR, 0), seg[2] + Vector3.new(0, FLOOR, 0)
		beam(rail, "CapRail" .. i, a + Vector3.new(0, RAIL_H, 0), b + Vector3.new(0, RAIL_H, 0), 0.45, PALETTE.Red, Enum.Material.SmoothPlastic)
		decor(beam(rail, "BottomRail" .. i, a + Vector3.new(0, 0.5, 0), b + Vector3.new(0, 0.5, 0), 0.3, PALETTE.Cream, Enum.Material.SmoothPlastic))
		local length = (b - a).Magnitude
		local count = math.max(1, math.floor(length / 1.4))
		for k = 0, count do
			local p = a:Lerp(b, k / count)
			decor(block(rail, "Baluster", Vector3.new(0.3, RAIL_H - 0.3, 0.3), CFrame.new(p + Vector3.new(0, (RAIL_H - 0.3) / 2 + 0.1, 0)), PALETTE.Cream, Enum.Material.SmoothPlastic))
		end
		for _, p in { a, b } do
			block(rail, "Post", Vector3.new(0.6, RAIL_H + 0.3, 0.6), CFrame.new(p + Vector3.new(0, (RAIL_H + 0.3) / 2, 0)), PALETTE.Red, Enum.Material.SmoothPlastic)
		end
	end

	-- Stairs down the front, flanked by red rails.
	local stairs = folder(deck, "Stairs")
	local rise = DECK_H / (STEPS + 1)
	local frontZ = -DECK_D / 2
	for i = 1, STEPS do
		local top = DECK_H - i * rise
		local z = frontZ - (i - 0.5) * STEP_RUN
		block(stairs, "Step" .. i, Vector3.new(STAIR_W, top, STEP_RUN), CFrame.new(0, top / 2, z), PALETTE.CreamShade, Enum.Material.WoodPlanks)
		decor(block(stairs, "Nosing" .. i, Vector3.new(STAIR_W + 0.06, 0.18, 0.24), CFrame.new(0, top - 0.07, z - STEP_RUN / 2 + 0.1), PALETTE.Red, Enum.Material.SmoothPlastic))
	end
	local bottomZ = frontZ - STEPS * STEP_RUN
	for _, sx in { -1, 1 } do
		local x = sx * (STAIR_W / 2 + 0.3)
		local low = Vector3.new(x, rise + RAIL_H, bottomZ + 0.3)
		local high = Vector3.new(x, DECK_H + RAIL_H, frontZ + 0.4)
		beam(stairs, "StairRail", low, high, 0.45, PALETTE.Red, Enum.Material.SmoothPlastic)
		block(stairs, "StairPost", Vector3.new(0.6, rise + RAIL_H + 0.3, 0.6), CFrame.new(x, (rise + RAIL_H + 0.3) / 2, bottomZ + 0.3), PALETTE.Red, Enum.Material.SmoothPlastic)
		for k = 1, STEPS - 1 do
			local p = low:Lerp(high, k / STEPS)
			-- The step under this baluster (step 1 is the one next to the deck).
			local under = math.clamp(math.ceil((frontZ - p.Z) / STEP_RUN), 1, STEPS)
			local stepTop = DECK_H - under * rise
			local h = p.Y - stepTop
			decor(block(stairs, "StairBaluster", Vector3.new(0.28, h, 0.28), CFrame.new(x, stepTop + h / 2, p.Z), PALETTE.Cream, Enum.Material.SmoothPlastic))
		end
	end
end

-- The cottage ------------------------------------------------------------------------------------

-- A red diamond window with dark glass and a cream cross, on a wall whose outward normal is `normal`.
local function diamondWindow(parent: Instance, center: Vector3, normal: Vector3)
	local facing = CFrame.lookAt(center, center + normal)
	local diamond = facing * CFrame.Angles(0, 0, math.rad(45))
	decor(block(parent, "WindowFrame", Vector3.new(2.7, 2.7, 0.3), diamond * CFrame.new(0, 0, -0.1), PALETTE.Red, Enum.Material.SmoothPlastic))
	local glass = decor(block(parent, "WindowGlass", Vector3.new(1.95, 1.95, 0.32), diamond * CFrame.new(0, 0, -0.14), PALETTE.Glass, Enum.Material.Glass))
	glass.Transparency = 0.15
	decor(block(parent, "Mullion", Vector3.new(0.18, 2.1, 0.36), diamond * CFrame.new(0, 0, -0.18), PALETTE.Cream, Enum.Material.SmoothPlastic))
	decor(block(parent, "Mullion", Vector3.new(2.1, 0.18, 0.36), diamond * CFrame.new(0, 0, -0.18), PALETTE.Cream, Enum.Material.SmoothPlastic))
end

local function lantern(parent: Instance, position: Vector3)
	decor(block(parent, "LanternBracket", Vector3.new(0.25, 0.25, 0.9), CFrame.new(position + Vector3.new(0, 0, -0.45)), PALETTE.Iron, Enum.Material.Metal))
	local glass = decor(block(parent, "LanternGlass", Vector3.new(0.7, 1, 0.7), CFrame.new(position + Vector3.new(0, -0.3, -0.95)), PALETTE.LampGlass, Enum.Material.Neon))
	glass.Transparency = 0.3
	glow(glass, PALETTE.LampGlow, 14, 1)
	decor(block(parent, "LanternCap", Vector3.new(0.95, 0.2, 0.95), CFrame.new(position + Vector3.new(0, 0.3, -0.95)), PALETTE.Iron, Enum.Material.Metal))
end

local function buildHouse(model: Model)
	local house = folder(model, "House")
	local midY = FLOOR + WALL_H / 2

	-- Back and side walls.
	block(house, "WallBack", Vector3.new(HOUSE_W, WALL_H, WALL_T), CFrame.new(0, midY, BACK_Z - WALL_T / 2), PALETTE.Cream, Enum.Material.Plaster)
	for _, sx in { -1, 1 } do
		block(house, "WallSide", Vector3.new(WALL_T, WALL_H, HOUSE_D), CFrame.new(sx * (HOUSE_W / 2 - WALL_T / 2), midY, HOUSE_Z), PALETTE.Cream, Enum.Material.Plaster)
	end

	-- Front wall around the doorway: two piers and a lintel; the doorway's top is an arch built from thin
	-- cream slices (a stepped curve reads as a smooth arch at this size).
	local frontZ = FRONT_Z + WALL_T / 2
	local pierW = (HOUSE_W - DOOR_W) / 2
	for _, sx in { -1, 1 } do
		block(house, "WallFront", Vector3.new(pierW, WALL_H, WALL_T), CFrame.new(sx * (DOOR_W / 2 + pierW / 2), midY, frontZ), PALETTE.Cream, Enum.Material.Plaster)
	end
	local lintelH = WALL_H - DOOR_H
	block(house, "Lintel", Vector3.new(DOOR_W, lintelH, WALL_T), CFrame.new(0, FLOOR + DOOR_H + lintelH / 2, frontZ), PALETTE.Cream, Enum.Material.Plaster)
	local radius = DOOR_W / 2
	local springY = FLOOR + DOOR_H - radius
	local slices = 12
	for s = 0, slices - 1 do
		local y0 = springY + s * radius / slices
		local yMid = y0 + radius / slices / 2
		local half = math.sqrt(math.max(radius * radius - (yMid - springY) ^ 2, 0))
		local fill = radius - half
		if fill > 0.02 then
			for _, sx in { -1, 1 } do
				decor(block(house, "ArchFill", Vector3.new(fill, radius / slices + 0.02, WALL_T), CFrame.new(sx * (radius - fill / 2), yMid, frontZ), PALETTE.Cream, Enum.Material.Plaster))
			end
		end
	end
	-- Blue arched frame: jambs and a ring of short segments.
	for _, sx in { -1, 1 } do
		decor(block(house, "DoorJamb", Vector3.new(0.45, DOOR_H - radius, WALL_T + 0.2), CFrame.new(sx * (radius + 0.05), FLOOR + (DOOR_H - radius) / 2, frontZ), PALETTE.Blue, Enum.Material.SmoothPlastic))
	end
	local ring = 10
	for s = 0, ring - 1 do
		local a = math.pi * (s + 0.5) / ring
		local p = Vector3.new(math.cos(a) * (radius + 0.05), springY + math.sin(a) * (radius + 0.05), frontZ)
		local chord = 2 * (radius + 0.05) * math.sin(math.pi / ring / 2) + 0.1
		decor(block(house, "DoorArch", Vector3.new(chord, 0.45, WALL_T + 0.2), CFrame.new(p) * CFrame.Angles(0, 0, a - math.pi / 2), PALETTE.Blue, Enum.Material.SmoothPlastic))
	end
	-- The door stands swung all the way open, flat against the inside of the front wall (hinged on the
	-- west jamb), so the doorway is walkable and the leaf stays out of the shop camera's view.
	local leafZ = FRONT_Z + WALL_T + 0.35
	local leaf = decor(block(house, "DoorLeaf", Vector3.new(DOOR_W - 0.3, DOOR_H - 0.4, 0.35), CFrame.new(-radius - (DOOR_W - 0.3) / 2, FLOOR + (DOOR_H - 0.4) / 2, leafZ), PALETTE.Blue, Enum.Material.WoodPlanks))
	-- A round window in the leaf: a cylinder along the leaf's thin (Z) axis.
	local porthole = decor(block(house, "DoorPorthole", Vector3.new(0.45, 1.3, 1.3), leaf.CFrame * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, math.rad(90), 0), PALETTE.BlueDark, Enum.Material.Glass))
	porthole.Shape = Enum.PartType.Cylinder

	-- Softened corners, red trim bands, and the layered red roof.
	for _, sx in { -1, 1 } do
		for _, z in { FRONT_Z, BACK_Z } do
			disc(house, "Corner", WALL_H, 1.8, Vector3.new(sx * HOUSE_W / 2, midY, z), PALETTE.CreamShade, Enum.Material.Plaster)
		end
	end
	local function band(name: string, y: number, height: number)
		decor(block(house, name, Vector3.new(HOUSE_W + 0.5, height, 0.35), CFrame.new(0, y, FRONT_Z - 0.12), PALETTE.Red, Enum.Material.SmoothPlastic))
		decor(block(house, name, Vector3.new(HOUSE_W + 0.5, height, 0.35), CFrame.new(0, y, BACK_Z + 0.12), PALETTE.Red, Enum.Material.SmoothPlastic))
		for _, sx in { -1, 1 } do
			decor(block(house, name, Vector3.new(0.35, height, HOUSE_D + 0.5), CFrame.new(sx * (HOUSE_W / 2 + 0.12), y, HOUSE_Z), PALETTE.Red, Enum.Material.SmoothPlastic))
		end
	end
	band("BaseTrim", FLOOR + 0.35, 0.7)
	band("TopTrim", FLOOR + WALL_H - 0.6, 0.9)
	local roofY = FLOOR + WALL_H
	block(house, "Roof", Vector3.new(HOUSE_W + 3, 1, HOUSE_D + 3), CFrame.new(0, roofY + 0.5, HOUSE_Z), PALETTE.Red, Enum.Material.Slate)
	decor(block(house, "Eave", Vector3.new(HOUSE_W + 3.3, 0.5, HOUSE_D + 3.3), CFrame.new(0, roofY + 0.05, HOUSE_Z), PALETTE.RedDark, Enum.Material.SmoothPlastic))
	block(house, "RoofTier", Vector3.new(HOUSE_W - 3, 1.2, HOUSE_D - 3), CFrame.new(0, roofY + 1.6, HOUSE_Z), PALETTE.Red, Enum.Material.Slate)
	decor(block(house, "RoofCap", Vector3.new(HOUSE_W - 7, 0.8, HOUSE_D - 7), CFrame.new(0, roofY + 2.6, HOUSE_Z), PALETTE.RedDark, Enum.Material.Slate))
	-- A little round cupola on top.
	disc(house, "Cupola", 1.8, 3.4, Vector3.new(4, roofY + 3.9, HOUSE_Z + 1.5), PALETTE.Cream, Enum.Material.Plaster)
	decor(disc(house, "CupolaCap", 0.6, 4, Vector3.new(4, roofY + 5.1, HOUSE_Z + 1.5), PALETTE.Red, Enum.Material.Slate))

	-- Diamond windows: two on the front, two on each side.
	for _, sx in { -1, 1 } do
		diamondWindow(house, Vector3.new(sx * 7, FLOOR + 6, FRONT_Z - 0.02), Vector3.new(0, 0, -1))
		for _, z in { HOUSE_Z - 2.5, HOUSE_Z + 3 } do
			diamondWindow(house, Vector3.new(sx * (HOUSE_W / 2 + 0.02), FLOOR + 6, z), Vector3.new(sx, 0, 0))
		end
	end

	-- Porch lanterns either side of the door.
	for _, sx in { -1, 1 } do
		lantern(house, Vector3.new(sx * 3.9, FLOOR + 6.6, FRONT_Z))
	end

	-- Vines: climbing the left of the door, arching over it, and spilling from the roof edge.
	local vines = folder(house, "Vines")
	local function leafAt(i: number, position: Vector3, size: number)
		local color = if hash(i, position.X) > 0.5 then PALETTE.Leaf else PALETTE.LeafDark
		decor(ball(vines, "Leaf", size, position, color, Enum.Material.Grass))
	end
	local n = 0
	for k = 0, 16 do -- up the wall left of the door
		n += 1
		local t = k / 16
		local x = -radius - 1.2 - math.sin(t * 5) * 0.6
		leafAt(n, Vector3.new(x, FLOOR + 0.4 + t * (DOOR_H + 0.6), FRONT_Z - 0.35), 0.8 + hash(n, 3) * 0.6)
	end
	for k = 0, 12 do -- over the arch
		n += 1
		local a = math.pi * (1 - k / 12)
		leafAt(n, Vector3.new(math.cos(a) * (radius + 0.9), springY + math.sin(a) * (radius + 0.9), FRONT_Z - 0.35), 0.7 + hash(n, 5) * 0.5)
	end
	for k = 0, 22 do -- draped along the front roof edge
		n += 1
		local x = -HOUSE_W / 2 - 1 + k * (HOUSE_W + 2) / 22
		local droop = if hash(n, 7) > 0.7 then 1.2 + hash(n, 9) * 1.4 else 0.3
		leafAt(n, Vector3.new(x, roofY - droop, FRONT_Z - 1.6), 0.8 + hash(n, 11) * 0.7)
	end
	for k = 0, 9 do -- the left front corner
		n += 1
		leafAt(n, Vector3.new(-HOUSE_W / 2 - 0.4, FLOOR + 1 + k * 1.05, FRONT_Z - 0.4 + hash(n, 13) * 0.8), 0.9 + hash(n, 15) * 0.5)
	end
end

-- The high-tech room inside ------------------------------------------------------------------------

local function neonStrip(parent: Instance, size: Vector3, cframe: CFrame, color: Color3)
	local strip = decor(block(parent, "NeonStrip", size, cframe, color, Enum.Material.Neon))
	strip.CastShadow = false
	return strip
end

local function screen(parent: Instance, cframe: CFrame, title: string, subtitle: string)
	decor(block(parent, "ScreenFrame", Vector3.new(4.4, 2.8, 0.2), cframe, PALETTE.PanelEdge, Enum.Material.Metal))
	local glass = decor(block(parent, "Screen", Vector3.new(4.1, 2.5, 0.22), cframe * CFrame.new(0, 0, -0.02), Color3.fromRGB(8, 20, 30), Enum.Material.Glass))
	neonStrip(parent, Vector3.new(4.4, 0.08, 0.24), cframe * CFrame.new(0, 1.4, -0.03), PALETTE.Holo)
	neonStrip(parent, Vector3.new(4.4, 0.08, 0.24), cframe * CFrame.new(0, -1.4, -0.03), PALETTE.Holo)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(410, 250)
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.Parent = glass
	local head = Instance.new("TextLabel")
	head.BackgroundTransparency = 1
	head.Size = UDim2.fromScale(1, 0.55)
	head.FontFace = SIGN_FONT
	head.TextScaled = true
	head.TextColor3 = PALETTE.Holo
	head.Text = title
	head.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromScale(0, 0.58)
	sub.Size = UDim2.fromScale(1, 0.3)
	sub.FontFace = SIGN_FONT
	sub.TextScaled = true
	sub.TextColor3 = PALETTE.HoloPink
	sub.Text = subtitle
	sub.Parent = gui
end

local function buildInterior(model: Model)
	local room = folder(model, "Interior")
	local innerW = HOUSE_W - WALL_T * 2
	local innerD = HOUSE_D - WALL_T * 2
	local innerBack = BACK_Z - WALL_T
	local innerFront = FRONT_Z + WALL_T
	local ceiling = FLOOR + WALL_H

	-- Dark metal floor with a panel grid, dark wall panels, and a ceiling.
	decor(block(room, "FloorPlate", Vector3.new(innerW, 0.08, innerD), CFrame.new(0, FLOOR + 0.04, HOUSE_Z), PALETTE.Panel, Enum.Material.DiamondPlate))
	decor(block(room, "PanelBack", Vector3.new(innerW, WALL_H, 0.15), CFrame.new(0, FLOOR + WALL_H / 2, innerBack - 0.075), PALETTE.Panel, Enum.Material.SmoothPlastic))
	for _, sx in { -1, 1 } do
		decor(block(room, "PanelSide", Vector3.new(0.15, WALL_H, innerD), CFrame.new(sx * (innerW / 2 - 0.075), FLOOR + WALL_H / 2, HOUSE_Z), PALETTE.Panel, Enum.Material.SmoothPlastic))
	end
	for _, sx in { -1, 1 } do
		local pierW = (innerW - DOOR_W) / 2
		decor(block(room, "PanelFront", Vector3.new(pierW, WALL_H, 0.15), CFrame.new(sx * (DOOR_W / 2 + pierW / 2), FLOOR + WALL_H / 2, innerFront + 0.075), PALETTE.Panel, Enum.Material.SmoothPlastic))
	end
	decor(block(room, "Ceiling", Vector3.new(innerW, 0.15, innerD), CFrame.new(0, ceiling - 0.075, HOUSE_Z), PALETTE.Panel, Enum.Material.SmoothPlastic))

	-- Neon: floor and ceiling lines round the room, magenta verticals in the back corners.
	for _, y in { FLOOR + 0.5, ceiling - 0.6 } do
		neonStrip(room, Vector3.new(innerW - 0.4, 0.1, 0.1), CFrame.new(0, y, innerBack - 0.2), PALETTE.Holo)
		for _, sx in { -1, 1 } do
			neonStrip(room, Vector3.new(0.1, 0.1, innerD - 0.4), CFrame.new(sx * (innerW / 2 - 0.2), y, HOUSE_Z), PALETTE.Holo)
		end
	end
	for _, sx in { -1, 1 } do
		neonStrip(room, Vector3.new(0.12, WALL_H - 1, 0.12), CFrame.new(sx * (innerW / 2 - 0.25), FLOOR + WALL_H / 2, innerBack - 0.25), PALETTE.HoloPink)
	end

	-- Two screens on the side walls just inside the door: seen when you walk in, but outside the menu
	-- camera's view (on the back wall their text showed through the menu's glass panels).
	for _, sx in { -1, 1 } do
		local x = sx * (innerW / 2 - 0.3)
		local at = CFrame.lookAt(Vector3.new(x, FLOOR + 5.5, innerFront + 3), Vector3.new(x - sx * 5, FLOOR + 5.5, innerFront + 3))
		screen(room, at, if sx < 0 then "ショップ" else "CREDITS", if sx < 0 then "FIGHTER EXCHANGE" else Currency.SHORT .. " ONLY // NO REFUNDS")
	end

	-- The hologram projector pad, with its ring light above.
	local padCenter = Vector3.new(0, FLOOR, STAGE_Z)
	disc(room, "PadBase", 0.5, 6.4, padCenter + Vector3.new(0, 0.25, 0), PALETTE.PanelEdge, Enum.Material.Metal)
	neonStrip(room, Vector3.new(0.12, 6.6, 6.6), CFrame.new(padCenter + Vector3.new(0, 0.44, 0)) * CFrame.Angles(0, 0, math.rad(90)), PALETTE.Holo).Shape = Enum.PartType.Cylinder
	local lens = decor(disc(room, "PadLens", 0.14, 5.2, padCenter + Vector3.new(0, 0.52, 0), PALETTE.Holo, Enum.Material.Glass))
	lens.Transparency = 0.45
	local beamPart = decor(disc(room, "HoloBeam", 7, 5, padCenter + Vector3.new(0, 4.1, 0), PALETTE.Holo, Enum.Material.Neon))
	beamPart.Transparency = 0.9 -- a faint column of light, not a solid
	beamPart.CastShadow = false
	local halo = neonStrip(room, Vector3.new(0.12, 5.6, 5.6), CFrame.new(padCenter + Vector3.new(0, WALL_H - 0.9, 0)) * CFrame.Angles(0, 0, math.rad(90)), PALETTE.Holo)
	halo.Shape = Enum.PartType.Cylinder
	glow(halo, PALETTE.Holo, 16, 1.6)
	local fill = hide(decor(block(room, "MagentaFill", Vector3.one, CFrame.new(0, FLOOR + 6, innerBack - 1), PALETTE.HoloPink, Enum.Material.SmoothPlastic)))
	glow(fill, PALETTE.HoloPink, 14, 0.8)
end

-- Framing trees and the sign ------------------------------------------------------------------------

local function bigTree(parent: Instance, name: string, x: number, z: number, lean: number)
	local tree = Instance.new("Model")
	tree.Name = name
	-- A thick, slightly leaning trunk from stacked tapering sections, with root flares.
	local sections = { { 3.8, 4 }, { 3.3, 4 }, { 2.8, 4 }, { 2.3, 4 }, { 1.8, 3 } }
	local y = 0
	for i, s in sections do
		local d, h = s[1], s[2]
		disc(tree, "Trunk" .. i, h, d, Vector3.new(x + lean * y, y + h / 2, z), PALETTE.Bark, Enum.Material.Wood)
		y += h
	end
	for r = 0, 3 do
		local a = r * math.pi / 2 + 0.4
		decor(block(tree, "Root", Vector3.new(1.2, 1.4, 3.2), CFrame.new(x + math.cos(a) * 2, 0.5, z + math.sin(a) * 2) * CFrame.Angles(0, -a, math.rad(18)), PALETTE.Bark, Enum.Material.Wood))
	end
	-- A dark, dense canopy with purple masses mixed in.
	local top = Vector3.new(x + lean * y, y, z)
	local masses = {
		{ Vector3.new(0, 1.5, 0), 11, PALETTE.Canopy },
		{ Vector3.new(4, 0, 2), 8, PALETTE.Purple },
		{ Vector3.new(-4.5, 0.5, -1.5), 8.5, PALETTE.Canopy },
		{ Vector3.new(1.5, 3.5, -3.5), 7.5, PALETTE.PurpleDark },
		{ Vector3.new(-2, 4.2, 3), 7, PALETTE.Canopy },
		{ Vector3.new(3.5, -2, -3), 6.5, PALETTE.Canopy },
		{ Vector3.new(-3.5, -2.2, 3.5), 6, PALETTE.Purple },
		{ Vector3.new(0, 6, 0), 6, PALETTE.PurpleDark },
	}
	for i, m in masses do
		decor(ball(tree, "Canopy" .. i, m[2], top + m[1], m[3], Enum.Material.Grass))
	end
	tree.Parent = parent
end

local function buildSign(model: Model)
	local anchor = hide(decor(block(model, "SignAnchor", Vector3.one, CFrame.new(0, FLOOR + WALL_H + 8.5, HOUSE_Z), PALETTE.Cream, Enum.Material.SmoothPlastic)))
	local sign = Instance.new("BillboardGui")
	sign.Name = "ShopSign"
	sign.Size = UDim2.fromScale(14, 5)
	sign.MaxDistance = 260
	sign.LightInfluence = 0
	sign.Parent = anchor
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.66)
	title.FontFace = SIGN_FONT
	title.TextScaled = true
	title.TextColor3 = PALETTE.Holo
	title.TextStrokeColor3 = Color3.fromRGB(10, 30, 40)
	title.TextStrokeTransparency = 0.2
	title.Text = "SHOP"
	title.Parent = sign
	local kana = Instance.new("TextLabel")
	kana.BackgroundTransparency = 1
	kana.Position = UDim2.fromScale(0, 0.64)
	kana.Size = UDim2.fromScale(1, 0.34)
	kana.FontFace = SIGN_FONT
	kana.TextScaled = true
	kana.TextColor3 = PALETTE.HoloPink
	kana.TextStrokeTransparency = 0.4
	kana.Text = "ショップ · " .. Currency.SHORT
	kana.Parent = sign
end

function ShopHouse.build(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "ShopHouse"

	local root = hide(decor(block(model, "Root", Vector3.one, CFrame.new(0, 0, 0), PALETTE.Cream, Enum.Material.SmoothPlastic)))
	model.PrimaryPart = root

	buildDeck(model)
	buildHouse(model)
	buildInterior(model)
	local trees = folder(model, "Trees")
	bigTree(trees, "TreeWest", -24, 1, 0.12)
	bigTree(trees, "TreeEast", 24, 2, -0.1)
	buildSign(model)

	-- Game-code anchors.
	local door = hide(decor(block(model, "ShopDoor", Vector3.new(DOOR_W - 0.5, DOOR_H - 1, 1), CFrame.new(0, FLOOR + (DOOR_H - 1) / 2, FRONT_Z + WALL_T / 2), PALETTE.Blue, Enum.Material.SmoothPlastic)))
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Enter Shop"
	prompt.ObjectText = Currency.SHOP
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Action", "Shop")
	prompt.Parent = door
	local stagePos = Vector3.new(0, FLOOR + 0.55, STAGE_Z)
	hide(decor(block(model, "ShopStage", Vector3.new(1, 0.1, 1), CFrame.lookAt(stagePos, stagePos + Vector3.new(0, 0, -1)), PALETTE.Holo, Enum.Material.SmoothPlastic)))
	local camPos = Vector3.new(0, FLOOR + 4.6, FRONT_Z + WALL_T + 0.6)
	hide(decor(block(model, "ShopCamera", Vector3.new(1, 1, 1), CFrame.lookAt(camPos, Vector3.new(0, FLOOR + 3, STAGE_Z)), PALETTE.Holo, Enum.Material.SmoothPlastic)))

	model.Parent = parent
	return model
end

return ShopHouse
