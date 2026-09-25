-- Goku (approved sheet, docs/ABILITIES.md).
--   Mild  — Phase Shift: after a short tell, teleport to a random open spot about 18 studs away.
--   Ult   — Energy Wave: 1.2 s charge (slowed, glowing), then a straight 60-stud beam along your aim that
--           stops at walls. Opponents in it are knocked back and can't type codes for 2 s.
-- Each ability's prepare() runs without yielding and returns a plan; run() does the timed part.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local AbilityRules = require(script.Parent.Parent.Parent.Lib.AbilityRules)

local CHEST = Vector3.new(0, 1.5, 0)

local Goku = {}

Goku.mild = {
	prepare = function(ctx)
		local root = ctx.root()
		if not root then
			return nil, "not_alive"
		end
		local from = root.Position
		local destination = ctx.findSpotNear(from, Constants.GOKU_TRANSMISSION_DISTANCE)
		if not destination then
			return nil, "no_room" -- nowhere open nearby: no cooldown spent
		end
		local tell = Constants.GOKU_TRANSMISSION_TELL
		return {
			castSeconds = tell,
			run = function()
				ctx.fx("goku_transmission", { from = from, to = destination.Position, delay = tell })
				task.wait(tell)
				if ctx.stillValid() then
					ctx.teleport(destination)
				end
			end,
		}
	end,
}

Goku.ultimate = {
	prepare = function(ctx)
		if not ctx.root() then
			return nil, "not_alive"
		end
		local charge = Constants.GOKU_WAVE_CHARGE
		return {
			castSeconds = charge,
			run = function()
				ctx.fx("goku_wave_charge", { duration = charge })
				ctx.slow(Constants.ABILITY_CHARGE_SLOW, charge)
				task.wait(charge)
				local root = ctx.root()
				if not root or not ctx.stillValid() then
					return
				end
				local direction = ctx.flatAim()
				local origin = root.Position + CHEST
				local length = ctx.clearDistance(origin, direction, Constants.GOKU_WAVE_LENGTH)
				ctx.fx("goku_wave_fire", { origin = origin, direction = direction, length = length })
				for _, target in ctx.opponents() do
					if AbilityRules.inBeam(origin, direction, length, Constants.GOKU_WAVE_RADIUS, target.root.Position) then
						ctx.knockback(target.player, direction * Constants.GOKU_WAVE_KNOCKBACK + Vector3.new(0, 25, 0))
						ctx.lockInput(target.player, Constants.GOKU_WAVE_LOCK)
					end
				end
			end,
		}
	end,
}

return Goku
