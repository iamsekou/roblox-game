-- Admin panel (owner, 2026-09-30: "an admin panel for me and sam"). Works on live servers and in Studio.
--
-- The client only *asks* (Remotes.AdminCommand). Every request is checked here, in this order: is the caller an
-- admin (Lib/AdminRules, by user id; the client's own idea of who's an admin is never trusted), not too fast, and
-- does the request have a known command with clean arguments. Only then does it run, through the same systems the
-- game uses (EconomyService, XpService, RoundManager, AbilityService, ClashDuelService), so an admin action
-- can't do anything those systems don't already allow. A non-admin gets "denied" and nothing else; the attempt is
-- logged on the server.
--
-- Every accepted action is written to the server log and to a short recent-actions list the admins see.
-- Admins get AdminState when they join (that's what shows the ADMIN button); nobody else hears it exists.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local Currency = require(ReplicatedStorage.Shared.Modules.Currency)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local AdminRules = require(script.Parent.Parent.Lib.AdminRules)
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)
local EconomyService = require(script.Parent.EconomyService)
local XpService = require(script.Parent.XpService)
local RoundManager = require(script.Parent.RoundManager)
local AbilityService = require(script.Parent.AbilityService)
local ClashDuelService = require(script.Parent.ClashDuelService)
local MapService = require(script.Parent.MapService)
local MovementGuard = require(script.Parent.MovementGuard)
local PlayerLifeService = require(script.Parent.PlayerLifeService)

local AdminService = {}

local LIMITS: AdminRules.Limits = {
	maxCredits = Constants.ADMIN_MAX_CREDITS,
	maxXp = Constants.ADMIN_MAX_XP,
	minSeconds = Constants.ADMIN_MIN_SECONDS,
	maxSeconds = Constants.ADMIN_MAX_SECONDS,
	maxReason = Constants.ADMIN_MAX_REASON,
}

local requests = RateLimiter.new(Constants.ADMIN_MIN_INTERVAL)
local recent: { { t: number, text: string } } = {}
local unlocked: { [Player]: boolean } = {}
local ghosts: { [Player]: Model } = {} -- admin -> the character made invisible

local function isAdmin(player: Player): boolean
	return AdminRules.isAdmin(player.UserId, Constants.ADMIN_USER_IDS, RunService:IsStudio())
end

local function stateFor(player: Player): { [string]: any }
	return {
		admin = true,
		log = recent,
		mode = RoundManager.adminMode(),
		unlockAll = unlocked[player] == true,
		ghost = ghosts[player] ~= nil,
	}
end

local function pushAll()
	for _, player in Players:GetPlayers() do
		if isAdmin(player) then
			Remotes.AdminState:FireClient(player, stateFor(player))
		end
	end
end

local function record(by: Player, text: string)
	local line = string.format("%s: %s", by.Name, text)
	print("[NAU] admin " .. line)
	table.insert(recent, 1, { t = workspace:GetServerTimeNow(), text = line })
	while #recent > Constants.ADMIN_LOG_SIZE do
		table.remove(recent)
	end
end

-- Ghost: the admin's own character turns invisible to everyone (and loses its name tag) so they can watch a
-- round from inside the arena. Only outside a fight: an invisible fighter would be cheating. The character comes
-- back visible when it's replaced (ghost off sends them to the lobby; pressing FIGHT spawns a fresh one).
local function setGhost(player: Player, on: boolean): (boolean, string)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if on then
		if ghosts[player] then
			return false, "Ghost is already on"
		end
		if not character or not humanoid or humanoid.Health <= 0 then
			return false, "You need a character first"
		end
		local match = RoundManager.getMatch()
		if match and match.participants[player.UserId] then
			return false, "Leave the round first: an invisible fighter would be cheating"
		end
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				d.Transparency = 1
			end
		end
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		ghosts[player] = character
		if match then
			character:PivotTo(MapService.findArenaSpawn({}) + Vector3.new(0, 6, 0))
			MovementGuard.reset(player)
			return true, "Ghost on: you're in the arena, invisible"
		end
		return true, "Ghost on (no round running, so you stayed put)"
	end
	if not ghosts[player] then
		return false, "Ghost is already off"
	end
	ghosts[player] = nil
	task.spawn(PlayerLifeService.spawnAt, player, MapService.getLobbySpawn())
	return true, "Ghost off: back in the lobby"
end

local function targetOf(args: { [string]: any }): Player?
	return Players:GetPlayerByUserId(args.target)
end

-- Each command: (admin, clean args) -> (ok, message for the admin, log text or nil).
local RUN: { [string]: (Player, { [string]: any }) -> (boolean, string, string?) } = {}

RUN.giveCredits = function(_admin, args)
	local target = targetOf(args)
	if not target then
		return false, "That player left", nil
	end
	EconomyService.award(target, args.credits, "admin")
	local text = string.format("gave %s %d %s", target.Name, args.credits, Currency.NAME)
	return true, text, text
end

RUN.takeCredits = function(_admin, args)
	local target = targetOf(args)
	if not target then
		return false, "That player left", nil
	end
	local amount = math.min(args.credits, EconomyService.getBalance(target))
	if amount <= 0 then
		return false, target.Name .. " has none to take", nil
	end
	EconomyService.spend(target, amount)
	local text = string.format("took %d %s from %s", amount, Currency.NAME, target.Name)
	return true, text, text
end

RUN.giveXp = function(_admin, args)
	local target = targetOf(args)
	if not target then
		return false, "That player left", nil
	end
	local character = AbilityService.equippedOf(target)
	XpService.awardExact(target, character, args.xp, "admin")
	local text = string.format("gave %s %d XP (%s)", target.Name, args.xp, character)
	return true, text, text
end

RUN.startRound = function()
	local ok, message = RoundManager.adminStartNow()
	return ok, message, if ok then "started the round" else nil
end

RUN.endRound = function()
	local ok, message = RoundManager.adminEndNow()
	return ok, message, if ok then "ended the round" else nil
end

RUN.setTimeLeft = function(_admin, args)
	local ok, message = RoundManager.adminSetTimeLeft(args.seconds)
	return ok, message, if ok then string.format("set the clock to %d s", args.seconds) else nil
end

RUN.setMode = function(_admin, args)
	local mode = if args.mode == "random" then nil else args.mode
	RoundManager.adminSetMode(mode)
	local text = "set the mode to " .. (mode or "random") .. " (from the next round)"
	return true, text, text
end

RUN.kick = function(admin, args)
	local target = targetOf(args)
	if not target then
		return false, "That player left", nil
	end
	if target == admin then
		return false, "You can't kick yourself", nil
	end
	if isAdmin(target) and not RunService:IsStudio() then
		return false, "Admins can't kick each other", nil
	end
	local text = string.format("kicked %s (%s)", target.Name, args.reason)
	target:Kick("Removed by an admin: " .. args.reason)
	return true, text, text
end

RUN.unlockAll = function(admin, args)
	unlocked[admin] = args.on or nil
	AbilityService.setAdminUnlock(admin, args.on)
	local text = if args.on then "unlocked every fighter for themselves" else "turned their fighter unlock off"
	return true, if args.on then "Every fighter unlocked for you (this session)" else "Back to your real fighters", text
end

RUN.duel = function(admin, args)
	local ok, message = ClashDuelService.testDuel(admin, if args.duel == "watch" then "watch" else "lose")
	return ok, message, if ok then "started a test duel (" .. args.duel .. ")" else nil
end

RUN.ghost = function(admin, args)
	local ok, message = setGhost(admin, args.on)
	return ok, message, if ok then (if args.on then "turned ghost on" else "turned ghost off") else nil
end

local function handle(player: Player, command: any, args: any)
	if not isAdmin(player) then
		warn(string.format("[NAU] admin: refused %s (%d), not an admin", player.Name, player.UserId))
		return { status = "denied" }
	end
	if not RateLimiter.allow(requests, player, os.clock()) then
		return { status = "rate_limited" }
	end
	local clean, why = AdminRules.validate(command, args, LIMITS)
	if not clean then
		return { status = why }
	end
	local ok, success, message, logText = pcall(RUN[command], player, clean)
	if not ok then
		warn("[NAU] admin command failed: " .. tostring(success))
		return { status = "error", message = "Something went wrong (see the server log)" }
	end
	if logText then
		record(player, logText)
	end
	pushAll()
	return { status = if success then "ok" else "refused", message = message }
end

function AdminService.Init()
	Remotes.AdminCommand.OnServerInvoke = handle
	local function onPlayerAdded(player: Player)
		if not isAdmin(player) then
			return
		end
		Remotes.AdminState:FireClient(player, stateFor(player))
		-- A ghost's character is replaced when they respawn, join a round or turn ghost off: the new one is
		-- visible, so ghost is over.
		player.CharacterAdded:Connect(function(character)
			if ghosts[player] and ghosts[player] ~= character then
				ghosts[player] = nil
				pushAll()
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.defer(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		RateLimiter.forget(requests, player)
		unlocked[player] = nil
		ghosts[player] = nil
	end)
end

return AdminService
