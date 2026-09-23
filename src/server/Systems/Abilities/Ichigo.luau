-- Ichigo (approved sheet, docs/ABILITIES.md).
--   Mild  — Flash Step: a 22-stud dash (stops short of walls); your plate vanishes for its 0.4 s.
--   Ult   — Moon Fang Wave: 1 s charge, then a wide crescent wave sweeps 40 studs forward and leaves a
--           dark trail for 3 s that slows opponents inside it by 40 %.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local AbilityRules = require(script.Parent.Parent.Parent.Lib.AbilityRules)

local TRAIL_TICK = 0.25

local Ichigo = {}

local CHEST = Vector3.new(0, 1.5, 0)

-- Owner, 2026-09-23: Flash Step goes where you look — the spot at the centre of your screen, up to 22 studs.
-- Looking at the ground: land there. Looking at a wall: stop just short of it. Looking up: dash up that way.
Ichigo.mild = {
	prepare = function(ctx)
		if not ctx.root() then
			return nil, "not_alive"
		end
		local target, surface = ctx.lookTarget(Constants.ICHIGO_FLASH_DISTANCE)
		if not target then
			return nil, "no_room"
		end
		local tell = Constants.ICHIGO_FLASH_TELL
		return {
			castSeconds = tell,
			run = function()
				task.wait(tell)
				local root = ctx.root()
				if not root or not ctx.stillValid() then
					return
				end
				local start = root.Position
				local finish: Vector3
				if surface and surface.Normal.Y > 0.6 then
					finish = surface.Position + Vector3.new(0, 3, 0) -- standing on the spot you looked at
				else
					local chest = start + CHEST
					local offset = target - chest
					if offset.Magnitude < 1 then
						return
					end
					local reach = math.min(offset.Magnitude, ctx.clearDistance(chest, offset.Unit, offset.Magnitude)) - 2
					finish = start + offset.Unit * math.max(reach, 0)
				end
				ctx.hidePlate(Constants.ICHIGO_FLASH_HIDE)
				ctx.dashTo(finish, Constants.ICHIGO_FLASH_SPEED)
				ctx.fx("ichigo_flash", { from = start, to = finish })
			end,
		}
	end,
}

Ichigo.ultimate = {
	prepare = function(ctx)
		if not ctx.root() then
			return nil, "not_alive"
		end
		local charge = Constants.ICHIGO_WAVE_CHARGE
		return {
			castSeconds = charge,
			run = function()
				ctx.fx("ichigo_wave_charge", { duration = charge })
				ctx.slow(Constants.ABILITY_CHARGE_SLOW, charge)
				task.wait(charge)
				local root = ctx.root()
				if not root or not ctx.stillValid() then
					return
				end
				local direction = ctx.flatAim()
				local origin = root.Position - Vector3.new(0, 2.5, 0) -- at the feet: the trail lies on the ground
				local length = ctx.clearDistance(root.Position, direction, Constants.ICHIGO_WAVE_LENGTH)
				local halfWidth = Constants.ICHIGO_WAVE_WIDTH / 2
				local seconds = Constants.ICHIGO_TRAIL_SECONDS
				ctx.fx("ichigo_wave", { origin = origin, direction = direction, length = length, width = Constants.ICHIGO_WAVE_WIDTH, trail = seconds })
				local stop = os.clock() + seconds
				while os.clock() < stop and ctx.matchLive() do
					for _, target in ctx.opponents() do
						if AbilityRules.inStrip(origin, direction, length, halfWidth, target.root.Position) then
							ctx.speed(target.player, Constants.ICHIGO_TRAIL_SLOW, TRAIL_TICK + 0.1)
						end
					end
					task.wait(TRAIL_TICK)
				end
			end,
		}
	end,
}

return Ichigo
