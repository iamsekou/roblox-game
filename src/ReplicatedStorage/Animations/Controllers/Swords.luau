-- In-hand swords for the sword fighters (owner-approved 2026-09-23): Zorin (a katana in each hand and a
-- third clenched in the teeth),
-- Ichiro (one oversized black cleaver-style blade), Sazuki (a straight, thin blade). A sword appears in
-- the hand with a flash when a sword ability's wind-up starts and dissolves after the strike
-- (AbilityAnim drives that from the move's `swords` entry in AbilityPoses). Generic shapes, built from
-- parts in code; nothing is uploaded.
--
-- Every client builds its own copy for every caster (the cast event reaches everyone), so the parts are
-- client-only: unanchored, massless, welded to the hand, and never collide, cast shadows or take
-- raycasts. They live in workspace.NAU_Swords, not inside the character, so nothing that measures the
-- avatar (plates, fades) sees them.
--
-- Grip frame (measured in play on this place's R15 hands, 2026-09-23): the hand's -Y runs down the arm
-- and -Z is forward, so the blade runs along the grip's -Z. From a hanging fist it points forward; from
-- an arm raised forward it points up. The same grip is used for the authoring copies (docs/ANIMATING.md).
local TweenService = game:GetService("TweenService")

local Swords = {}

export type Kind = string -- "Katana" | "KatanaDark" | "KatanaRed" | "Cleaver" | "Blade"
export type Spec = { right: Kind?, left: Kind?, mouth: Kind? }

local GRIP_OFFSET = CFrame.new(0, -0.3, 0) -- from the hand's centre to the middle of the fist
-- Zorin's third sword (owner request, 2026-09-23): the hilt clenched crosswise in the teeth, the blade
-- out past the right cheek. The mouth sits low on the front of the head; the grip then turns so the
-- blade (grip -Z) runs along the head's +X, shifted so the guard clears the cheek.
local function mouthGrip(head: BasePart): CFrame
	local size = head.Size
	return CFrame.new(0, -0.22 * size.Y, -size.Z / 2 - 0.08) * CFrame.Angles(0, math.rad(-90), 0) * CFrame.new(0, 0, -0.18 * size.X)
end
local DRAW_SECONDS = 0.12
local SHEATHE_SECONDS = 0.2

local STEEL = Color3.fromRGB(206, 212, 218)
local EDGE = Color3.fromRGB(245, 248, 252)

type Held = { model: Model, token: number, glow: BasePart? }
type Hands = { right: Held?, left: Held?, mouth: Held? }

local held: { [Model]: Hands } = {}
local nextToken = 0
local folder: Folder? = nil

local function swordFolder(): Folder
	if not folder or not folder.Parent then
		local f = Instance.new("Folder")
		f.Name = "NAU_Swords"
		f.Parent = workspace
		folder = f
	end
	return folder :: Folder
end

-- Builders -----------------------------------------------------------------------------------------

local function piece(model: Model, grip: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.CFrame = grip.CFrame * offset
	p.Color = color
	p.Material = material
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Anchored = false
	p:SetAttribute("NAU_Transparency", 0)
	local weld = Instance.new("Weld")
	weld.Part0 = grip
	weld.Part1 = p
	weld.C0 = offset
	weld.Parent = p
	p.Parent = model
	return p
end

local function newModel(name: string): (Model, Part)
	local model = Instance.new("Model")
	model.Name = name
	local grip = Instance.new("Part")
	grip.Name = "Grip"
	grip.Size = Vector3.one * 0.1
	grip.Transparency = 1
	grip.CanCollide = false
	grip.CanQuery = false
	grip.CanTouch = false
	grip.CastShadow = false
	grip.Massless = true
	grip.CFrame = CFrame.identity
	grip:SetAttribute("NAU_Transparency", 1)
	grip.Parent = model
	model.PrimaryPart = grip
	return model, grip
end

-- The trail endpoints ride on the grip: BladeBase just past the guard, BladeTip at the point.
local function addTrail(grip: BasePart, baseZ: number, tipZ: number, color: Color3)
	local base = Instance.new("Attachment")
	base.Name = "BladeBase"
	base.Position = Vector3.new(0, 0, baseZ)
	base.Parent = grip
	local tip = Instance.new("Attachment")
	tip.Name = "BladeTip"
	tip.Position = Vector3.new(0, 0, tipZ)
	tip.Parent = grip
	local trail = Instance.new("Trail")
	trail.Name = "SlashTrail"
	trail.Attachment0 = base
	trail.Attachment1 = tip
	trail.Lifetime = 0.2
	trail.MinLength = 0.05
	trail.LightEmission = 0.7
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new(1, 0.4)
	trail.Enabled = false
	trail.Parent = grip
end

-- A katana: wrapped grip, round guard, a long single-edged blade with a gentle upward curve (edge down).
local function katana(hilt: Color3, name: string): Model
	local model, grip = newModel(name)
	piece(model, grip, "Handle", Vector3.new(0.17, 0.19, 1.0), CFrame.new(0, 0, 0.05), hilt, Enum.Material.Fabric)
	piece(model, grip, "Pommel", Vector3.new(0.19, 0.21, 0.08), CFrame.new(0, 0, 0.58), Color3.fromRGB(150, 130, 90), Enum.Material.Metal)
	piece(model, grip, "Guard", Vector3.new(0.06, 0.5, 0.5), CFrame.new(0, 0, -0.5) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(60, 56, 50), Enum.Material.Metal, Enum.PartType.Cylinder)
	local z, y, angle = -0.53, 0, 0
	for i = 1, 4 do
		local length = if i == 4 then 0.7 else 0.95
		angle += math.rad(2.2)
		local center = CFrame.new(0, y, z) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, 0, -length / 2)
		local blade = piece(model, grip, "Blade" .. i, Vector3.new(0.05, 0.2 - i * 0.012, length), center, STEEL, Enum.Material.Metal)
		blade.Reflectance = 0.25
		piece(model, grip, "Edge" .. i, Vector3.new(0.02, 0.04, length), center * CFrame.new(0, -(0.1 - i * 0.006), 0), EDGE, Enum.Material.SmoothPlastic)
		local tip = center * CFrame.new(0, 0, -length / 2)
		z, y = tip.Position.Z, tip.Position.Y
	end
	-- A wedge tapers toward its -Z face with the flat side down: the spine slopes to meet the edge.
	local point = piece(model, grip, "Point", Vector3.new(0.05, 0.14, 0.3), CFrame.new(0, y, z) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, -0.02, -0.15), STEEL, Enum.Material.Metal)
	point.Shape = Enum.PartType.Wedge
	addTrail(grip, -0.7, z - 0.2, Color3.fromRGB(225, 240, 235))
	return model
end

-- The cleaver: an oversized black blade, wider below the grip line, with a silver edge and no guard.
local function cleaver(): Model
	local model, grip = newModel("Cleaver")
	piece(model, grip, "Handle", Vector3.new(0.19, 0.2, 1.25), CFrame.new(0, 0, 0.15), Color3.fromRGB(30, 30, 34), Enum.Material.Fabric)
	for i, z in { 0.55, 0.2, -0.15 } do
		piece(model, grip, "Wrap" .. i, Vector3.new(0.21, 0.22, 0.08), CFrame.new(0, 0, z), Color3.fromRGB(225, 222, 214), Enum.Material.Fabric)
	end
	piece(model, grip, "Collar", Vector3.new(0.14, 0.34, 0.14), CFrame.new(0, -0.02, -0.5), Color3.fromRGB(70, 70, 76), Enum.Material.Metal)
	local blade = piece(model, grip, "Blade", Vector3.new(0.1, 0.95, 4.3), CFrame.new(0, -0.22, -2.7), Color3.fromRGB(22, 22, 26), Enum.Material.Metal)
	blade.Reflectance = 0.15
	piece(model, grip, "Edge", Vector3.new(0.06, 0.12, 4.3), CFrame.new(0, -0.74, -2.7), Color3.fromRGB(215, 220, 228), Enum.Material.Metal)
	local point = piece(model, grip, "Point", Vector3.new(0.1, 1.07, 0.7), CFrame.new(0, -0.28, -5.2), Color3.fromRGB(22, 22, 26), Enum.Material.Metal)
	point.Shape = Enum.PartType.Wedge
	addTrail(grip, -0.8, -5.4, Color3.fromRGB(220, 60, 70))
	return model
end

-- A straight, thin blade with a small square guard.
local function straight(): Model
	local model, grip = newModel("Blade")
	piece(model, grip, "Handle", Vector3.new(0.14, 0.15, 0.95), CFrame.new(0, 0, 0.05), Color3.fromRGB(62, 58, 70), Enum.Material.Fabric)
	piece(model, grip, "Guard", Vector3.new(0.08, 0.3, 0.26), CFrame.new(0, 0, -0.48), Color3.fromRGB(45, 45, 50), Enum.Material.Metal)
	local blade = piece(model, grip, "Blade", Vector3.new(0.045, 0.15, 3.1), CFrame.new(0, 0, -2.1), STEEL, Enum.Material.Metal)
	blade.Reflectance = 0.3
	local point = piece(model, grip, "Point", Vector3.new(0.045, 0.15, 0.3), CFrame.new(0, 0, -3.8), STEEL, Enum.Material.Metal)
	point.Shape = Enum.PartType.Wedge
	addTrail(grip, -0.7, -3.9, Color3.fromRGB(170, 190, 255))
	return model
end

local BUILDERS: { [string]: () -> Model } = {
	Katana = function()
		return katana(Color3.fromRGB(235, 232, 222), "Katana")
	end,
	KatanaDark = function()
		return katana(Color3.fromRGB(28, 28, 32), "KatanaDark")
	end,
	KatanaRed = function()
		return katana(Color3.fromRGB(120, 28, 34), "KatanaRed")
	end,
	Cleaver = cleaver,
	Blade = straight,
}

-- A fresh, visible sword model with its grip at the origin (also used to make the authoring copies).
function Swords.build(kind: Kind): Model?
	local builder = BUILDERS[kind]
	return if builder then builder() else nil
end

-- Held swords --------------------------------------------------------------------------------------

local function setTransparency(model: Model, alpha: number, seconds: number)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			local target = alpha + (1 - alpha) * (p:GetAttribute("NAU_Transparency") or 0)
			if seconds > 0 then
				TweenService:Create(p, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = target }):Play()
			else
				p.Transparency = target
			end
		end
	end
end

local function flash(position: Vector3, color: Color3)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = Vector3.one * 0.4
	p.CFrame = CFrame.new(position)
	p.Transparency = 0.1
	p.Parent = swordFolder()
	local tween = TweenService:Create(p, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * 2.4, Transparency = 1 })
	tween.Completed:Connect(function()
		p:Destroy()
	end)
	tween:Play()
end

local function release(entry: Held?, seconds: number)
	if not entry then
		return
	end
	local model = entry.model
	for _, d in model:GetDescendants() do
		if d:IsA("Trail") then
			d.Enabled = false
		end
	end
	if seconds <= 0 then
		model:Destroy()
		return
	end
	setTransparency(model, 1, seconds)
	task.delay(seconds, function()
		model:Destroy()
	end)
end

local function attach(character: Model, partName: string, kind: Kind, token: number): Held?
	local hand = character:FindFirstChild(partName)
	if not hand or not hand:IsA("BasePart") then
		return nil
	end
	local model = Swords.build(kind)
	if not model then
		return nil
	end
	local offset = if partName == "Head" then mouthGrip(hand) else GRIP_OFFSET
	local grip = model.PrimaryPart :: BasePart
	setTransparency(model, 1, 0)
	model:PivotTo(hand.CFrame * offset)
	local weld = Instance.new("Weld")
	weld.Part0 = hand
	weld.Part1 = grip
	weld.C0 = offset
	weld.Parent = grip
	model.Parent = swordFolder()
	setTransparency(model, 0, DRAW_SECONDS)
	flash(hand.Position, Color3.fromRGB(235, 240, 255))
	return { model = model, token = token }
end

-- Draw the move's swords into the fighter's hands (replacing any still out).
function Swords.draw(character: Model, spec: Spec)
	Swords.sheathe(character, 0)
	nextToken += 1
	local hands: Hands = {}
	if spec.right then
		hands.right = attach(character, "RightHand", spec.right, nextToken)
	end
	if spec.left then
		hands.left = attach(character, "LeftHand", spec.left, nextToken)
	end
	if spec.mouth then
		hands.mouth = attach(character, "Head", spec.mouth, nextToken)
	end
	held[character] = hands
end

-- Dissolve the fighter's swords (0 seconds = remove at once, e.g. on death).
function Swords.sheathe(character: Model, seconds: number?)
	local hands = held[character]
	if not hands then
		return
	end
	held[character] = nil
	local fade = if seconds == nil then SHEATHE_SECONDS else seconds
	release(hands.right, fade)
	release(hands.left, fade)
	release(hands.mouth, fade)
end

-- The sword model in one hand ("right" / "left"), if one is out.
function Swords.get(character: Model?, hand: string): Model?
	local hands = character and held[character]
	local entry = hands and (hands :: any)[hand]
	return if entry and entry.model.Parent then entry.model else nil
end

-- Blade trails on or off (strikes and spins).
function Swords.setTrails(character: Model, on: boolean)
	local hands = held[character]
	if not hands then
		return
	end
	for _, entry in { hands.right, hands.left, hands.mouth } do
		if entry and entry.model.Parent then
			local trail = entry.model.PrimaryPart and entry.model.PrimaryPart:FindFirstChild("SlashTrail")
			if trail then
				(trail :: Trail).Enabled = on
			end
		end
	end
end

-- Every blade part of a held sword (for glows and crackles).
function Swords.bladeParts(model: Model): { BasePart }
	local parts = {}
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and (string.find(p.Name, "^Blade") or string.find(p.Name, "^Point")) then
			table.insert(parts, p)
		end
	end
	return parts
end

-- World positions of the blade's base and tip right now.
function Swords.bladeLine(model: Model): (Vector3?, Vector3?)
	local grip = model.PrimaryPart
	local base = grip and grip:FindFirstChild("BladeBase")
	local tip = grip and grip:FindFirstChild("BladeTip")
	if base and tip then
		return (base :: Attachment).WorldPosition, (tip :: Attachment).WorldPosition
	end
	return nil, nil
end

return Swords
