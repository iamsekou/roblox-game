-- The M1 clash cutscene (owner request 2026-09-25: "like Saitama vs Boros constantly punching each other").
-- Only the two fighters in the clash see it; everyone else watches with their normal camera.
-- Three shots across the clash, blended smoothly into each other:
--   1. wide side-on shot of both fighters, pushing in (the first beat of the exchange)
--   2. low angle orbiting round the two of them
--   3. tight over our own shoulder onto the opponent, getting shakier as it builds
-- Cinema bars slide in for the cutscene. The shot tracks both fighters live, so a knockback at the end
-- never leaves the camera behind; stop() hands the camera straight back to Roblox.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ClashCamera = {}

local BIND_NAME = "NAU_ClashCamera"
local BAR_HEIGHT = 0.11 -- share of the screen each cinema bar covers
local UP = Vector3.yAxis

local localPlayer = Players.LocalPlayer
local active: { stop: () -> () }? = nil

local function rootOf(who: any): BasePart?
	local character = if typeof(who) == "Instance" and who:IsA("Model") then who
		else (function()
			local player = if type(who) == "number" then Players:GetPlayerByUserId(who) else nil
			return player and player.Character
		end)()
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Where the camera sits and looks, `u` (0..1) of the way through the clash.
local function shot(u: number, me: Vector3, them: Vector3): (Vector3, Vector3, number, number)
	local flat = Vector3.new(them.X - me.X, 0, them.Z - me.Z)
	local axis = if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(0, 0, -1)
	local side = axis:Cross(UP).Unit
	local mid = (me + them) / 2 + UP * 0.6

	-- 1: side on, pushing in.
	local k1 = smooth(u / 0.33)
	local wideAt = mid + side * (15 - 5 * k1) + UP * (2.5 - 0.8 * k1)

	-- 2: low orbit, a quarter turn from the side toward our back.
	local k2 = smooth((u - 0.33) / 0.34)
	local angle = math.rad(-70 * k2)
	local orbitDir = (side * math.cos(angle) - axis * math.sin(angle))
	local orbitAt = mid + orbitDir * 9 + UP * 0.2

	-- 3: over our shoulder onto them.
	local shoulderAt = me - axis * 4.2 + side * 2.2 + UP * 2.1
	local shoulderLook = them + UP * 0.9

	local b12 = smooth((u - 0.28) / 0.1) -- blend shot 1 -> 2
	local b23 = smooth((u - 0.64) / 0.1) -- blend shot 2 -> 3
	local at = wideAt:Lerp(orbitAt, b12):Lerp(shoulderAt, b23)
	local look = mid:Lerp(shoulderLook, b23)
	local fov = (58 - 8 * k1) + (46 - (58 - 8 * k1)) * b12
	fov = fov + (40 - fov) * b23
	local shake = 0.08 + 0.1 * b12 + 0.22 * b23 -- builds toward the break
	return at, look, fov, shake
end

local function makeBars(): (ScreenGui, Frame, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = "NAU_ClashBars"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	local function bar(anchorY: number): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0, anchorY)
		f.Position = UDim2.fromScale(0, anchorY)
		f.Size = UDim2.fromScale(1, 0)
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BorderSizePixel = 0
		f.Parent = gui
		return f
	end
	local top, bottom = bar(0), bar(1)
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	return gui, top, bottom
end

-- Play the cutscene against `partner` (user id, or a model for solo tests) until `seconds` have passed.
function ClashCamera.play(partner: any, seconds: number)
	ClashCamera.stop()
	local camera = workspace.CurrentCamera
	if not camera or seconds <= 0 then
		return
	end
	local previousType = camera.CameraType
	local previousFov = camera.FieldOfView
	local started = os.clock()
	local gui, top, bottom = makeBars()
	local barsIn = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(top, barsIn, { Size = UDim2.fromScale(1, BAR_HEIGHT) }):Play()
	TweenService:Create(bottom, barsIn, { Size = UDim2.fromScale(1, BAR_HEIGHT) }):Play()
	camera.CameraType = Enum.CameraType.Scriptable
	local rng = Random.new()
	local current = camera.CFrame

	local handle
	local function stop()
		if active ~= handle then
			return
		end
		active = nil
		pcall(RunService.UnbindFromRenderStep, RunService, BIND_NAME)
		if camera.Parent then
			camera.CameraType = if previousType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else previousType
			camera.FieldOfView = previousFov
		end
		local barsOut = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(top, barsOut, { Size = UDim2.fromScale(1, 0) }):Play()
		local last = TweenService:Create(bottom, barsOut, { Size = UDim2.fromScale(1, 0) })
		last.Completed:Connect(function()
			gui:Destroy()
		end)
		last:Play()
	end
	handle = { stop = stop }
	active = handle

	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Last.Value, function(dt)
		local elapsed = os.clock() - started
		local mine, theirs = rootOf(localPlayer.Character), rootOf(partner)
		if elapsed >= seconds or not mine or not theirs then
			stop()
			return
		end
		local at, look, fov, shake = shot(elapsed / seconds, mine.Position, theirs.Position)
		local jitter = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * shake
		local target = CFrame.lookAt(at + jitter, look)
		-- Ease toward the shot so the cuts between framings glide rather than pop.
		local alpha = if elapsed < 0.05 then 1 else 1 - math.exp(-14 * dt)
		current = current:Lerp(target, alpha)
		camera.CFrame = current
		camera.FieldOfView = fov
	end)
end

function ClashCamera.stop()
	if active then
		active.stop()
	end
end

function ClashCamera.isPlaying(): boolean
	return active ~= nil
end

return ClashCamera
