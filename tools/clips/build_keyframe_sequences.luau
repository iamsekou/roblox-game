-- Builds a KeyframeSequence for every keyframed clip (ReplicatedStorage.Animations.Clips) into
-- ServerStorage.AnimationWork.Clips, ready for the owner to publish (docs/ANIMATING.md, "Publishing the
-- keyframed clips"). Run it in Studio's command bar in Edit mode (Claude runs it through the Studio tools).
-- Re-running replaces the sequences with the same names.
--
-- Each clip is baked: sampled at 60 frames a second plus every key's exact time, all Linear. That way the
-- published animation matches what the game plays from the data exactly (Roblox's own pose easing differs from
-- the clip format's, and its In/Out directions are reversed from TweenService's).
-- Poses nest by body part (HumanoidRootPart > LowerTorso > UpperTorso > ...). A part the clip never moves gets a
-- structural pose with Weight 0, so it never overrides the running animation.
--
-- Not synced by Rojo (tools/). The clip modules are cloned before requiring, so edits made since the last run
-- are picked up even though Studio caches modules required from the command bar.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local KeyframeClip = require(ReplicatedStorage.Shared.Modules.KeyframeClip:Clone())
local FPS = 60

-- Parent part of every R15 part in the pose tree.
local PARENT_PART = {
	LowerTorso = "HumanoidRootPart",
	UpperTorso = "LowerTorso",
	Head = "UpperTorso",
	RightUpperArm = "UpperTorso",
	RightLowerArm = "RightUpperArm",
	RightHand = "RightLowerArm",
	LeftUpperArm = "UpperTorso",
	LeftLowerArm = "LeftUpperArm",
	LeftHand = "LeftLowerArm",
	RightUpperLeg = "LowerTorso",
	RightLowerLeg = "RightUpperLeg",
	RightFoot = "RightLowerLeg",
	LeftUpperLeg = "LowerTorso",
	LeftLowerLeg = "LeftUpperLeg",
	LeftFoot = "LeftLowerLeg",
}
local PART_JOINT = {}
for joint, part in KeyframeClip.JOINT_PARTS do
	PART_JOINT[part] = joint
end

local function jointsOf(clip): { [string]: boolean }
	local set = {}
	for _, key in clip.keys do
		for joint in key.pose do
			set[joint] = true
		end
	end
	return set
end

local function sampleTimes(clip): { number }
	local times, seen = {}, {}
	local function add(t)
		local k = math.floor(t * 10000 + 0.5)
		if not seen[k] then
			seen[k] = true
			table.insert(times, t)
		end
	end
	for i = 0, math.floor(clip.length * FPS + 1e-6) do
		add(i / FPS)
	end
	for _, key in clip.keys do
		add(key.t)
		-- a "hold" jumps at the next key: bake the moment just before it too, so the jump stays a jump
		if key.ease == "hold" then
			for _, other in clip.keys do
				if other.t > key.t then
					add(math.max(key.t, other.t - 0.002))
					break
				end
			end
		end
	end
	add(clip.length)
	table.sort(times)
	return times
end

local function buildSequence(name: string, clip): KeyframeSequence
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = name
	sequence.Loop = clip.looped == true
	sequence.Priority = Enum.AnimationPriority.Action
	local animated = jointsOf(clip)
	-- Every part on the path from an animated part up to the root needs a pose.
	local needed = { HumanoidRootPart = true }
	for joint in animated do
		local part = KeyframeClip.JOINT_PARTS[joint]
		while part and not needed[part] do
			needed[part] = true
			part = PARENT_PART[part]
		end
	end
	for _, t in sampleTimes(clip) do
		local values = KeyframeClip.sample(clip, t)
		local keyframe = Instance.new("Keyframe")
		keyframe.Time = t
		local poses = {}
		local function poseFor(part: string): Pose
			if poses[part] then
				return poses[part]
			end
			local pose = Instance.new("Pose")
			pose.Name = part
			pose.EasingStyle = Enum.PoseEasingStyle.Linear
			local joint = PART_JOINT[part]
			local v = joint and values[joint]
			if v then
				pose.CFrame = KeyframeClip.toCFrame(v)
				pose.Weight = 1
			else
				pose.CFrame = CFrame.identity
				pose.Weight = 0 -- structure only: never overrides the running animation
			end
			poses[part] = pose
			local parent = PARENT_PART[part]
			pose.Parent = if parent then poseFor(parent) else keyframe
			return pose
		end
		for part in needed do
			poseFor(part)
		end
		keyframe.Parent = sequence
	end
	return sequence
end

local work = ServerStorage:FindFirstChild("AnimationWork") or Instance.new("Folder")
work.Name = "AnimationWork"
work.Parent = ServerStorage
local out = work:FindFirstChild("Clips") or Instance.new("Folder")
out.Name = "Clips"
out.Parent = work

local built = {}
for _, module in ReplicatedStorage.Animations.Clips:GetChildren() do
	if module:IsA("ModuleScript") then
		local clips = require(module:Clone())
		for slot, pair in clips do
			for _, which in { "windup", "release" } do
				local clip = pair[which]
				if clip then
					local name = string.format("%s_%s_%s", module.Name, slot, which)
					local old = out:FindFirstChild(name)
					if old then
						old:Destroy()
					end
					local sequence = buildSequence(name, clip)
					sequence.Parent = out
					table.insert(built, string.format("%s (%.2f s%s, %d frames)", name, clip.length, if clip.looped then ", looped" else "", #sequence:GetChildren()))
				end
			end
		end
	end
end
table.sort(built)
return string.format("built %d KeyframeSequences in ServerStorage.AnimationWork.Clips:\n%s", #built, table.concat(built, "\n"))
