-- Code Clash [CC] (formerly Numbers Assassin Universe; internal names keep the NAU prefix): client entry point. Starts each controller in order.
local ClientState = require(script:WaitForChild("ClientState"))
local Controllers = script:WaitForChild("Controllers")

local ORDER = {
	"HUDController",
	"XpController", -- after HUDController: it uses its banner and toasts
	"NumberPlateController",
	"SubmissionController",
	"ClashDuelController", -- before AbilityController, which hands it each clash duel
	"AbilityController",
	"LobbyController",
	"ShopController",
	"LeaderboardController",
	"FXController",
	"SettingsController", -- after FXController: it switches the effects FXController started
	"TutorialController",
	"TrainingController", -- after TutorialController: the training menu opens HOW TO PLAY
	"AdminController", -- admin panel; only shows for admins
}

ClientState.Start()
require(script:WaitForChild("Audio")).Start()
for _, name in ORDER do
	local ok, err = pcall(function()
		require(Controllers:WaitForChild(name)).Start()
	end)
	if not ok then
		warn("[NAU] " .. name .. " failed to start: " .. tostring(err))
	end
end

print("[NAU] Client started")
