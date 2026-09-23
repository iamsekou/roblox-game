-- Pure timeline of one ability cast animation (Phase 3 item 8). No engine calls, unit-tested.
--   windup  — from the cast until the server's cast time runs out (the tell / charge)
--   release — the strike: snaps from the wind-up pose into the release pose, then holds it
--   fade    — blends back to the fighter's normal animation
-- `weight` is how strongly the cast pose overrides the normal animation (0..1, eased in and out); `mix` is
-- how far the wind-up pose's target has turned into the release pose's (0..1). The joints then follow
-- their targets through springs (Modules/Spring), which is what makes the motion itself fluid.
local AnimTimeline = {}

export type Timing = {
	windup: number,
	hold: number,
	blendIn: number,
	snap: number,
	blendOut: number,
}

export type Sample = {
	phase: string, -- "windup" | "release" | "fade" | "done"
	windupT: number, -- seconds into the wind-up (frozen at its end afterwards)
	releaseT: number, -- seconds into the release (frozen at the hold's end while fading)
	mix: number,
	weight: number,
}

local function ramp(t: number, seconds: number): number
	if seconds <= 0 then
		return 1
	end
	return math.clamp(t / seconds, 0, 1)
end

-- Smoothstep: eases in and out, so blends start and finish gently instead of with a visible kink.
function AnimTimeline.smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

function AnimTimeline.total(timing: Timing): number
	return timing.windup + timing.hold + timing.blendOut
end

function AnimTimeline.sample(timing: Timing, t: number): Sample
	t = math.max(t, 0)
	local blendIn = AnimTimeline.smooth(ramp(t, timing.blendIn))
	if t < timing.windup then
		return { phase = "windup", windupT = t, releaseT = 0, mix = 0, weight = blendIn }
	end
	local r = t - timing.windup
	if r < timing.hold then
		return { phase = "release", windupT = timing.windup, releaseT = r, mix = ramp(r, timing.snap), weight = blendIn }
	end
	local f = r - timing.hold
	if f < timing.blendOut then
		return {
			phase = "fade",
			windupT = timing.windup,
			releaseT = timing.hold,
			mix = 1,
			weight = blendIn * (1 - AnimTimeline.smooth(f / timing.blendOut)),
		}
	end
	return { phase = "done", windupT = timing.windup, releaseT = timing.hold, mix = 1, weight = 0 }
end

return AnimTimeline
