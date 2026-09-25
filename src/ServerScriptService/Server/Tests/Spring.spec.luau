-- Unit tests for Shared/Modules/Spring (the damped spring that smooths placeholder ability poses).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Spring = require(ReplicatedStorage.Shared.Modules.Spring)
local T = require(script.Parent.TestUtil)

local tests = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

-- Runs the spring from 0 to 1 for `seconds` at 60 fps; returns the final position and the peak reached.
local function run(frequency: number, damping: number, seconds: number, fps: number?): (number, number)
	local x, v, peak = 0, 0, 0
	local dt = 1 / (fps or 60)
	for _ = 1, math.floor(seconds / dt + 0.5) do
		x, v = Spring.step(x, v, 1, frequency, damping, dt)
		peak = math.max(peak, x)
	end
	return x, peak
end

test("[SPRING] settles on its target", function()
	local x = run(6, 0.6, 1.5)
	T.truthy(math.abs(x - 1) < 1e-3, "ends within 0.001 of the target, got " .. x)
end)

test("[SPRING] critically damped never overshoots; underdamped overshoots a little", function()
	local _, peak = run(6, 1, 1)
	T.truthy(peak <= 1 + 1e-6, "damping 1 peaked at " .. peak)
	local _, softPeak = run(6, 0.6, 1)
	T.truthy(softPeak > 1.05 and softPeak < 1.15, "damping 0.6 should overshoot ~9 %, peaked at " .. softPeak)
end)

test("[SPRING] responds quickly: a 6 Hz joint is most of the way there in a tenth of a second", function()
	local x = run(6, 0.6, 0.1)
	T.truthy(x > 0.6, "at 0.1 s it's only at " .. x)
end)

test("[SPRING] barely depends on the frame rate", function()
	local at30 = run(8, 0.55, 0.4, 30)
	local at240 = run(8, 0.55, 0.4, 240)
	T.truthy(math.abs(at30 - at240) < 0.02, string.format("30 fps %.4f vs 240 fps %.4f", at30, at240))
end)

test("[SPRING] zero time changes nothing; works on Vector3s", function()
	local x, v = Spring.step(0.3, 2, 1, 6, 0.6, 0)
	T.eq(x, 0.3)
	T.eq(v, 2)
	local p = Vector3.zero
	local vel = Vector3.zero
	for _ = 1, 120 do
		p, vel = Spring.step(p, vel, Vector3.new(10, -20, 30), 6, 0.7, 1 / 60)
	end
	T.truthy((p - Vector3.new(10, -20, 30)).Magnitude < 1e-2, "Vector3 spring settled at " .. tostring(p))
end)

test("[SPRING] nearest angle takes the short way round", function()
	T.eq(Spring.nearestAngle(-310, 0), -360)
	T.eq(Spring.nearestAngle(10, 350), -10)
	T.eq(Spring.nearestAngle(170, -170), 190)
	T.eq(Spring.nearestAngle(0, 45), 45)
end)

return tests
