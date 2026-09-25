-- Unit tests for Lib/MeleeRules (the M1 combo, and trades building to a clash).
local MeleeRules = require(script.Parent.Parent.Lib.MeleeRules)
local T = require(script.Parent.TestUtil)

local P = {
	interval = 0.32,
	comboLength = 4,
	comboReset = 1,
	endlag = 0.8,
	tradeWindow = 0.35,
	chainGap = 1.6,
	tradesToClash = 3,
}

local tests = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

test("[M1] clicks walk through the 4-hit combo, then rest", function()
	local s = MeleeRules.new()
	T.eq(MeleeRules.swing(s, 1, 0, P), 1)
	T.eq(MeleeRules.swing(s, 1, 0.4, P), 2)
	T.eq(MeleeRules.swing(s, 1, 0.8, P), 3)
	T.eq(MeleeRules.swing(s, 1, 1.2, P), 4, "finisher")
	local step, why = MeleeRules.swing(s, 1, 1.6, P)
	T.eq(step, nil, "rest after the finisher")
	T.eq(why, "resting")
	T.eq(MeleeRules.swing(s, 1, 1.2 + 0.32 + 0.8, P), 1, "after the rest: a fresh combo")
end)

test("[M1] too-fast clicks are refused and don't advance the combo", function()
	local s = MeleeRules.new()
	MeleeRules.swing(s, 1, 0, P)
	local step, why = MeleeRules.swing(s, 1, 0.1, P)
	T.eq(step, nil)
	T.eq(why, "too_soon")
	T.eq(MeleeRules.swing(s, 1, 0.35, P), 2)
end)

test("[M1] a pause longer than the reset starts the combo over", function()
	local s = MeleeRules.new()
	MeleeRules.swing(s, 1, 0, P)
	MeleeRules.swing(s, 1, 0.4, P)
	T.eq(MeleeRules.swing(s, 1, 2, P), 1)
end)

test("[M1] punches landing on each other within the window trade", function()
	local s = MeleeRules.new()
	local traded = MeleeRules.hit(s, 1, 2, 0, P)
	T.eq(traded, false, "first punch alone isn't a trade yet")
	local traded2, chain = MeleeRules.hit(s, 2, 1, 0.2, P)
	T.eq(traded2, true)
	T.eq(chain, 1)
end)

test("[M1] an answer outside the window is not a trade", function()
	local s = MeleeRules.new()
	MeleeRules.hit(s, 1, 2, 0, P)
	local traded = MeleeRules.hit(s, 2, 1, 0.5, P)
	T.eq(traded, false)
end)

test("[M1] three trades in a row clash, and the count resets", function()
	local s = MeleeRules.new()
	local clash
	for i = 0, 2 do
		local t = i * 0.8
		MeleeRules.hit(s, 1, 2, t, P)
		_, _, clash = MeleeRules.hit(s, 2, 1, t + 0.1, P)
		T.eq(clash, i == 2, "clash only on the third trade")
	end
	MeleeRules.hit(s, 1, 2, 3, P)
	local _, chain = MeleeRules.hit(s, 2, 1, 3.1, P)
	T.eq(chain, 1, "a new chain after the clash")
end)

test("[M1] a one-sided punch between trades breaks the chain", function()
	local s = MeleeRules.new()
	MeleeRules.hit(s, 1, 2, 0, P)
	MeleeRules.hit(s, 2, 1, 0.1, P) -- trade 1
	MeleeRules.hit(s, 1, 2, 0.6, P) -- unanswered...
	MeleeRules.hit(s, 1, 2, 1.0, P) -- ...and again: one-sided
	local traded, chain = MeleeRules.hit(s, 2, 1, 1.1, P)
	T.eq(traded, true)
	T.eq(chain, 1, "chain restarted")
end)

test("[M1] trades too far apart start the count over", function()
	local s = MeleeRules.new()
	MeleeRules.hit(s, 1, 2, 0, P)
	MeleeRules.hit(s, 2, 1, 0.1, P)
	MeleeRules.hit(s, 1, 2, 3, P)
	local _, chain = MeleeRules.hit(s, 2, 1, 3.1, P)
	T.eq(chain, 1)
end)

test("[M1] different pairs keep separate chains", function()
	local s = MeleeRules.new()
	MeleeRules.hit(s, 1, 2, 0, P)
	MeleeRules.hit(s, 2, 1, 0.1, P)
	MeleeRules.hit(s, 1, 3, 0.2, P)
	local traded = MeleeRules.hit(s, 3, 1, 0.3, P)
	T.eq(traded, true, "1 vs 3 trade")
	MeleeRules.hit(s, 1, 2, 0.8, P)
	local _, chain = MeleeRules.hit(s, 2, 1, 0.9, P)
	T.eq(chain, 2, "1 vs 2 chain unaffected by 1 vs 3")
end)

test("[M1] forget clears a fighter's combo and pairs", function()
	local s = MeleeRules.new()
	MeleeRules.swing(s, 7, 0, P)
	MeleeRules.hit(s, 7, 8, 0, P)
	MeleeRules.forget(s, 7)
	T.eq(s.fighters[7], nil)
	T.eq(next(s.pairs), nil)
end)

return tests
