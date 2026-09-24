-- Settings menu (Phase 4, owner-approved 2026-09-23): motion toggles, crowd density and volume.
-- A gear button (top-right, in the top bar) opens a panel built from the shared schema (Modules/Settings).
-- Every change applies at once on this client, and is sent to the server (batched), which validates it and
-- keeps it in the saved profile; the saved values come back with ProfileState when the player joins.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Settings = require(Shared:WaitForChild("Modules"):WaitForChild("Settings"))
local AnimControllers = ReplicatedStorage:WaitForChild("Animations"):WaitForChild("Controllers")
local UIMotion = require(AnimControllers:WaitForChild("UIMotion"))
local SprintFX = require(AnimControllers:WaitForChild("SprintFX"))
local RunFOV = require(AnimControllers:WaitForChild("RunFOV"))
local CameraShake = require(AnimControllers:WaitForChild("CameraShake"))
local Crowd = require(AnimControllers:WaitForChild("Crowd"))
local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"))
local Audio = require(Client:WaitForChild("Audio"))
local ClientState = require(Client:WaitForChild("ClientState"))

local SettingsController = {}

local PANEL_WIDTH = 520
local TOUCH = UI.isTouch()
local CONTROL = if TOUCH then 44 else 30 -- control height; 44 = minimum touch target
local ROW_HEIGHT = if TOUCH then 54 else 46
local SEND_DELAY = 0.35 -- seconds of quiet before changes go to the server (sliders send once, on release)
local RETRY_DELAY = 0.3

local localPlayer = Players.LocalPlayer
local values = Settings.defaults()
local pending: { [string]: any } = {}
local sendScheduled = false
local refs: { [string]: any } = {}
local controls: { [string]: (any) -> () } = {} -- key -> refresh(value)

-- Applying ---------------------------------------------------------------------------------------

local function apply()
	SprintFX.setOptions({ speedLines = values.speedLines, cameraSway = values.cameraSway })
	RunFOV.setWide(values.runFov)
	CameraShake.setEnabled(values.screenShake)
	Crowd.setDensity(values.crowd)
	Audio.setVolume("Music", values.music)
	Audio.setVolume("Effects", values.effects)
	for key, refresh in controls do
		refresh(values[key])
	end
end

local function send()
	if next(pending) == nil then
		sendScheduled = false
		return
	end
	local batch = pending
	pending = {}
	local ok, reply = pcall(function()
		return Remotes.SetSettings:InvokeServer(batch)
	end)
	if ok and type(reply) == "table" and reply.status == "rate_limited" then
		for key, value in batch do
			if pending[key] == nil then
				pending[key] = value -- try again, unless a newer change replaced it
			end
		end
		task.delay(RETRY_DELAY, send)
		return
	end
	sendScheduled = false
	if next(pending) ~= nil then
		sendScheduled = true
		task.delay(SEND_DELAY, send)
	end
end

local howToPlay: (() -> ())? = nil -- set by TutorialController (it requires this module, not the other way)

local function set(key: string, value: any, sendNow: boolean?)
	local def = Settings.byKey[key]
	if not def or not Settings.valid(def, value) then
		return
	end
	values[key] = value
	apply()
	if sendNow == false then
		return -- a slider mid-drag: applied locally, sent on release
	end
	pending[key] = value
	if not sendScheduled then
		sendScheduled = true
		task.delay(SEND_DELAY, send)
	end
end

-- Building -----------------------------------------------------------------------------------------

local function rowFrame(parent: Instance, def: Settings.Def, order: number): Frame
	local row = UI.new("Frame", {
		Name = def.key,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UI.label({
		Name = "Label",
		Position = UDim2.fromOffset(0, if def.hint then 5 else 0),
		Size = UDim2.new(0.55, 0, 0, if def.hint then 20 else ROW_HEIGHT),
		Font = UI.Font,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = string.upper(def.label),
		Parent = row,
	})
	if def.hint then
		UI.label({
			Name = "Hint",
			Position = UDim2.fromOffset(0, 25),
			Size = UDim2.new(0.6, 0, 0, 16),
			Font = UI.FontBody,
			TextSize = 12,
			TextColor3 = UI.Colors.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = def.hint,
			Parent = row,
		})
	end
	return row
end

local function toggleControl(row: Frame, def: Settings.Def)
	local button = UI.button({
		Name = "Toggle",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(84, CONTROL),
		Font = UI.FontHeavy,
		TextSize = 16,
		Parent = row,
	}, { UI.corner() })
	button.Activated:Connect(function()
		set(def.key, not values[def.key])
		UIMotion.pop(button)
	end)
	controls[def.key] = function(on: boolean)
		button.Text = if on then "ON" else "OFF"
		button.BackgroundColor3 = if on then UI.Colors.Accent else UI.Colors.Slot
		button.TextColor3 = if on then UI.Colors.Text else UI.Colors.Muted
	end
end

local function choiceControl(row: Frame, def: Settings.Def)
	local options = def.options :: { string }
	local holder = UI.new("Frame", {
		Name = "Choice",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(110 + 2 * CONTROL, CONTROL),
		BackgroundTransparency = 1,
		Parent = row,
	})
	local value = UI.label({
		Name = "Value",
		Position = UDim2.fromOffset(CONTROL + 4, 0),
		Size = UDim2.new(1, -2 * (CONTROL + 4), 1, 0),
		Font = UI.FontHeavy,
		TextSize = 16,
		Parent = holder,
	})
	local function step(direction: number)
		local index = table.find(options, values[def.key]) or 1
		set(def.key, options[(index - 1 + direction) % #options + 1])
		UIMotion.pop(value)
	end
	for _, spec in { { "‹", 0, -1 }, { "›", 1, 1 } } do
		local arrow = UI.button({
			Name = if spec[3] < 0 then "Previous" else "Next",
			AnchorPoint = Vector2.new(spec[2], 0),
			Position = UDim2.fromScale(spec[2], 0),
			Size = UDim2.fromOffset(CONTROL, CONTROL),
			Font = UI.FontHeavy,
			TextSize = 22,
			Text = spec[1],
			Parent = holder,
		}, { UI.corner() })
		arrow.Activated:Connect(function()
			step(spec[3])
		end)
	end
	controls[def.key] = function(v: string)
		value.Text = string.upper(v)
	end
end

local function sliderControl(row: Frame, def: Settings.Def)
	local min, max = def.min :: number, def.max :: number
	local holder = UI.new("Frame", {
		Name = "Slider",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(220, CONTROL),
		BackgroundTransparency = 1,
		Parent = row,
	})
	local track = UI.new("TextButton", {
		Name = "Track",
		AutoButtonColor = false,
		Text = "",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, -52, 0, if TOUCH then 44 else 22), -- a tall hit area; the visible bar is inside
		BackgroundTransparency = 1,
		Parent = holder,
	})
	local bar = UI.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 4),
		BorderSizePixel = 0,
		BackgroundColor3 = UI.Colors.Slot,
		Parent = track,
	})
	local fill = UI.new("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, BackgroundColor3 = UI.Colors.Accent, Parent = bar })
	local knob = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(14, 14),
		BorderSizePixel = 0,
		BackgroundColor3 = UI.Colors.Text,
		Parent = bar,
	}, { UI.corner() })
	local readout = UI.label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 44, 1, 0),
		Font = UI.FontHeavy,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = holder,
	})
	local dragging = false
	local function valueAt(x: number): number
		local alpha = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
		return math.floor(min + alpha * (max - min) + 0.5)
	end
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			set(def.key, valueAt(input.Position.X), false)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			set(def.key, valueAt(input.Position.X), false)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			set(def.key, values[def.key]) -- released: send it
		end
	end)
	controls[def.key] = function(v: number)
		local alpha = (v - min) / (max - min)
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		readout.Text = tostring(v)
	end
end

local function setOpen(open: boolean)
	refs.panel.Visible = open
	refs.backdrop.Visible = open
	refs.gear.BackgroundColor3 = if open then UI.Colors.Accent else UI.Colors.Panel
	if open then
		UIMotion.pop(refs.panel)
	end
end

local function build()
	local gui = UI.screen("NAU_Settings", 30, true)
	refs.gui = gui

	-- Gear: top-right, below Roblox's top bar (its height differs between PC and phones), with the yen counter
	-- to its left (HUDController leaves room for it).
	local buttonGui = UI.screen("NAU_SettingsButton", 31) -- above the menu's backdrop, so the gear also closes it
	local gearSize = UI.gearSize()
	refs.gear = UI.button({
		Name = "Gear",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(gearSize, gearSize),
		BackgroundColor3 = UI.Colors.Panel,
		BackgroundTransparency = 0.12,
		Font = UI.FontHeavy,
		TextSize = math.floor(gearSize * 0.6),
		Text = "⚙",
		Parent = buttonGui,
	}, { UI.corner(), UI.stroke(Color3.new(1, 1, 1), 1, 0.85) })
	refs.gear.Activated:Connect(function()
		setOpen(not refs.panel.Visible)
	end)

	-- A dimmed backdrop behind the panel; clicking it closes the menu.
	refs.backdrop = UI.new("TextButton", {
		Name = "Backdrop",
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UI.Colors.Ink,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 0, -- under the gear and the panel
		Visible = false,
		Parent = gui,
	})
	refs.backdrop.Activated:Connect(function()
		setOpen(false)
	end)

	-- The panel: centred, never wider than the screen (16 px gutters), scrolls if the screen is short.
	local panel = UI.panel({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -32, 0.86, 0),
		BackgroundTransparency = 0,
		Visible = false,
		Parent = gui,
	}, {
		UI.new("UISizeConstraint", { MaxSize = Vector2.new(PANEL_WIDTH, 560) }),
	})
	refs.panel = panel
	UI.accentBar(panel, "top", UI.Colors.Accent, 3)
	UI.label({
		Name = "Title",
		Position = UDim2.fromOffset(20, 14),
		Size = UDim2.new(1, -80, 0, 30),
		Font = UI.FontHeavy,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "SETTINGS  <font color=\"#9297A3\" size=\"16\">設定</font>",
		RichText = true,
		Parent = panel,
	})
	local close = UI.button({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, if TOUCH then 8 else 14),
		Size = UDim2.fromOffset(if TOUCH then 44 else 34, if TOUCH then 44 else 34),
		Font = UI.FontHeavy,
		TextSize = 18,
		Text = "X",
		Parent = panel,
	}, { UI.corner() })
	close.Activated:Connect(function()
		setOpen(false)
	end)

	local list = UI.new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(20, 58),
		Size = UDim2.new(1, -40, 1, -72),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = UI.Colors.Line,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = panel,
	}, {
		UI.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }),
		UI.new("UIPadding", { PaddingRight = UDim.new(0, 10) }),
	})

	local order = 0
	for _, section in Settings.SECTIONS do
		order += 1
		UI.label({
			Name = "Section_" .. section,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 28),
			Font = UI.Font,
			TextSize = 13,
			TextColor3 = UI.Colors.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			Text = section,
			Parent = list,
		})
		for _, def in Settings.DEFS do
			if def.section == section then
				order += 1
				local row = rowFrame(list, def, order)
				if def.kind == "toggle" then
					toggleControl(row, def)
				elseif def.kind == "choice" then
					choiceControl(row, def)
				else
					sliderControl(row, def)
				end
			end
		end
	end

	-- HOW TO PLAY: reopens the first-join walkthrough (TutorialController).
	local help = UI.button({
		Name = "HowToPlay",
		LayoutOrder = order + 1,
		Size = UDim2.new(1, 0, 0, if TOUCH then 48 else 40),
		BackgroundColor3 = UI.Colors.Slot,
		Font = UI.FontHeavy,
		TextSize = 17,
		Text = "HOW TO PLAY",
		Parent = list,
	}, { UI.corner() })
	help.Activated:Connect(function()
		if howToPlay then
			setOpen(false)
			howToPlay()
		end
	end)
end

function SettingsController.get(key: string): any
	return values[key]
end

-- Changes a setting from another controller (applied here, saved through the server like a menu change).
function SettingsController.set(key: string, value: any)
	set(key, value)
end

-- The HOW TO PLAY button at the bottom of the menu opens this.
function SettingsController.setHowToPlay(open: () -> ())
	howToPlay = open
end

function SettingsController.close()
	if refs.panel then
		setOpen(false)
	end
end

function SettingsController.Start()
	build()
	apply()
	-- The saved values arrive with the profile (or the defaults, when this session can't be saved).
	local function onProfile()
		local profile = ClientState.profile
		if profile and type(profile.settings) == "table" then
			local saved = Settings.sanitize(profile.settings)
			for key, value in pending do
				saved[key] = value -- a change made while the profile loaded wins
			end
			values = saved
			apply()
		end
	end
	ClientState.Changed:Connect(function(kind)
		if kind == "profile" then
			onProfile()
		end
	end)
	onProfile()
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Escape and refs.panel.Visible then
			setOpen(false)
		end
	end)
	localPlayer.CharacterAdded:Connect(function()
		apply() -- sprint effects and the camera are per character
	end)
end

return SettingsController
