-- Code entry. F (or the on-screen CODE button) opens a compact four-slot box; submitting a full code
-- closes it again, and the server's answer appears as a HUD toast.
-- Digits are read straight from the keyboard, so players keep moving with WASD while they type;
-- nothing is captured while chat or any other text box has focus. Touch devices get an on-screen keypad.
-- The client only sends the typed characters; the server judges every submission.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Constants = require(Shared:WaitForChild("Modules"):WaitForChild("Constants"))
local Currency = require(Shared:WaitForChild("Modules"):WaitForChild("Currency"))
local AnimControllers = ReplicatedStorage:WaitForChild("Animations"):WaitForChild("Controllers")
local UIMotion = require(AnimControllers:WaitForChild("UIMotion"))
local CameraShake = require(AnimControllers:WaitForChild("CameraShake"))
local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"))
local Audio = require(Client:WaitForChild("Audio"))
local HUDController = require(script.Parent:WaitForChild("HUDController"))

local SubmissionController = {}

local CODE_LENGTH = Constants.CODE_LENGTH
local STRIKE_LIMIT = Constants.WRONG_SUBMISSION_LIMIT

-- Touch layout (Phase 4 phone pass): [code column | keypad]. Keys are at least 44 px tall (touch target).
local KEY_SIZE = Vector2.new(60, 44)
local KEY_GAP = 6
local TOUCH_COLUMN_WIDTH = 230 -- four 50 px slots with 8 px gaps, plus a little air
local TOUCH_PANEL_WIDTH = 12 + TOUCH_COLUMN_WIDTH + 12 + (3 * KEY_SIZE.X + 2 * KEY_GAP) + 12

local DIGIT_KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Zero] = "0",
	[Enum.KeyCode.One] = "1",
	[Enum.KeyCode.Two] = "2",
	[Enum.KeyCode.Three] = "3",
	[Enum.KeyCode.Four] = "4",
	[Enum.KeyCode.Five] = "5",
	[Enum.KeyCode.Six] = "6",
	[Enum.KeyCode.Seven] = "7",
	[Enum.KeyCode.Eight] = "8",
	[Enum.KeyCode.Nine] = "9",
	[Enum.KeyCode.KeypadZero] = "0",
	[Enum.KeyCode.KeypadOne] = "1",
	[Enum.KeyCode.KeypadTwo] = "2",
	[Enum.KeyCode.KeypadThree] = "3",
	[Enum.KeyCode.KeypadFour] = "4",
	[Enum.KeyCode.KeypadFive] = "5",
	[Enum.KeyCode.KeypadSix] = "6",
	[Enum.KeyCode.KeypadSeven] = "7",
	[Enum.KeyCode.KeypadEight] = "8",
	[Enum.KeyCode.KeypadNine] = "9",
}

local refs: { [string]: any } = { slots = {} }
local digits: { string } = {}
local isOpen = false
local busy = false
local strikesLeft = STRIKE_LIMIT
local feedbackToken = 0
local lastLifeAlive: boolean? = nil
local isTouch = false
local lockedUntil = -math.huge -- an ability jammed this player's code entry until this server time

local function render()
	for i = 1, CODE_LENGTH do
		local slot = refs.slots[i]
		local digit = digits[i]
		local active = i == #digits + 1
		slot.label.Text = digit or "-"
		slot.label.TextColor3 = if digit then UI.Colors.Text else UI.Colors.Muted
		slot.stroke.Color = if active then UI.Colors.Accent else UI.Colors.Line
		slot.stroke.Thickness = if active then 2 else 1
	end
	if strikesLeft < STRIKE_LIMIT then
		refs.strikes.Text = "LAST CHANCE: THE NEXT MISS ELIMINATES YOU"
		refs.strikes.TextColor3 = UI.Colors.Bad
	else
		refs.strikes.Text = string.format("%d WRONG CODES IN ONE LIFE ELIMINATES YOU", STRIKE_LIMIT)
		refs.strikes.TextColor3 = UI.Colors.Muted
	end
end

local function setFeedback(text: string, tone: string?)
	feedbackToken += 1
	local token = feedbackToken
	refs.feedback.Text = text
	refs.feedback.TextColor3 = UI.toneColor(tone)
	task.delay(3, function()
		if feedbackToken == token then
			refs.feedback.Text = ""
		end
	end)
end

local function close()
	isOpen = false
	table.clear(digits)
	refs.panel.Visible = false
	HUDController.setEntryOpen(false)
	render()
end

local function open()
	if not ClientState.canSubmit() then
		return
	end
	local jammed = lockedUntil - workspace:GetServerTimeNow()
	if jammed > 0 then
		HUDController.toast(string.format("JAMMED: you can't type codes for %.1fs", jammed), "bad")
		return
	end
	isOpen = true
	table.clear(digits)
	refs.panel.Visible = true
	HUDController.setEntryOpen(isTouch and UI.isPhone()) -- phones: the kill list makes room for the keypad
	UIMotion.pop(refs.panel)
	render()
end

local function toggle()
	if isOpen then
		close()
	else
		open()
	end
end

local function addDigit(digit: string)
	if #digits >= CODE_LENGTH then
		return
	end
	table.insert(digits, digit)
	render()
end

local function backspace()
	if #digits > 0 then
		table.remove(digits)
		render()
	end
end

-- The panel is already closed by the time the server answers, so results show as HUD toasts.
local function onResult(result: any)
	local status = result.status
	if status == "eliminated" then
		Audio.play("elimination")
		HUDController.toast(
			string.format("ELIMINATED %s   +%s", tostring(result.targetName), Currency.amount(UI.formatNumber(result.yen or Constants.YEN_PER_ELIMINATION))),
			"good"
		)
	elseif status == "wrong" then
		strikesLeft = if type(result.strikesLeft) == "number" then result.strikesLeft else strikesLeft - 1
		HUDController.toast("Wrong code. Careful: one more miss and you're out.", "bad")
		Audio.play("wrong_code")
		CameraShake.shake(0.7, 0.4) -- approved: the first wrong submission shakes the screen
	elseif status == "self_eliminated" then
		strikesLeft = 0
		CameraShake.shake(1.1, 0.5)
	elseif status == "stale" then
		HUDController.toast("That fighter is already down", "info")
	elseif status == "teammate" then
		HUDController.toast("That's a teammate", "info")
	elseif status == "protected" then
		HUDController.toast("Still spawn-protected: you can strike in a moment", "info")
	elseif status == "clone" then
		HUDController.toast("It was a decoy!", "info") -- Naruto's Mirror Decoy popped: no strike, no kill
	elseif status == "locked" then
		HUDController.toast("JAMMED: you can't type codes yet", "bad")
	elseif status == "rate_limited" then
		HUDController.toast("Too fast, try again", "info")
	elseif status == "malformed" then
		HUDController.toast("Enter all 4 digits", "bad")
	else
		HUDController.toast("You're not in an active round", "info")
	end
	render()
end

-- Owner rule (2026-09-23): confirming a full code, right or wrong, closes the panel; typing another
-- code means opening it again with F / the CODE button. An incomplete code isn't a confirmation.
local function submit()
	if busy or not isOpen then
		return
	end
	if #digits < CODE_LENGTH then
		setFeedback("Enter all 4 digits", "bad")
		UIMotion.shake(refs.slotsInner)
		return
	end
	local code = table.concat(digits)
	close()
	busy = true
	local ok, result = pcall(function()
		return Remotes.SubmitCode:InvokeServer(code)
	end)
	busy = false
	if not ok or type(result) ~= "table" then
		HUDController.toast("Connection hiccup, try again", "bad")
		return
	end
	onResult(result)
end

local function makeSlot(parent: Instance, index: number)
	local stroke = UI.stroke(UI.Colors.Line, 1, 0)
	local frame = UI.new("Frame", {
		Name = "Slot" .. index,
		LayoutOrder = index,
		Size = UDim2.fromOffset(50, 56),
		BackgroundColor3 = UI.Colors.Ink,
		BorderSizePixel = 0,
		Parent = parent,
	}, { stroke })
	local label = UI.label({
		Size = UDim2.fromScale(1, 1),
		TextSize = 32,
		Font = UI.FontHeavy,
		Text = "-",
		Parent = frame,
	})
	refs.slots[index] = { frame = frame, label = label, stroke = stroke }
end

local function build()
	isTouch = UI.isTouch()
	local gui = UI.screen("NAU_CodeEntry", 6)

	-- Outer slab (holds the accent bar) + inner content (padding and layout), so the bar never moves.
	-- Touch (Phase 4 phone pass): two columns, the code on the left and the keypad on the right, so the panel
	-- stays short enough for a phone held sideways (about 350 px of height below Roblox's top bar).
	local outer = UI.panel({
		Name = "CodeEntry",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, if isTouch then -16 else -24),
		Size = UDim2.fromOffset(if isTouch then TOUCH_PANEL_WIDTH else 290, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.06,
		Visible = false,
		Parent = gui,
	})
	UI.accentBar(outer, "top", UI.Colors.Accent, 2)
	local content = UI.new("Frame", {
		Name = "Content",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = outer,
	}, {
		UI.padding(12),
		UI.new("UIListLayout", {
			FillDirection = if isTouch then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, if isTouch then 12 else 7),
		}),
	})
	-- The code column: the whole panel on a PC, the left column on touch.
	local panel = content
	if isTouch then
		panel = UI.new("Frame", {
			Name = "Column",
			LayoutOrder = 1,
			Size = UDim2.fromOffset(TOUCH_COLUMN_WIDTH, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = content,
		}, {
			UI.new("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 7),
			}),
		})
	end
	refs.panel = outer

	refs.feedback = UI.label({
		Name = "Feedback",
		LayoutOrder = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = UI.FontBody,
		TextSize = 13,
		TextWrapped = true,
		Parent = panel,
	})
	UI.label({
		Name = "Title",
		LayoutOrder = 2,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = UI.FontHeavy,
		TextSize = 16,
		Text = "ENTER THEIR CODE",
		Parent = panel,
	})

	-- Slots live in an inner frame so they can shake without fighting the panel's list layout.
	local slotRow = UI.new("Frame", {
		Name = "SlotRow",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	refs.slotsInner = UI.new("Frame", {
		Name = "Slots",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = slotRow,
	}, {
		UI.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
	})
	for i = 1, CODE_LENGTH do
		makeSlot(refs.slotsInner, i)
	end

	refs.strikes = UI.label({
		Name = "Strikes",
		LayoutOrder = 4,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 13,
		TextWrapped = true,
		Parent = panel,
	})

	local buttons = UI.new("Frame", {
		Name = "Buttons",
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, if isTouch then 44 else 36),
		BackgroundTransparency = 1,
		Parent = panel,
	}, {
		UI.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 6),
		}),
	})
	local submitButton = UI.button({
		Name = "Submit",
		Size = UDim2.fromOffset(if isTouch then 130 else 160, if isTouch then 44 else 36),
		BackgroundColor3 = UI.Colors.Accent,
		Font = UI.FontHeavy,
		TextSize = 17,
		Text = if isTouch then "SUBMIT" else "SUBMIT  [ENTER]",
		Parent = buttons,
	})
	local cancelButton = UI.button({
		Name = "Cancel",
		Size = UDim2.fromOffset(if isTouch then 90 else 100, if isTouch then 44 else 36),
		Font = UI.Font,
		TextColor3 = UI.Colors.Muted,
		Text = if isTouch then "CANCEL" else "CANCEL  [F]",
		TextSize = 15,
		Parent = buttons,
	})
	submitButton.Activated:Connect(submit)
	cancelButton.Activated:Connect(close)

	if isTouch then
		local keypad = UI.new("Frame", {
			Name = "Keypad",
			LayoutOrder = 2,
			Size = UDim2.fromOffset(3 * KEY_SIZE.X + 2 * KEY_GAP, 4 * KEY_SIZE.Y + 3 * KEY_GAP),
			BackgroundTransparency = 1,
			Parent = content, -- the right-hand column
		}, {
			UI.new("UIGridLayout", {
				CellSize = UDim2.fromOffset(KEY_SIZE.X, KEY_SIZE.Y),
				CellPadding = UDim2.fromOffset(KEY_GAP, KEY_GAP),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "DEL", "0", "OK" }
		for i, key in keys do
			local button = UI.button({
				Name = "Key_" .. key,
				LayoutOrder = i,
				Text = key,
				TextSize = 22,
				Font = UI.FontHeavy,
				BackgroundColor3 = if key == "OK" then UI.Colors.Accent else UI.Colors.Slot,
				Parent = keypad,
			})
			button.Activated:Connect(function()
				if key == "DEL" then
					backspace()
				elseif key == "OK" then
					submit()
				else
					addDigit(key)
				end
			end)
		end
	else
		UI.label({
			Name = "Hint",
			LayoutOrder = 6,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Font = UI.FontBody,
			TextSize = 11,
			TextWrapped = true,
			TextColor3 = UI.Colors.Muted,
			Text = "Backspace deletes · you can keep moving",
			Parent = panel,
		})
	end

	local cluster = UI.touchCluster() -- touch: beside Roblox's jump button
	refs.openButton = UI.button({
		Name = "OpenCodeEntry",
		AnchorPoint = Vector2.new(1, 1),
		Position = if isTouch then cluster.code.position else UDim2.new(1, -20, 1, -24),
		Size = if isTouch then cluster.code.size else UDim2.fromOffset(128, 40),
		BackgroundColor3 = UI.Colors.Panel,
		BackgroundTransparency = 0.12,
		Font = UI.FontHeavy,
		TextSize = if isTouch then 24 else 18,
		Text = if isTouch then "CODE" else "[F]  CODE",
		Visible = false,
		Parent = gui,
	}, { UI.stroke(Color3.new(1, 1, 1), 1, 0.9) })
	UI.accentBar(refs.openButton, if isTouch then "bottom" else "left", UI.Colors.Accent, 3)
	refs.openButton.Activated:Connect(toggle)
	local camera = workspace.CurrentCamera
	if isTouch and camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local placed = UI.touchCluster()
			refs.openButton.Position = placed.code.position
			refs.openButton.Size = placed.code.size
		end)
	end

	render()
end

local function refreshAvailability()
	local life = ClientState.life
	-- A new life (or a new round) starts with a clean strike count.
	if life.alive and lastLifeAlive == false then
		strikesLeft = STRIKE_LIMIT
	end
	if not life.inMatch then
		strikesLeft = STRIKE_LIMIT
	end
	lastLifeAlive = life.alive
	local available = ClientState.canSubmit()
	refs.openButton.Visible = available
	if not available and isOpen then
		close()
	end
	render()
end

-- Luffy's Blitz Barrage: wipes a half-typed code (the box stays open). Returns whether anything was
-- wiped, so the caller can say why the digits vanished.
function SubmissionController.clearTyped(): boolean
	if #digits > 0 then
		table.clear(digits)
		render()
		UIMotion.shake(refs.slotsInner)
		return true
	end
	return false
end

-- An input-lock ability landed (the server already rejects codes until then): close the box and say why.
function SubmissionController.lockUntil(untilTime: number)
	lockedUntil = math.max(lockedUntil, untilTime)
	if isOpen then
		close()
	end
	local left = lockedUntil - workspace:GetServerTimeNow()
	if left > 0 then
		HUDController.toast(string.format("JAMMED: you can't type codes for %.1fs", left), "bad")
	end
end

function SubmissionController.Start()
	-- Number keys are also the default hotbar keys; NAU has no tools, so hide the backpack.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	build()
	ClientState.Changed:Connect(refreshAvailability)
	refreshAvailability()

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		-- Never capture typing meant for chat or any other text box.
		if gameProcessed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		if input.KeyCode == Constants.ENTRY_KEY then
			toggle()
			return
		end
		if not isOpen then
			return
		end
		local digit = DIGIT_KEYS[input.KeyCode]
		if digit then
			addDigit(digit)
		elseif input.KeyCode == Enum.KeyCode.Backspace then
			backspace()
		elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
			task.spawn(submit)
		end
	end)
end

return SubmissionController
