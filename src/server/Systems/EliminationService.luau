-- Handles SubmitCode. The client sends only the characters it typed; the server alone decides which
-- target (if any) that code means *for this observer*, whether it counts, and what happens next.
-- No line-of-sight check on submit: cover hides a number, it doesn't block a remembered one (approved).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local EconomyService = require(script.Parent.EconomyService)
local RoundManager = require(script.Parent.RoundManager)

local EliminationService = {}

-- Hooks for AbilityService: a popped Mirror Decoy (remove its model) and every elimination (Gojo's
-- Boundless ends after 3). Handlers run after the rules have already decided; they never change them.
local clonePoppedHandlers: { (popper: Player, decoyId: number) -> () } = {}
local eliminationHandlers: { (attacker: Player, victimId: number) -> () } = {}

function EliminationService.onClonePopped(handler: (popper: Player, decoyId: number) -> ())
	table.insert(clonePoppedHandlers, handler)
end

function EliminationService.onElimination(handler: (attacker: Player, victimId: number) -> ())
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
		EconomyService.award(player, Constants.YEN_PER_ELIMINATION, "elimination")
		RoundManager.onLifeLost(result.targetId, { cause = "code", attacker = player })
		for _, handler in eliminationHandlers do
			task.spawn(handler, player, result.targetId)
		end
		if result.winner then
			RoundManager.finish(result.winner)
		end
		return {
			status = status,
			targetName = if victim then victim.DisplayName else "a fighter",
			yen = Constants.YEN_PER_ELIMINATION,
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

function EliminationService.Init()
	Remotes.SubmitCode.OnServerInvoke = handleSubmit
end

return EliminationService
