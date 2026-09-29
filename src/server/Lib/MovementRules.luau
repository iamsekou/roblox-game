-- Movement sanity check (owner-approved 2026-09-24): the rule, independent of Roblox services so it can be
-- unit-tested. Characters are simulated by their own clients (Roblox), so a cheater can make theirs move faster
-- than the game allows or teleport (e.g. in front of opponents, to read their numbers). The server samples each
-- fighter's position and keeps a distance *budget* per player:
--   * the budget refills at the allowed speed and is spent by the distance actually moved;
--   * it holds at most `burst` seconds of travel plus `slack` studs, so network hiccups (positions arriving in a
--     clump after a lag spike) pass, but sustained over-speed or a teleport does not;
--   * sideways and upward movement have separate budgets; falling is never limited.
-- A step that doesn't fit is rejected and leaves the state unchanged (the last good position stays).
--
-- Game-granted fast moves (knockbacks, dashes, grapples) are *paths* (audit fix, 2026-09-28): a path allows
-- extra travel only along its own direction, up to its length. Before, a dash raised the whole budget, so a
-- cheater could spend a 170 studs/s dash allowance sideways, onto an opponent's front. Movement across a path
-- still comes out of the ordinary walking budget.
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

-- A game-granted move: up to `left` more studs of horizontal travel along `dir` (a flat unit vector) until
-- `untilTime`. Spent as the fighter moves along it.
export type Path = { dir: Vector3, left: number, untilTime: number }

local function finite(v: Vector3): boolean
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < math.huge and math.abs(v.Y) < math.huge and math.abs(v.Z) < math.huge
end

-- A path along the flat part of `direction`, `length` studs long. nil if the direction has no flat part.
function MovementRules.path(direction: Vector3, length: number, untilTime: number): Path?
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if not finite(flat) or flat.Magnitude < 1e-3 or not (length > 0) then
		return nil
	end
	return { dir = flat.Unit, left = length, untilTime = untilTime }
end

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

-- Accepts or rejects a newly observed position. `paths` are the game-granted moves in effect (optional).
-- Returns (ok, horizontal distance, upward distance, charged): `charged` is the horizontal distance that
-- came out of the walking budget (what no path explains). A position that isn't a real number (NaN or
-- infinite) is always rejected: it would otherwise poison the budget for good.
function MovementRules.step(state: State, position: Vector3, now: number, limits: Limits, paths: { Path }?): (boolean, number, number, number)
	if not finite(position) then
		return false, 0, 0, 0
	end
	local dt = math.max(0, now - state.t)
	state.t = now
	state.flat = math.min(state.flat + limits.speed * dt, limits.speed * limits.burst + limits.slack)
	state.up = math.min(state.up + limits.rise * dt, limits.rise * limits.burst + limits.slack)
	local offset = position - state.last
	local flatOffset = Vector3.new(offset.X, 0, offset.Z)
	local flat = flatOffset.Magnitude
	local up = math.max(offset.Y, 0)
	-- Paths explain travel along their direction; whatever is left is ordinary walking.
	local spent: { [Path]: number } = {}
	local remaining = flatOffset
	for _, path in paths or {} do
		if now < path.untilTime and path.left > 0 then
			local along = remaining:Dot(path.dir)
			if along > 0 then
				local use = math.min(along, path.left)
				spent[path] = use
				remaining -= path.dir * use
			end
		end
	end
	local charged = remaining.Magnitude
	if charged > state.flat or up > state.up then
		return false, flat, up, charged
	end
	state.flat -= charged
	state.up -= up
	state.last = position
	for path, use in spent do
		path.left -= use
	end
	return true, flat, up, charged
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
