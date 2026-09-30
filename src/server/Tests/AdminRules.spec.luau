-- Unit tests for Lib/AdminRules (who is an admin, and what an admin request may contain).
local AdminRules = require(script.Parent.Parent.Lib.AdminRules)
local T = require(script.Parent.TestUtil)

local LIMITS = { maxCredits = 1000000, maxXp = 100000, minSeconds = 5, maxSeconds = 3600, maxReason = 120 }
local ADMINS = { 111, 222 }

local tests = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

test("[ADMIN] only listed ids are admins live; everyone is in Studio", function()
	T.eq(AdminRules.isAdmin(111, ADMINS, false), true)
	T.eq(AdminRules.isAdmin(222, ADMINS, false), true)
	T.eq(AdminRules.isAdmin(333, ADMINS, false), false)
	T.eq(AdminRules.isAdmin(-1, ADMINS, false), false, "a local test id is nobody live")
	T.eq(AdminRules.isAdmin(-1, ADMINS, true), true, "Studio test players are admins")
end)

test("[ADMIN] unknown commands and non-table args are refused", function()
	local args, why = AdminRules.validate("deleteEverything", {}, LIMITS)
	T.eq(args, nil)
	T.eq(why, "unknown_command")
	_, why = AdminRules.validate(42, {}, LIMITS)
	T.eq(why, "unknown_command")
	_, why = AdminRules.validate("giveCredits", "lots", LIMITS)
	T.eq(why, "malformed")
end)

test("[ADMIN] amounts must be whole, positive and within the cap", function()
	local ok = AdminRules.validate("giveCredits", { target = 111, credits = 5000 }, LIMITS)
	T.truthy(ok and ok.credits == 5000 and ok.target == 111)
	for _, bad in { 0, -5, 2.5, 1000001, 0 / 0, math.huge, "5000" } do
		local args, why = AdminRules.validate("giveCredits", { target = 111, credits = bad }, LIMITS)
		T.eq(args, nil, "credits " .. tostring(bad))
		T.eq(why, "bad_credits")
	end
	local _, why = AdminRules.validate("giveXp", { target = 111, xp = 100001 }, LIMITS)
	T.eq(why, "bad_xp")
end)

test("[ADMIN] a target must be a whole user id", function()
	T.eq(select(2, AdminRules.validate("kick", { reason = "x" }, LIMITS)), "bad_target", "missing")
	for _, bad in { "111", 1.5, 0 / 0 } do
		local _, why = AdminRules.validate("kick", { target = bad, reason = "x" }, LIMITS)
		T.eq(why, "bad_target")
	end
	T.truthy(AdminRules.validate("kick", { target = -2, reason = "x" }, LIMITS), "Studio's negative test ids are fine")
end)

test("[ADMIN] seconds, modes, duels and switches only take their allowed values", function()
	T.truthy(AdminRules.validate("setTimeLeft", { seconds = 60 }, LIMITS))
	T.eq(select(2, AdminRules.validate("setTimeLeft", { seconds = 2 }, LIMITS)), "bad_seconds")
	T.eq(select(2, AdminRules.validate("setTimeLeft", { seconds = 7200 }, LIMITS)), "bad_seconds")
	for _, mode in { "random", "FFA", "Team6v6" } do
		T.truthy(AdminRules.validate("setMode", { mode = mode }, LIMITS), mode)
	end
	T.eq(select(2, AdminRules.validate("setMode", { mode = "Battle" }, LIMITS)), "bad_mode")
	T.truthy(AdminRules.validate("duel", { duel = "watch" }, LIMITS))
	T.eq(select(2, AdminRules.validate("duel", { duel = "win" }, LIMITS)), "bad_duel")
	local off = AdminRules.validate("ghost", { on = false }, LIMITS)
	T.truthy(off and off.on == false, "false is a real value, not a missing one")
	T.eq(select(2, AdminRules.validate("unlockAll", { on = "yes" }, LIMITS)), "bad_on")
	T.truthy(AdminRules.validate("startRound", nil, LIMITS), "no arguments needed")
end)

test("[ADMIN] kick reasons are cleaned, capped and defaulted", function()
	T.eq(AdminRules.cleanReason("  spamming\n\tthe lobby  ", 120), "spamming  the lobby")
	T.eq(AdminRules.cleanReason("   ", 120), "No reason given")
	T.eq(AdminRules.cleanReason(string.rep("a", 121), 120), nil)
	T.eq(AdminRules.cleanReason(5, 120), nil)
end)

return tests
