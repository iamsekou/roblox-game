-- Anime sprint package: makes running feel like an action-anime chase (owner request).
--   * Speed lines: white streaks at the screen edges pointing at the centre, re-drawn every few
--     frames like hand-drawn anime frames, plus a light edge vignette. The centre stays clear, so
--     plates are just as readable while running.
--   * Camera: leans into turns and bobs with the stride (on top of RunFOV's widening).
--   * Ninja-run pose on every running R15 fighter: upper body leans forward, arms sweep back.
--   * Wind trails off the hands and dust kicked up at the feet.
-- Everything is client-side visuals, scaled by how fast each fighter is actually running.
-- The camera stays Custom. The pose is layered onto each joint's animation Transform right after the
-- run cycle is applied (Stepped). Touched joints are reset just before the animator runs (PreAnimation),
-- so the offset can never accumulate. Works with classic Motor6D joints and the newer
-- AnimationConstraint joints this place's R15 avatars use. (Measured in play: rotating the joint
-- attachments moves the waist but not the arms on these rigs, so Transform is the one lever that
-- works on both.)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SprintFX = {}

export type Config = {
	minSpeed: number,
	fullSpeed: number,
	leanDegrees: number,
	armsBackDegrees: number,
	rollDegrees: number,
	bob: number,
}

-- Speed lines toned down (owner, 2026-09-23: "too much is happening"): was 36 lines, 2-4 px wide,
-- 70-240 px long, up to 75% opaque, redrawn every 0.05 s.
local LINE_COUNT = 8
local LINE_REDRAW_SECONDS = 0.09
local LINE_WIDTH = { 1, 2 } -- px
local LINE_LENGTH = { 50, 130 } -- px
local LINE_OPACITY = { 0.15, 0.35 } -- at full speed
local LINE_RADIUS = { 0.44, 0.62 } -- kept out at the screen edges
local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local localPlayer = Players.LocalPlayer
local rng = Random.new()

type Joint = { instance: any, dirty: boolean } -- a Motor6D or AnimationConstraint (both have Transform)

type Rig = {
	factor: number,
	waist: Joint?,
	neck: Joint?,
	rightShoulder: Joint?,
	leftShoulder: Joint?,
	trails: { Trail },
	dust: ParticleEmitter?,
}

local rigs: { [Model]: Rig } = {}
local lines: { Frame } = {}
local overlay: ScreenGui? = nil
local vignette: { Frame } = {}
local localFactor = 0
-- Player settings (Phase 4): each part of the package can be switched off.
local options = { speedLines = true, cameraSway = true }
local roll = 0
local bobClock = 0
local lastRedraw = 0

local function speedFactor(root: BasePart, humanoid: Humanoid, config: Config): number
	if humanoid.Health <= 0 or humanoid.FloorMaterial == Enum.Material.Air then
		return -1 -- airborne or dead: keep the previous value
	end
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	return math.clamp((speed - config.minSpeed) / math.max(config.fullSpeed - config.minSpeed, 1), 0, 1)
end

local function approach(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

-- Screen overlay -------------------------------------------------------------------------------

local function buildOverlay()
	local gui = Instance.new("ScreenGui")
	gui.Name = "NAU_SprintFX"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.DisplayOrder = 1 -- under the HUD
	gui.Enabled = false
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	for i = 1, LINE_COUNT do
		local line = Instance.new("Frame")
		line.Name = "SpeedLine" .. i
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.BorderSizePixel = 0
		line.BackgroundColor3 = Color3.new(1, 1, 1)
		line.BackgroundTransparency = 1
		line.Parent = gui
		lines[i] = line
	end
	-- Edge vignette: four black bands fading toward the centre.
	local bands = {
		{ UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.22), 90 },
		{ UDim2.fromScale(0, 0.78), UDim2.fromScale(1, 0.22), -90 },
		{ UDim2.fromScale(0, 0), UDim2.fromScale(0.18, 1), 0 },
		{ UDim2.fromScale(0.82, 0), UDim2.fromScale(0.18, 1), 180 },
	}
	for i, spec in bands do
		local band = Instance.new("Frame")
		band.Name = "Vignette" .. i
		band.Position = spec[1]
		band.Size = spec[2]
		band.BorderSizePixel = 0
		band.BackgroundColor3 = Color3.new(0, 0, 0)
		band.BackgroundTransparency = 1
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = spec[3]
		gradient.Transparency = NumberSequence.new(0, 1)
		gradient.Parent = band
		band.Parent = gui
		vignette[i] = band
	end
	overlay = gui
end

-- A fresh random streak: somewhere around the screen edge, pointing at the centre.
local function redrawLine(line: Frame, strength: number)
	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = rng:NextNumber(LINE_RADIUS[1], LINE_RADIUS[2])
	line.Position = UDim2.fromScale(0.5 + math.cos(angle) * radius, 0.5 + math.sin(angle) * radius * 1.15)
	line.Size = UDim2.fromOffset(rng:NextInteger(LINE_WIDTH[1], LINE_WIDTH[2]), rng:NextInteger(LINE_LENGTH[1], LINE_LENGTH[2]))
	line.Rotation = math.deg(angle) + 90
	line.BackgroundTransparency = 1 - strength * rng:NextNumber(LINE_OPACITY[1], LINE_OPACITY[2])
end

local function updateOverlay(now: number)
	local gui = overlay
	if not gui then
		return
	end
	local active = options.speedLines and localFactor > 0.05
	gui.Enabled = active
	if not active then
		return
	end
	if now - lastRedraw >= LINE_REDRAW_SECONDS then
		lastRedraw = now
		for _, line in lines do
			redrawLine(line, localFactor)
		end
	end
	for _, band in vignette do
		band.BackgroundTransparency = 1 - 0.35 * localFactor
	end
end

-- Per-character effects ---------------------------------------------------------------------------

local function makeTrail(hand: BasePart): Trail
	local top = Instance.new("Attachment")
	top.Name = "NAU_TrailTop"
	top.Position = Vector3.new(0, 0.35, 0)
	top.Parent = hand
	local bottom = Instance.new("Attachment")
	bottom.Name = "NAU_TrailBottom"
	bottom.Position = Vector3.new(0, -0.35, 0)
	bottom.Parent = hand
	local trail = Instance.new("Trail")
	trail.Name = "NAU_WindTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.18
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.LightEmission = 0.6
	trail.Color = ColorSequence.new(Color3.fromRGB(235, 245, 255))
	trail.Transparency = NumberSequence.new(0.35, 1)
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Enabled = false
	trail.Parent = hand
	return trail
end

local function makeDust(root: BasePart): ParticleEmitter
	local feet = Instance.new("Attachment")
	feet.Name = "NAU_DustAttachment"
	feet.Position = Vector3.new(0, -2.8, 0.6)
	feet.Parent = root
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "NAU_Dust"
	dust.Texture = DUST_TEXTURE
	dust.Color = ColorSequence.new(Color3.fromRGB(214, 202, 180))
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 2.4) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.35, 0.6)
	dust.Speed = NumberRange.new(2, 5)
	dust.SpreadAngle = Vector2.new(35, 35)
	dust.Acceleration = Vector3.new(0, 3, 0)
	dust.Drag = 3
	dust.Rate = 0
	dust.EmissionDirection = Enum.NormalId.Back
	dust.Parent = feet
	return dust
end

local function findJoint(character: Model, partName: string, jointName: string): Joint?
	local part = character:FindFirstChild(partName)
	local joint = part and part:FindFirstChild(jointName)
	if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
		return { instance = joint, dirty = false }
	end
	return nil
end

local function rigFor(character: Model): Rig?
	local existing = rigs[character]
	if existing then
		return existing
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local rig: Rig = {
		factor = 0,
		-- R15 joints; on an R6 avatar these stay nil and only trails and dust apply.
		waist = findJoint(character, "UpperTorso", "Waist"),
		neck = findJoint(character, "Head", "Neck"),
		rightShoulder = findJoint(character, "RightUpperArm", "RightShoulder"),
		leftShoulder = findJoint(character, "LeftUpperArm", "LeftShoulder"),
		trails = {},
		dust = makeDust(root),
	}
	for _, handName in { "RightHand", "LeftHand", "Right Arm", "Left Arm" } do
		local hand = character:FindFirstChild(handName)
		if hand and hand:IsA("BasePart") then
			table.insert(rig.trails, makeTrail(hand))
		end
	end
	rigs[character] = rig
	return rig
end

local function updateCharacters(dt: number, config: Config)
	for character in rigs do
		if not character.Parent then
			rigs[character] = nil
		end
	end
	-- Every player's fighter, plus Studio's stress-test bots (workspace.NAU_StressBots, Studio only), so the
	-- stress test costs the client what real fighters would.
	local fighters: { { character: Model?, player: Player? } } = {}
	for _, player in Players:GetPlayers() do
		table.insert(fighters, { character = player.Character, player = player })
	end
	local bots = workspace:FindFirstChild("NAU_StressBots")
	if bots then
		for _, bot in bots:GetChildren() do
			if bot:IsA("Model") then
				table.insert(fighters, { character = bot })
			end
		end
	end
	for _, fighter in fighters do
		local player = fighter.player
		local character = fighter.character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if character and root and root:IsA("BasePart") and humanoid then
			local rig = rigFor(character)
			if rig then
				local target = speedFactor(root, humanoid, config)
				if target >= 0 then
					rig.factor = approach(rig.factor, target, if target > rig.factor then 8 else 5, dt)
				end
				for _, trail in rig.trails do
					trail.Enabled = rig.factor > 0.45
				end
				if rig.dust then
					rig.dust.Rate = if humanoid.FloorMaterial ~= Enum.Material.Air then 45 * rig.factor else 0
				end
				if player == localPlayer then
					localFactor = rig.factor
				end
			end
		end
	end
end

-- Layer a pitch about the joint's X axis onto this frame's animated pose. Negative leans a torso
-- forward and sweeps a hanging arm back (measured in play on these rigs).
local function pitchJoint(joint: Joint?, radians: number)
	if joint and joint.instance.Parent then
		joint.instance.Transform *= CFrame.Angles(radians, 0, 0)
		joint.dirty = true
	end
end

-- Before the animator runs: put any joint we touched last frame back to neutral. Animated joints get
-- overwritten by the animator anyway; this stops the offset piling up on a joint no track drives.
local function resetPose()
	for _, rig in rigs do
		for _, joint in { rig.waist, rig.neck, rig.rightShoulder, rig.leftShoulder } do
			if joint and joint.dirty then
				joint.dirty = false
				if joint.instance.Parent then
					joint.instance.Transform = CFrame.identity
				end
			end
		end
	end
end

-- The ninja-run pose: body leans forward, arms sweep back, head stays level; blends with speed.
local function applyPose(config: Config)
	for _, rig in rigs do
		local f = rig.factor
		if f > 0.01 then
			local lean = math.rad(config.leanDegrees * f)
			local armsBack = math.rad(config.armsBackDegrees * f)
			pitchJoint(rig.waist, -lean)
			pitchJoint(rig.neck, lean * 0.7) -- keep the eyes on the road
			pitchJoint(rig.rightShoulder, -armsBack)
			pitchJoint(rig.leftShoulder, -armsBack)
		end
	end
end

-- Camera lean and stride bob, applied right after the default camera has placed itself.
local function updateCamera(dt: number, config: Config)
	local camera = workspace.CurrentCamera
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not camera or camera.CameraType ~= Enum.CameraType.Custom or not root or not root:IsA("BasePart") then
		return
	end
	if not options.cameraSway then
		roll = 0
		return
	end
	local turnRate = root.AssemblyAngularVelocity.Y
	local targetRoll = math.clamp(-turnRate * 0.08, -1, 1) * config.rollDegrees * localFactor
	roll = approach(roll, targetRoll, 6, dt)
	bobClock += dt * (2.2 + 1.2 * localFactor)
	local bob = math.sin(bobClock * math.pi * 2) * config.bob * localFactor
	if math.abs(roll) > 0.01 or math.abs(bob) > 0.001 then
		camera.CFrame = camera.CFrame * CFrame.new(0, bob, 0) * CFrame.Angles(0, 0, math.rad(roll))
	end
end

-- Player settings: `speedLines` (streaks + vignette) and `cameraSway` (lean + stride bob). The run pose,
-- trails and dust are on other fighters too, so they stay.
function SprintFX.setOptions(new: { speedLines: boolean?, cameraSway: boolean? })
	if new.speedLines ~= nil then
		options.speedLines = new.speedLines
	end
	if new.cameraSway ~= nil then
		options.cameraSway = new.cameraSway
	end
end

local started = false
function SprintFX.start(config: Config)
	if started then
		return
	end
	started = true
	buildOverlay()
	RunService.RenderStepped:Connect(function(dt)
		updateCharacters(dt, config)
		updateOverlay(os.clock())
	end)
	RunService.PreAnimation:Connect(resetPose)
	RunService.Stepped:Connect(function()
		applyPose(config)
	end)
	RunService:BindToRenderStep("NAU_SprintCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		updateCamera(dt, config)
	end)
end

return SprintFX
