-- Unit tests for Lib/RoundTimer (the 30-second alert).
local RoundTimer = require(script.Parent.Parent.Lib.RoundTimer)
local T = require(script.Parent.TestUtil)

local tests = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

test("[ALERT] 30-second alert fires once per end time", function()
	T.eq(RoundTimer.warningDue(480, 440, 30, nil), false, "40 s left: too early")
	T.eq(RoundTimer.warningDue(480, 450, 30, nil), true, "30 s left")
	T.eq(RoundTimer.warningDue(480, 455, 30, 480), false, "already sent for this end time")
	T.eq(RoundTimer.warningDue(480, 480, 30, nil), false, "time's up: no alert")
	T.eq(RoundTimer.warningDue(540, 511, 30, 480), true, "sudden death's new end time gets its own alert")
end)

return tests
