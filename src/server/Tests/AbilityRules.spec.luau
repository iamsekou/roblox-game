-- Unit tests for Lib/AbilityRules (cooldowns, availability, hit geometry), using the real Constants.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AbilityRules = require(script.Parent.Parent.Lib.AbilityRules)
local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local T = require(script.Parent.TestUtil)

local MILD, ULT = Constants.MILD_COOLDOWN, Constants.ULTIMATE_COOLDOWN
local READY = { inMatch = true, alive = true, protected = false }

local tests = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

test("[ABIL] both abilities are ready when a fighter enters a match", function()
	local s = AbilityRules.newState(100)
	T.eq(AbilityRules.check(s, "mild", 100, READY), true)
	T.eq(AbilityRules.check(s, "ultimate", 100, READY), true)
end)

test("[ABIL] using an ability starts its cooldown: mild 8 s, ultimate 20 s", function()
	local s = AbilityRules.newState(0)
	AbilityRules.activate(s, "mild", 0, MILD, 0)
	local ok, why = AbilityRules.check(s, "mild", MILD - 0.1, READY)
	T.eq(ok, false)
	T.eq(why, "cooldown")
	T.eq(AbilityRules.check(s, "mild", MILD, READY), true)
	AbilityRules.activate(s, "ultimate", 0, ULT, 0)
	T.eq(select(2, AbilityRules.check(s, "ultimate", ULT - 0.1, READY)), "cooldown")
	T.eq(AbilityRules.check(s, "ultimate", ULT, READY), true)
end)

test("[ABIL] a wind-up blocks starting the other ability until it finishes", function()
	local s = AbilityRules.newState(0)
	AbilityRules.activate(s, "ultimate", 0, ULT, 1.2)
	T.eq(select(2, AbilityRules.check(s, "mild", 1, READY)), "casting")
	T.eq(AbilityRules.check(s, "mild", 1.2, READY), true)
end)

test("[ABIL] dead, protected or out of the match: no abilities", function()
	local s = AbilityRules.newState(0)
	T.eq(select(2, AbilityRules.check(s, "mild", 0, { inMatch = false, alive = true, protected = false })), "not_in_match")
	T.eq(select(2, AbilityRules.check(s, "mild", 0, { inMatch = true, alive = false, protected = false })), "not_alive")
	T.eq(select(2, AbilityRules.check(s, "mild", 0, { inMatch = true, alive = true, protected = true })), "protected")
end)

test("[ABIL] respawn: mild ready, ultimate loses 10 s of its remaining cooldown", function()
	local s = AbilityRules.newState(0)
	AbilityRules.activate(s, "mild", 0, MILD, 0)
	AbilityRules.activate(s, "ultimate", 0, ULT, 1.2)
	AbilityRules.onRespawn(s, 4, Constants.ULTIMATE_RESPAWN_REDUCTION)
	T.eq(AbilityRules.check(s, "mild", 4, READY), true, "mild ready at once")
	T.eq(s.readyAt.ultimate, ULT - Constants.ULTIMATE_RESPAWN_REDUCTION, "ultimate 10 s sooner")
	T.eq(AbilityRules.check(s, "ultimate", 4, READY), false)
end)

test("[ABIL] respawn never pushes a cooldown into the past", function()
	local s = AbilityRules.newState(0)
	AbilityRules.activate(s, "ultimate", 0, ULT, 0)
	AbilityRules.onRespawn(s, 15, Constants.ULTIMATE_RESPAWN_REDUCTION)
	T.eq(s.readyAt.ultimate, 15, "5 s left minus 10 s = ready now, not earlier")
end)

test("[ABIL] beam hits along its length and thickness only", function()
	local origin, dir = Vector3.zero, Vector3.new(0, 0, -1)
	T.eq(AbilityRules.inBeam(origin, dir, 60, 3.5, Vector3.new(0, 0, -30)), true, "on the line")
	T.eq(AbilityRules.inBeam(origin, dir, 60, 3.5, Vector3.new(3, 0, -30)), true, "inside the radius")
	T.eq(AbilityRules.inBeam(origin, dir, 60, 3.5, Vector3.new(4, 0, -30)), false, "outside the radius")
	T.eq(AbilityRules.inBeam(origin, dir, 60, 3.5, Vector3.new(0, 0, -61)), false, "past the end (or a wall)")
	T.eq(AbilityRules.inBeam(origin, dir, 60, 3.5, Vector3.new(0, 0, 2)), false, "behind the caster")
end)

test("[ABIL] cone hits in front within range and angle only", function()
	local origin, dir = Vector3.zero, Vector3.new(0, 0, -1)
	T.eq(AbilityRules.inCone(origin, dir, 15, 50, Vector3.new(0, 0, -10)), true, "straight ahead")
	T.eq(AbilityRules.inCone(origin, dir, 15, 50, Vector3.new(7, 0, -10)), true, "35 degrees off")
	T.eq(AbilityRules.inCone(origin, dir, 15, 50, Vector3.new(10, 0, -5)), false, "63 degrees off")
	T.eq(AbilityRules.inCone(origin, dir, 15, 50, Vector3.new(0, 0, -16)), false, "out of range")
	T.eq(AbilityRules.inCone(origin, dir, 15, 50, Vector3.new(0, 0, 5)), false, "behind")
end)

test("[ABIL] client aim is sanitised: junk falls back, NaN is rejected", function()
	local fallback = Vector3.new(1, 0, 0)
	T.eq(AbilityRules.flatAim("nope", fallback), fallback)
	T.eq(AbilityRules.flatAim(Vector3.new(0, 1, 0), fallback), fallback, "straight up has no heading")
	T.eq(AbilityRules.flatAim(Vector3.new(0 / 0, 0, 0), fallback), fallback, "NaN")
	T.truthy(AbilityRules.flatAim(Vector3.new(0, -0.5, -2), fallback):FuzzyEq(Vector3.new(0, 0, -1)), "flattened and normalised")
	T.eq(AbilityRules.unitAim(Vector3.new(1e6, 0, 0)), nil, "absurd magnitude")
	T.eq(AbilityRules.isSlot("mild"), true)
	T.eq(AbilityRules.isSlot("super"), false)
end)

test("[ABIL] Ichigo's trail: a flat strip along the wave, ignoring height", function()
	local origin, dir = Vector3.zero, Vector3.new(0, 0, -1)
	T.eq(AbilityRules.inStrip(origin, dir, 40, 7, Vector3.new(6, 3, -20)), true, "inside, a little above")
	T.eq(AbilityRules.inStrip(origin, dir, 40, 7, Vector3.new(8, 0, -20)), false, "past the side")
	T.eq(AbilityRules.inStrip(origin, dir, 40, 7, Vector3.new(0, 0, -41)), false, "past the end")
	T.eq(AbilityRules.inStrip(origin, dir, 40, 7, Vector3.new(0, 0, 1)), false, "behind")
end)

test("[ABIL] Hunter's Eye picks the visible opponent closest to the aim, within 15 degrees", function()
	local eyes, aim = Vector3.zero, Vector3.new(0, 0, -1)
	local candidates = {
		{ id = 1, position = Vector3.new(10, 0, -40) }, -- ~14 degrees off
		{ id = 2, position = Vector3.new(2, 0, -150) }, -- far but nearly dead ahead
		{ id = 3, position = Vector3.new(10, 0, -10) }, -- 45 degrees off
	}
	T.eq(AbilityRules.pickByAim(eyes, aim, 15, candidates), 2, "distance doesn't matter, angle does")
	T.eq(AbilityRules.pickByAim(eyes, aim, 15, { candidates[3] }), nil, "nobody within 15 degrees")
end)

test("[ABIL] Hunter's Eye ignores camera pitch (the bug: a level target was never picked)", function()
	local eyes = Vector3.zero
	local lookingDown = Vector3.new(0, -math.sin(math.rad(25)), -math.cos(math.rad(25))) -- typical 3rd-person camera
	local level = { { id = 5, position = Vector3.new(1, 0, -30) } }
	T.eq(AbilityRules.pickByAim(eyes, lookingDown, 15, level), 5)
	T.eq(AbilityRules.pickByAim(eyes, Vector3.new(0, -1, 0), 15, level), nil, "straight down has no heading")
end)

test("[ABIL] Spiral Sphere hits the first opponent along the lunge", function()
	local origin, dir = Vector3.zero, Vector3.new(0, 0, -1)
	local candidates = {
		{ id = 1, position = Vector3.new(1, 0, -15) },
		{ id = 2, position = Vector3.new(-2, 0, -6) },
		{ id = 3, position = Vector3.new(9, 0, -3) }, -- off the path
	}
	local id, along = AbilityRules.firstAlong(origin, dir, 20, 4, candidates)
	T.eq(id, 2)
	T.eq(along, 6)
	T.eq(AbilityRules.firstAlong(origin, dir, 20, 4, { candidates[3] }), nil)
end)
return tests
