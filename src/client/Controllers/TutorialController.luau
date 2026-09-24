-- How to play (Phase 4, owner-approved 2026-09-23): a short walkthrough of the one unusual rule (everyone
-- sees a different number on each opponent) and the basics around it. It opens by itself on a player's first
-- visit (in the lobby, once their saved profile has loaded) until they finish or skip it once; the settings
-- menu's HOW TO PLAY button reopens it. "Seen" is the hidden `tutorialDone` setting (Modules/Settings), so it
-- is validated and saved by the server like any setting.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local AnimControllers = ReplicatedStorage:WaitForChild("Animations"):WaitForChild("Controllers")
local UIMotion = require(AnimControllers:WaitForChild("UIMotion"))
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Constants"))
local Currency = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Currency"))
local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"))
local ClientState = require(Client:WaitForChild("ClientState"))
local SettingsController = require(script.Parent:WaitForChild("SettingsController"))

local TutorialController = {}

local CARD_WIDTH = 560
local CARD_HEIGHT = 360
local FIRST_VISIT_DELAY = 2.5 -- seconds after the profile loads, so the lobby is on screen first
local PLATE_COLOR = Color3.fromRGB(14, 16, 24)

local refs: { [string]: any } = {}
local step = 1
local shownThisSession = false

-- Illustrations ------------------------------------------------------------------------------------

-- A number plate like the ones over fighters.
local function plate(parent: Instance, position: UDim2, textValue: string, revealed: boolean): Frame
	local frame = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(86, 34),
		BackgroundColor3 = PLATE_COLOR,
		Parent = parent,
	}, { UI.corner(), UI.stroke(Color3.new(1, 1, 1), 1, 0.4) })
	UI.label({
		Size = UDim2.fromScale(1, 1),
		Font = UI.FontHeavy,
		TextSize = 22,
		TextColor3 = if revealed then UI.Colors.Text else UI.Colors.Muted,
		Text = textValue,
		Parent = frame,
	})
	return frame
end

-- A simple fighter silhouette (head + body) with a caption under it.
local function fighter(parent: Instance, x: number, caption: string, color: Color3)
	UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(x, 0, 0, 54),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = color,
		Parent = parent,
	}, { UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) }) -- a round head (UI.corner caps rounding)
	UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(x, 0, 0, 83),
		Size = UDim2.fromOffset(34, 38),
		BackgroundColor3 = color,
		Parent = parent,
	}, { UI.corner(6) })
	UI.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(x, 0, 0, 124),
		Size = UDim2.fromOffset(170, 18),
		Font = UI.Font,
		TextSize = 14,
		TextColor3 = UI.Colors.Muted,
		Text = caption,
		Parent = parent,
	})
end

local function keycap(parent: Instance, position: UDim2, key: string, color: Color3)
	local cap = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(52, 52),
		BackgroundColor3 = UI.Colors.Slot,
		Parent = parent,
	}, { UI.corner(), UI.stroke(color, 2, 0) })
	UI.label({ Size = UDim2.fromScale(1, 1), Font = UI.FontHeavy, TextSize = 24, Text = key, Parent = cap })
end

local function caption(parent: Instance, position: UDim2, textValue: string, color: Color3?)
	UI.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = position,
		Size = UDim2.fromOffset(200, 18),
		Font = UI.Font,
		TextSize = 14,
		TextColor3 = color or UI.Colors.Muted,
		Text = textValue,
		Parent = parent,
	})
end

-- The steps ----------------------------------------------------------------------------------------

type Step = { title: string, body: string, draw: (Frame) -> () }

local function steps(): { Step }
	local touch = UI.isTouch()
	return {
		{
			title = "EVERYONE SEES A DIFFERENT NUMBER",
			body = "Every opponent carries a 4-digit number. The number YOU see on them is yours alone: another player sees a different number on the same fighter.",
			draw = function(art)
				fighter(art, 0.28, "YOU", UI.Colors.Info)
				fighter(art, 0.72, "OPPONENT", UI.Colors.Accent)
				plate(art, UDim2.new(0.72, 0, 0, 26), "4821", true)
				caption(art, UDim2.new(0.5, 0, 0, 4), "what you see on them", UI.Colors.Text)
			end,
		},
		{
			title = "GET CLOSE AND GET SEEN",
			body = string.format(
				"From afar a plate is blank. The digits only appear when you are within %d studs AND they are facing you. Cover hides plates.",
				Constants.PLATE_VIEW_DISTANCE
			),
			draw = function(art)
				plate(art, UDim2.new(0.25, 0, 0, 60), "••••", false)
				caption(art, UDim2.new(0.25, 0, 0, 86), "far away / turned away")
				UI.label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 60), Size = UDim2.fromOffset(60, 30), Font = UI.FontHeavy, TextSize = 28, TextColor3 = UI.Colors.Muted, Text = "→", Parent = art })
				plate(art, UDim2.new(0.75, 0, 0, 60), "4821", true)
				caption(art, UDim2.new(0.75, 0, 0, 86), "close + facing you", UI.Colors.Good)
			end,
		},
		{
			title = "TYPE IT TO TAKE THEM OUT",
			body = string.format(
				"%s, type the 4 digits you saw and confirm. The right code eliminates them and pays %d %s. They respawn a few seconds later.",
				if touch then "Tap CODE" else "Press F",
				Constants.YEN_PER_ELIMINATION,
				Currency.NAME
			),
			draw = function(art)
				for i, digit in { "4", "8", "2", "1" } do
					local slot = UI.new("Frame", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(0.5, (i - 2.5) * 58, 0, 52),
						Size = UDim2.fromOffset(50, 56),
						BackgroundColor3 = UI.Colors.Ink,
						Parent = art,
					}, { UI.stroke(UI.Colors.Accent, 1, 0) })
					UI.label({ Size = UDim2.fromScale(1, 1), Font = UI.FontHeavy, TextSize = 30, Text = digit, Parent = slot })
				end
				caption(art, UDim2.new(0.5, 0, 0, 92), "ELIMINATED  +" .. Currency.amount(Constants.YEN_PER_ELIMINATION), UI.Colors.Gold)
			end,
		},
		{
			title = "TWO MISSES AND YOU'RE OUT",
			body = "A wrong code is a warning. A second wrong code in the same life eliminates YOU. Only type numbers you have actually read.",
			draw = function(art)
				for i, spec in { { "1st miss", "warning", UI.Colors.Gold }, { "2nd miss", "you're out", UI.Colors.Bad } } do
					local x = if i == 1 then 0.3 else 0.7
					UI.label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(x, 0, 0, 48), Size = UDim2.fromOffset(60, 50), Font = UI.FontHeavy, TextSize = 44, TextColor3 = spec[3], Text = "X", Parent = art }) -- the display font has no ✕
					caption(art, UDim2.new(x, 0, 0, 78), spec[1], UI.Colors.Text)
					caption(art, UDim2.new(x, 0, 0, 96), spec[2], spec[3])
				end
			end,
		},
		{
			title = "ABILITIES AND WINNING",
			body = string.format(
				"Every fighter has two abilities: %s. A round lasts %d minutes and the most eliminations wins. A tie goes to sudden death.",
				if touch then "tap the Q and E buttons" else "press Q and E",
				math.floor(Constants.ROUND_TIME_CAP / 60)
			),
			draw = function(art)
				keycap(art, UDim2.new(0.34, 0, 0, 52), "Q", UI.Colors.Info)
				keycap(art, UDim2.new(0.5, 0, 0, 52), "E", UI.Colors.Gold)
				UI.label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.68, 0, 0, 52), Size = UDim2.fromOffset(60, 52), Font = UI.FontHeavy, TextSize = 40, TextColor3 = UI.Colors.Gold, Text = "★", Parent = art })
				caption(art, UDim2.new(0.5, 0, 0, 90), "abilities · then most eliminations wins")
			end,
		},
	}
end

-- Building and showing ----------------------------------------------------------------------------

local function render()
	local list = refs.steps
	local current = list[step]
	refs.title.Text = current.title
	refs.body.Text = current.body
	refs.counter.Text = string.format("%d / %d", step, #list)
	for _, child in refs.art:GetChildren() do
		child:Destroy()
	end
	current.draw(refs.art)
	refs.back.Visible = step > 1
	refs.next.Text = if step == #list then "LET'S FIGHT" else "NEXT"
	for i, dot in refs.dots do
		dot.BackgroundColor3 = if i == step then UI.Colors.Accent else UI.Colors.Slot
	end
	UIMotion.pop(refs.card)
end

local function close(done: boolean)
	refs.gui.Enabled = false
	if done and SettingsController.get("tutorialDone") ~= true then
		SettingsController.set("tutorialDone", true)
	end
end

-- NEXT (or LET'S FIGHT on the last step, which finishes it). Also Enter / the right arrow key.
local function advance()
	if step >= #refs.steps then
		close(true)
	else
		step += 1
		render()
	end
end

function TutorialController.open()
	SettingsController.close()
	step = 1
	refs.gui.Enabled = true
	render()
end

function TutorialController.isOpen(): boolean
	return refs.gui ~= nil and refs.gui.Enabled
end

local function build()
	local touch = UI.isTouch()
	local buttonHeight = if touch then 44 else 38
	local gui = UI.screen("NAU_Tutorial", 40, true)
	gui.Enabled = false
	refs.gui = gui
	refs.steps = steps()

	UI.new("TextButton", { -- a dim backdrop that swallows clicks
		Name = "Backdrop",
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UI.Colors.Ink,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = gui,
	})
	-- Never wider than the screen (16 px gutters); on a short phone screen the card shrinks to fit.
	local card = UI.panel({
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
		BackgroundTransparency = 0,
		Parent = gui,
	})
	local fit = UI.new("UIScale", { Parent = card })
	local function fitCard()
		local viewport = UI.viewport()
		fit.Scale = math.min(1, (viewport.X - 32) / CARD_WIDTH, (viewport.Y - 24) / CARD_HEIGHT)
	end
	fitCard()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitCard)
	end
	refs.card = card
	UI.accentBar(card, "top", UI.Colors.Accent, 3)

	UI.label({
		Position = UDim2.fromOffset(22, 14),
		Size = UDim2.new(1, -140, 0, 18),
		Font = UI.Font,
		TextSize = 14,
		TextColor3 = UI.Colors.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "HOW TO PLAY  遊び方",
		Parent = card,
	})
	refs.counter = UI.label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -22, 0, 14),
		Size = UDim2.fromOffset(60, 18),
		Font = UI.Font,
		TextSize = 14,
		TextColor3 = UI.Colors.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = card,
	})
	refs.title = UI.label({
		Position = UDim2.fromOffset(22, 36),
		Size = UDim2.new(1, -44, 0, 32),
		Font = UI.FontHeavy,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = false,
		Parent = card,
	})
	refs.art = UI.new("Frame", {
		Name = "Art",
		Position = UDim2.fromOffset(22, 74),
		Size = UDim2.new(1, -44, 0, 146),
		BackgroundColor3 = UI.Colors.Ink,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Parent = card,
	})
	refs.body = UI.label({
		Position = UDim2.fromOffset(22, 228),
		Size = UDim2.new(1, -44, 0, 66),
		Font = UI.FontBody,
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})

	-- Bottom row: SKIP · dots · BACK NEXT
	local skip = UI.button({
		Name = "Skip",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 22, 1, -14),
		Size = UDim2.fromOffset(90, buttonHeight),
		BackgroundTransparency = 1,
		Font = UI.Font,
		TextSize = 15,
		TextColor3 = UI.Colors.Muted,
		Text = "SKIP",
		Parent = card,
	})
	skip.Activated:Connect(function()
		close(true)
	end)
	refs.dots = {}
	for i = 1, #refs.steps do
		refs.dots[i] = UI.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.42, (i - (#refs.steps + 1) / 2) * 16, 1, -14 - buttonHeight / 2),
			Size = UDim2.fromOffset(8, 8),
			BorderSizePixel = 0,
			Parent = card,
		}, { UI.corner(4) })
	end
	refs.next = UI.button({
		Name = "Next",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -22, 1, -14),
		Size = UDim2.fromOffset(150, buttonHeight),
		BackgroundColor3 = UI.Colors.Accent,
		Font = UI.FontHeavy,
		TextSize = 17,
		Parent = card,
	}, { UI.corner() })
	refs.next.Activated:Connect(advance)
	refs.back = UI.button({
		Name = "Back",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -182, 1, -14),
		Size = UDim2.fromOffset(90, buttonHeight),
		Font = UI.FontHeavy,
		TextSize = 16,
		Text = "BACK",
		Parent = card,
	}, { UI.corner() })
	refs.back.Activated:Connect(function()
		step = math.max(1, step - 1)
		render()
	end)
end

-- First visit: once the saved profile says it hasn't been seen, in the lobby (not mid-match).
local function maybeShowFirstVisit()
	local profile = ClientState.profile
	if shownThisSession or not profile or type(profile.settings) ~= "table" or profile.settings.tutorialDone == true then
		return
	end
	shownThisSession = true
	task.delay(FIRST_VISIT_DELAY, function()
		while ClientState.life.inMatch do
			task.wait(1)
		end
		if SettingsController.get("tutorialDone") ~= true and not TutorialController.isOpen() then
			TutorialController.open()
		end
	end)
end

function TutorialController.Start()
	build()
	SettingsController.setHowToPlay(TutorialController.open)
	ClientState.Changed:Connect(function(kind)
		if kind == "profile" then
			maybeShowFirstVisit()
		end
	end)
	maybeShowFirstVisit()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not TutorialController.isOpen() then
			return
		end
		if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.Right then
			advance()
		end
	end)
end

return TutorialController
