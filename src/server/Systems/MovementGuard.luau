-- Movement sanity check (owner-approved 2026-09-24). Rules in Lib/MovementRules.
-- Every MOVEMENT_CHECK_INTERVAL the server samples each player's character. Allowed speed is the server's own
-- WalkSpeed (so speed buffs count and a cheater's local WalkSpeed doesn't) with a margin, raised while the game
-- has granted a burst: AbilityService reports every knockback, dash and grapple it sends (expect), and every
-- server teleport or spawn resets the baseline (reset).
-- A move that doesn't fit is undone: the character is put back where it last moved legitimately, and for
-- MOVEMENT_PENALTY_SECONDS it learns no numbers (so teleporting in front of someone to read them gains nothing).
-- Nobody is kicked: a bad network spike can only ever cost a short pull-back.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local MovementRules = require(script.Parent.Parent.Lib.MovementRules)
local NumberAssignmentService = require(script.Parent.NumberAssignmentService)

local MovementGuard = {}

type Grant = { speed: number, rise: number, untilTime: number }
type Entry = {
	character: Model,
	state: MovementRules.State,
	lastGood: CFrame,
	grants: { Grant },
	violations: number,
	graceUntil: number, -- just after a server teleport the client may still report where it was
	-- Accepted positions over the last burst window. The server receives a client's teleport smoothed over a
	-- few samples (measured: a 50-stud hop arrived as ~39 accepted studs and then a flagged step), so a
	-- pull-back goes to the oldest of these, undoing the whole hop rather than just its tail.
	history: { { t: number, cframe: CFrame } },
}

local entries: { [Player]: Entry } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(character: Model?): BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function limitsFor(entry: Entry, t: number): MovementRules.Limits
	local humanoid = entry.character:FindFirstChildOfClass("Humanoid")
	local walk = if humanoid then humanoid.WalkSpeed else Constants.MOVE_SPEED
	return MovementRules.limits(
		walk,
		Constants.MOVEMENT_SPEED_MARGIN,
		Constants.MOVEMENT_RISE_SPEED,
		entry.grants,
		t,
		Constants.MOVEMENT_BURST_SECONDS,
		Constants.MOVEMENT_SLACK
	)
end

local function entryFor(player: Player): Entry?
	local character = player.Character
	local root = rootOf(character)
	if not character or not root then
		return nil
	end
	local entry = entries[player]
	if not entry or entry.character ~= character then
		-- A new character (spawn): start fresh where it stands.
		entry = {
			character = character,
			state = nil :: any,
			lastGood = root.CFrame,
			grants = {},
			violations = 0,
			graceUntil = now() + Constants.MOVEMENT_TELEPORT_GRACE,
			history = { { t = now(), cframe = root.CFrame } },
		}
		entry.state = MovementRules.new(root.Position, now(), limitsFor(entry, now()))
		entries[player] = entry
	end
	return entry
end

-- The server moved this player itself (spawn, teleport ability, clash stance): the new spot is legitimate.
function MovementGuard.reset(player: Player)
	local entry = entryFor(player)
	local root = entry and rootOf(entry.character)
	if entry and root then
		local t = now()
		MovementRules.reset(entry.state, root.Position, t, limitsFor(entry, t))
		entry.lastGood = root.CFrame
		entry.graceUntil = t + Constants.MOVEMENT_TELEPORT_GRACE
		entry.history = { { t = t, cframe = root.CFrame } } -- never pull back across a server teleport
	end
end

-- The game is about to move this player fast (an AbilityEffect payload): allow that speed for as long as it
-- takes. Payloads that don't move anyone are ignored.
function MovementGuard.expect(player: Player, payload: any)
	if type(payload) ~= "table" then
		return
	end
	local entry = entryFor(player)
	if not entry then
		return
	end
	local t = now()
	if payload.kind == "knockback" and typeof(payload.velocity) == "Vector3" then
		local v = payload.velocity :: Vector3
		local flat = Vector3.new(v.X, 0, v.Z).Magnitude
		table.insert(entry.grants, {
			speed = flat,
			rise = math.max(v.Y, 0) + Constants.MOVEMENT_RISE_SPEED,
			untilTime = t + Constants.MOVEMENT_KNOCKBACK_SECONDS,
		})
	elseif payload.kind == "grapple" and typeof(payload.target) == "Vector3" and type(payload.speed) == "number" then
		local root = rootOf(entry.character)
		local distance = if root then (payload.target - root.Position).Magnitude else 50
		table.insert(entry.grants, {
			speed = payload.speed,
			rise = payload.speed,
			untilTime = t + distance / math.max(payload.speed, 1) + Constants.MOVEMENT_GRANT_TAIL,
		})
	end
end

local function pullBack(player: Player, entry: Entry, flat: number, up: number)
	local root = rootOf(entry.character)
	if not root then
		return
	end
	entry.violations += 1
	local back = if entry.history[1] then entry.history[1].cframe else entry.lastGood
	entry.character:PivotTo(back)
	root.AssemblyLinearVelocity = Vector3.zero
	local t = now()
	entry.lastGood = back
	entry.history = { { t = t, cframe = back } }
	MovementRules.reset(entry.state, back.Position, t, limitsFor(entry, t))
	entry.graceUntil = t + Constants.MOVEMENT_TELEPORT_GRACE -- the pull-back is a server teleport too
	NumberAssignmentService.blind(player.UserId, t + Constants.MOVEMENT_PENALTY_SECONDS)
	if RunService:IsStudio() then
		print(string.format("[NAU] movement check: %s pulled back (%.1f studs across, %.1f up in one step; %d so far)", player.Name, flat, up, entry.violations))
	end
end

local function check()
	local t = now()
	for _, player in Players:GetPlayers() do
		local entry = entryFor(player)
		local root = entry and rootOf(entry.character)
		local humanoid = entry and entry.character:FindFirstChildOfClass("Humanoid")
		if entry and root and humanoid and humanoid.Health > 0 then
			for i = #entry.grants, 1, -1 do
				if t >= entry.grants[i].untilTime then
					table.remove(entry.grants, i)
				end
			end
			local ok, flat, up = MovementRules.step(entry.state, root.Position, t, limitsFor(entry, t))
			if ok then
				entry.lastGood = root.CFrame
				table.insert(entry.history, { t = t, cframe = root.CFrame })
				local keep = t - Constants.MOVEMENT_BURST_SECONDS
				while #entry.history > 1 and entry.history[1].t < keep do
					table.remove(entry.history, 1)
				end
			elseif t < entry.graceUntil then
				-- Straight after a server teleport the client may still report where it was: ignore the report
				-- (the baseline stays where the server put the character). A character still out of bounds when
				-- the grace ends is pulled back then.
				continue
			else
				pullBack(player, entry, flat, up)
			end
		end
	end
end

-- Pulls-back so far for this player (Studio tests).
function MovementGuard.violations(player: Player): number
	local entry = entries[player]
	return if entry then entry.violations else 0
end

function MovementGuard.Init()
	Players.PlayerRemoving:Connect(function(player)
		entries[player] = nil
	end)
end

function MovementGuard.Start()
	while true do
		task.wait(Constants.MOVEMENT_CHECK_INTERVAL)
		local ok, err = pcall(check)
		if not ok then
			warn("[NAU] movement check failed: " .. tostring(err))
		end
	end
end

return MovementGuard
