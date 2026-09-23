-- Client-only screen shake driven through Humanoid.CameraOffset, so the default camera keeps working
-- (no Scriptable camera to forget to restore). A new shake while one is running refreshes it.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CameraShake = {}

local connection: RBXScriptConnection? = nil
local endsAt, duration, intensity = 0, 0, 0

local function humanoid(): Humanoid?
	local character = Players.LocalPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

-- strength: max offset in studs; length: seconds. Amplitude decays linearly to zero.
function CameraShake.shake(strength: number?, length: number?)
	intensity = strength or 0.6
	duration = length or 0.35
	endsAt = os.clock() + duration
	if connection then
		return
	end
	connection = RunService.RenderStepped:Connect(function()
		local hum = humanoid()
		local remaining = endsAt - os.clock()
		if remaining <= 0 or not hum then
			if hum then
				hum.CameraOffset = Vector3.zero
			end
			if connection then
				connection:Disconnect()
				connection = nil
			end
			return
		end
		local amplitude = intensity * (remaining / duration)
		hum.CameraOffset = Vector3.new((math.random() * 2 - 1) * amplitude, (math.random() * 2 - 1) * amplitude, 0)
	end)
end

return CameraShake
