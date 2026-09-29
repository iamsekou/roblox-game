-- The clash duel, for the two fighters in it (owner request 2026-09-29). The server lifts the pair into the air
-- and runs the duel (Systems/ClashDuelService); this shows it from inside:
--   * the cutscene camera (ClashCamera.playDuel), only for the two of them;
--   * one big digit at a time with its shrinking timer: type it (number row, keypad, or the on-screen keys on
--     touch) before the bar runs out. First mistake loses;
--   * the running score, and the result.
-- Number keys type the duel's digits while it lasts (the code box is closed: ClientState.dueling). The client only
-- sends (step, digit); the server judges.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local AnimControllers = ReplicatedStorage:WaitForChild("Animations"):WaitForChild("Controllers")
local ClashCamera = require(AnimControllers:WaitForChild("ClashCamera"))
local CameraShake = require(AnimControllers:WaitForChild("CameraShake"))
local UIMotion = require(AnimControllers:WaitForChild("UIMotion"))
local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"))
local Audio = require(Client:WaitForChild("Audio"))

local ClashDuelController = {}

local DIGIT_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.Zero] = 0,
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
	[Enum.KeyCode.KeypadZero] = 0,
	[Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.KeypadThree] = 3,
	[Enum.KeyCode.KeypadFour] = 4,
	[Enum.KeyCode.KeypadFive] = 5,
	[Enum.KeyCode.KeypadSix] = 6,
	[Enum.KeyCode.KeypadSeven] = 7,
	[Enum.KeyCode.KeypadEight] = 8,
	[Enum.KeyCode.KeypadNine] = 9,
}
local CARD = 170 -- px, the digit card
local STRIKE_RED = Color3.fromRGB(235, 70, 60)

local localPlayer = Players.LocalPlayer
local refs: { [string]: any } = {}

type Duel = {
	partner: any,
	step: number?, -- the digit being asked for
	digit: number?,
	deadline: number,
	shownAt: number,
	answered: number?, -- the step we already sent an answer for
	mine: number,
	theirs: number,
	result: string?,
}
local duel: Duel? = nil

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function build()
	local gui = UI.screen("NAU_ClashDuel", 8, true)
	gui.Enabled = false
	refs.gui = gui
	refs.phase = UI.label({
		Name = "Phase",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.13, 0),
		Size = UDim2.fromOffset(600, 54),
		Font = UI.FontHeavy,
		TextSize = 46,
		TextColor3 = UI.Colors.Text,
		TextStrokeTransparency = 0.3,
		Text = "CLASH!",
		Parent = gui,
	})
	refs.score = UI.label({
		Name = "Score",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.13, 56),
		Size = UDim2.fromOffset(600, 26),
		Font = UI.Font,
		TextSize = 22,
		TextColor3 = UI.Colors.Muted,
		TextStrokeTransparency = 0.5,
		Text = "",
		Parent = gui,
	})
	local card = UI.new("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.fromOffset(CARD, CARD),
		BackgroundColor3 = UI.Colors.Ink,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Visible = false,
		Parent = gui,
	})
	UI.corner().Parent = card
	refs.cardStroke = UI.stroke(UI.Colors.Text, 3, 0.1)
	refs.cardStroke.Parent = card
	refs.card = card
	refs.digit = UI.label({
		Name = "Digit",
		Size = UDim2.fromScale(1, 1),
		Font = UI.FontHeavy,
		TextSize = 150,
		TextColor3 = UI.Colors.Text,
		Text = "",
		Parent = card,
	})
	local barBack = UI.new("Frame", {
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 10),
		Size = UDim2.new(1, 40, 0, 8),
		BackgroundColor3 = UI.Colors.Slot,
		BorderSizePixel = 0,
		Parent = card,
	})
	refs.bar = UI.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UI.Colors.Gold,
		BorderSizePixel = 0,
		Parent = barBack,
	})
	refs.hint = UI.label({
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 24),
		Size = UDim2.new(1, 200, 0, 24),
		Font = UI.Font,
		TextSize = 20,
		TextColor3 = UI.Colors.Muted,
		Text = if UI.isTouch() then "TAP THE NUMBER · FIRST MISTAKE LOSES" else "TYPE THE NUMBER · FIRST MISTAKE LOSES",
		Parent = card,
	})
	refs.result = UI.label({
		Name = "Result",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(900, 120),
		Font = UI.FontHeavy,
		TextSize = 110,
		TextStrokeTransparency = 0.2,
		Visible = false,
		Text = "",
		Parent = gui,
	})
	-- Touch: a dedicated duel keypad with oversized keys (tapping is the slow part of a duel on a phone), two rows
	-- of five along the bottom. On phones the digit card moves up and shrinks so the keys never cover it.
	if UI.isTouch() then
		local phone = UI.isPhone()
		local keyW, keyH, gap = if phone then 84 else 96, if phone then 70 else 80, 10
		if phone then
			card.Size = UDim2.fromOffset(124, 124)
			card.Position = UDim2.fromScale(0.5, 0.36)
			refs.digit.TextSize = 108
			refs.hint.Visible = false
			refs.phase.Position = UDim2.new(0.5, 0, 0.02, 0)
			refs.score.Position = UDim2.new(0.5, 0, 0.02, 50)
			refs.result.Position = UDim2.fromScale(0.5, 0.3)
			refs.result.TextSize = 72
		end
		local pad = UI.new("Frame", {
			Name = "Keys",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -12),
			Size = UDim2.fromOffset(5 * keyW + 4 * gap, 2 * keyH + gap),
			BackgroundTransparency = 1,
			Parent = gui,
		})
		for d = 0, 9 do
			local index = if d == 0 then 9 else d - 1
			local key = UI.button({
				Name = "Key" .. d,
				Position = UDim2.fromOffset((index % 5) * (keyW + gap), math.floor(index / 5) * (keyH + gap)),
				Size = UDim2.fromOffset(keyW, keyH),
				Font = UI.FontHeavy,
				TextSize = 40,
				Text = tostring(d),
				BackgroundTransparency = 0.1,
				Parent = pad,
			})
			UI.corner().Parent = key
			-- On touch-down, not release: every tenth of a second counts in a duel.
			key.MouseButton1Down:Connect(function()
				ClashDuelController.type(d)
			end)
		end
		refs.pad = pad
	end
end

local function setPhase(text: string, color: Color3?)
	refs.phase.Text = text
	refs.phase.TextColor3 = color or UI.Colors.Text
	UIMotion.pop(refs.phase)
end

local function nameOf(who: any): string
	local player = if type(who) == "number" then Players:GetPlayerByUserId(who) else nil
	if player then
		return string.upper(player.DisplayName)
	end
	return if typeof(who) == "Instance" then string.upper(who.Name) else "THEM"
end

local function refreshScore()
	local d = duel
	if d then
		refs.score.Text = string.format("YOU  %d  —  %d  %s", d.mine, d.theirs, nameOf(d.partner))
	end
end

-- The server says the duel starts: camera, and the lift / slow-punch lead-in.
function ClashDuelController.begin(effect: any)
	if refs.gui == nil then
		return
	end
	local partner = if typeof(effect.partnerModel) == "Instance" then effect.partnerModel else effect.partner
	duel = {
		partner = partner,
		step = nil,
		digit = nil,
		deadline = 0,
		shownAt = 0,
		answered = nil,
		mine = 0,
		theirs = 0,
		result = nil,
	}
	ClientState.setDueling(true)
	refs.gui.Enabled = true
	refs.card.Visible = false
	refs.result.Visible = false
	refreshScore()
	setPhase("CLASH!", UI.Colors.Gold)
	CameraShake.shake(0.8, 0.4)
	if type(effect.startAt) == "number" and type(effect.slowAt) == "number" and type(effect.barrageAt) == "number" then
		ClashCamera.playDuel(partner, { startAt = effect.startAt, slowAt = effect.slowAt, barrageAt = effect.barrageAt })
		task.delay(math.max(0, effect.slowAt - serverNow()), function()
			if duel and not duel.step then
				setPhase("GET READY…")
			end
		end)
	end
end

-- The duel is over on the server (after the final blow): let the result and the blast play out, then hand back.
function ClashDuelController.finish()
	local d = duel
	if not d then
		return
	end
	local linger = if d.result == "win" or d.result == "lose" then 1.6 else 0.6
	task.delay(linger, function()
		if duel ~= d then
			return
		end
		duel = nil
		ClashCamera.stop()
		refs.gui.Enabled = false
		refs.result.Visible = false
		refs.card.Visible = false
		ClientState.setDueling(false)
	end)
end

-- A digit typed (key or touch button): send it for the current step, once.
function ClashDuelController.type(digit: number)
	local d = duel
	if not d or d.result or not d.step or d.answered == d.step then
		return
	end
	d.answered = d.step
	Remotes.ClashInput:FireServer(d.step, digit)
	if digit == d.digit then
		refs.cardStroke.Color = UI.Colors.Good
		UIMotion.pop(refs.card)
	else
		-- The server will call it; show the slip at once.
		refs.cardStroke.Color = STRIKE_RED
		refs.digit.TextColor3 = STRIKE_RED
		UIMotion.shake(refs.card)
		CameraShake.shake(1, 0.3)
	end
end

local function showDigit(payload: any)
	local d = duel
	if not d or d.result then
		return
	end
	d.step = payload.step
	d.digit = payload.digit
	d.deadline = payload.deadline
	d.shownAt = serverNow()
	d.answered = nil
	if payload.step > 1 then
		d.mine = payload.step - 1
		refreshScore()
	end
	refs.card.Visible = true
	refs.digit.Text = tostring(payload.digit)
	refs.digit.TextColor3 = UI.Colors.Text
	refs.cardStroke.Color = UI.Colors.Text
	UIMotion.pop(refs.card)
	if payload.step == 1 then
		setPhase("TYPE THE NUMBERS!", UI.Colors.Gold)
	end
	Audio.play("shop_select") -- a short servo tick on every new digit
end

local function showResult(outcome: string)
	local d = duel
	if not d then
		return
	end
	d.result = outcome
	refs.card.Visible = false
	refs.result.Visible = true
	if outcome == "win" then
		refs.result.Text = "YOU WIN THE CLASH"
		refs.result.TextColor3 = UI.Colors.Gold
		Audio.play("round_won")
	elseif outcome == "lose" then
		refs.result.Text = "CLASH LOST"
		refs.result.TextColor3 = STRIKE_RED
		Audio.play("eliminated")
	else
		refs.result.Text = "DRAW"
		refs.result.TextColor3 = UI.Colors.Text
	end
	UIMotion.pop(refs.result)
	setPhase(if outcome == "win" then "FINISH HIM" else "", UI.Colors.Gold)
end

-- Server events everyone gets (AbilityController forwards them): the score, and the final blow's camera.
function ClashDuelController.onFX(event: any)
	local d = duel
	if not d or type(event) ~= "table" then
		return
	end
	local me = localPlayer.UserId
	if event.a ~= me and event.b ~= me then
		return
	end
	if event.kind == "clash_tick" then
		if event.who ~= me then
			d.theirs = tonumber(event.typed) or d.theirs + 1
		else
			d.mine = tonumber(event.typed) or d.mine
		end
		refreshScore()
		ClashCamera.duelBeat()
	elseif event.kind == "clash_duel_end" and event.winner and type(event.finalAt) == "number" then
		local function modelOf(model: any, id: any): Model?
			if typeof(model) == "Instance" and model:IsA("Model") then
				return model
			end
			local player = if type(id) == "number" then Players:GetPlayerByUserId(id) else nil
			return player and player.Character
		end
		ClashCamera.duelFinal(modelOf(event.winnerModel, event.winner), modelOf(event.loserModel, event.loser), event.finalAt)
	end
end

-- For tests: what the duel screen shows right now.
function ClashDuelController.snapshot(): { [string]: any }
	local d = duel
	return {
		active = d ~= nil,
		step = d and d.step,
		digit = d and d.digit,
		result = d and d.result,
		shown = refs.card and refs.card.Visible and refs.digit.Text or nil,
		score = refs.score and refs.score.Text,
		phase = refs.phase and refs.phase.Text,
		camera = ClashCamera.isPlaying(),
	}
end

-- Tell the server what we play with: a duel's window floor follows the slower fighter's device.
local reportedDevice: string? = nil
local function reportDevice(inputType: Enum.UserInputType?)
	local device
	if inputType == Enum.UserInputType.Touch then
		device = "touch"
	elseif inputType and string.find(inputType.Name, "Gamepad", 1, true) then
		device = "gamepad"
	elseif inputType == Enum.UserInputType.Keyboard or (inputType and string.find(inputType.Name, "Mouse", 1, true)) then
		device = "keyboard"
	elseif inputType == nil then
		device = if UI.isTouch() then "touch" else "keyboard"
	else
		return -- focus changes, text input and the like say nothing about the device
	end
	if device ~= reportedDevice then
		reportedDevice = device
		Remotes.InputDevice:FireServer(device)
	end
end

function ClashDuelController.Start()
	build()
	-- A phone or tablet (or Studio's emulated touch layout) starts as touch; after that the last input used decides.
	reportDevice(if UI.isTouch() then Enum.UserInputType.Touch else nil)
	UserInputService.LastInputTypeChanged:Connect(reportDevice)
	Remotes.ClashDigit.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if type(payload.result) == "string" then
			showResult(payload.result)
		elseif type(payload.step) == "number" and type(payload.digit) == "number" and type(payload.deadline) == "number" then
			showDigit(payload)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not duel or gameProcessed or UserInputService:GetFocusedTextBox() then
			return
		end
		local digit = DIGIT_KEYS[input.KeyCode]
		if digit ~= nil then
			ClashDuelController.type(digit)
		end
	end)
	-- The timer bar drains toward the deadline, turning red near the end.
	RunService.RenderStepped:Connect(function()
		local d = duel
		if not d or not d.step or d.result then
			return
		end
		local total = math.max(d.deadline - d.shownAt, 0.05)
		local left = math.clamp((d.deadline - serverNow()) / total, 0, 1)
		refs.bar.Size = UDim2.fromScale(left, 1)
		refs.bar.BackgroundColor3 = if left < 0.3 then STRIKE_RED else UI.Colors.Gold
	end)
	-- Stopping in the middle (the round ended, a respawn): never leave the screen or the camera behind.
	ClientState.Changed:Connect(function(kind)
		if kind == "life" and duel and ClientState.life.inMatch == false then
			ClashDuelController.finish()
		end
	end)
end

return ClashDuelController
