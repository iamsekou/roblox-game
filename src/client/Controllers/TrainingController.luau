-- Training Grounds on screen (owner-approved 2026-09-29).
--   Public servers: a TRAINING slab under FIGHT in the lobby's action stack (bottom-left). One click and the server
--   teleports you to your own training server (Systems/TrainingService).
--   Training servers: TRAINING MENU and LEAVE DOJO buttons, and the training menu (also opened from the training
--   board's prompt in the dojo hall): how many training dummies, switch fighter on the spot, HOW TO PLAY (the
--   tutorial, optional here), and leaving (back to the lobby). Every change is decided by the server.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Constants = require(Shared:WaitForChild("Modules"):WaitForChild("Constants"))
local CharacterDefs = require(Shared:WaitForChild("Modules"):WaitForChild("CharacterDefs"))
local UIMotion = require(ReplicatedStorage:WaitForChild("Animations"):WaitForChild("Controllers"):WaitForChild("UIMotion"))
local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"))
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local TutorialController = require(script.Parent:WaitForChild("TutorialController"))
local LobbyController = require(script.Parent:WaitForChild("LobbyController"))

local TrainingController = {}

local TOUCH = UI.isTouch()
local BUTTON_H = if TOUCH then 44 else 34
local WOOD = Color3.fromRGB(120, 82, 52)
local PAPER = Color3.fromRGB(240, 234, 218)
local INK = Color3.fromRGB(28, 24, 22)
local LACQUER = Color3.fromRGB(176, 42, 36)

local refs: { [string]: any } = {}
local busy = false

local function trainingInfo(): { bots: number }
	local info = ClientState.round and ClientState.round.training
	if type(info) == "table" and type(info.bots) == "number" then
		return info
	end
	return { bots = Constants.TRAINING_DEFAULT_BOTS }
end

-- Teleports ----------------------------------------------------------------------------------------------

local ENTER_MESSAGES: { [string]: { string } } = {
	teleporting = { "Heading to the Training Grounds...", "good" },
	studio = { "Teleports don't run in Studio: set NAU_DevTraining on ServerScriptService before Play", "info" },
	in_round = { "Finish your round first (or wait to respawn), then train", "info" },
	rate_limited = { "One moment...", "info" },
	failed = { "Couldn't reach the Training Grounds. Try again.", "bad" },
}

local function callTeleport(remote: RemoteFunction, button: TextButton)
	if busy then
		return
	end
	busy = true
	UIMotion.punch(button)
	local ok, result = pcall(function()
		return remote:InvokeServer()
	end)
	busy = false
	local status = if ok and type(result) == "table" then result.status else "failed"
	local message = ENTER_MESSAGES[status] or ENTER_MESSAGES.failed
	HUDController.toast(message[1], message[2])
end

-- The training menu -----------------------------------------------------------------------------------------

local function send(changes: { [string]: any })
	task.spawn(function()
		local ok, result = pcall(function()
			return Remotes.TrainingConfig:InvokeServer(changes)
		end)
		if not ok or type(result) ~= "table" then
			HUDController.toast("Couldn't reach the server. Try again.", "bad")
		elseif result.status == "rate_limited" then
			HUDController.toast("One moment...", "info")
		end
	end)
end

local function styleChoice(button: TextButton, on: boolean)
	button.BackgroundColor3 = if on then LACQUER else PAPER
	button.TextColor3 = if on then PAPER else INK
end

local function refreshMenu()
	if not refs.menu then
		return
	end
	local info = trainingInfo()
	refs.botCount.Text = tostring(info.bots)
	local owned = ClientState.ability.owned or {}
	local current = ClientState.ability.character or ClientState.ability.equipped
	for id, button in refs.fighters do
		local has = table.find(owned, id) ~= nil
		button.Visible = has
		styleChoice(button, current == id)
	end
end

local function setMenuOpen(open: boolean)
	if not refs.menu then
		return
	end
	refs.menu.Visible = open
	if open then
		refreshMenu()
		UIMotion.pop(refs.menuPanel)
	end
end

local function label(parent: Instance, text: string, order: number)
	UI.label({
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 20),
		Font = UI.FontHeavy,
		TextSize = 14,
		TextColor3 = Color3.fromRGB(120, 60, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
		Parent = parent,
	})
end

local function row(parent: Instance, order: number, height: number?): Frame
	return UI.new("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, height or BUTTON_H),
		BackgroundTransparency = 1,
		Parent = parent,
	}, {
		UI.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
end

local function woodButton(props: { [string]: any }): TextButton
	local button = UI.button({
		Name = props.Name or "Button",
		Size = props.Size or UDim2.fromOffset(100, BUTTON_H),
		BackgroundColor3 = props.BackgroundColor3 or PAPER,
		TextColor3 = props.TextColor3 or INK,
		Font = UI.FontHeavy,
		TextSize = props.TextSize or 15,
		Text = props.Text or "",
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	}, { UI.corner(), UI.stroke(INK, 1, 0.4) })
	return button
end

local function buildMenu(gui: ScreenGui)
	local backdrop = UI.new("TextButton", {
		Name = "TrainingMenu",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 5,
		Parent = gui,
	})
	backdrop.Activated:Connect(function()
		setMenuOpen(false)
	end)
	refs.menu = backdrop
	local panel = UI.new("Frame", {
		Name = "Panel",
		Active = true, -- taps on the panel don't fall through to the backdrop
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -32, 0.9, 0),
		BackgroundColor3 = Color3.fromRGB(46, 34, 26),
		Parent = backdrop,
	}, {
		UI.corner(),
		UI.stroke(WOOD, 3, 0),
		UI.new("UISizeConstraint", { MaxSize = Vector2.new(520, 600) }),
	})
	refs.menuPanel = panel
	UI.accentBar(panel, "top", LACQUER, 4)
	UI.label({
		Position = UDim2.fromOffset(18, 12),
		Size = UDim2.new(1, -80, 0, 32),
		Font = UI.FontHeavy,
		TextSize = 28,
		TextColor3 = PAPER,
		TextXAlignment = Enum.TextXAlignment.Left,
		RichText = true,
		Text = 'TRAINING BOARD  <font color="#B89A78" size="16">道場</font>',
		Parent = panel,
	})
	local close = woodButton({ Name = "Close", Text = "X", Size = UDim2.fromOffset(BUTTON_H, BUTTON_H), Parent = panel })
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 10)
	close.Activated:Connect(function()
		setMenuOpen(false)
	end)

	local list = UI.new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(18, 56),
		Size = UDim2.new(1, -36, 1, -68),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = panel,
	}, {
		UI.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
		UI.new("UIPadding", { PaddingRight = UDim.new(0, 8) }),
	})

	-- Training dummies: - n +
	label(list, "TRAINING DUMMIES", 1)
	local botRow = row(list, 2)
	botRow.Name = "Bots"
	local minus = woodButton({ Name = "Minus", Text = "-", Size = UDim2.fromOffset(BUTTON_H + 10, BUTTON_H), LayoutOrder = 1, Parent = botRow })
	refs.botCount = UI.label({ Name = "Count", LayoutOrder = 2, Size = UDim2.fromOffset(60, BUTTON_H), Font = UI.FontHeavy, TextSize = 26, TextColor3 = PAPER, Text = "3", Parent = botRow })
	local plus = woodButton({ Name = "Plus", Text = "+", Size = UDim2.fromOffset(BUTTON_H + 10, BUTTON_H), LayoutOrder = 3, Parent = botRow })
	UI.label({ LayoutOrder = 4, Size = UDim2.fromOffset(170, BUTTON_H), TextSize = 13, TextColor3 = Color3.fromRGB(184, 154, 120), TextXAlignment = Enum.TextXAlignment.Left, Text = "0 = practise alone (max 11)", Parent = botRow })
	local function stepBots(delta: number)
		local info = trainingInfo()
		local n = math.clamp((info.bots or 0) + delta, 0, Constants.TRAINING_MAX_BOTS)
		if n ~= info.bots then
			refs.botCount.Text = tostring(n)
			send({ bots = n })
		end
	end
	minus.Activated:Connect(function()
		stepBots(-1)
	end)
	plus.Activated:Connect(function()
		stepBots(1)
	end)

	UI.label({
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = 12,
		TextColor3 = Color3.fromRGB(184, 154, 120),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Dummies turn now and then: step in front of one, read its number, type it (F)",
		TextWrapped = true,
		Parent = list,
	})

	-- Fighter: switch on the spot (owned fighters only).
	label(list, "FIGHT AS", 8)
	local grid = UI.new("Frame", {
		Name = "Fighters",
		LayoutOrder = 9,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = list,
	}, {
		UI.new("UIGridLayout", { CellSize = UDim2.new(0.2, -5, 0, BUTTON_H), CellPadding = UDim2.fromOffset(5, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	refs.fighters = {}
	for i, def in CharacterDefs.list do
		local button = woodButton({ Name = def.id, Text = string.upper(def.name), TextSize = 13, LayoutOrder = i, Parent = grid })
		refs.fighters[def.id] = button
		button.Activated:Connect(function()
			task.spawn(function()
				local ok, result = pcall(function()
					return Remotes.EquipCharacter:InvokeServer(def.id)
				end)
				if ok and type(result) == "table" and result.status == "equipped" then
					HUDController.toast(string.format("Fighting as %s", def.name), "good")
				else
					HUDController.toast("Couldn't switch fighter. Try again.", "bad")
				end
			end)
		end)
	end

	-- How to play, leave.
	local footer = row(list, 10, BUTTON_H + 8)
	footer.Name = "Footer"
	local help = woodButton({ Name = "HowToPlay", Text = "HOW TO PLAY", Size = UDim2.new(0.5, -3, 0, BUTTON_H), LayoutOrder = 1, Parent = footer })
	help.Activated:Connect(function()
		setMenuOpen(false)
		TutorialController.open()
	end)
	local leave = woodButton({ Name = "LeaveDojo", Text = "LEAVE DOJO", Size = UDim2.new(0.5, -3, 0, BUTTON_H), BackgroundColor3 = INK, TextColor3 = PAPER, LayoutOrder = 2, Parent = footer })
	leave.Activated:Connect(function()
		callTeleport(Remotes.LeaveTraining, leave)
	end)
end

-- Building ----------------------------------------------------------------------------------------------

local function buildPublic()
	-- The secondary call to action under FIGHT, in the lobby's own stack (it shows and hides with it).
	local action = UI.actionButton({
		name = "Training",
		title = "TRAINING",
		caption = "DOJO · PRACTISE ON DUMMIES",
		accent = UI.Colors.Gold,
		height = if TOUCH then 50 else 52,
		order = 4,
		parent = LobbyController.actionStack(),
	})
	refs.enter = action
	action.button.Activated:Connect(function()
		callTeleport(Remotes.EnterTraining, action.button)
	end)
end

local function buildTraining()
	local gui = UI.screen("NAU_Training", 6)
	-- Same place and style as the lobby's action stack (bottom-left, clear of the ability slots; higher on touch,
	-- clear of the thumbstick's corner).
	local bar = UI.new("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 1),
		Position = if TOUCH then UDim2.new(0, 16, 1, -110) else UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(if TOUCH then 230 else 250, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		UI.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
	})
	local menu = UI.actionButton({
		name = "Menu",
		title = "TRAINING MENU",
		caption = "DUMMIES · FIGHTER · HOW TO PLAY",
		accent = UI.Colors.Gold,
		height = if TOUCH then 50 else 48,
		order = 1,
		parent = bar,
	})
	menu.button.Activated:Connect(function()
		UIMotion.punch(menu.button)
		setMenuOpen(not refs.menu.Visible)
	end)
	local leave = UI.actionButton({
		name = "Leave",
		title = "LEAVE DOJO",
		caption = "BACK TO THE LOBBY",
		accent = UI.Colors.Line,
		height = if TOUCH then 46 else 42,
		order = 2,
		parent = bar,
	})
	leave.button.Activated:Connect(function()
		callTeleport(Remotes.LeaveTraining, leave.button)
	end)
	buildMenu(gui)
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if player == Players.LocalPlayer and prompt:GetAttribute("Action") == "Training" then
			setMenuOpen(true)
		end
	end)
	ClientState.Changed:Connect(function(kind)
		if kind == "round" or kind == "ability" then
			refreshMenu()
		end
	end)
	task.delay(2, function()
		HUDController.toast("Welcome to the Training Grounds. Read a dummy's number and type it (F). TRAINING MENU sets how many.", "info")
	end)
end

function TrainingController.Start()
	Remotes.TrainingNotice.OnClientEvent:Connect(function(notice)
		if type(notice) == "table" and notice.kind == "teleport_failed" then
			HUDController.toast("The teleport didn't go through. Try again.", "bad")
		end
	end)
	if ClientState.isTraining() then
		buildTraining()
	else
		buildPublic()
	end
end

return TrainingController
