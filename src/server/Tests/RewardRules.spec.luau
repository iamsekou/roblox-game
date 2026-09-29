-- Unit tests for Lib/RewardRules (the kill-farming limit).
local RewardRules = require(script.Parent.Parent.Lib.RewardRules)
local T = require(script.Parent.TestUtil)

local WINDOW, MAX = 60, 3

local tests = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

test("[FARM] the same victim pays at most MAX times per window", function()
	local s = RewardRules.new()
	for i = 1, MAX do
		T.eq(RewardRules.claim(s, 1, 2, i * 7, WINDOW, MAX), true, "paid elimination " .. i)
	end
	T.eq(RewardRules.claim(s, 1, 2, 28, WINDOW, MAX), false, "a fourth inside the window")
	T.eq(RewardRules.claim(s, 1, 2, 35, WINDOW, MAX), false, "still inside")
end)

test("[FARM] pays again once the oldest paid elimination leaves the window", function()
	local s = RewardRules.new()
	for i = 1, MAX do
		RewardRules.claim(s, 1, 2, i * 7, WINDOW, MAX)
	end
	T.eq(RewardRules.claim(s, 1, 2, 7 + WINDOW, WINDOW, MAX), true, "the first one aged out")
	T.eq(RewardRules.claim(s, 1, 2, 7 + WINDOW + 1, WINDOW, MAX), false, "only one slot freed")
end)

test("[FARM] other victims and other attackers are counted separately", function()
	local s = RewardRules.new()
	for i = 1, MAX do
		RewardRules.claim(s, 1, 2, i, WINDOW, MAX)
	end
	T.eq(RewardRules.claim(s, 1, 3, 5, WINDOW, MAX), true, "a different victim")
	T.eq(RewardRules.claim(s, 2, 1, 5, WINDOW, MAX), true, "the victim eliminating back")
	T.eq(RewardRules.claim(s, 4, 2, 5, WINDOW, MAX), true, "someone else eliminating the same victim")
end)

test("[FARM] a refused elimination doesn't use up a slot, and leavers are forgotten", function()
	local s = RewardRules.new()
	for i = 1, MAX do
		RewardRules.claim(s, 1, 2, i, WINDOW, MAX)
	end
	for t = 10, 50, 10 do
		RewardRules.claim(s, 1, 2, t, WINDOW, MAX) -- all refused
	end
	T.eq(RewardRules.claim(s, 1, 2, 1 + WINDOW, WINDOW, MAX), true, "refusals didn't extend the lockout")
	RewardRules.forget(s, 2)
	T.eq(s[1][2], nil, "as victim")
	RewardRules.forget(s, 1)
	T.eq(s[1], nil, "as attacker")
end)

return tests
