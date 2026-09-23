-- Abilities on the client: Q / E (or the two on-screen buttons on touch) *request* the equipped
-- character's mild / ultimate from the server, sending the camera's look direction as an aim hint.
-- The HUD shows both slots with their cooldowns. Effects the server sends to this player are applied
-- here: knockbacks and the grapple pull move our own character (Roblox simulates characters on their
-- owner's client), "clear code" and "jammed" go to the code box. While waiting to respawn, a small
-- picker switches the character for the next life (approved: respawn-screen switch).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Constants = require(Shared:WaitForChild("Modules"):WaitForChild("Constants"))
local CharacterDefs = require(Shared:WaitForChild("Modules"):WaitForChild("CharacterDefs"))
local AnimControllers = ReplicatedStorage:WaitForChild("Animations"):WaitForChild("Controllers")
local UIMotion = require(AnimControllers:WaitForChild("UIMotion"))
local AbilityFX = require(AnimControllers:WaitForChild("AbilityFX"))
local AbilityAnim = require(AnimControllers:WaitForChild("AbilityAnim"))
local CameraShake = require(AnimControllers:WaitForChild("CameraShake"))
local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"))
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local SubmissionController = require(script.Parent:WaitForChild("SubmissionController"))
local NumberPlateController = require(script.Parent:WaitForChild("NumberPlateController"))

local AbilityController = {}

local localPlayer = Players.LocalPlayer

local MESSAGES: { [string]: { string } } = {
	no_target = { "No target", "info" },
	nothing_to_grab = { "Nothing in reach to grab", "info" }, -- Stretch Grapple
	no_opponent = { "No opponent in sight where you're aiming", "info" }, -- Hunter's Eye
	no_point = { "Aim at the ground within range", "info" }, -- Big Bang Blast
	no_room = { "No open ground nearby to land on", "info" },
	protected = { "Spawn protection: abilities in a moment", "info" },
	not_available = { "This fighter's abilities are still being built", "info" },
	not_alive = { "You're down", "info" },
	blocked = { "HUNTER'S EYE: your mild is sealed", "bad" },
	clashing = { "You're locked in a clash!", "info" },
}

type Slot = {
	frame: Frame,
	name: TextLabel,
	shade: Frame,
	timer: TextLabel,
	key: TextLabel,
}

local refs: { [string]: any } = { slots = {} }
local isTouch = false
local busy: { [string]: boolean } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function readyAt(slot: string): number
	local info = ClientState.ability[slot]
	return if type(info) == "table" and type(info.readyAt) == "number" then info.readyAt else 0
end

local function inFight(): boolean
	local life = ClientState.life
	return ClientState.isParticipant() and life.inMatch == true and life.alive == true
end

local function request(slot: string)
	if busy[slot] or not inFight() or not ClientState.ability[slot] then
		return
	end
	if now() < readyAt(slot) then
		UIMotion.shake(refs.slots[slot].frame)
		return
	end
	busy[slot] = true
	-- Where we're looking: the camera's direction and position (the server finds the spot at the centre of
	-- the screen from these, and only trusts a camera position near our character).
	local camera = workspace.CurrentCamera
	local aim = if camera then camera.CFrame.LookVector else Vector3.zAxis
	local eye = if camera then camera.CFrame.Position else nil
	local ok, result = pcall(function()
		return Remotes.UseAbility:InvokeServer(slot, aim, eye)
	end)
	busy[slot] = false
	if not ok or type(result) ~= "table" then
		HUDController.toast("Connection hiccup, try again", "bad")
		return
	end
	if result.status == "ok" then
		UIMotion.punch(refs.slots[slot].frame)
	elseif result.status == "cooldown" or result.status == "casting" then
		UIMotion.shake(refs.slots[slot].frame)
	else
		local message = MESSAGES[result.status]
		if message then
			HUDController.toast(message[1], message[2])
		end
	end
end

-- Effects on our own character --------------------------------------------------------------------

local function myRootAndHumanoid(): (BasePart?, Humanoid?)
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if root and root:IsA("BasePart") then root else nil, humanoid
end

local function knockback(velocity: Vector3)
	local root, humanoid = myRootAndHumanoid()
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	-- Airborne, so ground friction and walk control don't swallow the shove.
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	root.AssemblyLinearVelocity = velocity
end

-- Pull toward the server-chosen point at a fixed speed, then let physics take over.
local function grapple(target: Vector3, speed: number)
	local root, humanoid = myRootAndHumanoid()
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	local offset = target - root.Position
	local distance = offset.Magnitude
	if distance < 1 then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local pull = Instance.new("LinearVelocity")
	pull.Attachment0 = attachment
	pull.RelativeTo = Enum.ActuatorRelativeTo.World
	pull.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	pull.MaxForce = math.huge
	pull.VectorVelocity = offset.Unit * speed
	pull.Parent = root
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	-- Home in every frame and stop *on* the point: a timer alone overshoots by a frame's travel (several
	-- studs at dash speeds). A time limit covers anything that blocks the way.
	local deadline = os.clock() + distance / speed + 0.35
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		local toGo = target - root.Position
		local arrived = toGo.Magnitude <= math.max(speed * dt * 1.5, 0.5)
		if arrived or os.clock() > deadline or not root.Parent or humanoid.Health <= 0 then
			connection:Disconnect()
			pull:Destroy()
			attachment:Destroy()
			if root.Parent then
				if arrived then
					root.CFrame = CFrame.new(target) * root.CFrame.Rotation
				end
				root.AssemblyLinearVelocity = offset.Unit * 12 -- arrive gently instead of slamming on
			end
			return
		end
		pull.VectorVelocity = toGo.Unit * speed
	end)
end

-- Solar Flare: the screen whites out, then clears.
local function whiteOut(untilTime: number)
	NumberPlateController.blind(untilTime)
	local seconds = math.max(0.2, untilTime - now())
	refs.flash.BackgroundTransparency = 0
	refs.flash.Visible = true
	local fade = TweenService:Create(refs.flash, TweenInfo.new(seconds, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { BackgroundTransparency = 1 })
	fade.Completed:Connect(function()
		refs.flash.Visible = false
	end)
	fade:Play()
end

-- L's camera: an arrow on a ring around the screen centre for each opponent near the camera.
local function showRadar(points: { Vector3 }, untilTime: number)
	refs.radarUntil = untilTime
	local camera = workspace.CurrentCamera
	local root = myRootAndHumanoid()
	for i, arrow in refs.radarArrows do
		local point = points[i]
		if point and camera and root then
			local offset = camera.CFrame:VectorToObjectSpace(point - root.Position)
			local angle = math.atan2(offset.X, -offset.Z) -- 0 = straight ahead
			arrow.Position = UDim2.new(0.5, math.sin(angle) * 150, 0.5, -math.cos(angle) * 150)
			arrow.Rotation = math.deg(angle)
			arrow.Visible = true
		else
			arrow.Visible = false
		end
	end
end

-- Deduction: every listed opponent's outline shows through walls for us, until untilTime.
local function deduce(targets: { number }, untilTime: number)
	for _, userId in targets do
		local player = Players:GetPlayerByUserId(userId)
		local character = player and player.Character
		if character then
			local outline = Instance.new("Highlight")
			outline.Name = "NAU_Deduction"
			outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			outline.FillTransparency = 1
			outline.OutlineColor = UI.Colors.Gold
			outline.Adornee = character
			outline.Parent = workspace.CurrentCamera -- client-local, so only we see it
			task.delay(math.max(0, untilTime - now()), function()
				outline:Destroy()
			end)
		end
	end
end

-- A clash (owner-approved 2026-09-23): the server has already put us face to face with the opponent and
-- set our walk speed to 0. Here we stop turning and jumping so we stay squared up (and both plates stay
-- readable) until it ends. The server's clash_end (after its throw-apart knockback) releases us; a
-- timer is the safety net if that message is lost.
local clashRelease: (() -> ())? = nil

local function endClash()
	local release = clashRelease
	clashRelease = nil
	if release then
		release()
	end
end

local function beginClash(untilTime: number, face: any)
	endClash()
	local root, humanoid = myRootAndHumanoid()
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	local autoRotate = humanoid.AutoRotate
	humanoid.AutoRotate = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	root.AssemblyLinearVelocity = Vector3.zero
	if typeof(face) == "Vector3" then
		root.CFrame = CFrame.lookAt(root.Position, Vector3.new(face.X, root.Position.Y, face.Z))
	end
	HUDController.toast("CLASH! Press F and type their number!", "good")
	CameraShake.shake(0.5, 0.35)
	clashRelease = function()
		if humanoid.Parent then
			humanoid.AutoRotate = autoRotate
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		end
		CameraShake.shake(0.8, 0.4)
	end
	local release = clashRelease
	task.delay(math.max(0, untilTime - now()) + 1, function()
		if clashRelease == release then
			endClash()
		end
	end)
end

local function onEffect(effect: any)
	if type(effect) ~= "table" then
		return
	end
	if effect.kind == "clash" and type(effect.untilTime) == "number" then
		beginClash(effect.untilTime, effect.face)
		return
	elseif effect.kind == "clash_end" then
		endClash()
		return
	end
	if effect.kind == "blind" and type(effect.untilTime) == "number" then
		whiteOut(effect.untilTime)
		return
	elseif effect.kind == "radar" and type(effect.points) == "table" and type(effect.untilTime) == "number" then
		showRadar(effect.points, effect.untilTime)
		return
	elseif effect.kind == "deduction" and type(effect.targets) == "table" and type(effect.untilTime) == "number" then
		deduce(effect.targets, effect.untilTime)
		HUDController.toast("DEDUCTION: every opponent revealed", "good")
		return
	elseif effect.kind == "warned" and type(effect.text) == "string" then
		HUDController.toast(effect.text, "bad")
		return
	elseif effect.kind == "readGrant" and type(effect.id) == "string" and type(effect.range) == "number" then
		NumberPlateController.addGrant(effect.id, effect.targets, effect.range, effect.untilTime)
		return
	elseif effect.kind == "readGrantEnd" and type(effect.id) == "string" then
		NumberPlateController.removeGrant(effect.id)
		return
	end
	if effect.kind == "knockback" and typeof(effect.velocity) == "Vector3" then
		knockback(effect.velocity)
	elseif effect.kind == "grapple" and typeof(effect.target) == "Vector3" and type(effect.speed) == "number" then
		grapple(effect.target, effect.speed)
	elseif effect.kind == "clearCode" then
		if SubmissionController.clearTyped() then
			HUDController.toast("GATLING BARRAGE: your code was knocked away", "bad")
		end
	elseif effect.kind == "lock" and type(effect.untilTime) == "number" then
		SubmissionController.lockUntil(effect.untilTime)
	end
end

-- HUD --------------------------------------------------------------------------------------------

local function makeSlot(gui: ScreenGui, slot: string, keyText: string, position: UDim2, size: UDim2): Slot
	local frame = UI.panel({
		Name = "Ability_" .. slot,
		AnchorPoint = Vector2.new(1, 1),
		Position = position,
		Size = size,
		Visible = false,
		Parent = gui,
	})
	UI.accentBar(frame, if isTouch then "bottom" else "left", if slot == "ultimate" then UI.Colors.Gold else UI.Colors.Info, 3)
	local key = UI.label({
		Name = "Key",
		Position = if isTouch then UDim2.fromOffset(0, 6) else UDim2.fromOffset(10, 0),
		Size = if isTouch then UDim2.new(1, 0, 0, 26) else UDim2.new(0, 22, 1, 0),
		Font = UI.FontHeavy,
		TextSize = if isTouch then 24 else 20,
		Text = keyText,
		Parent = frame,
	})
	local name = UI.label({
		Name = "AbilityName",
		Position = if isTouch then UDim2.new(0, 4, 1, -30) else UDim2.fromOffset(38, 0),
		Size = if isTouch then UDim2.new(1, -8, 0, 24) else UDim2.new(1, -46, 1, 0),
		Font = UI.Font,
		TextSize = if isTouch then 11 else 14,
		TextScaled = isTouch,
		TextWrapped = isTouch,
		TextXAlignment = if isTouch then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = frame,
	})
	-- Cooldown: a dark shade that drains left to right, plus the seconds left.
	local shade = UI.new("Frame", {
		Name = "Shade",
		Size = UDim2.fromScale(0, 1),
		BorderSizePixel = 0,
		BackgroundColor3 = UI.Colors.Ink,
		BackgroundTransparency = 0.25,
		ZIndex = 3,
		Parent = frame,
	})
	local timer = UI.label({
		Name = "Timer",
		Size = UDim2.fromScale(1, 1),
		Font = UI.FontHeavy,
		TextSize = 20,
		ZIndex = 4,
		Visible = false,
		Parent = frame,
	})
	local slotRef = { frame = frame, name = name, shade = shade, timer = timer, key = key }
	if isTouch then
		local hit = UI.button({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 5,
			Parent = frame,
		})
		hit.Activated:Connect(function()
			task.spawn(request, slot)
		end)
	end
	return slotRef
end

local function refreshSlots()
	local state = ClientState.ability
	local show = inFight() and state.mild ~= nil
	local t = now()
	for slot, ref in refs.slots do
		ref.frame.Visible = show
		if show then
			local info = state[slot]
			local sealed = slot == "mild" and type(state.mildBlockedUntil) == "number" and t < state.mildBlockedUntil
			ref.name.Text = if sealed then "SEALED" else string.upper(info.name or "")
			ref.name.TextColor3 = if sealed then UI.Colors.Bad else UI.Colors.Text
			local left = (info.readyAt or 0) - t
			local total = if slot == "mild" then Constants.MILD_COOLDOWN else Constants.ULTIMATE_COOLDOWN
			local cooling = left > 0
			ref.shade.Size = UDim2.fromScale(if cooling then math.clamp(left / total, 0, 1) else 0, 1)
			ref.timer.Visible = cooling
			ref.timer.Text = if cooling then string.format("%.0f", math.ceil(left)) else ""
			ref.name.TextTransparency = if cooling then 0.5 else 0
		end
	end
end

-- Respawn-screen character switch ----------------------------------------------------------------

-- The server says which characters we own (every one of them in Studio, for testing).
local function ownedCharacters(): { any }
	local list = {}
	local owned = ClientState.ability.owned
	for _, def in CharacterDefs.list do
		if type(owned) == "table" and table.find(owned, def.id) then
			table.insert(list, def)
		end
	end
	return list
end

local function equip(id: string)
	local ok, result = pcall(function()
		return Remotes.EquipCharacter:InvokeServer(id)
	end)
	if not ok or type(result) ~= "table" then
		HUDController.toast("Connection hiccup, try again", "bad")
	elseif result.status == "equipped" then
		local def = CharacterDefs.byId[id]
		HUDController.toast(string.format("Next life: %s", def and def.name or id), "good")
	elseif result.status == "in_fight" then
		HUDController.toast("You can switch in the lobby or while waiting to respawn", "info")
	elseif result.status == "not_owned" then
		HUDController.toast("You don't own that fighter yet", "info")
	end
end

local PICK_CELL = Vector2.new(112, 34)
local PICK_COLUMNS = 5

local function buildPicker()
	local gui = UI.screen("NAU_NextLife", 7, true)
	local holder = UI.new("Frame", {
		Name = "NextLife",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.6, 0),
		Size = UDim2.fromOffset(PICK_COLUMNS * (PICK_CELL.X + 6), 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	UI.label({
		Size = UDim2.new(1, 0, 0, 20),
		Font = UI.Font,
		TextSize = 14,
		TextColor3 = UI.Colors.Muted,
		Text = "NEXT LIFE",
		Parent = holder,
	})
	refs.pickerGrid = UI.new("Frame", {
		Name = "Grid",
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = holder,
	}, {
		UI.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(PICK_CELL.X, PICK_CELL.Y),
			CellPadding = UDim2.fromOffset(6, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	refs.pickerButtons = {}
	refs.pickerKey = ""
	refs.picker = holder
end

-- (Re)builds the buttons whenever the owned list changes.
local function rebuildPickerButtons()
	local owned = ownedCharacters()
	local ids = {}
	for _, def in owned do
		table.insert(ids, def.id)
	end
	local key = table.concat(ids, ",")
	if key == refs.pickerKey then
		return
	end
	refs.pickerKey = key
	for _, bar in refs.pickerButtons do
		bar.Parent:Destroy()
	end
	table.clear(refs.pickerButtons)
	for i, def in owned do
		local button = UI.button({
			Name = def.id,
			LayoutOrder = i,
			BackgroundColor3 = UI.Colors.Panel,
			Font = UI.FontHeavy,
			TextSize = 15,
			Text = string.upper(def.name),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = refs.pickerGrid,
		}, { UI.stroke(Color3.new(1, 1, 1), 1, 0.85) })
		local bar = UI.accentBar(button, "bottom", UI.Colors.Accent, 3)
		button.Activated:Connect(function()
			task.spawn(equip, def.id)
		end)
		refs.pickerButtons[def.id] = bar
	end
end

local function refreshPicker()
	rebuildPickerButtons()
	local life = ClientState.life
	refs.picker.Visible = life.inMatch == true and life.alive == false and life.respawnAt ~= nil
	local equipped = ClientState.ability.equipped
	for id, bar in refs.pickerButtons do
		bar.Visible = id == equipped
	end
end

local function build()
	isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local gui = UI.screen("NAU_Abilities", 5)
	if isTouch then
		-- Two square buttons beside the CODE button (which sits at bottom-right, 200 px up).
		refs.slots.mild = makeSlot(gui, "mild", "Q", UDim2.new(1, -116, 1, -200), UDim2.fromOffset(84, 84))
		refs.slots.ultimate = makeSlot(gui, "ultimate", "E", UDim2.new(1, -24, 1, -292), UDim2.fromOffset(84, 84))
	else
		-- A row to the left of the [F] CODE button: [Q mild] [E ultimate] [F CODE].
		refs.slots.ultimate = makeSlot(gui, "ultimate", "E", UDim2.new(1, -156, 1, -24), UDim2.fromOffset(176, 40))
		refs.slots.mild = makeSlot(gui, "mild", "Q", UDim2.new(1, -340, 1, -24), UDim2.fromOffset(176, 40))
	end
	buildPicker()

	-- Solar Flare white-out and L's radar arrows live on their own full-screen layer.
	local overlay = UI.screen("NAU_AbilityOverlay", 8, true)
	refs.gui = overlay
	refs.flash = UI.new("Frame", {
		Name = "WhiteOut",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 252, 240),
		BorderSizePixel = 0,
		Visible = false,
		Parent = overlay,
	})
	refs.radarArrows = {}
	for i = 1, 11 do
		refs.radarArrows[i] = UI.label({
			Name = "RadarArrow" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(26, 26),
			Font = UI.FontHeavy,
			TextSize = 26,
			TextColor3 = UI.Colors.Gold,
			TextStrokeTransparency = 0.4,
			Text = "^",
			Visible = false,
			Parent = overlay,
		})
	end
	refs.radarUntil = 0
end

function AbilityController.Start()
	build()
	AbilityAnim.start()
	Remotes.AbilityEffect.OnClientEvent:Connect(onEffect)
	Remotes.AbilityFX.OnClientEvent:Connect(function(event)
		if type(event) == "table" and event.kind == "plate_hide" and type(event.target) == "number" and type(event.untilTime) == "number" then
			NumberPlateController.hideTarget(event.target, event.untilTime)
		end
		AbilityAnim.handle(event)
		AbilityFX.play(event)
	end)
	ClientState.Changed:Connect(function()
		refreshPicker()
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Constants.ABILITY_MILD_KEY then
			task.spawn(request, "mild")
		elseif input.KeyCode == Constants.ABILITY_ULTIMATE_KEY then
			task.spawn(request, "ultimate")
		end
	end)
	task.spawn(function()
		while true do
			if now() >= refs.radarUntil then
				for _, arrow in refs.radarArrows do
					arrow.Visible = false
				end
			end
			local ok, err = pcall(refreshSlots)
			if not ok then
				warn("[NAU] ability HUD refresh failed: " .. tostring(err))
				task.wait(1)
			end
			task.wait(0.1)
		end
	end)
	refreshPicker()
end

return AbilityController
