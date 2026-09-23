-- Naruto (approved sheet, docs/ABILITIES.md).
--   Mild  — Shadow Clone: a clone of you runs forward for 4 s with its own fake plate (a unique code in
--           each observer's table). Typing a clone's code pops it: no strike, no kill, "It was a clone!".
--   Ult   — Spiral Sphere: 0.6 s glowing wind-up, then a 20-stud lunge (stops short of walls). The first
--           opponent in the path is launched ~25 studs and can't type codes for 2 s.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local AbilityRules = require(script.Parent.Parent.Parent.Lib.AbilityRules)

local Naruto = {}

Naruto.mild = {
	prepare = function(ctx)
		if not ctx.root() then
			return nil, "not_alive"
		end
		local tell = Constants.NARUTO_CLONE_TELL
		return {
			castSeconds = tell,
			run = function()
				task.wait(tell)
				if ctx.stillValid() then
					ctx.spawnClone(ctx.flatAim(), Constants.NARUTO_CLONE_SPEED, Constants.NARUTO_CLONE_SECONDS)
				end
			end,
		}
	end,
}

Naruto.ultimate = {
	prepare = function(ctx)
		if not ctx.root() then
			return nil, "not_alive"
		end
		local windup = Constants.NARUTO_SPHERE_WINDUP
		return {
			castSeconds = windup,
			run = function()
				ctx.fx("naruto_sphere_charge", { duration = windup })
				ctx.slow(Constants.ABILITY_CHARGE_SLOW, windup)
				task.wait(windup)
				if not ctx.stillValid() then
					return
				end
				local speed = Constants.NARUTO_SPHERE_SPEED
				local start, finish, direction = ctx.dashForward(Constants.NARUTO_SPHERE_LUNGE, speed)
				if not start or not finish or not direction then
					return
				end
				local length = (finish - start).Magnitude
				ctx.fx("naruto_sphere_lunge", { from = start, to = finish, duration = length / speed })
				local candidates, byId = {}, {}
				for _, target in ctx.opponents() do
					table.insert(candidates, { id = target.player.UserId, position = target.root.Position })
					byId[target.player.UserId] = target.player
				end
				local hitId, along = AbilityRules.firstAlong(start, direction, length + 2, Constants.NARUTO_SPHERE_RADIUS, candidates)
				if not hitId then
					return
				end
				task.wait((along or 0) / speed) -- land the hit when the lunge reaches them
				local target = byId[hitId]
				if target and ctx.isOpponentActive(target) and ctx.stillValid() then
					ctx.fx("naruto_sphere_hit", { target = hitId })
					ctx.knockback(target, direction * Constants.NARUTO_SPHERE_LAUNCH + Vector3.new(0, 40, 0))
					ctx.lockInput(target, Constants.NARUTO_SPHERE_LOCK)
				end
			end,
		}
	end,
}

return Naruto
