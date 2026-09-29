-- Player settings (Phase 4, owner-approved 2026-09-23): the schema shared by the settings menu (client) and
-- the server, which validates every change and keeps it in the player's saved profile. Pure: no services.
--   toggle  a boolean
--   slider  an integer between min and max
--   choice  one of `options`
local Settings = {}

export type Def = {
	key: string,
	kind: "toggle" | "slider" | "choice",
	label: string,
	section: string,
	default: any,
	min: number?,
	max: number?,
	options: { string }?,
	hint: string?,
}

-- Sections shown in the settings menu, in order. Settings in any other section ("STATE") are saved and
-- validated the same way but have no control in the menu.
Settings.SECTIONS = { "MOTION", "VISUALS", "AUDIO" }

Settings.DEFS = {
	{ key = "speedLines", kind = "toggle", label = "Speed lines", section = "MOTION", default = true, hint = "Streaks, hand trails and vignette while running" },
	{ key = "cameraSway", kind = "toggle", label = "Camera sway", section = "MOTION", default = true, hint = "Camera leans into turns and bobs with your stride" },
	{ key = "runFov", kind = "toggle", label = "Wide running view", section = "MOTION", default = true, hint = "The view widens while you run" },
	{ key = "screenShake", kind = "toggle", label = "Screen shake", section = "MOTION", default = true, hint = "Off: a red edge flash instead" },
	{ key = "crowd", kind = "choice", label = "Crowd", section = "VISUALS", default = "Auto", options = { "Auto", "Off", "Low", "Medium", "High" }, hint = "Auto follows your graphics quality" },
	{ key = "music", kind = "slider", label = "Music", section = "AUDIO", default = 60, min = 0, max = 100 },
	{ key = "effects", kind = "slider", label = "Effects", section = "AUDIO", default = 80, min = 0, max = 100 },
	-- The how-to-play walkthrough opens by itself on the first visit only (owner, 2026-09-29). Once true it stays
	-- true (Settings.STICKY): nothing a client sends and no merge can set it back.
	{ key = "tutorialDone", kind = "toggle", label = "How to play seen", section = "STATE", default = false },
} :: { Def }

-- Toggles that only ever go from false to true (one-time flags).
Settings.STICKY = { tutorialDone = true } :: { [string]: boolean }

Settings.byKey = {} :: { [string]: Def }
for _, def in Settings.DEFS do
	Settings.byKey[def.key] = def
end

function Settings.defaults(): { [string]: any }
	local values = {}
	for _, def in Settings.DEFS do
		values[def.key] = def.default
	end
	return values
end

-- Is `value` valid for `def`? (Sliders take whole numbers in range.)
function Settings.valid(def: Def, value: any): boolean
	if def.kind == "toggle" then
		return type(value) == "boolean"
	elseif def.kind == "slider" then
		return type(value) == "number" and value == value and value % 1 == 0 and value >= (def.min :: number) and value <= (def.max :: number)
	elseif def.kind == "choice" then
		return type(value) == "string" and table.find(def.options :: { string }, value) ~= nil
	end
	return false
end

-- A complete, valid settings table from anything (a save, a client request): known keys with valid values
-- are kept, everything else falls back to the default. Unknown keys are dropped.
function Settings.sanitize(raw: any): { [string]: any }
	local values = Settings.defaults()
	if type(raw) ~= "table" then
		return values
	end
	for _, def in Settings.DEFS do
		local value = raw[def.key]
		if Settings.valid(def, value) then
			values[def.key] = value
		end
	end
	return values
end

-- A change request from a client: `changes` maps keys to new values. Returns the updated settings and
-- true, or the unchanged settings and false if the request is malformed (not a table, an unknown key, a bad
-- value, or more keys than the schema has). All or nothing, so a bad request never half-applies.
function Settings.apply(current: { [string]: any }, changes: any): ({ [string]: any }, boolean)
	if type(changes) ~= "table" then
		return current, false
	end
	local count = 0
	for key, value in changes do
		count += 1
		local def = type(key) == "string" and Settings.byKey[key] or nil
		if count > #Settings.DEFS or not def or not Settings.valid(def, value) then
			return current, false
		end
	end
	local updated = table.clone(current)
	for key, value in changes do
		if not (Settings.STICKY[key] and current[key] == true) then
			updated[key] = value
		end
	end
	return updated, true
end

-- The saved settings arrived while the session already had its own (the player changed some before the profile
-- loaded). The saved values win except for the keys changed this session; a one-time flag that is true on
-- either side stays true. `changed` = the keys the player changed during loading.
function Settings.merge(saved: { [string]: any }, session: { [string]: any }, changed: { [string]: boolean }): { [string]: any }
	local merged = table.clone(saved)
	for key in changed do
		if Settings.byKey[key] and session[key] ~= nil then
			merged[key] = session[key]
		end
	end
	for key in Settings.STICKY do
		if saved[key] == true or session[key] == true then
			merged[key] = true
		end
	end
	return merged
end

return Settings
