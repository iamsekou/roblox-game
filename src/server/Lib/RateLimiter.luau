-- A per-player request throttle (audit fix, 2026-09-28): at most one request per `interval` seconds per key.
-- A refused request changes nothing, so a flood can't push the next legitimate request further away.
-- Pure: the caller passes the time, so it runs in the unit tests.
local RateLimiter = {}

export type Limiter = { interval: number, last: { [any]: number } }

function RateLimiter.new(interval: number): Limiter
	return { interval = interval, last = {} }
end

-- True (and recorded) if `key` may make a request at `now`.
function RateLimiter.allow(limiter: Limiter, key: any, now: number): boolean
	local last = limiter.last[key]
	if last ~= nil and now - last < limiter.interval then
		return false
	end
	limiter.last[key] = now
	return true
end

function RateLimiter.forget(limiter: Limiter, key: any)
	limiter.last[key] = nil
end

return RateLimiter
