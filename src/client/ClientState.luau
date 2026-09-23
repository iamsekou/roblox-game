-- Client-side cache of what the server has told us. Controllers read it and listen to Changed(kind).
-- Nothing here is trusted by the server; it only decides what the UI shows.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local ClientState = {}

ClientState.round = nil :: any -- latest RoundState broadcast
ClientState.life = { alive = true, inMatch = false } :: any -- latest LifeState for this player

local changed = Instance.new("BindableEvent")
ClientState.Changed = changed.Event -- fires with "round" or "life"

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
