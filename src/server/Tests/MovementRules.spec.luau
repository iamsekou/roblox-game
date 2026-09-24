-- Unit tests for Lib/MovementRules (the movement sanity check).
local MovementRules = require(script.Parent.Parent.Lib.MovementRules)
local T = require(script.Parent.TestUtil)

local LIMITS = { speed = 32, rise = 60, burst = 1, slack = 6 } -- walk 24 x 1.35 margin, roughly

local tests = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

local function walk(state, from: Vector3, direction: Vector3, speed: number, seconds: number, t0: number, limits): boolean
	local ok = true
	local steps = math.floor(seconds / 0.1)
	for i = 1, steps do
		local good = MovementRules.step(state, from + direction * speed * 0.1 * i, t0 + 0.1 * i, limits)
		ok = ok and good
	end
	return ok
end

test("[MOVE] running at walk speed for a long time is fine", function()
	local s = MovementRules.new(Vector3.zero, 0, LIMITS)
	T.eq(walk(s, Vector3.zero, Vector3.xAxis, 24, 30, 0, LIMITS), true)
end)

test("[MOVE] sustained over-speed is caught", function()
	local s = MovementRules.new(Vector3.zero, 0, LIMITS)
	T.eq(walk(s, Vector3.zero, Vector3.xAxis, 60, 3, 0, LIMITS), false, "60 studs/s with 32 allowed")
end)

test("[MOVE] a teleport is caught and the last good position is kept", function()
	local s = MovementRules.new(Vector3.zero, 0, LIMITS)
	MovementRules.step(s, Vector3.new(2, 0, 0), 0.1, LIMITS)
	local ok = MovementRules.step(s, Vector3.new(80, 0, 0), 0.2, LIMITS)
	T.eq(ok, false)
	T.eq(s.last, Vector3.new(2, 0, 0), "state unchanged")
end)

test("[MOVE] a lag clump passes: late positions arrive all at once", function()
	local s = MovementRules.new(Vector3.zero, 0, LIMITS)
	-- Nothing for 0.8 s while running at 24, then the whole stretch arrives in one update.
	T.eq(MovementRules.step(s, Vector3.new(19.2, 0, 0), 0.8, LIMITS), true)
end)

test("[MOVE] falling is never limited; rising is", function()
	local s = MovementRules.new(Vector3.new(0, 100, 0), 0, LIMITS)
	T.eq(MovementRules.step(s, Vector3.new(0, 10, 0), 0.5, LIMITS), true, "a 90-stud drop")
	T.eq(MovementRules.step(s, Vector3.new(0, 17, 0), 0.6, LIMITS), true, "a jump back up")
	local fly = MovementRules.new(Vector3.zero, 0, LIMITS)
	T.eq(MovementRules.step(fly, Vector3.new(0, 90, 0), 0.5, LIMITS), false, "flying straight up")
end)

test("[MOVE] a game-granted burst (grapple, knockback) raises the limit, then it lapses", function()
	local grants = { { speed = 120, rise = 120, untilTime = 1 } }
	local during = MovementRules.limits(24, 1.35, 60, grants, 0.5, 1, 6)
	T.eq(during.speed, 120)
	local after = MovementRules.limits(24, 1.35, 60, grants, 1.5, 1, 6)
	T.truthy(math.abs(after.speed - 32.4) < 1e-6, "back to walk speed x margin")
	local s = MovementRules.new(Vector3.zero, 0, during)
	-- A 45-stud grapple at 120 studs/s.
	T.eq(walk(s, Vector3.zero, Vector3.zAxis, 120, 0.4, 0, during), true)
end)

test("[MOVE] a server teleport resets the baseline", function()
	local s = MovementRules.new(Vector3.zero, 0, LIMITS)
	MovementRules.reset(s, Vector3.new(500, 0, 0), 1, LIMITS)
	T.eq(MovementRules.step(s, Vector3.new(502, 0, 0), 1.1, LIMITS), true)
end)

return tests
