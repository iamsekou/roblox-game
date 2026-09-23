-- Clash rule (owner-approved 2026-09-23). Two fighters who start the SAME attack ability at each other at
-- nearly the same moment clash instead of hitting: both abilities are cancelled (cooldowns stay spent) and
-- the pair is locked face to face for a short anime-style exchange. Nothing new decides the winner: they
-- stand inside reading range, so the first correct code wins through the normal elimination rules.
--
-- Pure: no engine calls beyond Vector3 math. The server feeds it each accepted clashable cast; it answers
-- with the earlier cast to clash with, or keeps the new one pending for a later caster.
-- A cast can only be clashed with while it is still in its wind-up and within the clash window, so a dash
-- that already fired can't be pulled back into a clash.
local ClashRules = {}

-- Attack abilities that can clash, as "<character id>.<slot>". Teleports, guards and information
-- abilities never clash.
ClashRules.CLASHABLE = {
	["Goku.ultimate"] = true, -- Energy Wave
	["Luffy.ultimate"] = true, -- Gatling Barrage
	["Vegeta.ultimate"] = true, -- Big Bang Blast
	["Zoro.ultimate"] = true, -- Tornado Slash
	["Naruto.ultimate"] = true, -- Spiral Sphere
	["Ichigo.mild"] = true, -- Flash Step
	["Ichigo.ultimate"] = true, -- Moon Fang Wave
	["Sasuke.mild"] = true, -- Lightning Dash
}

export type Cast = {
	id: number, -- the caster's user id
	key: string, -- "<character>.<slot>"
	t: number, -- when the server accepted it
	windup: number, -- seconds until it fires
	position: Vector3, -- the caster's root when accepted
	aim: Vector3, -- flat aim direction (unit)
}

export type Params = {
	window: number, -- max seconds between the two casts
	range: number, -- max studs between the casters
	facingDegrees: number, -- each must aim at the other within this cone
}

export type State = {
	pending: { Cast },
	clashing: { [number]: boolean },
}

function ClashRules.new(): State
	return { pending = {}, clashing = {} }
end

function ClashRules.key(character: string, slot: string): string
	return character .. "." .. slot
end

function ClashRules.isClashable(key: string): boolean
	return ClashRules.CLASHABLE[key] == true
end

-- Does a fighter at `from` aiming along `aim` point at `to`, within `degrees` (horizontal only)?
function ClashRules.aimsAt(from: Vector3, aim: Vector3, to: Vector3, degrees: number): boolean
	local offset = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local flat = Vector3.new(aim.X, 0, aim.Z)
	if offset.Magnitude < 1e-3 then
		return true -- standing on top of each other: nothing to face
	end
	if flat.Magnitude < 1e-3 then
		return false
	end
	return flat.Unit:Dot(offset.Unit) >= math.cos(math.rad(degrees))
end

-- Can `earlier` still be clashed with by a cast made at time `t`?
local function open(earlier: Cast, t: number, params: Params): boolean
	local gap = t - earlier.t
	return gap >= 0 and gap <= math.min(params.window, earlier.windup)
end

local function removeFor(state: State, id: number)
	for i = #state.pending, 1, -1 do
		if state.pending[i].id == id then
			table.remove(state.pending, i)
		end
	end
end

-- Offer a newly accepted cast. Returns the earlier cast it clashes with (both leave the pending list), or
-- nil (a clashable cast is then kept pending so a later caster can clash with it).
function ClashRules.offer(state: State, cast: Cast, params: Params): Cast?
	for i = #state.pending, 1, -1 do
		if not open(state.pending[i], cast.t, params) then
			table.remove(state.pending, i)
		end
	end
	removeFor(state, cast.id) -- a fighter has at most one pending cast: their latest
	if not ClashRules.isClashable(cast.key) or state.clashing[cast.id] then
		return nil
	end
	local best: Cast? = nil
	local bestDistance = math.huge
	for _, other in state.pending do
		local distance = (other.position - cast.position).Magnitude
		if
			other.key == cast.key
			and not state.clashing[other.id]
			and distance <= params.range
			and distance < bestDistance
			and ClashRules.aimsAt(cast.position, cast.aim, other.position, params.facingDegrees)
			and ClashRules.aimsAt(other.position, other.aim, cast.position, params.facingDegrees)
		then
			best, bestDistance = other, distance
		end
	end
	if best then
		removeFor(state, best.id)
		return best
	end
	table.insert(state.pending, cast)
	return nil
end

function ClashRules.begin(state: State, a: number, b: number)
	state.clashing[a] = true
	state.clashing[b] = true
	removeFor(state, a)
	removeFor(state, b)
end

function ClashRules.finish(state: State, a: number, b: number)
	state.clashing[a] = nil
	state.clashing[b] = nil
end

function ClashRules.isClashing(state: State, id: number): boolean
	return state.clashing[id] == true
end

-- Where the two stand for the exchange: on the line between them, `distance` apart around the midpoint,
-- each keeping their own height. Returns (standA, standB, axisAtoB).
function ClashRules.stances(a: Vector3, b: Vector3, distance: number): (Vector3, Vector3, Vector3)
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local axis = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local middle = (a + b) / 2
	local standA = Vector3.new(middle.X, a.Y, middle.Z) - axis * (distance / 2)
	local standB = Vector3.new(middle.X, b.Y, middle.Z) + axis * (distance / 2)
	return standA, standB, axis
end

return ClashRules
