-- Movement sanity check (owner-approved 2026-09-24): the rule, independent of Roblox services so it can be
-- unit-tested. Characters are simulated by their own clients (Roblox), so a cheater can make theirs move faster
-- than the game allows or teleport (e.g. in front of opponents, to read their numbers). The server samples each
-- fighter's position and keeps a distance *budget* per player:
--   * the budget refills at the allowed speed and is spent by the distance actually moved;
--   * it holds at most `burst` seconds of travel plus `slack` studs, so network hiccups (positions arriving in a
--     clump after a lag spike) pass, but sustained over-speed or a teleport does not;
--   * sideways and upward movement have separate budgets; falling is never limited.
-- A step that doesn't fit is rejected and leaves the state unchanged (the last good position stays).
local MovementRules = {}

export type Limits = {
	speed: number, -- allowed horizontal studs/second right now
	rise: number, -- allowed upward studs/second right now
	burst: number, -- seconds of travel the budget can hold
	slack: number, -- extra studs always allowed on top
}

export type State = {
	last: Vector3, -- last accepted position
	t: number, -- when it was accepted
	flat: number, -- horizontal budget, studs
	up: number, -- upward budget, studs
}

function MovementRules.new(position: Vector3, now: number, limits: Limits): State
	return { last = position, t = now, flat = limits.slack, up = limits.slack }
end

-- The server moved the fighter itself (spawn, teleport ability): start again from `position`.
function MovementRules.reset(state: State, position: Vector3, now: number, limits: Limits)
	state.last = position
	state.t = now
	state.flat = limits.slack
	state.up = limits.slack
end

-- Accepts or rejects a newly observed position. Returns (ok, horizontal distance, upward distance).
function MovementRules.step(state: State, position: Vector3, now: number, limits: Limits): (boolean, number, number)
	local dt = math.max(0, now - state.t)
	state.t = now
	state.flat = math.min(state.flat + limits.speed * dt, limits.speed * limits.burst + limits.slack)
	state.up = math.min(state.up + limits.rise * dt, limits.rise * limits.burst + limits.slack)
	local offset = position - state.last
	local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
	local up = math.max(offset.Y, 0)
	if flat > state.flat or up > state.up then
		return false, flat, up
	end
	state.flat -= flat
	state.up -= up
	state.last = position
	return true, flat, up
end

-- The limits right now: the base (walk speed with a margin, a jump) raised by any game-granted burst
-- (knockback, dash, grapple) that hasn't expired. `grants` holds { speed, rise, untilTime }.
function MovementRules.limits(walkSpeed: number, margin: number, baseRise: number, grants: { { speed: number, rise: number, untilTime: number } }, now: number, burst: number, slack: number): Limits
	local speed, rise = walkSpeed * margin, baseRise
	for _, grant in grants do
		if now < grant.untilTime then
			speed = math.max(speed, grant.speed)
			rise = math.max(rise, grant.rise)
		end
	end
	return { speed = speed, rise = rise, burst = burst, slack = slack }
end

return MovementRules
