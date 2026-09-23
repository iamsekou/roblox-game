-- Yen balances and leaderstats.
-- Phase 2 keeps balances in memory only (they reset when a player leaves). Phase 3 moves them into
-- the DataStore-backed profile (session lock, retries, autosave) without changing this API.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local EconomyService = {}

local balances: { [Player]: number } = {}

-- Finds or creates a leaderstats IntValue. "Elims" is created first so the player list sorts by it.
function EconomyService.leaderstat(player: Player, name: string): IntValue
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end
	local value = stats:FindFirstChild(name)
	if not value then
		value = Instance.new("IntValue")
		value.Name = name
		value.Parent = stats
	end
	return value :: IntValue
end

local function push(player: Player)
	local amount = balances[player] or 0
	EconomyService.leaderstat(player, "Yen").Value = amount
	Remotes.UpdateCurrency:FireClient(player, { yen = amount })
end

function EconomyService.getBalance(player: Player): number
	return balances[player] or 0
end

-- Server-only. No remote can ask for yen; eliminations call this after the server verified them.
function EconomyService.award(player: Player, amount: number, _reason: string)
	if balances[player] == nil then
		return -- already left the game
	end
	assert(typeof(amount) == "number" and amount > 0 and amount % 1 == 0, "award amount must be a positive integer")
	balances[player] += amount
	push(player)
end

local function onPlayerAdded(player: Player)
	if balances[player] ~= nil then
		return
	end
	balances[player] = 0
	EconomyService.leaderstat(player, "Elims")
	push(player)
end

function EconomyService.Init()
	-- Reserved from the original scaffold; character purchases arrive in Phase 3.
	Remotes.PurchaseItem.OnServerInvoke = function()
		return { status = "coming_soon" }
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		balances[player] = nil
	end)
end

return EconomyService
