-- Unit tests for Lib/TeamRules (team battle: mode pick, opening split, joiners) and team scoring in MatchCore.
local TeamRules = require(script.Parent.Parent.Lib.TeamRules)
local MatchCore = require(script.Parent.Parent.Lib.MatchCore)
local T = require(script.Parent.TestUtil)

local TEAMS = { "Crimson", "Azure" }
local BOTH = { "FFA", "Team6v6" }

local tests = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

test("[TEAM] too few queued: always free-for-all", function()
	for _, roll in { 0, 0.49, 0.5, 0.99 } do
		T.eq(TeamRules.pickMode(BOTH, 3, 4, roll), "FFA", "3 queued, roll " .. roll)
	end
end)

test("[TEAM] enough queued: uniform between the enabled modes", function()
	T.eq(TeamRules.pickMode(BOTH, 4, 4, 0.2), "FFA")
	T.eq(TeamRules.pickMode(BOTH, 4, 4, 0.7), "Team6v6")
	T.eq(TeamRules.pickMode(BOTH, 12, 4, 0.999), "Team6v6")
	T.eq(TeamRules.pickMode({ "FFA" }, 12, 4, 0.9), "FFA", "team mode switched off")
end)

test("[TEAM] opening split: dealt in turn, sizes differ by at most one", function()
	local teams = TeamRules.split({ 11, 12, 13, 14, 15 }, TEAMS)
	local sizes = { Crimson = 0, Azure = 0 }
	for _, team in teams do
		sizes[team] += 1
	end
	T.eq(sizes.Crimson, 3)
	T.eq(sizes.Azure, 2)
	T.eq(teams[11], "Crimson")
	T.eq(teams[12], "Azure")
	local full = TeamRules.split({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }, TEAMS)
	local crimson = 0
	for _, team in full do
		if team == "Crimson" then
			crimson += 1
		end
	end
	T.eq(crimson, 6, "a full match is 6v6")
end)

test("[TEAM] joiners go to the smaller team, then the team that's behind", function()
	T.eq(TeamRules.teamForJoiner(TEAMS, { Crimson = 3, Azure = 2 }, {}), "Azure", "smaller team")
	T.eq(TeamRules.teamForJoiner(TEAMS, { Crimson = 2, Azure = 3 }, { Crimson = 9 }), "Crimson", "size beats score")
	T.eq(TeamRules.teamForJoiner(TEAMS, { Crimson = 3, Azure = 3 }, { Crimson = 5, Azure = 2 }), "Azure", "equal sizes: the team behind")
	T.eq(TeamRules.teamForJoiner(TEAMS, { Crimson = 3, Azure = 3 }, { Crimson = 1, Azure = 1 }), "Crimson", "all equal: the first team")
	T.eq(TeamRules.teamForJoiner(TEAMS, {}, {}), "Crimson", "an empty match")
end)

-- Team scoring runs through MatchCore; these pin the behaviour team battle relies on.
local function teamMatch()
	local m = MatchCore.new({ mode = "Team6v6", maxPlayers = 12, strikeLimit = 2, debounce = 0, staleWindow = 5, codeLength = 4 })
	m:addParticipant(1, "Crimson", 0)
	m:addParticipant(2, "Crimson", 0)
	m:addParticipant(3, "Azure", 0)
	m:addParticipant(4, "Azure", 0)
	for id = 1, 4 do
		m:spawn(id, 0)
	end
	return m
end

test("[TEAM] a teammate's code: no kill, no strike; an enemy's code scores for the team", function()
	local m = teamMatch()
	local r = m:submit(1, m.codes:getCode(1, 2), 1)
	T.eq(r.status, "teammate")
	T.eq(m.participants[1].strikes, 0, "not a strike")
	T.eq(m.participants[2].alive, true)
	r = m:submit(1, m.codes:getCode(1, 3), 2)
	T.eq(r.status, "eliminated")
	T.eq(m.teamScores.Crimson, 1)
	T.eq(m.teamScores.Azure, 0)
end)

test("[TEAM] time cap: the leading team wins; a team tie goes to sudden death", function()
	local m = teamMatch()
	m:submit(1, m.codes:getCode(1, 3), 1)
	local w = m:resolveTimeCap()
	T.truthy(w and w.kind == "team" and w.team == "Crimson", "Crimson leads 1-0")
	local tied = teamMatch()
	tied:submit(1, tied.codes:getCode(1, 3), 1)
	tied:submit(4, tied.codes:getCode(4, 2), 2)
	T.eq(tied:resolveTimeCap(), nil, "1-1")
	T.eq(tied.suddenDeath, true)
	local r = tied:submit(1, tied.codes:getCode(1, 4), 3)
	T.truthy(r.winner and r.winner.team == "Crimson" and r.winner.reason == "sudden_death", "next team to lead wins")
end)

return tests
