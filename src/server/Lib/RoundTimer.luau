-- The round clock's alert rule (owner, 2026-09-23: "an alert to all players in the match that there are 30
-- seconds left"). Pure, unit-tested; RoundManager fires the alert.
--   * The alert fires once when `warnSeconds` or less are left before `endsAt`.
--   * It is remembered per end time, so a new end time (sudden death after a tie) gets its own alert.
local RoundTimer = {}

-- Is the alert due now? `warnedFor` is the end time the last alert was sent for (nil if none yet).
function RoundTimer.warningDue(endsAt: number, now: number, warnSeconds: number, warnedFor: number?): boolean
	local left = endsAt - now
	return left > 0 and left <= warnSeconds and warnedFor ~= endsAt
end

return RoundTimer
