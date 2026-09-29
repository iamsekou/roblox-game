-- Fighter auras (owner, 2026-09-29): every other fighter in the arena carries a faint aura in their fighter's
-- colour (CharacterDefs AURAS), so you can tell at a glance what you're up against: wisps rising off the body
-- and a ring at the feet. The name chip under the number plate (NumberPlateController) says it in words.
--
-- Client-only and cosmetic. The server tags each arena character with its fighter (Constants.FIGHTER_ATTRIBUTE);
-- lobby characters are fresh models without the tag, so the lobby stays clean. Mirror Decoys are copies of the
-- caster's character, so they carry the tag and look exactly like the fighter. Your own fighter gets none.
-- Depth-tested like everything else in the world: cover hides an aura, nothing shows through walls.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Modules"):WaitForChild("Constants"))
local CharacterDefs = require(Shared:WaitForChild("Modules"):WaitForChild("CharacterDefs"))

local FighterAura = {}

local SCAN_SECONDS = 0.25
-- Ships with the engine (not an uploaded asset). Neutral grey, so it takes the aura colour cleanly (the engine's
-- fire texture is orange and turned every colour muddy).
local WISP_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

type Aura = { fighter: string, root: BasePart, base: BasePart, wisps: ParticleEmitter, ring: CylinderHandleAdornment }

local localPlayer = Players.LocalPlayer
local auras: { [Model]: Aura } = {}
local enabled = true -- player setting ("Fighter auras")
local started = false

local function build(model: Model, root: BasePart, def: any): Aura
	local color = def.aura :: Color3
	local dark = def.auraDark == true
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local feet = -((if humanoid then humanoid.HipHeight else 2) + root.Size.Y / 2) -- the ground, from the root

	-- Wisps rise from a flat invisible disc at the feet, so they climb *around* the body (from inside the torso
	-- the body hid them). A client-only part welded to the root: no collision, no queries, no mass.
	local base = Instance.new("Part")
	base.Name = "NAU_AuraBase"
	base.Size = Vector3.new(Constants.AURA_RING_RADIUS * 1.75, 0.2, Constants.AURA_RING_RADIUS * 1.75)
	base.Transparency = 1
	base.CanCollide = false
	base.CanQuery = false
	base.CanTouch = false
	base.Massless = true
	base.CastShadow = false
	base.CFrame = root.CFrame * CFrame.new(0, feet + 0.2, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = base
	weld.Parent = base
	base.Parent = model

	local wisps = Instance.new("ParticleEmitter")
	wisps.Name = "NAU_AuraWisps"
	wisps.Texture = WISP_TEXTURE
	wisps.Color = ColorSequence.new(color)
	-- Mostly solid coloured smoke with a touch of glow: a glow only adds light, which vanished against the
	-- arena's pale sand (measured in Studio); dark smoke must not glow at all.
	wisps.LightEmission = if dark then 0 else 0.25
	wisps.Brightness = if dark then 1 else 1.5
	wisps.LightInfluence = 0
	wisps.Rate = Constants.AURA_WISP_RATE
	wisps.Lifetime = NumberRange.new(Constants.AURA_WISP_LIFETIME * 0.7, Constants.AURA_WISP_LIFETIME)
	wisps.Speed = NumberRange.new(3, 5)
	wisps.Acceleration = Vector3.new(0, 2, 0)
	wisps.SpreadAngle = Vector2.new(8, 8)
	wisps.EmissionDirection = Enum.NormalId.Top
	wisps.Shape = Enum.ParticleEmitterShape.Box
	wisps.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	wisps.Rotation = NumberRange.new(0, 360)
	wisps.RotSpeed = NumberRange.new(-40, 40)
	local size = Constants.AURA_WISP_SIZE
	wisps.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * 0.4),
		NumberSequenceKeypoint.new(0.35, size),
		NumberSequenceKeypoint.new(1, size * 0.25),
	})
	wisps.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, Constants.AURA_WISP_TRANSPARENCY),
		NumberSequenceKeypoint.new(1, 1),
	})
	wisps.Enabled = false
	wisps.Parent = base

	-- Ring at the feet: a thin flat band, following the root (so it lifts with a jump).
	local ring = Instance.new("CylinderHandleAdornment")
	ring.Name = "NAU_AuraRing"
	ring.Adornee = root
	ring.AlwaysOnTop = false
	ring.Radius = Constants.AURA_RING_RADIUS
	ring.InnerRadius = Constants.AURA_RING_RADIUS - Constants.AURA_RING_WIDTH
	ring.Height = 0.06
	ring.Color3 = color
	ring.Transparency = Constants.AURA_RING_TRANSPARENCY
	ring.CFrame = CFrame.new(0, feet + 0.08, 0) * CFrame.Angles(math.rad(90), 0, 0)
	ring.Visible = false
	ring.Parent = root

	return { fighter = def.id, root = root, base = base, wisps = wisps, ring = ring }
end

local function remove(model: Model)
	local aura = auras[model]
	auras[model] = nil
	if aura then
		aura.base:Destroy() -- the wisps with it
		aura.ring:Destroy()
	end
end

-- Other fighters' characters, and every Mirror Decoy (another fighter's, or our own: others see ours).
local function candidates(): { Model }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player ~= localPlayer and player.Character then
			table.insert(list, player.Character)
		end
	end
	local world = workspace:FindFirstChild("NAUWorld")
	local decoys = world and world:FindFirstChild("Decoys")
	for _, model in if decoys then decoys:GetChildren() else {} do
		if model:IsA("Model") and model:GetAttribute("Owner") ~= localPlayer.UserId then
			table.insert(list, model)
		end
	end
	return list
end

local function scan()
	local mine = localPlayer.Character
	local myRoot = mine and mine:FindFirstChild("HumanoidRootPart")
	local center = if myRoot and myRoot:IsA("BasePart") then myRoot.Position else workspace.CurrentCamera.CFrame.Position
	local seen: { [Model]: boolean } = {}
	for _, model in candidates() do
		local fighter = model:GetAttribute(Constants.FIGHTER_ATTRIBUTE)
		local def = if type(fighter) == "string" then CharacterDefs.byId[fighter] else nil
		local root = model:FindFirstChild("HumanoidRootPart")
		if enabled and def and def.aura and root and root:IsA("BasePart") then
			seen[model] = true
			local aura = auras[model]
			if aura and (aura.fighter ~= def.id or aura.root ~= root or not aura.base.Parent) then
				remove(model) -- a new fighter on the same model, or a rebuilt root
				aura = nil
			end
			if not aura then
				aura = build(model, root, def)
				auras[model] = aura
			end
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			local alive = humanoid == nil or humanoid.Health > 0
			local near = (root.Position - center).Magnitude <= Constants.AURA_MAX_DISTANCE
			local show = alive and near
			aura.wisps.Enabled = show
			aura.ring.Visible = show
		end
	end
	for model in auras do
		if not seen[model] then
			remove(model)
		end
	end
end

function FighterAura.setEnabled(on: boolean)
	enabled = on
	if started then
		scan()
	end
end

function FighterAura.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		while true do
			-- One bad frame must not end the loop for the session.
			local ok, err = pcall(scan)
			if not ok then
				warn("[NAU] fighter aura scan failed: " .. tostring(err))
			end
			task.wait(SCAN_SECONDS)
		end
	end)
end

return FighterAura
