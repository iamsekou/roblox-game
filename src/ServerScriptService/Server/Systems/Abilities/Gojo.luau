-- Satoru Gojo (approved sheet, docs/ABILITIES.md).
--   Mild  — Blink: teleport to the point you aim at, within 30 studs (open ground inside the arena only).
--   Ult   — Boundless: a 4 s barrier (10-stud radius) that pushes opponents out and stops projectiles.
--           From activation you can read every opponent's number you can see, at any distance or angle
--           (approved exception, line of sight only). The reading ends after 3 eliminations or 10 s,
--           whichever comes first. Wrong codes still follow the strike rule.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)

local PUSH_TICK = 0.2

local Gojo = {}

Gojo.mild = {
	prepare = function(ctx)
		local root = ctx.root()
		if not root then
			return nil, "not_alive"
		end
		-- Owner, 2026-09-23: Blink goes where you look — the spot at the centre of your screen, up to 30 studs.
		-- Land exactly there if it's open ground; otherwise (a wall, a boulder, thin air) at the farthest open
		-- spot on the line from Gozen toward it. Gozen must be able to see the landing spot.
		local chest = root.Position + Vector3.new(0, 1.5, 0)
		local target, surface = ctx.lookTarget(Constants.GOJO_BLINK_RANGE)
		if not target then
			return nil, "no_room"
		end
		local offset = target - chest
		local heading = if offset.Magnitude > 0.1 then offset.Unit else ctx.flatAim()
		local function visible(spot: CFrame?): CFrame?
			return if spot and ctx.lineOfSight(chest, spot.Position) then spot else nil
		end
		local destination = nil
		if surface and surface.Normal.Y > 0.6 then
			destination = visible(ctx.openSpotAt(surface.Position, heading))
		end
		local d = offset.Magnitude - 2
		while not destination and d >= 4 do
			local probe = chest + heading * d
			local ground = ctx.raycast(probe + Vector3.new(0, 2, 0), Vector3.new(0, -40, 0))
			if ground and ground.Normal.Y > 0.6 then
				destination = visible(ctx.openSpotAt(ground.Position, heading))
			end
			d -= 2
		end
		if not destination then
			return nil, "no_room"
		end
		local tell = Constants.GOJO_BLINK_TELL
		local from = root.Position
		return {
			castSeconds = tell,
			run = function()
				ctx.fx("gojo_blink", { from = from, to = destination.Position, delay = tell })
				task.wait(tell)
				if ctx.stillValid() then
					ctx.teleport(destination)
				end
			end,
		}
	end,
}

Gojo.ultimate = {
	prepare = function(ctx)
		if not ctx.root() then
			return nil, "not_alive"
		end
		local tell = Constants.GOJO_BOUNDLESS_TELL
		return {
			castSeconds = tell,
			run = function()
				ctx.fx("gojo_boundless_tell", { duration = tell })
				task.wait(tell)
				if not ctx.stillValid() then
					return
				end
				-- The reading: every opponent in line of sight, any range, until 3 eliminations or 10 s.
				local endRead = ctx.grantRead(nil, Constants.UNLIMITED_READ_RANGE, Constants.GOJO_READ_SECONDS)
				local eliminations = 0
				local stopListening
				stopListening = ctx.onMyEliminations(function()
					eliminations += 1
					if eliminations >= Constants.GOJO_READ_ELIMINATIONS then
						endRead()
						stopListening()
					end
				end)
				task.delay(Constants.GOJO_READ_SECONDS, stopListening)

				-- The barrier.
				local radius = Constants.GOJO_BARRIER_RADIUS
				local seconds = Constants.GOJO_BARRIER_SECONDS
				ctx.addBarrier(radius, seconds)
				ctx.fx("gojo_boundless", { radius = radius, duration = seconds })
				local stop = os.clock() + seconds
				while os.clock() < stop and ctx.stillValid() do
					local root = ctx.root()
					if root then
						for _, target in ctx.opponents() do
							local offset = target.root.Position - root.Position
							local flat = Vector3.new(offset.X, 0, offset.Z)
							if flat.Magnitude <= radius then
								local outward = if flat.Magnitude > 0.1 then flat.Unit else Vector3.xAxis
								ctx.knockback(target.player, outward * Constants.GOJO_BARRIER_PUSH + Vector3.new(0, 10, 0))
							end
						end
					end
					task.wait(PUSH_TICK)
				end
			end,
		}
	end,
}

return Gojo
