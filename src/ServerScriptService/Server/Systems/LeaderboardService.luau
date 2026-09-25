-- Kill leaderboards (owner-approved 2026-09-23): an all-time board and a weekly board (Monday 00:00 UTC),
-- global across every server via OrderedDataStores (SafeStore), shown on two floating holo boards in the
-- lobby (LeaderboardController draws them).
--
-- A kill = an elimination by a correct code (EliminationService.onElimination): never clones, falls,
-- self-eliminations or strike-outs.
--   * Each kill counts at once as "live" on this server's boards (broadcast straight away).
--   * Every FLUSH seconds the unsaved kills are added to both stores (IncrementAsync); on shutdown too.
--   * Every REFRESH seconds the global top list is re-read (GetSortedAsync), the fastest the per-minute
--     limits comfortably allow. Rank movement (up/down/new) is measured between refreshes.
-- Without DataStores (Studio with API access off, or an unpublished place) it runs offline: both boards
-- show this server session's kills, and the boards say so.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local WeekClock = require(script.Parent.Parent.Lib.WeekClock)
local LeaderboardRules = require(script.Parent.Parent.Lib.LeaderboardRules)
local SafeStore = require(script.Parent.SafeStore)
local EliminationService = require(script.Parent.EliminationService)
local MapService = require(script.Parent.MapService)

local LeaderboardService = {}

local BOARD_IDS = { "AllTime", "Weekly" }

type Board = {
	stored: { LeaderboardRules.Entry }, -- the saved top list, best first
	known: { [number]: number }, -- saved totals for players not in `stored`
	session: { [number]: number }, -- offline: this session's saved-equivalent totals
	pending: { [number]: number }, -- kills not saved yet
	previous: { [number]: number }, -- ranks at the last refresh
	deltas: { [number]: number | boolean }, -- movement at the last refresh (true = new)
	syncedAt: number?,
}

local function newBoard(): Board
	return { stored = {}, known = {}, session = {}, pending = {}, previous = {}, deltas = {}, syncedAt = nil }
end

local boards: { [string]: Board } = { AllTime = newBoard(), Weekly = newBoard() }
local weekKey = WeekClock.key(os.time())
local names: { [number]: string } = {}
local champions: { [string]: { userId: number, model: Model? } } = {}
local lastPayload: any = nil
local namingInFlight = false

local function storeName(id: string): string
	local version = Constants.LEADERBOARD_STORE_VERSION
	return if id == "AllTime" then "NAU_Kills_AllTime_" .. version else "NAU_Kills_Week" .. weekKey .. "_" .. version
end

local function storeFor(id: string): OrderedDataStore?
	return SafeStore.ordered(storeName(id))
end

-- Names ----------------------------------------------------------------------------------------

local function nameOf(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.DisplayName
	end
	return names[userId] or (if userId > 0 then "…" else "Test " .. tostring(-userId))
end

-- Fills in display names for ids we haven't seen (yields; called from the refresh loop only).
local function fetchNames(ids: { number })
	local missing = {}
	for _, id in ids do
		if not names[id] and id > 0 and not Players:GetPlayerByUserId(id) then
			table.insert(missing, id)
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, missing)
	if ok and type(infos) == "table" then
		for _, info in infos do
			names[info.Id] = info.DisplayName
		end
	end
	for _, id in missing do
		if not names[id] then
			local fine, name = pcall(Players.GetNameFromUserIdAsync, Players, id)
			names[id] = if fine and name then name else "Unknown"
		end
	end
end

-- The broadcast ----------------------------------------------------------------------------------

local function mergedRows(board: Board)
	local stored = board.stored
	if SafeStore.isOffline() then
		stored = {}
		for userId, kills in board.session do
			table.insert(stored, { userId = userId, kills = kills })
		end
		table.sort(stored, function(a, b)
			return a.kills > b.kills
		end)
	end
	return LeaderboardRules.merge(stored, board.pending, board.known)
end

local function boardAnchor(id: string): Model?
	local lobby = MapService.getLobby()
	local holder = lobby and lobby:FindFirstChild("Leaderboards", true)
	local board = holder and holder:FindFirstChild("Board_" .. id)
	return if board and board:IsA("Model") then board else nil
end

-- The #1 player's avatar floats above each board (the client makes it a spinning hologram).
local function setChampion(id: string, userId: number?)
	local current = champions[id]
	if current and current.userId == userId then
		return
	end
	if current and current.model then
		current.model:Destroy()
	end
	champions[id] = nil
	if not userId or userId <= 0 then
		return
	end
	local entry = { userId = userId, model = nil :: Model? }
	champions[id] = entry
	task.spawn(function()
		local ok, model = pcall(Players.CreateHumanoidModelFromUserId, Players, userId)
		if not ok or not model or champions[id] ~= entry then
			if ok and model then
				model:Destroy()
			end
			return
		end
		local board = boardAnchor(id)
		local floating = board and board:FindFirstChild("Floating")
		local anchor = floating and floating:FindFirstChild("ChampionAnchor")
		if not anchor or not anchor:IsA("BasePart") then
			model:Destroy()
			return
		end
		for _, d in model:GetDescendants() do
			if d:IsA("LuaSourceContainer") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
		local lift = if humanoid and root and root:IsA("BasePart") then humanoid.HipHeight + root.Size.Y / 2 else 3
		model.Name = "Champion"
		model:SetAttribute("UserId", userId)
		model:PivotTo(anchor.CFrame * CFrame.new(0, lift, 0))
		model.Parent = floating
		entry.model = model
	end)
end

local function broadcast()
	local now = os.time()
	local offline = SafeStore.isOffline()
	local payload = { serverTime = now, offline = offline, boards = {} }
	for _, id in BOARD_IDS do
		local board = boards[id]
		local rows = mergedRows(board)
		local top = {}
		for i = 1, math.min(#rows, Constants.LEADERBOARD_ROWS) do
			local row = rows[i]
			local delta = board.deltas[row.userId]
			table.insert(top, {
				userId = row.userId,
				name = nameOf(row.userId),
				kills = row.kills,
				live = row.live,
				rank = row.rank,
				delta = if delta == true then "new" elseif type(delta) == "number" then delta else nil,
			})
		end
		-- Every player on this server: their place (within the fetched depth) and their total.
		local you = {}
		for _, player in Players:GetPlayers() do
			local rank, kills = nil, (board.known[player.UserId] or board.session[player.UserId] or 0) + (board.pending[player.UserId] or 0)
			for _, row in rows do
				if row.userId == player.UserId then
					kills = row.kills
					if row.rank <= Constants.LEADERBOARD_DEPTH then
						rank = row.rank
					end
					break
				end
			end
			you[tostring(player.UserId)] = { rank = rank, kills = kills }
		end
		payload.boards[id] = {
			rows = top,
			you = you,
			syncedAt = board.syncedAt,
			resetAt = if id == "Weekly" then WeekClock.nextReset(now) else nil,
		}
		setChampion(id, if top[1] and top[1].kills > 0 then top[1].userId else nil)
	end
	lastPayload = payload
	Remotes.Leaderboards:FireAllClients(payload)
	-- A live update can show someone whose name isn't known yet: look it up now and redraw, rather than
	-- showing "…" until the next refresh.
	local unnamed = {}
	for _, id in BOARD_IDS do
		for _, row in payload.boards[id].rows do
			if not names[row.userId] and row.userId > 0 and not Players:GetPlayerByUserId(row.userId) then
				table.insert(unnamed, row.userId)
			end
		end
	end
	if #unnamed > 0 and not namingInFlight then
		namingInFlight = true
		task.spawn(function()
			fetchNames(unnamed)
			namingInFlight = false
			broadcast()
		end)
	end
end

-- Saving and refreshing --------------------------------------------------------------------------

local function flush()
	for _, id in BOARD_IDS do
		local board = boards[id]
		local batch = board.pending
		board.pending = {}
		for userId, n in batch do
			local store = storeFor(id)
			local ok, total = false, nil
			if store then
				ok, total = SafeStore.call(Enum.DataStoreRequestType.SetIncrementSortedAsync, function()
					return store:IncrementAsync(tostring(userId), n)
				end)
			end
			if ok and type(total) == "number" then
				board.known[userId] = total
				for _, entry in board.stored do
					if entry.userId == userId then
						entry.kills = total
					end
				end
			elseif SafeStore.isOffline() then
				board.session[userId] = (board.session[userId] or 0) + n
			else
				board.pending[userId] = (board.pending[userId] or 0) + n -- try again next flush
			end
		end
	end
end

local function refresh()
	local key = WeekClock.key(os.time())
	if key ~= weekKey then
		-- A new week: a fresh weekly board; kills not saved yet count toward the new week.
		local carried = boards.Weekly.pending
		weekKey = key
		boards.Weekly = newBoard()
		boards.Weekly.pending = carried
	end
	local ids: { number } = {}
	for _, id in BOARD_IDS do
		local board = boards[id]
		local store = storeFor(id)
		if store then
			local ok, pages = SafeStore.call(Enum.DataStoreRequestType.GetSortedAsync, function()
				return store:GetSortedAsync(false, Constants.LEADERBOARD_DEPTH)
			end)
			if ok and pages then
				local stored = {}
				for _, item in pages:GetCurrentPage() do
					local userId = tonumber(item.key)
					if userId then
						table.insert(stored, { userId = userId, kills = item.value })
						table.insert(ids, userId)
					end
				end
				board.stored = stored
				board.syncedAt = os.time()
				-- Saved totals for players here who aren't in the fetched list.
				for _, player in Players:GetPlayers() do
					local listed = false
					for _, entry in stored do
						if entry.userId == player.UserId then
							listed = true
							break
						end
					end
					if not listed and board.known[player.UserId] == nil then
						local fine, value = SafeStore.call(Enum.DataStoreRequestType.GetAsync, function()
							return store:GetAsync(tostring(player.UserId))
						end)
						board.known[player.UserId] = if fine and type(value) == "number" then value else 0
					end
				end
			end
		end
		if SafeStore.isOffline() then
			board.syncedAt = os.time()
		end
	end
	fetchNames(ids)
	-- Movement since the last refresh.
	for _, id in BOARD_IDS do
		local board = boards[id]
		local rows = mergedRows(board)
		LeaderboardRules.withChanges(rows, board.previous)
		board.deltas = {}
		for _, row in rows do
			board.deltas[row.userId] = if row.delta == nil then true else row.delta
		end
		board.previous = LeaderboardRules.ranks(rows)
	end
	broadcast()
end

function LeaderboardService.Init()
	Remotes.GetLeaderboards.OnServerInvoke = function()
		return lastPayload
	end
	EliminationService.onElimination(function(attacker: Player, _victimId: number)
		for _, id in BOARD_IDS do
			local pending = boards[id].pending
			pending[attacker.UserId] = (pending[attacker.UserId] or 0) + 1
		end
		broadcast() -- the kill shows at once, as "+live"
	end)
	Players.PlayerAdded:Connect(function()
		task.defer(broadcast)
	end)
	-- Studio-only test hook (one player can't make real eliminations): set ServerScriptService's
	-- NAU_DevFakeKills to "userId:count,userId:count" and those kills go in exactly as real ones would.
	if RunService:IsStudio() then
		local ServerScriptService = game:GetService("ServerScriptService")
		local attribute = Constants.DEV_FAKE_KILLS_ATTRIBUTE
		ServerScriptService:GetAttributeChangedSignal(attribute):Connect(function()
			local spec = ServerScriptService:GetAttribute(attribute)
			if type(spec) ~= "string" or spec == "" then
				return
			end
			ServerScriptService:SetAttribute(attribute, nil)
			for userId, count in string.gmatch(spec, "(%-?%d+):(%d+)") do
				for _, id in BOARD_IDS do
					local pending = boards[id].pending
					local key = tonumber(userId) :: number
					pending[key] = (pending[key] or 0) + (tonumber(count) :: number)
				end
			end
			broadcast()
		end)
	end
	game:BindToClose(function()
		flush()
	end)
end

function LeaderboardService.Start()
	task.spawn(function()
		while true do
			task.wait(Constants.LEADERBOARD_FLUSH_SECONDS)
			local ok, err = pcall(flush)
			if not ok then
				warn("[NAU] leaderboard flush failed: " .. tostring(err))
			end
		end
	end)
	while true do
		local ok, err = pcall(refresh)
		if not ok then
			warn("[NAU] leaderboard refresh failed: " .. tostring(err))
		end
		if RunService:IsStudio() then
			local offline, reason = SafeStore.isOffline()
			print(string.format("[NAU] leaderboards refreshed (%s)", if offline then "offline: " .. tostring(reason) else "global"))
		end
		task.wait(Constants.LEADERBOARD_REFRESH_SECONDS)
	end
end

return LeaderboardService
