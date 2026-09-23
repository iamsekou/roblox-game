-- Roronoa Zoro (approved sheet, docs/ABILITIES.md).
--   Mild  — Iron Guard: a 2 s stance, immune to ability knockback, drags and locks, projectiles bounce
--           off; you move 50 % slower.
--   Ult   — Tornado Slash: 1 s wind-up, then a tornado travels 40 studs forward (stopping at walls),
--           dragging opponents it touches along with it, bunching them together.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)

local STEP = 0.1

local Zoro = {}

Zoro.mild = {
	prepare = function(ctx)
		if not ctx.root() then
			return nil, "not_alive"
		end
		local tell = Constants.ZORO_GUARD_TELL
		return {
			castSeconds = tell,
			run = function()
				ctx.fx("zoro_guard", { duration = tell + Constants.ZORO_GUARD_SECONDS })
				task.wait(tell)
				if ctx.stillValid() then
					ctx.guard(Constants.ZORO_GUARD_SECONDS)
					ctx.speed(ctx.player, Constants.ZORO_GUARD_SLOW, Constants.ZORO_GUARD_SECONDS)
				end
			end,
		}
	end,
}

Zoro.ultimate = {
	prepare = function(ctx)
		if not ctx.root() then
			return nil, "not_alive"
		end
		local windup = Constants.ZORO_TORNADO_WINDUP
		return {
			castSeconds = windup,
			run = function()
				ctx.fx("zoro_windup", { duration = windup })
				ctx.slow(Constants.ABILITY_CHARGE_SLOW, windup)
				task.wait(windup)
				local root = ctx.root()
				if not root or not ctx.stillValid() then
					return
				end
				local direction = ctx.flatAim()
				local origin = root.Position + direction * 3
				local length = ctx.clearDistance(origin, direction, Constants.ZORO_TORNADO_LENGTH)
				local speed = Constants.ZORO_TORNADO_SPEED
				ctx.fx("zoro_tornado", { origin = origin, direction = direction, length = length, speed = speed })
				local travelled = 0
				while travelled < length and ctx.matchLive() do
					task.wait(STEP)
					travelled = math.min(length, travelled + speed * STEP)
					local center = origin + direction * travelled
					for _, target in ctx.opponents() do
						local offset = center - target.root.Position
						local flat = Vector3.new(offset.X, 0, offset.Z)
						if flat.Magnitude <= Constants.ZORO_TORNADO_RADIUS then
							-- Carried along with the tornado and pulled into its eye.
							local inward = if flat.Magnitude > 0.5 then flat.Unit * math.min(flat.Magnitude * 4, 14) else Vector3.zero
							ctx.knockback(target.player, direction * Constants.ZORO_TORNADO_DRAG + inward + Vector3.new(0, 6, 0))
						end
					end
				end
			end,
		}
	end,
}

return Zoro
