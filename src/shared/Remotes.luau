-- Single source of truth for every RemoteEvent / RemoteFunction in NAU.
-- The server creates the instances; clients wait for them (a remote created on a client would
-- never reach the server). Payload shapes are documented in docs/DESIGN.md.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Not "Remotes": a stale ModuleScript with that name may still exist in older copies of the place.
local FOLDER_NAME = "NAURemotes"

local DEFINITIONS: { [string]: string } = {
	-- Lobby / round flow
	RequestFight = "RemoteFunction", -- C->S ()                 -> { status }
	LeaveQueue = "RemoteFunction", -- C->S ()                   -> { status }
	GetRoundState = "RemoteFunction", -- C->S ()                -> RoundState
	RoundState = "RemoteEvent", -- S->all RoundState

	-- Number system
	SubmitCode = "RemoteFunction", -- C->S (code: string)       -> { status, strikesLeft?, targetName?, yen? }
	GetMyCodes = "RemoteFunction", -- C->S ()                   -> { { target, code } } (the caller's own view only)
	CodesChanged = "RemoteEvent", -- S->one observer { reset?, changes = { { target, code | false } } }

	-- Life / feed
	LifeState = "RemoteEvent", -- S->one player { alive, inMatch, respawnAt?, cause?, byName? }
	MatchFeed = "RemoteEvent", -- S->all { kind = "eliminated" | "spawned", ... }

	-- Abilities (approved sheet, docs/ABILITIES.md)
	UseAbility = "RemoteFunction", -- C->S (slot: "mild" | "ultimate", aim: Vector3, eye: Vector3) -> { status }
	EquipCharacter = "RemoteFunction", -- C->S (characterId) -> { status, equipped? }
	AbilityState = "RemoteEvent", -- S->one { equipped, character?, mild = { name, readyAt }?, ultimate = {...}? }
	AbilityFX = "RemoteEvent", -- S->all { kind, caster, ... } visuals only; every client draws the tell ("cast" drives animations)
	AbilityEffect = "RemoteEvent", -- S->one { kind = "knockback" | "grapple" | "clearCode" | "lock", ... }

	-- Kill leaderboards (all-time + weekly)
	Leaderboards = "RemoteEvent", -- S->all { serverTime, offline, boards = { AllTime|Weekly = { rows, you, syncedAt, resetAt? } } }
	GetLeaderboards = "RemoteFunction", -- C->S () -> the latest Leaderboards payload (for players who just joined)

	-- Economy (names kept from the original scaffold)
	UpdateCurrency = "RemoteEvent", -- S->one player { yen }
	PurchaseItem = "RemoteFunction", -- C->S (characterId) -> { status = bought|insufficient|owned|not_for_yen|unknown, granted?, price?, yen }
}

local isServer = RunService:IsServer()

local folder: Instance
if isServer then
	folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) or Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

local Remotes: { [string]: any } = {}
for name, className in DEFINITIONS do
	local remote = folder:FindFirstChild(name)
	if isServer then
		if not remote then
			remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
	else
		remote = folder:WaitForChild(name)
	end
	Remotes[name] = remote
end

return Remotes
