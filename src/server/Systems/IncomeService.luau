-- Passive yen (owner, 2026-09-23): playtime yen and the friend booster. Rules in Lib/IncomeRules.
--   Playtime  every player in the server earns PASSIVE_YEN every PASSIVE_YEN_SECONDS, lobby or match.
--   Friends   every FRIEND_YEN_SECONDS, FRIEND_YEN_PER_FRIEND for each Roblox friend in the same server
--             at that moment.
-- Each player's clocks start when they join. Friendships are a web lookup, so each pair is looked up once
-- when the later of the two joins; a failed lookup counts as "not friends". Yen goes through EconomyService,
-- so it's saved like any other yen, and the player gets an IncomeNotice for the HUD.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local IncomeRules = require(script.Parent.Parent.Lib.IncomeRules)
local EconomyService = require(script.Parent.EconomyService)

local IncomeService = {}

local CHECK_SECONDS = 1

type Clock = { passiveAt: number, friendsAt: number }

local clocks: { [Player]: Clock } = {}
local friendships: { [number]: { [number]: boolean } } = {} -- userId -> userId -> true (stored both ways)

local function isFriend(a: number, b: number): boolean
	local set = friendships[a]
	return set ~= nil and set[b] == true
end

local function lookUp(player: Player, other: Player)
	local ok, result = pcall(player.IsFriendsWith, player, other.UserId)
	if ok and result == true and player.Parent and other.Parent then
		friendships[player.UserId] = friendships[player.UserId] or {}
		friendships[other.UserId] = friendships[other.UserId] or {}
		friendships[player.UserId][other.UserId] = true
		friendships[other.UserId][player.UserId] = true
	end
end

local function friendsHere(player: Player): number
	if RunService:IsStudio() then
		local fake = player:GetAttribute(Constants.DEV_FRIENDS_ATTRIBUTE)
		if typeof(fake) == "number" and fake >= 0 then
			return math.floor(fake)
		end
	end
	local present = {}
	for _, other in Players:GetPlayers() do
		table.insert(present, other.UserId)
	end
	return IncomeRules.countFriends(player.UserId, present, isFriend)
end

local function pay(player: Player, amount: number, source: string, friends: number?)
	EconomyService.award(player, amount, source)
	if player.Parent then
		Remotes.IncomeNotice:FireClient(player, { source = source, amount = amount, friends = friends })
	end
end

local function onPlayerAdded(player: Player)
	if clocks[player] then
		return
	end
	local t = os.clock()
	clocks[player] = { passiveAt = t + Constants.PASSIVE_YEN_SECONDS, friendsAt = t + Constants.FRIEND_YEN_SECONDS }
	for _, other in Players:GetPlayers() do
		if other ~= player then
			task.spawn(lookUp, player, other)
		end
	end
end

local function payDue()
	local t = os.clock()
	for player, clock in clocks do
		if not player.Parent then
			continue
		end
		local count
		count, clock.passiveAt = IncomeRules.due(clock.passiveAt, t, Constants.PASSIVE_YEN_SECONDS)
		if count > 0 then
			pay(player, count * Constants.PASSIVE_YEN, "passive")
		end
		count, clock.friendsAt = IncomeRules.due(clock.friendsAt, t, Constants.FRIEND_YEN_SECONDS)
		if count > 0 then
			local friends = friendsHere(player)
			local amount = count * IncomeRules.friendBonus(friends, Constants.FRIEND_YEN_PER_FRIEND)
			if amount > 0 then
				pay(player, amount, "friends", friends)
			end
		end
	end
end

function IncomeService.Init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		clocks[player] = nil
		local set = friendships[player.UserId]
		friendships[player.UserId] = nil
		for other in set or {} do
			if friendships[other] then
				friendships[other][player.UserId] = nil
			end
		end
	end)
end

function IncomeService.Start()
	while true do
		task.wait(CHECK_SECONDS)
		local ok, err = pcall(payDue)
		if not ok then
			warn("[NAU] income tick failed: " .. tostring(err))
		end
	end
end

return IncomeService
