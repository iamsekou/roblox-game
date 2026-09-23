-- Idle motion for the lobby FIGHT portal: the glow "breathes" and its light pulses, so the portal
-- reads as the lobby's call to action from anywhere on the island. Sine in/out suits a slow, calm pulse.
local TweenService = game:GetService("TweenService")

local PortalFX = {}

-- Returns a stop function.
function PortalFX.start(portal: Model): () -> ()
	local glow = portal:FindFirstChild("PortalGlow", true)
	if not glow or not glow:IsA("BasePart") then
		return function() end
	end
	local info = TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tweens = { TweenService:Create(glow, info, { Transparency = 0.55 }) }
	local light = glow:FindFirstChildOfClass("PointLight")
	if light then
		table.insert(tweens, TweenService:Create(light, info, { Brightness = light.Brightness * 0.35 }))
	end
	for _, tween in tweens do
		tween:Play()
	end
	return function()
		for _, tween in tweens do
			tween:Cancel()
		end
	end
end

return PortalFX
