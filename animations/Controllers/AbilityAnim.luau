-- Ability cast animations (Phase 3 item 8). The server broadcasts a "cast" event (caster, character,
-- slot, cast time) the moment it accepts an ability; every client animates that caster from it.
--
-- Each ability has a wind-up clip (lasts the cast time) and a release clip (the strike). Per clip:
--   * authored id in Modules/AnimationIds -> the CASTER's own client plays it as an AnimationTrack at
--     Action priority. Roblox replicates the caster's tracks to everyone else, so other clients must not
--     play it too (they'd double it up).
--   * no id yet -> every client draws the procedural placeholder pose from AbilityPoses. Poses are
--     layered onto the joints' Transform right after the normal animation (Stepped) and cleared just
--     before the animator runs (PreAnimation), the same way the ninja-run pose works, so nothing piles
--     up and nothing is left behind when a cast ends.
-- Placeholder motion is kept fluid (owner request 2026-09-23): the poses only set *targets*. Each joint
-- follows its target on a damped spring (Modules/Spring, tuned per joint in Constants.ANIM_SPRINGS), the
-- torso slower than the arms, so strikes ease in, overshoot a touch and settle; the hands trail fast arm
-- swings; and a small breathing sway keeps held poses alive.
-- Casts end early when the fighter dies or respawns. Visual only: the server never waits on these.
--
-- Keyframed clips (owner, 2026-09-27: high-intensity fight animations; data in ReplicatedStorage.Animations.Clips,
-- format in Modules/KeyframeClip): where a move has a clip, it replaces the placeholder pose for that phase and is
-- played straight from its keys (no springs: the snaps and impact frames are the point). Clips pose the whole
-- body; while a fighter walks on the ground the legs are handed back to the walk. A published id in AnimationIds
-- still wins over both. A hit-stop (ImpactFX) can pause a cast for a split second.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local Fighters = require(Modules:WaitForChild("Fighters"))
local AnimationIds = require(Modules:WaitForChild("AnimationIds"))
local AnimTimeline = require(Modules:WaitForChild("AnimTimeline"))
local KeyframeClip = require(Modules:WaitForChild("KeyframeClip"))
local Spring = require(Modules:WaitForChild("Spring"))
local AbilityPoses = require(script.Parent:WaitForChild("AbilityPoses"))
local Swords = require(script.Parent:WaitForChild("Swords"))
local ClipsFolder = script.Parent.Parent:WaitForChild("Clips")

local AbilityAnim = {}

-- R15 joint name -> the part it lives in (the whole body: clips pose the legs too; placeholder poses never do).
local JOINT_PARTS: { [string]: string } = KeyframeClip.JOINT_PARTS

type PoseTable = { [string]: { number } }
type Pose = PoseTable | (number) -> PoseTable

type Cast = {
	character: Model,
	humanoid: Humanoid,
	started: number,
	timing: AnimTimeline.Timing,
	windup: Pose?, -- nil when an authored clip replaces it
	release: Pose?,
	tracks: { AnimationTrack },
	token: number,
	swords: boolean, -- this move drew swords (sheathed when the cast ends)
	trails: boolean, -- run the blade trails from the release until the fade
	trailsOn: boolean,
	poseOffset: number, -- seconds added to the pose clock (a clash's second fighter runs half a beat off)
	stiffness: number, -- multiplies the spring frequencies (fast repeating moves need snappier joints)
	names: { string }, -- the joints this cast drives, wrists last (they read the arms' swing)
	joints: { [string]: { angle: Vector3, velocity: Vector3 } }, -- spring state per joint, in degrees
	lastTime: number,
	seed: number, -- phase for the breathing sway, so two fighters never sway in lockstep
	characterId: string,
	slot: string,
	windupClip: KeyframeClip.Clip?, -- keyframed clips for this cast (nil = placeholder pose or authored track)
	releaseClip: KeyframeClip.Clip?,
	legs: number, -- 0..1: how much of the clip the legs play (walking hands them back)
	frozenUntil: number, -- hit-stop: the cast's clock is paused until then
	released: boolean, -- the release has started (listeners were told)
}

local localPlayer = Players.LocalPlayer
local casts: { [Model]: Cast } = {}
local dirty: { [Instance]: boolean } = {}
local nextToken = 0
local trackCache: { [Animator]: { [string]: AnimationTrack } } = setmetatable({}, { __mode = "k" }) :: any
local rng = Random.new()
local releaseListeners: { (Model, string, string) -> () } = {}

-- Keyframed clips by character id (one ModuleScript per character in Animations.Clips), loaded on first use.
local clipModules: { [string]: any } = {}
local function clipsFor(characterId: string, slot: string): { windup: KeyframeClip.Clip?, release: KeyframeClip.Clip? }?
	local loaded = clipModules[characterId]
	if loaded == nil then
		local module = ClipsFolder:FindFirstChild(characterId)
		local ok, result = false, nil
		if module and module:IsA("ModuleScript") then
			ok, result = pcall(require, module)
			if not ok then
				warn("[NAU] couldn't load clips for " .. characterId .. ": " .. tostring(result))
			end
		end
		loaded = if ok and type(result) == "table" then result else false
		clipModules[characterId] = loaded
	end
	local pair = loaded and loaded[slot]
	return if type(pair) == "table" then pair else nil
end

-- Sway amount per joint, as a share of Constants.ANIM_LIFE_DEGREES.
local LIFE_SHARE: { [string]: number } = {
	Waist = 0.7,
	Neck = 0.5,
	RightShoulder = 1,
	LeftShoulder = 1,
	RightElbow = 1.2,
	LeftElbow = 1.2,
}

local function springFor(name: string): (number, number)
	local springs = Constants.ANIM_SPRINGS
	local spec = springs[name]
		or (string.find(name, "Shoulder") and springs.Shoulder)
		or (string.find(name, "Elbow") and springs.Elbow)
		or (string.find(name, "Wrist") and springs.Wrist)
		or springs.Shoulder
	return spec[1], spec[2]
end

local function toDegrees(cframe: CFrame): Vector3
	local x, y, z = cframe:ToEulerAnglesXYZ()
	return Vector3.new(math.deg(x), math.deg(y), math.deg(z))
end

local function fromDegrees(angles: Vector3): CFrame
	return CFrame.Angles(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))
end

local function vectorOf(angles: { number }): Vector3
	return Vector3.new(angles[1] or 0, angles[2] or 0, angles[3] or 0)
end

local function evaluate(pose: Pose?, t: number): PoseTable?
	if pose == nil then
		return nil
	end
	if type(pose) == "function" then
		local ok, result = pcall(pose, t)
		return if ok and type(result) == "table" then result else nil
	end
	return pose
end

local function jointOf(character: Model, name: string): any
	local part = character:FindFirstChild(JOINT_PARTS[name] or "")
	local joint = part and part:FindFirstChild(name)
	if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
		return joint
	end
	return nil
end

-- Authored clips (caster's own client only) -------------------------------------------------------

local function loadTrack(humanoid: Humanoid, id: string): AnimationTrack?
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local byId = trackCache[animator]
	if not byId then
		byId = {}
		trackCache[animator] = byId
	end
	local track = byId[id]
	if not track then
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, loaded = pcall(animator.LoadAnimation, animator, animation)
		if not ok or not loaded then
			warn("[NAU] couldn't load ability animation " .. id .. ": " .. tostring(loaded))
			return nil
		end
		loaded.Priority = Enum.AnimationPriority.Action
		byId[id] = loaded
		track = loaded
	end
	return track
end

-- Stretch or squeeze a non-looping wind-up so it ends exactly when the ability fires.
local function fitToSeconds(track: AnimationTrack, seconds: number)
	if track.Looped or seconds <= 0 then
		return
	end
	task.spawn(function()
		local deadline = os.clock() + 1
		while track.Length <= 0 and os.clock() < deadline do
			task.wait()
		end
		if track.Length > 0 and track.IsPlaying then
			track:AdjustSpeed(track.Length / seconds)
		end
	end)
end

local function stopTracks(cast: Cast, fade: number)
	for _, track in cast.tracks do
		if track.IsPlaying then
			track:Stop(fade)
		end
	end
end

local function playAuthored(cast: Cast, windupId: string?, releaseId: string?)
	local windupTrack = windupId and loadTrack(cast.humanoid, windupId)
	if windupTrack and cast.timing.windup > 0 then
		table.insert(cast.tracks, windupTrack)
		windupTrack:Play(Constants.ANIM_BLEND_IN)
		fitToSeconds(windupTrack, cast.timing.windup)
	end
	if not releaseId then
		task.delay(cast.timing.windup, function()
			if windupTrack and windupTrack.IsPlaying then
				windupTrack:Stop(Constants.ANIM_RELEASE_SNAP)
			end
		end)
		return
	end
	task.delay(cast.timing.windup, function()
		if casts[cast.character] ~= cast then
			return -- cancelled or replaced
		end
		if windupTrack and windupTrack.IsPlaying then
			windupTrack:Stop(Constants.ANIM_RELEASE_SNAP)
		end
		local releaseTrack = loadTrack(cast.humanoid, releaseId)
		if not releaseTrack then
			return
		end
		table.insert(cast.tracks, releaseTrack)
		releaseTrack:Play(Constants.ANIM_RELEASE_SNAP)
		if releaseTrack.Looped then
			-- A looping release (a flurry, a held stance) runs for the move's hold, then fades out.
			local token = cast.token
			task.delay(cast.timing.hold, function()
				if cast.token == token and releaseTrack.IsPlaying then
					releaseTrack:Stop(Constants.ANIM_BLEND_OUT)
				end
			end)
		end
	end)
end

-- Casts ------------------------------------------------------------------------------------------

local function endCast(character: Model, fade: number)
	local cast = casts[character]
	if cast then
		casts[character] = nil
		stopTracks(cast, fade)
		if cast.swords then
			Swords.sheathe(character, if fade > 0 then nil else 0)
		end
	end
end

-- Every joint either pose touches (function poses sampled at a few moments), then the wrists of any posed
-- arm: the wrists come last because their drag reads the arm joints' spring velocity from the same frame.
local function jointNames(windup: Pose?, release: Pose?): { string }
	local seen: { [string]: boolean } = {}
	local names: { string } = {}
	for _, pose in { windup, release } do
		for _, t in { 0, 0.05, 0.1, 0.2 } do
			for name in evaluate(pose, t) or {} do
				if not seen[name] and JOINT_PARTS[name] and not string.find(name, "Wrist") then
					seen[name] = true
					table.insert(names, name)
				end
			end
		end
	end
	for _, side in { "Right", "Left" } do
		if seen[side .. "Shoulder"] or seen[side .. "Elbow"] then
			table.insert(names, side .. "Wrist")
		end
	end
	return names
end

-- A fighter from a user id (what the server sends) or a character model (solo visual tests against a
-- dummy, since a real clash needs two players).
local function fighterOf(who: any): (Player?, Model?)
	if typeof(who) == "Instance" and who:IsA("Model") then
		return nil, who
	end
	local player = if type(who) == "number" then Players:GetPlayerByUserId(who) else nil
	-- A training bot has no Player: its body is found by id.
	return player, if player then player.Character else Fighters.botModel(who)
end

-- Start `move` on a fighter (user id or model), replacing whatever they were casting. Authored clips
-- (from AnimationIds) only apply to real casts, not to clash exchanges.
local function startCast(who: any, characterId: string, slot: string, move: any, castSeconds: number, authored: boolean, poseOffset: number?)
	local player, character = fighterOf(who)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local clips = clipsFor(characterId, slot)
	if (not move and not clips) or not character or not humanoid or humanoid.Health <= 0 then
		return
	end
	move = move or {}
	local windupSeconds = tonumber(move.windupSeconds) or castSeconds
	local windupId = if authored then AnimationIds.get(characterId, slot, "windup") else nil
	local releaseId = if authored then AnimationIds.get(characterId, slot, "release") else nil
	endCast(character, Constants.ANIM_RELEASE_SNAP)
	nextToken += 1
	local started = os.clock()
	-- A clip replaces the placeholder pose for its phase; a published id replaces both.
	local windupClip = if clips and not windupId then clips.windup else nil
	local releaseClip = if clips and not releaseId then clips.release else nil
	local windupPose = if windupId or windupClip then nil else move.windup
	local releasePose = if releaseId or releaseClip then nil else move.release
	local keyed = clips ~= nil
	local hold = tonumber(move.hold) or Constants.ANIM_DEFAULT_HOLD
	if releaseClip and not releaseClip.looped then
		hold = releaseClip.length -- a one-shot clip holds exactly as long as it runs
	end
	local names = jointNames(windupPose, releasePose)
	for _, clip in { windupClip, releaseClip } do
		for _, key in clip and clip.keys or {} do
			for joint in key.pose do
				if not table.find(names, joint) then
					table.insert(names, joint)
				end
			end
		end
	end
	local cast: Cast = {
		character = character,
		humanoid = humanoid,
		started = started,
		timing = {
			windup = math.clamp(windupSeconds, 0, Constants.ANIM_MAX_WINDUP),
			hold = hold,
			-- A keyframed move with no wind-up (a hit reaction, a clash) *is* the impact: it snaps in at once,
			-- so the hit-stop that freezes it on its first frame shows the full pose.
			blendIn = if keyed then (if windupSeconds <= 0 then 0 else Constants.CLIP_BLEND_IN) else Constants.ANIM_BLEND_IN,
			snap = if keyed then Constants.CLIP_SNAP else Constants.ANIM_RELEASE_SNAP,
			blendOut = if keyed then Constants.CLIP_BLEND_OUT else Constants.ANIM_BLEND_OUT,
		},
		windup = windupPose,
		release = releasePose,
		tracks = {},
		token = nextToken,
		swords = move.swords ~= nil,
		trails = move.trails == true,
		trailsOn = false,
		poseOffset = poseOffset or 0,
		stiffness = tonumber(move.stiffness) or 1,
		names = names,
		joints = {},
		lastTime = started,
		seed = rng:NextNumber(0, math.pi * 2),
		characterId = characterId,
		slot = slot,
		windupClip = windupClip,
		releaseClip = releaseClip,
		legs = 1,
		frozenUntil = 0,
		released = false,
	}
	casts[character] = cast
	if move.swords then
		Swords.draw(character, move.swords)
	end
	if player ~= nil and player == localPlayer and (windupId or releaseId) then
		playAuthored(cast, windupId, releaseId)
	end
end

local function onCast(event: any)
	local casterId, characterId, slot, castSeconds = event.caster, event.character, event.slot, event.castSeconds
	if type(casterId) ~= "number" or type(characterId) ~= "string" or type(slot) ~= "string" or type(castSeconds) ~= "number" then
		return
	end
	local byCharacter = AbilityPoses[characterId]
	startCast(casterId, characterId, slot, type(byCharacter) == "table" and byCharacter[slot] or nil, castSeconds, true)
end

-- M1 (owner request 2026-09-25): a punch of the shared click combo ("melee", move = "m1_1".."m1_4"),
-- or the flinch of someone who got hit ("melee_hit"). Authored clips go in AnimationIds under "Melee".
local function onMelee(event: any)
	local who, moveName, castSeconds = event.caster, event.move, event.castSeconds
	if type(who) ~= "number" or type(moveName) ~= "string" or type(castSeconds) ~= "number" then
		return
	end
	local move = AbilityPoses.Melee and AbilityPoses.Melee[moveName]
	startCast(who, "Melee", moveName, move, castSeconds, true)
end

local function onMeleeHit(event: any)
	-- A user id from the server; a model only in solo visual tests (see fighterOf).
	if type(event.target) ~= "number" and not (typeof(event.target) == "Instance" and event.target:IsA("Model")) then
		return
	end
	local _, character = fighterOf(event.target)
	-- Someone still winding up (an ability, or a punch about to trade) keeps their pose: the flinch never
	-- swallows a blow that's on its way.
	local current = character and casts[character]
	if current and os.clock() - current.started < current.timing.windup + 0.05 then
		return
	end
	-- The finisher throws them: the "launched" reaction (keyframed only; a plain flinch is the fallback).
	local slot = if event.finisher and clipsFor("Melee", "launched") then "launched" else "hit"
	local move = AbilityPoses.Melee and AbilityPoses.Melee[slot]
	startCast(event.target, "Melee", slot, move, 0, true)
end

-- A clash: both fighters drop their cast and play that attack's exchange for the clash's length. The
-- second runs half a beat behind the first, so their blows meet (one cuts high as the other cuts low)
-- instead of mirroring each other in lockstep.
local function onClash(event: any)
	local characterId, slot, seconds = event.character, event.slot, event.duration
	if type(characterId) ~= "string" or type(slot) ~= "string" or type(seconds) ~= "number" then
		return
	end
	seconds = math.clamp(seconds, 0, 10)
	-- The M1 trade clash has a keyframed exchange (and its own published-id slot, Melee.clash): the second
	-- fighter runs half a loop behind, so one fist lands as the other pulls back.
	local exchange = if characterId == "Melee" then clipsFor("Melee", "clash") else nil
	if exchange and exchange.release then
		local offset = exchange.release.length / 2
		startCast(event.a, "Melee", "clash", { windupSeconds = 0, hold = seconds }, 0, true, 0)
		startCast(event.b, "Melee", "clash", { windupSeconds = 0, hold = seconds }, 0, true, offset)
		return
	end
	local move = AbilityPoses.clashMove(characterId, slot, seconds)
	if not move then
		return
	end
	startCast(event.a, characterId, slot, move, 0, false, 0)
	startCast(event.b, characterId, slot, move, 0, false, move.counterOffset)
end

-- Per frame --------------------------------------------------------------------------------------

-- How much of a clip the legs play: all of it standing, in the air or being thrown; none while walking on the
-- ground (the walk takes them back, so feet never skate). Eased, so the hand-over doesn't pop.
local function legShare(cast: Cast, dt: number): number
	local root = cast.character:FindFirstChild("HumanoidRootPart")
	local walking = false
	if root and root:IsA("BasePart") and cast.humanoid.FloorMaterial ~= Enum.Material.Air then
		local v = root.AssemblyLinearVelocity
		walking = Vector3.new(v.X, 0, v.Z).Magnitude > Constants.CLIP_WALK_SPEED
	end
	local target = if walking then 0 else 1
	cast.legs += (target - cast.legs) * (1 - math.exp(-Constants.CLIP_LEG_BLEND_RATE * dt))
	return cast.legs
end

-- A keyframed phase: pose straight from the clip's keys.
local function applyClip(cast: Cast, clip: KeyframeClip.Clip, t: number, weight: number, dt: number)
	local legs = legShare(cast, dt)
	for joint, values in KeyframeClip.sample(clip, t) do
		local instance = jointOf(cast.character, joint)
		if instance then
			local w = math.min(weight, 1) * (if KeyframeClip.LEG_JOINTS[joint] then legs else 1)
			if w > 0.001 then
				instance.Transform = instance.Transform:Lerp(KeyframeClip.toCFrame(values), w)
				dirty[instance] = true
			end
		end
	end
end

local function applyCast(cast: Cast, now: number): boolean
	local dt = math.clamp(now - cast.lastTime, 0, 0.1)
	cast.lastTime = now
	if now < cast.frozenUntil then
		cast.started += dt -- hit-stop: the cast's clock stands still
	end
	local s = AnimTimeline.sample(cast.timing, now - cast.started)
	if s.phase == "done" then
		return false
	end
	if s.phase ~= "windup" and not cast.released then
		cast.released = true
		for _, listener in releaseListeners do
			task.spawn(listener, cast.character, cast.characterId, cast.slot)
		end
	end
	if cast.trails then
		local want = s.phase == "release"
		if want ~= cast.trailsOn then
			cast.trailsOn = want
			Swords.setTrails(cast.character, want)
		end
	end
	-- Keyframed phase? A non-looping wind-up clip is stretched or squeezed to the cast time.
	if s.phase == "windup" and cast.windupClip then
		local clip = cast.windupClip
		local t = if clip.looped then s.windupT else s.windupT / math.max(cast.timing.windup, 1e-3) * clip.length
		applyClip(cast, clip, t + cast.poseOffset, s.weight, dt)
		table.clear(cast.joints)
		return true
	elseif s.phase ~= "windup" and cast.releaseClip then
		applyClip(cast, cast.releaseClip, s.releaseT + cast.poseOffset, s.weight, dt)
		table.clear(cast.joints)
		return true
	end
	-- While an authored clip plays this phase, leave the joints to it (and start the springs afresh from
	-- whatever it left behind if a placeholder phase follows).
	local posing = if s.mix >= 1 then cast.release ~= nil else cast.windup ~= nil
	if not posing then
		table.clear(cast.joints)
		return true
	end
	local from = evaluate(cast.windup, s.windupT + cast.poseOffset)
	local to = if s.mix > 0 then evaluate(cast.release, s.releaseT + cast.poseOffset) else nil
	local fading = s.phase == "fade"
	local elapsed = now - cast.started
	local life = Constants.ANIM_LIFE_DEGREES
	-- Strikes: stiffer springs right as the ability releases, easing back to the soft default.
	-- A move's own stiffness (fast repeating blows, spins) applies from the release on, so its wind-up
	-- still eases in softly.
	local boost = 1
	if s.phase == "release" then
		local left = 1 - AnimTimeline.smooth(s.releaseT / Constants.ANIM_STRIKE_SECONDS)
		boost = math.max(1 + (Constants.ANIM_STRIKE_BOOST - 1) * left, cast.stiffness)
	end
	for _, name in cast.names do
		local joint = jointOf(cast.character, name)
		if joint then
			-- What the normal animation wants this frame: the target for any joint the current pose leaves
			-- out. While fading, the springs keep holding the pose and only the eased blend weight carries
			-- the body home (spring and blend together measured as a jerk).
			local animated = joint.Transform
			local animatedAngles = toDegrees(animated)
			local target = animatedAngles
			local a = from and from[name]
			local b = to and to[name]
			if a or b then
				local va = if a then vectorOf(a) else animatedAngles
				local vb = if b then vectorOf(b) else animatedAngles
				target = if s.mix > 0 then va:Lerp(vb, s.mix) else va
				local share = if fading then nil else LIFE_SHARE[name]
				if share then -- breathing sway, a different rhythm on every joint
					local p = cast.seed + #name * 0.9
					target += Vector3.new(
						math.sin(elapsed * 2.1 + p),
						math.sin(elapsed * 1.7 + p * 1.3) * 0.6,
						math.sin(elapsed * 2.6 + p * 0.7) * 0.5
					) * (life * share)
				end
			end
			local state = cast.joints[name]
			if not state then
				state = { angle = animatedAngles, velocity = Vector3.zero } -- start from where the body is
				cast.joints[name] = state
			end
			local side = string.match(name, "^(%a-)Wrist$")
			if side then
				-- The hand trails the arm: bent back against a forward swing, forward against a back swing.
				local swing = 0
				local elbow, shoulder = cast.joints[side .. "Elbow"], cast.joints[side .. "Shoulder"]
				if elbow then
					swing += elbow.velocity.X
				end
				if shoulder then
					swing += shoulder.velocity.X * 0.6
				end
				local maxDrag = Constants.ANIM_WRIST_DRAG_MAX
				target += Vector3.new(math.clamp(-swing * Constants.ANIM_WRIST_DRAG, -maxDrag, maxDrag), 0, 0)
			end
			target = Vector3.new(
				Spring.nearestAngle(state.angle.X, target.X),
				Spring.nearestAngle(state.angle.Y, target.Y),
				Spring.nearestAngle(state.angle.Z, target.Z)
			)
			local frequency, damping = springFor(name)
			state.angle, state.velocity = Spring.step(state.angle, state.velocity, target, frequency * boost, damping, dt)
			if s.weight > 0.001 then
				joint.Transform = animated:Lerp(fromDegrees(state.angle), math.min(s.weight, 1))
				dirty[joint] = true
			end
		end
	end
	return true
end

local function step()
	local now = os.clock()
	for character, cast in casts do
		local alive = character.Parent ~= nil and cast.humanoid.Parent ~= nil and cast.humanoid.Health > 0
		-- One broken cast (a joint gone mid-pose) is dropped instead of erroring every frame and stopping every
		-- cast after it (audit fix, 2026-09-28).
		local ok, running = true, true
		if alive then
			ok, running = pcall(applyCast, cast, now)
			if not ok then
				warn("[NAU] cast animation failed: " .. tostring(running))
			end
		end
		if not alive or not ok then
			local ended = pcall(endCast, character, 0)
			if not ended then
				casts[character] = nil
			end
		elseif not running then
			-- Pose finished. An authored release clip keeps playing to its own end (a looping one is
			-- stopped by its hold timer), so only drop the bookkeeping here (and put the swords away).
			casts[character] = nil
			if cast.swords then
				Swords.sheathe(character)
			end
		end
	end
end

-- Before the animator runs: joints we posed last frame go back to neutral, so the pose never
-- accumulates on a joint no track drives and nothing lingers after a cast.
local function reset()
	for joint in dirty do
		dirty[joint] = nil
		if joint.Parent then
			joint.Transform = CFrame.identity
		end
	end
end

function AbilityAnim.handle(event: any)
	if type(event) ~= "table" then
		return
	end
	if event.kind == "cast" then
		onCast(event)
	elseif event.kind == "clash" then
		onClash(event)
	elseif event.kind == "melee" then
		onMelee(event)
	elseif event.kind == "melee_hit" then
		onMeleeHit(event)
	end
end

-- The clash duel (animations/Controllers/DuelFX): plays one move on a fighter (user id or model). `hold`
-- overrides how long the release is held (the barrage runs until the duel ends; the next move replaces it);
-- `poseOffset` starts the pose clock later (the second fighter's barrage runs half a beat off).
function AbilityAnim.playMove(who: any, characterId: string, slot: string, castSeconds: number, hold: number?, poseOffset: number?)
	local byCharacter = AbilityPoses[characterId]
	local base = type(byCharacter) == "table" and byCharacter[slot] or nil
	local move = if base then table.clone(base) else {}
	move.windupSeconds = castSeconds -- the duel sets the pace (a slow punch winds up for over a second)
	if hold then
		move.hold = hold
	end
	startCast(who, characterId, slot, move, castSeconds, true, poseOffset)
end

-- The yen shop's hologram: plays a character's ability animation (placeholder pose and swords) on a
-- stand-in model that isn't a player.
function AbilityAnim.preview(model: Model, characterId: string, slot: string, castSeconds: number)
	local byCharacter = AbilityPoses[characterId]
	startCast(model, characterId, slot, type(byCharacter) == "table" and byCharacter[slot] or nil, castSeconds, false)
end

-- For tests and tooling: is this character mid-cast?
function AbilityAnim.isCasting(character: Model): boolean
	return casts[character] ~= nil
end

-- Hit-stop (ImpactFX): pause this fighter's cast for `seconds`, so a blow's impact frame hangs in the air.
-- Published clips on the Animator are paused by ImpactFX itself.
function AbilityAnim.freeze(character: Model, seconds: number)
	local cast = casts[character]
	if cast then
		cast.frozenUntil = math.max(cast.frozenUntil, os.clock() + seconds)
	end
end

-- Called with (character, characterId, slot) the moment a cast's release starts (ImpactFX adds its weight
-- to ultimates and finishers).
function AbilityAnim.onRelease(listener: (Model, string, string) -> ())
	table.insert(releaseListeners, listener)
end

-- For tooling (contact sheets and publishing): the keyframed clips of one move, if it has any.
function AbilityAnim.clips(characterId: string, slot: string): { windup: KeyframeClip.Clip?, release: KeyframeClip.Clip? }?
	return clipsFor(characterId, slot)
end

local started = false
function AbilityAnim.start()
	if started then
		return
	end
	started = true
	RunService.PreAnimation:Connect(reset)
	RunService.Stepped:Connect(step)
end

return AbilityAnim
