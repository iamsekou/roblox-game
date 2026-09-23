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
-- Casts end early when the fighter dies or respawns. Visual only: the server never waits on these.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local AnimationIds = require(Modules:WaitForChild("AnimationIds"))
local AnimTimeline = require(Modules:WaitForChild("AnimTimeline"))
local AbilityPoses = require(script.Parent:WaitForChild("AbilityPoses"))
local Swords = require(script.Parent:WaitForChild("Swords"))

local AbilityAnim = {}

-- R15 joint name -> the part it lives in.
local JOINT_PARTS: { [string]: string } = {
	Waist = "UpperTorso",
	Neck = "Head",
	RightShoulder = "RightUpperArm",
	RightElbow = "RightLowerArm",
	RightWrist = "RightHand",
	LeftShoulder = "LeftUpperArm",
	LeftElbow = "LeftLowerArm",
	LeftWrist = "LeftHand",
}

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
}

local localPlayer = Players.LocalPlayer
local casts: { [Model]: Cast } = {}
local dirty: { [Instance]: boolean } = {}
local nextToken = 0
local trackCache: { [Animator]: { [string]: AnimationTrack } } = setmetatable({}, { __mode = "k" }) :: any
local cframeCache: { [{ number }]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

local function toCFrame(angles: { number }): CFrame
	local cached = cframeCache[angles]
	if not cached then
		cached = CFrame.Angles(math.rad(angles[1] or 0), math.rad(angles[2] or 0), math.rad(angles[3] or 0))
		cframeCache[angles] = cached
	end
	return cached
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

-- A fighter from a user id (what the server sends) or a character model (solo visual tests against a
-- dummy, since a real clash needs two players).
local function fighterOf(who: any): (Player?, Model?)
	if typeof(who) == "Instance" and who:IsA("Model") then
		return nil, who
	end
	local player = if type(who) == "number" then Players:GetPlayerByUserId(who) else nil
	return player, player and player.Character
end

-- Start `move` on a fighter (user id or model), replacing whatever they were casting. Authored clips
-- (from AnimationIds) only apply to real casts, not to clash exchanges.
local function startCast(who: any, characterId: string, slot: string, move: any, castSeconds: number, authored: boolean, poseOffset: number?)
	local player, character = fighterOf(who)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not move or not character or not humanoid or humanoid.Health <= 0 then
		return
	end
	local windupSeconds = tonumber(move.windupSeconds) or castSeconds
	local windupId = if authored then AnimationIds.get(characterId, slot, "windup") else nil
	local releaseId = if authored then AnimationIds.get(characterId, slot, "release") else nil
	endCast(character, Constants.ANIM_RELEASE_SNAP)
	nextToken += 1
	local cast: Cast = {
		character = character,
		humanoid = humanoid,
		started = os.clock(),
		timing = {
			windup = math.clamp(windupSeconds, 0, Constants.ANIM_MAX_WINDUP),
			hold = tonumber(move.hold) or Constants.ANIM_DEFAULT_HOLD,
			blendIn = Constants.ANIM_BLEND_IN,
			snap = Constants.ANIM_RELEASE_SNAP,
			blendOut = Constants.ANIM_BLEND_OUT,
		},
		windup = if windupId then nil else move.windup,
		release = if releaseId then nil else move.release,
		tracks = {},
		token = nextToken,
		swords = move.swords ~= nil,
		trails = move.trails == true,
		trailsOn = false,
		poseOffset = poseOffset or 0,
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

-- A clash: both fighters drop their cast and play that attack's exchange for the clash's length. The
-- second runs half a beat behind the first, so their blows meet (one cuts high as the other cuts low)
-- instead of mirroring each other in lockstep.
local function onClash(event: any)
	local characterId, slot, seconds = event.character, event.slot, event.duration
	if type(characterId) ~= "string" or type(slot) ~= "string" or type(seconds) ~= "number" then
		return
	end
	local move = AbilityPoses.clashMove(characterId, slot, math.clamp(seconds, 0, 10))
	if not move then
		return
	end
	startCast(event.a, characterId, slot, move, 0, false, 0)
	startCast(event.b, characterId, slot, move, 0, false, move.counterOffset)
end

-- Per frame --------------------------------------------------------------------------------------

local function applyCast(cast: Cast, now: number): boolean
	local s = AnimTimeline.sample(cast.timing, now - cast.started)
	if s.phase == "done" then
		return false
	end
	if cast.trails then
		local want = s.phase == "release"
		if want ~= cast.trailsOn then
			cast.trailsOn = want
			Swords.setTrails(cast.character, want)
		end
	end
	local from = evaluate(cast.windup, s.windupT + cast.poseOffset)
	local to = if s.mix > 0 then evaluate(cast.release, s.releaseT + cast.poseOffset) else nil
	local names: { [string]: boolean } = {}
	for name in from or {} do
		names[name] = true
	end
	for name in to or {} do
		names[name] = true
	end
	for name in names do
		local joint = jointOf(cast.character, name)
		if joint then
			-- A joint missing from one pose keeps the normal animation in that pose (weight 0 there).
			local a = from and from[name]
			local b = to and to[name]
			local cfA = if a then toCFrame(a) else nil
			local cfB = if b then toCFrame(b) else nil
			local target: CFrame = if cfA and cfB then cfA:Lerp(cfB, s.mix) else (cfA or cfB) :: CFrame
			local weightA = if a then 1 else 0
			local weightB = if b then 1 else 0
			local weight = (weightA + (weightB - weightA) * s.mix) * s.weight
			if weight > 0.001 then
				joint.Transform = joint.Transform:Lerp(target, math.min(weight, 1))
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
		if not alive then
			endCast(character, 0)
		elseif not applyCast(cast, now) then
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
	end
end

-- For tests and tooling: is this character mid-cast?
function AbilityAnim.isCasting(character: Model): boolean
	return casts[character] ~= nil
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
