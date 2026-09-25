-- The rules of abilities, independent of Roblox services so they can be unit-tested with plain
-- numbers and vectors (approved sheet: docs/ABILITIES.md). AbilityService turns these answers into
-- effects; nothing in here yields.
--
-- Cooldown rules (approved): mild 8 s, ultimate 20 s, both ready when a fighter first enters a match.
-- After a respawn the mild is ready and the ultimate loses ULTIMATE_RESPAWN_REDUCTION seconds of
-- whatever cooldown it had left. Abilities are off while dead or spawn-protected, and a fighter can't
-- start a second ability while the first is still winding up.
local AbilityRules = {}

export type Slot = "mild" | "ultimate"
export type State = {
	readyAt: { mild: number, ultimate: number },
	castingUntil: number,
}
export type Fighter = { inMatch: boolean, alive: boolean, protected: boolean }

function AbilityRules.isSlot(value: any): boolean
	return value == "mild" or value == "ultimate"
end

function AbilityRules.newState(now: number): State
	return { readyAt = { mild = now, ultimate = now }, castingUntil = -math.huge }
end

-- Can this fighter use `slot` right now? Returns (true) or (false, reason).
-- Reasons, in priority order: not_in_match, not_alive, protected, casting, cooldown.
function AbilityRules.check(state: State, slot: Slot, now: number, fighter: Fighter): (boolean, string?)
	if not fighter.inMatch then
		return false, "not_in_match"
	end
	if not fighter.alive then
		return false, "not_alive"
	end
	if fighter.protected then
		return false, "protected"
	end
	if now < state.castingUntil then
		return false, "casting"
	end
	if now < state.readyAt[slot] then
		return false, "cooldown"
	end
	return true
end

-- The ability fired: its cooldown starts now, and the fighter is busy for `castSeconds` (its wind-up).
function AbilityRules.activate(state: State, slot: Slot, now: number, cooldown: number, castSeconds: number)
	state.readyAt[slot] = now + cooldown
	state.castingUntil = now + castSeconds
end

-- A new life in the same match: the mild is ready, the ultimate loses `reduction` seconds (never below now).
function AbilityRules.onRespawn(state: State, now: number, reduction: number)
	state.readyAt.mild = now
	state.readyAt.ultimate = math.max(now, state.readyAt.ultimate - reduction)
	state.castingUntil = -math.huge
end

-- Hit tests ---------------------------------------------------------------------------------------

-- Is `point` inside a straight beam from `origin` along unit `direction`, `length` long and `radius` thick?
function AbilityRules.inBeam(origin: Vector3, direction: Vector3, length: number, radius: number, point: Vector3): boolean
	local offset = point - origin
	local along = offset:Dot(direction)
	if along < 0 or along > length then
		return false
	end
	local closest = origin + direction * along
	return (point - closest).Magnitude <= radius
end

-- Is `point` inside a flat (top-down) cone from `origin` facing unit `direction`?
-- `halfAngle` is in degrees either side of the direction.
function AbilityRules.inCone(origin: Vector3, direction: Vector3, range: number, halfAngle: number, point: Vector3): boolean
	local offset = Vector3.new(point.X - origin.X, 0, point.Z - origin.Z)
	local distance = offset.Magnitude
	if distance > range then
		return false
	end
	if distance < 0.5 then
		return true -- practically on top of the caster
	end
	local facing = Vector3.new(direction.X, 0, direction.Z)
	if facing.Magnitude < 1e-3 then
		return false
	end
	return facing.Unit:Dot(offset.Unit) >= math.cos(math.rad(halfAngle))
end

-- Is `point` inside a flat strip starting at `origin`, running `length` along unit `direction`,
-- `halfWidth` either side (Ichigo's trail)? Height is ignored.
function AbilityRules.inStrip(origin: Vector3, direction: Vector3, length: number, halfWidth: number, point: Vector3): boolean
	local facing = Vector3.new(direction.X, 0, direction.Z)
	if facing.Magnitude < 1e-3 then
		return false
	end
	facing = facing.Unit
	local offset = Vector3.new(point.X - origin.X, 0, point.Z - origin.Z)
	local along = offset:Dot(facing)
	if along < 0 or along > length then
		return false
	end
	return (offset - facing * along).Magnitude <= halfWidth
end

-- Of `candidates` ({ id, position }), the one closest in angle to `aim` from `origin`, if within
-- `maxDegrees` (Sasuke's Hunter's Eye). Compared top-down: the third-person camera looks *down* at your own
-- character, so its pitch alone would put a level opponent outside a small cone. Distance doesn't matter.
function AbilityRules.pickByAim(origin: Vector3, aim: Vector3, maxDegrees: number, candidates: { { id: number, position: Vector3 } }): number?
	local flatAim = Vector3.new(aim.X, 0, aim.Z)
	if flatAim.Magnitude < 1e-3 then
		return nil
	end
	flatAim = flatAim.Unit
	local best, bestDot = nil, math.cos(math.rad(maxDegrees))
	for _, c in candidates do
		local offset = Vector3.new(c.position.X - origin.X, 0, c.position.Z - origin.Z)
		if offset.Magnitude > 0.5 then
			local dot = offset.Unit:Dot(flatAim)
			if dot >= bestDot then
				best, bestDot = c.id, dot
			end
		end
	end
	return best
end

-- The first of `candidates` a moving body meets along a straight path (Naruto's lunge): inside the
-- beam from `origin` along unit `direction`, nearest along it. Returns (id, distance along) or nil.
function AbilityRules.firstAlong(origin: Vector3, direction: Vector3, length: number, radius: number, candidates: { { id: number, position: Vector3 } }): (number?, number?)
	local best, bestAlong = nil, math.huge
	for _, c in candidates do
		if AbilityRules.inBeam(origin, direction, length, radius, c.position) then
			local along = (c.position - origin):Dot(direction)
			if along < bestAlong then
				best, bestAlong = c.id, along
			end
		end
	end
	return best, if best then bestAlong else nil
end

-- A horizontal unit aim from a client-supplied look vector; `fallback` when it's unusable.
function AbilityRules.flatAim(aim: any, fallback: Vector3): Vector3
	-- Rejects NaN (x ~= x) and infinite or absurd vectors (a client sends a unit look vector).
	if typeof(aim) == "Vector3" and aim.Magnitude == aim.Magnitude and aim.Magnitude < 10 then
		local flat = Vector3.new(aim.X, 0, aim.Z)
		if flat.Magnitude > 0.1 then
			return flat.Unit
		end
	end
	return fallback
end

-- A full 3D unit aim from a client-supplied look vector, or nil when it's unusable.
function AbilityRules.unitAim(aim: any): Vector3?
	if typeof(aim) == "Vector3" and aim.Magnitude == aim.Magnitude and aim.Magnitude > 0.1 and aim.Magnitude < 10 then
		return aim.Unit
	end
	return nil
end

return AbilityRules
