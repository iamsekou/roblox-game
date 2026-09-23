-- Placeholder visuals for abilities (approved sheet, docs/ABILITIES.md; Phase 3 slice: Goku, Luffy).
-- Every client draws every cast from the server's AbilityFX event, so each tell is visible to all.
-- Built from tweened neon parts: flashes and rings for teleports, a charging orb and a fading beam for
-- the wave, a stretching arm for the grapple, fist blurs for the barrage. Character-specific poses come
-- later from the Animation Editor; these stay as the effect layer on top.
--
-- All parts are client-only, anchored, and never collide, cast shadows or take raycasts.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

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

local function handOf(character: Model?): BasePart?
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	return if hand and hand:IsA("BasePart") then hand else rootOf(character)
end

local function luffyGrapple(event: any)
	local character = characterOf(event.caster)
	local target = event.target
	if not character or typeof(target) ~= "Vector3" then
		return
	end
	local reach = tonumber(event.delay) or 0.3
	local arm = part(Enum.PartType.Cylinder, Vector3.new(0.1, 0.7, 0.7), CFrame.new(target), SKIN, 0)
	arm.Material = Enum.Material.SmoothPlastic
	local fist = part(Enum.PartType.Ball, Vector3.one * 1.3, CFrame.new(target), SKIN, 0)
	fist.Material = Enum.Material.SmoothPlastic
	local started = os.clock()
	local total = reach + 0.45 -- shoot out, then hold while the pull carries Luffy in
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - started
		local hand = handOf(character)
		if elapsed >= total or not hand or not hand.Parent then
			connection:Disconnect()
			arm:Destroy()
			fist:Destroy()
			return
		end
		local from = hand.Position
		local tip = if elapsed < reach then from:Lerp(target, elapsed / reach) else target
		local span = tip - from
		if span.Magnitude > 0.05 then
			arm.Size = Vector3.new(span.Magnitude, 0.7, 0.7)
			arm.CFrame = alongCFrame(from + span / 2, span.Unit)
		end
		fist.CFrame = CFrame.new(tip)
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

-- A small object travelling along a straight path (discs, tornadoes, waves).
local function travel(p: BasePart, origin: Vector3, direction: Vector3, length: number, speed: number, spin: number, lift: number)
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local along = (os.clock() - started) * speed
		if along >= length or not p.Parent then
			connection:Disconnect()
			if p.Parent then
				fadeOut(p, 0.2)
			end
			return
		end
		p.CFrame = CFrame.lookAt(origin + direction * along, origin + direction * (along + 1)) * CFrame.new(0, lift, 0) * CFrame.Angles(0, os.clock() * spin, 0)
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
	followShell(characterOf(event.caster), STEEL, tonumber(event.duration) or 2.3, 6.5)
end

handlers.zoro_windup = function(event)
	followShell(characterOf(event.caster), WIND, tonumber(event.duration) or 1, 5, Enum.Material.Neon, 0.85)
end

handlers.zoro_tornado = function(event)
	if typeof(event.origin) ~= "Vector3" or typeof(event.direction) ~= "Vector3" then
		return
	end
	-- A tall spinning funnel: a column with a wider band near the top.
	local funnel = part(Enum.PartType.Cylinder, Vector3.new(12, 6, 6), CFrame.new(event.origin), WIND, 0.55)
	funnel.Material = Enum.Material.ForceField
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
			return
		end
		local base = event.origin + event.direction * along
		funnel.CFrame = CFrame.new(base + Vector3.new(0, 3, 0)) * CFrame.Angles(0, os.clock() * 12, math.rad(90))
		funnel.Size = Vector3.new(12, 5 + math.sin(os.clock() * 10) * 1, 5 + math.sin(os.clock() * 10) * 1)
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
	if typeof(event.from) == "Vector3" and typeof(event.to) == "Vector3" then
		streak(event.from, event.to, Color3.fromRGB(30, 30, 34), 1.2, 0.25)
		burst(event.from, Color3.fromRGB(60, 60, 66))
	end
end

handlers.ichigo_wave_charge = function(event)
	followShell(characterOf(event.caster), GETSU_EDGE, tonumber(event.duration) or 1, 6, Enum.Material.Neon, 0.8)
end

handlers.ichigo_wave = function(event)
	if typeof(event.origin) ~= "Vector3" or typeof(event.direction) ~= "Vector3" then
		return
	end
	local length = tonumber(event.length) or 40
	local width = tonumber(event.width) or 14
	-- The crescent: a thin wide band sweeping forward.
	local crescent = part(Enum.PartType.Block, Vector3.new(width, 5, 0.6), CFrame.new(event.origin), GETSU_EDGE, 0.1)
	travel(crescent, event.origin + Vector3.new(0, 2.5, 0), event.direction, length, 60, 0, 0)
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
	followShell(characterOf(event.caster), LIGHTNING, tonumber(event.duration) or 0.3, 4.5, Enum.Material.Neon, 0.7)
end

handlers.sasuke_dash = function(event)
	if typeof(event.from) ~= "Vector3" or typeof(event.to) ~= "Vector3" then
		return
	end
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

local INFINITY = Color3.fromRGB(150, 210, 255)

handlers.gojo_blink = function(event)
	if typeof(event.from) == "Vector3" then
		burst(event.from, INFINITY)
	end
	if typeof(event.to) == "Vector3" then
		task.delay(tonumber(event.delay) or 0.3, burst, event.to, INFINITY)
	end
end

handlers.gojo_infinity_tell = function(event)
	chargeOrb(characterOf(event.caster), INFINITY, tonumber(event.duration) or 0.8, 1.6)
end

handlers.gojo_infinity = function(event)
	local radius = tonumber(event.radius) or 10
	followShell(characterOf(event.caster), INFINITY, tonumber(event.duration) or 4, radius * 2, Enum.Material.ForceField, 0.5)
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
