-- Delivers each observer's personal codes, and only when they could actually read them.
--
-- MatchCore decides every observer's code for every target. This service is the gate between that
-- server-side truth and the client: a code is disclosed to an observer only once the target is
-- within reading range, facing them, and in clear line of sight (PlateVisibility + a raycast). So a
-- modified client learns exactly what a real player could see and nothing more. Once disclosed,
-- a code stays known to that client until it is retired (death, respawn, leaving): remembering a
-- number you really saw is part of the game.
--
-- No global lookup exists anywhere a client can read: every change goes out with FireClient to the
-- single observer it belongs to, and GetMyCodes answers for the caller's own identity.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local PlateVisibility = require(ReplicatedStorage.Shared.Modules.PlateVisibility)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local NumberAssignmentService = {}

local VIEW_DISTANCE = Constants.PLATE_VIEW_DISTANCE + Constants.PLATE_SERVER_SLACK_DISTANCE
local VIEW_CONE = Constants.PLATE_VIEW_CONE_DEGREES + Constants.PLATE_SERVER_SLACK_DEGREES

local attached = false
local assigned: { [number]: { [number]: string } } = {} -- observer -> target -> code (server truth)
local disclosed: { [number]: { [number]: string } } = {} -- observer -> target -> code the client was sent
local pending: { [number]: { { target: number, code: string | boolean } } } = {}
local flushScheduled = false

local function flush()
	flushScheduled = false
	local batch = pending
	pending = {}
	for observerId, changes in batch do
		local observer = Players:GetPlayerByUserId(observerId)
		if observer then
			Remotes.CodesChanged:FireClient(observer, { changes = changes })
		end
	end
end

local function queue(observer: number, target: number, code: string | boolean)
	local list = pending[observer]
	if not list then
		list = {}
		pending[observer] = list
	end
	table.insert(list, { target = target, code = code })
	if not flushScheduled then
		flushScheduled = true
		task.defer(flush)
	end
end

-- Passed to MatchCore as onCodeChange. New codes wait for the visibility gate; retirements are
-- sent straight away so a plate never outlives its code.
function NumberAssignmentService.onCodeChange(observer: number, target: number, code: string?)
	local mine = assigned[observer]
	if not mine then
		mine = {}
		assigned[observer] = mine
	end
	mine[target] = code
	local told = disclosed[observer]
	if told and told[target] and told[target] ~= code then
		told[target] = nil
		queue(observer, target, false)
	end
end

local function rootOf(player: Player?): BasePart?
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Nothing solid between the two heads (other fighters don't block; decorations with CanQuery off don't either).
local function lineOfSight(from: BasePart, to: BasePart): boolean
	local params = RaycastParams.new()
	local characters = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(characters, player.Character)
		end
	end
	params.FilterDescendantsInstances = characters
	params.FilterType = Enum.RaycastFilterType.Exclude
	local origin = from.Position + Vector3.new(0, 1.5, 0)
	local goal = to.Position + Vector3.new(0, 1.5, 0)
	return workspace:Raycast(origin, goal - origin, params) == nil
end

local function discloseVisibleCodes()
	for observerId, targets in assigned do
		local observerRoot = rootOf(Players:GetPlayerByUserId(observerId))
		if observerRoot then
			for targetId, code in targets do
				local told = disclosed[observerId]
				if not told or told[targetId] ~= code then
					local targetRoot = rootOf(Players:GetPlayerByUserId(targetId))
					if
						targetRoot
						and PlateVisibility.canRead(targetRoot.CFrame, observerRoot.Position, VIEW_DISTANCE, VIEW_CONE)
						and lineOfSight(targetRoot, observerRoot)
					then
						if not told then
							told = {}
							disclosed[observerId] = told
						end
						told[targetId] = code
						queue(observerId, targetId, code)
					end
				end
			end
		end
	end
end

function NumberAssignmentService.attach(_match: any)
	attached = true
	table.clear(assigned)
	table.clear(disclosed)
end

-- Round over: forget everything and tell every client to drop all plates.
function NumberAssignmentService.detach()
	attached = false
	table.clear(assigned)
	table.clear(disclosed)
	pending = {}
	for _, player in Players:GetPlayers() do
		Remotes.CodesChanged:FireClient(player, { reset = true, changes = {} })
	end
end

function NumberAssignmentService.Init()
	Remotes.GetMyCodes.OnServerInvoke = function(player: Player)
		local list = {}
		for target, code in disclosed[player.UserId] or {} do
			table.insert(list, { target = target, code = code })
		end
		return list
	end
	Players.PlayerRemoving:Connect(function(player)
		assigned[player.UserId] = nil
		disclosed[player.UserId] = nil
	end)
end

function NumberAssignmentService.Start()
	while true do
		task.wait(Constants.PLATE_DISCLOSE_INTERVAL)
		if attached then
			local ok, err = pcall(discloseVisibleCodes)
			if not ok then
				warn("[NAU] plate disclosure failed: " .. tostring(err))
			end
		end
	end
end

return NumberAssignmentService
