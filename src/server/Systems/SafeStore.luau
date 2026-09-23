-- A careful wrapper round DataStoreService (first used by the kill leaderboards, 2026-09-23; saved progress,
-- Phase 3 item 4, builds on it). Every call:
--   * waits for request budget instead of throwing when Roblox's per-minute limits are spent;
--   * retries transient failures with exponential backoff;
--   * notices when DataStores aren't reachable at all (Studio without "Enable Studio Access to API
--     Services", or a place that was never published) and reports offline, so callers fall back
--     instead of spamming errors.
local DataStoreService = game:GetService("DataStoreService")

local SafeStore = {}

local RETRIES = 3
local BUDGET_WAIT = 8 -- seconds to wait for request budget before giving up on this call

local offline = false
local offlineReason: string? = nil

local function looksPermanent(message: string): boolean
	return string.find(message, "StudioAccessToApisNotAllowed", 1, true) ~= nil
		or string.find(message, "403", 1, true) ~= nil
		or string.find(message, "must publish", 1, true) ~= nil
		or string.find(message, "not allowed", 1, true) ~= nil
end

-- True once DataStores have been found unreachable for this server's lifetime.
function SafeStore.isOffline(): (boolean, string?)
	return offline, offlineReason
end

function SafeStore.ordered(name: string): OrderedDataStore?
	if offline then
		return nil
	end
	local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, name)
	if not ok then
		offline, offlineReason = true, tostring(store)
		return nil
	end
	return store
end

-- Runs `fn` (which makes exactly one DataStore request of `requestType`) safely. Returns (ok, result).
function SafeStore.call(requestType: Enum.DataStoreRequestType, fn: () -> any): (boolean, any)
	if offline then
		return false, offlineReason
	end
	local waited = 0
	while DataStoreService:GetRequestBudgetForRequestType(requestType) < 1 and waited < BUDGET_WAIT do
		task.wait(0.5)
		waited += 0.5
	end
	local lastError = nil
	for attempt = 1, RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = tostring(result)
		if looksPermanent(lastError) then
			offline, offlineReason = true, lastError
			warn("[NAU] DataStores unavailable, running offline: " .. lastError)
			return false, lastError
		end
		if attempt < RETRIES then
			task.wait(2 ^ (attempt - 1)) -- 1 s, 2 s
		end
	end
	warn("[NAU] DataStore request failed after retries: " .. tostring(lastError))
	return false, lastError
end

return SafeStore
