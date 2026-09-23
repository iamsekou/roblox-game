-- Procedural placeholder poses for every ability (Phase 3 item 8). Each move is modelled on how the
-- character performs it in their show (owner direction, 2026-09-23); a hand-keyframed clip from
-- Modules/AnimationIds replaces the wind-up or release pose as soon as its id is filled in.
--
-- A pose is { [jointName] = { x, y, z } } in degrees, applied to the R15 joint's Transform. Joints left
-- out keep the normal animation (legs are never posed, so fighters can still walk while casting).
-- A pose can also be a function(secondsIntoPhase) returning such a table, for moves that keep moving.
-- Axes measured in play on this place's R15 rigs (2026-09-23):
--   Shoulder  +X raises the arm forward (90 = straight ahead, 170 = overhead), -X swings it back.
--             Right arm +Z lifts it out to the side; left arm -Z lifts it out. The opposite sign crosses
--             the arm over the chest.
--   Elbow     +X bends the forearm (toward the front of the upper arm).
--   Waist     -X leans forward, +X leans back; +Y twists left, -Y right; +Z leans left.
--   Neck      +X tilts the head up, -X down; +Y turns it left, -Y right.
-- The angles compose (X, then Y, then Z about the turned axes), so a hand-to-face or hands-together pose
-- rarely has "obvious" numbers. Those were solved numerically against the rig's joint attachments for a
-- target hand position (forehead, mouth, eye, crossed wrists, hands meeting) and then checked in play.
--
-- Per move: windup (pose during the cast time), release (pose once it fires), and optionally
-- hold (seconds the release pose is held; default Constants.ANIM_DEFAULT_HOLD) and windupSeconds
-- (when the server's cast time also covers the effect, e.g. the Gatling flurry).
-- Sword moves also carry swords = { right = kind, left = kind, mouth = kind } (drawn for the cast, see Swords) and
-- trails = true to run the blade trails from the release until the fade.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Constants"))

local AbilityPoses = {}

-- Gokai ------------------------------------------------------------------------------------------

AbilityPoses.Goku = {
	-- Phase Shift: two fingers raised to the forehead, eyes shut, then gone. Lands in a ready crouch.
	mild = {
		windup = {
			RightShoulder = { 160, 60, -50 },
			RightElbow = { 20, 0, 0 },
			LeftShoulder = { 8, 0, -8 },
			Neck = { -8, 0, 0 },
		},
		release = {
			Waist = { -10, 0, 0 },
			RightShoulder = { 20, 0, 20 },
			RightElbow = { 45, 0, 0 },
			LeftShoulder = { 20, 0, -20 },
			LeftElbow = { 45, 0, 0 },
		},
		hold = 0.35,
	},
	-- Energy Wave: cupped hands drawn back to the right hip while the energy gathers, torso wound to the
	-- right, head still on the target; then both arms thrust straight out, palms together.
	ultimate = {
		windup = {
			Waist = { -8, -40, 0 },
			Neck = { 0, 35, 0 },
			RightShoulder = { -15, 0, -40 },
			RightElbow = { 100, 0, 0 },
			LeftShoulder = { 15, 0, 80 },
			LeftElbow = { 40, 0, 0 },
		},
		release = {
			Waist = { -12, 0, 0 },
			Neck = { 5, 0, 0 },
			RightShoulder = { 90, 0, -25 },
			RightElbow = { 0, 0, 0 },
			LeftShoulder = { 90, 0, 25 },
			LeftElbow = { 0, 0, 0 },
		},
		hold = 0.6,
	},
}

-- Luffo ------------------------------------------------------------------------------------------

AbilityPoses.Luffy = {
	-- Stretch Grapple: the right arm cocks back, then shoots out straight and stays out for the pull.
	mild = {
		windup = {
			Waist = { 0, -25, 0 },
			RightShoulder = { -45, 0, 10 },
			RightElbow = { 70, 0, 0 },
			LeftShoulder = { 40, 0, 0 },
			LeftElbow = { 40, 0, 0 },
		},
		release = {
			Waist = { -8, 25, 0 },
			RightShoulder = { 95, 0, 0 },
			RightElbow = { 0, 0, 0 },
			LeftShoulder = { -30, 0, 0 },
			LeftElbow = { 20, 0, 0 },
		},
		hold = 0.6,
	},
	-- Gatling Barrage: both fists drawn back, leaning into it; then a blur of alternating straight
	-- punches for the whole flurry, the torso rocking with each one.
	ultimate = {
		windupSeconds = Constants.LUFFY_GATLING_WINDUP,
		stiffness = 3.5, -- 7 punches a second: the joints must keep up or the flurry turns to mush
		windup = {
			Waist = { 10, 0, 0 },
			Neck = { 10, 0, 0 },
			RightShoulder = { -40, 0, 20 },
			RightElbow = { 110, 0, 0 },
			LeftShoulder = { -40, 0, -20 },
			LeftElbow = { 110, 0, 0 },
		},
		release = function(t: number)
			local s = math.sin(t * math.pi * 2 * 7) -- 7 punches a second per arm
			local right, left = math.max(s, 0), math.max(-s, 0)
			return {
				Waist = { -12, 14 * s, 0 },
				RightShoulder = { 30 + 60 * right, 0, -8 },
				RightElbow = { 110 - 110 * right, 0, 0 },
				LeftShoulder = { 30 + 60 * left, 0, 8 },
				LeftElbow = { 110 - 110 * left, 0, 0 },
			}
		end,
		hold = Constants.LUFFY_GATLING_DURATION,
	},
}

-- Krillo -----------------------------------------------------------------------------------------

AbilityPoses.Krillin = {
	-- Solar Flare: open hands raised either side of the face, then flung wide with the flash.
	mild = {
		windup = {
			Neck = { 5, 0, 0 },
			RightShoulder = { 20, 45, 120 },
			RightElbow = { 80, 0, 0 },
			LeftShoulder = { 20, -45, -120 },
			LeftElbow = { 80, 0, 0 },
		},
		release = {
			Waist = { 8, 0, 0 },
			Neck = { 12, 0, 0 },
			RightShoulder = { 100, 0, 40 },
			RightElbow = { 10, 0, 0 },
			LeftShoulder = { 100, 0, -40 },
			LeftElbow = { 10, 0, 0 },
		},
		hold = 0.5,
	},
	-- Tracking Disc: the right arm held straight up over the head with the disc spinning on the palm,
	-- then a side-arm throw across the body.
	ultimate = {
		windup = {
			Waist = { 8, 0, 0 },
			Neck = { 15, 0, 0 },
			RightShoulder = { 175, 0, 5 },
			RightElbow = { 5, 0, 0 },
			LeftShoulder = { 15, 0, -10 },
		},
		release = {
			Waist = { -18, 25, 0 },
			Neck = { 0, -20, 0 },
			RightShoulder = { 70, 0, -30 },
			RightElbow = { 10, 0, 0 },
			LeftShoulder = { -20, 0, 0 },
		},
		hold = 0.45,
	},
}

-- Vejaro -----------------------------------------------------------------------------------------

AbilityPoses.Vegeta = {
	-- Saiyan Pride: crouched, fists clenched and arms flexed as the power builds, then the chest-out,
	-- head-back roar as the aura flares.
	mild = {
		windup = {
			Waist = { -10, 0, 0 },
			Neck = { -10, 0, 0 },
			RightShoulder = { 10, 0, 30 },
			RightElbow = { 70, 0, 0 },
			LeftShoulder = { 10, 0, -30 },
			LeftElbow = { 70, 0, 0 },
		},
		release = {
			Waist = { 12, 0, 0 },
			Neck = { 20, 0, 0 },
			RightShoulder = { 0, 0, 40 },
			RightElbow = { 45, 0, 0 },
			LeftShoulder = { 0, 0, -40 },
			LeftElbow = { 45, 0, 0 },
		},
		hold = 0.7,
	},
	-- Big Bang Blast: one arm thrust straight out at the target, open palm, the other hand bracing the
	-- forearm; the release is the recoil of the blast.
	ultimate = {
		windup = {
			Waist = { 0, 15, 0 },
			Neck = { 0, -15, 0 },
			RightShoulder = { 90, 0, -5 },
			RightElbow = { 0, 0, 0 },
			LeftShoulder = { 80, 0, 60 },
			LeftElbow = { 0, 0, 0 },
		},
		release = {
			Waist = { 10, 15, 0 },
			Neck = { 0, -15, 0 },
			RightShoulder = { 115, 0, -5 },
			RightElbow = { 15, 0, 0 },
			LeftShoulder = { 95, 0, 60 },
			LeftElbow = { 0, 0, 0 },
		},
		hold = 0.5,
	},
}

-- Zorin ------------------------------------------------------------------------------------------

local ZORIN_GUARD = {
	Waist = { -12, 0, 0 },
	Neck = { 8, 0, 0 },
	RightShoulder = { 120, 30, -60 },
	RightElbow = { 0, 0, 0 },
	LeftShoulder = { 120, -30, 60 },
	LeftElbow = { 0, 0, 0 },
}

AbilityPoses.Zoro = {
	-- Iron Guard: blades crossed in front, braced forward, held for the whole stance.
	mild = {
		swords = { right = "KatanaRed", left = "KatanaDark", mouth = "Katana" },
		windup = ZORIN_GUARD,
		release = ZORIN_GUARD,
		hold = Constants.ZORO_GUARD_SECONDS,
	},
	-- Tornado Slash: blades raised crossed over the left shoulder, torso wound to the left; then a full
	-- spin with both arms flung wide that throws the tornado.
	ultimate = {
		swords = { right = "KatanaRed", left = "KatanaDark", mouth = "Katana" },
		trails = true,
		stiffness = 2.5, -- the spin is a full turn in 0.35 s
		windup = {
			Waist = { 0, 50, 0 },
			Neck = { 0, -40, 0 },
			RightShoulder = { 130, -15, -70 },
			RightElbow = { 0, 0, 0 },
			LeftShoulder = { 120, 0, 20 },
			LeftElbow = { 90, 0, 0 },
		},
		release = function(t: number)
			local spin = 50 - 360 * math.clamp(t / 0.35, 0, 1) -- one full turn, ending where it started
			return {
				Waist = { -10, spin, 0 },
				Neck = { 0, -40 * (1 - math.clamp(t / 0.35, 0, 1)), 0 },
				RightShoulder = { 20, 0, 80 },
				RightElbow = { 5, 0, 0 },
				LeftShoulder = { 20, 0, -80 },
				LeftElbow = { 5, 0, 0 },
			}
		end,
		hold = 0.55,
	},
}

-- Eli --------------------------------------------------------------------------------------------

AbilityPoses.L = {
	-- Surveillance Camera: a hunched stoop to set the camera down, then back to the slouch with a thumb
	-- at the lip.
	mild = {
		windup = {
			Waist = { -35, 0, 0 },
			Neck = { 25, 0, 0 },
			RightShoulder = { 45, 0, -5 },
			RightElbow = { 30, 0, 0 },
			LeftShoulder = { 5, 0, 0 },
		},
		release = {
			Waist = { -20, 0, 0 },
			Neck = { 12, 0, 0 },
			RightShoulder = { 120, 45, -50 },
			RightElbow = { 60, 0, 0 },
		},
		hold = 0.6,
	},
	-- Deduction: the thinking slouch — hunched, head tilted, thumb pressed to the lip, the other arm
	-- folded; then the head comes up when the answer lands.
	ultimate = {
		windup = {
			Waist = { -22, 0, 0 },
			Neck = { 14, 0, 10 },
			RightShoulder = { 150, 75, -50 },
			RightElbow = { 60, 0, 0 },
			LeftShoulder = { 50, 0, 60 },
			LeftElbow = { 0, 0, 0 },
		},
		release = {
			Waist = { -15, 0, 0 },
			Neck = { 18, 0, 0 },
			RightShoulder = { 130, 60, -40 },
			RightElbow = { 60, 0, 0 },
			LeftShoulder = { 50, 0, 60 },
			LeftElbow = { 0, 0, 0 },
		},
		hold = 0.9,
	},
}

-- Nariko -----------------------------------------------------------------------------------------

local NARIKO_SEAL = {
	Waist = { -5, 0, 0 },
	RightShoulder = { 70, 15, -50 },
	RightElbow = { 30, 0, 0 },
	LeftShoulder = { 70, -15, 50 },
	LeftElbow = { 30, 0, 0 },
}

AbilityPoses.Naruto = {
	-- Shadow Clone: the crossed-fingers hand seal in front of the chest, held as the clone appears.
	mild = {
		windup = NARIKO_SEAL,
		release = NARIKO_SEAL,
		hold = 0.3,
	},
	-- Spiral Sphere: the right palm held out low with the sphere forming, the left hand hovering over it
	-- shaping it; then the lunge, driving the right palm forward, left arm swept back.
	ultimate = {
		windup = {
			Waist = { -10, -25, 0 },
			Neck = { 0, 20, 0 },
			RightShoulder = { 0, 45, 20 },
			RightElbow = { 40, 0, 0 },
			LeftShoulder = { 50, 15, 70 },
			LeftElbow = { 0, 0, 0 },
		},
		release = {
			Waist = { -28, 15, 0 },
			Neck = { 18, 0, 0 },
			RightShoulder = { 90, 0, -5 },
			RightElbow = { 0, 0, 0 },
			LeftShoulder = { -45, 0, -10 },
			LeftElbow = { 10, 0, 0 },
		},
		hold = 0.5,
	},
}

-- Ichiro -----------------------------------------------------------------------------------------

AbilityPoses.Ichigo = {
	-- Flash Step: a low forward crouch, arms trailing; arrives with the blade arm out to the side.
	mild = {
		swords = { right = "Cleaver" },
		trails = true,
		windup = {
			Waist = { -30, 0, 0 },
			Neck = { 22, 0, 0 },
			RightShoulder = { -30, 0, 15 },
			RightElbow = { 20, 0, 0 },
			LeftShoulder = { -40, 0, -10 },
			LeftElbow = { 20, 0, 0 },
		},
		release = {
			Waist = { -12, 0, 0 },
			Neck = { 8, 0, 0 },
			RightShoulder = { 35, 0, 55 },
			RightElbow = { 10, 0, 0 },
			LeftShoulder = { -20, 0, 0 },
		},
		hold = 0.35,
	},
	-- Moon Fang Wave: the huge blade raised two-handed over the right shoulder while it charges, then
	-- one diagonal downward slash across the body that releases the wave.
	ultimate = {
		swords = { right = "Cleaver" },
		trails = true,
		windup = {
			Waist = { 8, -30, 0 },
			Neck = { 0, 25, 0 },
			RightShoulder = { 120, 45, 10 },
			RightElbow = { 50, 0, 0 },
			LeftShoulder = { 140, 15, 70 },
			LeftElbow = { 0, 0, 0 },
		},
		release = {
			Waist = { -20, 35, 0 },
			Neck = { 0, -25, 0 },
			RightShoulder = { 80, 30, -60 },
			RightElbow = { 0, 0, 0 },
			LeftShoulder = { 30, 0, 40 },
			LeftElbow = { 40, 0, 0 },
		},
		hold = 0.5,
	},
}

-- Sazuki -----------------------------------------------------------------------------------------

AbilityPoses.Sasuke = {
	-- Lightning Dash: crouched low with the crackling blade held down and back in the right hand, the
	-- left hand forward for balance; then the charge, blade driven straight ahead in a thrust.
	mild = {
		swords = { right = "Blade" },
		trails = true,
		windup = {
			Waist = { -25, -20, 0 },
			Neck = { 15, 20, 0 },
			RightShoulder = { -35, 0, 20 },
			RightElbow = { 15, 0, 0 },
			LeftShoulder = { 45, 0, 10 },
			LeftElbow = { 40, 0, 0 },
		},
		release = {
			Waist = { -30, 20, 0 },
			Neck = { 20, -15, 0 },
			RightShoulder = { 20, 0, -5 },
			RightElbow = { 0, 0, 0 },
			LeftShoulder = { -35, 0, -10 },
			LeftElbow = { 20, 0, 0 },
		},
		hold = 0.3,
	},
	-- Hunter's Eye: head bowed with a hand raised over one eye; then the head snaps up and the arm
	-- sweeps out, pointing at the marked opponent.
	ultimate = {
		windup = {
			Waist = { -8, 0, 0 },
			Neck = { -12, 0, 0 },
			RightShoulder = { 100, 15, -50 },
			RightElbow = { 60, 0, 0 },
		},
		release = {
			Neck = { 5, 0, 0 },
			RightShoulder = { 90, 0, -20 },
			RightElbow = { 0, 0, 0 },
		},
		hold = 0.6,
	},
}

-- Gozen ------------------------------------------------------------------------------------------

AbilityPoses.Gojo = {
	-- Blink: a relaxed, upright stance with two fingers raised in front of the chest.
	mild = {
		windup = {
			Waist = { 5, 0, 0 },
			Neck = { 5, 0, 0 },
			RightShoulder = { 90, 30, -40 },
			RightElbow = { 50, 0, 0 },
			LeftShoulder = { -5, 0, -5 },
		},
		release = {
			Waist = { 5, 0, 0 },
			RightShoulder = { 40, 0, -10 },
			RightElbow = { 60, 0, 0 },
		},
		hold = 0.25,
	},
	-- Infinity: the crossed-finger sign raised in front of the face; then the arms open, calm and
	-- unhurried, chin up, as the barrier forms.
	ultimate = {
		windup = {
			Waist = { 5, 0, 0 },
			Neck = { 5, 0, 0 },
			RightShoulder = { 110, -15, -60 },
			RightElbow = { 20, 0, 0 },
			LeftShoulder = { 15, 0, -10 },
		},
		release = {
			Waist = { 6, 0, 0 },
			Neck = { 10, 0, 0 },
			RightShoulder = { 25, 0, 40 },
			RightElbow = { 20, 0, 0 },
			LeftShoulder = { 25, 0, -40 },
			LeftElbow = { 20, 0, 0 },
		},
		hold = 1,
	},
}

-- Clashes (owner-approved 2026-09-23) -------------------------------------------------------------
-- When two fighters clash with the same attack, both play that attack's exchange for the whole clash
-- (no wind-up): sword fighters trade parries, beam users strain against each other, the Gatling pair
-- trade punches. Sword moves keep their swords (and trails) for the exchange.

local function tremble(t: number, degrees: number): number
	return math.sin(t * 63) * degrees
end

-- A snappy back-and-forth: -1..1, lingering at each end like a blow and its parry.
local function exchange(t: number, perSecond: number): number
	local s = math.sin(t * math.pi * 2 * perSecond)
	return math.sign(s) * math.abs(s) ^ 0.4
end

local function oneBladeExchange(t: number)
	local k = exchange(t, 2.5)
	local high = (1 + k) / 2 -- 1 = high cut, 0 = low cut
	return {
		Waist = { -10, -15 * k, 0 },
		Neck = { 6, 12 * k, 0 },
		RightShoulder = { 60 + 70 * high, 0, -20 - 20 * (1 - high) },
		RightElbow = { 30 * high, 0, 0 },
		LeftShoulder = { 30, 0, -10 },
		LeftElbow = { 40, 0, 0 },
	}
end

local CLASH_POSES: { [string]: (number) -> { [string]: { number } } } = {
	["Goku.ultimate"] = function(t) -- beam struggle: arms locked out, straining
		local j = tremble(t, 3)
		return {
			Waist = { -15, 0, 0 },
			Neck = { 5, 0, 0 },
			RightShoulder = { 90 + j, 0, -25 },
			RightElbow = { 0, 0, 0 },
			LeftShoulder = { 90 - j, 0, 25 },
			LeftElbow = { 0, 0, 0 },
		}
	end,
	["Vegeta.ultimate"] = function(t) -- blast against blast, bracing the arm
		local j = tremble(t, 3)
		return {
			Waist = { -12, 15, 0 },
			Neck = { 0, -15, 0 },
			RightShoulder = { 90 + j, 0, -5 },
			RightElbow = { 0, 0, 0 },
			LeftShoulder = { 80 - j, 0, 60 },
			LeftElbow = { 0, 0, 0 },
		}
	end,
	["Naruto.ultimate"] = function(t) -- spheres grinding: palm driven forward, the other hand bracing it
		local j = tremble(t, 4)
		return {
			Waist = { -20, 15, 0 },
			Neck = { 15, 0, 0 },
			RightShoulder = { 90 + j, 0, -5 },
			RightElbow = { 0, 0, 0 },
			LeftShoulder = { 80 - j, 0, 60 },
			LeftElbow = { 0, 0, 0 },
		}
	end,
	["Luffy.ultimate"] = AbilityPoses.Luffy.ultimate.release, -- fists meeting fists
	["Zoro.ultimate"] = function(t) -- three-sword exchange: the arms alternate crossing cuts
		local k = exchange(t, 2.5)
		local right, left = (1 + k) / 2, (1 - k) / 2
		return {
			Waist = { -10, -15 * k, 0 },
			Neck = { 6, 12 * k, 0 },
			RightShoulder = { 60 + 70 * right, 0, -20 - 30 * left },
			RightElbow = { 25 * right, 0, 0 },
			LeftShoulder = { 60 + 70 * left, 0, 20 + 30 * right },
			LeftElbow = { 25 * left, 0, 0 },
		}
	end,
	["Ichigo.mild"] = oneBladeExchange,
	["Ichigo.ultimate"] = oneBladeExchange,
	["Sasuke.mild"] = oneBladeExchange,
}

-- How far the second fighter's exchange runs behind the first: half a beat, so their blows meet (one
-- cuts high while the other cuts low, one fist lands as the other pulls back). Beam and sphere pairs
-- just strain out of step.
local COUNTER_OFFSET: { [string]: number } = {
	["Zoro.ultimate"] = 0.2, -- half of a 2.5-a-second exchange
	["Ichigo.mild"] = 0.2,
	["Ichigo.ultimate"] = 0.2,
	["Sasuke.mild"] = 0.2,
	["Luffy.ultimate"] = 1 / 14, -- half of a 7-a-second punch
	["Goku.ultimate"] = 0.05,
	["Vegeta.ultimate"] = 0.05,
	["Naruto.ultimate"] = 0.05,
}

-- Spring stiffness for the exchanges: fast repeating blows need snappier joints (see AbilityAnim).
local CLASH_STIFFNESS: { [string]: number } = {
	["Zoro.ultimate"] = 2.2,
	["Ichigo.mild"] = 2.2,
	["Ichigo.ultimate"] = 2.2,
	["Sasuke.mild"] = 2.2,
	["Luffy.ultimate"] = 3.5,
	["Goku.ultimate"] = 2.5, -- enough to let the straining tremble through
	["Vegeta.ultimate"] = 2.5,
	["Naruto.ultimate"] = 2.5,
}

-- The move a fighter plays for a clash over `character`.`slot` lasting `seconds`, or nil if that
-- ability never clashes. `counterOffset` is the second fighter's pose delay (see COUNTER_OFFSET).
function AbilityPoses.clashMove(character: string, slot: string, seconds: number): { [string]: any }?
	local key = character .. "." .. slot
	local pose = CLASH_POSES[key]
	if not pose then
		return nil
	end
	local byCharacter = AbilityPoses[character]
	local base = byCharacter and byCharacter[slot]
	return {
		windupSeconds = 0,
		release = pose,
		hold = seconds,
		swords = base and base.swords,
		trails = base ~= nil and base.swords ~= nil,
		counterOffset = COUNTER_OFFSET[key] or 0,
		stiffness = CLASH_STIFFNESS[key] or 1,
	}
end

return AbilityPoses
