-- Kill leaderboards (owner-approved 2026-09-23). Pure, unit-tested.
-- The saved boards (DataStore top lists) lag behind the game by up to a flush interval, so the boards
-- shown to players merge in the kills made on this server that haven't been saved yet ("+live").
local LeaderboardRules = {}

export type Entry = { userId: number, kills: number }
export type Row = { userId: number, kills: number, live: number, rank: number, delta: number? }

-- stored: saved entries, best first. pending: unsaved kills per user. known: a user's saved total when
-- they aren't in `stored` (e.g. a player on this server ranked below the fetched top list).
function LeaderboardRules.merge(stored: { Entry }, pending: { [number]: number }, known: { [number]: number }?): { Row }
	local rows: { Row } = {}
	local seen: { [number]: boolean } = {}
	local order: { [number]: number } = {}
	for i, entry in stored do
		if not seen[entry.userId] then
			seen[entry.userId] = true
			order[entry.userId] = i
			local live = pending[entry.userId] or 0
			table.insert(rows, { userId = entry.userId, kills = entry.kills + live, live = live, rank = 0 })
		end
	end
	for userId, live in pending do
		if not seen[userId] and live > 0 then
			seen[userId] = true
			order[userId] = math.huge
			local saved = if known then known[userId] or 0 else 0
			table.insert(rows, { userId = userId, kills = saved + live, live = live, rank = 0 })
		end
	end
	-- Most kills first; ties keep the saved order, then the lower user id (so it never flickers).
	table.sort(rows, function(a, b)
		if a.kills ~= b.kills then
			return a.kills > b.kills
		end
		if order[a.userId] ~= order[b.userId] then
			return order[a.userId] < order[b.userId]
		end
		return a.userId < b.userId
	end)
	for i, row in rows do
		row.rank = i
	end
	return rows
end

-- Movement since the last refresh: positive = climbed that many places; nil = new on the board.
function LeaderboardRules.withChanges(rows: { Row }, previous: { [number]: number }): { Row }
	for _, row in rows do
		local before = previous[row.userId]
		row.delta = if before then before - row.rank else nil
	end
	return rows
end

-- userId -> rank, for the next refresh's comparison.
function LeaderboardRules.ranks(rows: { Row }): { [number]: number }
	local ranks = {}
	for _, row in rows do
		ranks[row.userId] = row.rank
	end
	return ranks
end

return LeaderboardRules
