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

test("[MOVE] a dash allows extra travel only along the dash", function()
	-- A 30-stud dash along +X. Along it: fine. The same distance sideways (onto someone's front): caught.
	local along = MovementRules.new(Vector3.zero, 0, LIMITS)
	local path = MovementRules.path(Vector3.xAxis, 30, 1) :: MovementRules.Path
	local ok, _, _, charged = MovementRules.step(along, Vector3.new(30, 0, 0), 0.1, LIMITS, { path })
	T.eq(ok, true, "along the dash")
	T.truthy(charged < 1e-6, "none of it is walking")
	local sideways = MovementRules.new(Vector3.zero, 0, LIMITS)
	local path2 = MovementRules.path(Vector3.xAxis, 30, 1) :: MovementRules.Path
	T.eq(MovementRules.step(sideways, Vector3.new(0, 0, 30), 0.1, LIMITS, { path2 }), false, "sideways")
	local backwards = MovementRules.new(Vector3.zero, 0, LIMITS)
	local path3 = MovementRules.path(Vector3.xAxis, 30, 1) :: MovementRules.Path
	T.eq(MovementRules.step(backwards, Vector3.new(-30, 0, 0), 0.1, LIMITS, { path3 }), false, "backwards")
end)

test("[MOVE] a path is spent as it's used and lapses on time", function()
	local s = MovementRules.new(Vector3.zero, 0, LIMITS)
	local path = MovementRules.path(Vector3.xAxis, 30, 1) :: MovementRules.Path
	T.eq(MovementRules.step(s, Vector3.new(30, 0, 0), 0.1, LIMITS, { path }), true)
	T.truthy(path.left < 1e-6, "used up")
	T.eq(MovementRules.step(s, Vector3.new(60, 0, 0), 0.2, LIMITS, { path }), false, "a second dash on the same allowance")
	-- 45 studs: more than a full walking budget (38), so only a live path could explain it.
	local late = MovementRules.new(Vector3.zero, 0, LIMITS)
	local expired = MovementRules.path(Vector3.xAxis, 45, 1) :: MovementRules.Path
	T.eq(MovementRules.step(late, Vector3.new(45, 0, 0), 1.1, LIMITS, { expired }), false, "after it lapsed")
end)

test("[MOVE] a rejected step doesn't spend the path", function()
	local s = MovementRules.new(Vector3.zero, 0, LIMITS)
	local path = MovementRules.path(Vector3.xAxis, 30, 1) :: MovementRules.Path
	T.eq(MovementRules.step(s, Vector3.new(30, 0, 40), 0.1, LIMITS, { path }), false, "too far sideways")
	T.eq(path.left, 30)
end)

test("[MOVE] NaN and infinite positions are rejected and never poison the budget", function()
	local s = MovementRules.new(Vector3.zero, 0, LIMITS)
	local nan = 0 / 0
	T.eq(MovementRules.step(s, Vector3.new(nan, 0, 0), 0.1, LIMITS), false, "NaN")
	T.eq(MovementRules.step(s, Vector3.new(math.huge, 0, 0), 0.2, LIMITS), false, "infinite")
	T.eq(s.flat == s.flat, true, "budget still a number")
	T.eq(MovementRules.step(s, Vector3.new(80, 0, 0), 0.3, LIMITS), false, "a teleport right after is still caught")
	T.eq(MovementRules.step(s, Vector3.new(3, 0, 0), 0.4, LIMITS), true, "normal running still passes")
	T.eq(MovementRules.path(Vector3.new(nan, 0, 0), 10, 1), nil, "no path from a NaN direction")
	T.eq(MovementRules.path(Vector3.yAxis, 10, 1), nil, "no path straight up")
end)

return tests
