-- A damped spring (pure, unit-tested). Placeholder ability poses (AbilityAnim) move every joint toward its
-- target through one of these instead of snapping, which gives the motion ease-in, a little overshoot and
-- settle, and lets heavier joints lag lighter ones (owner request 2026-09-23: "more fluid, less blocky").
--
-- `frequency` is in Hz (how fast it responds), `damping` is the damping ratio: 1 = no overshoot, below 1 =
-- some overshoot. Works on numbers and Vector3s alike. Sub-stepped so the result barely depends on the
-- frame rate.
local Spring = {}

local MAX_STEP = 1 / 120

-- One update over `dt` seconds. Returns the new (position, velocity).
function Spring.step(position: any, velocity: any, target: any, frequency: number, damping: number, dt: number): (any, any)
	if dt <= 0 then
		return position, velocity
	end
	local omega = 2 * math.pi * frequency
	local steps = math.ceil(dt / MAX_STEP)
	local h = dt / steps
	for _ = 1, steps do
		local acceleration = (target - position) * (omega * omega) - velocity * (2 * damping * omega)
		velocity += acceleration * h
		position += velocity * h
	end
	return position, velocity
end

-- The angle equivalent to `target` (degrees) that is nearest to `current`, so a spring never takes the long
-- way round (e.g. from -310 back to 0 it goes to -360, one short hop).
function Spring.nearestAngle(current: number, target: number): number
	return current + ((target - current + 180) % 360 - 180)
end

return Spring
