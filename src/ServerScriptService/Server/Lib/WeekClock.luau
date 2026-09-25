-- The leaderboard week (owner-approved 2026-09-23): weeks start Monday 00:00 UTC. Pure, unit-tested.
local WeekClock = {}

local DAY = 86400
local WEEK = 7 * DAY

-- Unix time of the Monday 00:00 UTC that starts the week containing `unix`.
function WeekClock.weekStart(unix: number): number
	local days = math.floor(unix / DAY)
	local weekday = (days + 3) % 7 -- 1970-01-01 was a Thursday; this makes Monday 0
	return (days - weekday) * DAY
end

-- When the current week's board resets.
function WeekClock.nextReset(unix: number): number
	return WeekClock.weekStart(unix) + WEEK
end

-- A stable name for the week, e.g. "20260921" (its Monday), used in the weekly DataStore's name.
function WeekClock.key(unix: number): string
	return DateTime.fromUnixTimestamp(WeekClock.weekStart(unix)):FormatUniversalTime("YYYYMMDD", "en-us")
end

return WeekClock
