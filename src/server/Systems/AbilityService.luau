-- Abilities (approved sheet, docs/ABILITIES.md). Clients only *request* an ability with UseAbility;
-- this service checks the request against AbilityRules (in a match, alive, not spawn-protected, not
-- mid-wind-up, off cooldown, not blocked), then runs the character's ability module, which decides
-- what it hits using the toolkit below. Every effect on another fighter goes through here:
--   * input locks are recorded in MatchCore (the authority on submissions);
--   * reading exceptions, blinding, hidden plates and clones go to NumberAssignmentService's gate;
--   * speed changes are a stack of multipliers per fighter (so a slow and a boost combine cleanly);
--   * knockbacks, pulls and "clear their code" are sent to the affected client, which simulates its
--     own character in Roblox; visuals go to everyone so each tell is visible.
-- Zoro's Iron Guard makes a fighter immune to knockback, drags, locks and projectile marks; Gojo's
-- barrier stops projectiles at its edge; spawn-protected fighters are never valid targets.
--
-- Identity always comes from the invocation. The client's aim vector is only a direction hint:
-- it's normalised, and every range, cone and line-of-sight check is done here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local CharacterDefs = require(ReplicatedStorage.Shared.Modules.CharacterDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local AbilityRules = require(script.Parent.Parent.Lib.AbilityRules)
local ClashRules = require(script.Parent.Parent.Lib.ClashRules)
local MapService = require(script.Parent.MapService)
local RoundManager = require(script.Parent.RoundManager)
local NumberAssignmentService = require(script.Parent.NumberAssignmentService)
local EliminationService = require(script.Parent.EliminationService)
local EconomyService = require(script.Parent.EconomyService)
local MovementGuard = require(script.Parent.MovementGuard)

local AbilityService = {}

-- Every effect sent to one player goes through here, so the movement check (Systems/MovementGuard) hears
-- about each knockback, dash and grapple before the player's client acts on it.
local function sendEffect(target: Player, payload: { [string]: any })
	MovementGuard.expect(target, payload)
	Remotes.AbilityEffect:FireClient(target, payload)
end

local Abilities = script.Parent.Abilities
local IMPLEMENTED: { [string]: any } = {}
for _, def in CharacterDefs.list do
	local module = Abilities:FindFirstChild(def.id)
	if module then
		IMPLEMENTED[def.id] = require(module)
	end
end

local COOLDOWNS = { mild = Constants.MILD_COOLDOWN, ultimate = Constants.ULTIMATE_COOLDOWN }
local CHEST = Vector3.new(0, 1.5, 0)

type Entry = {
	match: any,
	rules: AbilityRules.State,
	lifeId: number,
	character: string, -- the character this life is played as
}

local equipped: { [Player]: string } = {}
local entries: { [Player]: Entry } = {}
local speedMods: { [Player]: { { mult: number, untilTime: number, key: string? } } } = {}
local guardUntil: { [number]: number } = {}
local mildBlockedUntil: { [number]: number } = {}
local lastGuardSpark: { [number]: number } = {} -- Iron Guard block sparks, rate-limited per fighter
local equipListeners: { (Player, string) -> () } = {}
local clashState = ClashRules.new()
local clashCasts: { [number]: any } = {} -- user id -> the context of their latest clashable cast (to cancel it)
local CLASH_PARAMS = {
	window = Constants.CLASH_WINDOW,
	range = Constants.CLASH_RANGE,
	facingDegrees = Constants.CLASH_FACING_DEGREES,
}
local barriers: { { owner: number, root: BasePart, radius: number, untilTime: number } } = {}
local eliminationListeners: { [any]: (attacker: Player, victimId: number) -> () } = {}
local decoyModels: { [number]: Model } = {}
local decoyFolder: Folder? = nil

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(player: Player?): BasePart?
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Everything ability raycasts and spot checks look through: fighters and Naruto's clones. Clones must be
-- excluded explicitly: their Humanoid keeps the torso colliding, and Roblox ignores CanQuery = false on
-- colliding parts (a clone once found its own chest as "the floor" and climbed into the sky).
local function characterModels(): { Instance }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	if decoyFolder and decoyFolder.Parent then
		table.insert(list, decoyFolder)
	end
	return list
end

local function isGuarded(userId: number): boolean
	local g = guardUntil[userId]
	return g ~= nil and now() < g
end

-- Owned = the free starters plus anything bought in the yen shop (Robux arrives with Game Passes, item 6).
-- In Studio everything is unlocked for testing (owner request; live servers ignore this) unless
-- ServerScriptService's NAU_DevUnlockAll attribute is set false, which shows the real inventory.
local function owns(player: Player, def: any): boolean
	if
		Constants.DEV_UNLOCK_ALL_IN_STUDIO
		and RunService:IsStudio()
		and ServerScriptService:GetAttribute(Constants.DEV_UNLOCK_ATTRIBUTE) ~= false
	then
		return true
	end
	return def.tier == "Free" or EconomyService.hasBought(player, def.id)
end

local function ownedList(player: Player): { string }
	local list = {}
	for _, def in CharacterDefs.list do
		if owns(player, def) then
			table.insert(list, def.id)
		end
	end
	return list
end

local function pushState(player: Player)
	local entry = entries[player]
	local payload: { [string]: any } = {
		equipped = equipped[player] or Constants.DEFAULT_CHARACTER,
		owned = ownedList(player),
	}
	local match = RoundManager.getMatch()
	if entry and entry.match == match and match and not match.ended then
		local def = CharacterDefs.byId[entry.character]
		payload.character = entry.character
		payload.implemented = IMPLEMENTED[entry.character] ~= nil
		payload.mild = { name = def and def.abilities.mild or "?", readyAt = entry.rules.readyAt.mild }
		payload.ultimate = { name = def and def.abilities.ultimate or "?", readyAt = entry.rules.readyAt.ultimate }
		payload.mildBlockedUntil = mildBlockedUntil[player.UserId]
	end
	Remotes.AbilityState:FireClient(player, payload)
end

-- Speed: WalkSpeed = base * every active multiplier. Recomputed whenever one starts or ends.
local function applySpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local t = now()
	local mult = 1
	local mods = speedMods[player]
	if mods then
		for i = #mods, 1, -1 do
			if t >= mods[i].untilTime then
				table.remove(mods, i)
			else
				mult *= mods[i].mult
			end
		end
	end
	humanoid.WalkSpeed = Constants.MOVE_SPEED * mult
end

-- Returns a function that ends this modifier early (clashes that finish before their time).
-- `key` marks an effect that re-applies itself while it lasts (Moon Fang's trail ticks every 0.25 s): a
-- modifier with the same key is extended instead of stacked, so a 40 % slow stays 40 % (stacked overlaps
-- measured 64 %).
local function addSpeed(player: Player, mult: number, seconds: number, key: string?): () -> ()
	speedMods[player] = speedMods[player] or {}
	local mod = nil
	if key then
		for _, existing in speedMods[player] do
			if existing.key == key and now() < existing.untilTime then
				mod = existing
				break
			end
		end
	end
	if mod then
		mod.mult = mult
		mod.untilTime = math.max(mod.untilTime, now() + seconds)
	else
		mod = { mult = mult, untilTime = now() + seconds, key = key }
		table.insert(speedMods[player], mod)
	end
	applySpeed(player)
	task.delay(seconds + 0.02, applySpeed, player)
	return function()
		mod.untilTime = now()
		applySpeed(player)
	end
end

-- Is `point` inside someone else's active Infinity barrier?
local function insideForeignBarrier(point: Vector3, ownerId: number): boolean
	local t = now()
	for i = #barriers, 1, -1 do
		local b = barriers[i]
		if t >= b.untilTime or not b.root.Parent then
			table.remove(barriers, i)
		elseif b.owner ~= ownerId and (point - b.root.Position).Magnitude <= b.radius then
			return true
		end
	end
	return false
end

local function removeDecoy(decoyId: number)
	local model = decoyModels[decoyId]
	decoyModels[decoyId] = nil
	NumberAssignmentService.unregisterDecoy(decoyId)
	if model then
		local root = model:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			Remotes.AbilityFX:FireAllClients({ kind = "clone_pop", position = root.Position })
		end
		model:Destroy()
	end
end

-- The toolkit an ability module works with. Everything here is server-side and validated.
local function makeContext(player: Player, entry: Entry, aim: any, eye: any)
	local match = entry.match
	local ctx = {}
	ctx.player = player
	ctx.userId = player.UserId
	ctx.now = now
	ctx.rawAim = AbilityRules.unitAim(aim)
	-- The client's camera position, trusted only if it's actually near the character.
	do
		local root = rootOf(player)
		local ok = typeof(eye) == "Vector3" and eye.Magnitude == eye.Magnitude and root ~= nil
			and (eye - root.Position).Magnitude <= Constants.LOOK_EYE_MAX_OFFSET
		ctx.eye = if ok then eye else nil
	end

	function ctx.root(): BasePart?
		return rootOf(player)
	end

	-- A horizontal aim: the client's camera direction if usable, else where the character faces.
	function ctx.flatAim(): Vector3
		local root = rootOf(player)
		local look = if root then Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z) else Vector3.zAxis
		return AbilityRules.flatAim(aim, if look.Magnitude > 0.1 then look.Unit else Vector3.zAxis)
	end

	-- Still the same life in the same, unfinished match, and not cancelled by a clash (abilities with a
	-- wind-up re-check this).
	ctx.cancelled = false
	function ctx.stillValid(): boolean
		local p = match.participants[player.UserId]
		return not ctx.cancelled
			and RoundManager.getMatch() == match
			and not match.ended
			and p ~= nil
			and p.alive
			and p.lifeId == entry.lifeId
			and rootOf(player) ~= nil
	end

	function ctx.matchLive(): boolean
		return RoundManager.getMatch() == match and not match.ended
	end

	-- Opponents an ability may affect: active (alive, not spawn-protected), not the caster, not teammates.
	-- Studio-only test switch (Constants.DEV_SELF_TARGET_ATTRIBUTE): the caster counts too.
	function ctx.opponents(): { { player: Player, root: BasePart } }
		local list = {}
		local selfTarget = RunService:IsStudio() and ServerScriptService:GetAttribute(Constants.DEV_SELF_TARGET_ATTRIBUTE) == true
		for id in match.participants do
			local isSelf = id == player.UserId
			if (not isSelf or selfTarget) and match:isActive(id) and (isSelf or not match:isTeammate(id, player.UserId)) then
				local other = Players:GetPlayerByUserId(id)
				local root = other and rootOf(other)
				if other and root then
					table.insert(list, { player = other, root = root })
				end
			end
		end
		return list
	end

	function ctx.isOpponentActive(target: Player): boolean
		return match:isActive(target.UserId) and ctx.matchLive()
	end

	-- Raycasts ignore fighters (and clones, whose parts don't take queries).
	function ctx.raycast(origin: Vector3, vector: Vector3): RaycastResult?
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = characterModels()
		params.FilterType = Enum.RaycastFilterType.Exclude
		return workspace:Raycast(origin, vector, params)
	end

	-- Distance along `direction` until solid scenery, capped at `maxDistance`.
	function ctx.clearDistance(origin: Vector3, direction: Vector3, maxDistance: number): number
		local hit = ctx.raycast(origin, direction * maxDistance)
		return if hit then (hit.Position - origin).Magnitude else maxDistance
	end

	function ctx.lineOfSight(from: Vector3, to: Vector3): boolean
		return ctx.raycast(from, to - from) == nil
	end

	-- Where the caster is aiming, up to `range`: the first surface hit along the 3D aim; if the aim
	-- hits nothing, the ground below its end point. nil if there's no ground there.
	function ctx.aimPoint(range: number): (Vector3?, Vector3?)
		local root = rootOf(player)
		local direction = ctx.rawAim or ctx.flatAim()
		if not root then
			return nil, nil
		end
		local origin = root.Position + CHEST
		local hit = ctx.raycast(origin, direction * range)
		if hit then
			return hit.Position, hit.Normal
		end
		local fall = ctx.raycast(origin + direction * range, Vector3.new(0, -40, 0))
		if fall then
			return fall.Position, fall.Normal
		end
		return nil, nil
	end

	-- Where the player is looking (owner: Flash Step and Blink go where you look): the point the ray through
	-- the centre of their screen hits, capped at `range` from their chest. Returns (point, hit) where
	-- `hit` is the surface under the point, or nil if the point was capped in mid-air.
	function ctx.lookTarget(range: number): (Vector3?, RaycastResult?)
		local root = rootOf(player)
		local direction = ctx.rawAim
		if not root or not direction then
			return nil, nil
		end
		local chest = root.Position + CHEST
		local origin = ctx.eye or chest
		local reach = (origin - chest).Magnitude + range
		local hit = ctx.raycast(origin, direction * reach)
		local point = if hit then hit.Position else origin + direction * reach
		local offset = point - chest
		if offset.Magnitude > range then
			return chest + offset.Unit * range, nil -- too far: cap it, in the direction you're looking
		end
		return point, hit
	end

	function ctx.isGuarded(target: Player): boolean
		return isGuarded(target.UserId)
	end

	function ctx.knockback(target: Player, velocity: Vector3)
		if not isGuarded(target.UserId) then
			sendEffect(target, { kind = "knockback", velocity = velocity })
			return
		end
		-- Iron Guard turned it away: everyone sees sparks off the blades. Drags repeat every tick, so this
		-- is rate-limited per guarded fighter.
		local t = now()
		if t - (lastGuardSpark[target.UserId] or -math.huge) >= Constants.GUARD_SPARK_INTERVAL then
			lastGuardSpark[target.UserId] = t
			Remotes.AbilityFX:FireAllClients({ kind = "guard_block", target = target.UserId, direction = velocity })
		end
	end

	-- Records the lock where submissions are judged; tells the target's client so its entry box greys out.
	function ctx.lockInput(target: Player, seconds: number)
		if isGuarded(target.UserId) then
			return
		end
		local t = now()
		if match:lockInput(target.UserId, t, seconds) then
			local p = match.participants[target.UserId]
			sendEffect(target, { kind = "lock", untilTime = p.inputLockedUntil })
		end
	end

	function ctx.clearCode(target: Player)
		sendEffect(target, { kind = "clearCode" })
	end

	-- `key`: for an effect that re-applies itself every tick (see addSpeed); it extends instead of stacking.
	function ctx.speed(target: Player, mult: number, seconds: number, key: string?)
		addSpeed(target, mult, seconds, key)
	end

	function ctx.guard(seconds: number)
		guardUntil[player.UserId] = math.max(guardUntil[player.UserId] or -math.huge, now() + seconds)
	end

	function ctx.blockMild(target: Player, seconds: number)
		mildBlockedUntil[target.UserId] = math.max(mildBlockedUntil[target.UserId] or -math.huge, now() + seconds)
		pushState(target)
	end

	-- Solar Flare: no new numbers for `seconds`, and the target's screen whites out.
	function ctx.blind(target: Player, seconds: number)
		local untilTime = now() + seconds
		NumberAssignmentService.blind(target.UserId, untilTime)
		sendEffect(target, { kind = "blind", untilTime = untilTime })
	end

	-- An approved reading exception for the caster. `targets` nil = every opponent. Returns an end().
	function ctx.grantRead(targets: { Player }?, range: number, seconds: number): () -> ()
		local untilTime = now() + seconds
		local ids: { [number]: boolean }? = nil
		local list: { number }? = nil
		if targets then
			ids, list = {}, {}
			for _, target in targets do
				(ids :: any)[target.UserId] = true
				table.insert(list :: any, target.UserId)
			end
		end
		local grant = NumberAssignmentService.grantRead(player.UserId, ids, range, untilTime)
		local grantId = tostring(grant)
		sendEffect(player, { kind = "readGrant", id = grantId, targets = list, range = range, untilTime = untilTime })
		return function()
			NumberAssignmentService.endGrant(grant)
			sendEffect(player, { kind = "readGrantEnd", id = grantId })
		end
	end

	-- Flash Step: nobody learns this fighter's number, and every client hides their plate, for `seconds`.
	function ctx.hidePlate(seconds: number)
		local untilTime = now() + seconds
		NumberAssignmentService.hide(player.UserId, untilTime)
		Remotes.AbilityFX:FireAllClients({ kind = "plate_hide", target = player.UserId, untilTime = untilTime })
	end

	function ctx.warn(target: Player, text: string)
		sendEffect(target, { kind = "warned", text = text })
	end

	function ctx.effect(payload: { [string]: any })
		sendEffect(player, payload)
	end

	function ctx.effectTo(target: Player, payload: { [string]: any })
		sendEffect(target, payload)
	end

	function ctx.fx(kind: string, data: { [string]: any }?)
		local payload = table.clone(data or {})
		payload.kind = kind
		payload.caster = player.UserId
		Remotes.AbilityFX:FireAllClients(payload)
	end

	function ctx.findSpotNear(center: Vector3, distance: number): CFrame?
		return MapService.findSpotNear(center, distance, characterModels())
	end

	function ctx.openSpotAt(feet: Vector3, heading: Vector3): CFrame?
		return MapService.openSpotAt(feet, characterModels(), heading)
	end

	function ctx.teleport(cframe: CFrame)
		local character = player.Character
		if character then
			character:PivotTo(cframe)
			MovementGuard.reset(player) -- a teleport ability, not a cheat
		end
	end

	-- Moves the caster to `target` at `speed` (their client runs the motion toward the server's point).
	function ctx.dashTo(target: Vector3, speed: number)
		sendEffect(player, { kind = "grapple", target = target, speed = speed })
	end

	-- A dash along the aim, stopping short of walls. Returns (start, end, direction).
	function ctx.dashForward(distance: number, speed: number): (Vector3?, Vector3?, Vector3?)
		local root = rootOf(player)
		if not root then
			return nil, nil, nil
		end
		local direction = ctx.flatAim()
		local start = root.Position
		local reach = math.max(0, ctx.clearDistance(start, direction, distance) - 2)
		local finish = start + direction * reach
		ctx.dashTo(finish, speed)
		return start, finish, direction
	end

	-- Slows the caster while charging.
	function ctx.slow(multiplier: number, seconds: number)
		addSpeed(player, multiplier, seconds)
	end

	-- Gojo's barrier: other fighters' projectiles stop at its edge.
	function ctx.addBarrier(radius: number, seconds: number)
		local root = rootOf(player)
		if root then
			table.insert(barriers, { owner = player.UserId, root = root, radius = radius, untilTime = now() + seconds })
		end
	end

	function ctx.blockedByBarrier(point: Vector3): boolean
		return insideForeignBarrier(point, player.UserId)
	end

	-- Naruto's Shadow Clone: a copy of the caster that runs along `direction` for `seconds` with its own
	-- plate (a unique code per observer). Popped by a correct code, or gone when time runs out.
	function ctx.spawnClone(direction: Vector3, speed: number, seconds: number): boolean
		local character = player.Character
		local root = rootOf(player)
		if not character or not root then
			return false
		end
		local decoyId = match:addDecoy(player.UserId, now())
		if not decoyId then
			return false
		end
		local archivable = character.Archivable
		character.Archivable = true
		local clone = character:Clone()
		character.Archivable = archivable
		if not clone then
			match:removeDecoy(decoyId, now())
			return false
		end
		local runAnimation = nil
		local animate = character:FindFirstChild("Animate")
		local run = animate and animate:FindFirstChild("run")
		local runTrack = run and run:FindFirstChildOfClass("Animation")
		if runTrack then
			runAnimation = runTrack.AnimationId -- the caster's own run cycle, read from their avatar
		end
		for _, d in clone:GetDescendants() do
			if d:IsA("LuaSourceContainer") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false -- never blocks line of sight or ability raycasts
				d.CanTouch = false
			end
		end
		local cloneRoot = clone:FindFirstChild("HumanoidRootPart") :: BasePart
		local humanoid = clone:FindFirstChildOfClass("Humanoid")
		cloneRoot.Anchored = true
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			humanoid.EvaluateStateMachine = false -- a prop, not a fighter: no standing, falling or collision fights
		end
		clone.Name = "ShadowClone"
		clone:SetAttribute("DecoyId", decoyId)
		clone:SetAttribute("Owner", player.UserId)
		local side = direction:Cross(Vector3.yAxis).Unit
		local startPos = root.Position + side * 3
		clone:PivotTo(CFrame.lookAt(startPos, startPos + direction))
		if not decoyFolder or not decoyFolder.Parent then
			local world = workspace:FindFirstChild("NAUWorld") or workspace
			decoyFolder = Instance.new("Folder")
			decoyFolder.Name = "Decoys"
			decoyFolder.Parent = world
		end
		clone.Parent = decoyFolder
		decoyModels[decoyId] = clone
		NumberAssignmentService.registerDecoy(decoyId, cloneRoot)
		if humanoid and runAnimation then
			local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
			local animation = Instance.new("Animation")
			animation.AnimationId = runAnimation
			pcall(function()
				animator:LoadAnimation(animation):Play()
			end)
		end
		ctx.fx("clone_spawn", { position = startPos })

		-- The run: along `direction`, steering round cover (the arena is dense with it) so the clone keeps
		-- running for its whole life, always facing where it's going.
		task.spawn(function()
			local STEER = { 45, -45, 90, -90, 135, -135 }
			local started = os.clock()
			local last = started
			local position = startPos
			local heading = direction
			while decoyModels[decoyId] == clone and clone.Parent do
				local t = os.clock()
				-- Ends on time, at round end, or when the rules dropped it (owner died or left).
				if t - started >= seconds or not ctx.matchLive() or not match.decoys[decoyId] then
					break
				end
				local dt = t - last
				last = t
				if ctx.clearDistance(position, heading, 4) < 4 then
					local best, bestClear = nil, 4
					for _, degrees in STEER do
						local turned = CFrame.Angles(0, math.rad(degrees), 0):VectorToWorldSpace(heading)
						local clear = ctx.clearDistance(position, turned, 12)
						if clear > bestClear then
							best, bestClear = turned, clear
						end
					end
					heading = best or heading
				end
				if ctx.clearDistance(position, heading, 2) >= 2 then
					position += heading * speed * dt
				end
				-- Keep the clone on the ground as it runs over bumps.
				local ground = ctx.raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0))
				if ground then
					position = Vector3.new(position.X, ground.Position.Y + 3, position.Z)
				end
				clone:PivotTo(CFrame.lookAt(position, position + heading))
				task.wait()
			end
			if decoyModels[decoyId] == clone then
				match:removeDecoy(decoyId, now())
				removeDecoy(decoyId)
			end
		end)
		return true
	end

	-- Calls `handler(victimId)` for each elimination this caster makes until the returned stop() runs.
	function ctx.onMyEliminations(handler: (victimId: number) -> ()): () -> ()
		local key = {}
		eliminationListeners[key] = function(attacker: Player, victimId: number)
			if attacker == player then
				handler(victimId)
			end
		end
		return function()
			eliminationListeners[key] = nil
		end
	end

	return ctx
end

-- Clashes (owner-approved 2026-09-23; rules in Lib/ClashRules) --------------------------------------

-- The fighter's current life id while alive in the current match, else nil.
local function lifeOf(player: Player): number?
	local match = RoundManager.getMatch()
	local p = match and not match.ended and match.participants[player.UserId]
	return if p and p.alive then p.lifeId else nil
end

-- Lock `a` and `b` into a clash over `key` (the ability `character`.`slot`). `ctxB` is b's context, used for
-- the line-of-sight check. Returns false (nothing changed) if the pair can't clash right now.
local function startClash(a: Player, b: Player, character: string, slot: string, ctxB: any): boolean
	local rootA, rootB = rootOf(a), rootOf(b)
	local lifeA, lifeB = lifeOf(a), lifeOf(b)
	if not rootA or not rootB or not lifeA or not lifeB or not a.Character or not b.Character then
		return false
	end
	if not ctxB.lineOfSight(rootB.Position + CHEST, rootA.Position + CHEST) then
		return false -- facing each other through a wall isn't a clash
	end
	ClashRules.begin(clashState, a.UserId, b.UserId)
	for _, id in { a.UserId, b.UserId } do
		local pending = clashCasts[id]
		if pending then
			pending.cancelled = true -- its wind-up re-check stops it from firing
		end
		clashCasts[id] = nil
	end

	-- Face to face, inside reading range, rooted in place.
	local standA, standB, axis = ClashRules.stances(rootA.Position, rootB.Position, Constants.CLASH_DISTANCE)
	a.Character:PivotTo(CFrame.lookAt(standA, Vector3.new(standB.X, standA.Y, standB.Z)))
	b.Character:PivotTo(CFrame.lookAt(standB, Vector3.new(standA.X, standB.Y, standA.Z)))
	MovementGuard.reset(a)
	MovementGuard.reset(b)
	local seconds = Constants.CLASH_SECONDS
	local freeA = addSpeed(a, 0, seconds)
	local freeB = addSpeed(b, 0, seconds)
	local untilTime = now() + seconds
	sendEffect(a, { kind = "clash", untilTime = untilTime, face = standB, partner = b.UserId })
	sendEffect(b, { kind = "clash", untilTime = untilTime, face = standA, partner = a.UserId })
	local midpoint = (standA + standB) / 2
	Remotes.AbilityFX:FireAllClients({
		kind = "clash",
		a = a.UserId,
		b = b.UserId,
		character = character,
		slot = slot,
		duration = seconds,
		midpoint = midpoint,
	})
	if RunService:IsStudio() then
		print(string.format("[NAU] clash %s vs %s (%s.%s)", a.Name, b.Name, character, slot))
	end

	-- The exchange runs its time, or ends as soon as either fighter goes down; then both are thrown apart.
	task.spawn(function()
		while now() < untilTime and lifeOf(a) == lifeA and lifeOf(b) == lifeB do
			task.wait(0.1)
		end
		ClashRules.finish(clashState, a.UserId, b.UserId)
		freeA()
		freeB()
		local up = Vector3.new(0, Constants.CLASH_LAUNCH, 0)
		if lifeOf(a) == lifeA then
			sendEffect(a, { kind = "knockback", velocity = -axis * Constants.CLASH_KNOCKBACK + up })
		end
		if lifeOf(b) == lifeB then
			sendEffect(b, { kind = "knockback", velocity = axis * Constants.CLASH_KNOCKBACK + up })
		end
		for _, p in { a, b } do
			if p.Parent then
				sendEffect(p, { kind = "clash_end" })
			end
		end
		Remotes.AbilityFX:FireAllClients({ kind = "clash_end", a = a.UserId, b = b.UserId, midpoint = midpoint })
	end)
	return true
end

local function handleUse(player: Player, slot: any, aim: any, eye: any)
	if not AbilityRules.isSlot(slot) then
		return { status = "malformed" }
	end
	local match = RoundManager.getMatch()
	local entry = entries[player]
	if not match or match.ended or not entry or entry.match ~= match then
		return { status = "not_in_match" }
	end
	if ClashRules.isClashing(clashState, player.UserId) then
		return { status = "clashing" }
	end
	local p = match.participants[player.UserId]
	local t = now()
	local ok, reason = AbilityRules.check(entry.rules, slot, t, {
		inMatch = p ~= nil,
		alive = p ~= nil and p.alive and p.lifeId == entry.lifeId,
		protected = p ~= nil and p.protectedUntil ~= nil,
	})
	if not ok then
		return { status = reason, readyAt = entry.rules.readyAt[slot] }
	end
	if slot == "mild" and mildBlockedUntil[player.UserId] and t < mildBlockedUntil[player.UserId] then
		return { status = "blocked" } -- Sasuke's Hunter's Eye
	end
	local kit = IMPLEMENTED[entry.character]
	local ability = kit and kit[slot]
	if not ability then
		return { status = "not_available" }
	end

	-- prepare() never yields: it validates targets and returns the plan, or a reason (no cooldown spent).
	local ctx = makeContext(player, entry, aim, eye)
	local plan, why = ability.prepare(ctx)
	if not plan then
		return { status = why or "no_target" }
	end
	AbilityRules.activate(entry.rules, slot, t, COOLDOWNS[slot], plan.castSeconds or 0)
	pushState(player)
	if RunService:IsStudio() then
		print(string.format("[NAU] ability %s %s.%s", player.Name, entry.character, slot))
	end
	-- Every client starts the caster's cast animation from this (visual only; fired before the ability's
	-- own effects so the wind-up always leads them).
	Remotes.AbilityFX:FireAllClients({
		kind = "cast",
		caster = player.UserId,
		character = entry.character,
		slot = slot,
		castSeconds = plan.castSeconds or 0,
	})
	-- The same attack started at each other a moment apart clashes: both are cancelled, the pair locks in.
	local clashKey = ClashRules.key(entry.character, slot)
	local root = rootOf(player)
	if ClashRules.isClashable(clashKey) and root then
		local partner = ClashRules.offer(clashState, {
			id = player.UserId,
			key = clashKey,
			t = t,
			windup = plan.castSeconds or 0,
			position = root.Position,
			aim = ctx.flatAim(),
			team = p and p.team,
		}, CLASH_PARAMS)
		local other = partner and Players:GetPlayerByUserId(partner.id)
		if other and startClash(other, player, entry.character, slot, ctx) then
			return { status = "ok", readyAt = entry.rules.readyAt[slot] } -- this cast never runs
		end
		clashCasts[player.UserId] = ctx
	end
	task.spawn(function()
		local success, err = pcall(plan.run)
		if not success then
			warn("[NAU] ability failed: " .. tostring(err))
		end
	end)
	return { status = "ok", readyAt = entry.rules.readyAt[slot] }
end

local function handleEquip(player: Player, characterId: any)
	local def = if type(characterId) == "string" then CharacterDefs.byId[characterId] else nil
	if not def then
		return { status = "unknown" }
	end
	if not owns(player, def) then
		return { status = "not_owned" }
	end
	-- Switch in the lobby or while waiting to respawn, never mid-life (approved: respawn-screen switch).
	local match = RoundManager.getMatch()
	local p = match and not match.ended and match.participants[player.UserId]
	if p and p.alive then
		return { status = "in_fight" }
	end
	equipped[player] = def.id
	pushState(player)
	for _, listener in equipListeners do
		task.spawn(listener, player, def.id)
	end
	return { status = "equipped", equipped = def.id }
end

-- Called with (player, characterId) on every equip (ProfileService keeps the save current).
function AbilityService.onEquipped(listener: (Player, string) -> ())
	table.insert(equipListeners, listener)
end

-- The saved equipped character arrived: use it unless the player already picked one this session.
-- Returns the character now equipped.
function AbilityService.applySavedEquip(player: Player, id: string): string
	local def = CharacterDefs.byId[id]
	if equipped[player] == nil and def and owns(player, def) then
		equipped[player] = def.id
		pushState(player)
	end
	return equipped[player] or Constants.DEFAULT_CHARACTER
end

local function onLifeStarted(player: Player, match: any, lifeId: number)
	local t = now()
	local entry = entries[player]
	if not entry or entry.match ~= match then
		entry = { match = match, rules = AbilityRules.newState(t), lifeId = lifeId, character = Constants.DEFAULT_CHARACTER }
		entries[player] = entry
	else
		AbilityRules.onRespawn(entry.rules, t, Constants.ULTIMATE_RESPAWN_REDUCTION)
	end
	entry.lifeId = lifeId
	entry.character = equipped[player] or Constants.DEFAULT_CHARACTER
	speedMods[player] = nil
	guardUntil[player.UserId] = nil
	mildBlockedUntil[player.UserId] = nil
	pushState(player)
end

-- Does the player own this character (free, bought, or unlocked for Studio testing)? Used by ShopService.
function AbilityService.owns(player: Player, id: string): boolean
	local def = CharacterDefs.byId[id]
	return def ~= nil and owns(player, def)
end

function AbilityService.Init()
	Remotes.UseAbility.OnServerInvoke = handleUse
	Remotes.EquipCharacter.OnServerInvoke = handleEquip
	RoundManager.onLifeStarted(onLifeStarted)
	EconomyService.onInventoryChanged(pushState) -- a purchase: re-send the owned list
	EliminationService.onClonePopped(function(_popper: Player, decoyId: number)
		removeDecoy(decoyId) -- the popper's code box already says "It was a clone!"
	end)
	EliminationService.onElimination(function(attacker: Player, victimId: number)
		for _, listener in eliminationListeners do
			task.spawn(listener, attacker, victimId)
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		task.defer(pushState, player)
	end)
	for _, player in Players:GetPlayers() do
		task.defer(pushState, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		equipped[player] = nil
		entries[player] = nil
		speedMods[player] = nil
		guardUntil[player.UserId] = nil
		mildBlockedUntil[player.UserId] = nil
		lastGuardSpark[player.UserId] = nil
		clashCasts[player.UserId] = nil
	end)
end

-- Tell clients when a round starts or ends, so ability slots come and go with it; clear leftovers.
function AbilityService.Start()
	local lastMatch = nil
	while true do
		task.wait(0.5)
		local match = RoundManager.getMatch()
		local live = if match and not match.ended then match else nil
		if live ~= lastMatch then
			lastMatch = live
			for decoyId in decoyModels do
				removeDecoy(decoyId)
			end
			table.clear(barriers)
			table.clear(eliminationListeners)
			for _, player in Players:GetPlayers() do
				pushState(player)
			end
		end
	end
end

return AbilityService
