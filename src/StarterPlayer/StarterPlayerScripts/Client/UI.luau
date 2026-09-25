-- Small helpers for building UI in code. All NAU UI is created at runtime by the controllers
-- (fully version-controlled), rather than authored as static StarterGui trees.
--
-- Style (owner, 2026-09-23: "cleaner and more aggressive, colours not distracting"): charcoal slabs
-- with sharp corners, a condensed heavy display face, off-white text, and one muted blood-red accent
-- used sparingly as thin bars. Text-bearing panels size themselves to their text (AutomaticSize)
-- so nothing spills out of its box.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")

local UI = {}

-- Touch layouts (on-screen keypad, big ability buttons) are for devices without a keyboard. Studio-only:
-- set attribute NAU_DevTouchUI = true on StarterPlayer (before pressing Play) to build them on a PC.
function UI.isTouch(): boolean
	if RunService:IsStudio() and StarterPlayer:GetAttribute("NAU_DevTouchUI") == true then
		return true
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- The screen size layouts are chosen for. Studio-only: attribute NAU_DevViewport = "844x390" on StarterPlayer
-- pretends the screen is that size (with NAU_DevTouchUI, this lays out a phone on a PC).
function UI.viewport(): Vector2
	if RunService:IsStudio() then
		local fake = StarterPlayer:GetAttribute("NAU_DevViewport")
		local w, h
		if type(fake) == "string" then
			w, h = string.match(fake, "^(%d+)x(%d+)$")
		end
		if w and h then
			return Vector2.new(tonumber(w) :: number, tonumber(h) :: number)
		end
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1024, 768)
end

-- Phones: the short side of the screen is 500 px or less (Roblox's own rule for its small touch controls).
function UI.isPhone(): boolean
	local viewport = UI.viewport()
	return math.min(viewport.X, viewport.Y) <= 500
end

-- The settings gear sits at the top-right, below Roblox's top bar, with the yen counter to its left (Phase 4).
-- 44 px on touch (minimum touch target), else the yen counter's height.
function UI.gearSize(): number
	return if UI.isTouch() then 44 else 30
end

-- Touch action buttons, arranged around Roblox's own jump button (Phase 4 phone pass). Roblox draws the jump
-- button at 70 px, 25 px from the right and 20 px from the bottom when the screen's short side is 500 px or
-- less (phones), else at 120 px, 50 px from the right and 90 px from the bottom (tablets). Layout:
--   [E ultimate] [Q mild]
--   [CODE]       [jump]
-- Returns bottom-right anchored { position, size } per button (AnchorPoint 1, 1).
export type Placement = { position: UDim2, size: UDim2 }
function UI.touchCluster(): { code: Placement, mild: Placement, ultimate: Placement }
	local phone = UI.isPhone()
	local jumpSize = if phone then 70 else 120
	local jumpRight = if phone then 25 else 50
	local jumpBottom = if phone then 20 else 90
	local codeSize = if phone then 72 else 84
	local buttonSize = if phone then 64 else 84
	local gap = 12
	local column = jumpRight + jumpSize + gap -- right edge of the column left of the jump button
	return {
		code = { position = UDim2.new(1, -column, 1, -jumpBottom), size = UDim2.fromOffset(codeSize, codeSize) },
		mild = { position = UDim2.new(1, -jumpRight, 1, -(jumpBottom + jumpSize + gap)), size = UDim2.fromOffset(buttonSize, buttonSize) },
		ultimate = { position = UDim2.new(1, -column, 1, -(jumpBottom + codeSize + gap)), size = UDim2.fromOffset(buttonSize, buttonSize) },
	}
end

UI.Colors = {
	Ink = Color3.fromRGB(11, 12, 15), -- deepest backdrop
	Panel = Color3.fromRGB(19, 21, 26), -- slabs
	Slot = Color3.fromRGB(33, 36, 44), -- inset cells, secondary buttons
	Line = Color3.fromRGB(78, 84, 98), -- hairlines
	Text = Color3.fromRGB(236, 236, 232),
	Muted = Color3.fromRGB(146, 151, 163),
	Accent = Color3.fromRGB(196, 52, 52), -- muted blood red
	Good = Color3.fromRGB(116, 196, 136),
	Bad = Color3.fromRGB(220, 84, 76),
	Info = Color3.fromRGB(150, 176, 214),
	Gold = Color3.fromRGB(214, 180, 96),
}

local DISPLAY = "rbxasset://fonts/families/Oswald.json"
local BODY = "rbxasset://fonts/families/GothamSSm.json"
UI.Font = Font.new(DISPLAY, Enum.FontWeight.SemiBold)
UI.FontHeavy = Font.new(DISPLAY, Enum.FontWeight.Bold)
UI.FontBody = Font.new(BODY, Enum.FontWeight.Medium)

-- Sharp look: corners are capped at this radius whatever a caller asks for.
local CORNER_CAP = 3

function UI.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance: any = Instance.new(className)
	local parent = nil
	for key, value in props or {} do
		if key == "Parent" then
			parent = value
		elseif key == "Font" and typeof(value) == "Font" then
			instance.FontFace = value -- UI.Font* are Font objects; Enum.Font values still work below
		else
			instance[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function merged(defaults: { [string]: any }, props: { [string]: any }): { [string]: any }
	for key, value in props do
		defaults[key] = value
	end
	return defaults
end

function UI.label(props: { [string]: any }, children: { Instance }?): TextLabel
	return UI.new("TextLabel", merged({
		BackgroundTransparency = 1,
		Font = UI.Font,
		TextColor3 = UI.Colors.Text,
		TextSize = 18,
		Text = "",
	}, props), children)
end

function UI.button(props: { [string]: any }, children: { Instance }?): TextButton
	return UI.new("TextButton", merged({
		AutoButtonColor = true,
		BackgroundColor3 = UI.Colors.Slot,
		BorderSizePixel = 0,
		Font = UI.Font,
		TextColor3 = UI.Colors.Text,
		TextSize = 18,
		Text = "",
	}, props), children)
end

function UI.corner(radius: number?): UICorner
	return UI.new("UICorner", { CornerRadius = UDim.new(0, math.min(radius or CORNER_CAP, CORNER_CAP)) })
end

function UI.stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return UI.new("UIStroke", {
		Color = color or Color3.new(1, 1, 1),
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UI.padding(px: number, horizontal: number?): UIPadding
	return UI.new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, horizontal or px),
		PaddingRight = UDim.new(0, horizontal or px),
	})
end

-- A thin accent bar glued to one edge of a panel ("left" or "top"/"bottom").
function UI.accentBar(parent: Instance, edge: string, color: Color3?, thickness: number?): Frame
	local t = thickness or 3
	local props: { [string]: any } = {
		Name = "Accent",
		BorderSizePixel = 0,
		BackgroundColor3 = color or UI.Colors.Accent,
		ZIndex = 2,
		Parent = parent,
	}
	if edge == "left" then
		props.Size = UDim2.new(0, t, 1, 0)
	elseif edge == "bottom" then
		props.AnchorPoint = Vector2.new(0, 1)
		props.Position = UDim2.fromScale(0, 1)
		props.Size = UDim2.new(1, 0, 0, t)
	else
		props.Size = UDim2.new(1, 0, 0, t)
	end
	return UI.new("Frame", props)
end

-- A charcoal slab. Pass AutomaticSize to let it hug its content.
function UI.panel(props: { [string]: any }, children: { Instance }?): Frame
	local frame = UI.new("Frame", merged({
		BackgroundColor3 = UI.Colors.Panel,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	}, props), children)
	UI.stroke(Color3.new(1, 1, 1), 1, 0.9).Parent = frame
	return frame
end

-- A panel that hugs its text: returns (panel, content). Put padding, layouts and text in `content`;
-- accent bars go on `panel`, so layouts and padding never move them. axis: "X" (fixed height) or "XY".
function UI.slab(props: { [string]: any }, axis: string?, contentChildren: { Instance }?): (Frame, Frame)
	local both = axis == "XY"
	local automatic = if both then Enum.AutomaticSize.XY else Enum.AutomaticSize.X
	props.AutomaticSize = automatic
	local panel = UI.panel(props)
	local content = UI.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = if both then UDim2.fromOffset(0, 0) else UDim2.fromScale(0, 1),
		AutomaticSize = automatic,
		Parent = panel,
	}, contentChildren)
	return panel, content
end

-- A ScreenGui that survives respawns. fullBleed = covers the whole screen, including the top bar.
function UI.screen(name: string, displayOrder: number?, fullBleed: boolean?): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	return UI.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder or 0,
		IgnoreGuiInset = fullBleed == true,
		ScreenInsets = if fullBleed then Enum.ScreenInsets.None else Enum.ScreenInsets.CoreUISafeInsets,
		Parent = playerGui,
	})
end

function UI.toneColor(tone: string?): Color3
	if tone == "good" then
		return UI.Colors.Good
	elseif tone == "bad" then
		return UI.Colors.Bad
	elseif tone == "info" then
		return UI.Colors.Info
	end
	return UI.Colors.Text
end

function UI.formatNumber(n: number): string
	local digits = tostring(math.floor(n))
	local result = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if result:sub(1, 1) == "," then
		result = result:sub(2)
	end
	return result
end

return UI
