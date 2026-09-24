-- Team battle rules (Phase 3 item 7, owner-approved 2026-09-23). Pure, unit-tested; RoundManager applies them.
--   * Mode: uniform random among the enabled modes, but team mode only when enough fighters are queued.
--   * Opening teams: fighters are dealt alternately (the caller shuffles first), so sizes differ by at most one.
--   * Joiners go to the smaller team; on equal sizes, the team that's behind; then the first team.
--   * Nobody changes team mid-round.
local TeamRules = {}

-- `roll` is a random number in [0, 1).
function TeamRules.pickMode(enabled: { string }, queued: number, minForTeams: number, roll: number): string
	local allowed = {}
	for _, mode in enabled do
		if mode ~= "Team6v6" or queued >= minForTeams then
			table.insert(allowed, mode)
		end
	end
	if #allowed == 0 then
		return "FFA"
	end
	return allowed[math.clamp(math.floor(roll * #allowed) + 1, 1, #allowed)]
end

-- Deals `ids` (already shuffled) onto `teamNames` in turn. Returns id -> team name.
function TeamRules.split(ids: { number }, teamNames: { string }): { [number]: string }
	local teams = {}
	for i, id in ids do
		teams[id] = teamNames[(i - 1) % #teamNames + 1]
	end
	return teams
end

-- The team a new fighter joins. `sizes` and `scores` are keyed by team name (missing = 0).
function TeamRules.teamForJoiner(teamNames: { string }, sizes: { [string]: number }, scores: { [string]: number }): string
	local best = teamNames[1]
	for i = 2, #teamNames do
		local name = teamNames[i]
		local size, bestSize = sizes[name] or 0, sizes[best] or 0
		if size < bestSize or (size == bestSize and (scores[name] or 0) < (scores[best] or 0)) then
			best = name
		end
	end
	return best
end

return TeamRules
