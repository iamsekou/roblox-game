-- Admin panel (owner, 2026-09-30: "an admin panel for me and sam"). Built only when the server says this player
-- is an admin (Remotes.AdminState); everyone else never gets the button or the panel. The panel only *asks*
-- (Remotes.AdminCommand): the server re-checks who is asking and every value before anything happens.
--
-- Layout: an ADMIN button top-right, left of the credits counter; the panel has a player picker and four sections: CREDITS & XP (for the
-- picked player), ROUND, MODERATION (kick the picked player, two taps to confirm) and TESTING (for yourself),
-- then the recent actions every admin on this server took.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local AnimControllers = ReplicatedStorage:WaitForChild("Animations"):WaitForChild("Controllers")
local UIMotion = require(AnimControllers:WaitForChild("UIMotion"))
local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"))
local HUDController = require(script.Parent:WaitForChild("HUDController"))

local AdminController = {}

local TOUCH = UI.isTouch()
local CONTROL = if TOUCH then 44 else 32
local PANEL_WIDTH = 560
local KICK_CONFIRM_SECONDS = 4

local localPlayer = Players.LocalPlayer
local refs: { [string]: any } = {}
local state: { [string]: any } = { log = {}, unlockAll = false, ghost = false }
local selected: Player = localPlayer
local busy = false
local kickArmedUntil = 0

local REASONS: { [string]: string } = {
	denied = "Not an admin",
	rate_limited = "Too fast, try again",
	unknown_command = "Unknown command",
	malformed = "Bad request",
	bad_target = "Pick a player first",
	bad_credits = "Enter a whole amount (1 to 1,000,000)",
	bad_xp = "Enter a whole amount of XP (1 to 100,000)",
	bad_seconds = "Enter seconds (5 to 3600)",
	bad_reason = "Reason too long (120 characters max)",
}

-- Sending ------------------------------------------------------------------------------------------

local function send(command: string, args: { [string]: any }?)
	if busy then
		return
	end
	busy = true
	local ok, reply = pcall(function()
		return Remotes.AdminCommand:InvokeServer(command, args)
	end)
	busy = false
	if not ok or type(reply) ~= "table" then
		HUDController.toast("Connection hiccup, try again", "bad")
		return
	end
	if reply.status == "ok" then
		HUDController.toast(tostring(reply.message or "Done"), "good")
	elseif reply.status == "refused" or reply.status == "error" then
		HUDController.toast(tostring(reply.message or "Couldn't do that"), "bad")
	else
		HUDController.toast(REASONS[reply.status] or tostring(reply.status), "bad")
	end
end

local function amountIn(box: TextBox): number?
	local digits = string.gsub(box.Text, "[,%s]", "")
	return tonumber(digits)
end

-- Building blocks ------------------------------------------------------------------------------------

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function section(title: string)
	UI.label({
		LayoutOrder = nextOrder(),
		Size = UDim2.new(1, 0, 0, 26),
		Font = UI.Font,
		TextSize = 13,
		TextColor3 = UI.Colors.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Text = title,
		Parent = refs.list,
	})
end

local function row(): Frame
	return UI.new("Frame", {
		LayoutOrder = nextOrder(),
		Size = UDim2.new(1, 0, 0, CONTROL),
		BackgroundTransparency = 1,
		Parent = refs.list,
	}, {
		UI.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})
end

local function button(parent: Instance, text: string, width: number, onClick: () -> (), color: Color3?): TextButton
	local b = UI.button({
		LayoutOrder = #parent:GetChildren(),
		Size = UDim2.new(width, if width < 1 then -6 else 0, 1, 0),
		BackgroundColor3 = color or UI.Colors.Slot,
		Font = UI.FontHeavy,
		TextSize = if TOUCH then 15 else 14,
		TextScaled = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = text,
		Parent = parent,
	}, { UI.corner() })
	b.Activated:Connect(function()
		task.spawn(onClick)
	end)
	return b
end

local function textBox(parent: Instance, placeholder: string, width: number): TextBox
	return UI.new("TextBox", {
		LayoutOrder = #parent:GetChildren(),
		Size = UDim2.new(width, -6, 1, 0),
		BackgroundColor3 = UI.Colors.Ink,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		FontFace = UI.FontBody,
		TextSize = 15,
		TextColor3 = UI.Colors.Text,
		PlaceholderText = placeholder,
		PlaceholderColor3 = UI.Colors.Muted,
		Text = "",
		Parent = parent,
	}, { UI.corner(), UI.stroke(UI.Colors.Line, 1, 0), UI.padding(0, 8) })
end

-- The player picker -----------------------------------------------------------------------------------

local function refreshPlayers()
	local grid = refs.playerGrid
	for _, child in grid:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	if not selected.Parent then
		selected = localPlayer
	end
	local list = Players:GetPlayers()
	table.sort(list, function(a, b)
		return a.Name:lower() < b.Name:lower()
	end)
	for i, player in list do
		local picked = player == selected
		local b = UI.button({
			Name = "Player_" .. player.UserId,
			LayoutOrder = i,
			BackgroundColor3 = if picked then UI.Colors.Accent else UI.Colors.Slot,
			Font = UI.Font,
			TextSize = 14,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = if player == localPlayer then player.Name .. " (you)" else player.Name,
			Parent = grid,
		}, { UI.corner() })
		b.Activated:Connect(function()
			selected = player
			kickArmedUntil = 0
			refreshPlayers()
		end)
	end
	refs.selectedLabel.Text = "PICKED: " .. string.upper(selected.Name)
	refs.kick.Text = "KICK " .. string.upper(selected.Name)
end

-- State from the server ---------------------------------------------------------------------------------

local function refreshState()
	if not refs.panel then
		return
	end
	for mode, b in refs.modeButtons do
		local active = (state.mode or "random") == mode
		b.BackgroundColor3 = if active then UI.Colors.Accent else UI.Colors.Slot
	end
	refs.unlock.Text = if state.unlockAll then "UNLOCK ALL FIGHTERS: ON" else "UNLOCK ALL FIGHTERS: OFF"
	refs.unlock.BackgroundColor3 = if state.unlockAll then UI.Colors.Accent else UI.Colors.Slot
	refs.ghost.Text = if state.ghost then "GHOST: ON" else "GHOST: OFF"
	refs.ghost.BackgroundColor3 = if state.ghost then UI.Colors.Accent else UI.Colors.Slot
	local lines = {}
	for i, entry in state.log or {} do
		if i > 12 then
			break
		end
		table.insert(lines, if type(entry) == "table" then tostring(entry.text) else tostring(entry))
	end
	refs.log.Text = if #lines > 0 then table.concat(lines, "\n") else "Nothing yet"
end

-- The panel ---------------------------------------------------------------------------------------------

local function setOpen(open: boolean)
	refs.panel.Visible = open
	refs.backdrop.Visible = open
	refs.open.BackgroundColor3 = if open then UI.Colors.Accent else UI.Colors.Panel
	if open then
		refreshPlayers()
		refreshState()
		UIMotion.pop(refs.panel)
	end
end

local function build()
	local gui = UI.screen("NAU_Admin", 32, true)
	local buttonGui = UI.screen("NAU_AdminButton", 33)
	-- Top-right, in the gear's row just left of the credits counter. Nowhere else up there is free: Roblox's chat
	-- window opens under the top bar on the left, and its player list under the gear on the right (both swallow
	-- clicks). The counter widens as credits grow, so the button follows its left edge.
	local gearSize = UI.gearSize()
	refs.open = UI.button({
		Name = "AdminButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(10 + gearSize + 6 + 60 + 6), 0, 8), -- until the counter is found
		Size = UDim2.fromOffset(if TOUCH then 88 else 76, gearSize),
		BackgroundColor3 = UI.Colors.Panel,
		BackgroundTransparency = 0.12,
		Font = UI.FontHeavy,
		TextSize = 15,
		Text = "ADMIN",
		Parent = buttonGui,
	}, { UI.corner(), UI.stroke(UI.Colors.Gold, 1, 0.3) })
	refs.open.Activated:Connect(function()
		setOpen(not refs.panel.Visible)
	end)
	task.spawn(function()
		local hud = localPlayer:WaitForChild("PlayerGui"):WaitForChild("NAU_HUD", 30)
		local counter = hud and hud:WaitForChild("Yen", 30)
		if not counter or not counter:IsA("GuiObject") then
			return
		end
		local function follow()
			refs.open.Position = UDim2.fromOffset(counter.AbsolutePosition.X - 6, 8)
			refs.open.AnchorPoint = Vector2.new(1, 0)
		end
		counter:GetPropertyChangedSignal("AbsolutePosition"):Connect(follow)
		counter:GetPropertyChangedSignal("AbsoluteSize"):Connect(follow)
		follow()
	end)

	refs.backdrop = UI.new("TextButton", {
		Name = "Backdrop",
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UI.Colors.Ink,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 0,
		Visible = false,
		Parent = gui,
	})
	refs.backdrop.Activated:Connect(function()
		setOpen(false)
	end)

	local panel = UI.panel({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -32, 0.88, 0),
		BackgroundTransparency = 0,
		Visible = false,
		Parent = gui,
	}, { UI.new("UISizeConstraint", { MaxSize = Vector2.new(PANEL_WIDTH, 640) }) })
	refs.panel = panel
	UI.accentBar(panel, "top", UI.Colors.Gold, 3)
	UI.label({
		Position = UDim2.fromOffset(20, 14),
		Size = UDim2.new(1, -80, 0, 30),
		Font = UI.FontHeavy,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "ADMIN",
		Parent = panel,
	})
	local close = UI.button({
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

	refs.list = UI.new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(20, 56),
		Size = UDim2.new(1, -40, 1, -68),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = UI.Colors.Line,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = panel,
	}, {
		UI.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
		UI.new("UIPadding", { PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }),
	})

	-- Player picker
	section("PLAYER")
	refs.playerGrid = UI.new("Frame", {
		LayoutOrder = nextOrder(),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = refs.list,
	}, {
		UI.new("UIGridLayout", {
			CellSize = UDim2.new(0.5, -3, 0, CONTROL),
			CellPadding = UDim2.fromOffset(6, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	refs.selectedLabel = UI.label({
		LayoutOrder = nextOrder(),
		Size = UDim2.new(1, 0, 0, 20),
		Font = UI.Font,
		TextSize = 14,
		TextColor3 = UI.Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = refs.list,
	})

	-- Credits & XP for the picked player
	section("CREDITS & XP  (picked player)")
	local amountRow = row()
	local amount = textBox(amountRow, "Amount, e.g. 5000", 1)
	local grantRow = row()
	button(grantRow, "GIVE CREDITS", 1 / 3, function()
		send("giveCredits", { target = selected.UserId, credits = amountIn(amount) })
	end)
	button(grantRow, "TAKE CREDITS", 1 / 3, function()
		send("takeCredits", { target = selected.UserId, credits = amountIn(amount) })
	end)
	button(grantRow, "GIVE XP", 1 / 3, function()
		send("giveXp", { target = selected.UserId, xp = amountIn(amount) })
	end)

	-- Round
	section("ROUND")
	local roundRow = row()
	button(roundRow, "START NOW", 0.5, function()
		send("startRound")
	end)
	button(roundRow, "END NOW", 0.5, function()
		send("endRound")
	end)
	local timeRow = row()
	local seconds = textBox(timeRow, "Seconds, e.g. 60", 0.5)
	button(timeRow, "SET TIME LEFT", 0.5, function()
		send("setTimeLeft", { seconds = amountIn(seconds) })
	end)
	local modeRow = row()
	refs.modeButtons = {}
	for _, spec in { { "random", "RANDOM MODE" }, { "FFA", "FFA" }, { "Team6v6", "TEAM 6V6" } } do
		refs.modeButtons[spec[1]] = button(modeRow, spec[2], 1 / 3, function()
			send("setMode", { mode = spec[1] })
		end)
	end
	UI.label({
		LayoutOrder = nextOrder(),
		Size = UDim2.new(1, 0, 0, 18),
		Font = UI.FontBody,
		TextSize = 12,
		TextColor3 = UI.Colors.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "The mode applies from the next round.",
		Parent = refs.list,
	})

	-- Moderation
	section("MODERATION  (picked player)")
	local reasonRow = row()
	local reason = textBox(reasonRow, "Reason (shown to them)", 1)
	local kickRow = row()
	refs.kick = button(kickRow, "KICK", 1, function()
		local t = os.clock()
		if t > kickArmedUntil then
			kickArmedUntil = t + KICK_CONFIRM_SECONDS
			refs.kick.Text = "TAP AGAIN TO KICK " .. string.upper(selected.Name)
			task.delay(KICK_CONFIRM_SECONDS, function()
				if os.clock() >= kickArmedUntil and refs.kick then
					refs.kick.Text = "KICK " .. string.upper(selected.Name)
				end
			end)
			return
		end
		kickArmedUntil = 0
		send("kick", { target = selected.UserId, reason = reason.Text })
		refs.kick.Text = "KICK " .. string.upper(selected.Name)
	end, UI.Colors.Bad)

	-- Testing (for yourself)
	section("TESTING  (you)")
	local testRow1 = row()
	refs.unlock = button(testRow1, "UNLOCK ALL FIGHTERS", 0.5, function()
		send("unlockAll", { on = not state.unlockAll })
	end)
	refs.ghost = button(testRow1, "GHOST", 0.5, function()
		send("ghost", { on = not state.ghost })
	end)
	local testRow2 = row()
	button(testRow2, "DUEL A BOT", 0.5, function()
		setOpen(false)
		send("duel", { duel = "bot" })
	end)
	button(testRow2, "WATCH 2 BOTS DUEL", 0.5, function()
		setOpen(false)
		send("duel", { duel = "watch" })
	end)

	-- Recent actions
	section("RECENT ACTIONS  (this server)")
	refs.log = UI.label({
		LayoutOrder = nextOrder(),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = UI.FontBody,
		TextSize = 13,
		TextColor3 = UI.Colors.Muted,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "Nothing yet",
		Parent = refs.list,
	})
end

function AdminController.Start()
	Remotes.AdminState.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or payload.admin ~= true then
			return
		end
		state = payload
		if not refs.panel then
			build()
			Players.PlayerAdded:Connect(function()
				if refs.panel.Visible then
					refreshPlayers()
				end
			end)
			Players.PlayerRemoving:Connect(function()
				task.defer(function()
					if refs.panel.Visible then
						refreshPlayers()
					end
				end)
			end)
		end
		refreshState()
	end)
end

return AdminController
