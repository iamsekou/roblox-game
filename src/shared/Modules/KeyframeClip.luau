-- Keyframed animation clips as data (owner, 2026-09-27: "stronger, high-intensity" fight animations). Pure,
-- unit-tested. One clip is the single source for both ways it plays:
--   * in game straight away: AbilityAnim samples it every frame and poses the joints (no upload needed);
--   * published: tools build a KeyframeSequence from the same data for the owner to publish, and once its id
--     is in Modules/AnimationIds the Animator plays that instead (docs/ANIMATING.md).
--
-- A clip: { length = seconds, looped = bool?, keys = { { t = seconds, ease = style?, pose = { [joint] = values } } } }.
-- values = { rx, ry, rz } in degrees, optionally followed by px, py, pz in studs (only the Root joint uses a
-- position: it moves the whole body off the HumanoidRootPart, for crouches and lunges). A joint may be left out
-- of a key: it then eases straight from its previous key to its next. `ease` shapes the motion *from* that key
-- to the next one for every joint it sets:
--   "linear", "in" (slow start, snaps into the next key), "out" (fast start, settles), "inout" (cubic),
--   "hold" (stays put, then jumps at the next key: an impact frame).
-- Angles use the same axes as AbilityPoses (measured on this place's rigs; see its header). Legs, measured
-- 2026-09-27: Hip +X swings the leg forward, right +Z / left -Z out to the side; Knee bends on -X; Root rotates
-- like the Waist (+X leans back, +Y twists left, +Z leans left).
local KeyframeClip = {}

export type Values = { number }
export type Key = { t: number, ease: string?, pose: { [string]: Values } }
export type Clip = { length: number, looped: boolean?, dense: boolean?, keys: { Key } }

-- Every joint a clip may drive (R15, this place's AnimationConstraint rigs), with the part it moves: the
-- KeyframeSequence builder nests poses by these parts.
KeyframeClip.JOINT_PARTS = {
	Root = "LowerTorso",
	Waist = "UpperTorso",
	Neck = "Head",
	RightShoulder = "RightUpperArm",
	RightElbow = "RightLowerArm",
	RightWrist = "RightHand",
	LeftShoulder = "LeftUpperArm",
	LeftElbow = "LeftLowerArm",
	LeftWrist = "LeftHand",
	RightHip = "RightUpperLeg",
	RightKnee = "RightLowerLeg",
	RightAnkle = "RightFoot",
	LeftHip = "LeftUpperLeg",
	LeftKnee = "LeftLowerLeg",
	LeftAnkle = "LeftFoot",
}

-- The leg joints (the Root included: it carries the legs). Players can walk while a clip plays, so the game
-- lets walking take the legs back (see AbilityAnim).
KeyframeClip.LEG_JOINTS = { Root = true, RightHip = true, RightKnee = true, RightAnkle = true, LeftHip = true, LeftKnee = true, LeftAnkle = true }

KeyframeClip.EASES = { linear = true, ["in"] = true, out = true, inout = true, hold = true }

function KeyframeClip.ease(style: string?, x: number): number
	x = math.clamp(x, 0, 1)
	if style == "hold" then
		return 0
	elseif style == "in" then
		return x * x * x
	elseif style == "out" then
		local y = 1 - x
		return 1 - y * y * y
	elseif style == "inout" then
		return if x < 0.5 then 4 * x * x * x else 1 - (-2 * x + 2) ^ 3 / 2
	end
	return x
end

local function lerpValues(a: Values, b: Values, k: number): Values
	local out = table.create(6)
	for i = 1, math.max(#a, #b) do
		local va, vb = a[i] or 0, b[i] or 0
		out[i] = va + (vb - va) * k
	end
	return out
end

-- A dense clip (baked from Blender by tools/blender/export.py: every key sets every joint, linear between) is
-- sampled by a binary search for the two keys around `t`.
local function sampleDense(keys: { Key }, t: number): { [string]: Values }
	local lo, hi = 1, #keys
	if t <= keys[1].t then
		hi = 1
	elseif t >= keys[#keys].t then
		lo = #keys
	else
		while hi - lo > 1 do
			local mid = (lo + hi) // 2
			if keys[mid].t <= t then
				lo = mid
			else
				hi = mid
			end
		end
	end
	local a, b = keys[lo], keys[hi]
	local span = b.t - a.t
	local k = if span > 0 then (t - a.t) / span else 0
	local result: { [string]: Values } = {}
	for joint, values in a.pose do
		local other = b.pose[joint]
		result[joint] = if other then lerpValues(values, other, k) else table.clone(values)
	end
	return result
end

-- The joint values at `t` seconds: { [joint] = values } for every joint the clip keys. A looped clip wraps;
-- any other clip holds its first key before 0 and its last after its length.
function KeyframeClip.sample(clip: Clip, t: number): { [string]: Values }
	if clip.looped and clip.length > 0 then
		t %= clip.length
	end
	t = math.clamp(t, 0, clip.length)
	local keys = clip.keys
	if (clip :: any).dense and #keys > 0 then
		return sampleDense(keys, t)
	end
	local result: { [string]: Values } = {}
	local joints: { [string]: boolean } = {}
	for _, key in keys do
		for joint in key.pose do
			joints[joint] = true
		end
	end
	for joint in joints do
		-- The last key at or before t that sets this joint, and the first one after it.
		local before: Key?, after: Key? = nil, nil
		for _, key in keys do
			if key.pose[joint] then
				if key.t <= t then
					before = key
				elseif after == nil then
					after = key
				end
			end
		end
		if before and after then
			local span = after.t - before.t
			local k = if span > 0 then KeyframeClip.ease(before.ease, (t - before.t) / span) else 1
			result[joint] = lerpValues(before.pose[joint], after.pose[joint], k)
		elseif before then
			result[joint] = table.clone(before.pose[joint])
		elseif after then
			result[joint] = table.clone(after.pose[joint])
		end
	end
	return result
end

-- The CFrame a joint's Transform gets for `values` (same composition as AbilityAnim's placeholder poses and
-- the published KeyframeSequence, so all three agree).
function KeyframeClip.toCFrame(values: Values): CFrame
	local rotation = CFrame.Angles(math.rad(values[1] or 0), math.rad(values[2] or 0), math.rad(values[3] or 0))
	if values[4] or values[5] or values[6] then
		return CFrame.new(values[4] or 0, values[5] or 0, values[6] or 0) * rotation
	end
	return rotation
end

-- Authoring helpers ------------------------------------------------------------------------------

-- The same pose on the other side: Right and Left joints swap, and the sideways rotations (Y, Z) and the Root's
-- sideways shift flip. A right-hand punch becomes a left-hand one.
function KeyframeClip.mirror(pose: { [string]: Values }): { [string]: Values }
	local out: { [string]: Values } = {}
	for joint, values in pose do
		local other = if string.sub(joint, 1, 5) == "Right" then "Left" .. string.sub(joint, 6)
			elseif string.sub(joint, 1, 4) == "Left" then "Right" .. string.sub(joint, 5)
			else joint
		local flipped = table.clone(values)
		flipped[2] = -(values[2] or 0)
		flipped[3] = -(values[3] or 0)
		if flipped[4] then
			flipped[4] = -flipped[4]
		end
		out[other] = flipped
	end
	return out
end

-- Pose tables merged left to right (later ones win per joint).
function KeyframeClip.merge(...: { [string]: Values }): { [string]: Values }
	local out: { [string]: Values } = {}
	for _, pose in { ... } do
		for joint, values in pose do
			out[joint] = values
		end
	end
	return out
end

-- Rig proportions used to plant the feet (this place's default R15 avatar, measured 2026-09-27): hip to knee,
-- knee to ankle, ankle to sole, and hip to sole standing. The rig measured 2.01 standing, 0.04 short of the
-- straight leg (its rest pose isn't perfectly straight); the straight length is used so the rest pose solves
-- to zero angles. The feet land within those 0.04 studs.
KeyframeClip.LEG = { thigh = 0.98, shin = 0.72, ankle = 0.35, hip = 2.05 }

-- One leg reaching a flat foot on the ground `reach` studs in front of its hip (negative = behind) with the
-- pelvis dropped by `drop` and pitched `pitch` degrees: (hip X, knee X, ankle X). Two-bone IK in the side view;
-- a target out of reach straightens the leg toward it.
local function plantLeg(drop: number, reach: number, pitch: number): (number, number, number)
	local L = KeyframeClip.LEG
	local height = L.hip - drop - L.ankle
	local distance = math.clamp(math.sqrt(height * height + reach * reach), 0.2, L.thigh + L.shin)
	local toward = math.atan2(reach, height) -- from straight down, toward the front
	local thighOff = math.acos(math.clamp((L.thigh ^ 2 + distance ^ 2 - L.shin ^ 2) / (2 * L.thigh * distance), -1, 1))
	local kneeInner = math.acos(math.clamp((L.thigh ^ 2 + L.shin ^ 2 - distance ^ 2) / (2 * L.thigh * L.shin), -1, 1))
	local thigh = math.deg(toward + thighOff) -- the knee points forward
	local bend = 180 - math.deg(kneeInner)
	local hip = thigh - pitch
	return hip, -bend, -(pitch + hip - bend)
end

-- A planted stance for fight moves: the Root and both legs. Options (all optional, studs and degrees):
--   drop     how far the pelvis sinks (a crouch); forward: how far it shifts ahead of the feet (a lunge)
--   pitch    Root lean (negative leans forward); twist: Root turn (positive turns left); lean: Root side tilt
--   right, left   each foot's distance in front of its hip before the lunge (negative = behind)
--   spread   how far apart the feet splay sideways, in degrees at the hips
-- The hips counter the twist so the feet keep pointing ahead.
function KeyframeClip.stance(o: { [string]: number }?): { [string]: Values }
	local opts = o or {}
	local drop, forward = opts.drop or 0, opts.forward or 0
	local pitch, twist, lean = opts.pitch or 0, opts.twist or 0, opts.lean or 0
	local spread = opts.spread or 4
	local rHip, rKnee, rAnkle = plantLeg(drop, (opts.right or 0) - forward, pitch)
	local lHip, lKnee, lAnkle = plantLeg(drop, (opts.left or 0) - forward, pitch)
	return {
		Root = { pitch, twist, lean, 0, -drop, -forward },
		RightHip = { rHip, -twist, spread - lean },
		RightKnee = { rKnee, 0, 0 },
		RightAnkle = { rAnkle, 0, 0 },
		LeftHip = { lHip, -twist, -spread - lean },
		LeftKnee = { lKnee, 0, 0 },
		LeftAnkle = { lAnkle, 0, 0 },
	}
end

-- Problems with a clip's data, as readable strings (empty = fine). The tests run this over every clip.
function KeyframeClip.validate(clip: any, name: string): { string }
	local problems = {}
	if type(clip) ~= "table" or type(clip.length) ~= "number" or clip.length <= 0 or type(clip.keys) ~= "table" then
		return { name .. ": not a clip" }
	end
	local last = -1
	for i, key in clip.keys do
		if type(key.t) ~= "number" or key.t < 0 or key.t > clip.length + 1e-6 then
			table.insert(problems, string.format("%s key %d: time outside 0..length", name, i))
		elseif key.t < last then
			table.insert(problems, string.format("%s key %d: keys out of order", name, i))
		else
			last = key.t
		end
		if key.ease ~= nil and not KeyframeClip.EASES[key.ease] then
			table.insert(problems, string.format("%s key %d: unknown ease %s", name, i, tostring(key.ease)))
		end
		for joint, values in key.pose or {} do
			if not KeyframeClip.JOINT_PARTS[joint] then
				table.insert(problems, string.format("%s key %d: unknown joint %s", name, i, tostring(joint)))
			elseif type(values) ~= "table" or #values < 3 or (#values > 3 and joint ~= "Root") then
				table.insert(problems, string.format("%s key %d: %s needs 3 angles (only Root may add a position)", name, i, joint))
			end
		end
	end
	if #clip.keys < 2 then
		table.insert(problems, name .. ": needs at least two keys")
	end
	return problems
end

return KeyframeClip
