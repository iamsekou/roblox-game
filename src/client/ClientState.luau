-- Client-side cache of what the server has told us. Controllers read it and listen to Changed(kind).
-- Nothing here is trusted by the server; it only decides what the UI shows.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Constants"))

local ClientState = {}

ClientState.round = nil :: any -- latest RoundState broadcast
ClientState.life = { alive = true, inMatch = false } :: any -- latest LifeState for this player
ClientState.ability = { equipped = "Goku" } :: any -- latest AbilityState: equipped character, slots, cooldowns
-- latest ProfileState ({ status, settings }). Kept here because a remote event that fires before anyone listens
-- is delivered only to the first listener, and ClientState always connects first.
ClientState.profile = nil :: any
-- latest XpState: { loaded, progress = { [character] = { p, l, x, need, full } }, maxLevel, maxPrestige }. The
-- one-off parts (gain, prestiged) are passed with the "xp" change: ClientState.lastXpEvent.
ClientState.xp = { loaded = false, progress = {}, maxLevel = Constants.XP_MAX_LEVEL, maxPrestige = Constants.XP_MAX_PRESTIGE } :: any
ClientState.lastXpEvent = nil :: any

-- In a clash duel (Controllers/ClashDuelController): number keys type the duel's digits, not codes.
ClientState.dueling = false

local changed = Instance.new("BindableEvent")
ClientState.Changed = changed.Event -- fires with "round", "life", "ability", "profile", "xp" or "duel"

-- A character's progress as the server last reported it ({ p, l, x, need, full }); a fresh start if never played.
function ClientState.xpOf(character: string?): { p: number, l: number, x: number, need: number, full: boolean }
	local entry = character and ClientState.xp.progress[character]
	if type(entry) == "table" then
		return entry
	end
	return { p = 0, l = 1, x = 0, need = Constants.XP_BAR_BASE, full = false }
end

function ClientState.setDueling(on: boolean)
	if ClientState.dueling ~= on then
		ClientState.dueling = on
		changed:Fire("duel")
	end
end

local localPlayer = Players.LocalPlayer

local function applyRound(snapshot: any)
	if type(snapshot) ~= "table" then
		return
	end
	-- An initial GetRoundState reply can arrive after a newer broadcast; keep the newest.
	if ClientState.round and (snapshot.seq or 0) < (ClientState.round.seq or 0) then
		return
	end
	ClientState.round = snapshot
	changed:Fire("round")
end

function ClientState.isParticipant(): boolean
	local r = ClientState.round
	if not r or (r.phase ~= "InRound" and r.phase ~= "RoundEnd") then
		return false
	end
	return table.find(r.participants or {}, localPlayer.UserId) ~= nil
end

-- Team battle: is the current round a team round, and which team is a fighter on (nil in FFA)?
function ClientState.isTeamRound(): boolean
	local r = ClientState.round
	return r ~= nil and r.mode == "Team6v6" and (r.phase == "InRound" or r.phase == "RoundEnd")
end

function ClientState.teamOf(userId: number?): string?
	local r = ClientState.round
	if not ClientState.isTeamRound() or userId == nil then
		return nil
	end
	for _, entry in r.scores or {} do
		if type(entry) == "table" and entry.userId == userId then
			return if type(entry.team) == "string" then entry.team else nil
		end
	end
	return nil
end

function ClientState.myTeam(): string?
	return ClientState.teamOf(localPlayer.UserId)
end

-- A team's colour (Constants.TEAMS), or nil for an unknown team.
function ClientState.teamColor(team: string?): Color3?
	for _, def in Constants.TEAMS do
		if def.name == team then
			return def.color
		end
	end
	return nil
end

-- A fighter's shown name: a player's display name, or a training bot's (the round state lists bots' names).
function ClientState.nameOf(userId: number?): string?
	if type(userId) ~= "number" then
		return nil
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player.DisplayName
	end
	local names = ClientState.round and ClientState.round.names
	return if type(names) == "table" then names[tostring(userId)] else nil
end

-- Training Grounds: this is a training server (workspace attribute set by the server's ServerMode).
function ClientState.isTraining(): boolean
	return workspace:GetAttribute("NAU_Training") == true
end

function ClientState.isQueued(): boolean
	local r = ClientState.round
	return r ~= nil and table.find(r.queued or {}, localPlayer.UserId) ~= nil
end

function ClientState.canSubmit(): boolean
	local r = ClientState.round
	local life = ClientState.life
	return r ~= nil
		and r.phase == "InRound"
		and ClientState.isParticipant()
		and life.alive == true
		and life.inMatch == true
		and life.protectedUntil == nil -- spawn-protected fighters see no plates and can't strike
		and not ClientState.dueling -- a duel's digits aren't codes
end

function ClientState.Start()
	Remotes.RoundState.OnClientEvent:Connect(applyRound)
	Remotes.LifeState.OnClientEvent:Connect(function(life)
		if type(life) ~= "table" then
			return
		end
		ClientState.life = life
		changed:Fire("life")
	end)
	Remotes.ProfileState.OnClientEvent:Connect(function(profile)
		if type(profile) ~= "table" then
			return
		end
		ClientState.profile = profile
		changed:Fire("profile")
	end)
	Remotes.XpState.OnClientEvent:Connect(function(state)
		if type(state) ~= "table" or type(state.progress) ~= "table" then
			return
		end
		ClientState.xp = state
		ClientState.lastXpEvent = { gain = state.gain, prestiged = state.prestiged }
		changed:Fire("xp")
	end)
	Remotes.AbilityState.OnClientEvent:Connect(function(state)
		if type(state) ~= "table" then
			return
		end
		ClientState.ability = state
		changed:Fire("ability")
	end)
	task.spawn(function()
		local ok, snapshot = pcall(function()
			return Remotes.GetRoundState:InvokeServer()
		end)
		if ok then
			applyRound(snapshot)
		end
	end)
end

return ClientState
