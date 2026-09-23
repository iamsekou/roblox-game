-- Unit tests for Lib/ClashRules (who clashes with whom, and where they stand).
local ClashRules = require(script.Parent.Parent.Lib.ClashRules)
local T = require(script.Parent.TestUtil)

local PARAMS = { window = 0.6, range = 30, facingDegrees = 35 }
local EAST, WEST = Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0)

local function cast(id: number, key: string, t: number, x: number, aim: Vector3, windup: number?)
	return { id = id, key = key, t = t, windup = windup or 1.2, position = Vector3.new(x, 3, 0), aim = aim }
end

local tests = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

test("[CLASH] same ability, aimed at each other, close in time and space: clash", function()
	local s = ClashRules.new()
	T.eq(ClashRules.offer(s, cast(1, "Goku.ultimate", 0, 0, EAST), PARAMS), nil, "first cast waits")
	local partner = ClashRules.offer(s, cast(2, "Goku.ultimate", 0.4, 20, WEST), PARAMS)
	T.truthy(partner and partner.id == 1, "second cast clashes with the first")
	T.eq(#s.pending, 0, "both leave the pending list")
end)

test("[CLASH] different abilities never clash", function()
	local s = ClashRules.new()
	ClashRules.offer(s, cast(1, "Goku.ultimate", 0, 0, EAST), PARAMS)
	T.eq(ClashRules.offer(s, cast(2, "Vegeta.ultimate", 0.2, 20, WEST), PARAMS), nil)
end)

test("[CLASH] abilities off the clash list never clash, even mirrored", function()
	local s = ClashRules.new()
	T.eq(ClashRules.offer(s, cast(1, "Goku.mild", 0, 0, EAST), PARAMS), nil)
	T.eq(ClashRules.offer(s, cast(2, "Goku.mild", 0.1, 10, WEST), PARAMS), nil)
	T.eq(#s.pending, 0, "non-clashable casts are never kept")
end)

test("[CLASH] too late: outside the window, or after the first one already fired", function()
	local s = ClashRules.new()
	ClashRules.offer(s, cast(1, "Goku.ultimate", 0, 0, EAST), PARAMS)
	T.eq(ClashRules.offer(s, cast(2, "Goku.ultimate", 0.7, 20, WEST), PARAMS), nil, "0.7 s > 0.6 s window")
	local s2 = ClashRules.new()
	ClashRules.offer(s2, cast(1, "Sasuke.mild", 0, 0, EAST, 0.3), PARAMS)
	T.eq(ClashRules.offer(s2, cast(2, "Sasuke.mild", 0.45, 20, WEST, 0.3), PARAMS), nil, "a 0.3 s dash already fired")
	local s3 = ClashRules.new()
	ClashRules.offer(s3, cast(1, "Sasuke.mild", 0, 0, EAST, 0.3), PARAMS)
	T.truthy(ClashRules.offer(s3, cast(2, "Sasuke.mild", 0.25, 20, WEST, 0.3), PARAMS), "still in its 0.3 s tell")
end)

test("[CLASH] too far apart, or not aiming at each other", function()
	local s = ClashRules.new()
	ClashRules.offer(s, cast(1, "Zoro.ultimate", 0, 0, EAST), PARAMS)
	T.eq(ClashRules.offer(s, cast(2, "Zoro.ultimate", 0.1, 31, WEST), PARAMS), nil, "31 studs > 30")
	local s2 = ClashRules.new()
	ClashRules.offer(s2, cast(1, "Zoro.ultimate", 0, 0, EAST), PARAMS)
	T.eq(ClashRules.offer(s2, cast(2, "Zoro.ultimate", 0.1, 20, EAST), PARAMS), nil, "second faces away")
	local s3 = ClashRules.new()
	ClashRules.offer(s3, cast(1, "Zoro.ultimate", 0, 0, Vector3.new(0, 0, 1)), PARAMS)
	T.eq(ClashRules.offer(s3, cast(2, "Zoro.ultimate", 0.1, 20, WEST), PARAMS), nil, "first aims elsewhere")
end)

test("[CLASH] the facing cone is inclusive at its edge and ignores height", function()
	local aim = CFrame.Angles(0, math.rad(34), 0).LookVector
	T.eq(ClashRules.aimsAt(Vector3.zero, aim, Vector3.new(0, 50, -10), 35), true, "34 deg off, target far above")
	local wide = CFrame.Angles(0, math.rad(40), 0).LookVector
	T.eq(ClashRules.aimsAt(Vector3.zero, wide, Vector3.new(0, 0, -10), 35), false, "40 deg off")
end)

test("[CLASH] nobody joins a clash already in progress; it frees up afterwards", function()
	local s = ClashRules.new()
	ClashRules.offer(s, cast(1, "Goku.ultimate", 0, 0, EAST), PARAMS)
	ClashRules.offer(s, cast(2, "Goku.ultimate", 0.1, 20, WEST), PARAMS)
	ClashRules.begin(s, 1, 2)
	T.eq(ClashRules.isClashing(s, 1), true)
	T.eq(ClashRules.offer(s, cast(3, "Goku.ultimate", 0.2, 10, WEST), PARAMS), nil, "3 finds no free partner")
	T.eq(ClashRules.offer(s, cast(1, "Goku.ultimate", 0.3, 0, EAST), PARAMS), nil, "a clashing fighter can't start another")
	ClashRules.finish(s, 1, 2)
	T.eq(ClashRules.isClashing(s, 1), false)
end)

test("[CLASH] with two candidates, the nearest one clashes", function()
	local s = ClashRules.new()
	ClashRules.offer(s, cast(1, "Naruto.ultimate", 0, 25, WEST), PARAMS)
	ClashRules.offer(s, cast(2, "Naruto.ultimate", 0.05, 10, WEST), PARAMS)
	local partner = ClashRules.offer(s, cast(3, "Naruto.ultimate", 0.1, 0, EAST), PARAMS)
	T.truthy(partner and partner.id == 2, "picks the one 10 studs away")
	T.eq(#s.pending, 1, "the other stays pending")
end)

test("[CLASH] stances: face to face, the given distance apart around the midpoint, heights kept", function()
	local a, b, axis = ClashRules.stances(Vector3.new(0, 3, 0), Vector3.new(20, 5, 0), 7)
	T.truthy((a - Vector3.new(6.5, 3, 0)).Magnitude < 1e-6, "A at midpoint - 3.5")
	T.truthy((b - Vector3.new(13.5, 5, 0)).Magnitude < 1e-6, "B at midpoint + 3.5")
	T.truthy((axis - EAST).Magnitude < 1e-6, "axis from A to B")
end)

return tests
