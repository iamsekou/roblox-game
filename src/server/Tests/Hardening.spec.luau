-- Unit tests for the audit fixes' small rule modules (2026-09-28): Lib/RateLimiter and Lib/StoreErrors.
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)
local StoreErrors = require(script.Parent.Parent.Lib.StoreErrors)
local T = require(script.Parent.TestUtil)

local tests = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

test("[LIMIT] one request per interval per player; refusals don't push the next one back", function()
	local l = RateLimiter.new(0.25)
	T.eq(RateLimiter.allow(l, "a", 0), true)
	T.eq(RateLimiter.allow(l, "a", 0.1), false)
	T.eq(RateLimiter.allow(l, "a", 0.2), false)
	T.eq(RateLimiter.allow(l, "a", 0.25), true, "measured from the last allowed request")
	T.eq(RateLimiter.allow(l, "b", 0.26), true, "players are independent")
	RateLimiter.forget(l, "a")
	T.eq(RateLimiter.allow(l, "a", 0.3), true, "a forgotten player starts fresh")
end)

test("[STORE] only real 'DataStores unreachable' errors switch saving off", function()
	-- Roblox's access errors.
	T.eq(StoreErrors.isPermanent("403: Cannot write to DataStore from studio if API access is not enabled."), true)
	T.eq(StoreErrors.isPermanent("StudioAccessToApisNotAllowed: Access to DataStore API is not allowed"), true)
	T.eq(StoreErrors.isPermanent("You must publish this place to the web to access DataStore."), true)
	-- Transient or unrelated errors must not stop saves for the whole server.
	T.eq(StoreErrors.isPermanent("502: API Services rejected request with error. HTTP 403 (Forbidden)"), false, "a 502 quoting 403")
	T.eq(StoreErrors.isPermanent("104: Cannot store Array in data store. Data stores can only accept valid UTF-8 characters. Key u_4031"), false)
	T.eq(StoreErrors.isPermanent("301: GetAsync request dropped. Request was throttled, but throttled request queue was full."), false)
	T.eq(StoreErrors.isPermanent("Something not allowed happened"), false, "loose wording")
	T.eq(StoreErrors.isPermanent(nil :: any), false)
end)

return tests
