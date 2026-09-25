-- HUD: round status and timer, score line, yen, kill feed, respawn overlay, big banners and toasts.
--
-- Battle layout (owner, 2026-09-23: "cleaner and more aggressive"): a three-slab scoreboard at the top
-- (YOU · clock · LEAD), a slim spawn-protection bar under it, yen and the kill feed top-right, toasts
-- bottom-centre. Every text panel sizes itself to its text, so nothing spills out of its box.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Constants = require(Shared:WaitForChild("Modules"):WaitForChild("Constants"))
local Currency = require(Shared:WaitForChild("Modules"):WaitForChild("Currency"))
local UIMotion = require(ReplicatedStorage:WaitForChild("Animations"):WaitForChild("Controllers"):WaitForChild("UIMotion"))
local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"))
local Audio = require(Client:WaitForChild("Audio"))

local HUDController = {}

local localPlayer = Players.LocalPlayer

local MODE_NAMES = { FFA = "Free-for-all", Team6v6 = "Team battle" }
local FEED_LIFETIME = 5
local FEED_MAX = 5
local REFRESH_SECONDS = 0.1
local TOAST_MAX_WIDTH = 520
local DEATH_SATURATION = -0.85 -- the world drains of colour while you wait to respawn
local LEADERBOARD_WIDTH = 190
local LEADERBOARD_PHONE_ROWS = 6 -- rows shown on phones (short side of the screen <= 500 px)

local refs: { [string]: any } = {}
local lastPhase: string? = nil
local lastSuddenDeath = false
local wasInMatch = false
local wasAlive = true -- so a death is heard once, not on every LifeState while waiting to respawn
local bannerToken, toastToken, feedOrder = 0, 0, 0
local deathGrade: ColorCorrectionEffect? = nil
local deathGradeOn = false

local function nameOf(userId: number?): string
	local player = userId and Players:GetPlayerByUserId(userId)
	return if player then player.DisplayName else "someone"
end

local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function hex(color: Color3): string
	return string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255)
end

local function formatClock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function resultText(result: any): string
	if not result then
		return "ROUND OVER"
	end
	if result.kind == "player" then
		if result.userId == localPlayer.UserId then
			return "YOU WIN"
		end
		return string.upper(string.format("%s wins", result.name or "A fighter"))
	elseif result.kind == "team" then
		if result.team ~= nil and result.team == ClientState.myTeam() then
			return "YOUR TEAM WINS"
		end
		return string.upper(string.format("%s wins", tostring(result.team)))
	elseif result.reason == "not_enough_players" then
		return "NOT ENOUGH FIGHTERS"
	end
	return "DRAW"
end

-- A small stat slab for the scoreboard: caption on top, big number below.
local function statSlab(parent: Instance, name: string, caption: string, order: number): TextLabel
	local slab = UI.panel({
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromOffset(62, 50),
		Visible = false,
		Parent = parent,
	})
	UI.label({
		Name = "Caption",
		Position = UDim2.fromOffset(0, 5),
		Size = UDim2.new(1, 0, 0, 12),
		Font = UI.Font,
		TextSize = 12,
		TextColor3 = UI.Colors.Muted,
		Text = caption,
		Parent = slab,
	})
	return UI.label({
		Name = "Value",
		Position = UDim2.fromOffset(0, 17),
		Size = UDim2.new(1, 0, 0, 28),
		Font = UI.FontHeavy,
		TextSize = 26,
		Text = "0",
		Parent = slab,
	})
end

local function build()
	local gui = UI.screen("NAU_HUD", 5)
	-- Owner, 2026-09-23: the timer and eliminations sit at the very top of the screen. This layer ignores
	-- Roblox's top-bar inset; the centre of the top bar is free (Roblox's buttons live in the corners).
	local topGui = UI.screen("NAU_HUDTop", 5, true)

	-- Scoreboard: [YOU] [clock] [LEAD]
	local board = UI.new("Frame", {
		Name = "Scoreboard",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(0, 50),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = topGui,
	}, {
		UI.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),
	})
	refs.you = statSlab(board, "You", "YOU", 1)
	refs.lead = statSlab(board, "Lead", "LEAD", 3)
	-- Team battle: the same slabs read YOUR TEAM / ENEMY with team-coloured bars.
	refs.youCaption = refs.you.Parent:FindFirstChild("Caption")
	refs.leadCaption = refs.lead.Parent:FindFirstChild("Caption")
	refs.youBar = UI.accentBar(refs.you.Parent, "bottom", UI.Colors.Line, 2)
	refs.leadBar = UI.accentBar(refs.lead.Parent, "bottom", UI.Colors.Line, 2)

	local clockPanel, clock = UI.slab({
		Name = "Clock",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(0, 50),
		Parent = board,
	}, "X", {
		UI.padding(0, 16),
		UI.new("UISizeConstraint", { MinSize = Vector2.new(160, 50) }),
		UI.new("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})
	UI.accentBar(clockPanel, "bottom", UI.Colors.Accent, 2)
	refs.phase = UI.label({
		Name = "Phase",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(0, 14),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = UI.Font,
		TextSize = 12,
		TextColor3 = UI.Colors.Muted,
		Parent = clock,
	})
	refs.timer = UI.label({
		Name = "Timer",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = UI.FontHeavy,
		TextSize = 28,
		Parent = clock,
	})

	-- Spawn protection: a caption and a draining bar.
	refs.protect = UI.panel({
		Name = "SpawnProtection",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 62),
		Size = UDim2.fromOffset(200, 26),
		Visible = false,
		Parent = topGui,
	})
	UI.label({
		Name = "Caption",
		Position = UDim2.fromOffset(10, 3),
		Size = UDim2.new(1, -20, 0, 14),
		Font = UI.Font,
		TextSize = 12,
		TextColor3 = UI.Colors.Info,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "SPAWN PROTECTION · HIDDEN",
		Parent = refs.protect,
	})
	local track = UI.new("Frame", {
		Name = "Track",
		Position = UDim2.new(0, 10, 1, -7),
		Size = UDim2.new(1, -20, 0, 3),
		BorderSizePixel = 0,
		BackgroundColor3 = UI.Colors.Slot,
		Parent = refs.protect,
	})
	refs.protectFill = UI.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		BackgroundColor3 = UI.Colors.Info,
		Parent = track,
	})

	-- Yen sits left of the settings gear (SettingsController, top-right corner).
	local yenPanel, yenContent = UI.slab({
		Name = "Yen",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(10 + UI.gearSize() + 6), 0, 8),
		Size = UDim2.fromOffset(0, 30),
		Parent = gui,
	}, "X", { UI.padding(0, 12) })
	UI.accentBar(yenPanel, "left", UI.Colors.Gold, 2)
	refs.yenPanel = yenPanel
	refs.yen = UI.label({
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = UI.FontHeavy,
		TextSize = 18,
		TextColor3 = UI.Colors.Gold,
		Text = Currency.amount(0),
		Parent = yenContent,
	})

	-- In-match leaderboard (owner, 2026-09-23): every fighter's eliminations, most to least. Left side,
	-- vertically centred, clear of Roblox's chat (top-left) and our feed (top-right).
	local boardPanel, boardContent = UI.slab({
		Name = "Leaderboard",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.45, 0),
		Size = UDim2.fromOffset(0, 0),
		Visible = false,
		Parent = gui,
	}, "XY", {
		UI.padding(8, 10),
		UI.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }),
	})
	UI.accentBar(boardPanel, "top", UI.Colors.Accent, 2)
	refs.leaderboard = boardPanel
	UI.label({
		LayoutOrder = 0,
		Size = UDim2.fromOffset(LEADERBOARD_WIDTH, 16),
		Font = UI.Font,
		TextSize = 12,
		TextColor3 = UI.Colors.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "ELIMINATIONS",
		Parent = boardContent,
	})
	refs.leaderRows = {}
	for i = 1, Constants.MAX_PLAYERS do
		local row = UI.new("Frame", {
			Name = "Row" .. i,
			LayoutOrder = i,
			Size = UDim2.fromOffset(LEADERBOARD_WIDTH, 20),
			BackgroundColor3 = UI.Colors.Slot,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = false,
			Parent = boardContent,
		})
		local stripe = UI.new("Frame", {
			Name = "Team",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromOffset(-3, 2),
			Size = UDim2.new(0, 3, 1, -4),
			BorderSizePixel = 0,
			Visible = false,
			Parent = row,
		})
		local rank = UI.label({
			Name = "Rank",
			Size = UDim2.new(0, 22, 1, 0),
			Font = UI.FontHeavy,
			TextSize = 14,
			TextColor3 = UI.Colors.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		local name = UI.label({
			Name = "Name",
			Position = UDim2.fromOffset(24, 0),
			Size = UDim2.new(1, -60, 1, 0),
			Font = UI.Font,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})
		local kills = UI.label({
			Name = "Kills",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 34, 1, 0),
			Font = UI.FontHeavy,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		})
		refs.leaderRows[i] = { frame = row, rank = rank, name = name, kills = kills, stripe = stripe }
	end

	refs.feed = UI.new("Frame", {
		Name = "Feed",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8 + math.max(30, UI.gearSize()) + 8), -- below the yen counter and gear
		Size = UDim2.fromOffset(320, 150),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		UI.new("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 3),
		}),
	})

	-- Big centre banner: title, a red slash that wipes in, and a small subtitle.
	refs.banner = UI.new("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.new(1, 0, 0, 96),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	refs.bannerTitle = UI.label({
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 62),
		Font = UI.FontHeavy,
		TextSize = 60,
		TextStrokeTransparency = 0.6,
		Parent = refs.banner,
	})
	refs.bannerSlash = UI.new("Frame", {
		Name = "Slash",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(0, 3),
		BorderSizePixel = 0,
		BackgroundColor3 = UI.Colors.Accent,
		Parent = refs.banner,
	})
	refs.bannerSub = UI.label({
		Name = "Subtitle",
		Position = UDim2.fromOffset(0, 72),
		Size = UDim2.new(1, 0, 0, 20),
		Font = UI.Font,
		TextSize = 18,
		TextColor3 = UI.Colors.Muted,
		Parent = refs.banner,
	})

	local toastContent
	refs.toast, toastContent = UI.slab({
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -140),
		Size = UDim2.fromOffset(0, 0),
		Visible = false,
		Parent = gui,
	}, "XY", { UI.padding(8, 16) })
	refs.toastBar = UI.accentBar(refs.toast, "left", UI.Colors.Text, 3)
	refs.toastText = UI.label({
		Name = "Text",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Font = UI.Font,
		TextSize = 16,
		TextWrapped = true,
		Parent = toastContent,
	}, { UI.new("UISizeConstraint", { MaxSize = Vector2.new(TOAST_MAX_WIDTH, 100) }) })

	-- Respawn overlay: its own full-screen layer under the HUD.
	local overlayGui = UI.screen("NAU_RespawnOverlay", 4, true)
	refs.overlay = UI.new("Frame", {
		Name = "Overlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(6, 6, 8),
		BackgroundTransparency = 0.4,
		Visible = false,
		Parent = overlayGui,
	})
	refs.overlayTitle = UI.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.new(1, 0, 0, 72),
		Font = UI.FontHeavy,
		TextSize = 72,
		Parent = refs.overlay,
	})
	UI.new("Frame", {
		Name = "Slash",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.4, 44),
		Size = UDim2.fromOffset(260, 3),
		BorderSizePixel = 0,
		BackgroundColor3 = UI.Colors.Accent,
		Parent = refs.overlay,
	})
	refs.overlaySub = UI.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.4, 68),
		Size = UDim2.new(1, 0, 0, 24),
		Font = UI.Font,
		TextSize = 20,
		TextColor3 = UI.Colors.Muted,
		Parent = refs.overlay,
	})
	refs.overlayCount = UI.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.4, 108),
		Size = UDim2.new(1, 0, 0, 30),
		Font = UI.FontHeavy,
		TextSize = 24,
		Parent = refs.overlay,
	})

	deathGrade = UI.new("ColorCorrectionEffect", { Name = "NAU_DeathGrade", Saturation = 0, Parent = Lighting })
end

-- Phones (Phase 4): while the touch keypad is open, the in-match kill list steps aside for it.
local entryOpen = false
function HUDController.setEntryOpen(open: boolean)
	entryOpen = open
end

function HUDController.toast(text: string, tone: string?)
	if not refs.toast then
		return
	end
	toastToken += 1
	local token = toastToken
	local color = UI.toneColor(tone)
	refs.toastText.Text = text
	refs.toastText.TextColor3 = if tone then color else UI.Colors.Text
	refs.toastBar.BackgroundColor3 = if tone then color else UI.Colors.Muted
	refs.toast.Visible = true
	UIMotion.pop(refs.toast)
	task.delay(3.5, function()
		if toastToken == token then
			refs.toast.Visible = false
		end
	end)
end

local function showBanner(title: string, subtitle: string?, color: Color3?, seconds: number?)
	bannerToken += 1
	local token = bannerToken
	refs.bannerTitle.Text = title
	refs.bannerTitle.TextColor3 = color or UI.Colors.Text
	refs.bannerSub.Text = subtitle or ""
	refs.bannerSlash.Size = UDim2.fromOffset(0, 3)
	refs.banner.Visible = true
	UIMotion.pop(refs.bannerTitle)
	TweenService:Create(refs.bannerSlash, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(240, 3),
	}):Play()
	task.delay(seconds or 2.5, function()
		if bannerToken == token then
			refs.banner.Visible = false
		end
	end)
end

local function pushFeed(richText: string, barColor: Color3)
	feedOrder -= 1 -- newest on top
	local entry, content = UI.slab({
		Size = UDim2.fromOffset(0, 24),
		LayoutOrder = feedOrder,
		Parent = refs.feed,
	}, "X", { UI.padding(0, 10) })
	UI.accentBar(entry, "left", barColor, 3)
	local label = UI.label({
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = UI.Font,
		TextSize = 15,
		RichText = true,
		Text = richText,
		Parent = content,
	})
	local entries = {}
	for _, child in refs.feed:GetChildren() do
		if child:IsA("Frame") then
			table.insert(entries, child)
		end
	end
	table.sort(entries, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = FEED_MAX + 1, #entries do
		entries[i]:Destroy()
	end
	task.delay(FEED_LIFETIME, function()
		if entry.Parent then
			local info = TweenInfo.new(0.4)
			TweenService:Create(label, info, { TextTransparency = 1 }):Play()
			local fade = TweenService:Create(entry, info, { BackgroundTransparency = 1 })
			fade.Completed:Connect(function()
				entry:Destroy()
			end)
			fade:Play()
		end
	end)
end

local function onFeed(event: any)
	if type(event) ~= "table" or event.kind ~= "eliminated" or not ClientState.isParticipant() then
		return
	end
	-- Team battle: names take their team's colour.
	local function named(userId: number?): string
		local text = escape(string.upper(nameOf(userId)))
		local color = ClientState.teamColor(ClientState.teamOf(userId))
		return if color then string.format('<font color="%s">%s</font>', hex(color), text) else text
	end
	local victim = named(event.victim)
	local muted = hex(UI.Colors.Muted)
	if event.cause == "code" then
		local bar = UI.Colors.Line
		if event.attacker == localPlayer.UserId then
			bar = UI.Colors.Good
		elseif event.victim == localPlayer.UserId then
			bar = UI.Colors.Accent
		end
		local attacker = named(event.attacker)
		pushFeed(string.format('%s  <font color="%s">ELIMINATED</font>  %s', attacker, muted, victim), bar)
	elseif event.cause == "strikes" then
		pushFeed(string.format('%s  <font color="%s">MISFIRED TWICE</font>', victim, muted), UI.Colors.Line)
	else
		pushFeed(string.format('%s  <font color="%s">FELL</font>', victim, muted), UI.Colors.Line)
	end
end

local function onRoundChanged()
	local r = ClientState.round
	if not r then
		return
	end
	if r.phase ~= lastPhase then
		if r.phase == "RoundEnd" and lastPhase == "InRound" and ClientState.isParticipant() then
			local won = r.result
				and (r.result.userId == localPlayer.UserId or (r.result.team ~= nil and r.result.team == ClientState.myTeam()))
			if won then
				Audio.play("round_won")
			end
			showBanner(resultText(r.result), "ROUND OVER", if won then UI.Colors.Gold else UI.Colors.Text, 5)
		end
		lastPhase = r.phase
	end
	if r.phase == "InRound" and r.suddenDeath and not lastSuddenDeath and ClientState.isParticipant() then
		Audio.play("sudden_death")
		showBanner("SUDDEN DEATH", if ClientState.myTeam() then "NEXT TEAM TO TAKE THE LEAD WINS" else "NEXT SOLE LEADER WINS", UI.Colors.Bad, 3)
	end
	lastSuddenDeath = r.suddenDeath == true
end

local function onLifeChanged()
	local life = ClientState.life
	if life.alive == false and life.inMatch then
		if wasAlive then
			Audio.play("eliminated")
		end
		if life.cause == "code" then
			refs.overlayTitle.Text = "ELIMINATED"
			refs.overlaySub.Text = string.upper(string.format("%s read your number", life.byName or "Someone"))
		elseif life.cause == "strikes" then
			refs.overlayTitle.Text = "MISFIRE"
			refs.overlaySub.Text = "TWO WRONG CODES IN ONE LIFE"
		else
			refs.overlayTitle.Text = "YOU FELL"
			refs.overlaySub.Text = ""
		end
	end
	if life.inMatch and life.alive and not wasInMatch then
		Audio.play("round_start")
		local team = ClientState.myTeam()
		if team then
			showBanner("FIGHT", string.format("YOU'RE %s · MOST TEAM ELIMINATIONS WINS", string.upper(team)), ClientState.teamColor(team), 3)
		else
			showBanner("FIGHT", "MOST ELIMINATIONS WINS", UI.Colors.Text, 2)
		end
	end
	wasInMatch = life.inMatch == true
	wasAlive = life.alive == true
end

local function setDeathGrade(on: boolean)
	if on == deathGradeOn or not deathGrade then
		return
	end
	deathGradeOn = on
	TweenService:Create(deathGrade, TweenInfo.new(if on then 0.4 else 0.25), {
		Saturation = if on then DEATH_SATURATION else 0,
	}):Play()
end

local function refresh()
	local r = ClientState.round
	if not r then
		refs.phase.Text = "CONNECTING"
		refs.timer.Text = "..."
		return
	end
	local t = workspace:GetServerTimeNow()
	local remaining = (r.endsAt or 0) - t
	local queuedCount = #(r.queued or {})
	local timerColor = UI.Colors.Text
	local phaseColor = UI.Colors.Muted

	if r.phase == "Waiting" then
		refs.phase.Text = "LOBBY · WAITING FOR FIGHTERS"
		refs.timer.Text = string.format("%d / %d", queuedCount, r.minPlayers or Constants.MIN_PLAYERS_TO_START)
	elseif r.phase == "Intermission" then
		refs.phase.Text = string.format("NEXT ROUND · %d/%d QUEUED", queuedCount, r.maxPlayers or Constants.MAX_PLAYERS)
		refs.timer.Text = formatClock(remaining)
	elseif r.phase == "InRound" then
		refs.phase.Text = string.upper(string.format("%s · %s", MODE_NAMES[r.mode] or tostring(r.mode), r.mapName or ""))
		if r.graceEndsAt then
			refs.phase.Text = "NEED FIGHTERS · ROUND ENDS IN"
			refs.timer.Text = formatClock(r.graceEndsAt - t)
			timerColor = UI.Colors.Bad
		elseif r.suddenDeath then
			refs.phase.Text = "SUDDEN DEATH"
			phaseColor = UI.Colors.Bad
			refs.timer.Text = formatClock(remaining)
			timerColor = UI.Colors.Bad
		else
			refs.timer.Text = formatClock(remaining)
			if remaining <= 30 then
				timerColor = UI.Colors.Bad -- final seconds
			end
		end
	else
		refs.phase.Text = "ROUND OVER"
		refs.timer.Text = resultText(r.result)
	end
	refs.timer.TextColor3 = timerColor
	refs.phase.TextColor3 = phaseColor

	local showScores = (r.phase == "InRound" or r.phase == "RoundEnd") and r.scores ~= nil and #r.scores > 0
	refs.you.Parent.Visible = showScores
	refs.lead.Parent.Visible = showScores
	local myTeam = ClientState.myTeam()
	local teamRound = showScores and myTeam ~= nil
	if teamRound then
		-- Team battle: YOUR TEAM · clock · ENEMY (the other team's total).
		local teamScores = if type(r.teamScores) == "table" then r.teamScores else {}
		local ours, theirs, enemy = teamScores[myTeam] or 0, 0, nil
		for _, def in Constants.TEAMS do
			if def.name ~= myTeam then
				enemy = def.name
				theirs = math.max(theirs, teamScores[def.name] or 0)
			end
		end
		refs.youCaption.Text = "YOUR TEAM"
		refs.leadCaption.Text = if enemy then string.upper(enemy) else "ENEMY"
		refs.you.Text = tostring(ours)
		refs.lead.Text = tostring(theirs)
		refs.you.TextColor3 = if ours > theirs then UI.Colors.Gold else UI.Colors.Text
		refs.youBar.BackgroundColor3 = ClientState.teamColor(myTeam) or UI.Colors.Line
		refs.leadBar.BackgroundColor3 = ClientState.teamColor(enemy) or UI.Colors.Line
	elseif showScores then
		local mine, best = 0, 0
		for _, entry in r.scores do
			best = math.max(best, entry.score)
			if entry.userId == localPlayer.UserId then
				mine = entry.score
			end
		end
		refs.youCaption.Text = "YOU"
		refs.leadCaption.Text = "LEAD"
		refs.you.Text = tostring(mine)
		refs.lead.Text = tostring(best)
		refs.you.TextColor3 = if mine > 0 and mine >= best then UI.Colors.Gold else UI.Colors.Text
	end
	refs.youBar.Visible = teamRound
	refs.leadBar.Visible = teamRound

	-- Leaderboard: most eliminations first; ties keep a stable order by name. Team battle: your team's
	-- fighters first, each row marked with its team colour.
	refs.leaderboard.Visible = showScores and not entryOpen
	if showScores then
		local rows = {}
		for _, entry in r.scores do
			local player = Players:GetPlayerByUserId(entry.userId)
			table.insert(rows, {
				userId = entry.userId,
				score = entry.score,
				name = if player then player.DisplayName else "Fighter",
				team = if teamRound then entry.team else nil,
			})
		end
		table.sort(rows, function(a, b)
			if a.team ~= b.team then
				return a.team == myTeam
			end
			if a.score ~= b.score then
				return a.score > b.score
			end
			return string.lower(a.name) < string.lower(b.name)
		end)
		-- Phones (Phase 4): only the top rows fit beside the thumbstick; your own row always shows.
		for i, row in rows do
			row.rank = i
		end
		local maxRows = if UI.isPhone() then LEADERBOARD_PHONE_ROWS else #refs.leaderRows
		if #rows > maxRows then
			local shown = table.move(rows, 1, maxRows, 1, {})
			local mineShown = false
			for _, row in shown do
				mineShown = mineShown or row.userId == localPlayer.UserId
			end
			if not mineShown then
				for _, row in rows do
					if row.userId == localPlayer.UserId then
						shown[maxRows] = row
					end
				end
			end
			rows = shown
		end
		for i, ref in refs.leaderRows do
			local row = rows[i]
			ref.frame.Visible = row ~= nil
			if row then
				local mine = row.userId == localPlayer.UserId
				ref.rank.Text = tostring(row.rank)
				ref.name.Text = string.upper(row.name)
				ref.kills.Text = tostring(row.score)
				ref.frame.BackgroundTransparency = if mine then 0.2 else 1
				ref.name.TextColor3 = if mine then UI.Colors.Gold else UI.Colors.Text
				ref.kills.TextColor3 = if row.rank == 1 and row.score > 0 and not teamRound then UI.Colors.Gold else UI.Colors.Text
				local color = ClientState.teamColor(row.team)
				ref.stripe.Visible = color ~= nil
				if color then
					ref.stripe.BackgroundColor3 = color
				end
			end
		end
	end

	local life = ClientState.life
	local protectedUntil = life.protectedUntil
	if life.inMatch and life.alive and type(protectedUntil) == "number" then
		refs.protect.Visible = true
		local left = math.max(0, protectedUntil - t)
		refs.protectFill.Size = UDim2.fromScale(math.clamp(left / Constants.SPAWN_PROTECTION_SECONDS, 0, 1), 1)
	else
		refs.protect.Visible = false
	end

	local dead = life.inMatch and life.alive == false
	refs.overlay.Visible = dead
	setDeathGrade(dead == true)
	if dead then
		refs.overlayCount.Text = if life.respawnAt
			then string.format("RESPAWN  %.1f", math.max(0, life.respawnAt - t))
			else "ROUND OVER"
	end
end

local function setYen(amount: number)
	refs.yen.Text = Currency.amount(UI.formatNumber(amount))
end

-- Owner, 2026-09-23: everyone in the match is told when 30 seconds are left (and again in sudden death).
local function onRoundAlert(alert: any)
	if type(alert) ~= "table" or alert.kind ~= "time_left" or type(alert.seconds) ~= "number" then
		return
	end
	local title = string.format("%d SECONDS LEFT", alert.seconds)
	local team = ClientState.myTeam()
	local subtitle
	if alert.suddenDeath then
		subtitle = if team then "A TEAM IN THE LEAD WINS · OTHERWISE A DRAW" else "SOLE LEADER WINS · OTHERWISE A DRAW"
	else
		subtitle = if team then "MOST TEAM ELIMINATIONS WINS" else "MOST ELIMINATIONS WINS"
	end
	showBanner(title, subtitle, UI.Colors.Bad, 3)
	Audio.play("time_left")
	UIMotion.pop(refs.timer)
end

-- Passive yen: a "+50 YC" that slides out to the left of the yen counter (the kill feed sits below it), with
-- what it was for. Payouts that land together (playtime and the friend boost every 10 minutes) show one
-- after the other. Yields until the popup is gone.
local incomeQueue: { any } = {}
local showingIncome = false

local function showIncome(notice: any)
	local caption = "PLAYTIME"
	if notice.source == "purchase" then
		caption = "PURCHASED · THANK YOU!"
	elseif notice.source == "friends" then
		local friends = if type(notice.friends) == "number" then notice.friends else 0
		caption = string.format("FRIEND BOOST · %d %s HERE", friends, if friends == 1 then "FRIEND" else "FRIENDS")
	end
	-- A CanvasGroup fades the plate, its accent and the text together.
	local popup = UI.new("CanvasGroup", {
		Name = "IncomePopup",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, -6, 0.5, 0),
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = refs.yenPanel,
	})
	local plate, content = UI.slab({ Size = UDim2.fromOffset(0, 26), Parent = popup }, "X", { UI.padding(0, 10) })
	UI.accentBar(plate, "left", UI.Colors.Gold, 2)
	UI.label({
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = UI.FontHeavy,
		TextSize = 17,
		TextColor3 = UI.Colors.Gold,
		RichText = true,
		Text = string.format('+%s  <font size="13" color="%s">%s</font>', Currency.amount(UI.formatNumber(notice.amount)), hex(UI.Colors.Muted), caption),
		Parent = content,
	})
	UIMotion.pop(refs.yen)
	Audio.play("income")
	local slide = TweenInfo.new(4.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(popup, slide, { Position = UDim2.new(0, -20, 0.5, 0) }):Play()
	task.wait(3.7)
	local fade = TweenService:Create(popup, TweenInfo.new(0.8), { GroupTransparency = 1 })
	fade:Play()
	fade.Completed:Wait()
	popup:Destroy()
end

local function onIncome(notice: any)
	if type(notice) ~= "table" or type(notice.amount) ~= "number" or not refs.yenPanel then
		return
	end
	table.insert(incomeQueue, notice)
	if showingIncome then
		return
	end
	showingIncome = true
	while #incomeQueue > 0 do
		showIncome(table.remove(incomeQueue, 1))
	end
	showingIncome = false
end

function HUDController.Start()
	build()
	ClientState.Changed:Connect(function(kind)
		if kind == "round" then
			onRoundChanged()
		elseif kind == "life" then
			onLifeChanged()
		end
	end)
	Remotes.MatchFeed.OnClientEvent:Connect(onFeed)
	Remotes.RoundAlert.OnClientEvent:Connect(onRoundAlert)
	Remotes.IncomeNotice.OnClientEvent:Connect(onIncome)
	Remotes.UpdateCurrency.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and type(payload.yen) == "number" then
			setYen(payload.yen)
		end
	end)
	-- Saved progress: only the failure is worth interrupting for (a normal load is silent).
	local function onProfile()
		local profile = ClientState.profile
		if profile and profile.status == "offline" then
			HUDController.toast("Progress isn't saving this session", "bad")
		end
	end
	ClientState.Changed:Connect(function(kind)
		if kind == "profile" then
			onProfile()
		end
	end)
	onProfile()
	task.spawn(function()
		local stats = localPlayer:WaitForChild("leaderstats", 15)
		local yen = stats and stats:WaitForChild(Currency.STAT, 15)
		if yen then
			setYen(yen.Value)
		end
	end)
	onRoundChanged()
	task.spawn(function()
		while true do
			local ok, err = pcall(refresh)
			if not ok then
				warn("[NAU] HUD refresh failed: " .. tostring(err))
				task.wait(1)
			end
			task.wait(REFRESH_SECONDS)
		end
	end)
end

return HUDController
