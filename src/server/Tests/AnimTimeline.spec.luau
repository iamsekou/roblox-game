-- Unit tests for Shared/Modules/AnimTimeline (phases and blend weights of an ability cast animation).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimTimeline = require(ReplicatedStorage.Shared.Modules.AnimTimeline)
local T = require(script.Parent.TestUtil)

local TIMING = { windup = 1, hold = 0.5, blendIn = 0.1, snap = 0.1, blendOut = 0.25 }

local function near(actual: number, expected: number, message: string?)
	T.truthy(math.abs(actual - expected) < 1e-6, string.format("%sexpected %s, got %s", if message then message .. ": " else "", tostring(expected), tostring(actual)))
end

local tests = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

test("[ANIM] wind-up blends in, then holds full weight until the cast time ends", function()
	local s = AnimTimeline.sample(TIMING, 0.05)
	T.eq(s.phase, "windup")
	near(s.weight, 0.5, "half-way through the blend-in")
	near(s.mix, 0)
	s = AnimTimeline.sample(TIMING, 0.99)
	T.eq(s.phase, "windup")
	near(s.weight, 1)
	near(s.windupT, 0.99)
end)

test("[ANIM] release starts exactly at the cast time and snaps into the release pose", function()
	local s = AnimTimeline.sample(TIMING, 1)
	T.eq(s.phase, "release")
	near(s.mix, 0)
	near(s.windupT, 1, "wind-up frozen at its end")
	s = AnimTimeline.sample(TIMING, 1.05)
	near(s.mix, 0.5)
	near(s.releaseT, 0.05)
	s = AnimTimeline.sample(TIMING, 1.4)
	near(s.mix, 1)
	near(s.weight, 1)
end)

test("[ANIM] fades out after the hold and ends at the total time", function()
	local s = AnimTimeline.sample(TIMING, 1.5 + 0.125)
	T.eq(s.phase, "fade")
	near(s.weight, 0.5)
	near(s.releaseT, 0.5, "release frozen at the hold's end")
	near(AnimTimeline.total(TIMING), 1.75)
	s = AnimTimeline.sample(TIMING, 1.75)
	T.eq(s.phase, "done")
	near(s.weight, 0)
end)

test("[ANIM] no wind-up goes straight to the release, still blending in", function()
	local timing = { windup = 0, hold = 0.4, blendIn = 0.1, snap = 0, blendOut = 0.2 }
	local s = AnimTimeline.sample(timing, 0.05)
	T.eq(s.phase, "release")
	near(s.mix, 1, "zero snap = instant release pose")
	near(s.weight, 0.5)
end)

test("[ANIM] negative time is treated as the start", function()
	local s = AnimTimeline.sample(TIMING, -3)
	T.eq(s.phase, "windup")
	near(s.weight, 0)
end)

-- AnimationIds: the owner pastes published ids; blanks and junk must fall back to the placeholder pose.
local AnimationIds = require(ReplicatedStorage.Shared.Modules.AnimationIds)

test("[ANIM] ids: blank, missing or junk entries mean 'not authored yet'", function()
	T.eq(AnimationIds.get("Goku", "mild", "windup"), nil, "shipped blank")
	T.eq(AnimationIds.get("Nobody", "mild", "windup"), nil, "unknown character")
	T.eq(AnimationIds.get("Goku", "nope", "windup"), nil, "unknown slot")
	local saved = AnimationIds.ids.Goku.mild.windup
	AnimationIds.ids.Goku.mild.windup = "not an id"
	local junk = AnimationIds.get("Goku", "mild", "windup")
	AnimationIds.ids.Goku.mild.windup = saved
	T.eq(junk, nil, "junk text")
end)

test("[ANIM] ids: digits, numbers and rbxassetid:// all become a playable asset id", function()
	local saved = AnimationIds.ids.Goku.mild.release
	local results = {}
	for _, raw in { "123456", 123456, " rbxassetid://123456 " } do
		AnimationIds.ids.Goku.mild.release = raw :: any
		table.insert(results, AnimationIds.get("Goku", "mild", "release"))
	end
	AnimationIds.ids.Goku.mild.release = saved
	for _, result in results do
		T.eq(result, "rbxassetid://123456")
	end
end)

return tests
