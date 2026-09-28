-- Unit tests for Modules/KeyframeClip (keyframed fight animations as data), and a check of every authored
-- clip in ReplicatedStorage.Animations.Clips.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local KeyframeClip = require(ReplicatedStorage.Shared.Modules.KeyframeClip)
local T = require(script.Parent.TestUtil)

local tests = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

local function near(a: number, b: number, what: string)
	T.truthy(math.abs(a - b) < 1e-4, string.format("%s: expected %.4f, got %.4f", what, b, a))
end

local CLIP = {
	length = 1,
	keys = {
		{ t = 0, pose = { Waist = { 0, 0, 0 }, Neck = { 10, 0, 0 } } },
		{ t = 0.5, ease = "hold", pose = { Waist = { 40, -20, 0 } } },
		{ t = 1, pose = { Waist = { 0, 0, 0 }, Neck = { 30, 0, 0 } } },
	},
}

test("[CLIP] keys are hit exactly; linear in between", function()
	local at0 = KeyframeClip.sample(CLIP, 0)
	near(at0.Waist[1], 0, "start")
	local mid = KeyframeClip.sample(CLIP, 0.25)
	near(mid.Waist[1], 20, "halfway to the second key")
	near(mid.Waist[2], -10, "every axis")
	near(KeyframeClip.sample(CLIP, 0.5).Waist[1], 40, "on the second key")
end)

test("[CLIP] a joint left out of a key eases straight from its previous key to its next", function()
	near(KeyframeClip.sample(CLIP, 0.5).Neck[1], 20, "Neck isn't in the middle key")
end)

test("[CLIP] 'hold' stays put until the next key (an impact frame)", function()
	near(KeyframeClip.sample(CLIP, 0.99).Waist[1], 40, "held")
	near(KeyframeClip.sample(CLIP, 1).Waist[1], 0, "then jumps")
end)

test("[CLIP] eases: in starts slow, out starts fast, all end on the key", function()
	T.truthy(KeyframeClip.ease("in", 0.5) < 0.5, "in")
	T.truthy(KeyframeClip.ease("out", 0.5) > 0.5, "out")
	for _, style in { "linear", "in", "out", "inout" } do
		near(KeyframeClip.ease(style, 0), 0, style .. " at 0")
		near(KeyframeClip.ease(style, 1), 1, style .. " at 1")
	end
end)

test("[CLIP] looped clips wrap; others hold their ends", function()
	local looped = { length = 1, looped = true, keys = CLIP.keys }
	near(KeyframeClip.sample(looped, 1.25).Waist[1], 20, "wrapped to 0.25")
	near(KeyframeClip.sample(CLIP, 5).Neck[1], 30, "past the end: last key")
	near(KeyframeClip.sample(CLIP, -1).Neck[1], 10, "before the start: first key")
end)

test("[CLIP] Root positions move the body; angles compose like the placeholder poses", function()
	local cf = KeyframeClip.toCFrame({ 0, 90, 0, 0, -1, 0.5 })
	T.truthy(cf.Position:FuzzyEq(Vector3.new(0, -1, 0.5)), "position")
	T.truthy(cf.LookVector:FuzzyEq(Vector3.new(-1, 0, 0), 1e-4), "rotated 90 degrees about Y")
	T.truthy(KeyframeClip.toCFrame({ 10, 20, 30 }) == CFrame.Angles(math.rad(10), math.rad(20), math.rad(30)), "same as CFrame.Angles")
end)

test("[CLIP] validation catches bad data", function()
	T.eq(#KeyframeClip.validate(CLIP, "ok"), 0, "a good clip")
	T.truthy(#KeyframeClip.validate({ length = 1, keys = { { t = 0, pose = { Elbow = { 0, 0, 0 } } }, { t = 1, pose = {} } } }, "x") > 0, "unknown joint")
	T.truthy(#KeyframeClip.validate({ length = 1, keys = { { t = 0.6, pose = {} }, { t = 0.2, pose = {} } } }, "x") > 0, "out of order")
	T.truthy(#KeyframeClip.validate({ length = 1, keys = { { t = 0, pose = { Waist = { 0, 0, 0, 1, 0, 0 } } }, { t = 1, pose = {} } } }, "x") > 0, "only Root moves")
end)

test("[CLIP] dense clips (baked in Blender) sample the same as the general path", function()
	local dense = { length = 1, dense = true, keys = {} }
	for i = 0, 10 do
		local x = i / 10
		table.insert(dense.keys, { t = x, pose = { Waist = { x * 30, -x * 10, 0 }, Root = { 0, 0, 0, 0, -x, 0 } } })
	end
	local general = table.clone(dense)
	general.dense = nil
	for _, t in { -0.5, 0, 0.05, 0.37, 0.5, 0.999, 1, 3 } do
		local a, b = KeyframeClip.sample(dense, t), KeyframeClip.sample(general, t)
		for joint, values in b do
			for i, v in values do
				near(a[joint][i], v, string.format("%s[%d] at %.2f", joint, i, t))
			end
		end
	end
end)

test("[CLIP] mirror swaps sides and flips the sideways axes", function()
	local m = KeyframeClip.mirror({ RightShoulder = { 90, 10, -20 }, Waist = { -5, 30, 4 }, Root = { 0, 12, 0, 0.4, -1, -0.2 } })
	T.eq(m.RightShoulder, nil)
	T.eq(m.LeftShoulder[1], 90)
	T.eq(m.LeftShoulder[2], -10)
	T.eq(m.LeftShoulder[3], 20)
	T.eq(m.Waist[2], -30, "twist flips")
	T.eq(m.Root[4], -0.4, "sideways shift flips")
	T.eq(m.Root[5], -1, "height stays")
end)

test("[CLIP] stance: standing is straight; a crouch plants each foot flat where asked", function()
	local L = KeyframeClip.LEG
	local stand = KeyframeClip.stance()
	near(stand.RightHip[1], 0, "straight hip")
	near(stand.RightKnee[1], 0, "straight knee")
	for _, spec in { { drop = 0.6, right = -0.5, left = 0.6, pitch = -15 }, { drop = 0.3, forward = 0.4, right = -0.5, left = 0.2 } } do
		local s = KeyframeClip.stance(spec)
		for side, reach in { Right = spec.right, Left = spec.left } do
			-- Forward kinematics in the side view: angles add along the leg, +X swings forward.
			local a1 = math.rad(spec.pitch or 0) + math.rad(s[side .. "Hip"][1])
			local a2 = a1 + math.rad(s[side .. "Knee"][1])
			local ahead = L.thigh * math.sin(a1) + L.shin * math.sin(a2)
			local down = L.thigh * math.cos(a1) + L.shin * math.cos(a2)
			near(down, L.hip - spec.drop - L.ankle, side .. " ankle reaches the ground")
			near(ahead, reach - (spec.forward or 0), side .. " ankle lands where asked")
			near((spec.pitch or 0) + s[side .. "Hip"][1] + s[side .. "Knee"][1] + s[side .. "Ankle"][1], 0, side .. " foot flat")
		end
	end
end)

test("[CLIP] every authored clip is valid", function()
	local folder = ReplicatedStorage:FindFirstChild("Animations") and ReplicatedStorage.Animations:FindFirstChild("Clips")
	T.truthy(folder ~= nil, "Animations.Clips exists")
	local problems, count = {}, 0
	for _, module in folder:GetChildren() do
		if module:IsA("ModuleScript") then
			for slot, pair in require(module) do
				for _, which in { "windup", "release" } do
					if pair[which] then
						count += 1
						for _, p in KeyframeClip.validate(pair[which], module.Name .. "." .. slot .. "." .. which) do
							table.insert(problems, p)
						end
					end
				end
			end
		end
	end
	T.truthy(count > 0, "no clips found")
	T.eq(#problems, 0, table.concat(problems, "; "))
end)

return tests
