-- Numbers Assassin Universe: client entry point. Starts each controller in order.
local ClientState = require(script:WaitForChild("ClientState"))
local Controllers = script:WaitForChild("Controllers")

local ORDER = {
	"HUDController",
	"NumberPlateController",
	"SubmissionController",
	"AbilityController",
	"LobbyController",
	"ShopController",
	"LeaderboardController",
	"FXController",
}

ClientState.Start()
for _, name in ORDER do
	local ok, err = pcall(function()
		require(Controllers:WaitForChild(name)).Start()
	end)
	if not ok then
		warn("[NAU] " .. name .. " failed to start: " .. tostring(err))
	end
end

print("[NAU] Client started")
