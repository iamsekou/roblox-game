-- Hand-keyframed ability animations (Phase 3 item 8). The owner poses these in Studio's Animation Editor
-- and publishes them; paste each published id here (digits only, or "rbxassetid://..."). How to author
-- them: docs/ANIMATING.md.
--
-- Each ability has two clips:
--   windup  — plays during the tell / charge; it is sped up or slowed down to fit the cast time exactly
--             (a Looped clip plays at normal speed instead)
--   release — the strike, starting the moment the ability fires
-- A blank id falls back to the procedural placeholder pose (animations/Controllers/AbilityPoses) for that
-- clip, so ids can be filled in one at a time. Never invent an id: blank means "not authored yet".
-- Keys are the internal character ids (never shown to players).
local AnimationIds = {}

AnimationIds.ids = {
	Goku = { -- Gokai
		mild = { windup = "", release = "" }, -- Phase Shift
		ultimate = { windup = "", release = "" }, -- Energy Wave
	},
	Luffy = { -- Luffo
		mild = { windup = "", release = "" }, -- Stretch Grapple
		ultimate = { windup = "", release = "" }, -- Blitz Barrage (release should be a Looped flurry)
	},
	Krillin = { -- Krillo
		mild = { windup = "", release = "" }, -- Blinding Burst
		ultimate = { windup = "", release = "" }, -- Tracking Disc
	},
	Vegeta = { -- Vejaro
		mild = { windup = "", release = "" }, -- Rising Fury
		ultimate = { windup = "", release = "" }, -- Nova Blast
	},
	Zoro = { -- Zorin
		mild = { windup = "", release = "" }, -- Iron Guard (release should be a Looped stance)
		ultimate = { windup = "", release = "" }, -- Cyclone Cut
	},
	L = { -- Eli
		mild = { windup = "", release = "" }, -- Surveillance Camera
		ultimate = { windup = "", release = "" }, -- Deduction
	},
	Naruto = { -- Nariko
		mild = { windup = "", release = "" }, -- Mirror Decoy
		ultimate = { windup = "", release = "" }, -- Vortex Orb
	},
	Ichigo = { -- Ichiro
		mild = { windup = "", release = "" }, -- Blur Step
		ultimate = { windup = "", release = "" }, -- Crescent Wave
	},
	Sasuke = { -- Sazuki
		mild = { windup = "", release = "" }, -- Lightning Dash
		ultimate = { windup = "", release = "" }, -- Hunter's Eye
	},
	Gojo = { -- Gozen
		mild = { windup = "", release = "" }, -- Blink
		ultimate = { windup = "", release = "" }, -- Boundless
	},
	-- M1 click combo, shared by every fighter (owner request 2026-09-25). Wind-ups are squeezed to
	-- Constants.M1_WINDUP, so keep each windup clip short and snappy.
	Melee = {
		m1_1 = { windup = "", release = "" }, -- right jab
		m1_2 = { windup = "", release = "" }, -- left cross
		m1_3 = { windup = "", release = "" }, -- right hook
		m1_4 = { windup = "", release = "" }, -- uppercut finisher (launches)
		hit = { windup = "", release = "" }, -- flinch when punched (release only)
	},
}

-- The playable asset id for one clip, or nil when it hasn't been authored yet.
function AnimationIds.get(character: string, slot: string, clip: string): string?
	local byCharacter = AnimationIds.ids[character]
	local bySlot = byCharacter and byCharacter[slot]
	local raw = bySlot and bySlot[clip]
	if type(raw) == "number" then
		raw = tostring(raw)
	end
	if type(raw) ~= "string" then
		return nil
	end
	local digits = string.match(raw, "^%s*(%d+)%s*$") or string.match(raw, "^%s*rbxassetid://(%d+)%s*$")
	return if digits then "rbxassetid://" .. digits else nil
end

return AnimationIds
