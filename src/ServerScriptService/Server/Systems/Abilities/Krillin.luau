-- Krillin (approved sheet, docs/ABILITIES.md).
--   Mild  — Blinding Burst: 0.4 s tell, then every opponent within 25 studs who is facing Krillin (and can
--           see him) is whited out for 1.5 s: their screen flashes white and they learn no numbers.
--   Ult   — Tracking Disc: after a tell, a slow disc flies 60 studs along the aim (stops at walls and at
--           Gojo's barrier). Opponents it passes are marked for 5 s: Krillin can read their plates out to
--           200 studs, from any angle, in line of sight only (approved exception). Iron Guard deflects it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local PlateVisibility = require(ReplicatedStorage.Shared.Modules.PlateVisibility)

local CHEST = Vector3.new(0, 1.5, 0)
local STEP = 0.05 -- seconds between disc position updates

local Krillin = {}

Krillin.mild = {
	prepare = function(ctx)
		if not ctx.root() then
			return nil, "not_alive"
		end
		local tell = Constants.KRILLIN_FLARE_TELL
		return {
			castSeconds = tell,
			run = function()
				ctx.fx("krillin_flare_tell", { duration = tell })
				task.wait(tell)
				local root = ctx.root()
				if not root or not ctx.stillValid() then
					return
				end
				ctx.fx("krillin_flare", { position = root.Position })
				for _, target in ctx.opponents() do
					-- "Facing Krillin" is the plate rule turned around: Krillin stands in *their* view cone.
					local facing = PlateVisibility.canRead(
						target.root.CFrame,
						root.Position,
						Constants.KRILLIN_FLARE_RANGE,
						Constants.KRILLIN_FLARE_FACING
					)
					if facing and ctx.lineOfSight(root.Position + CHEST, target.root.Position + CHEST) then
						ctx.blind(target.player, Constants.KRILLIN_FLARE_BLIND)
					end
				end
			end,
		}
	end,
}

Krillin.ultimate = {
	prepare = function(ctx)
		if not ctx.root() then
			return nil, "not_alive"
		end
		local tell = Constants.KRILLIN_DISC_TELL
		return {
			castSeconds = tell,
			run = function()
				ctx.fx("krillin_disc_tell", { duration = tell })
				task.wait(tell)
				local root = ctx.root()
				if not root or not ctx.stillValid() then
					return
				end
				local direction = ctx.flatAim()
				local origin = root.Position + CHEST
				local length = ctx.clearDistance(origin, direction, Constants.KRILLIN_DISC_LENGTH)
				local speed = Constants.KRILLIN_DISC_SPEED
				ctx.fx("krillin_disc", { origin = origin, direction = direction, length = length, speed = speed })
				local marked: { [Player]: boolean } = {}
				local travelled = 0
				while travelled < length and ctx.matchLive() do
					task.wait(STEP)
					travelled = math.min(length, travelled + speed * STEP)
					local position = origin + direction * travelled
					if ctx.blockedByBarrier(position) then
						ctx.fx("krillin_disc_stop", { position = position })
						break
					end
					for _, target in ctx.opponents() do
						if
							not marked[target.player]
							and not ctx.isGuarded(target.player) -- Iron Guard: projectiles bounce off
							and (target.root.Position - position).Magnitude <= Constants.KRILLIN_DISC_RADIUS
						then
							marked[target.player] = true
							ctx.grantRead({ target.player }, Constants.KRILLIN_DISC_READ_RANGE, Constants.KRILLIN_DISC_MARK)
							ctx.fx("tracked", { target = target.player.UserId, duration = Constants.KRILLIN_DISC_MARK })
						end
					end
				end
			end,
		}
	end,
}

return Krillin
