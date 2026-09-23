-- Yen balances, the character inventory, and leaderstats.
-- Everything is in memory for now (it resets when a player leaves). Saved progress (Phase 3 item 4) moves
-- it into a DataStore-backed profile (session lock, retries, autosave) without changing this API.
-- Purchases are decided in ShopService (rules in Lib/ShopRules); this service only holds the numbers.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local EconomyService = {}

local balances: { [Player]: number } = {}
local inventories: { [Player]: { [string]: boolean } } = {}
local inventoryListeners: { (Player) -> () } = {}

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
	end)
end

return EconomyService
