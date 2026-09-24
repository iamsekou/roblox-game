-- Unit tests for Lib/ProfileData (saved-progress format, sanitising and the session lock).
local ProfileData = require(script.Parent.Parent.Lib.ProfileData)
local T = require(script.Parent.TestUtil)

local DEFS = {
	{ id = "Free1", tier = "Free" },
	{ id = "A", tier = "Yen" },
	{ id = "B", tier = "Yen" },
	{ id = "Pass", tier = "Robux" },
}

local tests = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

test("[SAVE] a new player gets a fresh profile", function()
	local p = ProfileData.sanitize(nil, DEFS, "Free1")
	T.eq(p.yen, 0)
	T.eq(#p.owned, 0)
	T.eq(p.equipped, "Free1")
	T.eq(p.version, ProfileData.VERSION)
end)

test("[SAVE] a good record loads as saved", function()
	local p = ProfileData.sanitize({ yen = 12500, owned = { "A", "B" }, equipped = "B" }, DEFS, "Free1")
	T.eq(p.yen, 12500)
	T.eq(#p.owned, 2)
	T.eq(p.equipped, "B")
end)

test("[SAVE] damaged or tampered values are repaired", function()
	local p = ProfileData.sanitize({ yen = -50, owned = { "A", "A", "Nope", "Pass", "Free1", 7 }, equipped = "Pass" }, DEFS, "Free1")
	T.eq(p.yen, 0, "negative yen")
	T.eq(#p.owned, 1, "duplicates, unknown ids, Robux and free characters are dropped")
	T.eq(p.owned[1], "A")
	T.eq(p.equipped, "Free1", "an unowned equipped character falls back to the default")
	T.eq(ProfileData.sanitize({ yen = 0 / 0 }, DEFS, "Free1").yen, 0, "NaN yen")
	T.eq(ProfileData.sanitize({ yen = 99.7 }, DEFS, "Free1").yen, 99, "fractional yen")
	T.eq(ProfileData.sanitize("garbage", DEFS, "Free1").yen, 0, "not a table at all")
	T.eq(ProfileData.sanitize({ equipped = "Free1" }, DEFS, "B").equipped, "Free1", "a free character is always equippable")
end)

test("[SAVE] session lock: free, mine, or stale can be claimed; a live one can't", function()
	T.eq(ProfileData.canClaim(nil, "me", 1000, 180), true, "no record")
	T.eq(ProfileData.canClaim({ yen = 1 }, "me", 1000, 180), true, "no lock")
	T.eq(ProfileData.canClaim({ session = { jobId = "me", time = 990 } }, "me", 1000, 180), true, "already mine")
	T.eq(ProfileData.canClaim({ session = { jobId = "other", time = 990 } }, "me", 1000, 180), false, "another server, fresh")
	T.eq(ProfileData.canClaim({ session = { jobId = "other", time = 800 } }, "me", 1000, 180), true, "another server, stale")
end)

test("[SAVE] saves only while holding the lock; release drops it", function()
	T.eq(ProfileData.holds({ session = { jobId = "me", time = 1 } }, "me"), true)
	T.eq(ProfileData.holds({ session = { jobId = "other", time = 1 } }, "me"), false, "taken over: don't overwrite")
	T.eq(ProfileData.holds({}, "me"), false)
	local profile = ProfileData.sanitize({ yen = 5, owned = { "A" }, equipped = "A" }, DEFS, "Free1")
	local held = ProfileData.record(profile, "me", 100, false)
	T.eq(held.session.jobId, "me")
	T.eq(held.session.time, 100)
	T.eq(held.yen, 5)
	local released = ProfileData.record(profile, "me", 100, true)
	T.eq(released.session, nil)
	T.eq(released.owned[1], "A")
end)

return tests
