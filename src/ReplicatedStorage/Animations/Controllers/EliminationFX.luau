-- Victim reaction for a number-code elimination: "out-thought, not beaten up".
-- A white flash that cools to red, a burst of glowing shards, then the body fades away.
-- Placeholder until an authored animation exists; everything here is client-side visuals only.
-- The server just sets Health = 0 (with BreakJointsOnDeath off, so nothing falls apart).
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local CharacterFade = require(script.Parent.CharacterFade)

local EliminationFX = {}

local FADE_DELAY = 0.15
local FADE_TIME = 0.7
local SHARD_COUNT = 8
local SHARD_COLOR = Color3.fromRGB(255, 120, 60)

function EliminationFX.play(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.OutlineColor = Color3.fromRGB(255, 70, 70)
	highlight.FillTransparency = 0.1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = character
	TweenService:Create(highlight, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FillColor = Color3.fromRGB(255, 60, 60),
		FillTransparency = 1,
		OutlineTransparency = 1,
	}):Play()
	Debris:AddItem(highlight, FADE_DELAY + FADE_TIME + 0.2)

	local origin = root.Position + Vector3.new(0, 1.5, 0)
	for i = 1, SHARD_COUNT do
		local shard = Instance.new("Part")
		shard.Name = "NAU_Shard"
		shard.Anchored = true
		shard.CanCollide = false
		shard.CanQuery = false
		shard.CanTouch = false
		shard.CastShadow = false
		shard.Material = Enum.Material.Neon
		shard.Color = SHARD_COLOR
		shard.Size = Vector3.new(0.35, 0.35, 0.35)
		shard.CFrame = CFrame.new(origin)
		shard.Parent = workspace.CurrentCamera -- local-only container
		local angle = (i / SHARD_COUNT) * math.pi * 2
		local goal = origin + Vector3.new(math.cos(angle) * 3.5, 2 + math.random() * 2, math.sin(angle) * 3.5)
		TweenService:Create(shard, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(goal) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
			Transparency = 1,
			Size = Vector3.new(0.1, 0.1, 0.1),
		}):Play()
		Debris:AddItem(shard, 0.7)
	end

	task.delay(FADE_DELAY, CharacterFade.run, character, 0, 1, FADE_TIME)
end

return EliminationFX
