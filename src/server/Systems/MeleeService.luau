-- M1 click combo (owner request 2026-09-25). Clients only *ask* to punch (Remotes.M1); the server owns
-- the combo, the hit and its effects:
--   * a click is checked against Lib/MeleeRules (in a match, alive and active, not clashing, not too soon)
--     and becomes the next punch of a 4-hit combo; every client animates it (AbilityFX "melee");
--   * after the wind-up, the nearest opponent in front of the puncher, in reach and in sight, is hit:
--     a shove and a brief stagger (the 4th punch launches). Punches never eliminate; codes do that;
--   * two fighters landing punches on each other within M1_TRADE_WINDOW is a trade; M1_TRADES_TO_CLASH
--     trades in a row lock them into a fist-exchange clash with the cutscene camera (AbilityService).
-- The punch direction is where the puncher's character faces on the server, never a client-sent aim.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MeleeRules = require(script.Parent.Parent.Lib.MeleeRules)
local RoundManager = require(script.Parent.RoundManager)
local AbilityService = require(script.Parent.AbilityService)

local MeleeService = {}

local CHEST = Vector3.new(0, 1.5, 0)
local PARAMS: MeleeRules.Params = {
	interval = Constants.M1_INTERVAL,
	comboLength = Constants.M1_COMBO_LENGTH,
	comboReset = Constants.M1_COMBO_RESET,
	endlag = Constants.M1_ENDLAG,
	tradeWindow = Constants.M1_TRADE_WINDOW,
	chainGap = Constants.M1_TRADE_CHAIN_GAP,
	tradesToClash = Constants.M1_TRADES_TO_CLASH,
}

local state = MeleeRules.new()

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(player: Player?): BasePart?
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- The live match and this fighter's life id, if they may fight right now (alive, not spawn-protected).
local function fightingLife(player: Player): (any, number?)
	local match = RoundManager.getMatch()
	if not match or match.ended or not match:isActive(player.UserId) then
		return nil, nil
	end
	local p = match.participants[player.UserId]
	return match, p and p.lifeId
end

-- The opponent this punch connects with: nearest active enemy within reach, inside the cone in front of
-- the puncher, with nothing solid in between.
local function findTarget(player: Player, match: any, root: BasePart): (Player?, BasePart?)
	local facing = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if facing.Magnitude < 0.1 then
		return nil, nil
	end
	facing = facing.Unit
	local minDot = math.cos(math.rad(Constants.M1_CONE_DEGREES))
	local best, bestRoot, bestDistance = nil, nil, math.huge
	for id in match.participants do
		if id ~= player.UserId and match:isActive(id) and not match:isTeammate(id, player.UserId) then
			local other = Players:GetPlayerByUserId(id)
			local otherRoot = rootOf(other)
			if other and otherRoot then
				local offset = otherRoot.Position - root.Position
				local flat = Vector3.new(offset.X, 0, offset.Z)
				local distance = offset.Magnitude
				local inCone = flat.Magnitude < 1 or facing:Dot(flat.Unit) >= minDot
				if distance <= Constants.M1_RANGE and distance < bestDistance and inCone
					and AbilityService.lineOfSight(root.Position + CHEST, otherRoot.Position + CHEST)
				then
					best, bestRoot, bestDistance = other, otherRoot, distance
				end
			end
		end
	end
	return best, bestRoot
end

local function land(player: Player, combo: number, match: any, lifeId: number)
	-- Still the same fight and the same life, and not pulled into a clash during the wind-up.
	local liveMatch, liveLife = fightingLife(player)
	if liveMatch ~= match or liveLife ~= lifeId or AbilityService.isClashing(player) then
		return
	end
	local root = rootOf(player)
	if not root then
		return
	end
	local target, targetRoot = findTarget(player, match, root)
	if not target or not targetRoot or AbilityService.isClashing(target) then
		return
	end
	local t = now()
	local flat = Vector3.new(targetRoot.Position.X - root.Position.X, 0, targetRoot.Position.Z - root.Position.Z)
	local away = if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local finisher = combo >= Constants.M1_COMBO_LENGTH
	local traded, chain, clash = MeleeRules.hit(state, player.UserId, target.UserId, t, PARAMS)

	Remotes.AbilityFX:FireAllClients({
		kind = "melee_hit",
		caster = player.UserId,
		target = target.UserId,
		position = targetRoot.Position + CHEST * 0.6 - away * 0.8,
		direction = -away,
		finisher = finisher,
		traded = traded,
	})
	if RunService:IsStudio() then
		print(string.format("[NAU] M1 %s -> %s (hit %d)%s", player.Name, target.Name, combo,
			if traded then string.format(" TRADE %d/%d", chain, Constants.M1_TRADES_TO_CLASH) else ""))
	end

	if clash and AbilityService.meleeClash(player, target) then
		MeleeRules.resetPair(state, player.UserId, target.UserId)
		return -- the clash places them and throws them apart at the end
	end
	if finisher then
		AbilityService.knockback(target, away * Constants.M1_FINISHER_KNOCKBACK + Vector3.new(0, Constants.M1_FINISHER_LAUNCH, 0))
	else
		AbilityService.knockback(target, away * Constants.M1_KNOCKBACK + Vector3.new(0, Constants.M1_KNOCKBACK_LIFT, 0))
	end
	AbilityService.slow(target, Constants.M1_STAGGER_SLOW, Constants.M1_STAGGER_SECONDS)
end

local function onM1(player: Player)
	local match, lifeId = fightingLife(player)
	if not match or not lifeId or AbilityService.isClashing(player) or not rootOf(player) then
		return
	end
	local combo = MeleeRules.swing(state, player.UserId, now(), PARAMS)
	if not combo then
		return
	end
	Remotes.AbilityFX:FireAllClients({
		kind = "melee",
		caster = player.UserId,
		move = "m1_" .. combo,
		castSeconds = Constants.M1_WINDUP,
	})
	task.delay(Constants.M1_WINDUP, land, player, combo, match, lifeId)
end

function MeleeService.Init()
	Remotes.M1.OnServerEvent:Connect(onM1)
	Players.PlayerRemoving:Connect(function(player)
		MeleeRules.forget(state, player.UserId)
	end)
end

return MeleeService
