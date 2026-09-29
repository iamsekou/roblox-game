-- Unit tests for Lib/XpRules (character XP, levels and prestige).
local XpRules = require(script.Parent.Parent.Lib.XpRules)
local T = require(script.Parent.TestUtil)

-- The approved numbers (owner, 2026-09-29), pinned here independently of Constants tuning.
local P = { maxLevel = 20, maxPrestige = 10, base = 6000, step = 800, growth = 0.35, round = 100 }

local tests = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

test("[XP] bars: 6,000 at level 1, +800 a level, 35% bigger per prestige", function()
	T.eq(XpRules.need(1, 0, P), 6000)
	T.eq(XpRules.need(10, 0, P), 13200)
	T.eq(XpRules.need(20, 0, P), 21200)
	T.eq(XpRules.need(1, 1, P), 8100)
	T.eq(XpRules.need(1, 5, P), 16500, "x2.75 at prestige 5")
	T.eq(XpRules.totalFor(0, P), 272000, "a full prestige at 0 is the approved ~272,000")
	T.truthy(XpRules.totalFor(1, P) > XpRules.totalFor(0, P), "each prestige takes longer")
	T.truthy(XpRules.totalFor(10, P) > XpRules.totalFor(9, P))
end)

test("[XP] gaining XP levels up, carries the rest over, and can gain several levels at once", function()
	local p, gained = XpRules.add(XpRules.new(), 1200, P)
	T.eq(p.l, 1) T.eq(p.x, 1200) T.eq(gained, 0)
	p, gained = XpRules.add(p, 5000, P)
	T.eq(p.l, 2, "6,200 total: level 2") T.eq(p.x, 200, "the extra 200 carries over") T.eq(gained, 1)
	p, gained = XpRules.add(XpRules.new(), 6000 + 6800 + 100, P)
	T.eq(p.l, 3) T.eq(p.x, 100) T.eq(gained, 2)
end)

test("[XP] the last bar fills and stops; nothing more is kept until a prestige", function()
	local p, _, full = XpRules.add(XpRules.new(), 10 ^ 7, P)
	T.eq(p.l, 20) T.eq(p.x, 21200) T.eq(full, true, "this gain filled it")
	T.truthy(XpRules.canPrestige(p, P))
	local again, gained, fullAgain = XpRules.add(p, 5000, P)
	T.eq(again.x, 21200, "no overflow") T.eq(gained, 0) T.eq(fullAgain, false, "already full: not reported twice")
end)

test("[XP] prestige: only when full, back to level 1, one higher; none past the top", function()
	T.eq(XpRules.prestige(XpRules.new(), P), nil, "not ready")
	local full = XpRules.add(XpRules.new(), 10 ^ 7, P)
	local next = XpRules.prestige(full, P) :: any
	T.eq(next.p, 1) T.eq(next.l, 1) T.eq(next.x, 0)
	local top = { p = 10, l = 20, x = XpRules.need(20, 10, P) }
	T.eq(XpRules.isFull(top, P), true)
	T.eq(XpRules.prestige(top, P), nil, "prestige 10 is the top")
end)

test("[XP] bad amounts do nothing", function()
	for _, amount in { 0, -500, 0 / 0, "1200" :: any } do
		local p, gained = XpRules.add(XpRules.new(), amount, P)
		T.eq(p.x, 0) T.eq(gained, 0)
	end
end)

test("[XP] saved progress is sanitised", function()
	local p = XpRules.sanitize({ p = 3.7, l = 99, x = -4 }, P)
	T.eq(p.p, 3) T.eq(p.l, 20) T.eq(p.x, 0)
	T.eq(XpRules.sanitize({ p = 50 }, P).p, 10, "prestige capped")
	T.eq(XpRules.sanitize({ l = 2, x = 10 ^ 9 }, P).x, XpRules.need(2, 0, P) - 1, "an impossible full mid bar")
	T.eq(XpRules.sanitize("junk", P).l, 1)
	T.eq(XpRules.sanitize({ p = 0 / 0, l = 0 / 0 }, P).p, 0)
	T.eq(XpRules.numeral(4), "IV") T.eq(XpRules.numeral(10), "X")
end)

return tests
