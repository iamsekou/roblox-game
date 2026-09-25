-- Respawn "materialize": a ring expands at the feet while the fighter fades in.
-- Placeholder for an authored respawn animation. Client-side visuals only.
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CharacterFade = require(script.Parent.CharacterFade)

local SpawnFX = {}

local RING_COLOR = Color3.fromRGB(150, 230, 255)
local FADE_TIME = 0.45

-- isLocal: skip the fade on your own character (the default camera manages its transparency).
function SpawnFX.play(character: Model, isLocal: boolean?)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local ring = Instance.new("Part")
	ring.Name = "NAU_SpawnRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = RING_COLOR
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.15, 2, 2)
	-- Cylinders run along X; roll 90 degrees so the disc lies flat under the fighter's feet.
	ring.CFrame = CFrame.new(root.Position - Vector3.new(0, 2.9, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace.CurrentCamera
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, 11, 11),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.6)

	if isLocal then
		-- The server places the fighter after the character loads, so the default camera can still
		-- face the old heading (e.g. staring at the wall behind a north-end spawn). Swing it behind
		-- the fighter, looking the way they face. The camera stays Custom, so control is never taken away.
		RunService.RenderStepped:Wait()
		local camera = workspace.CurrentCamera
		if camera and camera.CameraType == Enum.CameraType.Custom and root.Parent then
			local look = root.CFrame.LookVector
			local focus = root.Position + Vector3.new(0, 1.5, 0)
			camera.CFrame = CFrame.lookAt(focus - look * 12 + Vector3.new(0, 4, 0), focus + look * 6)
		end
	else
		CharacterFade.run(character, 1, 0, FADE_TIME)
	end
end

return SpawnFX
