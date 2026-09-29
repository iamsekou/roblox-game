-- Every fighter in a match is a Player, or (Training Grounds, 2026-09-29) a bot. Systems written for players look
-- fighters up here instead of Players:GetPlayerByUserId, and get either the Player or the bot's handle.
--
-- A bot handle deliberately reads like a Player where the game only reads (UserId, Name, DisplayName, Character,
-- Parent), so the fight code (abilities, punches, eliminations) runs unchanged for both. Everything that would
-- *send* to a client (FireClient, the movement check) asks isBot first: a bot's effects go to its own
-- controller (handle.onEffect) instead.
--
-- Bot ids never collide with real user ids (always positive) or Studio's local test players (-1, -2, ...):
-- they start at BOT_ID_BASE and go down. The id's sign is never used to tell them apart: ask isBot.
local Players = game:GetService("Players")

local FighterRegistry = {}

FighterRegistry.BOT_ID_BASE = -1000000

export type BotHandle = {
	UserId: number,
	Name: string,
	DisplayName: string,
	Character: Model?,
	Parent: Instance?, -- non-nil while the bot exists (like a Player still in the game)
	IsBot: boolean,
	fighter: string, -- the character it fights as
	onEffect: (payload: { [string]: any }) -> (), -- knockbacks, locks, blinds... (its controller applies them)
}

local bots: { [number]: BotHandle } = {}
local folder: Folder? = nil

function FighterRegistry.isBot(fighter: any): boolean
	return type(fighter) == "table" and fighter.IsBot == true
end

function FighterRegistry.registerBot(handle: BotHandle)
	bots[handle.UserId] = handle
end

function FighterRegistry.unregisterBot(id: number)
	local handle = bots[id]
	bots[id] = nil
	if handle then
		handle.Parent = nil
	end
end

function FighterRegistry.bot(id: number): BotHandle?
	return bots[id]
end

function FighterRegistry.bots(): { [number]: BotHandle }
	return bots
end

-- The Player or bot with this id (nil if neither).
function FighterRegistry.get(id: number): any
	return Players:GetPlayerByUserId(id) or bots[id]
end

function FighterRegistry.displayName(id: number): string?
	local fighter = FighterRegistry.get(id)
	return if fighter then fighter.DisplayName else nil
end

-- Bots' shown names by id (the round state carries them, so clients can label bots).
function FighterRegistry.botNames(): { [string]: string }
	local names = {}
	for id, handle in bots do
		names[tostring(id)] = handle.DisplayName
	end
	return names
end

-- Where bot bodies live: NAUWorld/Bots. Raycasts that ignore fighters ignore this folder too.
function FighterRegistry.folder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local world = workspace:FindFirstChild("NAUWorld") or workspace
	local existing = world:FindFirstChild("Bots")
	if existing and existing:IsA("Folder") then
		folder = existing
		return existing
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "Bots"
	newFolder.Parent = world
	folder = newFolder
	return newFolder
end

return FighterRegistry
