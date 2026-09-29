-- Unit tests for Lib/DuelRules (the clash duel: type the digits, first mistake loses).
local DuelRules = require(script.Parent.Parent.Lib.DuelRules)
local T = require(script.Parent.TestUtil)

local PARAMS = { firstWindow = 2, decay = 0.5, minWindow = 0.5, grace = 0.2 }

-- Deterministic digits: fighter 1 always sees 1, 2, 3, ...; fighter 2 sees 9, 8, 7, ...
local function digits(id: number, step: number): number
	return if id == 1 then step % 10 else (10 - step) % 10
end

local tests = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

test("[DUEL] windows shrink every step and stop at the minimum", function()
	T.eq(DuelRules.window(PARAMS, 1), 2)
	T.eq(DuelRules.window(PARAMS, 2), 1)
	T.eq(DuelRules.window(PARAMS, 3), 0.5)
	T.eq(DuelRules.window(PARAMS, 9), 0.5, "never below the minimum")
end)

test("[DUEL] a correct digit moves you on to the next, with a shorter window", function()
	local s = DuelRules.new({ 1, 2 }, 0, PARAMS, digits)
	T.eq(s.fighters[1].digit, 1)
	T.eq(DuelRules.input(s, 1, 1, 1, 0.5), "ok")
	T.eq(s.fighters[1].step, 2)
	T.eq(s.fighters[1].digit, 2)
	T.eq(s.fighters[1].deadline, 1.5, "the next window starts when you answered")
	T.eq(DuelRules.result(s, 0.6), nil, "nobody has made a mistake")
end)

test("[DUEL] the first mistake loses: a wrong digit", function()
	local s = DuelRules.new({ 1, 2 }, 0, PARAMS, digits)
	DuelRules.input(s, 1, 1, 1, 0.3)
	T.eq(DuelRules.input(s, 2, 1, 5, 0.4), "wrong")
	local r = DuelRules.result(s, 0.4) :: DuelRules.Result
	T.truthy(r and r.loser == 2 and r.winner == 1 and not r.draw, "fighter 2 typed a wrong digit")
end)

test("[DUEL] the first mistake loses: letting the window run out", function()
	local s = DuelRules.new({ 1, 2 }, 0, PARAMS, digits)
	-- Fighter 1 keeps answering (next windows close at 1.5, 1.9, 2.3); fighter 2 never does.
	T.eq(DuelRules.input(s, 1, 1, 1, 0.5), "ok")
	T.eq(DuelRules.input(s, 1, 2, 2, 1.4), "ok")
	T.eq(DuelRules.input(s, 1, 3, 3, 1.8), "ok")
	T.eq(DuelRules.result(s, 2.1), nil, "still inside fighter 2's grace")
	local r = DuelRules.result(s, 2.25) :: DuelRules.Result
	T.truthy(r and r.loser == 2 and r.winner == 1, "fighter 2 timed out")
	T.eq(DuelRules.input(s, 2, 1, 9, 2.3), "over", "too late to answer now")
end)

test("[DUEL] an answer inside the network grace still counts; after it, it's a mistake", function()
	local s = DuelRules.new({ 1, 2 }, 0, PARAMS, digits)
	T.eq(DuelRules.input(s, 1, 1, 1, 2.1), "ok", "0.1 s after the window, within the 0.2 s grace")
	T.eq(DuelRules.input(s, 2, 1, 9, 2.25), "wrong", "past the grace")
end)

test("[DUEL] when both slip, whoever slipped first loses; the same instant is a draw", function()
	local s = DuelRules.new({ 1, 2 }, 0, PARAMS, digits)
	DuelRules.input(s, 1, 1, 1, 0.2) -- fighter 1's next window closes at 1.2 (a timeout counts at 1.4, after grace)
	DuelRules.input(s, 2, 1, 7, 1.3) -- fighter 2 types a wrong digit at 1.3
	local r = DuelRules.result(s, 1.5) :: DuelRules.Result
	T.truthy(r and r.loser == 2, "fighter 2's mistake at 1.3 came before fighter 1's timeout at 1.4")
	local d = DuelRules.new({ 1, 2 }, 0, PARAMS, digits)
	local draw = DuelRules.result(d, 5) :: DuelRules.Result -- nobody ever answered: both time out together
	T.truthy(draw and draw.draw and draw.winner == nil, "a draw")
end)

test("[DUEL] duplicate or out-of-date answers are ignored, junk is a mistake", function()
	local s = DuelRules.new({ 1, 2 }, 0, PARAMS, digits)
	DuelRules.input(s, 1, 1, 1, 0.2)
	T.eq(DuelRules.input(s, 1, 1, 1, 0.3), "stale", "step 1 again (a resent message)")
	T.eq(DuelRules.input(s, 1, "2", 2, 0.3), "stale", "a step that isn't a number")
	T.eq(DuelRules.input(s, 1, 2, "2", 0.3), "wrong", "a digit that isn't a number")
	T.eq(DuelRules.input(s, 99, 1, 1, 0.3), "over", "not in this duel")
end)

test("[DUEL] random digits are single digits and never repeat back to back", function()
	local nextDigit = DuelRules.randomDigits(Random.new(7))
	local previous = nil
	for step = 1, 500 do
		local d = nextDigit(1, step, previous)
		T.truthy(d >= 0 and d <= 9 and d % 1 == 0, "0-9")
		T.truthy(d ~= previous, "no repeat")
		previous = d
	end
end)

return tests
