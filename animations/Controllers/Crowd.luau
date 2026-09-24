-- The colosseum crowd (owner-approved 2026-09-23: "fans and characters with different designs and
-- uniqueness, all seeming to watch the battle, colosseum style, filled").
--
-- Each client builds its own crowd from the arena's Crowd/Row* configurations (radius, height, seats to
-- avoid), so the server never replicates thousands of parts. Spectators are stylised part figures:
--   * fans (most): varied build, skin, outfit and headwear, some holding flags, signs, foam fingers,
--     glow sticks or drums;
--   * characters sprinkled in: robed monks, masked ninjas, armoured guards, robots, mascots, oni, samurai.
-- Behaviour: an idle sway; heads follow the fighter nearest their section; the whole bowl erupts when
-- someone is eliminated (loudest near it); a stadium wave rolls round every so often.
-- Performance: every part is anchored and never collides, casts shadows or takes raycasts; a slice of
-- the crowd is re-posed each frame with one BulkMoveTo; density follows the graphics quality.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Constants"))

local Crowd = {}

local SECTIONS = 24 -- head-tracking sections round the bowl

local SKINS = {
	Color3.fromRGB(255, 219, 172), Color3.fromRGB(241, 194, 125), Color3.fromRGB(224, 172, 105),
	Color3.fromRGB(198, 134, 66), Color3.fromRGB(141, 85, 36), Color3.fromRGB(94, 58, 30),
}
local SHIRTS = {
	Color3.fromRGB(200, 40, 50), Color3.fromRGB(40, 90, 200), Color3.fromRGB(240, 200, 40), Color3.fromRGB(40, 150, 80),
	Color3.fromRGB(130, 60, 170), Color3.fromRGB(240, 120, 30), Color3.fromRGB(235, 235, 235), Color3.fromRGB(30, 30, 36),
	Color3.fromRGB(60, 190, 200), Color3.fromRGB(230, 90, 150),
}
local PANTS = { Color3.fromRGB(40, 44, 60), Color3.fromRGB(70, 60, 50), Color3.fromRGB(30, 30, 34), Color3.fromRGB(90, 96, 110), Color3.fromRGB(120, 100, 70) }
local HAIR = { Color3.fromRGB(20, 20, 24), Color3.fromRGB(90, 60, 30), Color3.fromRGB(230, 200, 90), Color3.fromRGB(200, 60, 40), Color3.fromRGB(80, 120, 230), Color3.fromRGB(240, 240, 240) }
local BRIGHT = { Color3.fromRGB(255, 80, 150), Color3.fromRGB(80, 230, 255), Color3.fromRGB(255, 230, 60), Color3.fromRGB(120, 255, 120) }
local METAL = Color3.fromRGB(150, 158, 170)

-- Groups a part moves with: 0 = static (legs), 1 = body, 2 = head, 3 = left arm, 4 = right arm.
type Spec = {
	base: CFrame,
	angle: number, -- degrees round the bowl
	section: number,
	scale: number,
	shoulder: number,
	phase: number,
	energy: number,
	style: string, -- "fan" | "flag" | "sign" | "drum" | ...
	parts: { BasePart },
	groups: { number },
	offsets: { CFrame },
	excite: number,
	exciteAt: number,
}

local crowdFolder: Folder? = nil
local specs: { Spec } = {}
local cursor = 1
local building = false
local builtFor: Instance? = nil
local center = Vector3.zero
local targets: { Vector3? } = {}
local lastTargets = 0
local waveStart: number? = nil
local nextWave = 0
local waveFrom = 0
local token = 0

local function pick(rng: Random, list: { any }): any
	return list[rng:NextInteger(1, #list)]
end

-- Player setting (Phase 4): "Auto" (graphics quality, capped on touch devices), "Off", "Low", "Medium", "High".
local densityChoice = "Auto"

local function density(): number
	if densityChoice == "Off" then
		return 0
	elseif densityChoice == "Low" then
		return Constants.CROWD_DENSITY_LOW
	elseif densityChoice == "Medium" then
		return Constants.CROWD_DENSITY_MID
	elseif densityChoice == "High" then
		return 1
	end
	local d = 1
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	end)
	if ok and type(level) == "number" and level > 0 then
		d = if level <= 3 then Constants.CROWD_DENSITY_LOW elseif level <= 6 then Constants.CROWD_DENSITY_MID else 1
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		d = math.min(d, Constants.CROWD_DENSITY_TOUCH_MAX)
	end
	return d
end

-- Building ---------------------------------------------------------------------------------------

local function newPart(spec: Spec, group: number, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	table.insert(spec.parts, p)
	table.insert(spec.groups, group)
	table.insert(spec.offsets, offset)
	return p
end

local function makeSpectator(rng: Random, base: CFrame, angle: number): Spec
	local s = rng:NextNumber(0.85, 1.1)
	local w = rng:NextNumber(0.85, 1.1) -- build: slim to broad (kept inside a seat's width)
	local spec: Spec = {
		base = base,
		angle = angle,
		section = math.floor(((angle % 360) / 360) * SECTIONS) + 1,
		scale = s,
		shoulder = (0.85 * w + 0.28) * s,
		phase = rng:NextNumber(0, math.pi * 2),
		energy = rng:NextNumber(0.35, 1),
		style = "fan",
		parts = {},
		groups = {},
		offsets = {},
		excite = 0,
		exciteAt = 0,
	}
	local skin, shirt, pants = pick(rng, SKINS), pick(rng, SHIRTS), pick(rng, PANTS)
	local headColor, headShape, headSize = skin, Enum.PartType.Block, 1.15 * s
	local sleeves = shirt
	local roll = rng:NextNumber()
	local kind = "fan"
	if roll < 0.05 then
		kind, shirt, pants, sleeves = "monk", Color3.fromRGB(235, 130, 40), Color3.fromRGB(235, 130, 40), skin
	elseif roll < 0.09 then
		kind, shirt, pants, sleeves, headColor = "ninja", Color3.fromRGB(26, 26, 32), Color3.fromRGB(26, 26, 32), Color3.fromRGB(26, 26, 32), Color3.fromRGB(26, 26, 32)
	elseif roll < 0.12 then
		kind, shirt, sleeves = "guard", METAL, METAL
	elseif roll < 0.145 then
		kind, shirt, pants, sleeves, headColor = "robot", Color3.fromRGB(90, 110, 140), Color3.fromRGB(60, 70, 90), Color3.fromRGB(120, 130, 150), METAL
	elseif roll < 0.165 then
		kind = "mascot"
		local bright = pick(rng, BRIGHT)
		shirt, sleeves, headColor, headShape, headSize = bright, bright, bright, Enum.PartType.Ball, 2.1 * s
	elseif roll < 0.19 then
		kind, headColor, shirt = "oni", Color3.fromRGB(200, 40, 40), Color3.fromRGB(40, 30, 40)
	elseif roll < 0.215 then
		kind, shirt, sleeves = "samurai", Color3.fromRGB(170, 30, 36), Color3.fromRGB(60, 20, 24)
	end

	-- Body.
	newPart(spec, 0, Vector3.new(1.5 * w, 1.7, 0.85) * s, CFrame.new(0, 0.85 * s, 0), pants)
	newPart(spec, 1, Vector3.new(1.7 * w, 1.8, 0.95) * s, CFrame.new(), shirt, if kind == "guard" then Enum.Material.DiamondPlate else nil)
	newPart(spec, 2, Vector3.one * headSize, CFrame.new(0, headSize / 2, 0), headColor, nil, headShape)
	for _, side in { -1, 1 } do
		newPart(spec, if side < 0 then 3 else 4, Vector3.new(0.55, 1.65, 0.55) * s, CFrame.new(0, -0.8 * s, 0), sleeves)
	end
	local top = headSize -- head-group y of the top of the head

	-- Headwear and character details.
	if kind == "monk" then
		newPart(spec, 1, Vector3.new(1.75 * w, 0.2, 1) * s, CFrame.new(0, 0.7 * s, 0), Color3.fromRGB(100, 60, 30)) -- beads
	elseif kind == "ninja" then
		newPart(spec, 2, Vector3.new(1.18, 0.14, 0.2) * s, CFrame.new(0, 0.65 * s, -0.5 * s), Color3.fromRGB(255, 60, 60), Enum.Material.Neon) -- eye slit
	elseif kind == "guard" then
		newPart(spec, 2, Vector3.one * 1.5 * s, CFrame.new(0, top * 0.62, 0), METAL, Enum.Material.Metal, Enum.PartType.Ball)
	elseif kind == "robot" then
		newPart(spec, 2, Vector3.new(0.95, 0.22, 0.2) * s, CFrame.new(0, 0.65 * s, -0.5 * s), Color3.fromRGB(80, 230, 255), Enum.Material.Neon)
		newPart(spec, 2, Vector3.new(0.1, 0.7, 0.1) * s, CFrame.new(0, top + 0.35 * s, 0), METAL, Enum.Material.Metal)
		newPart(spec, 2, Vector3.one * 0.3 * s, CFrame.new(0, top + 0.75 * s, 0), Color3.fromRGB(255, 80, 80), Enum.Material.Neon, Enum.PartType.Ball)
	elseif kind == "oni" then
		for _, side in { -1, 1 } do
			newPart(spec, 2, Vector3.new(0.22, 0.6, 0.22) * s, CFrame.new(side * 0.35 * s, top + 0.2 * s, 0) * CFrame.Angles(0, 0, math.rad(-side * 18)), Color3.fromRGB(240, 235, 220))
		end
	elseif kind == "samurai" then
		newPart(spec, 2, Vector3.new(1.35, 0.45, 1.35) * s, CFrame.new(0, top - 0.05 * s, 0), Color3.fromRGB(40, 36, 40), Enum.Material.Metal)
		newPart(spec, 2, Vector3.new(0.9, 0.5, 0.1) * s, CFrame.new(0, top + 0.35 * s, -0.4 * s), Color3.fromRGB(230, 190, 80), Enum.Material.Metal)
	elseif kind == "fan" then
		local hat = rng:NextNumber()
		local hair = pick(rng, HAIR)
		if hat < 0.15 then -- cap
			newPart(spec, 2, Vector3.new(1.22, 0.35, 1.22) * s, CFrame.new(0, top, 0), pick(rng, SHIRTS))
			newPart(spec, 2, Vector3.new(1, 0.12, 0.6) * s, CFrame.new(0, top - 0.12 * s, -0.8 * s), pick(rng, SHIRTS))
		elseif hat < 0.27 then -- bandana
			newPart(spec, 2, Vector3.new(1.22, 0.28, 1.22) * s, CFrame.new(0, top - 0.3 * s, 0), pick(rng, SHIRTS), Enum.Material.Fabric)
		elseif hat < 0.42 then -- spiky hair
			for k = -1, 1 do
				newPart(spec, 2, Vector3.new(0.45, 0.7, 0.45) * s, CFrame.new(k * 0.35 * s, top + 0.15 * s, 0) * CFrame.Angles(0, 0, math.rad(-k * 25)), hair)
			end
		elseif hat < 0.5 then -- hood
			newPart(spec, 2, Vector3.one * 1.45 * s, CFrame.new(0, top * 0.55, 0.12 * s), pick(rng, SHIRTS), Enum.Material.Fabric, Enum.PartType.Ball)
		elseif hat < 0.58 then -- afro
			newPart(spec, 2, Vector3.one * 1.6 * s, CFrame.new(0, top * 0.75, 0.1 * s), hair, nil, Enum.PartType.Ball)
		elseif hat < 0.65 then -- glowing headband
			newPart(spec, 2, Vector3.new(1.2, 0.18, 1.2) * s, CFrame.new(0, top - 0.35 * s, 0), pick(rng, BRIGHT), Enum.Material.Neon)
		elseif hat < 0.72 then -- topknot
			newPart(spec, 2, Vector3.new(1.18, 0.25, 1.18) * s, CFrame.new(0, top - 0.05 * s, 0), hair)
			newPart(spec, 2, Vector3.one * 0.5 * s, CFrame.new(0, top + 0.3 * s, 0.1 * s), hair, nil, Enum.PartType.Ball)
		elseif hat < 0.75 then -- horned headband
			for _, side in { -1, 1 } do
				newPart(spec, 2, Vector3.new(0.2, 0.5, 0.2) * s, CFrame.new(side * 0.4 * s, top + 0.15 * s, 0), Color3.fromRGB(240, 240, 240))
			end
		end
	end

	-- What they're holding (on the right hand unless noted).
	local hand = CFrame.new(0, -1.55 * s, 0)
	local item = rng:NextNumber()
	if kind == "guard" then
		spec.style = "spear"
		newPart(spec, 4, Vector3.new(0.14, 5, 0.14) * s, hand * CFrame.new(0, -1.2 * s, 0), Color3.fromRGB(90, 60, 40), Enum.Material.Wood)
		newPart(spec, 4, Vector3.new(0.3, 0.7, 0.14) * s, hand * CFrame.new(0, -3.9 * s, 0), METAL, Enum.Material.Metal)
	elseif kind == "fan" and item < 0.09 then
		spec.style = "flag"
		newPart(spec, 4, Vector3.new(0.12, 3.4, 0.12) * s, hand * CFrame.new(0, -1.5 * s, 0), Color3.fromRGB(60, 50, 40), Enum.Material.Wood)
		newPart(spec, 4, Vector3.new(0.08, 1.2, 1.9) * s, hand * CFrame.new(0, -2.6 * s, 0.95 * s), pick(rng, SHIRTS), Enum.Material.Fabric)
	elseif kind == "fan" and item < 0.16 then
		spec.style = "finger"
		newPart(spec, 4, Vector3.new(0.7, 1.4, 0.35) * s, hand * CFrame.new(0, -0.6 * s, 0), pick(rng, BRIGHT), Enum.Material.Foil)
	elseif kind == "fan" and item < 0.25 then
		spec.style = "glow"
		newPart(spec, 4, Vector3.new(0.14, 1.1, 0.14) * s, hand * CFrame.new(0, -0.45 * s, 0), pick(rng, BRIGHT), Enum.Material.Neon)
	elseif kind == "fan" and item < 0.31 then
		spec.style = "sign"
		newPart(spec, 4, Vector3.new(2.6, 1.5, 0.12) * s, hand * CFrame.new(0.6 * s, -0.8 * s, 0), Color3.fromRGB(245, 240, 225))
		newPart(spec, 4, Vector3.new(2.2, 0.35, 0.14) * s, hand * CFrame.new(0.6 * s, -0.8 * s, 0), pick(rng, SHIRTS), Enum.Material.Neon)
	elseif kind == "fan" and item < 0.335 then
		spec.style = "drum"
		newPart(spec, 1, Vector3.new(1, 1.3, 1.3) * s, CFrame.new(0, -0.3 * s, -0.95 * s) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(170, 40, 30), Enum.Material.Wood, Enum.PartType.Cylinder)
	elseif kind == "mascot" then
		spec.style = "flap"
	end
	return spec
end

-- Posing -----------------------------------------------------------------------------------------

local function waveAt(angle: number, now: number): number
	if not waveStart then
		return 0
	end
	local front = waveFrom + (now - waveStart) / Constants.CROWD_WAVE_SECONDS * 360
	local diff = math.abs(((angle - front + 180) % 360) - 180)
	return math.max(0, 1 - diff / 18)
end

local function armPose(spec: Spec, cheer: number, now: number, side: number): CFrame
	local p = spec.phase
	-- Idle: arms hang with a small sway. Cheering: up overhead and waving.
	local idleX = 0.1 + math.sin(now * 1.3 + p + side) * 0.07
	local upX = 2.75 + math.sin(now * 9 + p + side * 1.3) * 0.3
	local x = idleX + (upX - idleX) * cheer
	local z = side * (0.08 + 0.3 * cheer + math.sin(now * 8 + p) * 0.12 * cheer)
	local style = spec.style
	if side > 0 and (style == "flag" or style == "sign" or style == "finger" or style == "glow") then
		x = math.max(x, 2.3 + math.sin(now * 2.2 + p) * 0.35) -- always held up, swaying
	elseif style == "sign" then
		x = math.max(x, 2.5)
	elseif style == "drum" then
		x = 1.2 + math.abs(math.sin(now * (6 + 6 * cheer) + p + side * 1.6)) * 0.6 -- drumming
		z = -side * 0.35
	elseif style == "spear" and side > 0 then
		x = 0.35 + cheer * 0.6
	elseif style == "flap" then
		z = side * (0.4 + math.abs(math.sin(now * 6 + p)) * (0.6 + cheer))
	end
	return CFrame.Angles(x, 0, z)
end

-- Re-poses one spectator, appending its moving parts and their CFrames.
local function pose(spec: Spec, now: number, parts: { BasePart }, cframes: { CFrame })
	local excite = math.max(0, spec.excite - (now - spec.exciteAt) * Constants.CROWD_EXCITE_DECAY)
	local idleCheer = math.max(0, math.sin(now * 0.4 + spec.phase * 3)) ^ 12 * spec.energy -- the odd random whoop
	-- Amplified, so a moderate cheer already throws the arms right up.
	local cheer = math.min(1, math.max(excite, idleCheer, waveAt(spec.angle, now)) * 1.5)
	local s = spec.scale
	local bounce = math.sin(now * 2.2 + spec.phase) * 0.05 + cheer * math.abs(math.sin(now * 7 + spec.phase)) * 0.45
	local body = spec.base * CFrame.new(0, 2.6 * s + bounce, 0) * CFrame.Angles(-0.12 * cheer, 0, 0)
	-- The head follows the fight in this spectator's section.
	local yaw = 0
	local target = targets[spec.section]
	if target then
		local d = spec.base:PointToObjectSpace(target)
		yaw = math.clamp(math.atan2(-d.X, -d.Z), -1.1, 1.1)
	end
	local head = body * CFrame.new(0, 0.9 * s, 0) * CFrame.Angles(0.15 * cheer, yaw, 0)
	local armL = body * CFrame.new(-spec.shoulder, 0.75 * s, 0) * armPose(spec, cheer, now, -1)
	local armR = body * CFrame.new(spec.shoulder, 0.75 * s, 0) * armPose(spec, cheer, now, 1)
	local frames = { body, head, armL, armR }
	for i, part in spec.parts do
		local group = spec.groups[i]
		if group > 0 then
			table.insert(parts, part)
			table.insert(cframes, frames[group] * spec.offsets[i])
		end
	end
end

-- Seating ----------------------------------------------------------------------------------------

local function parseAvoid(text: any): { { number } }
	local list = {}
	if type(text) == "string" then
		for a, half in string.gmatch(text, "([%d%.%-]+):([%d%.]+)") do
			table.insert(list, { tonumber(a) :: number, tonumber(half) :: number })
		end
	end
	return list
end

local function avoided(angle: number, list: { { number } }): boolean
	for _, item in list do
		if math.abs(((angle - item[1] + 180) % 360) - 180) <= item[2] then
			return true
		end
	end
	return false
end

local function clear()
	token += 1
	if crowdFolder then
		crowdFolder:Destroy()
		crowdFolder = nil
	end
	table.clear(specs)
	cursor = 1
	builtFor = nil
	building = false
end

local function build(map: Model, crowdConfig: Instance)
	clear()
	token += 1
	local myToken = token
	building = true
	builtFor = map
	local folder = Instance.new("Folder")
	folder.Name = "NAU_Crowd"
	folder.Parent = workspace
	crowdFolder = folder
	local origin = map:GetPivot()
	center = origin.Position
	local fill = density()
	local rng = Random.new(20260923)
	local seats = {}
	for _, row in crowdConfig:GetChildren() do
		local radius, y = row:GetAttribute("Radius"), row:GetAttribute("Y")
		if type(radius) == "number" and type(y) == "number" then
			local avoid = parseAvoid(row:GetAttribute("Avoid"))
			local count = math.floor(2 * math.pi * radius / Constants.CROWD_SEAT_SPACING)
			local offset = rng:NextNumber(0, 360 / count) -- rows don't line up in columns
			for k = 0, count - 1 do
				local angle = offset + k * 360 / count
				if not avoided(angle, avoid) and rng:NextNumber() <= fill then
					local r = math.rad(angle)
					local jitter = rng:NextNumber(-0.25, 0.25)
					local localPos = Vector3.new(math.cos(r) * (radius + jitter), y, math.sin(r) * (radius + jitter))
					local world = origin * localPos
					table.insert(seats, { angle = angle, cf = CFrame.lookAt(world, Vector3.new(center.X, world.Y, center.Z)) })
				end
			end
		end
	end
	local perFrame = Constants.CROWD_BUILD_PER_FRAME
	for i, seat in seats do
		if myToken ~= token then
			return
		end
		local spec = makeSpectator(rng, seat.cf, seat.angle)
		-- First pose, then parent (so nothing flashes at the origin).
		local parts, cframes = {}, {}
		for j, part in spec.parts do
			local group = spec.groups[j]
			if group == 0 then
				part.CFrame = spec.base * spec.offsets[j]
			end
		end
		pose(spec, os.clock(), parts, cframes)
		for j, part in parts do
			part.CFrame = cframes[j]
		end
		for _, part in spec.parts do
			part.Parent = folder
		end
		table.insert(specs, spec)
		if i % perFrame == 0 then
			RunService.Heartbeat:Wait()
		end
	end
	building = false
end

-- Per frame ------------------------------------------------------------------------------------

local function updateTargets(now: number)
	if now - lastTargets < 0.5 then
		return
	end
	lastTargets = now
	local fighters = {}
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - center).Magnitude < 90 then
			table.insert(fighters, root.Position)
		end
	end
	for section = 1, SECTIONS do
		local a = math.rad((section - 0.5) * 360 / SECTIONS)
		local seat = center + Vector3.new(math.cos(a) * 80, 0, math.sin(a) * 80)
		local best, bestDistance = nil, math.huge
		for _, position in fighters do
			local d = (position - seat).Magnitude
			if d < bestDistance then
				best, bestDistance = position, d
			end
		end
		targets[section] = best or center
	end
end

local function step()
	if #specs == 0 then
		return
	end
	local now = os.clock()
	updateTargets(now)
	if now >= nextWave then
		waveStart = now
		waveFrom = math.random(0, 359)
		nextWave = now + Constants.CROWD_WAVE_EVERY
	elseif waveStart and now - waveStart > Constants.CROWD_WAVE_SECONDS + 1 then
		waveStart = nil
	end
	local parts, cframes = {}, {}
	local n = math.min(Constants.CROWD_UPDATES_PER_FRAME, #specs)
	for _ = 1, n do
		if cursor > #specs then
			cursor = 1
		end
		local spec = specs[cursor]
		cursor += 1
		if spec.parts[1].Parent then
			pose(spec, now, parts, cframes)
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- The crowd reacts to an elimination at `position`: the whole bowl cheers, loudest nearest it.
function Crowd.react(position: Vector3)
	if #specs == 0 then
		return
	end
	local now = os.clock()
	local offset = position - center
	local angle = math.deg(math.atan2(offset.Z, offset.X))
	for _, spec in specs do
		local diff = math.abs(((spec.angle - angle + 180) % 360) - 180)
		local strength = 1 - diff / 180 * (1 - Constants.CROWD_FAR_CHEER)
		local current = math.max(0, spec.excite - (now - spec.exciteAt) * Constants.CROWD_EXCITE_DECAY)
		spec.excite = math.max(current, strength)
		spec.exciteAt = now
	end
end

function Crowd.count(): number
	return #specs
end

-- Changing the density rebuilds the crowd of the arena that's loaded (if any) straight away.
function Crowd.setDensity(choice: string)
	if choice == densityChoice then
		return
	end
	densityChoice = choice
	local map = builtFor
	local config = map and map:FindFirstChild("Crowd")
	if map and config and map.Parent then
		task.spawn(build, map, config)
	end
end

local started = false
function Crowd.start()
	if started then
		return
	end
	started = true
	nextWave = os.clock() + 10
	RunService.Heartbeat:Connect(step)
	task.spawn(function()
		local world = workspace:WaitForChild("NAUWorld", 120)
		if not world then
			return
		end
		local function consider(child: Instance)
			if child:IsA("Model") and child ~= builtFor then
				local config = child:WaitForChild("Crowd", 10)
				if config and child.Parent == world then
					task.spawn(build, child, config)
				end
			end
		end
		for _, child in world:GetChildren() do
			if child.Name ~= "Lobby" then
				consider(child)
			end
		end
		world.ChildAdded:Connect(function(child)
			if child.Name ~= "Lobby" then
				consider(child)
			end
		end)
		world.ChildRemoved:Connect(function(child)
			if child == builtFor then
				clear()
			end
		end)
	end)
end

return Crowd
