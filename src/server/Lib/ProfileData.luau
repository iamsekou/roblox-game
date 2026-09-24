-- Saved progress (Phase 3 item 4): the profile format and its rules. Pure, unit-tested.
--   * A profile is { version, yen, owned, equipped, settings, session?, updated }.
--   * Anything loaded is sanitised: a saved record can be old, damaged or tampered with, and the game only ever
--     sees valid values (never negative yen, only real yen-tier characters as purchases, an equipped character
--     the player actually owns).
--   * Session lock: one server owns a profile at a time. A server may claim it when nobody holds it, when it
--     already holds it, or when the holder's heartbeat is stale (that server crashed or lost contact).
--   * Settings (Phase 4) ride along in the same record, sanitised by the shared Modules/Settings schema.
local Settings = require(game:GetService("ReplicatedStorage").Shared.Modules.Settings)

local ProfileData = {}

ProfileData.VERSION = 1
local MAX_YEN = 1e12

export type Def = { id: string, tier: string }
export type Profile = { version: number, yen: number, owned: { string }, equipped: string, settings: { [string]: any } }
export type Session = { jobId: string, time: number }

function ProfileData.new(defaultCharacter: string): Profile
	return { version = ProfileData.VERSION, yen = 0, owned = {}, equipped = defaultCharacter, settings = Settings.defaults() }
end

-- A clean profile from whatever was stored (nil for a new player).
function ProfileData.sanitize(raw: any, defs: { Def }, defaultCharacter: string): Profile
	local profile = ProfileData.new(defaultCharacter)
	if type(raw) ~= "table" then
		return profile
	end
	local byId: { [string]: Def } = {}
	for _, def in defs do
		byId[def.id] = def
	end
	if type(raw.yen) == "number" and raw.yen == raw.yen then -- not NaN
		profile.yen = math.clamp(math.floor(raw.yen), 0, MAX_YEN)
	end
	if type(raw.owned) == "table" then
		local seen = {}
		for _, id in raw.owned do
			local def = type(id) == "string" and byId[id] or nil
			-- Only yen-tier characters are stored purchases; free ones are always owned, Robux ones come
			-- from Game Passes and are never trusted from a save.
			if def and def.tier == "Yen" and not seen[id] then
				seen[id] = true
				table.insert(profile.owned, id)
			end
		end
	end
	local equipped = raw.equipped
	local def = type(equipped) == "string" and byId[equipped] or nil
	if def and (def.tier == "Free" or table.find(profile.owned, equipped) ~= nil) then
		profile.equipped = equipped
	end
	profile.settings = Settings.sanitize(raw.settings)
	return profile
end

-- May the server `jobId` take this stored record's lock at `now`?
function ProfileData.canClaim(raw: any, jobId: string, now: number, staleAfter: number): boolean
	local session = type(raw) == "table" and raw.session or nil
	if type(session) ~= "table" or type(session.jobId) ~= "string" or type(session.time) ~= "number" then
		return true
	end
	return session.jobId == jobId or now - session.time >= staleAfter
end

-- Does the stored record still belong to `jobId`? (A save is skipped if another server took over.)
function ProfileData.holds(raw: any, jobId: string): boolean
	local session = type(raw) == "table" and raw.session or nil
	return type(session) == "table" and session.jobId == jobId
end

-- The record to store: the profile, plus the lock (kept on a heartbeat, dropped on release).
function ProfileData.record(profile: Profile, jobId: string, now: number, release: boolean): { [string]: any }
	return {
		version = ProfileData.VERSION,
		yen = profile.yen,
		owned = table.clone(profile.owned),
		equipped = profile.equipped,
		settings = table.clone(profile.settings),
		session = if release then nil else { jobId = jobId, time = now },
		updated = now,
	}
end

return ProfileData
