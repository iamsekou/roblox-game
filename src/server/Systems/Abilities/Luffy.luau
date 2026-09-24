-- Monkey D. Luffy (approved sheet, docs/ABILITIES.md).
--   Mild  — Stretch Grapple: aim at a surface up to 45 studs away; after a short tell the arm latches
--           on and Luffy is pulled there. Nothing to grab = nothing happens and no cooldown is spent.
--   Ult   — Gatling Barrage: 1 s wind-up (slowed), then a 1.5 s punch flurry in a 15-stud cone. Every
--           pulse pushes opponents in the cone back; the first time each is hit, their half-typed code
--           is cleared.
-- The server picks the grapple point with its own raycast; the pull itself runs on Luffy's client
-- (characters are client-simulated in Roblox), toward the point the server chose.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local AbilityRules = require(script.Parent.Parent.Parent.Lib.AbilityRules)

local CHEST = Vector3.new(0, 1.5, 0)
local STAND_OFF = 2.5 -- stop this far out from the surface

local Luffy = {}

Luffy.mild = {
	prepare = function(ctx)
		local root = ctx.root()
		local aim = ctx.rawAim
		if not root or not aim then
			return nil, "nothing_to_grab"
		end
		local origin = root.Position + CHEST
		local hit = ctx.raycast(origin, aim * Constants.LUFFY_GRAPPLE_RANGE)
		if not hit then
			return nil, "nothing_to_grab"
		end
		local target = hit.Position + hit.Normal * STAND_OFF
		local tell = Constants.LUFFY_GRAPPLE_TELL
		return {
			castSeconds = tell,
			run = function()
				-- The arm (animations/Controllers/AbilityFX) plants the hand flat on the surface (normal) and
				-- holds on for the pull (speed tells every client how long that takes).
				ctx.fx("luffy_grapple", { target = hit.Position, normal = hit.Normal, delay = tell, speed = Constants.LUFFY_GRAPPLE_SPEED })
				task.wait(tell)
				if ctx.stillValid() then
					ctx.effect({ kind = "grapple", target = target, speed = Constants.LUFFY_GRAPPLE_SPEED })
				end
			end,
		}
	end,
}

Luffy.ultimate = {
	prepare = function(ctx)
		if not ctx.root() then
			return nil, "not_alive"
		end
		local windup, duration = Constants.LUFFY_GATLING_WINDUP, Constants.LUFFY_GATLING_DURATION
		return {
			castSeconds = windup + duration,
			run = function()
				ctx.fx("luffy_gatling", { windup = windup, duration = duration })
				ctx.slow(Constants.ABILITY_CHARGE_SLOW, windup + duration)
				task.wait(windup)
				local cleared: { [Player]: boolean } = {}
				local pulses = Constants.LUFFY_GATLING_PULSES
				for _ = 1, pulses do
					local root = ctx.root()
					if not root or not ctx.stillValid() then
						return
					end
					local direction = ctx.flatAim()
					local origin = root.Position
					for _, target in ctx.opponents() do
						local point = target.root.Position
						if
							AbilityRules.inCone(origin, direction, Constants.LUFFY_GATLING_RANGE, Constants.LUFFY_GATLING_HALF_ANGLE, point)
							and ctx.lineOfSight(origin + CHEST, point + CHEST)
						then
							ctx.knockback(target.player, direction * Constants.LUFFY_GATLING_PUSH + Vector3.new(0, 12, 0))
							if not cleared[target.player] then
								cleared[target.player] = true
								ctx.clearCode(target.player)
							end
						end
					end
					task.wait(duration / pulses)
				end
			end,
		}
	end,
}

return Luffy
