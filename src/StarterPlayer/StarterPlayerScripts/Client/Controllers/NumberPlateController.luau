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
--
-- Team battle (owner-approved 2026-09-23): every plate's border takes its fighter's team colour, and teammates
-- also get a small name tag above their plate (arena names are otherwise hidden).
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
local TEAM_STROKE_THICKNESS = 2 -- pixels; the neutral (FFA) border is 1
local TAG_SIZE = Vector2.new(4, 0.55) -- studs: a teammate's name tag
local TAG_GAP = 0.3 -- studs between the plate's top edge and the tag
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
type Plate = {
	gui: BillboardGui,
	frame: Frame,
	label: TextLabel,
	stroke: UIStroke,
	tag: BillboardGui, -- teammate name tag (team battle only)
	tagLabel: TextLabel,
	ally: boolean,
	root: BasePart?,
	humanoid: Humanoid?,
	mode: Mode,
	scale: number,
}

local codes: { [number]: string } = {} -- target userId -> the code THIS client was shown
local plates: { [number]: Plate } = {} -- one per opponent in the round, whether or not we know their code
local fighting: { [number]: boolean } = {} -- opponents alive and past spawn protection (from RoundState)
local receivedPush = false

-- Ability effects on what this client may read (the server enforces the same through its disclosure gate):
local grants: { [string]: PlateVisibility.Grant } = {} -- reading exceptions for us (Krillin / Sasuke / Gojo)
local hiddenUntil: { [number]: number } = {} -- Blur Step: that fighter's plate is gone until then
local blindUntil = -math.huge -- Blinding Burst: we can't read any plate until then

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

	local tag = Instance.new("BillboardGui")
	tag.Name = "NAU_TeamTag_" .. userId
	tag.ResetOnSpawn = false
	tag.AlwaysOnTop = false
	tag.LightInfluence = 0
	tag.Size = UDim2.fromScale(TAG_SIZE.X, TAG_SIZE.Y)
	tag.Enabled = false
	local tagLabel = Instance.new("TextLabel")
	tagLabel.Name = "Name"
	tagLabel.BackgroundTransparency = 1
	tagLabel.Size = UDim2.fromScale(1, 1)
	tagLabel.Font = Enum.Font.GothamBold
	tagLabel.TextScaled = true
	tagLabel.TextStrokeTransparency = 0.4
	tagLabel.Parent = tag

	gui.Parent = playerGui
	tag.Parent = playerGui
	return {
		gui = gui,
		frame = frame,
		label = label,
		stroke = stroke,
		tag = tag,
		tagLabel = tagLabel,
		ally = false,
		root = nil,
		humanoid = nil,
		mode = "hidden",
		scale = 1,
	}
end

-- Team colours: the border shows the fighter's team; a teammate (or a teammate's clone) also gets a name tag.
local function applyTeam(plate: Plate, userId: number, decoy: Model?)
	local owner = if decoy then decoy:GetAttribute("Owner") else userId
	local team = ClientState.teamOf(if type(owner) == "number" then owner else nil)
	local color = ClientState.teamColor(team)
	plate.stroke.Color = color or Color3.fromRGB(255, 255, 255)
	plate.stroke.Transparency = if color then 0 else 0.4
	plate.stroke.Thickness = if color then TEAM_STROKE_THICKNESS else 1
	local myTeam = ClientState.myTeam()
	plate.ally = team ~= nil and team == myTeam
	if plate.ally then
		local player = Players:GetPlayerByUserId(owner :: number)
		plate.tagLabel.Text = string.upper(if player then player.DisplayName else "Ally")
		plate.tagLabel.TextColor3 = color :: Color3
	end
	plate.tag.Enabled = plate.ally and plate.mode ~= "hidden"
end

-- Naruto's Mirror Decoys (server models tagged DecoyId / Owner), except our own.
local function decoyModels(): { [number]: Model }
	local found = {}
	local world = workspace:FindFirstChild("NAUWorld")
	local folder = world and world:FindFirstChild("Decoys")
	for _, model in if folder then folder:GetChildren() else {} do
		local id, owner = model:GetAttribute("DecoyId"), model:GetAttribute("Owner")
		if model:IsA("Model") and type(id) == "number" and owner ~= localPlayer.UserId then
			found[id] = model
		end
	end
	return found
end

-- Every other fighter in the round we're in (teammates included: they show plates too, per DESIGN.md),
-- plus other fighters' clones (their own decoy ids), which carry plates exactly like fighters.
local function opponentIds(decoys: { [number]: Model }): { [number]: boolean }
	local ids = {}
	local round = ClientState.round
	if round and ClientState.isParticipant() then
		for _, userId in round.participants or {} do
			if type(userId) == "number" and userId ~= localPlayer.UserId then
				ids[userId] = true
			end
		end
		for decoyId in decoys do
			ids[decoyId] = true
		end
	end
	return ids
end

-- Structural pass: create/destroy plates, re-adorn after respawns, re-measure accessory clearance.
local function reconcile()
	local decoys = decoyModels()
	local opponents = opponentIds(decoys)

	table.clear(fighting)
	for decoyId in decoys do
		fighting[decoyId] = true
	end
	local round = ClientState.round
	for _, entry in (round and round.scores) or {} do
		if type(entry) == "table" and entry.alive == true and entry.protected ~= true then
			fighting[entry.userId] = true
		end
	end

	for userId, plate in plates do
		if not opponents[userId] then
			plate.gui:Destroy()
			plate.tag:Destroy()
			plates[userId] = nil
		end
	end
	for userId in opponents do
		-- A clone or a fighter. Tell them apart by the clone list, never by the id's sign: Studio's local
		-- test players have negative user ids.
		local player = if decoys[userId] then nil else Players:GetPlayerByUserId(userId)
		local character = decoys[userId] or (player and player.Character)
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
			local offset = plateOffset(character, head)
			plate.gui.StudsOffsetWorldSpace = Vector3.new(0, offset, 0)
			plate.tag.Adornee = head
			plate.tag.StudsOffsetWorldSpace = Vector3.new(0, offset + (Constants.PLATE_SIZE.Y + TAG_SIZE.Y) / 2 + TAG_GAP, 0)
			applyTeam(plate, userId, decoys[userId])
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
	plate.tag.Enabled = plate.ally and mode ~= "hidden"
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
local function granted(userId: number, distance: number, t: number): boolean
	for id, grant in grants do
		if t >= grant.untilTime then
			grants[id] = nil
		elseif PlateVisibility.grantAllows(grant, userId, distance, t) then
			return true
		end
	end
	return false
end

-- Plates read from far away (reading exceptions) grow with distance so the digits stay legible.
local function setScale(plate: Plate, scale: number)
	if math.abs(plate.scale - scale) > 0.05 then
		plate.scale = scale
		plate.gui.Size = UDim2.fromScale(Constants.PLATE_SIZE.X * scale, Constants.PLATE_SIZE.Y * scale)
	end
end

local function updateVisibility()
	local myCharacter = localPlayer.Character
	local myRoot = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")
	local t = workspace:GetServerTimeNow()
	-- You: in the round, alive, not protected, and not whited out by a Blinding Burst.
	local canSee = myRoot ~= nil and ClientState.canSubmit() and t >= blindUntil
	for userId, plate in plates do
		local mode: Mode = "hidden"
		local scale = 1
		local root = plate.root
		local humanoid = plate.humanoid
		local hidden = hiddenUntil[userId] ~= nil and t < hiddenUntil[userId]
		if
			canSee
			and not hidden
			and root
			and root.Parent
			and fighting[userId]
			and (humanoid == nil or humanoid.Health > 0)
		then
			local observer = (myRoot :: BasePart).Position
			local distance = (root.Position - observer).Magnitude
			if granted(userId, distance, t) then
				-- Reading exception: any angle, up to the grant's range (cover still hides the plate).
				mode = if codes[userId] then "revealed" else "masked"
				scale = math.max(1, distance / Constants.PLATE_VIEW_DISTANCE)
			else
				mode = PlateVisibility.plateMode(root.CFrame, observer, codes[userId] ~= nil, plate.mode == "revealed", RULES)
			end
		end
		setScale(plate, scale)
		setMode(plate, userId, mode)
		local code = codes[userId]
		if mode == "revealed" and code and plate.label.Text ~= code then
			plate.label.Text = code -- code was reissued while it was showing
		end
	end
end

-- Ability hooks (called by AbilityController) ----------------------------------------------------

function NumberPlateController.addGrant(id: string, targets: { number }?, range: number, untilTime: number)
	local set: { [number]: boolean }? = nil
	if targets then
		set = {}
		for _, userId in targets do
			(set :: any)[userId] = true
		end
	end
	grants[id] = { targets = set, range = range, untilTime = untilTime }
end

function NumberPlateController.removeGrant(id: string)
	grants[id] = nil
end

function NumberPlateController.hideTarget(userId: number, untilTime: number)
	hiddenUntil[userId] = untilTime
end

function NumberPlateController.blind(untilTime: number)
	blindUntil = math.max(blindUntil, untilTime)
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
