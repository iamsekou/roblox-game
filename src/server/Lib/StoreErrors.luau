-- Which DataStore errors mean "DataStores are unreachable for this server's whole life" (audit fix, 2026-09-28).
-- Only these switch SafeStore to offline, which stops every save on the server, so the test is strict: the
-- messages Roblox gives when Studio has no API access or the place was never published. Before, any message
-- that merely contained "403" or "not allowed" counted, so one odd transient error could stop all saving.
-- Pure: string matching only, so it runs in the unit tests.
local StoreErrors = {}

local PERMANENT = {
	"StudioAccessToApisNotAllowed",
	"Cannot write to DataStore from studio",
	"Cannot read from DataStore from studio",
	"must publish this place",
}

function StoreErrors.isPermanent(message: string): boolean
	if type(message) ~= "string" then
		return false
	end
	-- Roblox's own access error starts with its code: "403: ...".
	if string.match(message, "^%s*403:") then
		return true
	end
	for _, phrase in PERMANENT do
		if string.find(message, phrase, 1, true) then
			return true
		end
	end
	return false
end

return StoreErrors
