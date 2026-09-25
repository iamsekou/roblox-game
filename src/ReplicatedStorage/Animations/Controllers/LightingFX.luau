-- Per-area lighting mood (owner, 2026-09-23: lobby rebuild with a lighting pass). Lighting is global,
-- but changes a client makes to it only affect that client, so each player sees the lobby's warm
-- late-afternoon grade while in the lobby and the arena's unchanged look while fighting.
--
-- The lobby preset only nudges what the place already has (Atmosphere, Bloom, SunRays) plus one colour
-- grade of our own. Everything it touches is snapshotted first, and the "Arena" preset is exactly that
-- snapshot, so the approved arena look is restored bit for bit. Sine easing keeps the change soft.
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local LightingFX = {}

local TRANSITION = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local GRADE_NAME = "NAU_LobbyGrade"

-- Keyed by the instance's name under Lighting ("Lighting" = the service itself).
local LOBBY: { [string]: { [string]: any } } = {
	Lighting = {
		ClockTime = 16.8, -- low, warm sun rakes across the colonnades
		Brightness = 2.6,
		Ambient = Color3.fromRGB(62, 56, 54),
		OutdoorAmbient = Color3.fromRGB(124, 114, 104),
		ColorShift_Top = Color3.fromRGB(255, 232, 200),
		EnvironmentDiffuseScale = 0.7,
		EnvironmentSpecularScale = 0.6,
		ExposureCompensation = 0.1,
	},
	Atmosphere = {
		Density = 0.3,
		Offset = 0.1,
		Color = Color3.fromRGB(214, 196, 172),
		Decay = Color3.fromRGB(106, 96, 104),
		Glare = 0.25,
		Haze = 1.4,
	},
	Bloom = { Intensity = 0.5, Size = 28, Threshold = 1.4 },
	SunRays = { Intensity = 0.05, Spread = 0.7 },
	[GRADE_NAME] = {
		Brightness = 0.02,
		Contrast = 0.14,
		Saturation = -0.06,
		TintColor = Color3.fromRGB(255, 244, 232),
	},
}

local snapshot: { [Instance]: { [string]: any } } = {}
local current: string? = nil

local function target(name: string): Instance?
	if name == "Lighting" then
		return Lighting
	end
	return Lighting:FindFirstChild(name)
end

-- Neutral grade: identical to having no colour correction at all.
local function ensureGrade()
	if not Lighting:FindFirstChild(GRADE_NAME) then
		local grade = Instance.new("ColorCorrectionEffect")
		grade.Name = GRADE_NAME
		grade.Brightness = 0
		grade.Contrast = 0
		grade.Saturation = 0
		grade.TintColor = Color3.new(1, 1, 1)
		grade.Parent = Lighting
	end
end

local function takeSnapshot()
	for name, props in LOBBY do
		local instance = target(name)
		if instance then
			local saved = {}
			for prop in props do
				saved[prop] = (instance :: any)[prop]
			end
			snapshot[instance] = saved
		end
	end
end

-- preset: "Lobby" or "Arena". Repeated calls with the same preset do nothing.
function LightingFX.apply(preset: string)
	if preset == current then
		return
	end
	current = preset
	if preset == "Lobby" then
		for name, props in LOBBY do
			local instance = target(name)
			if instance then
				TweenService:Create(instance, TRANSITION, props):Play()
			end
		end
	else
		for instance, props in snapshot do
			if instance.Parent or instance == Lighting then
				TweenService:Create(instance, TRANSITION, props):Play()
			end
		end
	end
end

local started = false
function LightingFX.start(initialPreset: string)
	if started then
		return
	end
	started = true
	ensureGrade()
	takeSnapshot()
	LightingFX.apply(initialPreset)
end

return LightingFX
