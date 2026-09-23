-- Unit tests for Lib/MatchCore (round rules), using the real values from Constants.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MatchCore = require(script.Parent.Parent.Lib.MatchCore)
local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local T = require(script.Parent.TestUtil)

-- Deterministic codes: observer o sees target t as "OOTT" (e.g. observer 3 sees player 2 as "0302").
local function codeFor(o: number, t: number): string
	return string.format("%02d%02d", o, t)
end

-- A match whose listed players have spawned and finished spawn protection at t = 0.
local function newMatch(mode: string?, ids: { number }?, opts: { [string]: any }?)
	local options = opts or {}
	local m = MatchCore.new({
		mode = mode or "FFA",
		maxPlayers = Constants.MAX_PLAYERS,
		strikeLimit = Constants.WRONG_SUBMISSION_LIMIT,
		debounce = Constants.SUBMISSION_DEBOUNCE,
		staleWindow = Constants.STALE_CODE_GRACE,
		reuseCooldown = Constants.CODE_REUSE_COOLDOWN,
		protectionSeconds = Constants.SPAWN_PROTECTION_SECONDS,
		maxInputLock = Constants.MAX_INPUT_LOCK,
		codeLength = Constants.CODE_LENGTH,
		generator = options.generator or (if options.random then nil else codeFor),
	})
	for _, id in ids or {} do
		m:addParticipant(id, options.teams and options.teams[id] or nil, 0)
	end
	for _, id in ids or {} do
		m:spawn(id, 0)
	end
	if not options.keepProtected then
		for _, id in ids or {} do
			m:releaseProtection(id, 0)
		end
	end
	return m
end

-- Respawn and run out the protection window straight away (for tests about other rules).
local function respawn(m: any, id: number, t: number)
	m:spawn(id, t)
	m:releaseProtection(id, t)
end

local tests = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

test("[AT4] a correct code eliminates the target and credits exactly one elimination", function()
	local m = newMatch("FFA", { 1, 2, 3 })
	local r = m:submit(1, codeFor(1, 2), 1)
	T.eq(r.status, "eliminated")
	T.eq(r.targetId, 2)
	T.eq(m.participants[1].score, 1)
	T.eq(m.participants[2].alive, false)
	-- Same code again, and another observer's (now retired) code for the same victim: no second credit.
	T.eq(m:submit(1, codeFor(1, 2), 2).status, "stale")
	T.eq(m:submit(3, codeFor(3, 2), 3).status, "stale")
	T.eq(m.participants[1].score, 1)
	T.eq(m.participants[3].score, 0)
end)

test("[AT1] another observer's code for the same target does not work for you", function()
	local m = newMatch("FFA", { 1, 2, 3 })
	local r = m:submit(1, codeFor(3, 2), 1) -- "0302": what player 3 sees above player 2
	T.eq(r.status, "wrong")
	T.eq(m.participants[2].alive, true)
end)

test("[AT1] ...unless it independently matches your own assignment", function()
	-- Players 1 and 3 happen to both see player 2 as "4444". Resolution is always per observer.
	local m = newMatch("FFA", { 1, 2, 3 }, {
		generator = function(o, t)
			return if t == 2 then "4444" else codeFor(o, t)
		end,
	})
	T.eq(m.codes:getCode(1, 2), "4444")
	T.eq(m.codes:getCode(3, 2), "4444")
	local r = m:submit(1, "4444", 1)
	T.eq(r.status, "eliminated")
	T.eq(r.targetId, 2)
end)

test("[AT3] you cannot eliminate yourself with the number others see on you", function()
	local m = newMatch("FFA", { 1, 2 })
	T.eq(m.codes:getCode(1, 1), nil, "no self code exists")
	local r = m:submit(1, codeFor(2, 1), 1) -- the code player 2 sees above player 1
	T.eq(r.status, "wrong")
	T.eq(m.participants[1].alive, true)
	T.eq(m.participants[1].score, 0)
end)

test("[AT3] teammates are never valid targets (and it is not a strike)", function()
	local m = newMatch("Team6v6", { 1, 2, 3 }, { teams = { [1] = "Red", [2] = "Red", [3] = "Blue" } })
	local r = m:submit(1, codeFor(1, 2), 1)
	T.eq(r.status, "teammate")
	T.eq(m.participants[2].alive, true)
	T.eq(m.participants[1].strikes, 0)
	T.eq(m:submit(1, codeFor(1, 3), 2).status, "eliminated")
	T.eq(m.teamScores.Red, 1)
end)

test("[AT3] a pre-respawn code never hits the respawned target", function()
	local m = newMatch("FFA", { 1, 2 })
	local old = m.codes:getCode(1, 2)
	T.eq(m:submit(1, old, 1).status, "eliminated")
	respawn(m, 2, 2)
	local new = m.codes:getCode(1, 2)
	T.truthy(new ~= nil and new ~= old, "fresh code after respawn")
	T.eq(m:submit(1, old, 3).status, "stale", "inside the grace window: a harmless 'already down'")
	T.eq(m.participants[2].alive, true)
	T.eq(m:submit(1, old, 3 + Constants.STALE_CODE_GRACE + 1).status, "wrong", "after the window: an ordinary wrong code")
	T.eq(m.participants[2].alive, true)
	T.eq(m.participants[1].score, 1)
end)

test("[PROTECT] a respawned fighter has no plate for anyone and sees none while protected", function()
	local m = newMatch("FFA", { 1, 2, 3 })
	T.eq(m:submit(1, codeFor(1, 2), 1).status, "eliminated")
	m:spawn(2, 4)
	T.eq(m.codes:getCode(1, 2), nil, "player 1 can't see the respawned player")
	T.eq(m.codes:getCode(3, 2), nil, "player 3 can't see the respawned player")
	T.eq(#m.codes:snapshot(2), 0, "the respawned player sees nobody")
	local r = m:submit(2, codeFor(2, 1), 5)
	T.eq(r.status, "protected", "no striking while hidden")
	T.eq(m.participants[2].strikes, 0, "and it is not a strike")
	T.eq(m.participants[1].alive, true)
	T.eq(m:releaseProtection(2, 4 + Constants.SPAWN_PROTECTION_SECONDS), true)
	T.truthy(m.codes:getCode(1, 2) ~= nil and m.codes:getCode(3, 2) ~= nil, "visible to everyone again")
	T.truthy(m.codes:getCode(2, 1) ~= nil and m.codes:getCode(2, 3) ~= nil, "sees everyone again")
end)

test("[PROTECT] dying wipes your view, so numbers remembered from the last life never land", function()
	local m = newMatch("FFA", { 1, 2, 3 })
	local remembered = m.codes:getCode(1, 3)
	T.eq(m:submit(2, codeFor(2, 1), 1).status, "eliminated") -- player 2 takes player 1 out
	T.eq(#m.codes:snapshot(1), 0, "a dead player's plates all disappear")
	respawn(m, 1, 5)
	T.truthy(m.codes:getCode(1, 3) ~= remembered, "a fresh code for the same target")
	T.eq(m:submit(1, remembered, 20).status, "wrong")
	T.eq(m.participants[3].alive, true)
end)

test("[PROTECT] two protected fighters only see each other once both are released", function()
	local m = newMatch("FFA", { 1, 2, 3 })
	T.eq(m:submit(3, codeFor(3, 1), 1).status, "eliminated")
	T.eq(m:submit(3, codeFor(3, 2), 2).status, "eliminated")
	m:spawn(1, 4)
	m:spawn(2, 4)
	m:releaseProtection(1, 7)
	T.truthy(m.codes:getCode(1, 3) ~= nil and m.codes:getCode(3, 1) ~= nil, "1 and 3 see each other")
	T.eq(m.codes:getCode(1, 2), nil, "2 is still hidden from 1")
	T.eq(m.codes:getCode(3, 2), nil, "2 is still hidden from 3")
	m:releaseProtection(2, 7.5)
	T.truthy(m.codes:getCode(1, 2) ~= nil and m.codes:getCode(2, 1) ~= nil, "both released: 1 and 2 see each other")
end)

test("[PROTECT] round start: nobody sees anyone until protection ends", function()
	local m = newMatch("FFA", { 1, 2, 3 }, { keepProtected = true })
	for id = 1, 3 do
		T.eq(#m.codes:snapshot(id), 0, "player " .. id .. " sees nobody yet")
	end
	for id = 1, 3 do
		m:releaseProtection(id, 3)
	end
	for id = 1, 3 do
		T.eq(#m.codes:snapshot(id), 2, "player " .. id .. " sees both opponents")
	end
end)

test("[STRIKE] 1st wrong code warns, 2nd wrong code self-eliminates with no credit to anyone", function()
	local m = newMatch("FFA", { 1, 2 })
	local r1 = m:submit(1, "9999", 1)
	T.eq(r1.status, "wrong")
	T.eq(r1.strikesLeft, 1)
	T.eq(m.participants[1].alive, true)
	local r2 = m:submit(1, "9998", 2)
	T.eq(r2.status, "self_eliminated")
	T.eq(m.participants[1].alive, false)
	T.eq(m.participants[1].score, 0)
	T.eq(m.participants[2].score, 0)
	T.eq(m.codes:getCode(2, 1), nil, "their code is retired like any death")
	T.eq(m:submit(1, codeFor(1, 2), 3).status, "not_alive")
end)

test("[STRIKE] a correct second guess after a miss eliminates the target, not you", function()
	local m = newMatch("FFA", { 1, 2 })
	T.eq(m:submit(1, "9999", 1).status, "wrong")
	local r = m:submit(1, codeFor(1, 2), 2)
	T.eq(r.status, "eliminated")
	T.eq(m.participants[1].alive, true)
	T.eq(m.participants[1].strikes, 1, "the earlier miss still counts for this life")
end)

test("[STRIKE] strikes reset on respawn", function()
	local m = newMatch("FFA", { 1, 2 })
	T.eq(m:submit(1, "9999", 1).status, "wrong")
	T.eq(m:submit(2, codeFor(2, 1), 2).status, "eliminated") -- player 2 takes player 1 out
	respawn(m, 1, 3)
	T.eq(m.participants[1].strikes, 0)
	T.eq(m:submit(1, "9999", 4).status, "wrong")
	T.eq(m.participants[1].alive, true)
end)

test("[AT12] malformed, forged and flooded submissions never count", function()
	local m = newMatch("FFA", { 1, 2 })
	T.eq(m:submit(1, nil, 1).status, "malformed")
	for _, bad in { 1234, "123", "12345", "12a4", " 123", "0102 ", "１２３４", {}, true } do
		T.eq(m:submit(1, bad, 1).status, "malformed", "input " .. tostring(bad))
	end
	T.eq(m.participants[1].strikes, 0)
	T.eq(m.participants[2].alive, true)
	T.eq(m:submit(1, "9999", 10).status, "wrong")
	T.eq(m:submit(1, "9998", 10.1).status, "rate_limited", "inside the debounce window")
	T.eq(m.participants[1].strikes, 1, "rate-limited submissions are not strikes")
	T.eq(m:submit(99, codeFor(1, 2), 20).status, "not_in_match", "a non-participant can't submit")
	T.eq(m.participants[2].alive, true)
end)

-- Owner rule (2026-09-23): no elimination target. Rounds only end on time (or too few players).
local UNCAPPED_KILLS = 60 -- far past the old "first to 20"

test("[AT5] FFA eliminations are uncapped: no score ends the round; the time cap crowns the leader", function()
	local m = newMatch("FFA", { 1, 2, 3 })
	local t = 0
	for i = 1, UNCAPPED_KILLS do
		t += 1
		local last = m:submit(1, m.codes:getCode(1, 2), t)
		T.eq(last.status, "eliminated", "kill " .. i)
		T.eq(last.winner, nil, "no winner from score alone (kill " .. i .. ")")
		t += 1
		respawn(m, 2, t)
	end
	T.eq(m.ended, false)
	T.eq(m.participants[1].score, UNCAPPED_KILLS)
	local w = m:resolveTimeCap()
	T.truthy(w and w.kind == "player" and w.id == 1 and w.reason == "time_cap", "player 1 wins at the cap")
	T.eq(m:submit(3, m.codes:getCode(3, 1) or "0301", t + 1).status, "round_over")
	T.eq(m:spawn(2, t + 2), nil, "no respawns once the round is over")
end)

test("[AT5] team eliminations are uncapped; the team total decides at the time cap", function()
	local m = newMatch("Team6v6", { 1, 2, 3 }, { teams = { [1] = "Red", [2] = "Red", [3] = "Blue" } })
	local t = 0
	for i = 1, UNCAPPED_KILLS do
		t += 1
		local shooter = if i % 2 == 0 then 2 else 1
		local last = m:submit(shooter, m.codes:getCode(shooter, 3), t)
		T.eq(last.status, "eliminated")
		T.eq(last.winner, nil, "no winner from score alone")
		t += 1
		respawn(m, 3, t)
	end
	T.eq(m.teamScores.Red, UNCAPPED_KILLS)
	local w = m:resolveTimeCap()
	T.truthy(w and w.kind == "team" and w.team == "Red", "Red wins on the team total at the cap")
end)

test("[AT6] a match never exceeds 12 participants", function()
	local m = newMatch("FFA", {})
	for id = 1, Constants.MAX_PLAYERS do
		T.eq(m:addParticipant(id, nil, 0), true)
	end
	T.eq(m:canJoin(), false)
	T.eq(m:addParticipant(13, nil, 0), false)
	T.eq(m:count(), Constants.MAX_PLAYERS)
	m:removeParticipant(5, 1)
	T.eq(m:canJoin(), true)
	T.eq(m:addParticipant(13, nil, 1), true)
	T.eq(m:count(), Constants.MAX_PLAYERS)
end)

test("[AT6] a mid-round joiner sees everyone, and is seen, once their protection ends", function()
	local m = newMatch("FFA", { 1, 2, 3 }, { random = true })
	m:addParticipant(4, nil, 5)
	m:spawn(4, 6)
	T.eq(#m.codes:snapshot(4), 0, "hidden and blind while protected")
	T.eq(m.codes:getCode(1, 4), nil, "not targetable while protected")
	m:releaseProtection(4, 9)
	T.eq(#m.codes:snapshot(4), 3)
	for _, o in { 1, 2, 3 } do
		T.truthy(m.codes:getCode(o, 4) ~= nil, "observer " .. o .. " sees the joiner")
	end
end)

test("a leaver disappears from every observer's view", function()
	local m = newMatch("FFA", { 1, 2, 3 }, { random = true })
	m:removeParticipant(2, 1)
	T.eq(m.codes:getCode(1, 2), nil)
	T.eq(m.codes:getCode(3, 2), nil)
	T.eq(m.participants[2], nil)
end)

test("time cap: a sole leader wins; a tie goes to sudden death, won by the next sole leader", function()
	local m = newMatch("FFA", { 1, 2, 3 })
	m:submit(1, m.codes:getCode(1, 3), 1)
	respawn(m, 3, 2)
	local w = m:resolveTimeCap()
	T.truthy(w and w.id == 1 and w.reason == "time_cap", "player 1 leads alone")

	local m2 = newMatch("FFA", { 1, 2, 3 })
	m2:submit(1, m2.codes:getCode(1, 3), 1)
	respawn(m2, 3, 2)
	m2:submit(2, m2.codes:getCode(2, 3), 3)
	respawn(m2, 3, 4)
	T.eq(m2:resolveTimeCap(), nil, "1-1 tie at the top")
	T.eq(m2.suddenDeath, true)
	T.eq(m2.ended, false)
	local r = m2:submit(3, m2.codes:getCode(3, 1), 5) -- now 1-1-1: still tied
	T.eq(r.winner, nil)
	respawn(m2, 1, 6)
	r = m2:submit(2, m2.codes:getCode(2, 1), 7) -- player 2 reaches 2: sole leader
	T.truthy(r.winner and r.winner.id == 2 and r.winner.reason == "sudden_death", "sudden-death winner")
end)

test("sudden death that expires is a draw", function()
	local m = newMatch("FFA", { 1, 2 })
	T.eq(m:resolveTimeCap(), nil)
	local w = m:endAsDraw("sudden_death_expired")
	T.eq(w.kind, "draw")
	T.eq(m.ended, true)
	T.eq(m:submit(1, m.codes:getCode(1, 2) or "0102", 1).status, "round_over")
end)

test("[LOCK] an ability's input lock rejects submissions without a strike, then lifts", function()
	local m = newMatch("FFA", { 1, 2 })
	T.eq(m:lockInput(1, 10, 2), true)
	local r = m:submit(1, m.codes:getCode(1, 2), 11)
	T.eq(r.status, "locked")
	T.eq(m.participants[1].strikes, 0, "a lock is never a strike")
	T.eq(m.participants[2].alive, true)
	T.eq(m:submit(1, m.codes:getCode(1, 2), 12).status, "eliminated", "lock over at 12")
end)

test("[LOCK] locks are capped at the approved maximum and never shortened", function()
	local m = newMatch("FFA", { 1, 2 })
	m:lockInput(1, 0, 30)
	T.eq(m.participants[1].inputLockedUntil, Constants.MAX_INPUT_LOCK, "capped")
	m:lockInput(1, 0, 0.5)
	T.eq(m.participants[1].inputLockedUntil, Constants.MAX_INPUT_LOCK, "a shorter lock doesn't cut it short")
end)

test("[LOCK] spawn-protected and dead fighters can't be locked; a new life starts unlocked", function()
	local m = newMatch("FFA", { 1, 2 }, { keepProtected = true })
	T.eq(m:lockInput(1, 0, 2), false, "protected")
	m:releaseProtection(1, 3)
	m:releaseProtection(2, 3)
	T.eq(m:lockInput(1, 3, 2), true)
	m:markDead(1, 4)
	T.eq(m:lockInput(1, 4, 2), false, "dead")
	m:spawn(1, 4.5)
	T.eq(m.participants[1].inputLockedUntil, -math.huge, "fresh life, no lock")
end)

test("[CLONE] a Shadow Clone gets its own code for every other active fighter, not its owner", function()
	local m = newMatch("FFA", { 1, 2, 3 }, { random = true })
	local decoy = m:addDecoy(1, 1)
	T.truthy(decoy and decoy <= -1000000000, "far from any user id (Studio test players are -1, -2, ...)")
	T.eq(m.codes:getCode(1, decoy), nil, "the owner has no code for their own clone")
	T.truthy(m.codes:getCode(2, decoy) ~= nil and m.codes:getCode(3, decoy) ~= nil)
	T.truthy(m.codes:getCode(2, decoy) ~= m.codes:getCode(2, 1), "the clone's code differs from Naruto's")
end)

test("[CLONE] typing a clone's code pops it: no strike, no kill, no credit", function()
	local m = newMatch("FFA", { 1, 2 }, { random = true })
	local decoy = m:addDecoy(1, 1)
	local r = m:submit(2, m.codes:getCode(2, decoy), 2)
	T.eq(r.status, "clone")
	T.eq(r.decoyOwner, 1)
	T.eq(m.participants[2].strikes, 0)
	T.eq(m.participants[2].score, 0)
	T.eq(m.participants[1].alive, true)
	T.eq(m.decoys[decoy], nil, "popped")
end)

test("[CLONE] clones vanish when their owner dies, and late joiners see existing clones", function()
	local m = newMatch("FFA", { 1, 2 }, { random = true })
	m:addParticipant(3, nil, 1)
	m:spawn(3, 1)
	local decoy = m:addDecoy(1, 1)
	T.eq(m.codes:getCode(3, decoy), nil, "3 is still protected")
	m:releaseProtection(3, 4)
	T.truthy(m.codes:getCode(3, decoy) ~= nil, "3 sees the clone once protection ends")
	m:markDead(1, 5)
	T.eq(m.decoys[decoy], nil)
	T.eq(m.codes:getCode(2, decoy), nil, "codes retired with it")
end)

test("[CLONE] Studio test players (negative user ids) and clones never collide", function()
	-- Test -> Clients and Servers gives players user ids -1, -2, -3.
	local m = newMatch("FFA", { -1, -2, -3 }, { random = true })
	local decoy = m:addDecoy(-1, 1)
	T.truthy(decoy ~= nil and m.participants[decoy] == nil, "the clone's id is nobody's user id")
	T.eq(m:submit(-2, m.codes:getCode(-2, decoy), 2).status, "clone")
	local r = m:submit(-2, m.codes:getCode(-2, -3), 3)
	T.eq(r.status, "eliminated", "negative-id players eliminate each other normally")
	T.eq(r.targetId, -3)
end)
return tests
