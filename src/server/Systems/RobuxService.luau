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

-- Asks Roblox whether the player owns `passId`, retrying failed requests. Returns (answered, owns, error).
local function ownsPass(player: Player, passId: number): (boolean, boolean, string?)
	local lastError = nil
	for attempt = 1, Constants.GAMEPASS_CHECK_ATTEMPTS do
		local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
		if ok then
			return true, owns == true, nil
		end
		lastError = tostring(owns)
		if not player.Parent then
			return false, false, lastError
		end
		if attempt < Constants.GAMEPASS_CHECK_ATTEMPTS then
			task.wait(Constants.GAMEPASS_CHECK_RETRY_SECONDS)
		end
	end
	return false, false, lastError
end

local function checkPasses(player: Player)
	local failed = {}
	local lastError = nil
	for passId, def in byPassId do
		local answered, owns, err = ownsPass(player, passId)
		if not player.Parent then
			return
		end
		if answered and owns then
			EconomyService.grantPass(player, def.id)
		elseif not answered then
			table.insert(failed, def.name)
			lastError = err
		end
	end
	-- One line per player, not one per pass per attempt (Studio's test players can't be looked up at all).
	if #failed > 0 then
		warn(string.format("[NAU] couldn't check %s's passes (%s): %s", player.Name, table.concat(failed, ", "), tostring(lastError)))
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
	-- A pass bought in game. The event is only the trigger (audit fix, 2026-09-28): the grant waits for Roblox to
	-- confirm the player really owns the pass, so a forged "purchased" event can't unlock a Robux character.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		local def = byPassId[passId]
		if not purchased or not def then
			return
		end
		task.spawn(function()
			local answered, owns, err = ownsPass(player, passId)
			-- Should Roblox still answer from before the purchase, ask again a few times.
			for _ = 1, Constants.GAMEPASS_CHECK_ATTEMPTS do
				if not answered or owns or not player.Parent then
					break
				end
				task.wait(Constants.GAMEPASS_CHECK_RETRY_SECONDS)
				answered, owns, err = ownsPass(player, passId)
			end
			if answered and owns then
				EconomyService.grantPass(player, def.id)
			elseif not answered and player.Parent then
				-- Roblox is the record: the pass is checked again on the player's next join.
				warn(string.format("[NAU] couldn't confirm %s's %s purchase: %s", player.Name, def.name, tostring(err)))
			end
		end)
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
