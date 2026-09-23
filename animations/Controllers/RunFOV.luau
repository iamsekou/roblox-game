-- "Speed" field of view: while the fighter is actually running the camera widens drastically
-- (approved), and it eases back when they stop. The effect sells the always-sprinting movement.
-- Exponential easing per frame, so it feels the same at any frame rate. Client-only; the camera
-- stays Custom, and the loop only touches FieldOfView.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local RunFOV = {}

export type Config = {
	base: number, -- standing still
	run: number, -- full running
	response: number, -- higher = snappier
	minSpeed: number, -- horizontal studs/second before the run FOV applies
}

local connection: RBXScriptConnection? = nil
local activeConfig: Config? = nil
local running = false

function RunFOV.start(config: Config)
	if connection then
		return
	end
	activeConfig = config
	connection = RunService.RenderStepped:Connect(function(dt)
		local camera = workspace.CurrentCamera
		if not camera or camera.CameraType ~= Enum.CameraType.Custom then
			return
		end
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		-- "Running" = on the ground and moving at speed, whatever is driving the movement. While airborne
		-- the previous state is kept, so a jump mid-run doesn't snap the FOV back.
		if root and humanoid and humanoid.Health > 0 then
			if humanoid.FloorMaterial ~= Enum.Material.Air then
				local v = root.AssemblyLinearVelocity
				running = Vector3.new(v.X, 0, v.Z).Magnitude >= config.minSpeed
			end
		else
			running = false
		end
		local target = if running then config.run else config.base
		local alpha = 1 - math.exp(-config.response * dt)
		camera.FieldOfView += (target - camera.FieldOfView) * alpha
	end)
end

function RunFOV.stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	local camera = workspace.CurrentCamera
	if camera and activeConfig then
		camera.FieldOfView = activeConfig.base
	end
end

return RunFOV
