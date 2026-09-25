-- Kill leaderboards on screen (owner-approved 2026-09-23): the two floating holo boards by the arrival
-- plaza, drawn in the shop's holographic style. The server (LeaderboardService) sends the rows; this only
-- draws them.
--
--   header   katakana line, title, and a chip: weekly reset countdown / GLOBAL / OFFLINE
--   rows     top 10: rank (gold, silver, bronze for 1-3), avatar headshot, name, kills, movement since the
--            last refresh (up / down / NEW) and a "+N LIVE" chip for kills not saved yet
--   you      the local player's place and total
--   footer   "SYNCED 12s AGO"
-- Motion: the boards bob, neon edges flow, scanlines drift; a refresh sweeps a scan bar and cascades the
-- rows in; the #1 player's avatar spins above each board as a tinted hologram.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Constants = require(Shared:WaitForChild("Modules"):WaitForChild("Constants"))
local UI = require(script.Parent.Parent:WaitForChild("UI"))

local LeaderboardController = {}

local localPlayer = Players.LocalPlayer

local HOLO = Color3.fromRGB(80, 230, 255)
local PINK = Color3.fromRGB(255, 90, 200)
local GOLD = Color3.fromRGB(255, 208, 110)
local WHITE = Color3.new(1, 1, 1)
local MUTED = Color3.fromRGB(140, 150, 166)
local UP = Color3.fromRGB(110, 230, 150)
local DOWN = Color3.fromRGB(240, 96, 96)
local MEDALS = { Color3.fromRGB(255, 208, 110), Color3.fromRGB(214, 222, 232), Color3.fromRGB(214, 142, 90) }
local HEAVY = UI.FontHeavy
local BODY = UI.FontBody

local CANVAS = Vector2.new(780, 1020)
local ROW_H = 66
local ROWS_TOP = 188

local THEMES = {
	AllTime = { accent = GOLD, second = WHITE, kana = "総合ランキング  //  ALL-TIME", title = "ALL-TIME KILLS", phase = 0 },
	Weekly = { accent = HOLO, second = PINK, kana = "週間ランキング  //  THIS WEEK", title = "WEEKLY KILLS", phase = 1.7 },
}

type Board = {
	id: string,
	floating: Model,
	home: CFrame,
	screen: BasePart,
	theme: any,
	gui: SurfaceGui,
	rows: { any },
	chip: TextLabel,
	you: TextLabel,
	footer: TextLabel,
	sweep: Frame,
	gradients: { UIGradient },
	data: any,
	champion: Model?,
	championOffset: CFrame?,
}

local boards: { [string]: Board } = {}
local payload: any = nil
local headshots: { [number]: string } = {}

local function tween(object: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	local t = TweenService:Create(object, TweenInfo.new(seconds, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), goal)
	t:Play()
	return t
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

local function headshot(userId: number, image: ImageLabel)
	if headshots[userId] then
		image.Image = headshots[userId]
		return
	end
	image.Image = ""
	if userId <= 0 then
		return
	end
	task.spawn(function()
		local ok, content = pcall(Players.GetUserThumbnailAsync, Players, userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		if ok and content then
			headshots[userId] = content
			if image:GetAttribute("UserId") == userId then
				image.Image = content
			end
		end
	end)
end

local function formatClock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local d = seconds // 86400
	local h = (seconds % 86400) // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	return string.format("%dD %02d:%02d:%02d", d, h, m, s)
end

-- Drawing ----------------------------------------------------------------------------------------

local function buildRow(parent: Instance, index: number, theme: any): any
	local frame = UI.new("Frame", {
		Name = "Row" .. index,
		Position = UDim2.fromOffset(24, ROWS_TOP + (index - 1) * ROW_H),
		Size = UDim2.fromOffset(CANVAS.X - 48, ROW_H - 8),
		BackgroundColor3 = if index <= 3 then MEDALS[index] else Color3.fromRGB(14, 22, 32),
		BackgroundTransparency = if index <= 3 then 0.82 else 0.35,
		BorderSizePixel = 0,
		Parent = parent,
	})
	UI.new("UIGradient", {
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.7) }),
		Parent = frame,
	})
	local stroke = UI.stroke(if index <= 3 then MEDALS[index] else theme.accent, 1, if index <= 3 then 0.2 else 0.8)
	stroke.Parent = frame
	local rank = text({
		Text = tostring(index),
		TextSize = if index <= 3 then 40 else 30,
		TextColor3 = if index <= 3 then MEDALS[index] else MUTED,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(4, 0),
		Size = UDim2.fromOffset(60, ROW_H - 8),
		Parent = frame,
	})
	local picture = UI.new("ImageLabel", {
		Position = UDim2.fromOffset(72, 5),
		Size = UDim2.fromOffset(48, 48),
		BackgroundColor3 = Color3.fromRGB(24, 36, 50),
		Parent = frame,
	})
	UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = picture })
	UI.new("UIStroke", { Color = if index <= 3 then MEDALS[index] else theme.accent, Thickness = 2, Transparency = 0.2, Parent = picture })
	local name = text({ Text = "", TextSize = 28, Position = UDim2.fromOffset(134, 0), Size = UDim2.fromOffset(360, ROW_H - 8), TextTruncate = Enum.TextTruncate.AtEnd, Parent = frame })
	local delta = text({ Text = "", TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(470, 0), Size = UDim2.fromOffset(70, ROW_H - 8), Parent = frame })
	local live = text({
		Text = "",
		TextSize = 15,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundColor3 = PINK,
		BackgroundTransparency = 0.1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -118, 0.5, 0),
		Size = UDim2.fromOffset(78, 22),
		Visible = false,
		Parent = frame,
	})
	UI.new("UICorner", { CornerRadius = UDim.new(0, 4), Parent = live })
	local kills = text({ Text = "", TextSize = 36, TextColor3 = theme.accent, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 0), Size = UDim2.fromOffset(100, ROW_H - 8), Parent = frame })
	return { frame = frame, rank = rank, picture = picture, name = name, delta = delta, live = live, kills = kills, userId = nil, key = nil }
end

local function buildBoard(id: string, floating: Model, screen: BasePart): Board
	local theme = THEMES[id]
	local gui = UI.new("SurfaceGui", {
		Name = "NAU_Board_" .. id,
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = CANVAS,
		LightInfluence = 0,
		Brightness = 1.6,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ResetOnSpawn = false,
		Adornee = screen,
		Parent = localPlayer:WaitForChild("PlayerGui"),
	})
	local root = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(4, 8, 14), BackgroundTransparency = 0.25, BorderSizePixel = 0, Parent = gui })
	UI.new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(10, 22, 34), Color3.fromRGB(4, 6, 12)),
		Parent = root,
	})
	local gradients = {}
	local edge = UI.stroke(WHITE, 4, 0)
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = root
	table.insert(gradients, UI.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, theme.accent),
			ColorSequenceKeypoint.new(0.5, theme.second),
			ColorSequenceKeypoint.new(1, theme.accent),
		}),
		Parent = edge,
	}))
	-- Scanlines.
	for y = 0, CANVAS.Y, 12 do
		UI.new("Frame", { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = theme.accent, BackgroundTransparency = 0.93, BorderSizePixel = 0, ZIndex = 8, Parent = root })
	end

	-- Header.
	text({ Text = theme.kana, TextSize = 20, TextColor3 = theme.second, Position = UDim2.fromOffset(28, 22), Size = UDim2.fromOffset(500, 24), Parent = root })
	local title = text({ Text = theme.title, TextSize = 64, Position = UDim2.fromOffset(26, 46), Size = UDim2.fromOffset(560, 70), Parent = root })
	UI.new("UIGradient", { Color = ColorSequence.new(WHITE, theme.accent), Parent = title })
	local chip = text({
		Text = "",
		TextSize = 20,
		TextColor3 = Color3.fromRGB(6, 10, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundColor3 = theme.accent,
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -28, 0, 28),
		Size = UDim2.fromOffset(200, 34),
		Parent = root,
	})
	UI.new("UICorner", { CornerRadius = UDim.new(0, 4), Parent = chip })
	UI.new("Frame", { Position = UDim2.fromOffset(26, 128), Size = UDim2.new(1, -52, 0, 3), BackgroundColor3 = theme.accent, BorderSizePixel = 0, Parent = root })
	for _, column in { { "#", 24, 60, Enum.TextXAlignment.Center }, { "FIGHTER", 158, 300, Enum.TextXAlignment.Left }, { "KILLS", CANVAS.X - 140, 100, Enum.TextXAlignment.Right } } do
		text({ Text = column[1], TextSize = 16, TextColor3 = MUTED, Position = UDim2.fromOffset(column[2], 148), Size = UDim2.fromOffset(column[3], 24), TextXAlignment = column[4], Parent = root })
	end

	local rows = {}
	for i = 1, Constants.LEADERBOARD_ROWS do
		rows[i] = buildRow(root, i, theme)
	end

	-- Your line and the footer.
	local youBar = UI.new("Frame", {
		Position = UDim2.fromOffset(24, ROWS_TOP + Constants.LEADERBOARD_ROWS * ROW_H + 10),
		Size = UDim2.fromOffset(CANVAS.X - 48, 62),
		BackgroundColor3 = PINK,
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		Parent = root,
	})
	UI.stroke(PINK, 2, 0.1).Parent = youBar
	local you = text({ Text = "", TextSize = 28, Position = UDim2.fromOffset(20, 0), Size = UDim2.new(1, -40, 1, 0), Parent = youBar })
	local footer = text({ Text = "", TextSize = 16, TextColor3 = MUTED, Position = UDim2.fromOffset(28, CANVAS.Y - 34), Size = UDim2.fromOffset(500, 20), Parent = root })
	text({ Text = "NAU // KILL RECORD", TextSize = 16, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -28, 0, CANVAS.Y - 34), Size = UDim2.fromOffset(300, 20), Parent = root })

	local sweep = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 8), Position = UDim2.fromOffset(0, -20), BackgroundColor3 = theme.accent, BorderSizePixel = 0, ZIndex = 9, Parent = root })
	UI.new("UIGradient", {
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }),
		Parent = sweep,
	})

	return {
		id = id,
		floating = floating,
		home = floating:GetPivot(),
		screen = screen,
		theme = theme,
		gui = gui,
		rows = rows,
		chip = chip,
		you = you,
		footer = footer,
		sweep = sweep,
		gradients = gradients,
		data = nil,
		champion = nil,
		championOffset = nil,
	}
end

local function drawBoard(board: Board, data: any, refreshed: boolean)
	board.data = data
	local rows = data.rows or {}
	for i, row in board.rows do
		local entry = rows[i]
		local key = if entry then string.format("%d:%d:%d:%s", entry.userId, entry.kills, entry.live or 0, tostring(entry.delta)) else "empty"
		local changed = row.key ~= key
		row.key = key
		if entry then
			row.frame.Visible = true
			row.name.Text = string.upper(entry.name or "?")
			row.kills.Text = UI.formatNumber(entry.kills)
			row.picture:SetAttribute("UserId", entry.userId)
			if row.userId ~= entry.userId then
				row.userId = entry.userId
				headshot(entry.userId, row.picture)
			end
			local delta = entry.delta
			if delta == "new" then
				row.delta.Text, row.delta.TextColor3 = "NEW", HOLO
			elseif type(delta) == "number" and delta > 0 then
				row.delta.Text, row.delta.TextColor3 = "▲" .. delta, UP
			elseif type(delta) == "number" and delta < 0 then
				row.delta.Text, row.delta.TextColor3 = "▼" .. -delta, DOWN
			else
				row.delta.Text, row.delta.TextColor3 = "—", MUTED
			end
			local live = entry.live or 0
			row.live.Visible = live > 0
			row.live.Text = "+" .. live .. " LIVE"
		else
			row.frame.Visible = i == 1 -- an empty board still shows one line
			row.name.Text = if i == 1 then "NO KILLS YET" else ""
			row.kills.Text = ""
			row.delta.Text = ""
			row.live.Visible = false
			row.picture.Image = ""
			row.userId = nil
		end
		-- Cascade the rows in on a refresh; flash a row that changed live.
		if changed and entry then
			local home = UDim2.fromOffset(24, ROWS_TOP + (i - 1) * ROW_H)
			if refreshed then
				row.frame.Position = home + UDim2.fromOffset(60, 0)
				task.delay((i - 1) * 0.04, function()
					tween(row.frame, 0.35, { Position = home })
				end)
			else
				row.frame.BackgroundColor3 = PINK
				tween(row.frame, 0.8, { BackgroundColor3 = if i <= 3 then MEDALS[i] else Color3.fromRGB(14, 22, 32) })
			end
		end
	end
	local mine = data.you and data.you[tostring(localPlayer.UserId)]
	if mine then
		board.you.Text = if mine.rank
			then string.format("YOU  ·  #%d  ·  %s KILLS", mine.rank, UI.formatNumber(mine.kills))
			else string.format("YOU  ·  UNRANKED  ·  %s KILLS", UI.formatNumber(mine.kills))
	else
		board.you.Text = "YOU  ·  —"
	end
	if refreshed then
		board.sweep.Position = UDim2.fromOffset(0, -20)
		tween(board.sweep, 0.7, { Position = UDim2.fromOffset(0, CANVAS.Y + 20) }, Enum.EasingStyle.Quad)
	end
end

local function redraw(newPayload: any)
	if type(newPayload) ~= "table" or type(newPayload.boards) ~= "table" then
		return
	end
	local old = payload
	payload = newPayload
	payload.receivedAt = os.clock()
	for id, board in boards do
		local data = newPayload.boards[id]
		if data then
			local before = old and old.boards and old.boards[id]
			local refreshed = before == nil or before.syncedAt ~= data.syncedAt
			drawBoard(board, data, refreshed)
		end
	end
end

-- Per frame: bob, spin the champion, flow the edges; once a second: clocks.
local lastClock = 0
local function animate()
	local now = os.clock()
	for _, board in boards do
		local bob = math.sin(now * 1.1 + board.theme.phase) * 0.35
		local tilt = math.sin(now * 0.7 + board.theme.phase) * 1.2
		board.floating:PivotTo(board.home * CFrame.new(0, bob, 0) * CFrame.Angles(0, math.rad(tilt), 0))
		for _, gradient in board.gradients do
			gradient.Rotation = (now * 50) % 360
		end
		local champion = board.floating:FindFirstChild("Champion")
		if champion and champion:IsA("Model") then
			local anchor = board.floating:FindFirstChild("ChampionAnchor") :: BasePart
			if champion ~= board.champion then
				board.champion = champion
				board.championOffset = anchor.CFrame:ToObjectSpace(champion:GetPivot())
				UI.new("Highlight", {
					FillColor = board.theme.accent,
					FillTransparency = 0.6,
					OutlineColor = board.theme.accent,
					OutlineTransparency = 0,
					DepthMode = Enum.HighlightDepthMode.Occluded,
					Parent = champion,
				})
			end
			champion:PivotTo(anchor.CFrame * CFrame.Angles(0, now * 0.9, 0) * (board.championOffset :: CFrame))
		end
	end
	if now - lastClock >= 1 and payload then
		lastClock = now
		local serverNow = (payload.serverTime or 0) + (now - (payload.receivedAt or now))
		for id, board in boards do
			local data = board.data
			if data then
				if payload.offline then
					board.chip.Text = "OFFLINE · THIS SERVER"
					board.chip.BackgroundColor3 = Color3.fromRGB(120, 120, 130)
				elseif id == "Weekly" and data.resetAt then
					board.chip.Text = "RESETS " .. formatClock(data.resetAt - serverNow)
				else
					board.chip.Text = "GLOBAL · 全サーバー"
				end
				local ago = if data.syncedAt then math.max(0, math.floor(serverNow - data.syncedAt)) else nil
				board.footer.Text = if ago then string.format("SYNCED %ds AGO", ago) else "SYNCING…"
			end
		end
	end
end

function LeaderboardController.Start()
	task.spawn(function()
		local world = workspace:WaitForChild("NAUWorld", 60)
		local lobby = world and world:WaitForChild("Lobby", 60)
		local holder = lobby and lobby:WaitForChild("Leaderboards", 60)
		if not holder then
			return
		end
		for _, id in { "AllTime", "Weekly" } do
			local model = holder:WaitForChild("Board_" .. id, 30)
			local floating = model and model:WaitForChild("Floating", 30)
			local screen = floating and floating:WaitForChild("Screen", 30)
			if floating and screen and screen:IsA("BasePart") then
				boards[id] = buildBoard(id, floating :: Model, screen)
			end
		end
		Remotes.Leaderboards.OnClientEvent:Connect(redraw)
		local ok, first = pcall(function()
			return Remotes.GetLeaderboards:InvokeServer()
		end)
		if ok then
			redraw(first)
		end
		RunService.RenderStepped:Connect(animate)
	end)
end

return LeaderboardController
