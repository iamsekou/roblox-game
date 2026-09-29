-- The clash duel (owner request 2026-09-29: "single-digit numbers keep popping up one at a time, and you have
-- to type them one at a time. First person to mess up dies"). Pure: no services, so it runs in the unit tests.
--
--   * Each fighter gets their own stream of single digits (never the same digit twice in a row), one at a time.
--   * Each digit must be typed within its window. Windows shrink step by step (`decay`) down to `minWindow`,
--     so the duel speeds up: "more and more" numbers.
--   * Typing the wrong digit, or letting the window run out, is a mistake. The first mistake (by time) loses.
--     `grace` covers network lag: an answer arriving that much after the window still counts, and a timeout
--     is only a mistake once the grace has passed too.
--   * Both making their mistake at the same instant (both timing out on a matching deadline) is a draw.
local DuelRules = {}

export type Params = {
	firstWindow: number, -- seconds for the first digit
	decay: number, -- each next window = the previous x this
	minWindow: number, -- windows never shrink below this
	grace: number, -- seconds of network slack
}

export type Fighter = {
	step: number, -- the digit being asked for (1, 2, ...)
	digit: number,
	deadline: number, -- when this digit's window closes
	failedAt: number?, -- when this fighter made their mistake
	typed: number, -- digits typed correctly so far
}

export type State = {
	params: Params,
	fighters: { [number]: Fighter },
	order: { number },
	nextDigit: (id: number, step: number, previous: number?) -> number,
}

export type Result = { winner: number?, loser: number?, draw: boolean }

function DuelRules.window(params: Params, step: number): number
	return math.max(params.minWindow, params.firstWindow * params.decay ^ (step - 1))
end

-- A digit source: a random digit 0-9, never the one just shown (so a repeat never looks like a missed update).
function DuelRules.randomDigits(rng: Random): (number, number, number?) -> number
	return function(_id: number, _step: number, previous: number?): number
		local digit = rng:NextInteger(0, 9)
		if digit == previous then
			digit = (digit + rng:NextInteger(1, 9)) % 10
		end
		return digit
	end
end

-- A duel between `ids`, starting at `now` (the first digits appear then).
function DuelRules.new(ids: { number }, now: number, params: Params, nextDigit: (number, number, number?) -> number): State
	local state: State = { params = params, fighters = {}, order = table.clone(ids), nextDigit = nextDigit }
	for _, id in ids do
		state.fighters[id] = {
			step = 1,
			digit = nextDigit(id, 1, nil),
			deadline = now + DuelRules.window(params, 1),
			failedAt = nil,
			typed = 0,
		}
	end
	return state
end

-- Marks every fighter whose window (plus grace) has run out.
function DuelRules.tick(state: State, now: number)
	for _, f in state.fighters do
		if f.failedAt == nil and now >= f.deadline + state.params.grace then
			f.failedAt = f.deadline + state.params.grace
		end
	end
end

-- A fighter typed `digit` for step `step` at `now`. Returns:
--   "ok"     correct: the fighter moves on to the next digit
--   "wrong"  a mistake (wrong digit, or too late)
--   "stale"  an answer for a step that's already over (a duplicate or delayed message): ignored
--   "over"   this fighter has already made their mistake, or isn't in the duel
function DuelRules.input(state: State, id: number, step: any, digit: any, now: number): string
	local f = state.fighters[id]
	if not f or f.failedAt ~= nil then
		return "over"
	end
	if type(step) ~= "number" or step ~= f.step then
		return "stale"
	end
	if now >= f.deadline + state.params.grace then
		f.failedAt = f.deadline + state.params.grace
		return "wrong"
	end
	if type(digit) ~= "number" or digit ~= f.digit then
		f.failedAt = now
		return "wrong"
	end
	f.typed += 1
	f.step += 1
	f.digit = state.nextDigit(id, f.step, f.digit)
	f.deadline = now + DuelRules.window(state.params, f.step)
	return "ok"
end

-- The outcome so far: nil while nobody has made a mistake. The earliest mistake loses; a tie is a draw.
function DuelRules.result(state: State, now: number): Result?
	DuelRules.tick(state, now)
	local first: number? = nil
	local firstAt = math.huge
	local tie = false
	for _, id in state.order do
		local at = state.fighters[id].failedAt
		if at ~= nil then
			if at < firstAt then
				first, firstAt, tie = id, at, false
			elseif at == firstAt then
				tie = true
			end
		end
	end
	if first == nil then
		return nil
	end
	if tie then
		return { winner = nil, loser = nil, draw = true }
	end
	local winner = nil
	for _, id in state.order do
		if id ~= first then
			winner = id
		end
	end
	return { winner = winner, loser = first, draw = false }
end

return DuelRules
