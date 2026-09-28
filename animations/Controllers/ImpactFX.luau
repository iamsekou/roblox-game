-- The impact layer (owner, 2026-09-27: "more action, high intensity"). Client-only visuals on top of the fight
-- animations and the existing ability effects (AbilityFX), so every blow *lands*:
--   * hit-stop: attacker and target freeze for a split second on contact (casts and Animator tracks alike);
--   * shockwaves: a ring bursts out where the blow lands; heavy blows also slam a ring and dust into the ground;
--   * afterimages: ghost copies left behind along dashes, lunges, pulls and launches;
--   * for the two fighters involved only: a camera shake, and on heavy blows a one-frame black-and-white
--     impact frame. Both follow the Screen shake setting (off: no impact frame; CameraShake shows its edge
--     flash instead of shaking).
-- Driven by the server's AbilityFX events (melee_hit, clash, clash_end) and by AbilityAnim's release moments.
-- Everything here is visual; the server never waits on it. Numbers: Constants IMPACT_*.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Constants"))
local AbilityAnim = require(script.Parent:WaitForChild("AbilityAnim"))
local CameraShake = require(script.Parent:WaitForChild("CameraShake"))

local ImpactFX = {}

local WHITE = Color3.fromRGB(255, 248, 235)
local DUST = Color3.fromRGB(214, 202, 180)
local GHOST = Color3.fromRGB(170, 215, 255)
local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

-- Moves whose caster streaks across the arena: afterimages follow them from the release on (seconds).
local TRAILS: { [string]: number } = {
	["Sasuke.mild"] = 0.3, -- Lightning Dash
	["Ichigo.mild"] = 0.3, -- Blur Step
	["Naruto.ultimate"] = 0.35, -- Vortex Orb lunge
	["Luffy.mild"] = 0.45, -- Stretch Grapple pull
}
-- Releases heavy enough to shake the ground under the caster.
local HEAVY_RELEASES: { [string]: boolean } = {
	["Melee.m1_4"] = true,
}

local localPlayer = Players.LocalPlayer
local fxFolder: Folder? = nil
-- A finisher reaches its victim twice (the server's melee_hit, then the knockback itself): one heavy moment
-- per blow, not two stacked impact frames.
local lastLocalHeavy = 0
local function claimLocalHeavy(): boolean
	local now = os.clock()
	if now - lastLocalHeavy < 0.25 then
		return false
	end
	lastLocalHeavy = now
	return true
end

local function folder(): Folder
	if fxFolder and fxFolder.Parent then
		return fxFolder
	end
	local f = Instance.new("Folder")
	f.Name = "NAU_ImpactFX"
	f.Parent = workspace
	fxFolder = f
	return f
end

local function characterOf(userId: any): Model?
	local player = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	return player and player.Character
end

local function rootOf(character: Model?): BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function isLocal(character: Model?): boolean
	return character ~= nil and character == localPlayer.Character
end

local function effectPart(shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, transparency: number): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency
	p.Size = size
	p.CFrame = cframe
	p.Parent = folder()
	return p
end

local function fade(instance: Instance, seconds: number, goal: { [string]: any })
	local tween = TweenService:Create(instance, TweenInfo.new(seconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), goal)
	tween.Completed:Connect(function()
		instance:Destroy()
	end)
	tween:Play()
end

-- Hit-stop -----------------------------------------------------------------------------------------

-- Freeze these fighters for `seconds`: their cast poses (AbilityAnim) and whatever their Animator is playing
-- (walks, published clips), then let everything run on.
function ImpactFX.hitStop(characters: { Model? }, seconds: number)
	for _, character in characters do
		if character and character.Parent then
			AbilityAnim.freeze(character, seconds)
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
			if animator then
				local paused: { [AnimationTrack]: number } = {}
				for _, track in animator:GetPlayingAnimationTracks() do
					if track.Speed ~= 0 then
						paused[track] = track.Speed
						track:AdjustSpeed(0)
					end
				end
				task.delay(seconds, function()
					for track, speed in paused do
						if track.Speed == 0 then -- nobody changed it meanwhile
							track:AdjustSpeed(speed)
						end
					end
				end)
			end
		end
	end
end

-- Shapes -------------------------------------------------------------------------------------------

-- A ring bursting outward, facing `normal` (up for a ground ring, the blow's direction for a hit).
function ImpactFX.shockwave(position: Vector3, normal: Vector3, radius: number, seconds: number, color: Color3?)
	local up = if normal.Magnitude > 0.01 then normal.Unit else Vector3.yAxis
	-- A cylinder's axis is its X: point X along the normal.
	local cframe = CFrame.lookAt(position, position + up) * CFrame.Angles(0, math.rad(90), 0)
	local ring = effectPart(Enum.PartType.Cylinder, Vector3.new(0.12, 0.6, 0.6), cframe, color or WHITE, 0.15)
	ring.Material = Enum.Material.ForceField
	fade(ring, seconds, { Size = Vector3.new(0.05, radius * 2, radius * 2), Transparency = 1 })
	local core = effectPart(Enum.PartType.Ball, Vector3.one * 0.5, CFrame.new(position), color or WHITE, 0.1)
	fade(core, seconds * 0.6, { Size = Vector3.one * radius * 0.9, Transparency = 1 })
end

-- A puff of dust kicked up from the ground.
function ImpactFX.dust(position: Vector3, amount: number)
	local anchor = effectPart(Enum.PartType.Block, Vector3.one * 0.1, CFrame.new(position), DUST, 1)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = DUST_TEXTURE
	emitter.Color = ColorSequence.new(DUST)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 3.2) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(80, 12)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Acceleration = Vector3.new(0, 4, 0)
	emitter.Drag = 5
	emitter.Rate = 0
	emitter.Parent = anchor
	emitter:Emit(amount)
	task.delay(1, function()
		anchor:Destroy()
	end)
end

-- One ghost of a fighter's current pose, fading where it stands.
local function ghost(character: Model)
	local model = Instance.new("Model")
	model.Name = "Afterimage"
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Transparency < 0.9 then
			local copy = part:Clone()
			for _, child in copy:GetChildren() do
				if not (child:IsA("SpecialMesh") or child:IsA("DataModelMesh")) then
					child:Destroy()
				end
			end
			copy.Anchored = true
			copy.CanCollide = false
			copy.CanQuery = false
			copy.CanTouch = false
			copy.CastShadow = false
			copy.Material = Enum.Material.Neon
			copy.Color = GHOST
			copy.Transparency = 0.55
			if copy:IsA("MeshPart") then
				copy.TextureID = ""
			end
			copy.CFrame = part.CFrame
			copy.Parent = model
			fade(copy, Constants.IMPACT_AFTERIMAGE_FADE, { Transparency = 1 })
		end
	end
	model.Parent = folder()
	task.delay(Constants.IMPACT_AFTERIMAGE_FADE + 0.1, function()
		model:Destroy()
	end)
end

-- Ghosts left behind a fighter as they move over the next `seconds`.
function ImpactFX.afterimages(character: Model?, seconds: number)
	if not character then
		return
	end
	local count = Constants.IMPACT_AFTERIMAGES
	task.spawn(function()
		for _ = 1, count do
			if not character.Parent then
				return
			end
			ghost(character)
			task.wait(seconds / count)
		end
	end)
end

-- Only for the fighter it happens to: the black-and-white impact frame.
function ImpactFX.impactFrame(seconds: number)
	if not CameraShake.isEnabled() then
		return -- the Screen shake setting also turns these flashes off
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "NAU_ImpactFrame"
	cc.Saturation = -1
	cc.Contrast = 0.7
	cc.Brightness = 0.08
	cc.Parent = Lighting
	task.delay(seconds, function()
		cc:Destroy()
	end)
end

-- Blows --------------------------------------------------------------------------------------------

-- A blow lands on `target` from `attacker` at `position`. Heavy = finishers, clashes, heavy ability hits.
function ImpactFX.hit(attacker: Model?, target: Model?, position: Vector3, direction: Vector3?, heavy: boolean)
	ImpactFX.hitStop({ attacker, target }, if heavy then Constants.IMPACT_HITSTOP_HEAVY else Constants.IMPACT_HITSTOP_LIGHT)
	local facing = if direction and direction.Magnitude > 0.01 then direction else Vector3.yAxis
	ImpactFX.shockwave(position, facing, if heavy then 4.5 else 2, if heavy then 0.4 else 0.22)
	if heavy then
		local root = rootOf(target)
		local floor = if root then root.Position - Vector3.new(0, 2.9, 0) else position - Vector3.new(0, 3, 0)
		ImpactFX.shockwave(floor, Vector3.yAxis, 7, 0.55, DUST)
		ImpactFX.dust(floor, 14)
		ImpactFX.afterimages(target, 0.4)
	end
	if isLocal(attacker) or isLocal(target) then
		CameraShake.shake(if heavy then Constants.IMPACT_SHAKE_HEAVY else Constants.IMPACT_SHAKE_LIGHT, if heavy then 0.4 else 0.18)
		if heavy and claimLocalHeavy() then
			ImpactFX.impactFrame(Constants.IMPACT_FLASH_SECONDS)
		end
	end
end

-- Server events (the same ones AbilityFX draws).
function ImpactFX.handle(event: any)
	if type(event) ~= "table" then
		return
	end
	if event.kind == "melee_hit" and typeof(event.position) == "Vector3" then
		local direction = if typeof(event.direction) == "Vector3" then -event.direction else nil -- the blow travels away from the puncher
		ImpactFX.hit(characterOf(event.caster), characterOf(event.target), event.position, direction, event.finisher == true)
	elseif event.kind == "clash" and typeof(event.midpoint) == "Vector3" then
		local a, b = characterOf(event.a), characterOf(event.b)
		ImpactFX.hit(a, b, event.midpoint + Vector3.new(0, 1, 0), nil, true)
	elseif event.kind == "clash_end" and typeof(event.midpoint) == "Vector3" then
		local a, b = characterOf(event.a), characterOf(event.b)
		ImpactFX.shockwave(event.midpoint - Vector3.new(0, 2.9, 0), Vector3.yAxis, 9, 0.6, DUST)
		ImpactFX.dust(event.midpoint - Vector3.new(0, 2.9, 0), 20)
		ImpactFX.afterimages(a, 0.35)
		ImpactFX.afterimages(b, 0.35)
		if isLocal(a) or isLocal(b) then
			CameraShake.shake(Constants.IMPACT_SHAKE_HEAVY, 0.45)
		end
	end
end

-- Our own character took an ability's knockback (applied on this client): feel it.
function ImpactFX.selfKnockback(velocity: Vector3)
	local heavy = velocity.Magnitude >= 45
	CameraShake.shake(if heavy then Constants.IMPACT_SHAKE_HEAVY else Constants.IMPACT_SHAKE_LIGHT, if heavy then 0.35 else 0.2)
	if heavy and claimLocalHeavy() then
		ImpactFX.impactFrame(Constants.IMPACT_FLASH_SECONDS)
		ImpactFX.afterimages(localPlayer.Character, 0.35)
	end
end

local started = false
function ImpactFX.start()
	if started then
		return
	end
	started = true
	-- Release moments: dashes leave afterimages; heavy releases slam the ground under the caster.
	AbilityAnim.onRelease(function(character: Model, characterId: string, slot: string)
		local key = characterId .. "." .. slot
		if TRAILS[key] then
			ImpactFX.afterimages(character, TRAILS[key])
		end
		if HEAVY_RELEASES[key] or (slot == "ultimate" and characterId ~= "Melee") then
			local root = rootOf(character)
			if root then
				local floor = root.Position - Vector3.new(0, 2.9, 0)
				ImpactFX.shockwave(floor, Vector3.yAxis, 6, 0.5, DUST)
				ImpactFX.dust(floor, 10)
				if isLocal(character) then
					CameraShake.shake(Constants.IMPACT_SHAKE_LIGHT, 0.25)
				end
			end
		end
	end)
end

return ImpactFX
