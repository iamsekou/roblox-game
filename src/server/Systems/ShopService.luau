-- The yen shop (Phase 3 item 5, approved 2026-09-23). Clients only *request* a character by id through
-- PurchaseItem; the server checks it against Lib/ShopRules (sold for yen? already owned? enough yen?), takes
-- the yen and grants the character plus every cheaper yen tier. The check, the spend and the grant happen
-- with no yield in between, so two quick clicks can't buy twice or overspend.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterDefs = require(ReplicatedStorage.Shared.Modules.CharacterDefs)
local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)
local ShopRules = require(script.Parent.Parent.Lib.ShopRules)
local EconomyService = require(script.Parent.EconomyService)
local AbilityService = require(script.Parent.AbilityService)

local ShopService = {}

local requests = RateLimiter.new(Constants.PURCHASE_MIN_INTERVAL)

local function handlePurchase(player: Player, id: any)
	if not RateLimiter.allow(requests, player, os.clock()) then
		return { status = "rate_limited", yen = EconomyService.getBalance(player) }
	end
	local owned: { [string]: boolean } = {}
	for _, def in CharacterDefs.list do
		if AbilityService.owns(player, def.id) then
			owned[def.id] = true
		end
	end
	local verdict = ShopRules.check(id, CharacterDefs.list, owned, EconomyService.getBalance(player))
	if verdict.status ~= "ok" then
		return { status = verdict.status, price = verdict.price, yen = EconomyService.getBalance(player) }
	end
	local grants = verdict.grants :: { string }
	if not EconomyService.spend(player, verdict.price :: number) then
		return { status = "insufficient", price = verdict.price, yen = EconomyService.getBalance(player) }
	end
	EconomyService.grant(player, grants)
	if RunService:IsStudio() then
		print(string.format("[NAU] shop: %s bought %s for %d yen (granted %s)", player.Name, tostring(id), verdict.price :: number, table.concat(grants, ", ")))
	end
	return { status = "bought", granted = grants, yen = EconomyService.getBalance(player) }
end

function ShopService.Init()
	Remotes.PurchaseItem.OnServerInvoke = handlePurchase
	Players.PlayerRemoving:Connect(function(player)
		RateLimiter.forget(requests, player)
	end)
end

return ShopService
