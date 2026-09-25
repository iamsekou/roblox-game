-- Placeholder visuals for abilities (approved sheet, docs/ABILITIES.md; Phase 3 slice: Goku, Luffy).
-- Sword fighters (Zorin, Ichiro, Sazuki) also get slash crescents, sparks, glints, blade glow and
-- crackle on the swords that Swords draws into their hands for each sword move.
-- Every client draws every cast from the server's AbilityFX event, so each tell is visible to all.
-- Built from tweened neon parts: flashes and rings for teleports, a charging orb and a fading beam for
-- the wave, a stretching arm for the grapple, fist blurs for the barrage. Character-specific poses come
-- later from the Animation Editor; these stay as the effect layer on top.
--
-- All parts are client-only, anchored, and never collide, cast shadows or take raycasts.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Swords = require(script.Parent:WaitForChild("Swords"))

local AbilityFX = {}

local KI = Color3.fromRGB(140, 205, 255) -- Goku's energy
local KI_CORE = Color3.fromRGB(235, 248, 255)
local SKIN = Color3.fromRGB(236, 188, 150) -- Luffy's stretching arm and fists
local BLUR = Color3.fromRGB(255, 214, 180)

local folder: Folder? = nil

local function fxFolder(): Folder
	if not folder or not folder.Parent then
		local f = Instance.new("Folder")
		f.Name = "NAU_AbilityFX"
		f.Parent = workspace
		folder = f
	end
	return folder :: Folder
end

local function part(shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, transparency: number): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Transparency = transparency
	p.Parent = fxFolder()
	return p
end

local function fadeOut(p: BasePart, seconds: number, extra: { [string]: any }?)
	local goal: { [string]: any } = { Transparency = 1 }
	for key, value in extra or {} do
		goal[key] = value
	end
	local tween = TweenService:Create(p, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	tween.Completed:Connect(function()
		p:Destroy()
	end)
	tween:Play()
end

-- Cylinders run along their X axis; this lays one along `direction`, centred on `center`.
local function alongCFrame(center: Vector3, direction: Vector3): CFrame
	return CFrame.lookAt(center, center + direction) * CFrame.Angles(0, math.rad(90), 0)
end

local function characterOf(userId: number?): Model?
	local player = userId and Players:GetPlayerByUserId(userId)
	return player and player.Character
end

local function rootOf(character: Model?): BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- A burst: a quick bright sphere and a flat ring rolling out along the ground.
local function burst(position: Vector3, color: Color3)
	local orb = part(Enum.PartType.Ball, Vector3.one, CFrame.new(position + Vector3.new(0, 1, 0)), KI_CORE, 0.1)
	fadeOut(orb, 0.35, { Size = Vector3.one * 7 })
	local ring = part(Enum.PartType.Cylinder, Vector3.new(0.2, 2, 2), CFrame.new(position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, 0.2)
	fadeOut(ring, 0.45, { Size = Vector3.new(0.2, 13, 13) })
end

-- Goku -------------------------------------------------------------------------------------------

local function gokuTransmission(event: any)
	if typeof(event.from) == "Vector3" then
		burst(event.from, KI)
	end
	if typeof(event.to) == "Vector3" then
		task.delay(tonumber(event.delay) or 0.3, burst, event.to, KI)
	end
end

local function gokuWaveCharge(event: any)
	local root = rootOf(characterOf(event.caster))
	if not root then
		return
	end
	local duration = tonumber(event.duration) or 1.2
	local orb = part(Enum.PartType.Ball, Vector3.one * 0.5, root.CFrame, KI, 0.15)
	local light = Instance.new("PointLight")
	light.Color = KI
	light.Range = 10
	light.Brightness = 2
	light.Parent = orb
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - started) / duration
		if t >= 1 or not root.Parent then
			connection:Disconnect()
			orb:Destroy()
			return
		end
		-- Cupped in front of the chest, growing as it charges, with a nervous flicker.
		local size = 0.5 + 2 * t + math.sin(os.clock() * 40) * 0.08
		orb.Size = Vector3.one * size
		orb.CFrame = root.CFrame * CFrame.new(0, 0.6, -2)
		light.Range = 6 + 10 * t
	end)
end

local function gokuWaveFire(event: any)
	local origin, direction, length = event.origin, event.direction, tonumber(event.length)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" or not length or length <= 0 then
		return
	end
	local center = origin + direction * (length / 2)
	local beam = part(Enum.PartType.Cylinder, Vector3.new(length, 3.4, 3.4), alongCFrame(center, direction), KI, 0.15)
	local core = part(Enum.PartType.Cylinder, Vector3.new(length, 1.3, 1.3), alongCFrame(center, direction), KI_CORE, 0)
	fadeOut(beam, 0.55, { Size = Vector3.new(length, 0.4, 0.4) })
	fadeOut(core, 0.4, { Size = Vector3.new(length, 0.2, 0.2) })
	burst(origin + direction * length, KI)
end

-- Luffy ------------------------------------------------------------------------------------------

-- Stretch Grapple (owner request 2026-09-24: "an arm stretching out to grab on to what it grapples").
-- The upper arm stays real (the cast pose points it at the target); from the elbow on, the real forearm
-- and hand are hidden and a rubber arm takes over:
--   shoot   over the server's tell, a copy of Luffo's own hand flies out fingers-first; the arm behind it
--           ripples like rubber and thins as it stretches (volume kept, roughly);
--   grab    the hand plants flat on the surface with a squash and a ring of dust, and holds on;
--   pull    the hand stays put while Luffo is pulled in (his own client moves him; everyone sees it
--           replicate), so the arm shortens and thickens back;
--   snap    on arrival (or a time limit) the hand lets go and the arm whips back into the elbow.
local ARM_SEGMENTS = 10
local ARM_WIDTH = 1.05 -- studs, at rest length (owner, 2026-09-24: "a little thicker"; was 0.85)
local ARM_MIN_WIDTH = 0.6 -- studs, fully stretched (was 0.4)
local ARM_REST = 2 -- studs: an unstretched forearm and hand
local HAND_SCALE = 1.6 -- the flying hand is drawn a bit bigger, cartoon style
local RIPPLE = 1.1 -- studs of sideways ripple while shooting out (decays)
local RIPPLE_WAVES = 1.5 -- ripples along the arm
local SNAP_SECONDS = 0.16
local ARRIVE_DISTANCE = 3.5 -- elbow this close to the grip: let go
local HIDDEN_PARTS = { "RightLowerArm", "RightHand", "Right Arm" } -- R15, and the R6 name

local function jointPosition(character: Model): Vector3?
	-- The elbow (R15), else the shoulder (R6: the whole arm is one part).
	local upper = character:FindFirstChild("RightUpperArm")
	local elbow = upper and upper:FindFirstChild("RightElbowRigAttachment")
	if elbow and elbow:IsA("Attachment") then
		return elbow.WorldPosition
	end
	local torso = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
	return if torso and torso:IsA("BasePart") then torso.CFrame:PointToWorldSpace(Vector3.new(1.5, 0.6, 0)) else nil
end

local function setArmHidden(character: Model, hidden: boolean)
	for _, name in HIDDEN_PARTS do
		local p = character:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			p.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

-- A copy of the fighter's own hand (its mesh and skin), or a fist-sized ball if the rig has none.
local function handCopy(character: Model, color: Color3): BasePart
	local real = character:FindFirstChild("RightHand")
	local copy: BasePart
	if real and real:IsA("BasePart") then
		copy = real:Clone()
		for _, child in copy:GetChildren() do
			if not child:IsA("SpecialMesh") and not child:IsA("SurfaceAppearance") then
				child:Destroy()
			end
		end
		copy.Size *= HAND_SCALE
		copy.Anchored = true
		copy.CanCollide = false
		copy.CanQuery = false
		copy.CanTouch = false
		copy.CastShadow = false
		copy.Massless = true
		copy.Transparency = 0
		copy.LocalTransparencyModifier = 0
		copy.Parent = fxFolder()
	else
		copy = part(Enum.PartType.Ball, Vector3.one * 1.3, CFrame.new(), color, 0)
		copy.Material = Enum.Material.SmoothPlastic
	end
	return copy
end

-- Fingers along `direction`: a rig's hand hangs down its -Y axis.
local function handCFrame(at: Vector3, direction: Vector3): CFrame
	return CFrame.lookAt(at, at + direction) * CFrame.Angles(math.rad(90), 0, 0)
end

local function grabDust(point: Vector3, normal: Vector3)
	local ring = part(Enum.PartType.Cylinder, Vector3.new(0.12, 1, 1), alongCFrame(point + normal * 0.1, normal), Color3.fromRGB(240, 232, 214), 0.25)
	ring.Material = Enum.Material.SmoothPlastic
	fadeOut(ring, 0.4, { Size = Vector3.new(0.12, 6, 6) })
	-- A few puffs kicked out across the surface.
	local across = normal:Cross(if math.abs(normal.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis).Unit
	for i = 1, 6 do
		local angle = (i / 6) * math.pi * 2
		local dir = (CFrame.fromAxisAngle(normal, angle) * across)
		local puff = part(Enum.PartType.Ball, Vector3.one * 0.5, CFrame.new(point + normal * 0.3), Color3.fromRGB(230, 220, 200), 0.3)
		puff.Material = Enum.Material.SmoothPlastic
		fadeOut(puff, 0.45, { Size = Vector3.one * 1.3, CFrame = CFrame.new(point + normal * 0.6 + dir * 2.4) })
	end
end

local function luffyGrapple(event: any)
	local character = characterOf(event.caster)
	local target = event.target
	if not character or typeof(target) ~= "Vector3" then
		return
	end
	local start = jointPosition(character)
	if not start then
		return
	end
	local normal = if typeof(event.normal) == "Vector3" and event.normal.Magnitude > 0.5 then event.normal.Unit else (start - target).Unit
	local reach = tonumber(event.delay) or 0.3
	local speed = tonumber(event.speed) or 120
	-- Shoot + the pull (distance / speed) + slack for a blocked path; then let go regardless.
	local limit = reach + (target - start).Magnitude / speed + 0.6

	local lower = character:FindFirstChild("RightLowerArm") or character:FindFirstChild("Right Arm")
	local skin = if lower and lower:IsA("BasePart") then lower.Color else SKIN
	setArmHidden(character, true)
	local hand = handCopy(character, skin)
	local grip = target + normal * 0.35 -- the palm sits just off the surface
	local segments, knuckles = {}, {}
	for i = 1, ARM_SEGMENTS do
		local seg = part(Enum.PartType.Cylinder, Vector3.new(0.1, ARM_WIDTH, ARM_WIDTH), CFrame.new(start), skin, 0)
		seg.Material = Enum.Material.SmoothPlastic
		segments[i] = seg
		local ball = part(Enum.PartType.Ball, Vector3.one * ARM_WIDTH, CFrame.new(start), skin, 0)
		ball.Material = Enum.Material.SmoothPlastic
		knuckles[i] = ball
	end

	local started = os.clock()
	local phase = "shoot"
	local snapFrom: Vector3? = nil
	local snapStarted = 0
	local connection: RBXScriptConnection
	local function finish()
		connection:Disconnect()
		for i = 1, ARM_SEGMENTS do
			segments[i]:Destroy()
			knuckles[i]:Destroy()
		end
		hand:Destroy()
		if character.Parent then
			setArmHidden(character, false)
		end
	end

	connection = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local elapsed = now - started
		local from = if character.Parent then jointPosition(character) else nil
		if not from then
			finish()
			return
		end
		-- Where the hand is, and how much the arm ripples.
		local tip, ripple
		if phase == "shoot" then
			local t = math.min(elapsed / reach, 1)
			local eased = 1 - (1 - t) ^ 2 -- fast out, slowing into the grab
			tip = from:Lerp(grip, eased)
			ripple = RIPPLE * (1 - t)
			if t >= 1 then
				phase = "hold"
				grabDust(target, normal)
				local size = hand.Size
				hand.Size = size * Vector3.new(1.25, 0.75, 1.25) -- the squash of a hard grab
				TweenService:Create(hand, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Size = size }):Play()
			end
		elseif phase == "hold" then
			tip = grip
			ripple = 0
			if (grip - from).Magnitude <= ARRIVE_DISTANCE or elapsed >= limit then
				phase = "snap"
				snapFrom = grip
				snapStarted = now
			end
		else
			local t = math.min((now - snapStarted) / SNAP_SECONDS, 1)
			if t >= 1 then
				finish()
				return
			end
			tip = (snapFrom :: Vector3):Lerp(from, t * t) -- accelerating back in
			ripple = RIPPLE * 0.6 * math.sin(t * math.pi) -- the whip
		end

		local span = tip - from
		local length = span.Magnitude
		local direction = if length > 0.05 then span / length else normal * -1
		-- Rubber: thinner the further it stretches.
		local width = math.clamp(ARM_WIDTH * math.sqrt(ARM_REST / math.max(length, ARM_REST)), ARM_MIN_WIDTH, ARM_WIDTH)
		local side = direction:Cross(Vector3.yAxis)
		side = if side.Magnitude > 0.1 then side.Unit else Vector3.xAxis
		local previous = from
		for i = 1, ARM_SEGMENTS do
			local along = i / ARM_SEGMENTS
			local wave = math.sin(along * math.pi * 2 * RIPPLE_WAVES - elapsed * 30) * math.sin(along * math.pi)
			local point = from + span * along + side * (wave * ripple)
			local piece = point - previous
			local pieceLength = piece.Magnitude
			local seg, ball = segments[i], knuckles[i]
			if pieceLength > 0.02 then
				seg.Size = Vector3.new(pieceLength, width, width)
				seg.CFrame = alongCFrame(previous + piece / 2, piece / pieceLength)
			end
			ball.Size = Vector3.one * width
			ball.CFrame = CFrame.new(point)
			previous = point
		end
		-- The hand: fingers leading while it flies, palm flat on the surface while it holds.
		local facing = if phase == "hold" then -normal else direction
		hand.CFrame = handCFrame(tip, facing)
	end)
end

local function luffyGatling(event: any)
	local character = characterOf(event.caster)
	local root = rootOf(character)
	if not root then
		return
	end
	local windup = tonumber(event.windup) or 1
	local duration = tonumber(event.duration) or 1.5
	-- Wind-up tell: the fists pull back with a hot glow at the shoulders.
	local glow = part(Enum.PartType.Ball, Vector3.one * 1.6, root.CFrame * CFrame.new(0, 1, 0.8), Color3.fromRGB(255, 120, 70), 0.35)
	fadeOut(glow, windup, { Size = Vector3.one * 3.2 })
	task.delay(windup, function()
		local stop = os.clock() + duration
		while os.clock() < stop and root.Parent do
			for _ = 1, 3 do
				-- A blur of fists anywhere in the front cone, chest height give or take.
				local angle = math.rad((math.random() - 0.5) * 80)
				local reach = 2 + math.random() * 9
				local offset = CFrame.Angles(0, angle, 0) * Vector3.new(0, 0, -reach)
				local position = root.CFrame:PointToWorldSpace(offset + Vector3.new(0, 0.5 + math.random() * 2, 0))
				local fist = part(Enum.PartType.Ball, Vector3.one * (0.9 + math.random() * 0.6), CFrame.new(position), BLUR, 0.25)
				fadeOut(fist, 0.14, { Size = Vector3.one * 0.3 })
			end
			task.wait(0.04)
		end
	end)
end

-- Shared building blocks for the other eight -----------------------------------------------------

-- A glowing shell that follows a character for `duration` (auras, stances, barriers).
local function followShell(character: Model?, color: Color3, duration: number, size: number, material: Enum.Material?, transparency: number?)
	local root = rootOf(character)
	if not root then
		return
	end
	local shell = part(Enum.PartType.Ball, Vector3.one * size, root.CFrame, color, transparency or 0.75)
	shell.Material = material or Enum.Material.ForceField
	local stop = os.clock() + duration
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if os.clock() >= stop or not root.Parent then
			connection:Disconnect()
			fadeOut(shell, 0.25)
			return
		end
		shell.CFrame = root.CFrame
	end)
end

-- An orb held in front of the chest that grows for `duration` (charges and wind-ups).
local function chargeOrb(character: Model?, color: Color3, duration: number, finalSize: number)
	local root = rootOf(character)
	if not root then
		return
	end
	local orb = part(Enum.PartType.Ball, Vector3.one * 0.4, root.CFrame, color, 0.15)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 8
	light.Brightness = 2
	light.Parent = orb
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - started) / duration
		if t >= 1 or not root.Parent then
			connection:Disconnect()
			orb:Destroy()
			return
		end
		orb.Size = Vector3.one * (0.4 + (finalSize - 0.4) * t + math.sin(os.clock() * 40) * 0.06)
		orb.CFrame = root.CFrame * CFrame.new(0, 0.6, -2)
	end)
end

-- A flat ring on the ground; `grow` = expand and fade, otherwise pulse in place for `duration`.
local function groundRing(position: Vector3, radius: number, color: Color3, duration: number, grow: boolean)
	local ring = part(Enum.PartType.Cylinder, Vector3.new(0.15, radius * 2, radius * 2), CFrame.new(position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, 0.45)
	if grow then
		fadeOut(ring, duration, { Size = Vector3.new(0.15, radius * 3, radius * 3) })
	else
		TweenService:Create(ring, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.8 }):Play()
		task.delay(duration, function()
			ring:Destroy()
		end)
	end
end

-- A streak between two points that thins and fades (dashes and lunges).
local function streak(from: Vector3, to: Vector3, color: Color3, thickness: number, seconds: number)
	local span = to - from
	if span.Magnitude < 0.5 then
		return
	end
	local beam = part(Enum.PartType.Cylinder, Vector3.new(span.Magnitude, thickness, thickness), alongCFrame(from + span / 2, span.Unit), color, 0.2)
	fadeOut(beam, seconds, { Size = Vector3.new(span.Magnitude, 0.1, 0.1) })
end

-- A marker hovering above a fighter's head for `duration`.
local function headMarker(userId: number?, color: Color3, duration: number)
	local character = characterOf(userId)
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local marker = part(Enum.PartType.Block, Vector3.new(1.1, 1.1, 0.2), head.CFrame, color, 0.1)
	local stop = os.clock() + duration
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if os.clock() >= stop or not head.Parent then
			connection:Disconnect()
			marker:Destroy()
			return
		end
		marker.CFrame = CFrame.new(head.Position + Vector3.new(0, 4.2, 0)) * CFrame.Angles(0, os.clock() * 3, math.rad(45))
	end)
end

-- Sword effects (owner-approved 2026-09-23): slash crescents, sparks, glints, blade glow, crackle ------

-- A crescent of neon segments: its middle sits at the model's pivot, the convex side faces the pivot's
-- -Z and the arc curves back toward +Z across the pivot's X axis (a circle of `radius` centred at +Z).
-- Segments taper toward the tips.
local function crescent(radius: number, spanDeg: number, segments: number, height: number, depth: number, color: Color3, transparency: number): Model
	local model = Instance.new("Model")
	model.Name = "Crescent"
	local pivot = part(Enum.PartType.Block, Vector3.one * 0.1, CFrame.identity, color, 1)
	pivot.Parent = model
	model.PrimaryPart = pivot
	local span = math.rad(spanDeg)
	local function at(theta: number): Vector3
		return Vector3.new(radius * math.sin(theta), 0, radius * (1 - math.cos(theta)))
	end
	for i = 1, segments do
		local a0 = -span / 2 + span * (i - 1) / segments
		local a1 = a0 + span / segments
		local p0, p1 = at(a0), at(a1)
		local middle = (p0 + p1) / 2
		local along = (a0 + a1) / (2 * (span / 2)) -- -1..1 from tip to tip
		local h = height * (1 - 0.85 * math.abs(along) ^ 1.5)
		local seg = part(Enum.PartType.Block, Vector3.new(depth, h, (p1 - p0).Magnitude + 0.05), CFrame.lookAt(middle, middle + (p1 - p0)), color, transparency)
		seg.Parent = model
	end
	model.Parent = fxFolder()
	return model
end

local function fadeModel(model: Model, seconds: number)
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p ~= model.PrimaryPart then
			TweenService:Create(p, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 }):Play()
		end
	end
	task.delay(seconds, function()
		model:Destroy()
	end)
end

-- A quick four-point glint that faces the camera.
local function glint(position: Vector3, color: Color3, size: number)
	local camera = workspace.CurrentCamera
	local facing = if camera then CFrame.lookAt(position, camera.CFrame.Position) else CFrame.new(position)
	local core = part(Enum.PartType.Ball, Vector3.one * size * 0.3, CFrame.new(position), color, 0)
	fadeOut(core, 0.35, { Size = Vector3.one * size * 0.05 })
	for _, roll in { 0, 90 } do
		local ray = part(Enum.PartType.Block, Vector3.new(size * 0.06, size, size * 0.06), facing * CFrame.Angles(0, 0, math.rad(roll + 45)), color, 0)
		fadeOut(ray, 0.35, { Size = Vector3.new(size * 0.02, size * 0.2, size * 0.02) })
	end
end

-- Sparks flying off a blocked hit: shards thrown back toward where the blow came from.
local function sparks(position: Vector3, toward: Vector3)
	local color = Color3.fromRGB(255, 214, 150)
	glint(position, Color3.fromRGB(255, 245, 225), 2.4)
	for _ = 1, 9 do
		local spread = CFrame.lookAt(Vector3.zero, toward) * CFrame.Angles(math.rad(math.random(-55, 55)), math.rad(math.random(-55, 55)), 0)
		local direction = spread.LookVector
		local shard = part(Enum.PartType.Block, Vector3.new(0.07, 0.07, 0.6 + math.random() * 0.5), CFrame.lookAt(position, position + direction), color, 0)
		fadeOut(shard, 0.22, { CFrame = CFrame.lookAt(position + direction * (2.5 + math.random() * 2), position + direction * 6), Size = Vector3.new(0.03, 0.03, 0.2) })
	end
end

-- A pulsing glow shell over every blade part of a held sword, for `seconds`.
local function bladeGlow(sword: Model?, color: Color3, seconds: number)
	if not sword then
		return
	end
	for _, blade in Swords.bladeParts(sword) do
		local shell = Instance.new("Part")
		shell.Name = "NAU_BladeGlow"
		shell.Shape = blade.Shape
		shell.Size = blade.Size + Vector3.new(0.1, 0.14, 0.1)
		shell.CFrame = blade.CFrame
		shell.Material = Enum.Material.Neon
		shell.Color = color
		shell.Transparency = 0.6
		shell.CanCollide = false
		shell.CanQuery = false
		shell.CanTouch = false
		shell.CastShadow = false
		shell.Massless = true
		local weld = Instance.new("Weld")
		weld.Part0 = blade
		weld.Part1 = shell
		weld.Parent = shell
		shell.Parent = fxFolder()
		TweenService:Create(shell, TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.25 }):Play()
		task.delay(seconds, function()
			shell:Destroy()
		end)
	end
	local grip = sword.PrimaryPart
	if grip then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 9
		light.Brightness = 2.5
		light.Parent = grip
		task.delay(seconds, function()
			light:Destroy()
		end)
	end
end

-- Lightning crawling along a held blade, redrawn every few frames, for `seconds`.
local function bladeCrackle(sword: Model?, color: Color3, seconds: number)
	if not sword then
		return
	end
	local stop = os.clock() + seconds
	local bolts: { BasePart } = {}
	task.spawn(function()
		while os.clock() < stop and sword.Parent do
			for _, b in bolts do
				b:Destroy()
			end
			table.clear(bolts)
			local base, tip = Swords.bladeLine(sword)
			if base and tip then
				local previous = base
				for i = 1, 5 do
					local point = base:Lerp(tip, i / 5) + if i < 5 then Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 0.7 else Vector3.zero
					local span = point - previous
					if span.Magnitude > 0.05 then
						table.insert(bolts, part(Enum.PartType.Block, Vector3.new(0.07, 0.07, span.Magnitude), CFrame.lookAt(previous + span / 2, point), color, 0))
					end
					previous = point
				end
			end
			task.wait(0.05)
		end
		for _, b in bolts do
			b:Destroy()
		end
	end)
end

-- Krillin ----------------------------------------------------------------------------------------

local FLARE = Color3.fromRGB(255, 250, 225)
local DISC = Color3.fromRGB(255, 226, 150)

local handlers: { [string]: (any) -> () } = {}

handlers.krillin_flare_tell = function(event)
	chargeOrb(characterOf(event.caster), FLARE, tonumber(event.duration) or 0.4, 1.4)
end

handlers.krillin_flare = function(event)
	if typeof(event.position) == "Vector3" then
		local flash = part(Enum.PartType.Ball, Vector3.one * 2, CFrame.new(event.position + Vector3.new(0, 1.5, 0)), FLARE, 0)
		fadeOut(flash, 0.5, { Size = Vector3.one * 26 })
	end
end

handlers.krillin_disc_tell = function(event)
	local root = rootOf(characterOf(event.caster))
	if root then
		local disc = part(Enum.PartType.Cylinder, Vector3.new(0.2, 3.5, 3.5), root.CFrame * CFrame.new(0, 3.5, 0) * CFrame.Angles(0, 0, math.rad(90)), DISC, 0.2)
		fadeOut(disc, tonumber(event.duration) or 0.8, { Size = Vector3.new(0.2, 4.5, 4.5) })
	end
end

handlers.krillin_disc = function(event)
	if typeof(event.origin) ~= "Vector3" or typeof(event.direction) ~= "Vector3" then
		return
	end
	local disc = part(Enum.PartType.Cylinder, Vector3.new(0.25, 4, 4), CFrame.new(event.origin), DISC, 0.1)
	disc.Name = "TrackingDisc_" .. tostring(event.caster)
	-- Lie the disc flat and spin it as it flies.
	local started = os.clock()
	local speed, length = tonumber(event.speed) or 30, tonumber(event.length) or 60
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local along = (os.clock() - started) * speed
		if along >= length or not disc.Parent then
			connection:Disconnect()
			if disc.Parent then
				fadeOut(disc, 0.2)
			end
			return
		end
		disc.CFrame = CFrame.new(event.origin + event.direction * along) * CFrame.Angles(0, os.clock() * 25, math.rad(90))
	end)
end

handlers.krillin_disc_stop = function(event)
	local disc = fxFolder():FindFirstChild("TrackingDisc_" .. tostring(event.caster))
	if disc then
		disc:Destroy()
	end
	if typeof(event.position) == "Vector3" then
		burst(event.position, DISC)
	end
end

handlers.tracked = function(event)
	headMarker(tonumber(event.target), DISC, tonumber(event.duration) or 5)
end

-- Vegeta -----------------------------------------------------------------------------------------

local SAIYAN = Color3.fromRGB(255, 212, 90)
local BLAST = Color3.fromRGB(150, 200, 255)

handlers.vegeta_pride = function(event)
	followShell(characterOf(event.caster), SAIYAN, tonumber(event.duration) or 4.3, 7)
end

handlers.vegeta_blast_warn = function(event)
	if typeof(event.position) == "Vector3" then
		groundRing(event.position, tonumber(event.radius) or 10, Color3.fromRGB(230, 90, 70), tonumber(event.duration) or 1, false)
	end
	chargeOrb(characterOf(event.caster), BLAST, tonumber(event.duration) or 1, 2)
end

handlers.vegeta_blast = function(event)
	if typeof(event.position) ~= "Vector3" then
		return
	end
	local radius = tonumber(event.radius) or 10
	local blast = part(Enum.PartType.Ball, Vector3.one * 2, CFrame.new(event.position), BLAST, 0.05)
	fadeOut(blast, 0.5, { Size = Vector3.one * radius * 2.2 })
	groundRing(event.position, radius, BLAST, 0.6, true)
end

-- Zoro -------------------------------------------------------------------------------------------

local STEEL = Color3.fromRGB(170, 200, 190)
local WIND = Color3.fromRGB(190, 225, 200)

handlers.zoro_guard = function(event)
	local character = characterOf(event.caster)
	followShell(character, STEEL, tonumber(event.duration) or 2.3, 6.5)
	-- A glint where the crossed blades meet as the stance locks in (after the 0.3 s tell).
	task.delay(tonumber(event.tell) or 0.3, function()
		local right, left = Swords.get(character, "right"), Swords.get(character, "left")
		if not right or not left then
			return
		end
		local rBase, rTip = Swords.bladeLine(right)
		local lBase, lTip = Swords.bladeLine(left)
		if rBase and rTip and lBase and lTip then
			glint((rBase:Lerp(rTip, 0.45) + lBase:Lerp(lTip, 0.45)) / 2, Color3.fromRGB(240, 250, 255), 3)
		end
	end)
end

-- Iron Guard turned a knockback or drag away: sparks off the blades, thrown back at the attacker.
handlers.guard_block = function(event)
	local character = characterOf(tonumber(event.target))
	local torso = character and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"))
	if not torso or not torso:IsA("BasePart") then
		return
	end
	local push = if typeof(event.direction) == "Vector3" and event.direction.Magnitude > 0.01 then event.direction.Unit else -torso.CFrame.LookVector
	sparks(torso.Position - push * 1.3 + Vector3.new(0, 0.4, 0), -push)
end

handlers.zoro_windup = function(event)
	followShell(characterOf(event.caster), WIND, tonumber(event.duration) or 1, 5, Enum.Material.Neon, 0.85)
end

handlers.zoro_tornado = function(event)
	if typeof(event.origin) ~= "Vector3" or typeof(event.direction) ~= "Vector3" then
		return
	end
	-- A tall spinning funnel: a column with a wider band near the top, with sword slashes spiralling
	-- round inside it as it travels.
	local funnel = part(Enum.PartType.Cylinder, Vector3.new(12, 6, 6), CFrame.new(event.origin), WIND, 0.55)
	funnel.Material = Enum.Material.ForceField
	local slashes: { { model: Model, height: number, phase: number, tilt: number, radius: number } } = {}
	for i = 1, 4 do
		local radius = 2.6 + i * 0.25
		table.insert(slashes, {
			model = crescent(radius, 120, 7, 0.4, 0.12, Color3.fromRGB(235, 250, 240), 0.15),
			height = -1.5 + i * 1.8,
			phase = i * math.pi / 2,
			tilt = math.rad(if i % 2 == 0 then 18 else -18),
			radius = radius,
		})
	end
	local speed, length = tonumber(event.speed) or 20, tonumber(event.length) or 40
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local along = (os.clock() - started) * speed
		if along >= length or not funnel.Parent then
			connection:Disconnect()
			if funnel.Parent then
				fadeOut(funnel, 0.3)
			end
			for _, slash in slashes do
				fadeModel(slash.model, 0.3)
			end
			return
		end
		local base = event.origin + event.direction * along
		funnel.CFrame = CFrame.new(base + Vector3.new(0, 3, 0)) * CFrame.Angles(0, os.clock() * 12, math.rad(90))
		funnel.Size = Vector3.new(12, 5 + math.sin(os.clock() * 10) * 1, 5 + math.sin(os.clock() * 10) * 1)
		for _, slash in slashes do
			-- The crescent's circle is centred on the funnel's axis, so the arc hugs it as it spins.
			local angle = os.clock() * 16 + slash.phase
			slash.model:PivotTo(CFrame.new(base + Vector3.new(0, 3 + slash.height, 0)) * CFrame.Angles(0, angle, 0) * CFrame.Angles(slash.tilt, 0, 0) * CFrame.new(0, 0, -slash.radius))
		end
	end)
end

-- L ----------------------------------------------------------------------------------------------

local LENS = Color3.fromRGB(40, 40, 46)
local cameras: { [string]: Model } = {}

handlers.l_camera = function(event)
	if typeof(event.position) ~= "Vector3" then
		return
	end
	local key = tostring(event.caster)
	if cameras[key] then
		cameras[key]:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "SurveillanceCamera"
	local feet = event.position - Vector3.new(0, 2.5, 0)
	local pole = part(Enum.PartType.Block, Vector3.new(0.2, 1.6, 0.2), CFrame.new(feet + Vector3.new(0, 0.8, 0)), LENS, 0)
	pole.Material = Enum.Material.Metal
	pole.Parent = model
	local body = part(Enum.PartType.Block, Vector3.new(0.6, 0.45, 0.9), CFrame.new(feet + Vector3.new(0, 1.8, 0)), Color3.fromRGB(220, 220, 214), 0)
	body.Material = Enum.Material.SmoothPlastic
	body.Parent = model
	local light = part(Enum.PartType.Ball, Vector3.one * 0.2, CFrame.new(feet + Vector3.new(0, 2.1, -0.3)), Color3.fromRGB(255, 60, 60), 0)
	light.Parent = model
	TweenService:Create(light, TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.9 }):Play()
	model.Parent = fxFolder()
	cameras[key] = model
	-- Slow sweep, like a security camera.
	local stop = os.clock() + (tonumber(event.duration) or 20)
	task.spawn(function()
		while model.Parent and os.clock() < stop do
			local angle = math.sin(os.clock() * 0.8) * math.rad(60)
			body.CFrame = CFrame.new(feet + Vector3.new(0, 1.8, 0)) * CFrame.Angles(0, angle, 0)
			light.CFrame = body.CFrame * CFrame.new(0, 0.3, -0.3)
			task.wait()
		end
		if cameras[key] == model then
			cameras[key] = nil
		end
		model:Destroy()
	end)
end

handlers.l_camera_end = function(event)
	local key = tostring(event.caster)
	if cameras[key] then
		cameras[key]:Destroy()
		cameras[key] = nil
	end
end

handlers.l_deduction_tell = function(event)
	followShell(characterOf(event.caster), Color3.fromRGB(230, 230, 236), tonumber(event.duration) or 0.8, 5, Enum.Material.Neon, 0.88)
end

-- Naruto -----------------------------------------------------------------------------------------

local SMOKE = Color3.fromRGB(235, 235, 235)
local CHAKRA = Color3.fromRGB(110, 170, 255)

local function puff(position: Vector3)
	for i = 1, 5 do
		local offset = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5) * 3
		local cloud = part(Enum.PartType.Ball, Vector3.one * 2.5, CFrame.new(position + offset), SMOKE, 0.3)
		cloud.Material = Enum.Material.SmoothPlastic
		fadeOut(cloud, 0.45 + i * 0.05, { Size = Vector3.one * 5.5 })
	end
end

handlers.clone_spawn = function(event)
	if typeof(event.position) == "Vector3" then
		puff(event.position)
	end
end

handlers.clone_pop = function(event)
	if typeof(event.position) == "Vector3" then
		puff(event.position)
	end
end

handlers.naruto_sphere_charge = function(event)
	chargeOrb(characterOf(event.caster), CHAKRA, tonumber(event.duration) or 0.6, 2.2)
end

handlers.naruto_sphere_lunge = function(event)
	if typeof(event.from) == "Vector3" and typeof(event.to) == "Vector3" then
		streak(event.from, event.to, CHAKRA, 2.4, 0.4)
	end
end

handlers.naruto_sphere_hit = function(event)
	local root = rootOf(characterOf(tonumber(event.target)))
	if root then
		burst(root.Position, CHAKRA)
	end
end

-- Ichigo -----------------------------------------------------------------------------------------

local GETSU = Color3.fromRGB(60, 30, 40) -- a dark, bruised red-black
local GETSU_EDGE = Color3.fromRGB(220, 60, 70)

handlers.ichigo_flash = function(event)
	if typeof(event.from) ~= "Vector3" or typeof(event.to) ~= "Vector3" then
		return
	end
	streak(event.from, event.to, Color3.fromRGB(30, 30, 34), 1.2, 0.25)
	burst(event.from, Color3.fromRGB(60, 60, 66))
	-- On arrival, the cut he made on the way through: a wide horizontal slash arc that flashes and fades.
	local span = event.to - event.from
	local flat = Vector3.new(span.X, 0, span.Z)
	if flat.Magnitude < 0.5 then
		return
	end
	task.delay(span.Magnitude / (tonumber(event.speed) or 160), function()
		local center = event.to + Vector3.new(0, 0.6, 0) - flat.Unit * 1.5
		local frame = CFrame.lookAt(center, center + flat.Unit) * CFrame.Angles(0, 0, math.rad(-12))
		local outer = crescent(3.8, 150, 11, 0.9, 0.15, Color3.fromRGB(245, 245, 250), 0.05)
		outer:PivotTo(frame)
		local inner = crescent(3.5, 140, 11, 0.55, 0.16, Color3.fromRGB(25, 25, 30), 0.1)
		inner:PivotTo(frame * CFrame.new(0, 0, 0.3))
		fadeModel(outer, 0.35)
		fadeModel(inner, 0.3)
	end)
end

handlers.ichigo_wave_charge = function(event)
	local character = characterOf(event.caster)
	local duration = tonumber(event.duration) or 1
	followShell(character, GETSU_EDGE, duration, 6, Enum.Material.Neon, 0.8)
	bladeGlow(Swords.get(character, "right"), GETSU_EDGE, duration + 0.15)
end

handlers.ichigo_wave = function(event)
	if typeof(event.origin) ~= "Vector3" or typeof(event.direction) ~= "Vector3" then
		return
	end
	local length = tonumber(event.length) or 40
	local width = tonumber(event.width) or 14
	-- The wave: a red-edged crescent with a dark core, tilted along the diagonal of the slash, flying
	-- forward convex side first.
	local origin = event.origin + Vector3.new(0, 2.5, 0)
	local direction = Vector3.new(event.direction.X, 0, event.direction.Z)
	direction = if direction.Magnitude > 0.01 then direction.Unit else Vector3.new(0, 0, -1)
	local tilt = CFrame.Angles(0, 0, math.rad(30))
	local edge = crescent(width / 2, 115, 21, 4.2, 0.5, GETSU_EDGE, 0.05)
	local core = crescent(width / 2 - 0.3, 105, 21, 2.8, 0.55, GETSU, 0)
	local started = os.clock()
	local speed = 60
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local along = (os.clock() - started) * speed
		if along >= length or not edge.Parent then
			connection:Disconnect()
			fadeModel(edge, 0.2)
			fadeModel(core, 0.2)
			return
		end
		local frame = CFrame.lookAt(origin + direction * along, origin + direction * (along + 1)) * tilt
		edge:PivotTo(frame)
		core:PivotTo(frame * CFrame.new(0, 0, 0.45))
	end)
	-- The trail it leaves: a dark strip on the ground for the trail's duration.
	local center = event.origin + event.direction * (length / 2) + Vector3.new(0, 0.1, 0)
	local strip = part(Enum.PartType.Block, Vector3.new(width, 0.12, length), CFrame.lookAt(center, center + event.direction), GETSU, 0.35)
	task.delay(tonumber(event.trail) or 3, function()
		fadeOut(strip, 0.4)
	end)
end

-- Sasuke -----------------------------------------------------------------------------------------

local LIGHTNING = Color3.fromRGB(170, 190, 255)
local SHARINGAN = Color3.fromRGB(210, 30, 40)

handlers.sasuke_dash_tell = function(event)
	local character = characterOf(event.caster)
	local duration = tonumber(event.duration) or 0.3
	followShell(character, LIGHTNING, duration, 4.5, Enum.Material.Neon, 0.7)
	bladeCrackle(Swords.get(character, "right"), LIGHTNING, duration)
end

handlers.sasuke_dash = function(event)
	if typeof(event.from) ~= "Vector3" or typeof(event.to) ~= "Vector3" then
		return
	end
	-- The blade keeps crackling through the dash and a moment after.
	bladeCrackle(Swords.get(characterOf(event.caster), "right"), LIGHTNING, (event.to - event.from).Magnitude / (tonumber(event.speed) or 170) + 0.25)
	-- A jagged crackle: a few short offset segments along the dash.
	local segments = 6
	local previous = event.from
	for i = 1, segments do
		local t = i / segments
		local point = event.from:Lerp(event.to, t) + if i < segments then Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2.2 else Vector3.zero
		streak(previous, point, LIGHTNING, 0.5, 0.35)
		previous = point
	end
end

handlers.sasuke_eye_tell = function(event)
	headMarker(event.caster, SHARINGAN, tonumber(event.duration) or 0.8)
end

handlers.sasuke_mark = function(event)
	headMarker(tonumber(event.target), SHARINGAN, tonumber(event.duration) or 6)
end

-- Gojo -------------------------------------------------------------------------------------------

local BOUNDLESS = Color3.fromRGB(150, 210, 255)

handlers.gojo_blink = function(event)
	if typeof(event.from) == "Vector3" then
		burst(event.from, BOUNDLESS)
	end
	if typeof(event.to) == "Vector3" then
		task.delay(tonumber(event.delay) or 0.3, burst, event.to, BOUNDLESS)
	end
end

handlers.gojo_boundless_tell = function(event)
	chargeOrb(characterOf(event.caster), BOUNDLESS, tonumber(event.duration) or 0.8, 1.6)
end

handlers.gojo_boundless = function(event)
	local radius = tonumber(event.radius) or 10
	followShell(characterOf(event.caster), BOUNDLESS, tonumber(event.duration) or 4, radius * 2, Enum.Material.ForceField, 0.5)
end

-- Clashes (owner-approved 2026-09-23) -------------------------------------------------------------
-- Two fighters locked in the same attack. Everyone sees the exchange between them: parry sparks for
-- swords, a beam struggle for the energy attacks, grinding spheres, fists meeting fists. Everything
-- follows the two fighters live and stops the moment the clash ends (or either one is gone).

local CLASH_WHITE = Color3.fromRGB(245, 248, 255)
local SWORD_CLASHES = { ["Zoro.ultimate"] = true, ["Ichigo.mild"] = true, ["Ichigo.ultimate"] = true, ["Sasuke.mild"] = true }
local BEAM_CLASHES = { ["Goku.ultimate"] = KI, ["Vegeta.ultimate"] = BLAST }

-- A fighter's chest, from a user id (what the server sends) or a character model (solo visual tests
-- against a dummy, since a real clash needs two players).
local function chestOf(who: any): Vector3?
	local character = if typeof(who) == "Instance" and who:IsA("Model") then who else characterOf(tonumber(who))
	local root = rootOf(character)
	return if root then root.Position + Vector3.new(0, 0.8, 0) else nil
end

local function randomUnit(): Vector3
	local v = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
	return if v.Magnitude > 0.01 then v.Unit else Vector3.yAxis
end

-- A cylinder stretched between two points.
local function span(p: BasePart, from: Vector3, to: Vector3, thickness: number)
	local d = to - from
	if d.Magnitude < 0.05 then
		return
	end
	p.Size = Vector3.new(d.Magnitude, thickness, thickness)
	p.CFrame = alongCFrame(from + d / 2, d.Unit)
end

-- Runs `step(a, b, now)` every frame while the clash lasts and both fighters exist; then `finish()`.
local function whileClashing(event: any, seconds: number, step: (Vector3, Vector3, number) -> (), finish: () -> ())
	local stop = os.clock() + seconds
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local a, b = chestOf(event.a), chestOf(event.b)
		local now = os.clock()
		if now >= stop or not a or not b then
			connection:Disconnect()
			finish()
			return
		end
		step(a, b, now)
	end)
end

local function swordClash(event: any, seconds: number)
	local nextBlow, nextRing = 0, 0
	whileClashing(event, seconds, function(a, b, now)
		if now >= nextBlow then
			nextBlow = now + 0.2 -- one blow or parry every 0.2 s, matching the exchange pose
			local meet = (a + b) / 2 + Vector3.new((math.random() - 0.5) * 1.2, 0.3 + math.random() * 1.5, (math.random() - 0.5) * 1.2)
			local toward = if math.random() < 0.5 then a - b else b - a
			sparks(meet, if toward.Magnitude > 0.01 then toward.Unit else Vector3.yAxis)
		end
		if now >= nextRing then
			nextRing = now + 0.6
			groundRing((a + b) / 2 - Vector3.new(0, 3.8, 0), 3, CLASH_WHITE, 0.5, true)
		end
	end, function() end)
end

-- Beam struggle: each fighter's beam pushes on a collision point that sways between them.
local function beamClash(event: any, seconds: number, color: Color3)
	local beams = {
		part(Enum.PartType.Cylinder, Vector3.one, CFrame.new(), color, 0.15),
		part(Enum.PartType.Cylinder, Vector3.one, CFrame.new(), color, 0.15),
	}
	local cores = {
		part(Enum.PartType.Cylinder, Vector3.one, CFrame.new(), KI_CORE, 0),
		part(Enum.PartType.Cylinder, Vector3.one, CFrame.new(), KI_CORE, 0),
	}
	local orb = part(Enum.PartType.Ball, Vector3.one * 1.7, CFrame.new(), KI_CORE, 0.05)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 12
	light.Brightness = 3
	light.Parent = orb
	local nextSpark = 0
	whileClashing(event, seconds, function(a, b, now)
		local d = b - a
		if d.Magnitude < 1 then
			return
		end
		local dir = d.Unit
		-- Sized for the 7-stud clash gap: the beams must stay visible either side of the collision.
		local handA, handB = a + dir * 1.4, b - dir * 1.4
		local sway = math.sin(now * 3.1) * 0.5 + math.sin(now * 7.3) * 0.15
		local meet = (handA + handB) / 2 + dir * sway
		local pulse = math.sin(now * 30) * 0.15
		span(beams[1], handA, meet, 1.3 + pulse)
		span(beams[2], meet, handB, 1.3 - pulse)
		span(cores[1], handA, meet, 0.45)
		span(cores[2], meet, handB, 0.45)
		orb.Size = Vector3.one * (1.7 + math.sin(now * 25) * 0.3)
		orb.CFrame = CFrame.new(meet)
		if now >= nextSpark then
			nextSpark = now + 0.15
			sparks(meet, randomUnit())
		end
	end, function()
		for _, p in { beams[1], beams[2], cores[1], cores[2] } do
			fadeOut(p, 0.2)
		end
		fadeOut(orb, 0.3, { Size = Vector3.one * 5 })
	end)
end

-- Spiral spheres grinding against each other, a ring of force spinning round the contact.
local function sphereClash(event: any, seconds: number)
	local left = part(Enum.PartType.Ball, Vector3.one * 2.2, CFrame.new(), CHAKRA, 0.1)
	local right = part(Enum.PartType.Ball, Vector3.one * 2.2, CFrame.new(), CHAKRA, 0.1)
	local ring = part(Enum.PartType.Cylinder, Vector3.new(0.15, 4.5, 4.5), CFrame.new(), Color3.fromRGB(200, 225, 255), 0.35)
	local nextSpark = 0
	whileClashing(event, seconds, function(a, b, now)
		local d = b - a
		if d.Magnitude < 1 then
			return
		end
		local dir = d.Unit
		local meet = (a + b) / 2 + dir * math.sin(now * 4) * 0.4
		local size = 2.2 + math.sin(now * 28) * 0.2
		left.Size, right.Size = Vector3.one * size, Vector3.one * size
		left.CFrame = CFrame.new(meet - dir * size * 0.45)
		right.CFrame = CFrame.new(meet + dir * size * 0.45)
		ring.CFrame = alongCFrame(meet, dir) * CFrame.Angles(now * 20, 0, 0)
		if now >= nextSpark then
			nextSpark = now + 0.12
			sparks(meet, randomUnit())
		end
	end, function()
		fadeOut(left, 0.25, { Size = Vector3.one * 5 })
		fadeOut(right, 0.25, { Size = Vector3.one * 5 })
		fadeOut(ring, 0.25, { Size = Vector3.new(0.15, 9, 9) })
	end)
end

-- Fists meeting fists: a blur of impacts filling the gap between the two.
local function fistClash(event: any, seconds: number)
	local nextFist, nextImpact = 0, 0
	whileClashing(event, seconds, function(a, b, now)
		if now >= nextFist then
			nextFist = now + 0.04
			for _ = 1, 2 do
				local at = a:Lerp(b, 0.3 + math.random() * 0.4) + Vector3.new((math.random() - 0.5) * 2, (math.random() - 0.5) * 1.6, (math.random() - 0.5) * 2)
				local fist = part(Enum.PartType.Ball, Vector3.one * (0.9 + math.random() * 0.6), CFrame.new(at), BLUR, 0.25)
				fadeOut(fist, 0.14, { Size = Vector3.one * 0.3 })
			end
		end
		if now >= nextImpact then
			nextImpact = now + 0.25
			glint((a + b) / 2 + Vector3.new(0, math.random() - 0.3, 0), Color3.fromRGB(255, 236, 205), 2.2)
		end
	end, function() end)
end

handlers.clash = function(event)
	if typeof(event.midpoint) ~= "Vector3" then
		return
	end
	local key = tostring(event.character) .. "." .. tostring(event.slot)
	local seconds = math.clamp(tonumber(event.duration) or 2.5, 0, 10)
	-- The moment of impact: a white flash where they meet.
	glint(event.midpoint + Vector3.new(0, 1, 0), CLASH_WHITE, 4.5)
	burst(event.midpoint, CLASH_WHITE)
	if SWORD_CLASHES[key] then
		swordClash(event, seconds)
	elseif BEAM_CLASHES[key] then
		beamClash(event, seconds, BEAM_CLASHES[key])
	elseif key == "Naruto.ultimate" then
		sphereClash(event, seconds)
	elseif key == "Luffy.ultimate" or key == "Melee.m1" then
		fistClash(event, seconds)
	end
end

-- M1 (owner request 2026-09-25) ------------------------------------------------------------------
-- A punch landing: a quick white pop where the fist met the body. The launching finisher gets a bigger
-- flash, a burst and a ring on the ground. Two punches landing together (a trade) spark between them.
local M1_POP = Color3.fromRGB(255, 244, 225)

handlers.melee_hit = function(event)
	if typeof(event.position) ~= "Vector3" then
		return
	end
	if event.finisher then
		glint(event.position, M1_POP, 3.6)
		burst(event.position, M1_POP)
		groundRing(event.position - Vector3.new(0, 3, 0), 3.5, M1_POP, 0.4, true)
	else
		glint(event.position, M1_POP, 1.8)
		local pop = part(Enum.PartType.Ball, Vector3.one * 0.8, CFrame.new(event.position), M1_POP, 0.3)
		fadeOut(pop, 0.12, { Size = Vector3.one * 2.4 })
	end
	if event.traded and typeof(event.direction) == "Vector3" then
		sparks(event.position, event.direction)
	end
end

-- The clash breaks: a shockwave throws the two apart.
handlers.clash_end = function(event)
	if typeof(event.midpoint) ~= "Vector3" then
		return
	end
	local flash = part(Enum.PartType.Ball, Vector3.one * 2, CFrame.new(event.midpoint + Vector3.new(0, 0.8, 0)), CLASH_WHITE, 0.05)
	fadeOut(flash, 0.45, { Size = Vector3.one * 14 })
	groundRing(event.midpoint - Vector3.new(0, 3, 0), 6, CLASH_WHITE, 0.6, true)
	glint(event.midpoint + Vector3.new(0, 1, 0), CLASH_WHITE, 5)
end

local HANDLERS: { [string]: (any) -> () } = {
	goku_transmission = gokuTransmission,
	goku_wave_charge = gokuWaveCharge,
	goku_wave_fire = gokuWaveFire,
	luffy_grapple = luffyGrapple,
	luffy_gatling = luffyGatling,
}
for kind, handler in handlers do
	HANDLERS[kind] = handler
end

function AbilityFX.play(event: any)
	if type(event) ~= "table" or type(event.kind) ~= "string" then
		return
	end
	local handler = HANDLERS[event.kind]
	if handler then
		task.spawn(handler, event)
	end
end

return AbilityFX
