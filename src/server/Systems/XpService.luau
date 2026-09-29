-- Character XP and prestige (owner-approved 2026-09-29; rules in Lib/XpRules). Every character a player fights
-- as earns its own XP:
--   elimination      XP_ELIMINATION          (a code elimination)
--   clash win        XP_CLASH_WIN            (instead of the elimination's XP)
--   round win        XP_ROUND_WIN            (team battle: everyone on the winning team)
--   time alive       XP_PER_MINUTE_ALIVE     (per full minute alive in a round, spawn protection excluded)
-- Training Grounds pay XP_TRAINING_MULTIPLIER of all of it (setScale). No remote can ask for XP; only the server's
-- own verified events pay it. Prestige is the one request: allowed only when the last bar is full.
--
-- Saved in the profile (ProfileService hands the saved progress over with applySaved and keeps its copy current
-- through onChanged). XP earned before the save arrives is added on top of it; prestiging waits for the save.
-- Each arena character carries its fighter's prestige (Constants.PRESTIGE_ATTRIBUTE) so every client can show
-- the badge on the name chip and brighten the aura.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local CharacterDefs = require(ReplicatedStorage.Shared.Modules.CharacterDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local XpRules = require(script.Parent.Parent.Lib.XpRules)
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)
local RoundManager = require(script.Parent.RoundManager)
local EliminationService = require(script.Parent.EliminationService)
local AbilityService = require(script.Parent.AbilityService)
local FighterRegistry = require(script.Parent.FighterRegistry)

local XpService = {}

local PARAMS = XpRules.params(Constants)
local TICK_SECONDS = 1

type Entry = {
	progress: { [string]: XpRules.Progress },
	loaded: boolean,
	pending: { [string]: number }, -- XP earned before the save arrived, per character (added on load)
	aliveSeconds: number, -- toward the next minute-alive payout
}

local entries: { [Player]: Entry } = {}
local fighters: { [Player]: string } = {} -- the character each player last started a life as (round wins land after the round)
local listeners: { (Player, { [string]: XpRules.Progress }) -> () } = {}
local prestigeRequests = RateLimiter.new(Constants.XP_PRESTIGE_MIN_INTERVAL)
local scale = 1

local function log(message: string)
	if RunService:IsStudio() then
		print("[NAU] xp: " .. message)
	end
end

local function snapshot(entry: Entry): { [string]: any }
	local list = {}
	for id, progress in entry.progress do
		list[id] = {
			p = progress.p,
			l = progress.l,
			x = progress.x,
			need = XpRules.need(progress.l, progress.p, PARAMS),
			full = XpRules.isFull(progress, PARAMS),
		}
	end
	return list
end

local function push(player: Player, extra: { [string]: any }?)
	local entry = entries[player]
	if not entry or not player.Parent then
		return
	end
	local payload = extra or {}
	payload.loaded = entry.loaded
	payload.progress = snapshot(entry)
	payload.maxLevel = PARAMS.maxLevel
	payload.maxPrestige = PARAMS.maxPrestige
	Remotes.XpState:FireClient(player, payload)
end

local function changed(player: Player)
	local entry = entries[player]
	if not entry then
		return
	end
	for _, listener in listeners do
		task.spawn(listener, player, entry.progress)
	end
end

-- The prestige badge on the arena character (every client reads it: name chip, aura).
local function tagPrestige(player: Player)
	local character = player.Character
	local fighter = fighters[player]
	local entry = entries[player]
	if character and fighter and entry then
		local progress = entry.progress[fighter]
		character:SetAttribute(Constants.PRESTIGE_ATTRIBUTE, if progress then progress.p else 0)
	end
end

-- Pays `amount` (before the training scale) to `character`'s progress. `reason` is shown in the popup.
function XpService.award(player: Player, character: string?, amount: number, reason: string)
	local entry = entries[player]
	if not entry or not character or not CharacterDefs.byId[character] then
		return
	end
	local paid = math.floor(amount * scale)
	if paid <= 0 then
		return
	end
	if not entry.loaded then
		entry.pending[character] = (entry.pending[character] or 0) + paid
	end
	local before = entry.progress[character] or XpRules.new()
	local after, levels, full = XpRules.add(before, paid, PARAMS)
	entry.progress[character] = after
	changed(player)
	push(player, { gain = { character = character, amount = paid, reason = reason, levels = levels, full = full, level = after.l } })
	if levels > 0 or full then
		log(string.format("%s's %s: +%d (%s) -> P%d L%d%s", player.Name, character, paid, reason, after.p, after.l, if full then " FULL" else ""))
	end
end

-- Training Grounds: every payout is multiplied by this.
function XpService.setScale(value: number)
	scale = value
end

function XpService.progressOf(player: Player, character: string): XpRules.Progress
	local entry = entries[player]
	return (entry and entry.progress[character]) or XpRules.new()
end

-- A copy of every character's progress (what the profile saves).
function XpService.snapshotOf(player: Player): { [string]: XpRules.Progress }
	local copy = {}
	local entry = entries[player]
	for id, progress in if entry then entry.progress else {} do
		copy[id] = { p = progress.p, l = progress.l, x = progress.x }
	end
	return copy
end

-- ProfileService: the saved progress arrived. Anything earned while it loaded goes on top.
function XpService.applySaved(player: Player, saved: { [string]: XpRules.Progress })
	local entry = entries[player]
	if not entry then
		return
	end
	local merged = {}
	for id, progress in saved do
		merged[id] = { p = progress.p, l = progress.l, x = progress.x }
	end
	for id, amount in entry.pending do
		merged[id] = (XpRules.add(merged[id] or XpRules.new(), amount, PARAMS))
	end
	entry.progress = merged
	entry.pending = {}
	entry.loaded = true
	changed(player)
	tagPrestige(player)
	push(player)
end

-- Called with (player, progress) whenever it changes (ProfileService keeps the save current).
function XpService.onChanged(listener: (Player, { [string]: XpRules.Progress }) -> ())
	table.insert(listeners, listener)
end

local function handlePrestige(player: Player, character: any)
	if not RateLimiter.allow(prestigeRequests, player, os.clock()) then
		return { status = "rate_limited" }
	end
	local entry = entries[player]
	if type(character) ~= "string" or not CharacterDefs.byId[character] or not entry then
		return { status = "unknown" }
	end
	if not entry.loaded then
		return { status = "loading" } -- the save isn't here yet: a prestige now could be lost or doubled
	end
	local next = XpRules.prestige(entry.progress[character] or XpRules.new(), PARAMS)
	if not next then
		return { status = "not_ready" }
	end
	entry.progress[character] = next
	changed(player)
	tagPrestige(player)
	push(player, { prestiged = { character = character, p = next.p } })
	log(string.format("%s prestiged %s to %d", player.Name, character, next.p))
	return { status = "prestiged", p = next.p }
end

local function onPlayerAdded(player: Player)
	entries[player] = { progress = {}, loaded = false, pending = {}, aliveSeconds = 0 }
	push(player)
	-- Studio-only test hook: a number on the Player grants that much XP to the equipped character. Ignored live.
	if RunService:IsStudio() then
		local attribute = Constants.DEV_GRANT_XP_ATTRIBUTE
		player:GetAttributeChangedSignal(attribute):Connect(function()
			local amount = player:GetAttribute(attribute)
			if typeof(amount) == "number" and amount >= 1 then
				player:SetAttribute(attribute, nil)
				local was = scale
				scale = 1 -- the test grant is exact, even on a training server
				XpService.award(player, AbilityService.equippedOf(player), math.floor(amount), "studio test")
				scale = was
			end
		end)
	end
end

function XpService.Init()
	Remotes.Prestige.OnServerInvoke = handlePrestige
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		entries[player] = nil
		fighters[player] = nil
		RateLimiter.forget(prestigeRequests, player)
	end)
	RoundManager.onLifeStarted(function(player)
		if FighterRegistry.isBot(player) then
			return -- training bots earn nothing (and a fresh handle each round would pile up here)
		end
		-- Deferred: AbilityService records the life's character in its own handler first.
		task.defer(function()
			fighters[player] = AbilityService.fighterOf(player) or fighters[player]
			tagPrestige(player)
		end)
	end)
	-- Training Grounds switch fighters mid-life: XP (and the prestige badge) follow the switch.
	AbilityService.onEquipped(function(player, id)
		if AbilityService.fighterOf(player) == id then
			fighters[player] = id
			tagPrestige(player)
		end
	end)
	EliminationService.onElimination(function(attacker, _victimId, _rewarded, cause)
		local character = AbilityService.fighterOf(attacker) or fighters[attacker]
		if cause == "clash" then
			XpService.award(attacker, character, Constants.XP_CLASH_WIN, "CLASH WON")
		else
			XpService.award(attacker, character, Constants.XP_ELIMINATION, "ELIMINATION")
		end
	end)
	RoundManager.onRoundFinished(function(match, winner)
		for id, p in match.participants do
			local won = (winner.kind == "player" and winner.id == id) or (winner.kind == "team" and p.team == winner.team)
			local player = if won then Players:GetPlayerByUserId(id) else nil
			if player then
				XpService.award(player, fighters[player], Constants.XP_ROUND_WIN, "ROUND WON")
			end
		end
	end)
end

-- Minutes alive: counted every second for each fighter alive in the round and past spawn protection.
function XpService.Start()
	while true do
		task.wait(TICK_SECONDS)
		local ok, err = pcall(function()
			local match = RoundManager.getMatch()
			if not match or match.ended then
				return
			end
			for id, p in match.participants do
				local player = Players:GetPlayerByUserId(id)
				local entry = player and entries[player]
				if entry and p.alive and p.protectedUntil == nil then
					entry.aliveSeconds += TICK_SECONDS
					if entry.aliveSeconds >= 60 then
						entry.aliveSeconds -= 60
						XpService.award(player :: Player, AbilityService.fighterOf(player :: Player), Constants.XP_PER_MINUTE_ALIVE, "SURVIVED A MINUTE")
					end
				end
			end
		end)
		if not ok then
			warn("[NAU] xp tick failed: " .. tostring(err))
		end
	end
end

return XpService
