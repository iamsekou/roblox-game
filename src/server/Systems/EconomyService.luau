-- Yen balances, the character inventory, and leaderstats.
-- This service holds the live numbers for the session; ProfileService saves and restores them (applySaved,
-- and the balance/inventory listeners keep its copy current).
-- Purchases are decided in ShopService (rules in Lib/ShopRules); this service only holds the numbers.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local Currency = require(ReplicatedStorage.Shared.Modules.Currency)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local EconomyService = {}

local balances: { [Player]: number } = {}
local inventories: { [Player]: { [string]: boolean } } = {}
local passes: { [Player]: { [string]: boolean } } = {} -- Game Pass characters (never saved: Roblox is the record)
local inventoryListeners: { (Player) -> () } = {}
local balanceListeners: { (Player, number) -> () } = {}

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
	EconomyService.leaderstat(player, Currency.STAT).Value = amount
	Remotes.UpdateCurrency:FireClient(player, { yen = amount })
	for _, listener in balanceListeners do
		task.spawn(listener, player, amount)
	end
end

-- Called with (player, balance) whenever a balance changes (ProfileService keeps the save current).
function EconomyService.onBalanceChanged(listener: (Player, number) -> ())
	table.insert(balanceListeners, listener)
end

-- Every character this player bought for yen.
function EconomyService.boughtList(player: Player): { string }
	local list = {}
	for id in inventories[player] or {} do
		table.insert(list, id)
	end
	table.sort(list)
	return list
end

-- Saved progress arrived (ProfileService): add the saved yen to anything earned while it loaded, and the
-- saved purchases to the inventory.
function EconomyService.applySaved(player: Player, yen: number, owned: { string })
	if balances[player] == nil then
		return -- already left
	end
	balances[player] += math.max(0, math.floor(yen))
	EconomyService.grant(player, owned)
	push(player)
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

-- Server-only. Takes `amount` if the player has it; false (nothing taken) if not.
function EconomyService.spend(player: Player, amount: number): boolean
	local balance = balances[player]
	if balance == nil or typeof(amount) ~= "number" or amount <= 0 or amount % 1 ~= 0 or balance < amount then
		return false
	end
	balances[player] = balance - amount
	push(player)
	return true
end

-- Characters bought for yen (free starters and Studio unlocks are decided by AbilityService, not stored).
function EconomyService.hasBought(player: Player, id: string): boolean
	local inventory = inventories[player]
	return inventory ~= nil and inventory[id] == true
end

function EconomyService.grant(player: Player, ids: { string })
	local inventory = inventories[player]
	if not inventory then
		return
	end
	for _, id in ids do
		inventory[id] = true
	end
	for _, listener in inventoryListeners do
		task.spawn(listener, player)
	end
end

-- A Robux character's Game Pass (RobuxService: owned when they joined, or just bought). Kept for the session
-- only and never saved; Roblox is asked again on every join.
function EconomyService.grantPass(player: Player, id: string)
	local owned = passes[player]
	if not owned or owned[id] then
		return
	end
	owned[id] = true
	for _, listener in inventoryListeners do
		task.spawn(listener, player)
	end
end

function EconomyService.hasPass(player: Player, id: string): boolean
	local owned = passes[player]
	return owned ~= nil and owned[id] == true
end

-- Called with the player whenever their inventory changes (AbilityService re-sends their owned list).
function EconomyService.onInventoryChanged(listener: (Player) -> ())
	table.insert(inventoryListeners, listener)
end

local function onPlayerAdded(player: Player)
	if balances[player] ~= nil then
		return
	end
	balances[player] = 0
	inventories[player] = {}
	passes[player] = {}
	EconomyService.leaderstat(player, "Elims")
	push(player)
	-- Studio-only test hook: set this number attribute on a Player to grant that much yen. Ignored live.
	if RunService:IsStudio() then
		local attribute = Constants.DEV_GRANT_YEN_ATTRIBUTE
		player:GetAttributeChangedSignal(attribute):Connect(function()
			local amount = player:GetAttribute(attribute)
			if typeof(amount) == "number" and amount >= 1 and amount % 1 == 0 then
				player:SetAttribute(attribute, nil)
				EconomyService.award(player, amount, "studio test grant")
			end
		end)
	end
end

function EconomyService.Init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		balances[player] = nil
		inventories[player] = nil
		passes[player] = nil
	end)
end

return EconomyService
