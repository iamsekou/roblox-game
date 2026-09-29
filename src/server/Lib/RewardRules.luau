-- Kill-farming limit (audit fix, 2026-09-28). Two cooperating accounts can trade eliminations every few
-- seconds (respawn + spawn protection) for yen and leaderboard kills. So an elimination of the SAME victim
-- by the SAME attacker pays (yen + a leaderboard kill) at most `maxPaid` times within any `window` seconds.
-- It still counts for the round (score, win, Gojo's reading) like any other: only the rewards stop.
-- Normal play is untouched: in a busy match you rarely eliminate one person more than every 20 seconds.
-- Pure: no services, so it runs in the unit tests.
local RewardRules = {}

export type State = { [number]: { [number]: { number } } } -- attacker -> victim -> times of paid eliminations

function RewardRules.new(): State
	return {}
end

-- Should this elimination pay? Records it if so.
function RewardRules.claim(state: State, attacker: number, victim: number, now: number, window: number, maxPaid: number): boolean
	local byVictim = state[attacker]
	if not byVictim then
		byVictim = {}
		state[attacker] = byVictim
	end
	local times = byVictim[victim] or {}
	byVictim[victim] = times
	for i = #times, 1, -1 do
		if now - times[i] >= window then
			table.remove(times, i)
		end
	end
	if #times >= maxPaid then
		return false
	end
	table.insert(times, now)
	return true
end

-- A player left: drop everything about them, as attacker and as victim.
function RewardRules.forget(state: State, id: number)
	state[id] = nil
	for _, byVictim in state do
		byVictim[id] = nil
	end
end

return RewardRules
