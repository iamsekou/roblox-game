-- Handles SubmitCode. The client sends only the characters it typed; the server alone decides which
-- target (if any) that code means *for this observer*, whether it counts, and what happens next.
-- No line-of-sight check on submit: cover hides a number, it doesn't block a remembered one (approved).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RewardRules = require(script.Parent.Parent.Lib.RewardRules)
local EconomyService = require(script.Parent.EconomyService)
local RoundManager = require(script.Parent.RoundManager)

local EliminationService = {}

-- Hooks for AbilityService: a popped Mirror Decoy (remove its model) and every elimination (Gojo's
-- Boundless ends after 3). Handlers run after the rules have already decided; they never change them.
-- `rewarded`: the elimination paid yen and counts as a leaderboard kill (Lib/RewardRules: eliminating the same
-- victim over and over stops paying for a while, audit fix 2026-09-28). It always counts for the round.
local clonePoppedHandlers: { (popper: Player, decoyId: number) -> () } = {}
local eliminationHandlers: { (attacker: Player, victimId: number, rewarded: boolean) -> () } = {}
local rewards = RewardRules.new()

function EliminationService.onClonePopped(handler: (popper: Player, decoyId: number) -> ())
	table.insert(clonePoppedHandlers, handler)
end

function EliminationService.onElimination(handler: (attacker: Player, victimId: number, rewarded: boolean) -> ())
	table.insert(eliminationHandlers, handler)
end

local function handleSubmit(player: Player, code: any)
	local match = RoundManager.getMatch()
	if not match then
		return { status = "not_in_match" }
	end
	-- MatchCore validates the type/shape of `code`, the observer's state, the debounce and the strike rule,
	-- and never yields, so two simultaneous correct submissions can't both be credited.
	local result = match:submit(player.UserId, code, workspace:GetServerTimeNow())
	local status = result.status
	if RunService:IsStudio() then
		print("[NAU] submit from", player.Name, "->", status)
	end

	if status == "eliminated" then
		local victim = Players:GetPlayerByUserId(result.targetId)
		local rewarded = RewardRules.claim(
			rewards,
			player.UserId,
			result.targetId :: number,
			workspace:GetServerTimeNow(),
			Constants.FARM_WINDOW_SECONDS,
			Constants.FARM_MAX_PAID_PER_PAIR
		)
		if rewarded then
			EconomyService.award(player, Constants.YEN_PER_ELIMINATION, "elimination")
		end
		RoundManager.onLifeLost(result.targetId, { cause = "code", attacker = player })
		for _, handler in eliminationHandlers do
			task.spawn(handler, player, result.targetId, rewarded)
		end
		if result.winner then
			RoundManager.finish(result.winner)
		end
		return {
			status = status,
			targetName = if victim then victim.DisplayName else "a fighter",
			yen = if rewarded then Constants.YEN_PER_ELIMINATION else 0,
		}
	elseif status == "clone" then
		for _, handler in clonePoppedHandlers do
			task.spawn(handler, player, result.targetId)
		end
		return { status = status } -- "It was a decoy!": no strike, no kill
	elseif status == "self_eliminated" then
		RoundManager.onLifeLost(player.UserId, { cause = "strikes" })
		return { status = status, strikesLeft = 0 }
	end
	return { status = status, strikesLeft = result.strikesLeft }
end

-- A clash duel's loser (Systems/ClashDuelService): eliminated and credited to `winner` exactly like a code
-- elimination (score, yen within the farming limit, leaderboard kill, Gojo's count). `winner` nil = nobody to
-- credit. Returns whether anyone was eliminated.
function EliminationService.clashElimination(winner: Player?, loserId: number): boolean
	local match = RoundManager.getMatch()
	if not match then
		return false
	end
	local t = workspace:GetServerTimeNow()
	local done, roundWinner = match:eliminateByClash(if winner then winner.UserId else nil, loserId, t)
	if not done then
		return false
	end
	local rewarded = false
	if winner then
		rewarded = RewardRules.claim(rewards, winner.UserId, loserId, t, Constants.FARM_WINDOW_SECONDS, Constants.FARM_MAX_PAID_PER_PAIR)
		if rewarded then
			EconomyService.award(winner, Constants.YEN_PER_ELIMINATION, "clash")
		end
	end
	RoundManager.onLifeLost(loserId, { cause = "clash", attacker = winner })
	if winner then
		for _, handler in eliminationHandlers do
			task.spawn(handler, winner, loserId, rewarded)
		end
	end
	if roundWinner then
		RoundManager.finish(roundWinner)
	end
	return true
end

function EliminationService.Init()
	Remotes.SubmitCode.OnServerInvoke = handleSubmit
	Players.PlayerRemoving:Connect(function(player)
		RewardRules.forget(rewards, player.UserId)
	end)
end

return EliminationService
