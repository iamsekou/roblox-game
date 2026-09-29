-- Character XP on screen (owner-approved 2026-09-29; rules in Lib/XpRules, server in Systems/XpService). A slim
-- strip under the scoreboard shows the fighter you're playing (in a round) or have equipped (lobby): prestige
-- badge, level, and the bar in the fighter's aura colour. Every gain floats up from it ("+1,200 XP ·
-- ELIMINATION"); a level up and a prestige get the big centre banner. When the last bar is full the strip says
-- READY TO PRESTIGE and a PRESTIGE button appears (a second tap within a few seconds confirms; the server
-- decides). The strip steps aside during spawn protection (that panel sits in the same place) and clash duels.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local CharacterDefs = require(Shared:WaitForChild("Modules"):WaitForChild("CharacterDefs"))
local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"))
local Audio = require(Client:WaitForChild("Audio"))
local HUDController = require(script.Parent:WaitForChild("HUDController"))

local XpController = {}

local STRIP_WIDTH = 320
local STRIP_TOP = 62 -- just under the scoreboard (HUDController), where the spawn-protection panel also sits
local CONFIRM_SECONDS = 3
local NUMERALS = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }

local refs: { [string]: any } = {}
local confirmUntil = 0
local busy = false

local function numeral(p: number): string
	return NUMERALS[p] or tostring(p)
end

-- The fighter the strip is about: the one fighting this round, else the equipped one.
local function shownCharacter(): string
	local ability = ClientState.ability
	if ClientState.life.inMatch and type(ability.character) == "string" then
		return ability.character
	end
	return if type(ability.equipped) == "string" then ability.equipped else "Goku"
end

local function auraOf(id: string): Color3
	local def = CharacterDefs.byId[id]
	local color = def and def.aura
	if not color or (def and def.auraDark) then
		return UI.Colors.Text -- a dark aura (Ichiro) would vanish on the dark strip
	end
	return color
end

local function refresh()
	if not refs.strip then
		return
	end
	local id = shownCharacter()
	local def = CharacterDefs.byId[id]
	local xp = ClientState.xpOf(id)
	local maxPrestige = ClientState.xp.maxPrestige or 10
	local color = auraOf(id)
	local badge = if xp.p > 0 then string.format('<font color="#D6B460">P·%s</font>  ', numeral(xp.p)) else ""
	refs.name.Text = string.format('%s%s  <font color="#9297A3">LV</font> %d', badge, string.upper(def and def.name or id), xp.l)
	refs.fill.BackgroundColor3 = if xp.full then UI.Colors.Gold else color
	refs.fill.Size = UDim2.fromScale(math.clamp(xp.x / math.max(1, xp.need), 0, 1), 1)
	local ready = xp.full and xp.p < maxPrestige
	if xp.full and not ready then
		refs.amount.Text = "MAX PRESTIGE"
	elseif ready then
		refs.amount.Text = "READY TO PRESTIGE"
	else
		refs.amount.Text = string.format("%s / %s XP", UI.formatNumber(xp.x), UI.formatNumber(xp.need))
	end
	refs.amount.TextColor3 = if xp.full then UI.Colors.Gold else UI.Colors.Muted
	refs.prestige.Visible = ready and ClientState.xp.loaded == true
	if os.clock() >= confirmUntil then
		refs.prestige.Text = string.format("PRESTIGE %s", numeral(xp.p + 1))
	end
	-- Out of the way during spawn protection (same spot) and clash duels (their own screen).
	local life = ClientState.life
	refs.strip.Visible = life.protectedUntil == nil and not ClientState.dueling
end

-- "+1,200 XP · ELIMINATION", floating up from the strip.
local function popGain(gain: any)
	if not refs.popups or type(gain.amount) ~= "number" then
		return
	end
	local shown = shownCharacter()
	local who = ""
	if gain.character ~= shown then
		local def = CharacterDefs.byId[gain.character]
		who = if def then "  " .. string.upper(def.name) else ""
	end
	local label = UI.label({
		RichText = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(STRIP_WIDTH, 22),
		Font = UI.FontHeavy,
		TextSize = 18,
		TextColor3 = UI.Colors.Gold,
		TextStrokeTransparency = 0.5,
		Text = string.format('+%s XP <font color="#ECECE8" size="13">· %s%s</font>', UI.formatNumber(gain.amount), tostring(gain.reason or ""), who),
		Parent = refs.popups,
	})
	local info = TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(label, info, { Position = UDim2.new(0.5, 0, 0, 34), TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.7, function()
		label:Destroy()
	end)
end

local function onXpEvent()
	local event = ClientState.lastXpEvent
	if type(event) ~= "table" then
		return
	end
	local gain = event.gain
	if type(gain) == "table" and type(gain.character) == "string" then
		popGain(gain)
		local def = CharacterDefs.byId[gain.character]
		local name = string.upper(def and def.name or gain.character)
		if gain.full then
			HUDController.banner("READY TO PRESTIGE", name .. " · LEVEL " .. tostring(gain.level), UI.Colors.Gold, 3)
			Audio.play("round_won")
		elseif type(gain.levels) == "number" and gain.levels > 0 then
			HUDController.banner("LEVEL " .. tostring(gain.level), name, auraOf(gain.character), 2.5)
			Audio.play("income")
		end
	end
	local prestiged = event.prestiged
	if type(prestiged) == "table" and type(prestiged.p) == "number" then
		local def = CharacterDefs.byId[prestiged.character]
		HUDController.banner("PRESTIGE " .. numeral(prestiged.p), string.upper(def and def.name or "") .. " · BACK TO LEVEL 1", UI.Colors.Gold, 3.5)
		Audio.play("round_won")
	end
end

local function pressPrestige()
	if busy then
		return
	end
	local id = shownCharacter()
	local now = os.clock()
	if now >= confirmUntil then
		confirmUntil = now + CONFIRM_SECONDS
		refs.prestige.Text = "TAP AGAIN"
		task.delay(CONFIRM_SECONDS, refresh)
		return
	end
	confirmUntil = 0
	busy = true
	refs.prestige.Text = "..."
	local ok, result = pcall(function()
		return Remotes.Prestige:InvokeServer(id)
	end)
	busy = false
	if not ok or type(result) ~= "table" or result.status ~= "prestiged" then
		HUDController.toast(if ok and type(result) == "table" and result.status == "loading" then "Your progress is still loading" else "Couldn't prestige, try again", "bad")
	end
	refresh() -- the banner comes with the server's XpState
end

local function build()
	local gui = UI.screen("NAU_XP", 5, true)
	local strip = UI.panel({
		Name = "Strip",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, STRIP_TOP),
		Size = UDim2.fromOffset(STRIP_WIDTH, 34),
		Parent = gui,
	})
	refs.strip = strip
	refs.name = UI.label({
		Name = "Fighter",
		RichText = true,
		Position = UDim2.fromOffset(10, 2),
		Size = UDim2.new(0.6, -10, 0, 20),
		Font = UI.FontHeavy,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = strip,
	})
	refs.amount = UI.label({
		Name = "Amount",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 3),
		Size = UDim2.new(0.4, 0, 0, 18),
		Font = UI.Font,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = strip,
	})
	local track = UI.new("Frame", {
		Name = "Track",
		Position = UDim2.new(0, 10, 1, -9),
		Size = UDim2.new(1, -20, 0, 4),
		BorderSizePixel = 0,
		BackgroundColor3 = UI.Colors.Slot,
		Parent = strip,
	})
	refs.fill = UI.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BorderSizePixel = 0,
		Parent = track,
	})
	local touch = UI.isTouch()
	refs.prestige = UI.button({
		Name = "Prestige",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 6, 0.5, 0),
		Size = UDim2.fromOffset(if touch then 130 else 118, if touch then 44 else 34),
		BackgroundColor3 = UI.Colors.Gold,
		TextColor3 = UI.Colors.Ink,
		Font = UI.FontHeavy,
		TextSize = 15,
		Visible = false,
		Parent = strip,
	}, { UI.corner() })
	refs.prestige.Activated:Connect(pressPrestige)
	refs.popups = UI.new("Frame", {
		Name = "Popups",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, STRIP_TOP + 38),
		Size = UDim2.fromOffset(STRIP_WIDTH, 60),
		BackgroundTransparency = 1,
		Parent = gui,
	})
end

function XpController.Start()
	build()
	refresh()
	ClientState.Changed:Connect(function(kind)
		if kind == "xp" then
			refresh()
			onXpEvent()
		elseif kind == "ability" or kind == "life" or kind == "duel" then
			refresh()
		end
	end)
	Players.LocalPlayer.CharacterAdded:Connect(refresh)
end

return XpController
