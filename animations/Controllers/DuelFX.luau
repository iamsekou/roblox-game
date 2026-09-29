-- The clash duel as everyone sees it (owner request 2026-09-29): the pair rises inside a force field, a slow
-- punch meets with a shockwave, then a barrage of fists while they type digits; every digit typed lands a blow;
-- the winner's final punch ends it with a blast that blows everything back. Spectators also get a floating
-- score over the force field; the two fighters get their own camera and digits on top of this
-- (Controllers/ClashDuelController, ClashCamera.playDuel). Driven by the server's AbilityFX events
-- clash_duel / clash_tick / clash_duel_end (Systems/ClashDuelService). Client-only visuals.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Constants"))
local AbilityAnim = require(script.Parent:WaitForChild("AbilityAnim"))
local ImpactFX = require(script.Parent:WaitForChild("ImpactFX"))
local CameraShake = require(script.Parent:WaitForChild("CameraShake"))

local DuelFX = {}

local FIELD = Color3.fromRGB(150, 205, 255)
local FIELD_CORE = Color3.fromRGB(235, 245, 255)
local FIST = Color3.fromRGB(255, 238, 210)
local BOLT = Color3.fromRGB(190, 225, 255)
local BLAST = Color3.fromRGB(255, 250, 240)
local UP = Vector3.yAxis

local localPlayer = Players.LocalPlayer
local folder: Folder? = nil

type Active = {
	a: any,
	b: any,
	midpoint: Vector3,
	radius: number,
	field: BasePart,
	shell: BasePart,
	board: BillboardGui?,
	scoreA: number,
	scoreB: number,
	over: boolean,
	connection: RBXScriptConnection?,
}
local active: { [string]: Active } = {} -- "a:b" -> the duel on screen

local function fx(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "NAU_DuelFX"
	f.Parent = workspace
	folder = f
	return f
end

local function part(shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, transparency: number, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = material or Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency
	p.Size = size
	p.CFrame = cframe
	p.Parent = fx()
	return p
end

local function fadeOut(p: Instance, seconds: number, goal: { [string]: any })
	local tween = TweenService:Create(p, TweenInfo.new(seconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), goal)
	tween.Completed:Connect(function()
		p:Destroy()
	end)
	tween:Play()
end

-- A fighter from the event: the model the server sent (bots in Studio tests), else the player's character.
local function modelOf(model: any, id: any): Model?
	if typeof(model) == "Instance" and model:IsA("Model") and model.Parent then
		return model
	end
	local player = if type(id) == "number" then Players:GetPlayerByUserId(id) else nil
	return player and player.Character
end

local function chestOf(model: Model?): Vector3?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position + Vector3.new(0, 0.6, 0) else nil
end

local function keyOf(event: any): string
	return tostring(event.a) .. ":" .. tostring(event.b)
end

-- How long until a server time.
local function untilTime(t: any): number
	return if type(t) == "number" then math.max(0, t - workspace:GetServerTimeNow()) else 0
end

local function near(position: Vector3, radius: number): boolean
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and root:IsA("BasePart") and (root.Position - position).Magnitude <= radius
end

-- A jagged bolt of light between two points.
local function bolt(from: Vector3, to: Vector3)
	local points = { from }
	for i = 1, 3 do
		local p = from:Lerp(to, i / 4) + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 1.2
		table.insert(points, p)
	end
	table.insert(points, to)
	for i = 1, #points - 1 do
		local d = points[i + 1] - points[i]
		if d.Magnitude > 0.05 then
			local seg = part(Enum.PartType.Block, Vector3.new(0.12, 0.12, d.Magnitude), CFrame.lookAt(points[i] + d / 2, points[i + 1]), BOLT, 0)
			fadeOut(seg, 0.12, { Transparency = 1 })
		end
	end
end

-- The floating score spectators see over the force field.
local function scoreBoard(event: any, anchor: BasePart, radius: number): BillboardGui?
	-- The two fighters have their own duel screen; the board is for everyone else.
	if event.a == localPlayer.UserId or event.b == localPlayer.UserId then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "ClashBoard"
	gui.Size = UDim2.fromOffset(260, 64)
	gui.StudsOffsetWorldSpace = Vector3.new(0, radius + 1.5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0.5, 0)
	title.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
	title.TextScaled = true
	title.TextColor3 = FIELD_CORE
	title.TextStrokeTransparency = 0.4
	title.Text = "CLASH!"
	title.Parent = gui
	local score = Instance.new("TextLabel")
	score.Name = "Score"
	score.BackgroundTransparency = 1
	score.Position = UDim2.fromScale(0, 0.5)
	score.Size = UDim2.new(1, 0, 0.5, 0)
	score.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.SemiBold)
	score.TextScaled = true
	score.TextColor3 = Color3.fromRGB(236, 236, 232)
	score.TextStrokeTransparency = 0.4
	local function nameOf(id: any, model: any): string
		local player = if type(id) == "number" then Players:GetPlayerByUserId(id) else nil
		return string.upper(if player then player.DisplayName elseif typeof(model) == "Instance" then model.Name else "?")
	end
	score.Text = string.format("%s  0 — 0  %s", nameOf(event.a, event.aModel), nameOf(event.b, event.bModel))
	score:SetAttribute("Names", nameOf(event.a, event.aModel) .. "|" .. nameOf(event.b, event.bModel))
	score.Parent = gui
	gui.Adornee = anchor
	gui.Parent = anchor
	return gui
end

local function setScore(duel: Active)
	local board = duel.board
	local label = board and board:FindFirstChild("Score")
	if label and label:IsA("TextLabel") then
		local names = string.split(tostring(label:GetAttribute("Names")), "|")
		label.Text = string.format("%s  %d — %d  %s", names[1] or "?", duel.scoreA, duel.scoreB, names[2] or "?")
	end
end

-- Lift, force field, slow punch, then the barrage until the duel ends.
local function onStart(event: any)
	if typeof(event.midpoint) ~= "Vector3" then
		return
	end
	local key = keyOf(event)
	local old = active[key]
	if old then
		old.over = true
	end
	local radius = tonumber(event.radius) or Constants.CLASH_FORCEFIELD_RADIUS
	local mid = event.midpoint
	local floor = mid - UP * (Constants.CLASH_FLOAT_HEIGHT + 3)
	local a, b = modelOf(event.aModel, event.a), modelOf(event.bModel, event.b)

	-- Lift-off: the ground cracks, dust, and the force field swells round the pair.
	ImpactFX.shockwave(floor, UP, radius * 1.4, 0.7)
	ImpactFX.dust(floor, 30)
	local field = part(Enum.PartType.Ball, Vector3.one * 0.5, CFrame.new(mid), FIELD, 0.25, Enum.Material.ForceField)
	local shell = part(Enum.PartType.Ball, Vector3.one * 0.5, CFrame.new(mid), FIELD_CORE, 0.93)
	local lift = TweenInfo.new(Constants.CLASH_LIFT_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(field, lift, { Size = Vector3.one * radius * 2 }):Play()
	TweenService:Create(shell, lift, { Size = Vector3.one * (radius * 2 - 0.4) }):Play()
	local duel: Active = {
		a = event.a,
		b = event.b,
		midpoint = mid,
		radius = radius,
		field = field,
		shell = shell,
		board = scoreBoard(event, field, radius),
		scoreA = 0,
		scoreB = 0,
		over = false,
		connection = nil,
	}
	active[key] = duel
	if near(mid, radius * 3) then
		CameraShake.shake(0.6, 0.5)
	end

	-- The slow punch: both wind up for the whole beat; the fists meet as the barrage begins.
	task.delay(untilTime(event.slowAt), function()
		if duel.over then
			return
		end
		for _, pair in { { event.aModel, event.a }, { event.bModel, event.b } } do
			local model = modelOf(pair[1], pair[2])
			if model then
				AbilityAnim.playMove(model, "Melee", "m1_2", Constants.CLASH_SLOW_PUNCH_SECONDS, 0.1)
			end
		end
	end)
	task.delay(untilTime(event.barrageAt), function()
		if duel.over then
			return
		end
		local ma, mb = modelOf(event.aModel, event.a), modelOf(event.bModel, event.b)
		-- The fists meet: a flash, a ring through the field, the ground below shudders.
		local impact = part(Enum.PartType.Ball, Vector3.one * 1.5, CFrame.new(mid), BLAST, 0.05)
		fadeOut(impact, 0.5, { Size = Vector3.one * radius * 1.6, Transparency = 1 })
		local ca, cb = chestOf(ma), chestOf(mb)
		ImpactFX.shockwave(mid, if ca and cb then cb - ca else UP, radius * 1.8, 0.6)
		ImpactFX.shockwave(floor, UP, radius * 2, 0.8)
		ImpactFX.dust(floor, 24)
		ImpactFX.hitStop({ ma, mb }, 0.18)
		if near(mid, radius * 4) then
			CameraShake.shake(1.2, 0.5)
		end
		-- The barrage: the keyframed fist exchange, looping until the duel ends (the next move replaces it).
		if ma and mb then
			AbilityAnim.playMove(ma, "Melee", "clash", 0, Constants.CLASH_DUEL_MAX_SECONDS + 5, 0)
			local clips = AbilityAnim.clips("Melee", "clash")
			local offset = if clips and clips.release then clips.release.length / 2 else 0.1
			AbilityAnim.playMove(mb, "Melee", "clash", 0, Constants.CLASH_DUEL_MAX_SECONDS + 5, offset)
		end
		local nextFist, nextRing, nextBolt = 0, 0, 0
		duel.connection = RunService.RenderStepped:Connect(function()
			if duel.over then
				if duel.connection then
					duel.connection:Disconnect()
				end
				return
			end
			local pa, pb = chestOf(modelOf(event.aModel, event.a)), chestOf(modelOf(event.bModel, event.b))
			local now = os.clock()
			local pulse = 1 + math.sin(now * 14) * 0.02
			field.Size = Vector3.one * radius * 2 * pulse
			if not pa or not pb then
				return
			end
			if now >= nextFist then
				nextFist = now + 0.035
				for _ = 1, 2 do
					local at = pa:Lerp(pb, 0.3 + math.random() * 0.4) + Vector3.new((math.random() - 0.5) * 2.2, (math.random() - 0.5) * 1.8, (math.random() - 0.5) * 2.2)
					local fist = part(Enum.PartType.Ball, Vector3.one * (0.8 + math.random() * 0.7), CFrame.new(at), FIST, 0.3)
					fadeOut(fist, 0.13, { Size = Vector3.one * 0.3, Transparency = 1 })
				end
			end
			if now >= nextBolt then
				nextBolt = now + 0.09
				bolt((pa + pb) / 2, (pa + pb) / 2 + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit * radius * 0.9)
			end
			if now >= nextRing then
				nextRing = now + 0.45
				ImpactFX.shockwave((pa + pb) / 2, pb - pa, radius * 0.9, 0.35, FIELD_CORE)
			end
		end)
	end)
end

-- A digit typed right: that fighter's blow lands on the other.
local function onTick(event: any)
	local duel = active[keyOf(event)]
	if not duel or duel.over then
		return
	end
	local hitterIsA = event.who == event.a
	if hitterIsA then
		duel.scoreA = tonumber(event.typed) or duel.scoreA + 1
	else
		duel.scoreB = tonumber(event.typed) or duel.scoreB + 1
	end
	setScore(duel)
	local hitter = if hitterIsA then modelOf(event.aModel, event.a) else modelOf(event.bModel, event.b)
	local target = if hitterIsA then modelOf(event.bModel, event.b) else modelOf(event.aModel, event.a)
	local from, to = chestOf(hitter), chestOf(target)
	if from and to then
		local at = to:Lerp(from, 0.3) + Vector3.new(0, math.random() * 0.8, 0)
		local pop = part(Enum.PartType.Ball, Vector3.one * 1.2, CFrame.new(at), BLAST, 0.05)
		fadeOut(pop, 0.22, { Size = Vector3.one * 4, Transparency = 1 })
		ImpactFX.shockwave(at, to - from, 3.5, 0.3)
		ImpactFX.hitStop({ target }, 0.05)
	end
	local pop = TweenService:Create(duel.field, TweenInfo.new(0.08), { Transparency = 0.05 })
	pop.Completed:Connect(function()
		if duel.field.Parent then
			TweenService:Create(duel.field, TweenInfo.new(0.25), { Transparency = 0.25 }):Play()
		end
	end)
	pop:Play()
end

local function shatter(duel: Active, size: number)
	duel.over = true
	if duel.connection then
		duel.connection:Disconnect()
	end
	fadeOut(duel.field, 0.45, { Size = Vector3.one * size, Transparency = 1 })
	fadeOut(duel.shell, 0.3, { Size = Vector3.one * size, Transparency = 1 })
	if duel.board then
		duel.board:Destroy()
	end
end

-- The end: a draw (or an abandoned duel) throws them apart; a win winds up the final punch and blows up.
local function onEnd(event: any)
	local key = keyOf(event)
	local duel = active[key]
	active[key] = nil
	local mid = if typeof(event.midpoint) == "Vector3" then event.midpoint elseif duel then duel.midpoint else nil
	if not mid then
		return
	end
	local radius = if duel then duel.radius else Constants.CLASH_FORCEFIELD_RADIUS
	if event.draw or event.aborted or not event.winner then
		if duel then
			shatter(duel, radius * 2.6)
		end
		ImpactFX.shockwave(mid, UP, radius * 1.5, 0.5)
		for _, pair in { { event.aModel, event.a }, { event.bModel, event.b } } do
			local model = modelOf(pair[1], pair[2])
			if model then
				AbilityAnim.playMove(model, "Melee", "hit", 0)
			end
		end
		return
	end
	local winner, loser = modelOf(event.winnerModel, event.winner), modelOf(event.loserModel, event.loser)
	-- The final punch: the winner winds up the uppercut as the barrage stops.
	if winner then
		AbilityAnim.playMove(winner, "Melee", "m1_4", untilTime(event.finalAt))
	end
	if loser then
		AbilityAnim.playMove(loser, "Melee", "hit", 0)
	end
	if duel then
		duel.over = true
		if duel.connection then
			duel.connection:Disconnect()
		end
		TweenService:Create(duel.field, TweenInfo.new(untilTime(event.finalAt)), { Size = Vector3.one * radius * 1.5, Transparency = 0.12 }):Play()
	end
	task.delay(untilTime(event.finalAt), function()
		-- The blast: the field bursts, a flash as wide as the blow-back, rings through the air and the ground.
		local blastRadius = tonumber(event.radius) or Constants.CLASH_BLAST_RADIUS
		if duel then
			shatter(duel, blastRadius * 1.2)
		end
		local flash = part(Enum.PartType.Ball, Vector3.one * 3, CFrame.new(mid), BLAST, 0)
		fadeOut(flash, 0.7, { Size = Vector3.one * blastRadius * 2, Transparency = 1 })
		local floor = mid - UP * (Constants.CLASH_FLOAT_HEIGHT + 3)
		for i, delay in { 0, 0.12, 0.26 } do
			task.delay(delay, function()
				ImpactFX.shockwave(floor, UP, blastRadius * (0.7 + 0.25 * i), 0.8, if i == 2 then FIELD else nil)
				ImpactFX.shockwave(mid, UP, blastRadius * (0.5 + 0.2 * i), 0.6)
			end)
		end
		ImpactFX.dust(floor, 60)
		for _ = 1, 10 do
			local dir = Vector3.new(math.random() - 0.5, math.random() * 0.6 - 0.1, math.random() - 0.5).Unit
			bolt(mid, mid + dir * blastRadius * 0.6)
		end
		if loser then
			AbilityAnim.playMove(loser, "Melee", "launched", 0)
			ImpactFX.afterimages(loser, 0.6)
		end
		ImpactFX.hitStop({ winner, loser }, 0.2)
		if near(mid, blastRadius * 1.5) then
			CameraShake.shake(2.2, 0.8)
			if event.winner == localPlayer.UserId or event.loser == localPlayer.UserId or near(mid, blastRadius) then
				ImpactFX.impactFrame(Constants.IMPACT_FLASH_SECONDS * 1.5)
			end
		end
	end)
end

function DuelFX.handle(event: any)
	if type(event) ~= "table" then
		return
	end
	if event.kind == "clash_duel" then
		onStart(event)
	elseif event.kind == "clash_tick" then
		onTick(event)
	elseif event.kind == "clash_duel_end" then
		onEnd(event)
	end
end

return DuelFX
