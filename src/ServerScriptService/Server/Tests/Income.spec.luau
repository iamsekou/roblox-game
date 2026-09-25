-- Unit tests for Lib/IncomeRules (passive yen, friend booster) and Lib/RoundTimer (the 30-second alert).
local IncomeRules = require(script.Parent.Parent.Lib.IncomeRules)
local RoundTimer = require(script.Parent.Parent.Lib.RoundTimer)
local T = require(script.Parent.TestUtil)

local tests = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

test("[INCOME] nothing is paid before the interval is up", function()
	local count, nextAt = IncomeRules.due(120, 119.9, 120)
	T.eq(count, 0)
	T.eq(nextAt, 120, "the clock doesn't move")
end)

test("[INCOME] one payout when due, and the clock moves one interval on", function()
	local count, nextAt = IncomeRules.due(120, 120, 120)
	T.eq(count, 1)
	T.eq(nextAt, 240)
	count, nextAt = IncomeRules.due(120, 121, 120)
	T.eq(count, 1, "a late check still pays once")
	T.eq(nextAt, 240, "and keeps the original rhythm")
end)

test("[INCOME] a stalled server pays each missed interval once", function()
	local count, nextAt = IncomeRules.due(120, 365, 120)
	T.eq(count, 3, "due at 120, 240 and 360")
	T.eq(nextAt, 480)
end)

test("[INCOME] friends: only friends who are present, never yourself", function()
	local friends = { [1] = { [2] = true, [3] = true, [9] = true } }
	local function isFriend(a: number, b: number): boolean
		return (friends[a] and friends[a][b]) == true
	end
	T.eq(IncomeRules.countFriends(1, { 1, 2, 3, 4 }, isFriend), 2, "2 and 3 are here; 9 isn't; 4 isn't a friend")
	T.eq(IncomeRules.countFriends(1, { 1 }, isFriend), 0, "alone")
	T.eq(IncomeRules.countFriends(1, { 1, 1 }, function()
		return true
	end), 0, "never counts yourself")
end)

test("[INCOME] friend booster pays per friend", function()
	T.eq(IncomeRules.friendBonus(0, 100), 0, "no friends, no booster")
	T.eq(IncomeRules.friendBonus(1, 100), 100)
	T.eq(IncomeRules.friendBonus(11, 100), 1100, "a full server of friends")
	T.eq(IncomeRules.friendBonus(-3, 100), 0, "never negative")
end)

test("[ALERT] 30-second alert fires once per end time", function()
	T.eq(RoundTimer.warningDue(480, 440, 30, nil), false, "40 s left: too early")
	T.eq(RoundTimer.warningDue(480, 450, 30, nil), true, "30 s left")
	T.eq(RoundTimer.warningDue(480, 455, 30, 480), false, "already sent for this end time")
	T.eq(RoundTimer.warningDue(480, 480, 30, nil), false, "time's up: no alert")
	T.eq(RoundTimer.warningDue(540, 511, 30, 480), true, "sudden death's new end time gets its own alert")
end)

return tests
