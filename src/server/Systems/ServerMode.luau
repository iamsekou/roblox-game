-- What kind of server this is, decided once at start (every system reads it; it requires nothing).
--   Training Grounds (owner, 2026-09-29): a reserved private server made for one player by TrainingService
--   (TeleportService:ReserveServer). A reserved server has a PrivateServerId and no owner (a player-owned VIP
--   server has an owner and stays a normal server). In Studio, where teleports don't run, the attribute
--   NAU_DevTraining = true on ServerScriptService (set in Edit mode, before pressing Play) makes Play a training
--   server; it's ignored live.
-- Clients learn it from workspace's NAU_Training attribute.
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ServerMode = {}

local studioTraining = RunService:IsStudio() and ServerScriptService:GetAttribute("NAU_DevTraining") == true
local reserved = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0

ServerMode.isTraining = studioTraining or reserved
workspace:SetAttribute("NAU_Training", ServerMode.isTraining)

return ServerMode
