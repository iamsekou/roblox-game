-- L (approved sheet, docs/ABILITIES.md).
--   Mild  — Surveillance Camera: place a small camera where you stand; for 20 s, opponents within 25
--           studs of it show as direction arrows on your HUD (positions only, never numbers). A new
--           camera replaces the old one.
--   Ult   — Deduction: after a tell, for 3 s every opponent's outline is visible to you through walls;
--           every one of them is warned. Outlines only: characters already replicate to every client,
--           so this reveals nothing the server keeps secret.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)

local SCAN = 0.25 -- seconds between camera scans

local L = {}

local cameraTokens: { [number]: number } = {} -- caster -> the live camera's token

L.mild = {
	prepare = function(ctx)
		local root = ctx.root()
		if not root then
			return nil, "not_alive"
		end
		local tell = Constants.L_CAMERA_TELL
		return {
			castSeconds = tell,
			run = function()
				task.wait(tell)
				local here = ctx.root()
				if not here or not ctx.stillValid() then
					return
				end
				local token = (cameraTokens[ctx.userId] or 0) + 1
				cameraTokens[ctx.userId] = token
				local position = here.Position
				local seconds = Constants.L_CAMERA_SECONDS
				ctx.fx("l_camera", { position = position, duration = seconds, token = token })
				local stop = os.clock() + seconds
				while os.clock() < stop and cameraTokens[ctx.userId] == token and ctx.matchLive() do
					local points = {}
					for _, target in ctx.opponents() do
						if (target.root.Position - position).Magnitude <= Constants.L_CAMERA_RANGE then
							table.insert(points, target.root.Position)
						end
					end
					ctx.effect({ kind = "radar", points = points, untilTime = ctx.now() + SCAN * 2 })
					task.wait(SCAN)
				end
				if cameraTokens[ctx.userId] == token then
					ctx.fx("l_camera_end", { token = token })
				end
			end,
		}
	end,
}

L.ultimate = {
	prepare = function(ctx)
		if not ctx.root() then
			return nil, "not_alive"
		end
		local tell = Constants.L_DEDUCTION_TELL
		return {
			castSeconds = tell,
			run = function()
				ctx.fx("l_deduction_tell", { duration = tell })
				task.wait(tell)
				if not ctx.stillValid() then
					return
				end
				local ids = {}
				for _, target in ctx.opponents() do
					table.insert(ids, target.player.UserId)
					ctx.warn(target.player, "You've been deduced")
				end
				ctx.effect({ kind = "deduction", targets = ids, untilTime = ctx.now() + Constants.L_DEDUCTION_SECONDS })
			end,
		}
	end,
}

return L
