-- Client-side lookups for any fighter by id: a player, or (Training Grounds) a bot. Bot bodies live in
-- workspace.NAUWorld.Bots, each tagged with its id (attribute BotId); the server's FighterRegistry puts them there.
local Players = game:GetService("Players")

local Fighters = {}

local function botsFolder(): Instance?
	local world = workspace:FindFirstChild("NAUWorld")
	return world and world:FindFirstChild("Bots")
end

function Fighters.botModel(id: number): Model?
	local folder = botsFolder()
	for _, model in if folder then folder:GetChildren() else {} do
		if model:IsA("Model") and model:GetAttribute("BotId") == id then
			return model
		end
	end
	return nil
end

-- The body of the fighter with this id (nil if unknown or not loaded).
function Fighters.modelOf(id: number?): Model?
	if type(id) ~= "number" then
		return nil
	end
	local player = Players:GetPlayerByUserId(id)
	if player then
		return player.Character
	end
	return Fighters.botModel(id)
end

-- Every bot body (FighterAura, plates).
function Fighters.botModels(): { Model }
	local list = {}
	local folder = botsFolder()
	for _, model in if folder then folder:GetChildren() else {} do
		if model:IsA("Model") and type(model:GetAttribute("BotId")) == "number" then
			table.insert(list, model)
		end
	end
	return list
end

return Fighters
