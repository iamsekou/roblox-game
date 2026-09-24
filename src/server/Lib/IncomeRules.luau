-- Passive yen (owner, 2026-09-23): the rules, independent of Roblox services so they can be unit-tested.
--   * Playtime: every player in the server earns a flat amount every interval, in the lobby or a match.
--   * Friend booster: every interval, a player earns a set amount for each Roblox friend in the same server.
-- Each player's clocks start when they join. Systems/IncomeService applies these answers.
local IncomeRules = {}

-- How many payouts a clock owes at `now`, given its next payout is due at `nextAt`, and when the one after
-- that is due. A server that stalled past several due times pays each missed interval once.
function IncomeRules.due(nextAt: number, now: number, interval: number): (number, number)
	if now < nextAt or interval <= 0 then
		return 0, nextAt
	end
	local count = math.floor((now - nextAt) / interval) + 1
	return count, nextAt + count * interval
end

-- How many of `userId`'s friends are among `presentIds` (never counting themself).
function IncomeRules.countFriends(userId: number, presentIds: { number }, isFriend: (number, number) -> boolean): number
	local count = 0
	for _, other in presentIds do
		if other ~= userId and isFriend(userId, other) then
			count += 1
		end
	end
	return count
end

-- The friend booster for one payout: `perFriend` for each friend present.
function IncomeRules.friendBonus(friends: number, perFriend: number): number
	return math.max(0, math.floor(friends)) * perFriend
end

return IncomeRules
