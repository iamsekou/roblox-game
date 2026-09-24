-- Saved progress (Phase 3 item 4): each player's yen, bought characters and equipped character survive
-- leaving and rejoining. Rules and format in Lib/ProfileData; DataStore calls through SafeStore.
--
--   Join      claim the profile's session lock and load it (UpdateAsync). If another server still holds a
--             fresh lock (the player hopped servers faster than that one saved), wait and retry; after the
--             retries, take it over. Loaded data is sanitised, then handed to EconomyService (yen, purchases)
--             and AbilityService (equipped character).
--   Play      the profile follows every balance change, purchase and equip as it happens.
--   Autosave  every PROFILE_AUTOSAVE_SECONDS, which also renews the lock.
--   Leave     save and release the lock. Shutdown: the same for everyone (BindToClose).
-- A save only writes while this server still holds the lock, so a server that lost it can never overwrite
-- newer progress. Offline (Studio without API access): progress lasts the session and the player is told.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local CharacterDefs = require(ReplicatedStorage.Shared.Modules.CharacterDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ProfileData = require(script.Parent.Parent.Lib.ProfileData)
local SafeStore = require(script.Parent.SafeStore)
local EconomyService = require(script.Parent.EconomyService)
local AbilityService = require(script.Parent.AbilityService)

local ProfileService = {}

type Entry = {
	profile: ProfileData.Profile,
	loaded: boolean, -- false until the saved profile arrived (nothing is saved before that)
	saving: boolean,
}

-- In Studio, game.JobId is empty; a random id keeps each Play session's lock distinct.
local jobId = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)
local entries: { [Player]: Entry } = {}

local function key(player: Player): string
	return "u_" .. player.UserId
end

local function log(message: string)
	if RunService:IsStudio() then
		print("[NAU] profiles: " .. message)
	end
end

local function tell(player: Player, status: string)
	if player.Parent then
		Remotes.ProfileState:FireClient(player, { status = status })
	end
end

local save: (Player, Entry, boolean) -> boolean -- below

-- Loading ----------------------------------------------------------------------------------------

local function load(player: Player)
	local entry: Entry = { profile = ProfileData.new(Constants.DEFAULT_CHARACTER), loaded = false, saving = false }
	entries[player] = entry
	local store = SafeStore.regular(Constants.PROFILE_STORE)
	for attempt = 1, Constants.PROFILE_LOAD_ATTEMPTS + 1 do
		if not player.Parent or entries[player] ~= entry then
			return
		end
		if not store then
			break
		end
		local force = attempt > Constants.PROFILE_LOAD_ATTEMPTS -- out of patience: take the lock over
		local claimed, loaded = false, nil
		local ok = SafeStore.call(Enum.DataStoreRequestType.UpdateAsync, function()
			return store:UpdateAsync(key(player), function(old)
				local now = os.time()
				if not force and not ProfileData.canClaim(old, jobId, now, Constants.PROFILE_LOCK_STALE_SECONDS) then
					claimed = false
					return nil -- someone else holds it: change nothing, try again shortly
				end
				claimed = true
				loaded = ProfileData.sanitize(old, CharacterDefs.list, Constants.DEFAULT_CHARACTER)
				return ProfileData.record(loaded :: any, jobId, now, false)
			end)
		end)
		if ok and claimed and loaded then
			local profile = loaded :: ProfileData.Profile
			if not player.Parent or entries[player] ~= entry then
				-- Left while loading: hand the lock straight back, unchanged, so their next server needn't wait.
				save(player, { profile = profile, loaded = true, saving = false }, true)
				return
			end
			entry.loaded = true
			-- Hand it to the game. Anything earned while loading is kept on top (applySaved adds).
			EconomyService.applySaved(player, profile.yen, profile.owned)
			entry.profile.yen = EconomyService.getBalance(player)
			entry.profile.owned = EconomyService.boughtList(player)
			entry.profile.equipped = AbilityService.applySavedEquip(player, profile.equipped)
			log(string.format("loaded %s: ¥%d, %d bought, equipped %s%s", player.Name, profile.yen, #profile.owned, profile.equipped, if force then " (lock taken over)" else ""))
			tell(player, "loaded")
			return
		end
		if SafeStore.isOffline() then
			break
		end
		task.wait(Constants.PROFILE_LOAD_RETRY_SECONDS)
	end
	-- No DataStores (or no answer at all): the session still works, it just isn't saved.
	log(string.format("%s is playing unsaved (%s)", player.Name, tostring(select(2, SafeStore.isOffline()) or "no response")))
	tell(player, "offline")
end

-- Saving -----------------------------------------------------------------------------------------

local inFlight = 0 -- saves not yet finished (shutdown waits for these)

-- Returns true if the profile was written. One save per player at a time: a second one (the save on leaving,
-- arriving mid-autosave) waits its turn, so it still writes the latest values and releases the lock.
function save(player: Player, entry: Entry, release: boolean): boolean
	inFlight += 1
	while entry.saving do
		task.wait(0.1)
	end
	local store = if entry.loaded then SafeStore.regular(Constants.PROFILE_STORE) else nil
	if not store then
		inFlight -= 1
		return false
	end
	entry.saving = true
	local wrote = false
	local profile = entry.profile
	local ok = SafeStore.call(Enum.DataStoreRequestType.UpdateAsync, function()
		return store:UpdateAsync(key(player), function(old)
			if not ProfileData.holds(old, jobId) then
				wrote = false
				return nil -- another server took this profile over: never overwrite its newer progress
			end
			wrote = true
			return ProfileData.record(profile, jobId, os.time(), release)
		end)
	end)
	entry.saving = false
	inFlight -= 1
	if ok and wrote and release then
		entry.loaded = false -- released: this server is done with the profile (shutdown and leaving both release)
	elseif ok and not wrote then
		entry.loaded = false -- we lost the lock; stop saving this session
		warn(string.format("[NAU] %s's profile is held by another server; this server stopped saving it", player.Name))
	end
	return ok and wrote
end

local function saveAll(release: boolean)
	for player, entry in entries do
		task.spawn(save, player, entry, release)
	end
end

function ProfileService.Init()
	-- The profile follows the game as it happens, so it's already current when the player leaves.
	EconomyService.onBalanceChanged(function(player, balance)
		local entry = entries[player]
		if entry and entry.loaded then
			entry.profile.yen = balance
		end
	end)
	EconomyService.onInventoryChanged(function(player)
		local entry = entries[player]
		if entry and entry.loaded then
			entry.profile.owned = EconomyService.boughtList(player)
		end
	end)
	AbilityService.onEquipped(function(player, id)
		local entry = entries[player]
		if entry then
			entry.profile.equipped = id
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(load, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local entry = entries[player]
		entries[player] = nil
		if entry then
			if save(player, entry, true) then
				log("saved and released " .. player.Name)
			end
		end
	end)
	game:BindToClose(function()
		-- Save everyone still here and release their locks, then wait for every save (including ones started
		-- by players leaving) within Roblox's shutdown allowance.
		saveAll(true)
		local deadline = os.clock() + Constants.PROFILE_SHUTDOWN_WAIT_SECONDS
		while inFlight > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
		log(if inFlight == 0 then "shutdown saves done" else inFlight .. " saves unfinished at shutdown")
	end)
end

function ProfileService.Start()
	while true do
		task.wait(Constants.PROFILE_AUTOSAVE_SECONDS)
		saveAll(false)
	end
end

return ProfileService
