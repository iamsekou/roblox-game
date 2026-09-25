-- Sasuke (approved sheet, docs/ABILITIES.md).
--   Mild  — Lightning Dash: a 30-stud dash (stops short of walls) with a crackling trail.
--   Ult   — Hunter's Eye: mark the opponent you can see closest to where you aim (within 15°). For 6 s
--           their plate is readable to you at any distance in line of sight (approved exception), and
--           they can't use their mild ability. The target is warned, and everyone sees the mark.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local AbilityRules = require(script.Parent.Parent.Parent.Lib.AbilityRules)

local EYES = Vector3.new(0, 1.5, 0)

local Sasuke = {}

Sasuke.mild = {
	prepare = function(ctx)
		if not ctx.root() then
			return nil, "not_alive"
		end
		local tell = Constants.SASUKE_DASH_TELL
		return {
			castSeconds = tell,
			run = function()
				ctx.fx("sasuke_dash_tell", { duration = tell })
				task.wait(tell)
				if not ctx.stillValid() then
					return
				end
				local start, finish = ctx.dashForward(Constants.SASUKE_DASH_DISTANCE, Constants.SASUKE_DASH_SPEED)
				if start and finish then
					ctx.fx("sasuke_dash", { from = start, to = finish, speed = Constants.SASUKE_DASH_SPEED })
				end
			end,
		}
	end,
}

Sasuke.ultimate = {
	prepare = function(ctx)
		local root = ctx.root()
		local aim = ctx.rawAim
		if not root or not aim then
			return nil, "no_opponent"
		end
		-- Pick the target now, while the caster is looking at them: visible opponents only.
		local eyes = root.Position + EYES
		local candidates, byId = {}, {}
		for _, target in ctx.opponents() do
			if ctx.lineOfSight(eyes, target.root.Position + EYES) then
				table.insert(candidates, { id = target.player.UserId, position = target.root.Position + EYES })
				byId[target.player.UserId] = target.player
			end
		end
		local pick = AbilityRules.pickByAim(eyes, aim, Constants.SASUKE_EYE_AIM, candidates)
		local target = pick and byId[pick]
		if not target then
			return nil, "no_opponent"
		end
		local tell = Constants.SASUKE_EYE_TELL
		return {
			castSeconds = tell,
			run = function()
				ctx.fx("sasuke_eye_tell", { duration = tell })
				task.wait(tell)
				if not ctx.stillValid() or not ctx.isOpponentActive(target) then
					return
				end
				local seconds = Constants.SASUKE_EYE_SECONDS
				ctx.grantRead({ target }, Constants.UNLIMITED_READ_RANGE, seconds)
				ctx.blockMild(target, seconds)
				ctx.warn(target, string.format("HUNTER'S EYE: %s has marked you", ctx.player.DisplayName))
				ctx.fx("sasuke_mark", { target = target.UserId, duration = seconds })
			end,
		}
	end,
}

return Sasuke
