-- Lobby UI: the FIGHT button with live queue status, plus podium inspection cards.
-- The FIGHT portal's ProximityPrompt uses exactly the same request path as the button.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local CharacterDefs = require(Shared:WaitForChild("Modules"):WaitForChild("CharacterDefs"))
local UIMotion = require(ReplicatedStorage:WaitForChild("Animations"):WaitForChild("Controllers"):WaitForChild("UIMotion"))
local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"))
local HUDController = require(script.Parent:WaitForChild("HUDController"))

local LobbyController = {}

local localPlayer = Players.LocalPlayer

-- Every server answer gets a visible explanation; nothing fails silently.
local MESSAGES: { [string]: { string } } = {
	joined = { "Dropping into the fight!", "good" },
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

-- FIGHT button looks: hot red when ready, cold steel once you're queued.
local FIGHT_READY = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 96, 40)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(214, 20, 36)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 6, 20)),
})
local FIGHT_QUEUED = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 130, 150)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(44, 50, 64)),
})

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
	UIMotion.punch(refs.holder) -- the container, so it doesn't fight the button's own idle pulse
	call(Remotes.RequestFight)
end

local function leaveQueue()
	call(Remotes.LeaveQueue)
end

local function showCard(def: any)
	refs.cardAccent.BackgroundColor3 = def.accent
	refs.cardName.Text = def.name
	refs.cardEpithet.Text = def.franchise or ""
	if def.tier == "Free" then
		refs.cardTier.Text = "FREE STARTER · already yours"
	elseif def.tier == "Yen" then
		refs.cardTier.Text = string.format("¥ %s · yen tier %d", UI.formatNumber(def.yenPrice), def.yenTier)
	else
		refs.cardTier.Text = "Robux pass · price announced later"
	end
	refs.cardIdentity.Text = def.identity
	refs.card.Visible = true
	UIMotion.pop(refs.card)
end

local function buildCard(gui: ScreenGui)
	local card = UI.new("Frame", {
		Name = "InspectCard",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(300, 262),
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
		Size = UDim2.new(1, -30, 0, 28),
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
	UI.label({
		Position = UDim2.fromOffset(0, 142),
		Size = UDim2.new(1, 0, 0, 36),
		TextSize = 13,
		Font = UI.FontBody,
		TextColor3 = UI.Colors.Muted,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "Abilities: a mild (8s) and an ultimate (20s), revealed once the ability sheet is approved.",
		Parent = card,
	})
	UI.button({
		Position = UDim2.fromOffset(0, 190),
		Size = UDim2.new(1, 0, 0, 40),
		AutoButtonColor = false,
		BackgroundColor3 = UI.Colors.Slot,
		TextColor3 = UI.Colors.Muted,
		Text = "Unlocks coming soon",
		Parent = card,
	}, { UI.corner(10) })
	local closeButton = UI.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 10),
		Size = UDim2.fromOffset(28, 28),
		Text = "X",
		TextSize = 16,
		Parent = card,
	}, { UI.corner(14) })
	closeButton.Activated:Connect(function()
		card.Visible = false
	end)
end

local function build()
	local gui = UI.screen("NAU_Lobby", 3)
	local holder = UI.new("Frame", {
		Name = "FightHolder",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(240, 112),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	refs.holder = holder
	-- Smaller, angrier FIGHT button: hot gradient, heavy black outline, comic-impact lettering
	-- tilted like it's mid-swing. Motion (pulse, light sweep, press punch) comes from UIMotion.
	-- The gradient lives on the plate behind the text (a UIGradient would also tint the lettering),
	-- and only the lettering is tilted: Roblox doesn't clip children of a rotated frame, and the
	-- light sweep has to stay inside the plate.
	refs.fightGradient = UI.new("UIGradient", { Color = FIGHT_READY, Rotation = 90 })
	refs.fight = UI.new("Frame", {
		Name = "FightButton",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(230, 58),
		ClipsDescendants = true,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = holder,
	}, {
		UI.corner(8),
		refs.fightGradient,
		UI.new("UIStroke", { Color = Color3.fromRGB(20, 0, 4), Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	})
	refs.fightShine = UI.new("Frame", {
		Name = "Shine",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(-0.3, 0.5),
		Size = UDim2.new(0, 26, 2, 0),
		Rotation = 20,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.65,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = refs.fight,
	})
	refs.fightText = UI.button({
		Name = "Hit",
		Size = UDim2.fromScale(1, 1),
		Rotation = -4,
		ZIndex = 2,
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Font = Enum.Font.Bangers,
		TextSize = 48,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeColor3 = Color3.fromRGB(20, 0, 4),
		TextStrokeTransparency = 0,
		Text = "FIGHT!",
		Parent = refs.fight,
	})
	UIMotion.pulse(refs.fight, 0.05, 0.9)
	UIMotion.sweep(refs.fightShine, 2.4)

	refs.status = UI.label({
		Name = "Status",
		Position = UDim2.fromOffset(-60, 64),
		Size = UDim2.new(1, 120, 0, 20),
		TextSize = 14,
		TextStrokeTransparency = 0.4,
		Parent = holder,
	})
	refs.leave = UI.button({
		Name = "LeaveQueue",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 88),
		Size = UDim2.fromOffset(120, 22),
		BackgroundColor3 = UI.Colors.Ink,
		BackgroundTransparency = 0.25,
		TextSize = 12,
		Text = "Leave queue",
		Visible = false,
		Parent = holder,
	}, { UI.corner(8) })
	refs.fightText.Activated:Connect(requestFight)
	refs.leave.Activated:Connect(leaveQueue)
	buildCard(gui)
end

local function refresh()
	local r = ClientState.round
	local inMatch = ClientState.isParticipant()
	refs.holder.Visible = not inMatch
	if inMatch then
		refs.card.Visible = false
		return
	end
	if not r then
		refs.status.Text = "Connecting..."
		return
	end
	local queued = ClientState.isQueued()
	refs.fightText.Text = if queued then "QUEUED" else "FIGHT!"
	refs.fightGradient.Color = if queued then FIGHT_QUEUED else FIGHT_READY
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
	ClientState.Changed:Connect(refresh)
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
