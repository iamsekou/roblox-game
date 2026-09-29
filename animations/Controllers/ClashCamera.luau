-- The M1 clash cutscene (owner request 2026-09-25: "like Saitama vs Boros constantly punching each other").
-- Only the two fighters in the clash see it; everyone else watches with their normal camera.
-- Three shots across the clash, blended smoothly into each other:
--   1. wide side-on shot of both fighters, pushing in (the first beat of the exchange)
--   2. low angle orbiting round the two of them
--   3. tight over our own shoulder onto the opponent, getting shakier as it builds
-- Cinema bars slide in for the cutscene. The shot tracks both fighters live, so a knockback at the end
-- never leaves the camera behind; stop() hands the camera straight back to Roblox.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Constants"))

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

-- The clash duel camera (owner request 2026-09-29: "make the camera change angles like an intense scene and be
-- extremely animated"; only the two fighters get it). By phase, from the server's times:
--   lift     low angle looking up as the pair rises, pulling round
--   slow     a tight side shot on the fists, tilted, pushing in slowly until they meet
--   barrage  hard cuts between angles (over either shoulder, the fists, below, above, orbiting, wide) every
--            0.4-0.9 s, cutting faster as the duel speeds up; every typed digit kicks the lens (duelBeat)
--   final    duelFinal(): on the winner's fist as it winds up, then a hard cut wide as the blast goes off
-- Everything follows the two fighters live. stop() hands the camera back to Roblox.
local duelState: {
	beats: number, -- digits typed so far (both fighters): the cuts get faster
	kick: number, -- the lens kick from the last digit, decaying (1 = just landed)
	cutAt: number,
	shot: number,
	shotStarted: number,
	final: { winner: Model?, loser: Model?, finalAt: number }?,
}? = nil

local SHOTS = 8

-- Shot `n` for the barrage: (camera position, look-at, field of view, roll in degrees). `t` = seconds into it.
local function barrageShot(n: number, t: number, me: Vector3, them: Vector3): (Vector3, Vector3, number, number)
	local flat = Vector3.new(them.X - me.X, 0, them.Z - me.Z)
	local axis = if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(0, 0, -1)
	local side = axis:Cross(UP).Unit
	local mid = (me + them) / 2 + UP * 0.6
	if n == 1 then -- over our shoulder onto them
		return me - axis * 4.4 + side * 2.3 + UP * 1.9 + side * t * 0.6, them + UP * 0.8, 44, -4
	elseif n == 2 then -- over their shoulder onto us
		return them + axis * 4.4 - side * 2.3 + UP * 1.9 - side * t * 0.6, me + UP * 0.8, 44, 4
	elseif n == 3 then -- extreme close-up on the fists
		return mid + side * (3.4 - t * 0.8) + UP * 0.2, mid, 30, 10
	elseif n == 4 then -- worm's-eye, looking up at the pair against the sky
		return mid + side * 5 - UP * (5 - t), mid + UP * 1.2, 72, 0
	elseif n == 5 then -- straight down from above, spinning
		local a = t * 1.6
		return mid + UP * 15 + (side * math.cos(a) + axis * math.sin(a)) * 0.5, mid, 58, 0
	elseif n == 6 then -- fast orbit
		local a = t * 2.4
		return mid + (side * math.cos(a) + axis * math.sin(a)) * 9 + UP * 1.5, mid, 60, 0
	elseif n == 7 then -- wide: the whole force field, dollying in
		return mid + side * (20 - t * 6) + UP * 4, mid, 50, 0
	end
	-- 8: dutch angle behind us
	return me - axis * 6 - side * 1.5 + UP * 3, them, 52, 18
end

-- Play the duel cutscene against `partner` (user id or model). `times` = the server's { startAt, slowAt,
-- barrageAt }. Runs until stop() (the duel's end, after duelFinal's blast shot).
function ClashCamera.playDuel(partner: any, times: { startAt: number, slowAt: number, barrageAt: number })
	ClashCamera.stop()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local previousType = camera.CameraType
	local previousFov = camera.FieldOfView
	local gui, top, bottom = makeBars()
	local barsIn = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(top, barsIn, { Size = UDim2.fromScale(1, BAR_HEIGHT) }):Play()
	TweenService:Create(bottom, barsIn, { Size = UDim2.fromScale(1, BAR_HEIGHT) }):Play()
	camera.CameraType = Enum.CameraType.Scriptable
	local rng = Random.new()
	local current = camera.CFrame
	local fovNow = camera.FieldOfView
	duelState = { beats = 0, kick = 0, cutAt = 0, shot = 1, shotStarted = os.clock(), final = nil }

	local handle
	local function stop()
		if active ~= handle then
			return
		end
		active = nil
		duelState = nil
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
		local state = duelState
		local mine, theirs = rootOf(localPlayer.Character), rootOf(partner)
		if not state or not mine or not theirs then
			stop()
			return
		end
		local me, them = mine.Position, theirs.Position
		local flat = Vector3.new(them.X - me.X, 0, them.Z - me.Z)
		local axis = if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(0, 0, -1)
		local side = axis:Cross(UP).Unit
		local mid = (me + them) / 2 + UP * 0.6
		local serverNow = workspace:GetServerTimeNow()
		local clock = os.clock()
		local at, look, fov, roll, shake
		local hardCut = false
		local final = state.final
		if final then
			local winnerRoot, loserRoot = rootOf(final.winner), rootOf(final.loser)
			local w = if winnerRoot then winnerRoot.Position else me
			local l = if loserRoot then loserRoot.Position else them
			local dir = Vector3.new(l.X - w.X, 0, l.Z - w.Z)
			dir = if dir.Magnitude > 0.05 then dir.Unit else axis
			local wside = dir:Cross(UP).Unit
			if serverNow < final.finalAt then
				-- On the winner's fist, slowly creeping in: the moment before the blow.
				local u = 1 - math.clamp((final.finalAt - serverNow) / Constants.CLASH_FINAL_WINDUP, 0, 1)
				at = w + dir * 1.5 + wside * (3.2 - u) - UP * 0.4
				look = w + dir * 2 + UP * 0.6
				fov, roll, shake = 34 - 6 * u, -12, 0.05 + 0.1 * u
			else
				-- The blast: cut wide and pull back hard, shaking.
				local u = math.clamp(serverNow - final.finalAt, 0, 1.5)
				if state.shot ~= -1 then
					state.shot = -1
					hardCut = true
				end
				at = mid + wside * (12 + u * 16) + UP * (4 + u * 5) - dir * 4
				look = mid + dir * u * 6
				fov, roll, shake = 70, 0, math.max(0, 0.9 - u * 0.5)
			end
		elseif serverNow < times.slowAt then
			-- Lift: low, looking up as they rise, swinging round.
			local u = math.clamp((serverNow - times.startAt) / math.max(times.slowAt - times.startAt, 0.01), 0, 1)
			local angle = math.rad(-40 + 70 * u)
			local dir = side * math.cos(angle) - axis * math.sin(angle)
			at = mid + dir * (12 - 3 * u) - UP * (4 - 2 * u)
			look = mid + UP * 0.5
			fov, roll, shake = 70 - 12 * u, 0, 0.12
		elseif serverNow < times.barrageAt then
			-- Slow punch: tight on the fists, tilted, pushing in.
			local u = math.clamp((serverNow - times.slowAt) / math.max(times.barrageAt - times.slowAt, 0.01), 0, 1)
			if state.shot ~= 0 then
				state.shot = 0
				hardCut = true
			end
			at = mid + side * (6 - 3 * u) + UP * (0.4 - 0.3 * u)
			look = mid
			fov, roll, shake = 38 - 10 * u, 9, 0.02 + 0.05 * u
		else
			-- Barrage: hard cuts, faster as the duel goes on.
			if state.shot < 1 or clock >= state.cutAt then
				local next = state.shot
				while next == state.shot or next < 1 do
					next = rng:NextInteger(1, SHOTS)
				end
				state.shot = next
				state.shotStarted = clock
				state.cutAt = clock + math.max(0.4, 0.9 - state.beats * 0.03) * rng:NextNumber(0.85, 1.15)
				hardCut = true
			end
			at, look, fov, roll = barrageShot(state.shot, clock - state.shotStarted, me, them)
			shake = 0.12 + math.min(state.beats * 0.012, 0.25)
		end
		local target = CFrame.lookAt(at, look) * CFrame.Angles(0, 0, math.rad(roll))
		local jitter = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * shake
		target = target + jitter
		if hardCut then
			current = target
			fovNow = fov
		else
			current = current:Lerp(target, 1 - math.exp(-16 * dt))
			fovNow += (fov - fovNow) * (1 - math.exp(-10 * dt))
		end
		camera.CFrame = current
		-- Every digit typed kicks the lens in, easing back out.
		camera.FieldOfView = math.clamp(fovNow - state.kick * 10, 20, 90)
		state.kick *= math.exp(-12 * dt)
	end)
end

-- A digit landed (ours or theirs): kick the lens, and cut sooner.
function ClashCamera.duelBeat()
	local state = duelState
	if state then
		state.beats += 1
		state.kick = 1
		state.cutAt = math.min(state.cutAt, os.clock() + 0.12)
	end
end

-- The duel is decided: the final shots (on the winner's fist, then the blast).
function ClashCamera.duelFinal(winner: Model?, loser: Model?, finalAt: number)
	local state = duelState
	if state then
		state.final = { winner = winner, loser = loser, finalAt = finalAt }
	end
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
