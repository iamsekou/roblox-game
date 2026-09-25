-- Client-only screen shake driven through Humanoid.CameraOffset, so the default camera keeps working
-- (no Scriptable camera to forget to restore). A new shake while one is running refreshes it.
-- Player setting (Phase 4): with screen shake off, the same call flashes the screen edges red instead, so
-- the signal (e.g. a wrong code) is never lost.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CameraShake = {}

local FLASH_COLOR = Color3.fromRGB(220, 60, 50)
local FLASH_OPACITY_PER_STUD = 0.5 -- edge opacity per stud of shake strength (capped below)
local FLASH_MAX_OPACITY = 0.55

local connection: RBXScriptConnection? = nil
local endsAt, duration, intensity = 0, 0, 0
local enabled = true
local flashBands: { Frame } = {}

local function humanoid(): Humanoid?
	local character = Players.LocalPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

function CameraShake.setEnabled(on: boolean)
	enabled = on
end

local function ensureFlash()
	if #flashBands > 0 and flashBands[1].Parent then
		return
	end
	table.clear(flashBands)
	local gui = Instance.new("ScreenGui")
	gui.Name = "NAU_EdgeFlash"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.DisplayOrder = 2
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	-- Four bands fading toward the centre (the same shape as the sprint vignette).
	for _, spec in {
		{ UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.2), 90 },
		{ UDim2.fromScale(0, 0.8), UDim2.fromScale(1, 0.2), -90 },
		{ UDim2.fromScale(0, 0), UDim2.fromScale(0.15, 1), 0 },
		{ UDim2.fromScale(0.85, 0), UDim2.fromScale(0.15, 1), 180 },
	} do
		local band = Instance.new("Frame")
		band.Position = spec[1]
		band.Size = spec[2]
		band.BorderSizePixel = 0
		band.BackgroundColor3 = FLASH_COLOR
		band.BackgroundTransparency = 1
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = spec[3]
		gradient.Transparency = NumberSequence.new(0, 1)
		gradient.Parent = band
		band.Parent = gui
		table.insert(flashBands, band)
	end
end

local function flash(strength: number, length: number)
	ensureFlash()
	local opacity = math.min(FLASH_MAX_OPACITY, strength * FLASH_OPACITY_PER_STUD)
	for _, band in flashBands do
		band.BackgroundTransparency = 1 - opacity
		TweenService:Create(band, TweenInfo.new(length, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	end
end

-- strength: max offset in studs; length: seconds. Amplitude decays linearly to zero.
function CameraShake.shake(strength: number?, length: number?)
	if not enabled then
		flash(strength or 0.6, length or 0.35)
		return
	end
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
