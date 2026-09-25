-- Vegeta (approved sheet, docs/ABILITIES.md).
--   Mild  — Rising Fury: +30 % move speed for 4 s, golden aura.
--   Ult   — Nova Blast: pick a point within 50 studs (where you aim); a ground ring warns for 1 s,
--           then a blast launches every opponent inside and locks their typing for 1.5 s.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)

local Vegeta = {}

Vegeta.mild = {
	prepare = function(ctx)
		if not ctx.root() then
			return nil, "not_alive"
		end
		local tell = Constants.VEGETA_PRIDE_TELL
		return {
			castSeconds = tell,
			run = function()
				ctx.fx("vegeta_pride", { duration = tell + Constants.VEGETA_PRIDE_SECONDS })
				task.wait(tell)
				if ctx.stillValid() then
					ctx.speed(ctx.player, Constants.VEGETA_PRIDE_SPEED, Constants.VEGETA_PRIDE_SECONDS)
				end
			end,
		}
	end,
}

Vegeta.ultimate = {
	prepare = function(ctx)
		local point = ctx.aimPoint(Constants.VEGETA_BLAST_RANGE)
		if not point then
			return nil, "no_point"
		end
		local warn = Constants.VEGETA_BLAST_WARN
		return {
			castSeconds = warn,
			run = function()
				ctx.fx("vegeta_blast_warn", { position = point, radius = Constants.VEGETA_BLAST_RADIUS, duration = warn })
				task.wait(warn)
				if not ctx.stillValid() then
					return
				end
				ctx.fx("vegeta_blast", { position = point, radius = Constants.VEGETA_BLAST_RADIUS })
				for _, target in ctx.opponents() do
					local offset = target.root.Position - point
					if offset.Magnitude <= Constants.VEGETA_BLAST_RADIUS + 2 then -- +2: body, not just the root
						local outward = Vector3.new(offset.X, 0, offset.Z)
						local push = if outward.Magnitude > 0.1 then outward.Unit * 20 else Vector3.zero
						ctx.knockback(target.player, push + Vector3.new(0, Constants.VEGETA_BLAST_LAUNCH, 0))
						ctx.lockInput(target.player, Constants.VEGETA_BLAST_LOCK)
					end
				end
			end,
		}
	end,
}

return Vegeta
