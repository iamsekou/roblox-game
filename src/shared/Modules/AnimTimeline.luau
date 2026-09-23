-- Pure timeline of one ability cast animation (Phase 3 item 8). No engine calls, unit-tested.
--   windup  — from the cast until the server's cast time runs out (the tell / charge)
--   release — the strike: snaps from the wind-up pose into the release pose, then holds it
--   fade    — blends back to the fighter's normal animation
-- `weight` is how strongly the cast pose overrides the normal animation (0..1); `mix` is how far the
-- wind-up pose has turned into the release pose (0..1).
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

function AnimTimeline.total(timing: Timing): number
	return timing.windup + timing.hold + timing.blendOut
end

function AnimTimeline.sample(timing: Timing, t: number): Sample
	t = math.max(t, 0)
	local blendIn = ramp(t, timing.blendIn)
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
			weight = blendIn * (1 - f / timing.blendOut),
		}
	end
	return { phase = "done", windupT = timing.windup, releaseT = timing.hold, mix = 1, weight = 0 }
end

return AnimTimeline
