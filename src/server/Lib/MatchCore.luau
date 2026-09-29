-- The rules of one round, independent of Roblox services so they can be unit-tested with fake ids.
-- Systems/RoundManager and Systems/EliminationService turn these results into deaths, yen,
-- respawns and remote events. Nothing in here yields, which is what makes eliminations
-- race-free: a check and its state change always happen in one uninterrupted step.
--
-- Visibility rule (spawn protection, approved): a fighter's codes exist only while they are
-- alive AND past their spawn-protection window. While protected they have no plate for anyone
-- and see no plates themselves; when protection ends, fresh codes are issued in both directions.
-- Dying wipes the fighter's own view, so numbers remembered from a previous life never work.
local CodeBook = require(script.Parent.CodeBook)

export type Participant = {
	id: number,
	team: string?,
	alive: boolean,
	protectedUntil: number?, -- set while spawn-protected
	inputLockedUntil: number, -- an ability's "can't type codes" lock (approved: at most maxInputLock)
	lifeId: number,
	strikes: number,
	score: number,
	lastSubmitAt: number,
	dueling: boolean?, -- locked in a clash duel: inside its force field, out of reach of codes (both ways)
}

export type Winner = {
	kind: "player" | "team" | "draw",
	id: number?,
	team: string?,
	reason: string,
}

export type SubmitResult = {
	status: string,
	-- "eliminated" | "wrong" | "self_eliminated" | "stale" | "teammate" | "protected" | "locked" | "clone"
	-- | "dueling" | "shielded" | "malformed" | "rate_limited" | "not_alive" | "not_in_match" | "round_over"
	targetId: number?,
	strikes: number?,
	strikesLeft: number?,
	winner: Winner?,
	decoyOwner: number?, -- set with "clone": whose Mirror Decoy was popped
}

export type Config = {
	mode: string, -- "FFA" | "Team6v6"
	maxPlayers: number,
	strikeLimit: number,
	debounce: number,
	staleWindow: number,
	reuseCooldown: number?,
	protectionSeconds: number?,
	maxInputLock: number?,
	codeLength: number,
	generator: ((observer: number, target: number) -> string)?,
	onCodeChange: ((observer: number, target: number, code: string?) -> ())?,
}

local MatchCore = {}
MatchCore.__index = MatchCore

function MatchCore.new(config: Config)
	return setmetatable({
		mode = config.mode,
		config = config,
		participants = {} :: { [number]: Participant },
		teamScores = {} :: { [string]: number },
		decoys = {} :: { [number]: { owner: number } }, -- Naruto's clones: ids below DECOY_ID_BASE, codes like any target
		nextDecoy = 0,
		ended = false,
		winner = nil :: Winner?,
		suddenDeath = false,
		codes = CodeBook.new({
			generator = config.generator,
			staleWindow = config.staleWindow,
			reuseCooldown = config.reuseCooldown,
			codeLength = config.codeLength,
			onChange = config.onCodeChange,
		}),
	}, MatchCore)
end

function MatchCore:count(): number
	local n = 0
	for _ in self.participants do
		n += 1
	end
	return n
end

function MatchCore:canJoin(): boolean
	return not self.ended and self:count() < self.config.maxPlayers
end

-- Alive and past spawn protection: the only state in which a fighter has a plate and sees plates.
function MatchCore:isActive(id: number): boolean
	local p = self.participants[id]
	return p ~= nil and p.alive and p.protectedUntil == nil
end

-- Adds a participant who has not spawned yet. Codes flow only once they spawn and their
-- protection ends (see releaseProtection).
function MatchCore:addParticipant(id: number, team: string?, _now: number): boolean
	if self.participants[id] then
		return true
	end
	if not self:canJoin() then
		return false
	end
	self.participants[id] = {
		id = id,
		team = team,
		alive = false,
		protectedUntil = nil,
		inputLockedUntil = -math.huge,
		lifeId = 0,
		strikes = 0,
		score = 0,
		lastSubmitAt = -math.huge,
	}
	if team and self.teamScores[team] == nil then
		self.teamScores[team] = 0
	end
	self.codes:addObserver(id)
	return true
end

-- Team battle: a team scores (and can lead or tie) from the start, even before anyone joins it.
function MatchCore:addTeam(team: string)
	if self.teamScores[team] == nil then
		self.teamScores[team] = 0
	end
end

-- A fighter left. In sudden death the leader is re-checked (audit fix, 2026-09-28): if a tied fighter or team
-- leaves, whoever is now the sole leader wins at once instead of the round expiring as a draw.
-- Returns the winner if that ended the round.
function MatchCore:removeParticipant(id: number, now: number): Winner?
	if not self.participants[id] then
		return nil
	end
	self:_removeDecoysOf(id, now)
	self.codes:retireTarget(id, now)
	self.codes:removeObserver(id)
	self.participants[id] = nil
	if self.ended then
		return nil
	end
	return self:_checkWin()
end

-- Team battle: the only team that still has fighters, or nil (FFA, nobody left, or two teams still in it).
function MatchCore:soleTeam(): string?
	if self.mode ~= "Team6v6" then
		return nil
	end
	local found: string? = nil
	for _, p in self.participants do
		if p.team then
			if found == nil then
				found = p.team
			elseif p.team ~= found then
				return nil
			end
		end
	end
	return found
end

-- Team battle: every fighter on the other side left (audit fix, 2026-09-28). The team still standing wins by
-- forfeit, whatever the score: a team with nobody left can't win or keep a round alive.
function MatchCore:endByForfeit(team: string): Winner
	return self:_finish({ kind = "team", team = team, reason = "forfeit" })
end

-- Replaces `observer`'s codes for `targets` with new ones (the old ones answer "stale": no strike, no kill).
-- Used when the observer learned them from somewhere they weren't allowed to be (the movement check pulled
-- them back). Targets the observer holds no code for are skipped. Returns how many were replaced.
function MatchCore:reissue(observer: number, targets: { number }, now: number): number
	local replaced = 0
	for _, target in targets do
		if self.codes:getCode(observer, target) then
			self.codes:issue(observer, target, now)
			replaced += 1
		end
	end
	return replaced
end

-- Clash duels (owner request 2026-09-29): the two fighters float inside a force field while they type digits.
-- Meanwhile codes can't touch them (a code for a duelist answers "shielded", no strike) and they can't submit
-- codes ("dueling"). Only alive fighters can be put in a duel. Returns whether the flag is now as asked.
function MatchCore:setDueling(id: number, on: boolean): boolean
	local p = self.participants[id]
	if not p or (on and not p.alive) then
		return false
	end
	p.dueling = if on then true else nil
	return true
end

-- The duel's loser is eliminated, credited to the winner (nil = nobody, e.g. the other side left): the same
-- scoring as a code elimination. Returns (whether anyone was eliminated, the round's winner if that ended it).
function MatchCore:eliminateByClash(winnerId: number?, loserId: number, now: number): (boolean, Winner?)
	if self.ended then
		return false, nil
	end
	local loser = self.participants[loserId]
	if not loser or not loser.alive then
		return false, nil
	end
	self:_endLife(loserId, now)
	local w = if winnerId then self.participants[winnerId] else nil
	if w then
		w.dueling = nil
		w.score += 1
		if w.team then
			self.teamScores[w.team] = (self.teamScores[w.team] or 0) + 1
		end
	end
	return true, self:_checkWin()
end

-- Forgets retired codes whose reuse cooldown is over (keeps a long round's bookkeeping small).
function MatchCore:purge(now: number)
	self.codes:purgeStale(now)
end

-- Starts a new life: strikes reset and spawn protection begins. Returns the new lifeId,
-- or nil if the player can't spawn. With protectionSeconds = 0 the fighter is visible at once.
function MatchCore:spawn(id: number, now: number): number?
	local p = self.participants[id]
	if not p or self.ended then
		return nil
	end
	local protection = self.config.protectionSeconds or 0
	p.alive = true
	p.strikes = 0
	p.lifeId += 1
	p.lastSubmitAt = -math.huge
	p.inputLockedUntil = -math.huge
	p.protectedUntil = now + protection
	if protection <= 0 then
		self:releaseProtection(id, now)
	end
	return p.lifeId
end

-- Ends spawn protection: everyone active gets a brand-new code for this fighter, and this
-- fighter gets brand-new codes for everyone active. Returns true if protection was lifted.
function MatchCore:releaseProtection(id: number, now: number): boolean
	local p = self.participants[id]
	if self.ended or not p or not p.alive or p.protectedUntil == nil then
		return false
	end
	p.protectedUntil = nil
	for otherId in self.participants do
		if otherId ~= id and self:isActive(otherId) then
			self.codes:issue(otherId, id, now) -- they can see me
			self.codes:issue(id, otherId, now) -- I can see them
		end
	end
	for decoyId, decoy in self.decoys do
		if decoy.owner ~= id then
			self.codes:issue(id, decoyId, now) -- and everyone else's clones
		end
	end
	return true
end

-- Any end of a life: nobody can see this fighter, and this fighter can see nobody.
function MatchCore:_endLife(id: number, now: number)
	local p = self.participants[id]
	p.alive = false
	p.protectedUntil = nil
	p.dueling = nil
	self:_removeDecoysOf(id, now)
	self.codes:retireTarget(id, now)
	self.codes:retireView(id, now)
end

-- Decoys (Naruto's Mirror Decoy, approved): a clone is a target with its own code for every active
-- observer except its owner. Typing a clone's code pops it: no strike, no kill, no credit.
-- Returns the decoy's id, or nil if the owner isn't active. Decoy ids live far below any user id:
-- live user ids are positive, but Studio's local test players are -1, -2, ... so small negatives are taken.
local DECOY_ID_BASE = -1000000000

function MatchCore:addDecoy(ownerId: number, now: number): number?
	if self.ended or not self:isActive(ownerId) then
		return nil
	end
	self.nextDecoy += 1
	local decoyId = DECOY_ID_BASE - self.nextDecoy
	self.decoys[decoyId] = { owner = ownerId }
	for id in self.participants do
		if id ~= ownerId and self:isActive(id) then
			self.codes:issue(id, decoyId, now)
		end
	end
	return decoyId
end

function MatchCore:removeDecoy(decoyId: number, now: number)
	if self.decoys[decoyId] then
		self.decoys[decoyId] = nil
		self.codes:retireTarget(decoyId, now)
	end
end

function MatchCore:_removeDecoysOf(ownerId: number, now: number)
	for decoyId, decoy in self.decoys do
		if decoy.owner == ownerId then
			self:removeDecoy(decoyId, now)
		end
	end
end

-- Deaths that aren't eliminations (fell into the void, reset): no credit to anyone.
function MatchCore:markDead(id: number, now: number)
	local p = self.participants[id]
	if not p or not p.alive then
		return
	end
	self:_endLife(id, now)
end

function MatchCore:isTeammate(a: number, b: number): boolean
	if self.mode ~= "Team6v6" then
		return false
	end
	local pa, pb = self.participants[a], self.participants[b]
	return pa ~= nil and pb ~= nil and pa.team ~= nil and pa.team == pb.team
end

-- Unique leader (player id in FFA, team name in team mode), or nils on a tie at the top.
function MatchCore:leader(): (number?, string?, number)
	if self.mode == "Team6v6" then
		local bestTeam, best, tie = nil, -1, false
		for team, score in self.teamScores do
			if score > best then
				bestTeam, best, tie = team, score, false
			elseif score == best then
				tie = true
			end
		end
		if tie then
			return nil, nil, best
		end
		return nil, bestTeam, best
	end
	local bestId, best, tie = nil, -1, false
	for id, p in self.participants do
		if p.score > best then
			bestId, best, tie = id, p.score, false
		elseif p.score == best then
			tie = true
		end
	end
	if tie then
		return nil, nil, best
	end
	return bestId, nil, best
end

function MatchCore:_finish(winner: Winner): Winner
	if self.ended then
		return self.winner
	end
	self.ended = true
	self.winner = winner
	return winner
end

function MatchCore:_winnerFrom(id: number?, team: string?, reason: string): Winner
	return { kind = if team then "team" else "player", id = id, team = team, reason = reason }
end

-- Rounds are time-based with uncapped eliminations (owner, 2026-09-23: no "first to 20"). The only
-- win an elimination can trigger is during sudden death, when the first sole leader takes it.
function MatchCore:_checkWin(): Winner?
	local id, team = self:leader()
	if self.suddenDeath and (id or team) then
		return self:_finish(self:_winnerFrom(id, team, "sudden_death"))
	end
	return nil
end

-- The time cap was reached: a sole leader with at least one elimination wins, otherwise sudden death.
function MatchCore:resolveTimeCap(): Winner?
	if self.ended then
		return self.winner
	end
	local id, team, best = self:leader()
	if (id or team) and best > 0 then
		return self:_finish(self:_winnerFrom(id, team, "time_cap"))
	end
	self.suddenDeath = true
	return nil
end

function MatchCore:endAsDraw(reason: string): Winner
	return self:_finish({ kind = "draw", reason = reason })
end

-- An ability's input lock: the fighter can't submit codes for seconds (capped at maxInputLock).
-- Only active fighters can be locked: spawn-protected ones are immune (approved ground rule 5).
-- Locks never shorten an existing one. Returns true if the fighter is now locked.
function MatchCore:lockInput(id: number, now: number, seconds: number): boolean
	if self.ended or not self:isActive(id) or seconds <= 0 then
		return false
	end
	local p = self.participants[id]
	local until_ = now + math.min(seconds, self.config.maxInputLock or seconds)
	p.inputLockedUntil = math.max(p.inputLockedUntil, until_)
	return true
end

-- The heart of the game. `rawCode` comes straight from a client and is treated as hostile.
function MatchCore:submit(observerId: number, rawCode: any, now: number): SubmitResult
	if self.ended then
		return { status = "round_over" }
	end
	local p = self.participants[observerId]
	if not p then
		return { status = "not_in_match" }
	end
	if not p.alive then
		return { status = "not_alive" }
	end
	if p.protectedUntil ~= nil then
		return { status = "protected" } -- can't strike while hidden; never a strike
	end
	if now < p.inputLockedUntil then
		return { status = "locked" } -- an ability jammed their input; never a strike
	end
	if p.dueling then
		return { status = "dueling" } -- typing the duel's digits, not codes; never a strike
	end
	if
		typeof(rawCode) ~= "string"
		or #rawCode ~= self.config.codeLength
		or string.match(rawCode, "^%d+$") == nil
	then
		return { status = "malformed" } -- never a strike: the real UI can't produce this
	end
	if now - p.lastSubmitAt < self.config.debounce then
		return { status = "rate_limited" } -- never a strike
	end
	p.lastSubmitAt = now

	local kind, targetId = self.codes:lookup(observerId, rawCode, now)
	local decoy = kind == "live" and targetId and self.decoys[targetId]
	if decoy then
		if self:isTeammate(observerId, decoy.owner) then
			return { status = "teammate", targetId = targetId }
		end
		self:removeDecoy(targetId :: number, now)
		return { status = "clone", targetId = targetId, decoyOwner = decoy.owner } -- popped; never a strike
	end
	if kind == "live" and targetId and targetId ~= observerId then
		local target = self.participants[targetId]
		if target and target.alive then
			if self:isTeammate(observerId, targetId) then
				return { status = "teammate", targetId = targetId } -- a real number they saw; not a strike
			end
			if target.dueling then
				return { status = "shielded", targetId = targetId } -- inside a clash's force field; not a strike
			end
			-- Check-and-set with no yield in between: a second submission for this target (even in
			-- the same frame) finds it dead with its codes retired, so it can never be credited twice.
			self:_endLife(targetId, now)
			p.score += 1
			if p.team then
				self.teamScores[p.team] = (self.teamScores[p.team] or 0) + 1
			end
			return { status = "eliminated", targetId = targetId, winner = self:_checkWin() }
		end
		return { status = "stale", targetId = targetId }
	elseif kind == "stale" then
		return { status = "stale", targetId = targetId } -- someone got them first; no strike
	end

	-- A code that means nothing to this observer: a strike.
	p.strikes += 1
	if p.strikes >= self.config.strikeLimit then
		self:_endLife(observerId, now)
		return { status = "self_eliminated", strikes = p.strikes, strikesLeft = 0 }
	end
	return { status = "wrong", strikes = p.strikes, strikesLeft = self.config.strikeLimit - p.strikes }
end

return MatchCore
