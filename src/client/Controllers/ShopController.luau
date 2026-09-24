-- The yen shop menu (Phase 3 item 5, approved 2026-09-23): an over-the-top futuristic hologram interface
-- with anime energy, opened from the shop cottage's door in the lobby garden.
--
-- Opening: the door's ProximityPrompt (attribute Action = "Shop"). Movement is frozen, the camera glides to
-- the door and through it to the cottage's high-tech room, where a hologram copy of the player's avatar
-- stands on the projector pad playing the selected character's ability animations (AbilityAnim.preview).
-- The menu then boots: a scan sweep, a glitch, and the panels unfold.
--
--   left   ROSTER: all ten characters (portrait, name, price or state)
--   right  DETAIL: name, identity, both abilities with preview buttons, price, what a purchase includes,
--          and the action: HOLD TO BUY (1 s charge) / EQUIP / EQUIPPED / Robux coming soon
--   top    title and the yen balance (animated counter)
--
-- The client only asks: PurchaseItem and EquipCharacter are decided by the server (ShopService /
-- AbilityService); the menu redraws from what the server sends back (balance, owned list, equipped).
-- EXIT or [X] closes it and reverses everything; it also closes itself if the player leaves the lobby.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local CharacterDefs = require(Shared:WaitForChild("Modules"):WaitForChild("CharacterDefs"))
local AnimControllers = ReplicatedStorage:WaitForChild("Animations"):WaitForChild("Controllers")
local AbilityAnim = require(AnimControllers:WaitForChild("AbilityAnim"))
local CameraShake = require(AnimControllers:WaitForChild("CameraShake"))
local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"))
local Audio = require(Client:WaitForChild("Audio"))

local ShopController = {}

local localPlayer = Players.LocalPlayer

-- Look
local HOLO = Color3.fromRGB(80, 230, 255)
local PINK = Color3.fromRGB(255, 90, 200)
local GOLD = Color3.fromRGB(255, 208, 110)
local GLASS = Color3.fromRGB(8, 14, 22)
local WHITE = Color3.new(1, 1, 1)
local HEAVY = UI.FontHeavy
local BODY = UI.FontBody
local DESKTOP_CANVAS = Vector2.new(1920, 1080) -- the menu is laid out on this canvas and scaled to the screen
-- Phones (Phase 4 phone pass): a compact layout on a canvas 700 units tall, as wide as the screen's shape
-- allows, so text stays at least ~11 pt and every button at least 44 pt on a 390 pt tall phone.
local PHONE_CANVAS_HEIGHT = 700
local CANVAS = DESKTOP_CANVAS -- the canvas in use (set when the menu is built)
local phoneLayout = false

-- Timing
local HOLD_TO_BUY = 1 -- seconds the BUY button must be held
local PREVIEW_EVERY = 3.4 -- seconds between the hologram's ability previews
local EXIT_KEY = Enum.KeyCode.X

type Refs = { [string]: any }
local refs: Refs = { cards = {}, gradients = {} }
local state = {
	open = false,
	busy = false,
	selected = nil :: any,
	previewSlot = "mild",
	nextPreview = 0,
	yenShown = 0,
	holdStarted = nil :: number?,
}
local scene: { [string]: any } = {}

-- Small helpers ----------------------------------------------------------------------------------

local function yen(): number
	local stats = localPlayer:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Yen")
	return if value and value:IsA("IntValue") then value.Value else 0
end

local function owned(id: string): boolean
	local list = ClientState.ability.owned
	return type(list) == "table" and table.find(list, id) ~= nil
end

local function equipped(id: string): boolean
	return ClientState.ability.equipped == id
end

local function tween(object: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local t = TweenService:Create(object, TweenInfo.new(seconds, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

-- A glowing neon edge whose colour flows round the frame (the gradient's rotation is animated while open).
local function neonEdge(frame: GuiObject, thickness: number?, transparency: number?)
	local stroke = UI.stroke(WHITE, thickness or 2, transparency or 0)
	stroke.Parent = frame
	local gradient = UI.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, HOLO),
			ColorSequenceKeypoint.new(0.5, PINK),
			ColorSequenceKeypoint.new(1, HOLO),
		}),
		Parent = stroke,
	})
	table.insert(refs.gradients, gradient)
	return stroke
end

-- Targeting-reticle brackets on the four corners of a frame.
local function brackets(frame: GuiObject, color: Color3, length: number, thickness: number)
	for _, corner in { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) } do
		local position = UDim2.new(corner.X, (corner.X * 2 - 1) * 6, corner.Y, (corner.Y * 2 - 1) * 6)
		for _, horizontal in { true, false } do
			UI.new("Frame", {
				Name = "Bracket",
				AnchorPoint = corner,
				Position = position,
				Size = if horizontal then UDim2.fromOffset(length, thickness) else UDim2.fromOffset(thickness, length),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				ZIndex = 5,
				Parent = frame,
			})
		end
	end
end

-- A dark glass panel with a flowing neon edge and corner brackets.
local function glassPanel(props: { [string]: any }): Frame
	local frame = UI.new("Frame", {
		BackgroundColor3 = GLASS,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
	})
	for key, value in props do
		frame[key] = value
	end
	UI.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.2) }),
		Parent = frame,
	})
	neonEdge(frame, 2, 0.15)
	brackets(frame, HOLO, 26, 3)
	return frame
end

local function text(props: { [string]: any }): TextLabel
	local label = UI.label({ Font = HEAVY, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left })
	for key, value in props do
		if key == "Font" then
			label.FontFace = value
		else
			(label :: any)[key] = value
		end
	end
	return label
end

-- Sound slots (owner-approved) live in the client's Audio module as "shop_<name>".
local function sound(name: string)
	Audio.play("shop_" .. name)
end

-- Effects ------------------------------------------------------------------------------------------

-- Anime speed lines bursting out from a point on the canvas.
local function speedBurst(at: Vector2, color: Color3, count: number)
	local layer = refs.fx
	if not layer then
		return
	end
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + math.random() * 0.2
		local line = UI.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(at.X + math.cos(angle) * 60, at.Y + math.sin(angle) * 60),
			Size = UDim2.fromOffset(40, if i % 3 == 0 then 3 else 2),
			Rotation = math.deg(angle),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			BackgroundTransparency = 0.1,
			Parent = layer,
		})
		local reach = 260 + math.random() * 220
		local t = tween(line, 0.32, {
			Position = UDim2.fromOffset(at.X + math.cos(angle) * reach, at.Y + math.sin(angle) * reach),
			Size = UDim2.fromOffset(180 + math.random() * 120, 1),
			BackgroundTransparency = 1,
		})
		t.Completed:Connect(function()
			line:Destroy()
		end)
	end
end

-- A short digital glitch: the frame jitters sideways and flickers for a few frames.
local function glitch(frame: GuiObject, frames: number?)
	local home = frame.Position
	task.spawn(function()
		for _ = 1, frames or 6 do
			if not frame.Parent then
				return
			end
			frame.Position = home + UDim2.fromOffset(math.random(-14, 14), math.random(-3, 3))
			task.wait(0.03)
		end
		frame.Position = home
	end)
end

-- The boot sweep: a bright scan bar racing down the screen.
local function scanSweep()
	local bar = UI.new("Frame", {
		Size = UDim2.new(1, 0, 0, 6),
		Position = UDim2.fromOffset(0, -10),
		BackgroundColor3 = HOLO,
		BorderSizePixel = 0,
		ZIndex = 20,
		Parent = refs.fx,
	})
	UI.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = bar,
	})
	local t = tween(bar, 0.55, { Position = UDim2.fromOffset(0, CANVAS.Y + 10) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	t.Completed:Connect(function()
		bar:Destroy()
	end)
end

-- Canvas ----------------------------------------------------------------------------------------

-- Roster card geometry: desktop (in the roster panel) and phone (in a scrolling list).
type CardStyle = {
	top: number, step: number, height: number, x: number, xSelected: number, xHover: number,
	portrait: number, nameSize: number, subSize: number, badgeSize: number, textX: number,
}
local DESKTOP_CARD: CardStyle = {
	top = 58, step = 72, height = 64, x = 18, xSelected = 36, xHover = 28,
	portrait = 54, nameSize = 28, subSize = 15, badgeSize = 22, textX = 76,
}
local PHONE_CARD: CardStyle = {
	top = 0, step = 92, height = 84, x = 8, xSelected = 8, xHover = 8,
	portrait = 64, nameSize = 32, subSize = 22, badgeSize = 26, textX = 86,
}

local function buildCard(parent: Instance, def: any, index: number, style: CardStyle)
	local card = UI.new("TextButton", {
		Name = "Card_" .. def.id,
		AutoButtonColor = false,
		Text = "",
		Position = UDim2.fromOffset(style.x, style.top + (index - 1) * style.step),
		Size = UDim2.new(1, -2 * style.x, 0, style.height),
		BackgroundColor3 = GLASS,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Parent = parent,
	})
	local stroke = UI.stroke(HOLO, 1, 0.75)
	stroke.Parent = card
	local tint = UI.new("Frame", { -- a coloured sheen that brightens when selected
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = def.accent,
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
		Parent = card,
	})
	UI.new("UIGradient", {
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		Parent = tint,
	})
	local portrait = UI.new("ImageLabel", {
		Position = UDim2.fromOffset(8, (style.height - style.portrait) / 2),
		Size = UDim2.fromOffset(style.portrait, style.portrait),
		BackgroundColor3 = def.bubbleCenter,
		Image = def.portrait or "",
		ScaleType = Enum.ScaleType.Crop,
		Parent = card,
	})
	UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = portrait })
	UI.new("UIStroke", { Color = def.accent, Thickness = 2, Parent = portrait })
	local textTop = (style.height - style.nameSize - style.subSize - 6) / 2
	text({ Position = UDim2.fromOffset(style.textX, textTop), Size = UDim2.fromOffset(260, style.nameSize + 4), Text = string.upper(def.name), TextSize = style.nameSize, Parent = card })
	local sub = text({
		Name = "Sub",
		Position = UDim2.fromOffset(style.textX + 1, textTop + style.nameSize + 4),
		Size = UDim2.new(1, -(style.textX + 150), 0, style.subSize + 4),
		Font = BODY,
		TextSize = style.subSize,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = UI.Colors.Muted,
		Parent = card,
	})
	local badge = text({
		Name = "Badge",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(150, style.badgeSize + 8),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = style.badgeSize,
		Parent = card,
	})
	card.MouseEnter:Connect(function()
		if state.selected ~= def then
			tween(card, 0.15, { Position = UDim2.fromOffset(style.xHover, card.Position.Y.Offset) })
		end
	end)
	card.MouseLeave:Connect(function()
		if state.selected ~= def then
			tween(card, 0.15, { Position = UDim2.fromOffset(style.x, card.Position.Y.Offset) })
		end
	end)
	refs.cards[def.id] = { card = card, stroke = stroke, tint = tint, sub = sub, badge = badge, def = def, style = style }
	return card
end

local function refreshCards()
	for _, entry in refs.cards do
		local def = entry.def
		local selected = state.selected == def
		local isOwned, isEquipped = owned(def.id), equipped(def.id)
		entry.stroke.Thickness = if selected then 2 else 1
		entry.stroke.Transparency = if selected then 0 else 0.75
		entry.tint.BackgroundTransparency = if selected then 0.55 else 0.85
		entry.card.Position = UDim2.fromOffset(if selected then entry.style.xSelected else entry.style.x, entry.card.Position.Y.Offset)
		entry.sub.Text = string.format("%s  ·  %s", def.abilities.mild, def.abilities.ultimate)
		if isEquipped then
			entry.badge.Text = "EQUIPPED"
			entry.badge.TextColor3 = HOLO
		elseif isOwned then
			entry.badge.Text = "OWNED"
			entry.badge.TextColor3 = UI.Colors.Good
		elseif def.tier == "Yen" then
			entry.badge.Text = "¥" .. UI.formatNumber(def.yenPrice or 0)
			entry.badge.TextColor3 = if yen() >= (def.yenPrice or 0) then GOLD else UI.Colors.Muted
		else
			entry.badge.Text = "ROBUX"
			entry.badge.TextColor3 = Color3.fromRGB(190, 160, 255)
		end
	end
end

-- What buying `def` would also unlock (every cheaper yen character not owned yet).
local function includes(def: any): { string }
	local names = {}
	if def.tier ~= "Yen" then
		return names
	end
	for _, other in CharacterDefs.list do
		if other ~= def and other.tier == "Yen" and (other.yenTier or 0) < (def.yenTier or 0) and not owned(other.id) then
			table.insert(names, other.name)
		end
	end
	return names
end

local function setAction(label: string, color: Color3, enabled: boolean)
	refs.actionText.Text = label
	refs.action.BackgroundColor3 = color
	refs.action.BackgroundTransparency = if enabled then 0.1 else 0.6
	refs.actionText.TextTransparency = if enabled then 0 else 0.35
	refs.action.Active = enabled
	refs.actionFill.Size = UDim2.fromScale(0, 1)
end

-- Sets `label`'s text at its largest size that fits its width (between its MaxTextSize and MinTextSize
-- attributes; anything still too long is truncated). Measured in the background (the measure yields).
local function fitText(label: TextLabel, value: string)
	label.Text = value
	local max = label:GetAttribute("MaxTextSize") or label.TextSize
	local min = label:GetAttribute("MinTextSize") or max
	label.TextSize = max
	task.spawn(function()
		local params = Instance.new("GetTextBoundsParams")
		params.Text = value
		params.Font = label.FontFace
		params.Width = 100000
		local size = max
		while size > min do
			params.Size = size
			local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
			if not ok or bounds.X <= label.Size.X.Offset then
				break
			end
			size -= 1
		end
		if label.Text == value then
			label.TextSize = size
		end
	end)
end

local function refreshDetail()
	local def = state.selected
	if not def then
		return
	end
	refs.name.Text = string.upper(def.name)
	refs.nameShadow.Text = refs.name.Text
	refs.identity.Text = def.identity
	fitText(refs.mild, def.abilities.mild)
	fitText(refs.ultimate, def.abilities.ultimate)
	refs.tier.Text = if def.tier == "Free" then "STARTER" elseif def.tier == "Yen" then string.format("TIER %d  ·  YEN", def.yenTier or 0) else "PREMIUM  ·  ROBUX"
	refs.accentBar.BackgroundColor3 = def.accent
	local extra = includes(def)
	refs.includes.Text = if #extra > 0 and not owned(def.id) then "ALSO UNLOCKS  " .. string.upper(table.concat(extra, " · ")) else ""
	if equipped(def.id) then
		setAction("EQUIPPED", Color3.fromRGB(30, 60, 70), false)
		refs.price.Text = "READY TO FIGHT"
		refs.price.TextColor3 = HOLO
	elseif owned(def.id) then
		setAction("EQUIP", Color3.fromRGB(20, 120, 140), true)
		refs.price.Text = "OWNED"
		refs.price.TextColor3 = UI.Colors.Good
	elseif def.tier == "Yen" then
		local price = def.yenPrice or 0
		local affordable = yen() >= price
		refs.price.Text = "¥" .. UI.formatNumber(price)
		refs.price.TextColor3 = if affordable then GOLD else UI.Colors.Muted
		if affordable then
			setAction("HOLD TO BUY", Color3.fromRGB(150, 30, 110), true)
		else
			setAction(string.format("NEED ¥%s MORE", UI.formatNumber(price - yen())), Color3.fromRGB(50, 40, 50), false)
		end
	else
		refs.price.Text = "ROBUX"
		refs.price.TextColor3 = Color3.fromRGB(190, 160, 255)
		setAction("ROBUX · COMING SOON", Color3.fromRGB(50, 40, 70), false)
	end
end

-- One ability line in the fighter file, with a preview button that plays it on the hologram.
type RowStyle = {
	x: number, width: number, height: number, keycap: number, keySize: number,
	captionSize: number, nameSize: number, minNameSize: number, previewSize: Vector2, previewText: number,
}
local DESKTOP_ROW: RowStyle = {
	x = 28, width = 524, height = 64, keycap = 44, keySize = 30,
	captionSize = 14, nameSize = 26, minNameSize = 26, previewSize = Vector2.new(110, 40), previewText = 18,
}
local PHONE_ROW: RowStyle = {
	x = 22, width = 516, height = 90, keycap = 56, keySize = 34,
	captionSize = 20, nameSize = 30, minNameSize = 21, previewSize = Vector2.new(150, 80), previewText = 24,
}

local function abilityRow(detail: Frame, style: RowStyle, y: number, key: string, slot: string): TextLabel
	local h = style.height
	local row = UI.new("Frame", { Position = UDim2.fromOffset(style.x, y), Size = UDim2.fromOffset(style.width, h), BackgroundColor3 = GLASS, BackgroundTransparency = 0.3, BorderSizePixel = 0, Parent = detail })
	UI.stroke(HOLO, 1, 0.7).Parent = row
	local keycap = text({
		Text = key,
		TextSize = style.keySize,
		TextColor3 = GLASS,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0,
		BackgroundColor3 = HOLO,
		Position = UDim2.fromOffset(10, (h - style.keycap) / 2),
		Size = UDim2.fromOffset(style.keycap, style.keycap),
		Parent = row,
	})
	UI.new("UICorner", { CornerRadius = UDim.new(0, 4), Parent = keycap })
	local textX = 10 + style.keycap + 16
	local captionY = (h - (style.captionSize + 2 + style.nameSize + 6)) / 2
	text({
		Text = if slot == "mild" then "MILD  ·  8 s" else "ULTIMATE  ·  20 s",
		TextSize = style.captionSize,
		TextColor3 = UI.Colors.Muted,
		Position = UDim2.fromOffset(textX, captionY),
		Size = UDim2.fromOffset(300, style.captionSize + 2),
		Parent = row,
	})
	-- Long ability names step down to fit (never below minNameSize; see fitText). TextScaled isn't used: under
	-- the canvas's UIScale it sized names past their box.
	local name = text({
		Text = "",
		TextSize = style.nameSize,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(textX, captionY + style.captionSize + 2),
		Size = UDim2.fromOffset(style.width - textX - style.previewSize.X - 20, style.nameSize + 6),
		Parent = row,
	})
	name:SetAttribute("MaxTextSize", style.nameSize)
	name:SetAttribute("MinTextSize", style.minNameSize)
	local preview = UI.new("TextButton", {
		Name = "Preview",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(style.previewSize.X, style.previewSize.Y),
		BackgroundColor3 = GLASS,
		AutoButtonColor = true,
		FontFace = HEAVY,
		TextSize = style.previewText,
		TextColor3 = HOLO,
		Text = "▶ PREVIEW",
		Parent = row,
	})
	UI.stroke(HOLO, 1, 0.3).Parent = preview
	preview.Activated:Connect(function()
		ShopController.preview(slot)
	end)
	return name
end

-- The hold-to-buy / equip button at the bottom of the fighter file.
local function actionButton(detail: Frame, height: number, bottom: number, textSize: number): TextButton
	local action = UI.new("TextButton", {
		Name = "Action",
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -bottom),
		Size = UDim2.new(1, -56, 0, height),
		BackgroundColor3 = Color3.fromRGB(150, 30, 110),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = detail,
	})
	neonEdge(action, 3, 0)
	refs.actionFill = UI.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = HOLO, BackgroundTransparency = 0.25, BorderSizePixel = 0, Parent = action })
	refs.actionText = text({ Text = "", TextSize = textSize, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = action })
	refs.action = action
	return action
end

-- Desktop: header across the top, roster left, fighter file right, the hologram framed in between.
local function buildDesktopPanels(canvas: Frame)
	-- Header: title on the left, balance and exit on the right.
	local header = UI.new("Frame", { Name = "Header", Position = UDim2.fromOffset(70, 36), Size = UDim2.fromOffset(CANVAS.X - 140, 110), BackgroundTransparency = 1, Parent = canvas })
	refs.header = header
	text({ Text = "ショップ  //  YEN EXCHANGE  //  販売中", TextSize = 20, TextColor3 = PINK, Size = UDim2.fromOffset(700, 24), Parent = header })
	local title = text({ Text = "FIGHTER EXCHANGE", TextSize = 72, Position = UDim2.fromOffset(0, 22), Size = UDim2.fromOffset(900, 80), Parent = header })
	UI.new("UIGradient", {
		Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, WHITE), ColorSequenceKeypoint.new(1, HOLO) }),
		Parent = title,
	})
	refs.title = title
	local wallet = glassPanel({ Name = "Wallet", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 6), Size = UDim2.fromOffset(360, 96), Parent = header })
	text({ Text = "BALANCE  ·  残高", TextSize = 16, TextColor3 = UI.Colors.Muted, Position = UDim2.fromOffset(22, 10), Size = UDim2.fromOffset(300, 20), Parent = wallet })
	refs.balance = text({ Text = "¥0", TextSize = 50, TextColor3 = GOLD, Position = UDim2.fromOffset(20, 30), Size = UDim2.fromOffset(320, 58), Parent = wallet })
	refs.exit = UI.new("TextButton", {
		Name = "Exit",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -380, 0, 30),
		Size = UDim2.fromOffset(170, 52),
		BackgroundColor3 = GLASS,
		BackgroundTransparency = 0.2,
		AutoButtonColor = true,
		FontFace = HEAVY,
		TextSize = 22,
		TextColor3 = WHITE,
		Text = "EXIT  [X]",
		Parent = header,
	})
	neonEdge(refs.exit, 2, 0.2)

	-- Left: the roster.
	local roster = glassPanel({ Name = "Roster", Position = UDim2.fromOffset(70, 172), Size = UDim2.fromOffset(540, 790), Parent = canvas })
	refs.roster = roster
	text({ Text = "ROSTER  ·  ロスター", TextSize = 24, TextColor3 = HOLO, Position = UDim2.fromOffset(22, 14), Size = UDim2.fromOffset(400, 30), Parent = roster })
	for i, def in CharacterDefs.list do
		local card = buildCard(roster, def, i, DESKTOP_CARD)
		card.Activated:Connect(function()
			ShopController.select(def)
		end)
	end

	-- Right: the selected character.
	refs.detailHome = UDim2.new(1, -70, 0, 172)
	local detail = glassPanel({ Name = "Detail", AnchorPoint = Vector2.new(1, 0), Position = refs.detailHome, Size = UDim2.fromOffset(580, 790), Parent = canvas })
	refs.detail = detail
	refs.accentBar = UI.new("Frame", { Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 6), BorderSizePixel = 0, BackgroundColor3 = HOLO, Parent = detail })
	text({ Text = "キャラクター  //  FIGHTER FILE", TextSize = 18, TextColor3 = PINK, Position = UDim2.fromOffset(28, 24), Size = UDim2.fromOffset(500, 22), Parent = detail })
	refs.nameShadow = text({ Text = "", TextSize = 84, TextColor3 = PINK, TextTransparency = 0.45, Position = UDim2.fromOffset(32, 50), Size = UDim2.fromOffset(530, 90), Parent = detail })
	refs.name = text({ Text = "", TextSize = 84, Position = UDim2.fromOffset(28, 46), Size = UDim2.fromOffset(530, 90), Parent = detail })
	refs.tier = text({ Text = "", TextSize = 20, TextColor3 = HOLO, Position = UDim2.fromOffset(30, 136), Size = UDim2.fromOffset(520, 24), Parent = detail })
	refs.identity = text({
		Text = "",
		Font = BODY,
		TextSize = 20,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Color3.fromRGB(200, 214, 226),
		Position = UDim2.fromOffset(30, 176),
		Size = UDim2.fromOffset(520, 80),
		Parent = detail,
	})
	refs.mild = abilityRow(detail, DESKTOP_ROW, 276, "Q", "mild")
	refs.ultimate = abilityRow(detail, DESKTOP_ROW, 352, "E", "ultimate")
	text({ Text = "PRICE  ·  価格", TextSize = 16, TextColor3 = UI.Colors.Muted, Position = UDim2.fromOffset(30, 456), Size = UDim2.fromOffset(300, 20), Parent = detail })
	refs.price = text({ Text = "", TextSize = 60, TextColor3 = GOLD, Position = UDim2.fromOffset(28, 474), Size = UDim2.fromOffset(520, 70), Parent = detail })
	refs.includes = text({ Text = "", Font = BODY, TextSize = 16, TextWrapped = true, TextColor3 = HOLO, Position = UDim2.fromOffset(30, 548), Size = UDim2.fromOffset(520, 44), Parent = detail })
	actionButton(detail, 92, 34, 36)

	-- Centre: a targeting frame round the hologram, with a caption.
	local focus = UI.new("Frame", { Name = "Focus", Position = UDim2.fromOffset(700, 190), Size = UDim2.fromOffset(520, 720), BackgroundTransparency = 1, Parent = canvas })
	brackets(focus, HOLO, 40, 2)
	refs.focusCaption = text({ Text = "", TextSize = 22, TextColor3 = HOLO, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 12), Size = UDim2.fromOffset(520, 26), Parent = focus })
	refs.focus = focus
	refs.stampSize = Vector2.new(1200, 140)
	refs.stampText = 120
end

-- Phones (Phase 4): the same menu, compact. Text is at least 20 canvas units (about 11 pt on a 390 pt tall
-- phone) and every button at least 80 (about 44 pt). The roster scrolls; the hologram still shows between the
-- two panels. The canvas is as wide as the screen's shape (fitCanvas), so the header and the hologram frame
-- are sized from the canvas edges.
local function buildPhonePanels(canvas: Frame)
	local margin, top, gap = 24, 110, 20
	local rosterWidth, detailWidth = 470, 560
	local panelHeight = PHONE_CANVAS_HEIGHT - top - 16

	local header = UI.new("Frame", { Name = "Header", Position = UDim2.fromOffset(margin, 12), Size = UDim2.new(1, -2 * margin, 0, 86), BackgroundTransparency = 1, Parent = canvas })
	refs.header = header
	local title = text({ Text = "FIGHTER EXCHANGE", TextSize = 50, Position = UDim2.fromOffset(0, 14), Size = UDim2.fromOffset(620, 58), Parent = header })
	UI.new("UIGradient", {
		Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, WHITE), ColorSequenceKeypoint.new(1, HOLO) }),
		Parent = title,
	})
	refs.title = title
	local wallet = glassPanel({ Name = "Wallet", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(300, 86), Parent = header })
	text({ Text = "BALANCE", TextSize = 20, TextColor3 = UI.Colors.Muted, Position = UDim2.fromOffset(18, 6), Size = UDim2.fromOffset(260, 24), Parent = wallet })
	refs.balance = text({ Text = "¥0", TextSize = 44, TextColor3 = GOLD, Position = UDim2.fromOffset(16, 30), Size = UDim2.fromOffset(270, 50), Parent = wallet })
	refs.exit = UI.new("TextButton", {
		Name = "Exit",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -316, 0, 3),
		Size = UDim2.fromOffset(150, 80),
		BackgroundColor3 = GLASS,
		BackgroundTransparency = 0.2,
		AutoButtonColor = true,
		FontFace = HEAVY,
		TextSize = 28,
		TextColor3 = WHITE,
		Text = "EXIT",
		Parent = header,
	})
	neonEdge(refs.exit, 2, 0.2)

	-- Left: the roster, scrolling.
	local roster = glassPanel({ Name = "Roster", Position = UDim2.fromOffset(margin, top), Size = UDim2.fromOffset(rosterWidth, panelHeight), Parent = canvas })
	refs.roster = roster
	text({ Text = "ROSTER", TextSize = 24, TextColor3 = HOLO, Position = UDim2.fromOffset(18, 10), Size = UDim2.fromOffset(300, 30), Parent = roster })
	local list = UI.new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 1, -56),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = HOLO,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.fromOffset(0, #CharacterDefs.list * PHONE_CARD.step),
		Parent = roster,
	})
	for i, def in CharacterDefs.list do
		local card = buildCard(list, def, i, PHONE_CARD)
		card.Activated:Connect(function()
			ShopController.select(def)
		end)
	end

	-- Right: the selected character.
	refs.detailHome = UDim2.new(1, -margin, 0, top)
	local detail = glassPanel({ Name = "Detail", AnchorPoint = Vector2.new(1, 0), Position = refs.detailHome, Size = UDim2.fromOffset(detailWidth, panelHeight), Parent = canvas })
	refs.detail = detail
	refs.accentBar = UI.new("Frame", { Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 6), BorderSizePixel = 0, BackgroundColor3 = HOLO, Parent = detail })
	refs.nameShadow = text({ Text = "", TextSize = 52, TextColor3 = PINK, TextTransparency = 0.45, Position = UDim2.fromOffset(25, 17), Size = UDim2.fromOffset(510, 58), Parent = detail })
	refs.name = text({ Text = "", TextSize = 52, Position = UDim2.fromOffset(22, 14), Size = UDim2.fromOffset(510, 58), Parent = detail })
	refs.tier = text({ Text = "", TextSize = 22, TextColor3 = HOLO, Position = UDim2.fromOffset(24, 70), Size = UDim2.fromOffset(510, 26), Parent = detail })
	refs.identity = text({
		Text = "",
		Font = BODY,
		TextSize = 22,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Color3.fromRGB(200, 214, 226),
		Position = UDim2.fromOffset(24, 98),
		Size = UDim2.fromOffset(512, 54),
		Parent = detail,
	})
	refs.mild = abilityRow(detail, PHONE_ROW, 158, "Q", "mild")
	refs.ultimate = abilityRow(detail, PHONE_ROW, 256, "E", "ultimate")
	text({ Text = "PRICE", TextSize = 20, TextColor3 = UI.Colors.Muted, Position = UDim2.fromOffset(24, 352), Size = UDim2.fromOffset(300, 24), Parent = detail })
	refs.price = text({ Text = "", TextSize = 44, TextColor3 = GOLD, Position = UDim2.fromOffset(22, 374), Size = UDim2.fromOffset(510, 50), Parent = detail })
	refs.includes = text({ Text = "", Font = BODY, TextSize = 20, TextWrapped = true, TextColor3 = HOLO, Position = UDim2.fromOffset(24, 424), Size = UDim2.fromOffset(512, 46), Parent = detail })
	actionButton(detail, 84, 14, 32)

	-- Centre: the hologram's frame fills whatever width is left between the panels.
	local left = margin + rosterWidth + gap
	local right = margin + detailWidth + gap
	local focus = UI.new("Frame", { Name = "Focus", Position = UDim2.fromOffset(left, top + 10), Size = UDim2.new(1, -(left + right), 0, panelHeight - 70), BackgroundTransparency = 1, Parent = canvas })
	brackets(focus, HOLO, 30, 2)
	refs.focusCaption = text({ Text = "", TextSize = 20, TextColor3 = HOLO, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 8), Size = UDim2.new(1, 0, 0, 48), Parent = focus })
	refs.focus = focus
	refs.stampSize = Vector2.new(900, 110)
	refs.stampText = 90
end

local function buildGui()
	local gui = UI.screen("NAU_Shop", 30, true)
	gui.Enabled = false
	refs.gui = gui

	phoneLayout = UI.isPhone()
	if phoneLayout then
		local viewport = UI.viewport()
		CANVAS = Vector2.new(math.floor(viewport.X * PHONE_CANVAS_HEIGHT / viewport.Y), PHONE_CANVAS_HEIGHT)
	end
	local canvas = UI.new("Frame", {
		Name = "Canvas",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CANVAS.X, CANVAS.Y),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	refs.scale = UI.new("UIScale", { Parent = canvas })
	refs.canvas = canvas

	-- Scanlines and a slow scan band over everything, very faint.
	local lines = UI.new("Frame", { Name = "Scanlines", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 15, Parent = canvas })
	for y = 0, CANVAS.Y, 18 do
		UI.new("Frame", { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = HOLO, BackgroundTransparency = 0.95, BorderSizePixel = 0, ZIndex = 15, Parent = lines })
	end
	refs.band = UI.new("Frame", { Name = "ScanBand", Size = UDim2.new(1, 0, 0, 140), BackgroundColor3 = HOLO, BackgroundTransparency = 0.94, BorderSizePixel = 0, ZIndex = 15, Parent = canvas })
	UI.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }),
		Parent = refs.band,
	})

	if phoneLayout then
		buildPhonePanels(canvas)
	else
		buildDesktopPanels(canvas)
	end

	-- Effects layer on top of everything, and a full-screen flash for purchases.
	refs.fx = UI.new("Frame", { Name = "FX", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 18, Parent = canvas })
	refs.flash = UI.new("Frame", { Name = "Flash", Size = UDim2.new(1, 400, 1, 400), Position = UDim2.fromOffset(-200, -200), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 19, Parent = canvas })
	refs.stamp = text({ Text = "UNLOCKED  解放", TextSize = refs.stampText, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = HOLO, TextStrokeColor3 = PINK, TextStrokeTransparency = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(refs.stampSize.X, refs.stampSize.Y), Visible = false, ZIndex = 20, Parent = canvas })

	-- Hold-to-buy / equip input.
	local action = refs.action
	action.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		ShopController.pressAction()
	end)
	action.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			ShopController.releaseAction()
		end
	end)
	action.MouseLeave:Connect(function()
		ShopController.releaseAction()
	end)
	refs.exit.Activated:Connect(function()
		ShopController.close()
	end)
end

local function fitCanvas()
	if not refs.scale then
		return
	end
	local size = UI.viewport()
	if phoneLayout then
		-- As tall as the screen; as wide as the screen's shape allows (the panels hang off the canvas edges).
		local scale = size.Y / PHONE_CANVAS_HEIGHT
		CANVAS = Vector2.new(math.floor(size.X / scale), PHONE_CANVAS_HEIGHT)
		refs.canvas.Size = UDim2.fromOffset(CANVAS.X, CANVAS.Y)
		refs.scale.Scale = scale
	else
		refs.scale.Scale = math.min(size.X / CANVAS.X, size.Y / CANVAS.Y)
	end
end

-- The centre of a menu element, in canvas units (for effects that burst from it).
local function canvasCenterOf(gui: GuiObject): Vector2
	local scale = if refs.scale and refs.scale.Scale > 0 then refs.scale.Scale else 1
	return (gui.AbsolutePosition + gui.AbsoluteSize / 2 - refs.canvas.AbsolutePosition) / scale
end

-- The hologram and the camera -------------------------------------------------------------------

local function findShop(): Model?
	local world = workspace:FindFirstChild("NAUWorld")
	local lobby = world and world:FindFirstChild("Lobby")
	local shop = lobby and lobby:FindFirstChild("ShopHouse", true)
	return if shop and shop:IsA("Model") then shop else nil
end

-- A hologram copy of the player's avatar on the projector pad.
local function makeHologram(stage: BasePart): Model?
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or not root or not root:IsA("BasePart") then
		return nil
	end
	local archivable = character.Archivable
	character.Archivable = true
	local copy = character:Clone()
	character.Archivable = archivable
	if not copy then
		return nil
	end
	for _, d in copy:GetDescendants() do
		-- Scripts, and anything the game hung on the real character (run trails, dust, name tags).
		if d:IsA("LuaSourceContainer") or d:IsA("ForceField") or d:IsA("Trail") or d:IsA("ParticleEmitter") or d:IsA("BillboardGui") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	copy.Name = "NAU_ShopHologram"
	local copyHumanoid = copy:FindFirstChildOfClass("Humanoid")
	if copyHumanoid then
		copyHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		copyHumanoid.EvaluateStateMachine = false
	end
	local copyRoot = copy:FindFirstChild("HumanoidRootPart") :: BasePart
	copyRoot.Anchored = true
	local lift = humanoid.HipHeight + root.Size.Y / 2
	copy:PivotTo(stage.CFrame * CFrame.new(0, lift, 0))
	local glow = UI.new("Highlight", {
		FillColor = HOLO,
		FillTransparency = 0.72,
		OutlineColor = HOLO,
		OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.Occluded,
		Parent = copy,
	})
	scene.glow = glow
	copy.Parent = workspace
	scene.stageCFrame = stage.CFrame * CFrame.new(0, lift, 0)
	return copy
end

local function cameraTween(cframe: CFrame, seconds: number, style: Enum.EasingStyle?): Tween
	local camera = workspace.CurrentCamera
	return tween(camera, seconds, { CFrame = cframe }, style or Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
end

-- Freeze the character while shopping (this place has no standard PlayerModule to disable controls
-- through, so the humanoid is held still directly and restored exactly as it was).
local function setControls(enabled: boolean)
	-- Roblox's own touch controls (thumbstick, jump) would sit over the menu's buttons on phones.
	GuiService.TouchControlsEnabled = enabled
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if not enabled then
		scene.movement = {
			humanoid = humanoid,
			walkSpeed = humanoid.WalkSpeed,
			jumpPower = humanoid.JumpPower,
			jumpHeight = humanoid.JumpHeight,
			autoRotate = humanoid.AutoRotate,
		}
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false
	elseif scene.movement then
		local saved = scene.movement
		scene.movement = nil
		if saved.humanoid.Parent then
			saved.humanoid.WalkSpeed = saved.walkSpeed
			saved.humanoid.JumpPower = saved.jumpPower
			saved.humanoid.JumpHeight = saved.jumpHeight
			saved.humanoid.AutoRotate = saved.autoRotate
		end
	end
end

-- Public -----------------------------------------------------------------------------------------

function ShopController.select(def: any)
	if state.selected == def then
		return
	end
	local first = state.selected == nil
	state.selected = def
	refreshCards()
	refreshDetail()
	refs.focusCaption.Text = string.format("%s  ·  HOLOGRAM PREVIEW", string.upper(def.name))
	if not first then
		sound("select")
		speedBurst(Vector2.new(CANVAS.X / 2, CANVAS.Y / 2), HOLO, 16)
		glitch(refs.name, 5)
		refs.detail.Position = refs.detailHome + UDim2.fromOffset(30, 0)
		tween(refs.detail, 0.25, { Position = refs.detailHome })
	end
	state.previewSlot = "mild"
	state.nextPreview = 0 -- play the new character's mild straight away
end

function ShopController.preview(slot: string)
	state.previewSlot = slot
	state.nextPreview = 0
end

function ShopController.pressAction()
	local def = state.selected
	if not def or state.busy or not refs.action.Active then
		return
	end
	if owned(def.id) then
		if equipped(def.id) then
			return
		end
		state.busy = true
		local ok, result = pcall(function()
			return Remotes.EquipCharacter:InvokeServer(def.id)
		end)
		state.busy = false
		if ok and type(result) == "table" and result.status == "equipped" then
			ClientState.ability.equipped = def.id -- the server's AbilityState follows; redraw now
			sound("equip")
			speedBurst(canvasCenterOf(refs.action), HOLO, 12)
			refreshCards()
			refreshDetail()
		end
		return
	end
	-- BUY: charge up for HOLD_TO_BUY seconds; letting go early cancels.
	state.holdStarted = os.clock()
	sound("charge")
	refs.actionFill.Size = UDim2.fromScale(0, 1)
	tween(refs.actionFill, HOLD_TO_BUY, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Linear)
	refs.actionText.Text = "CHARGING..."
end

function ShopController.releaseAction()
	if state.holdStarted and not state.busy then
		state.holdStarted = nil
		refreshDetail() -- cancelled: empty the bar, restore the label
	end
end

local function completePurchase(def: any)
	state.holdStarted = nil
	state.busy = true
	refs.actionText.Text = "PROCESSING..."
	local ok, result = pcall(function()
		return Remotes.PurchaseItem:InvokeServer(def.id)
	end)
	state.busy = false
	if not ok or type(result) ~= "table" then
		refreshDetail()
		refs.includes.Text = "CONNECTION HICCUP. TRY AGAIN."
		return
	end
	if result.status == "bought" then
		-- The server already sent the new owned list (AbilityState); fold the grant in now so the menu
		-- updates this frame.
		local list = table.clone(ClientState.ability.owned or {})
		for _, id in result.granted or {} do
			if not table.find(list, id) then
				table.insert(list, id)
			end
		end
		ClientState.ability.owned = list
		sound("purchase")
		refs.flash.BackgroundTransparency = 0.15
		tween(refs.flash, 0.6, { BackgroundTransparency = 1 })
		speedBurst(Vector2.new(CANVAS.X / 2, CANVAS.Y / 2), WHITE, 28)
		speedBurst(Vector2.new(CANVAS.X / 2, CANVAS.Y / 2), PINK, 14)
		refs.stamp.Visible = true
		refs.stamp.TextTransparency = 0
		refs.stamp.TextStrokeTransparency = 0
		refs.stamp.Size = UDim2.fromOffset(refs.stampSize.X * 1.5, refs.stampSize.Y * 1.43)
		tween(refs.stamp, 0.35, { Size = UDim2.fromOffset(refs.stampSize.X, refs.stampSize.Y) }, Enum.EasingStyle.Back)
		task.delay(1.1, function()
			local fade = tween(refs.stamp, 0.35, { TextTransparency = 1, TextStrokeTransparency = 1 })
			fade.Completed:Connect(function()
				refs.stamp.Visible = false
			end)
		end)
		CameraShake.shake(0.35, 0.3)
		state.previewSlot = "ultimate"
		state.nextPreview = 0 -- celebrate with the ultimate
	elseif result.status == "insufficient" then
		sound("denied")
		glitch(refs.price, 8)
	end
	refreshCards()
	refreshDetail()
end

local function animate(dt: number)
	if not state.open then
		return
	end
	local now = os.clock()
	-- Flowing neon edges and the drifting scan band.
	local spin = (now * 60) % 360
	for _, gradient in refs.gradients do
		gradient.Rotation = spin
	end
	refs.band.Position = UDim2.fromOffset(0, ((now * 140) % (CANVAS.Y + 280)) - 140)
	-- The yen counter rolls toward the real balance.
	local target = yen()
	if math.abs(state.yenShown - target) >= 1 then
		state.yenShown += (target - state.yenShown) * math.min(1, dt * 8)
		if math.abs(state.yenShown - target) < 1 then
			state.yenShown = target
		end
	end
	refs.balance.Text = "¥" .. UI.formatNumber(state.yenShown)
	-- Hold-to-buy completes.
	if state.holdStarted and now - state.holdStarted >= HOLD_TO_BUY and not state.busy and state.selected then
		task.spawn(completePurchase, state.selected)
	end
	-- The hologram: a slow turntable sway, a flicker, and an ability preview every few seconds.
	local hologram = scene.hologram
	if hologram and hologram.Parent and scene.stageCFrame then
		hologram:PivotTo(scene.stageCFrame * CFrame.Angles(0, math.rad(math.sin(now * 0.6) * 25), 0))
		if scene.glow then
			scene.glow.FillTransparency = 0.7 + math.sin(now * 23) * 0.04 + (if math.random() < 0.03 then 0.2 else 0)
		end
		if state.selected and now >= state.nextPreview then
			local slot = state.previewSlot
			AbilityAnim.preview(hologram, state.selected.id, slot, if slot == "mild" then 0.7 else 1.1)
			state.previewSlot = if slot == "mild" then "ultimate" else "mild"
			state.nextPreview = now + PREVIEW_EVERY
		end
	end
end

function ShopController.open()
	if state.open or state.busy then
		return
	end
	local shop = findShop()
	local door = shop and shop:FindFirstChild("ShopDoor")
	local cameraPart = shop and shop:FindFirstChild("ShopCamera")
	local stage = shop and shop:FindFirstChild("ShopStage")
	if not door or not cameraPart or not stage then
		return
	end
	state.open = true
	state.holdStarted = nil
	state.yenShown = yen()
	setControls(false)

	-- Hide the rest of the HUD while shopping.
	scene.hidden = {}
	for _, g in localPlayer.PlayerGui:GetChildren() do
		if g:IsA("ScreenGui") and g ~= refs.gui and g.Enabled then
			g.Enabled = false
			table.insert(scene.hidden, g)
		end
	end

	-- Camera: to the door, then through it to the shop camera.
	local camera = workspace.CurrentCamera
	scene.returnCFrame = camera.CFrame
	scene.returnFov = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	local doorway = door.CFrame * CFrame.new(0, 1.2, -7)
	scene.doorway = CFrame.lookAt(doorway.Position, door.Position + Vector3.new(0, 1.2, 0))
	scene.hologram = makeHologram(stage)
	tween(camera, 1.1, { FieldOfView = 52 }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	cameraTween(scene.doorway, 0.5).Completed:Wait()
	if not state.open then
		return
	end
	cameraTween(cameraPart.CFrame, 0.6, Enum.EasingStyle.Quint).Completed:Wait()
	if not state.open then
		return
	end

	-- Boot the menu: sweep, unfold, glitch.
	fitCanvas()
	refs.gui.Enabled = true
	sound("boot")
	scanSweep()
	for _, panel in { refs.roster, refs.detail } do
		local size = panel.Size
		panel.Size = UDim2.new(size.X.Scale, size.X.Offset, 0, 0)
		tween(panel, 0.45, { Size = size }, Enum.EasingStyle.Quint)
	end
	glitch(refs.header, 8)
	local pick = state.selected or CharacterDefs.byId[ClientState.ability.equipped or ""] or CharacterDefs.list[1]
	state.selected = nil
	ShopController.select(pick)
end

function ShopController.close()
	if not state.open then
		return
	end
	state.open = false
	state.holdStarted = nil
	refs.gui.Enabled = false
	local camera = workspace.CurrentCamera
	local function finish()
		if scene.hologram then
			scene.hologram:Destroy()
			scene.hologram = nil
		end
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = scene.returnFov or 70
		for _, g in scene.hidden or {} do
			if g.Parent then
				g.Enabled = true
			end
		end
		scene.hidden = nil
		setControls(true)
	end
	if scene.doorway and camera.CameraType == Enum.CameraType.Scriptable then
		task.spawn(function()
			cameraTween(scene.doorway, 0.45, Enum.EasingStyle.Quint).Completed:Wait()
			if scene.returnCFrame then
				cameraTween(scene.returnCFrame, 0.4).Completed:Wait()
			end
			if not state.open then
				finish()
			end
		end)
	else
		finish()
	end
end

function ShopController.isOpen(): boolean
	return state.open
end

function ShopController.Start()
	buildGui()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitCanvas)
	end
	RunService.RenderStepped:Connect(animate)
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if player == localPlayer and prompt:GetAttribute("Action") == "Shop" then
			task.spawn(ShopController.open)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and state.open and input.KeyCode == EXIT_KEY then
			ShopController.close()
		end
	end)
	-- Redraw when the server's view changes (a purchase, an equip); close if we leave the lobby.
	ClientState.Changed:Connect(function(kind)
		if state.open and kind == "ability" then
			refreshCards()
			refreshDetail()
		elseif state.open and kind == "life" and ClientState.life.inMatch then
			ShopController.close()
		end
	end)
	localPlayer.CharacterAdded:Connect(function()
		if state.open then
			ShopController.close()
		end
	end)
end

return ShopController
