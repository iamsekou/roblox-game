-- Robux purchases (Phase 3 item 6 + credit bundles, approved 2026-09-23; owner's ids 2026-09-24).
--
--   Game Passes    Robux characters (CharacterDefs gamePassId). On join the server asks Roblox whether the
--                  player owns each pass; a pass bought in game counts at once. Ownership is never saved: Roblox
--                  is the record, and it's asked again on every join.
--   Credit bundles Developer Products (Modules/RobuxCatalog). ProcessReceipt credits the bundle and saves it with
--                  the receipt id before telling Roblox it was granted (ProfileService.creditPurchase), so a
--                  bundle is never paid twice or lost. Anything unsaved answers NotProcessedYet: Roblox retries.
--
-- Clients open Roblox's purchase prompts themselves; the server grants only what Roblox reports as bought.
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local CharacterDefs = require(ReplicatedStorage.Shared.Modules.CharacterDefs)
local RobuxCatalog = require(ReplicatedStorage.Shared.Modules.RobuxCatalog)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local EconomyService = require(script.Parent.EconomyService)
local ProfileService = require(script.Parent.ProfileService)

local RobuxService = {}

local byPassId: { [number]: any } = {}
for _, def in CharacterDefs.list do
	if def.tier == "Robux" and def.gamePassId then
		byPassId[def.gamePassId] = def
	end
end

-- Game Passes ------------------------------------------------------------------------------------

local function checkPasses(player: Player)
	for passId, def in byPassId do
		for attempt = 1, Constants.GAMEPASS_CHECK_ATTEMPTS do
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
			if ok then
				if owns then
					EconomyService.grantPass(player, def.id)
				end
				break
			end
			if not player.Parent then
				return
			end
			if attempt < Constants.GAMEPASS_CHECK_ATTEMPTS then
				task.wait(Constants.GAMEPASS_CHECK_RETRY_SECONDS)
			else
				warn(string.format("[NAU] couldn't check %s's %s pass: %s", player.Name, def.name, tostring(owns)))
			end
		end
	end
end

-- Credit bundles ---------------------------------------------------------------------------------

local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local bundle = RobuxCatalog.byProductId[info.ProductId]
	if not bundle then
		warn(string.format("[NAU] receipt for unknown product %s: left unprocessed", tostring(info.ProductId)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- not in this server: credited when they're back
	end
	local result = ProfileService.creditPurchase(player, tostring(info.PurchaseId), bundle.yen)
	if result == "granted" then
		Remotes.IncomeNotice:FireClient(player, { source = "purchase", amount = bundle.yen })
		return Enum.ProductPurchaseDecision.PurchaseGranted
	elseif result == "duplicate" then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- Studio-only test switch (Constants.DEV_RECEIPT_ATTRIBUTE): a fake receipt through the real path. Roblox's
-- purchase dialog can't be driven by Studio's test automation, so this is how the credit and save are tested.
local function watchDevReceipts(player: Player)
	local attribute = Constants.DEV_RECEIPT_ATTRIBUTE
	player:GetAttributeChangedSignal(attribute):Connect(function()
		local value = player:GetAttribute(attribute)
		if type(value) ~= "string" then
			return
		end
		player:SetAttribute(attribute, nil)
		local productId, purchaseId = value:match("^(%d+):?(.*)$")
		if not productId then
			return
		end
		if purchaseId == "" then
			purchaseId = "studio-test-" .. HttpService:GenerateGUID(false)
		end
		task.spawn(function()
			local decision = processReceipt({ PlayerId = player.UserId, ProductId = tonumber(productId), PurchaseId = purchaseId })
			player:SetAttribute(Constants.DEV_RECEIPT_RESULT_ATTRIBUTE, decision.Name .. " " .. purchaseId)
		end)
	end)
end

function RobuxService.Init()
	MarketplaceService.ProcessReceipt = processReceipt
	-- Fired on the server by Roblox (not by a client), so `purchased` can be trusted.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		local def = byPassId[passId]
		if purchased and def then
			EconomyService.grantPass(player, def.id)
		end
	end)
	local function onPlayerAdded(player: Player)
		task.spawn(checkPasses, player)
		if RunService:IsStudio() then
			watchDevReceipts(player)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return RobuxService
