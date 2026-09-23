-- Unit tests for Lib/WeekClock (weekly reset) and Lib/LeaderboardRules (merging, ranking, movement).
local WeekClock = require(script.Parent.Parent.Lib.WeekClock)
local LeaderboardRules = require(script.Parent.Parent.Lib.LeaderboardRules)
local T = require(script.Parent.TestUtil)

local function utc(y: number, m: number, d: number, h: number?, min: number?, s: number?): number
	return DateTime.fromUniversalTime(y, m, d, h or 0, min or 0, s or 0).UnixTimestamp
end

local tests = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

test("[BOARD] weeks start Monday 00:00 UTC", function()
	local monday = utc(2026, 9, 21)
	T.eq(WeekClock.weekStart(utc(2026, 9, 23, 15, 30)), monday, "a Wednesday afternoon")
	T.eq(WeekClock.weekStart(monday), monday, "the Monday midnight itself")
	T.eq(WeekClock.weekStart(utc(2026, 9, 27, 23, 59, 59)), monday, "the last second of Sunday")
	T.eq(WeekClock.weekStart(utc(2026, 9, 28)), utc(2026, 9, 28), "the next Monday starts a new week")
	T.eq(WeekClock.nextReset(utc(2026, 9, 23)), utc(2026, 9, 28))
	T.eq(WeekClock.key(utc(2026, 9, 23)), "20260921")
	T.eq(WeekClock.key(utc(2027, 1, 1)), "20261228", "a week can span the new year")
end)

test("[BOARD] unsaved kills merge into the saved board and re-rank it", function()
	local stored = { { userId = 1, kills = 10 }, { userId = 2, kills = 8 }, { userId = 3, kills = 5 } }
	local rows = LeaderboardRules.merge(stored, { [3] = 4 }, {})
	T.eq(rows[1].userId, 1)
	T.eq(rows[2].userId, 3, "5 saved + 4 live = 9 passes 8")
	T.eq(rows[2].kills, 9)
	T.eq(rows[2].live, 4)
	T.eq(rows[3].userId, 2)
	T.eq(rows[3].rank, 3)
end)

test("[BOARD] a player off the saved list joins with their known total plus live kills", function()
	local stored = { { userId = 1, kills = 10 }, { userId = 2, kills = 3 } }
	local rows = LeaderboardRules.merge(stored, { [9] = 2 }, { [9] = 7 })
	T.eq(rows[2].userId, 9, "7 known + 2 live = 9")
	T.eq(rows[2].kills, 9)
	local unknown = LeaderboardRules.merge(stored, { [8] = 1 }, {})
	T.eq(unknown[3].userId, 8, "unknown saved total counts as 0")
	T.eq(unknown[3].kills, 1)
end)

test("[BOARD] ties keep the saved order and never flicker", function()
	local stored = { { userId = 5, kills = 4 }, { userId = 2, kills = 4 } }
	local rows = LeaderboardRules.merge(stored, {}, {})
	T.eq(rows[1].userId, 5)
	T.eq(rows[2].userId, 2)
	local fresh = LeaderboardRules.merge({}, { [7] = 3, [4] = 3 }, {})
	T.eq(fresh[1].userId, 4, "new players tied: lower id first")
end)

test("[BOARD] movement since the last refresh; new entries have no delta", function()
	local previous = { [1] = 1, [2] = 2, [3] = 3 }
	local rows = LeaderboardRules.withChanges(LeaderboardRules.merge({ { userId = 3, kills = 9 }, { userId = 1, kills = 8 }, { userId = 4, kills = 2 } }, {}, {}), previous)
	T.eq(rows[1].delta, 2, "3rd -> 1st climbed two")
	T.eq(rows[2].delta, -1, "1st -> 2nd dropped one")
	T.eq(rows[3].delta, nil, "new on the board")
	local ranks = LeaderboardRules.ranks(rows)
	T.eq(ranks[3], 1)
	T.eq(ranks[4], 3)
end)

return tests
