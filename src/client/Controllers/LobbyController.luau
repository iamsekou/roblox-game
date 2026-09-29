-- Lobby UI: the FIGHT button with live queue status, plus podium inspection cards.
-- The FIGHT portal's ProximityPrompt uses exactly the same request path as the button.
-- The inspection card is also a place to buy (owner, 2026-09-29: "it shouldn't only be the shop but both"): a
-- fighter you don't own can be bought right there, through exactly the shop's paths (PurchaseItem for credits,
-- which the server checks and charges; Roblox's Game Pass prompt for the Robux fighters). A credit purchase asks
-- for a second tap to confirm; short of credits, the button offers the smallest bundle that covers the gap.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local CharacterDefs = require(Shared:WaitForChild("Modules"):WaitForChild("CharacterDefs"))
local Constants = require(Shared:WaitForChild("Modules"):WaitForChild("Constants"))
local Currency = require(Shared:WaitForChild("Modules"):WaitForChild("Currency"))
local RobuxCatalog = require(Shared:WaitForChild("Modules"):WaitForChild("RobuxCatalog"))
local UIMotion = require(ReplicatedStorage:WaitForChild("Animations"):WaitForChild("Controllers"):WaitForChild("UIMotion"))
local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"))
local Audio = require(Client:WaitForChild("Audio"))
local HUDController = require(script.Parent:WaitForChild("HUDController"))

local LobbyController = {}

local localPlayer = Players.LocalPlayer
local XP_NUMERALS = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }

-- Every server answer gets a visible explanation; nothing fails silently.
local MESSAGES: { [string]: { string } } = {
	joined = { "Dropping into the fight!", "good" },
	rate_limited = { "One moment...", "info" },
	queued = { "You're queued. The round starts when enough fighters are ready.", "info" },
	queued_round_ending = { "This round is wrapping up. You're queued for the next one.", "info" },
	queued_match_full = { "The match is full (12/12). You'll drop in as soon as a slot opens.", "info" },
	already_queued = { "You're already queued.", "info" },
	already_in_match = { "You're already in the fight.", "info" },
	queue_full = { "The next round is full. Try again once it starts.", "bad" },
	left_queue = { "You left the queue.", "info" },
	not_queued = { "You weren't in the queue.", "info" },
}

local refs: { [string]: any } = {}
local busy = false
local refreshCardAction: () -> ()
local equipShown: () -> ()


local function call(remote: RemoteFunction)
	if busy then
		return
	end
	busy = true
	local ok, result = pcall(function()
		return remote:InvokeServer()
	end)
	busy = false
	if not ok or type(result) ~= "table" then
		HUDController.toast("Couldn't reach the server. Try again.", "bad")
		return
	end
	local message = MESSAGES[result.status]
	if message then
		HUDController.toast(message[1], message[2])
	end
end

local function requestFight()
	UIMotion.punch(refs.fight.button)
	call(Remotes.RequestFight)
end

local function leaveQueue()
	call(Remotes.LeaveQueue)
end

local CONFIRM_SECONDS = 3 -- a credit purchase waits this long for its confirming second tap
local confirm: { def: any, untilAt: number }? = nil
local pendingPass: { id: string, token: number }? = nil
local passToken = 0
local livePassPrice: { [number]: number } = {} -- Game Pass id -> the price Roblox reports

local function balance(): number
	local stats = localPlayer:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild(Currency.STAT)
	return if value and value:IsA("IntValue") then value.Value else 0
end

local function owns(def: any): boolean
	local ownedList = ClientState.ability.owned
	return type(ownedList) == "table" and table.find(ownedList, def.id) ~= nil -- server's list (all, in Studio)
end

local function passPrice(def: any): number?
	return if def.gamePassId and livePassPrice[def.gamePassId] then livePassPrice[def.gamePassId] else def.robuxPrice
end

-- The smallest credit bundle that covers `short` credits (the biggest one if none does).
local function bundleFor(short: number): RobuxCatalog.Bundle?
	local best = nil
	for _, bundle in RobuxCatalog.bundles do
		if bundle.yen >= short and (not best or bundle.yen < best.yen) then
			best = bundle
		end
	end
	if not best then
		for _, bundle in RobuxCatalog.bundles do
			if not best or bundle.yen > best.yen then
				best = bundle
			end
		end
	end
	return best
end

-- What the card's button does for this fighter right now.
local function cardMode(def: any): string
	if ClientState.ability.equipped == def.id then
		return "equipped"
	elseif owns(def) then
		return "equip"
	elseif def.tier == "Robux" then
		return if pendingPass and pendingPass.id == def.id then "pending" elseif def.gamePassId then "pass" else "unavailable"
	elseif def.tier == "Yen" then
		if balance() < (def.yenPrice or 0) then
			return "credits"
		end
		return if confirm and confirm.def == def and os.clock() < confirm.untilAt then "confirm" else "buy"
	end
	return "unavailable"
end

-- The card's action: EQUIP what you own; BUY (credits or Robux) what you don't.
refreshCardAction = function()
	local def = refs.cardDef
	if not def or not refs.cardAction then
		return
	end
	local mode = cardMode(def)
	local active = mode ~= "equipped" and mode ~= "pending" and mode ~= "unavailable"
	local text
	if mode == "equipped" then
		text = "EQUIPPED"
	elseif mode == "equip" then
		text = "EQUIP"
	elseif mode == "buy" then
		text = "BUY · " .. Currency.amount(UI.formatNumber(def.yenPrice))
	elseif mode == "confirm" then
		text = "TAP AGAIN TO BUY · " .. Currency.amount(UI.formatNumber(def.yenPrice))
	elseif mode == "credits" then
		local short = (def.yenPrice or 0) - balance()
		local bundle = bundleFor(short)
		text = string.format("NEED %s · GET MORE%s", Currency.amount(UI.formatNumber(short)), if bundle then " (R$ " .. UI.formatNumber(bundle.robux) .. ")" else "")
	elseif mode == "pass" then
		local price = passPrice(def)
		text = if price then "BUY WITH ROBUX · R$ " .. UI.formatNumber(price) else "BUY WITH ROBUX"
	elseif mode == "pending" then
		text = "WAITING FOR ROBLOX…"
	else
		text = "NOT FOR SALE"
	end
	refs.cardAction.Text = text
	refs.cardAction.AutoButtonColor = active
	refs.cardAction.BackgroundColor3 = if mode == "equip" then UI.Colors.Accent
		elseif mode == "buy" or mode == "pass" then Color3.fromRGB(150, 118, 48)
		elseif mode == "confirm" then UI.Colors.Gold
		elseif mode == "credits" then UI.Colors.Info
		else UI.Colors.Slot
	refs.cardAction.TextColor3 = if mode == "confirm" then UI.Colors.Ink elseif active or mode == "equipped" then UI.Colors.Text else UI.Colors.Muted
end

-- A credit purchase through the server (it checks the price, charges, and unlocks lower tiers too).
local function buyShown(def: any)
	busy = true
	local ok, result = pcall(function()
		return Remotes.PurchaseItem:InvokeServer(def.id)
	end)
	busy = false
	confirm = nil
	if not ok or type(result) ~= "table" then
		HUDController.toast("Couldn't reach the server. Try again.", "bad")
	elseif result.status == "bought" then
		Audio.play("shop_purchase")
		local extra = if type(result.granted) == "table" then #result.granted - 1 else 0
		HUDController.toast(string.format("%s unlocked%s! Tap EQUIP to fight as them.", def.name,
			if extra > 0 then string.format(" (+%d cheaper fighter%s)", extra, if extra == 1 then "" else "s") else ""), "good")
		UIMotion.pop(refs.card)
	elseif result.status == "insufficient" then
		HUDController.toast("Not enough credits yet", "bad")
	elseif result.status == "owned" then
		HUDController.toast("You already own that fighter", "info")
	elseif result.status == "rate_limited" then
		HUDController.toast("One moment...", "info")
	else
		HUDController.toast("That fighter can't be bought with credits", "info")
	end
	refreshCardAction()
end

local function pressCardAction()
	local def = refs.cardDef
	if busy or not def then
		return
	end
	local mode = cardMode(def)
	if mode == "equip" then
		task.spawn(equipShown)
	elseif mode == "buy" then
		confirm = { def = def, untilAt = os.clock() + CONFIRM_SECONDS }
		refreshCardAction()
		UIMotion.pop(refs.cardAction)
		task.delay(CONFIRM_SECONDS, refreshCardAction)
	elseif mode == "confirm" then
		task.spawn(buyShown, def)
	elseif mode == "credits" then
		local bundle = bundleFor((def.yenPrice or 0) - balance())
		if bundle then
			if RunService:IsStudio() then
				print(string.format("[NAU] card: prompting credit bundle %d (%d YC, R$ %d) for %s", bundle.productId, bundle.yen, bundle.robux, def.name))
			end
			MarketplaceService:PromptProductPurchase(localPlayer, bundle.productId)
		end
	elseif mode == "pass" then
		passToken += 1
		local token = passToken
		pendingPass = { id = def.id, token = token }
		refreshCardAction()
		if RunService:IsStudio() then
			print(string.format("[NAU] card: prompting Game Pass %d for %s", def.gamePassId, def.name))
		end
		MarketplaceService:PromptGamePassPurchase(localPlayer, def.gamePassId)
		-- Should Roblox never report the prompt closed, the button comes back.
		task.delay(Constants.GAMEPASS_PROMPT_TIMEOUT, function()
			if pendingPass and pendingPass.token == token then
				pendingPass = nil
				refreshCardAction()
			end
		end)
	end
end

function equipShown()
	local def = refs.cardDef
	local ownedList = ClientState.ability.owned
	local owned = def and type(ownedList) == "table" and table.find(ownedList, def.id) ~= nil
	if busy or not def or not owned or ClientState.ability.equipped == def.id then
		return
	end
	busy = true
	local ok, result = pcall(function()
		return Remotes.EquipCharacter:InvokeServer(def.id)
	end)
	busy = false
	if not ok or type(result) ~= "table" then
		HUDController.toast("Couldn't reach the server. Try again.", "bad")
	elseif result.status == "equipped" then
		HUDController.toast(string.format("%s equipped", def.name), "good")
	elseif result.status == "in_fight" then
		HUDController.toast("You can switch in the lobby or while waiting to respawn", "info")
	elseif result.status == "not_owned" then
		HUDController.toast("You don't own that fighter yet", "info")
	end
end

-- The fighter's XP on the card: "PRESTIGE II · LEVEL 7 · 8,400 / 11,000 XP".
local function xpLine(def: any): string
	local xp = ClientState.xpOf(def.id)
	return string.format(
		"%sLEVEL %d  ·  %s",
		if xp.p > 0 then "PRESTIGE " .. (XP_NUMERALS[xp.p] or tostring(xp.p)) .. "  ·  " else "",
		xp.l,
		if xp.full then "READY TO PRESTIGE" else string.format("%s / %s XP", UI.formatNumber(xp.x), UI.formatNumber(xp.need))
	)
end

local function showCard(def: any)
	refs.cardAccent.BackgroundColor3 = def.accent
	refs.cardName.Text = def.name
	refs.cardEpithet.Text = xpLine(def) -- franchise names used to sit here; they aren't shown in game
	if def.tier == "Free" then
		refs.cardTier.Text = "FREE STARTER · already yours"
	elseif def.tier == "Yen" then
		refs.cardTier.Text = string.format("%s · tier %d", Currency.amount(UI.formatNumber(def.yenPrice)), def.yenTier)
	else
		local price = passPrice(def)
		refs.cardTier.Text = if price then string.format("Robux pass · R$ %s", UI.formatNumber(price)) else "Robux pass"
	end
	refs.cardIdentity.Text = def.identity
	refs.cardAbilities.Text = string.format("Q  %s    E  %s", string.upper(def.abilities.mild), string.upper(def.abilities.ultimate))
	if refs.cardDef ~= def then
		confirm = nil -- a pending confirmation never carries over to another fighter
	end
	refs.cardDef = def
	refreshCardAction()
	refs.card.Visible = true
	UIMotion.pop(refs.card)
end

local function buildCard(gui: ScreenGui)
	local card = UI.new("Frame", {
		Name = "InspectCard",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(300, if UI.isTouch() then 266 else 262),
		BackgroundColor3 = UI.Colors.Panel,
		BackgroundTransparency = 0.04,
		Visible = false,
		Parent = gui,
	}, { UI.corner(14), UI.stroke(Color3.new(1, 1, 1), 1, 0.8), UI.padding(14) })
	refs.card = card
	refs.cardAccent = UI.new("Frame", {
		Size = UDim2.new(1, 0, 0, 4),
		BorderSizePixel = 0,
		BackgroundColor3 = UI.Colors.Accent,
		Parent = card,
	}, { UI.corner(2) })
	refs.cardName = UI.label({
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.new(1, if UI.isTouch() then -44 else -30, 0, 28), -- clear of the close button
		TextSize = 24,
		Font = UI.FontHeavy,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	refs.cardEpithet = UI.label({
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = 14,
		TextColor3 = UI.Colors.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	refs.cardTier = UI.label({
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 17,
		TextColor3 = UI.Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	refs.cardIdentity = UI.label({
		Position = UDim2.fromOffset(0, 94),
		Size = UDim2.new(1, 0, 0, 44),
		TextSize = 15,
		Font = UI.FontBody,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})
	refs.cardAbilities = UI.label({
		Position = UDim2.fromOffset(0, 146),
		Size = UDim2.new(1, 0, 0, 36),
		TextSize = 14,
		Font = UI.Font,
		TextColor3 = UI.Colors.Muted,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})
	refs.cardAction = UI.button({
		Name = "Action",
		Position = UDim2.fromOffset(0, 190),
		Size = UDim2.new(1, 0, 0, if UI.isTouch() then 44 else 40), -- 44: minimum touch target
		Font = UI.FontHeavy,
		TextSize = 17,
		Parent = card,
	})
	refs.cardAction.Activated:Connect(pressCardAction)
	local closeButton = UI.button({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, if UI.isTouch() then 6 else 0, 0, if UI.isTouch() then 2 else 10),
		Size = if UI.isTouch() then UDim2.fromOffset(44, 44) else UDim2.fromOffset(28, 28),
		Text = "X",
		TextSize = 16,
		Parent = card,
	}, { UI.corner(14) })
	closeButton.Activated:Connect(function()
		card.Visible = false
		confirm = nil
	end)
end

local function build()
	local gui = UI.screen("NAU_Lobby", 3)
	local touch = UI.isTouch()
	-- The lobby's calls to action (owner, 2026-09-30: moved to the bottom-left and restyled; the comic "FIGHT!"
	-- button and the separate TRAINING tab above it were retired): one stack of slabs in the HUD's own style, the
	-- round status on top, FIGHT, LEAVE QUEUE while queued, then TRAINING (TrainingController adds it through
	-- LobbyController.actionStack). On touch it sits higher, clear of the movement thumbstick's corner.
	local holder = UI.new("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(0, 1),
		Position = if touch then UDim2.new(0, 16, 1, -110) else UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(if touch then 250 else 280, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		UI.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
	})
	refs.holder = holder
	refs.status = UI.label({
		Name = "Status",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = UI.Font,
		TextSize = 13,
		TextColor3 = UI.Colors.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		TextStrokeTransparency = 0.6,
		Parent = holder,
	})
	refs.fight = UI.actionButton({
		name = "Fight",
		title = "FIGHT",
		caption = "ENTER THE ARENA",
		glyph = "»",
		accent = UI.Colors.Accent,
		height = if touch then 64 else 68,
		order = 2,
		parent = holder,
	})
	refs.leave = UI.button({
		Name = "LeaveQueue",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, if touch then 44 else 26), -- 44: touch target
		BackgroundColor3 = UI.Colors.Ink,
		BackgroundTransparency = 0.2,
		Font = UI.Font,
		TextSize = if touch then 15 else 13,
		TextColor3 = UI.Colors.Muted,
		Text = "LEAVE QUEUE",
		Visible = false,
		Parent = holder,
	}, { UI.corner() })
	refs.fight.button.Activated:Connect(requestFight)
	refs.leave.Activated:Connect(leaveQueue)
	buildCard(gui)
end

-- The stack the lobby's calls to action live in (TrainingController adds TRAINING to it).
function LobbyController.actionStack(): Frame
	return refs.holder
end

local function refresh()
	local r = ClientState.round
	local inMatch = ClientState.isParticipant()
	-- Training Grounds have no lobby queue: the training controller has its own buttons. The stack also steps aside
	-- while a fighter card is open (both live on the left).
	refs.holder.Visible = not inMatch and not ClientState.isTraining() and not refs.card.Visible
	if inMatch or ClientState.isTraining() then
		refs.card.Visible = false
		return
	end
	if not r then
		refs.status.Text = "Connecting..."
		return
	end
	local queued = ClientState.isQueued()
	refs.fight.title.Text = if queued then "QUEUED" else "FIGHT"
	refs.fight.caption.Text = if queued then "WAITING FOR THE ROUND" else "ENTER THE ARENA"
	UI.setActionAccent(refs.fight, if queued then UI.Colors.Line else UI.Colors.Accent) -- steel while queued
	refs.leave.Visible = queued

	local t = workspace:GetServerTimeNow()
	local nQueued = #(r.queued or {})
	local nFighting = #(r.participants or {})
	local maxPlayers = r.maxPlayers or 12
	if r.phase == "Waiting" then
		refs.status.Text = string.format("Waiting for fighters (%d/%d)", nQueued, r.minPlayers or 2)
	elseif r.phase == "Intermission" then
		refs.status.Text = string.format(
			"Round starts in %ds · %d/%d queued",
			math.max(0, math.ceil((r.endsAt or t) - t)),
			nQueued,
			maxPlayers
		)
	elseif r.phase == "InRound" then
		refs.status.Text = if nFighting >= maxPlayers
			then string.format("Battle full (%d/%d) · FIGHT takes the next open slot", nFighting, maxPlayers)
			else string.format("Battle in progress (%d/%d) · FIGHT to drop in", nFighting, maxPlayers)
	else
		refs.status.Text = "Round ending · FIGHT to queue for the next one"
	end
end

function LobbyController.Start()
	build()
	refs.card:GetPropertyChangedSignal("Visible"):Connect(refresh) -- the stack hides while a card is open
	ClientState.Changed:Connect(function(kind)
		refresh()
		if kind == "ability" then
			-- A purchase or a confirmed Game Pass changes the owned list.
			if pendingPass and refs.cardDef and pendingPass.id == refs.cardDef.id and owns(refs.cardDef) then
				pendingPass = nil
				HUDController.toast(string.format("%s unlocked! Tap EQUIP to fight as them.", refs.cardDef.name), "good")
			end
			refreshCardAction()
		elseif kind == "xp" and refs.cardDef and refs.card.Visible then
			refs.cardEpithet.Text = xpLine(refs.cardDef)
		end
	end)
	-- The card's price follows the balance (a bundle, an elimination, a purchase).
	task.spawn(function()
		local stats = localPlayer:WaitForChild("leaderstats", 30)
		local value = stats and stats:WaitForChild(Currency.STAT, 30)
		if value and value:IsA("IntValue") then
			value.Changed:Connect(refreshCardAction)
		end
	end)
	-- A Game Pass prompt closed: not bought → the button comes back; bought → wait for the server's grant.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, _passId, purchased)
		if player == localPlayer and pendingPass and not purchased then
			pendingPass = nil
			refreshCardAction()
		end
	end)
	-- Live Robux prices for the passes (the defs hold only a fallback).
	task.spawn(function()
		for _, def in CharacterDefs.list do
			if def.gamePassId then
				local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, def.gamePassId, Enum.InfoType.GamePass)
				if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
					livePassPrice[def.gamePassId] = info.PriceInRobux
				end
			end
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if player ~= localPlayer then
			return
		end
		if prompt:GetAttribute("Action") == "Fight" then
			requestFight()
			return
		end
		local id = prompt:GetAttribute("CharacterId")
		local def = if type(id) == "string" then CharacterDefs.byId[id] else nil
		if def then
			showCard(def)
		end
	end)
	task.spawn(function()
		while true do
			pcall(refresh)
			task.wait(0.25)
		end
	end)
end

return LobbyController
