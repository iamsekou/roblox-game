-- Unit tests for Modules/Settings (the settings schema) and settings in Lib/ProfileData.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Settings = require(ReplicatedStorage.Shared.Modules.Settings)
local ProfileData = require(script.Parent.Parent.Lib.ProfileData)
local T = require(script.Parent.TestUtil)

local tests = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

test("[SETTINGS] defaults: every setting has a valid default", function()
	local values = Settings.defaults()
	for _, def in Settings.DEFS do
		T.truthy(Settings.valid(def, values[def.key]), def.key)
	end
	T.eq(values.speedLines, true)
	T.eq(values.crowd, "Auto")
end)

test("[SETTINGS] sanitize keeps valid values and repairs the rest", function()
	local values = Settings.sanitize({ speedLines = false, music = 35, crowd = "Low", effects = 101, runFov = "no", junk = 1 })
	T.eq(values.speedLines, false)
	T.eq(values.music, 35)
	T.eq(values.crowd, "Low")
	T.eq(values.effects, 80, "out of range: default")
	T.eq(values.runFov, true, "wrong type: default")
	T.eq(values.junk, nil, "unknown keys dropped")
	T.eq(Settings.sanitize(nil).music, 60, "nothing saved yet")
	T.eq(Settings.sanitize({ music = 12.5 }).music, 60, "sliders take whole numbers")
	T.eq(Settings.sanitize({ crowd = "Ultra" }).crowd, "Auto", "not an option")
end)

test("[SETTINGS] a change request applies all or nothing", function()
	local current = Settings.defaults()
	local updated, ok = Settings.apply(current, { speedLines = false, music = 0 })
	T.eq(ok, true)
	T.eq(updated.speedLines, false)
	T.eq(updated.music, 0)
	T.eq(current.speedLines, true, "the old table isn't modified")
	local same, bad = Settings.apply(current, { speedLines = false, music = 500 })
	T.eq(bad, false, "one bad value rejects the request")
	T.eq(same.speedLines, true, "nothing half-applied")
	T.eq(select(2, Settings.apply(current, { unknown = true })), false, "unknown key")
	T.eq(select(2, Settings.apply(current, "speedLines")), false, "not a table")
	T.eq(select(2, Settings.apply(current, { [1] = true })), false, "not a key")
end)

test("[SETTINGS] settings are saved with the profile and sanitised on load", function()
	local profile = ProfileData.sanitize({ yen = 10, settings = { screenShake = false, crowd = "Off" } }, {}, "Goku")
	T.eq(profile.settings.screenShake, false)
	T.eq(profile.settings.crowd, "Off")
	T.eq(profile.settings.music, 60, "missing values get defaults")
	local record = ProfileData.record(profile, "job", 1, true)
	T.eq(record.settings.crowd, "Off")
	T.eq(ProfileData.sanitize({ settings = { crowd = 7 } }, {}, "Goku").settings.crowd, "Auto", "damaged value repaired")
	T.eq(ProfileData.new("Goku").settings.speedLines, true, "a new player gets the defaults")
end)

return tests
