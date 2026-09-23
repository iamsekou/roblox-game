-- Per-observer number plates. Every opponent in the round carries a plate you can always see (owner
-- rule, 2026-09-23), but it stays masked ("••••") until the reading rule holds: you're within
-- reading range (11 studs) AND the front of that fighter faces you. Only then are the digits drawn, and only if the
-- server has disclosed that code to this client (see NumberAssignmentService), so a mask never hides
-- anything the client actually holds. Plates are small and depth-tested, so cover hides them.
--
-- Draw distance is measured from your fighter, never from the camera: BillboardGui.MaxDistance counts
-- from the camera, which sits well behind you in third person and used to cull plates you stood next to.
--
-- Placement rule (animator spec): the plate floats just above the tallest visible point of the avatar
-- (hats, hair and every other accessory included), re-measured continuously.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Constants = require(Shared:WaitForChild("Modules"):WaitForChild("Constants"))
local PlateVisibility = require(Shared:WaitForChild("Modules"):WaitForChild("PlateVisibility"))
local UIMotion = require(ReplicatedStorage:WaitForChild("Animations"):WaitForChild("Controllers"):WaitForChild("UIMotion"))
local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))

local NumberPlateController = {}

local RECONCILE_SECONDS = 0.25
local MASK_TEXT = string.rep("•", Constants.CODE_LENGTH)
local MASK_TEXT_COLOR = Color3.fromRGB(150, 156, 172)
local CODE_TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local RULES: PlateVisibility.PlateRules = {
	drawDistance = Constants.PLATE_BLANK_DRAW_DISTANCE,
	viewDistance = Constants.PLATE_VIEW_DISTANCE,
	coneDegrees = Constants.PLATE_VIEW_CONE_DEGREES,
	hideSlackDistance = Constants.PLATE_HIDE_SLACK_DISTANCE,
	hideSlackDegrees = Constants.PLATE_HIDE_SLACK_DEGREES,
}

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

type Mode = "hidden" | "masked" | "revealed"
type Plate = { gui: BillboardGui, frame: Frame, label: TextLabel, root: BasePart?, humanoid: Humanoid?, mode: Mode }

local codes: { [number]: string } = {} -- target userId -> the code THIS client was shown
local plates: { [number]: Plate } = {} -- one per opponent in the round, whether or not we know their code
local fighting: { [number]: boolean } = {} -- opponents alive and past spawn protection (from RoundState)
local receivedPush = false

-- World-space height of the tallest visible part of the avatar, accessories included.
local function avatarTop(character: Model): number?
	local top: number? = nil
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 1 then
			local cf, size = descendant.CFrame, descendant.Size
			local halfHeight = 0.5
				* (math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z)
			local y = cf.Position.Y + halfHeight
			if top == nil or y > top then
				top = y
			end
		end
	end
	return top
end

local function plateOffset(character: Model, head: BasePart): number
	local top = avatarTop(character) or (head.Position.Y + head.Size.Y / 2)
	local offset = (top - head.Position.Y) + Constants.PLATE_CLEARANCE
	return math.clamp(offset, Constants.PLATE_MIN_OFFSET, Constants.PLATE_MAX_OFFSET)
end

local function createPlate(userId: number): Plate
	local gui = Instance.new("BillboardGui")
	gui.Name = "NAU_Plate_" .. userId
	gui.ResetOnSpawn = false
	gui.AlwaysOnTop = false -- depth-tested: cover genuinely hides the plate
	gui.LightInfluence = 0
	gui.Size = UDim2.fromScale(Constants.PLATE_SIZE.X, Constants.PLATE_SIZE.Y) -- studs: small and physical
	gui.StudsOffsetWorldSpace = Vector3.new(0, Constants.PLATE_MIN_OFFSET, 0)
	gui.Enabled = false

	local frame = Instance.new("Frame")
	frame.Name = "Plate"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(14, 16, 24)
	frame.BackgroundTransparency = 0.15
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.4
	stroke.Thickness = 1
	stroke.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "Code"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -4, 1, -2)
	label.Position = UDim2.fromOffset(2, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = MASK_TEXT_COLOR
	label.TextScaled = true
	label.Text = MASK_TEXT
	label.Parent = frame

	gui.Parent = playerGui
	return { gui = gui, frame = frame, label = label, root = nil, humanoid = nil, mode = "hidden" }
end

-- Every other fighter in the round we're in (teammates included: they show plates too, per DESIGN.md).
local function opponentIds(): { [number]: boolean }
	local ids = {}
	local round = ClientState.round
	if round and ClientState.isParticipant() then
		for _, userId in round.participants or {} do
			if type(userId) == "number" and userId ~= localPlayer.UserId then
				ids[userId] = true
			end
		end
	end
	return ids
end

-- Structural pass: create/destroy plates, re-adorn after respawns, re-measure accessory clearance.
local function reconcile()
	local opponents = opponentIds()

	table.clear(fighting)
	local round = ClientState.round
	for _, entry in (round and round.scores) or {} do
		if type(entry) == "table" and entry.alive == true and entry.protected ~= true then
			fighting[entry.userId] = true
		end
	end

	for userId, plate in plates do
		if not opponents[userId] then
			plate.gui:Destroy()
			plates[userId] = nil
		end
	end
	for userId in opponents do
		local player = Players:GetPlayerByUserId(userId)
		local character = player and player.Character
		local head = character and character:FindFirstChild("Head")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local plate = plates[userId]
		if character and head and head:IsA("BasePart") and root and root:IsA("BasePart") then
			if not plate then
				plate = createPlate(userId)
				plates[userId] = plate
			end
			plate.gui.Adornee = head
			plate.root = root
			plate.humanoid = character:FindFirstChildOfClass("Humanoid")
			plate.gui.StudsOffsetWorldSpace = Vector3.new(0, plateOffset(character, head), 0)
		elseif plate then
			plate.root = nil -- character not loaded or streamed in yet
		end
	end
end

local function setMode(plate: Plate, userId: number, mode: Mode)
	if plate.mode == mode then
		return
	end
	plate.mode = mode
	plate.gui.Enabled = mode ~= "hidden"
	if mode == "revealed" then
		plate.label.Text = codes[userId] or MASK_TEXT
		plate.label.TextColor3 = CODE_TEXT_COLOR
		UIMotion.pop(plate.frame)
	else
		plate.label.Text = MASK_TEXT
		plate.label.TextColor3 = MASK_TEXT_COLOR
	end
end

-- Every frame: nearby opponents show a masked plate; the digits appear only while you're within
-- range and the fighter's front faces you. Spawn-protected fighters (either side) show nothing.
local function updateVisibility()
	local myCharacter = localPlayer.Character
	local myRoot = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")
	local canSee = myRoot ~= nil and ClientState.canSubmit() -- you: in the round, alive, not protected
	for userId, plate in plates do
		local mode: Mode = "hidden"
		local root = plate.root
		local humanoid = plate.humanoid
		if
			canSee
			and root
			and root.Parent
			and fighting[userId]
			and (humanoid == nil or humanoid.Health > 0)
		then
			mode = PlateVisibility.plateMode(
				root.CFrame,
				(myRoot :: BasePart).Position,
				codes[userId] ~= nil,
				plate.mode == "revealed",
				RULES
			)
		end
		setMode(plate, userId, mode)
		local code = codes[userId]
		if mode == "revealed" and code and plate.label.Text ~= code then
			plate.label.Text = code -- code was reissued while it was showing
		end
	end
end

function NumberPlateController.Start()
	Remotes.CodesChanged.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		receivedPush = true
		if payload.reset then
			table.clear(codes)
		end
		for _, change in payload.changes or {} do
			if type(change) == "table" and type(change.target) == "number" then
				if type(change.code) == "string" then
					codes[change.target] = change.code
				else
					codes[change.target] = nil
				end
			end
		end
		reconcile()
	end)

	-- Catch up if this script started mid-round (the pushes are the source of truth after that).
	task.spawn(function()
		local ok, snapshot = pcall(function()
			return Remotes.GetMyCodes:InvokeServer()
		end)
		if ok and type(snapshot) == "table" and not receivedPush then
			for _, entry in snapshot do
				if type(entry) == "table" and type(entry.target) == "number" and type(entry.code) == "string" then
					codes[entry.target] = entry.code
				end
			end
			reconcile()
		end
	end)

	ClientState.Changed:Connect(function(kind)
		if kind == "round" then
			reconcile()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(RECONCILE_SECONDS)
			local ok, err = pcall(reconcile)
			if not ok then
				warn("[NAU] plate reconcile failed: " .. tostring(err))
			end
		end
	end)
	RunService.RenderStepped:Connect(updateVisibility)
end

return NumberPlateController
