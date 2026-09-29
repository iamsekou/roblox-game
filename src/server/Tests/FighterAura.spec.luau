-- Unit tests for the fighter aura palette (CharacterDefs AURAS) and its setting (owner, 2026-09-29).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CharacterDefs = require(ReplicatedStorage.Shared.Modules.CharacterDefs)
local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local Settings = require(ReplicatedStorage.Shared.Modules.Settings)
local T = require(script.Parent.TestUtil)

-- Minimum RGB distance (0-255 per channel) between any two auras, and from a team colour.
local MIN_APART = 80
local MIN_FROM_TEAM = 70

local function distance(a: Color3, b: Color3): number
	local dr, dg, db = (a.R - b.R) * 255, (a.G - b.G) * 255, (a.B - b.B) * 255
	return math.sqrt(dr * dr + dg * dg + db * db)
end

local tests = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

test("[AURA] every fighter has an aura colour", function()
	for _, def in CharacterDefs.list do
		T.truthy(typeof(def.aura) == "Color3", def.id)
	end
end)

test("[AURA] no two fighters' auras look alike, and none looks like a team colour", function()
	local list = CharacterDefs.list
	for i = 1, #list do
		for j = i + 1, #list do
			local d = distance(list[i].aura :: Color3, list[j].aura :: Color3)
			T.truthy(d >= MIN_APART, string.format("%s vs %s: %.0f apart", list[i].id, list[j].id, d))
		end
		for _, team in Constants.TEAMS do
			local d = distance(list[i].aura :: Color3, team.color)
			T.truthy(d >= MIN_FROM_TEAM, string.format("%s vs team %s: %.0f apart", list[i].id, team.name, d))
		end
	end
end)

test("[AURA] the Fighter auras setting is on by default and can be switched off", function()
	T.eq(Settings.defaults().fighterAuras, true)
	local updated, ok = Settings.apply(Settings.defaults(), { fighterAuras = false })
	T.eq(ok, true)
	T.eq(updated.fighterAuras, false)
end)

return tests
