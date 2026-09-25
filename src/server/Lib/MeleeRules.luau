-- M1 rules (owner request 2026-09-25). Pure: no engine calls, so every rule is unit-tested.
--
-- Combo: each click throws the next punch of a 4-hit combo. A punch too soon after the last is refused;
-- one long after the last starts the combo over; after the finisher there's a short rest.
--
-- Trades: when two fighters punch each other within TRADE_WINDOW seconds, that's a trade. Trades between
-- the same pair in a row (each within CHAIN_GAP of the last, with no one-sided punch between them) build a
-- chain; the chain reaching TRADES_TO_CLASH starts a clash and the count goes back to zero.
local MeleeRules = {}

export type Params = {
	interval: number, -- min seconds between punches
	comboLength: number,
	comboReset: number, -- a punch this long after the last restarts the combo
	endlag: number, -- extra rest after the finisher
	tradeWindow: number,
	chainGap: number,
	tradesToClash: number,
}

type Fighter = { lastSwing: number, combo: number, restUntil: number }
type Pair = { pending: { by: number, t: number }?, trades: number, lastTrade: number }

export type State = {
	fighters: { [number]: Fighter },
	pairs: { [string]: Pair },
}

function MeleeRules.new(): State
	return { fighters = {}, pairs = {} }
end

local function pairKey(a: number, b: number): string
	if a > b then
		a, b = b, a
	end
	return a .. ":" .. b
end

-- A click at time `t`. Returns the combo step (1..comboLength) of the punch it throws, or nil and why
-- ("too_soon" or "resting").
function MeleeRules.swing(state: State, id: number, t: number, params: Params): (number?, string?)
	local f = state.fighters[id]
	if not f then
		f = { lastSwing = -math.huge, combo = 0, restUntil = -math.huge }
		state.fighters[id] = f
	end
	if t < f.restUntil then
		return nil, "resting"
	end
	if t - f.lastSwing < params.interval then
		return nil, "too_soon"
	end
	if t - f.lastSwing > params.comboReset or f.combo >= params.comboLength then
		f.combo = 0
	end
	f.combo += 1
	f.lastSwing = t
	if f.combo >= params.comboLength then
		f.restUntil = t + params.interval + params.endlag
	end
	return f.combo, nil
end

-- `attacker`'s punch landed on `victim` at time `t`. Returns (traded, tradesInChain, clash): whether this
-- punch completed a trade, how long the chain now is, and whether the pair should clash now.
function MeleeRules.hit(state: State, attacker: number, victim: number, t: number, params: Params): (boolean, number, boolean)
	local key = pairKey(attacker, victim)
	local pair = state.pairs[key]
	if not pair then
		pair = { pending = nil, trades = 0, lastTrade = -math.huge }
		state.pairs[key] = pair
	end
	if t - pair.lastTrade > params.chainGap then
		pair.trades = 0 -- too long since the last trade: the chain cooled off
	end
	local pending = pair.pending
	if pending and pending.by ~= attacker and t - pending.t <= params.tradeWindow then
		-- Their punch landed on us a moment ago and ours lands now: a trade.
		pair.pending = nil
		pair.trades += 1
		pair.lastTrade = t
		if pair.trades >= params.tradesToClash then
			pair.trades = 0
			return true, params.tradesToClash, true
		end
		return true, pair.trades, false
	end
	if pending then
		-- The earlier punch went unanswered (or it was this fighter again): a one-sided exchange breaks the chain.
		pair.trades = 0
	end
	pair.pending = { by = attacker, t = t }
	return false, pair.trades, false
end

-- Drop a fighter (they left, or their clash began and the slate should be clean).
function MeleeRules.forget(state: State, id: number)
	state.fighters[id] = nil
	local tag = tostring(id)
	for key in state.pairs do
		local a, b = string.match(key, "^(%-?%d+):(%-?%d+)$")
		if a == tag or b == tag then
			state.pairs[key] = nil
		end
	end
end

-- Reset a pair's trade count (a clash between them just ended).
function MeleeRules.resetPair(state: State, a: number, b: number)
	state.pairs[pairKey(a, b)] = nil
end

return MeleeRules
