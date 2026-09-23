-- Per-observer number assignment. Pure logic (no services), so it runs in unit tests in Studio.
--
-- Guarantees:
--   * Every observer has their own table. The same target has unrelated codes in different
--     observers' tables, and a code only ever means something to the observer who holds it.
--   * Within one observer's table every live code is unique. A code retired for that observer
--     is not reissued to them for `reuseCooldown` seconds, so a respawned target always gets a
--     fresh code and an old code can never land on the wrong person.
--   * Nobody ever holds a code for themself, so typing "your own number" can never target you.
--     (Players don't see a plate over their own head.)

export type Lookup = "live" | "stale" | "unknown"

export type Options = {
	generator: ((observer: number, target: number) -> string)?, -- tests inject deterministic codes
	staleWindow: number?, -- how long a retired code answers "stale" instead of "unknown"
	reuseCooldown: number?, -- how long a retired code is kept out of circulation for that observer
	codeLength: number?,
	onChange: ((observer: number, target: number, code: string?) -> ())?, -- code nil = removed
}

type StaleRecord = { target: number, expires: number, reuseUntil: number }

local MAX_RANDOM_ATTEMPTS = 64

local CodeBook = {}
CodeBook.__index = CodeBook

function CodeBook.new(options: Options?)
	local opts = options or {}
	local length = opts.codeLength or 4
	local staleWindow = opts.staleWindow or 5
	return setmetatable({
		_codes = {} :: { [number]: { [number]: string } }, -- observer -> target -> code
		_owners = {} :: { [number]: { [string]: number } }, -- observer -> code -> target
		_stale = {} :: { [number]: { [string]: StaleRecord } }, -- observer -> code -> retired record
		_generator = opts.generator,
		_staleWindow = staleWindow,
		_reuseCooldown = math.max(opts.reuseCooldown or 30, staleWindow),
		_onChange = opts.onChange,
		_length = length,
		_space = 10 ^ length,
		_format = "%0" .. length .. "d",
		_rng = Random.new(),
	}, CodeBook)
end

function CodeBook:_isTaken(observer: number, code: string, now: number): boolean
	if self._owners[observer][code] ~= nil then
		return true
	end
	local stale = self._stale[observer][code]
	return stale ~= nil and stale.reuseUntil > now
end

function CodeBook:_generate(observer: number, target: number, now: number): string
	for _ = 1, MAX_RANDOM_ATTEMPTS do
		local code = if self._generator
			then self._generator(observer, target)
			else string.format(self._format, self._rng:NextInteger(0, self._space - 1))
		if not self:_isTaken(observer, code, now) then
			return code
		end
	end
	-- Only reachable with a test generator that keeps colliding: walk the space from a random start.
	local start = self._rng:NextInteger(0, self._space - 1)
	for i = 0, self._space - 1 do
		local code = string.format(self._format, (start + i) % self._space)
		if not self:_isTaken(observer, code, now) then
			return code
		end
	end
	error("CodeBook: code space exhausted")
end

function CodeBook:addObserver(observer: number)
	if self._codes[observer] then
		return
	end
	self._codes[observer] = {}
	self._owners[observer] = {}
	self._stale[observer] = {}
end

-- Drops the observer's own view. Callers also use retireTarget() so others stop seeing them.
function CodeBook:removeObserver(observer: number)
	self._codes[observer] = nil
	self._owners[observer] = nil
	self._stale[observer] = nil
end

-- Gives `observer` a fresh code for `target` (replacing any current one). Returns the code.
function CodeBook:issue(observer: number, target: number, now: number): string?
	if observer == target then
		return nil
	end
	local codes = self._codes[observer]
	if not codes then
		return nil
	end
	if codes[target] then
		self:retire(observer, target, now)
	end
	local code = self:_generate(observer, target, now)
	codes[target] = code
	self._owners[observer][code] = target
	if self._onChange then
		self._onChange(observer, target, code)
	end
	return code
end

function CodeBook:retire(observer: number, target: number, now: number)
	local codes = self._codes[observer]
	local code = codes and codes[target]
	if not code then
		return
	end
	codes[target] = nil
	self._owners[observer][code] = nil
	self._stale[observer][code] = {
		target = target,
		expires = now + self._staleWindow,
		reuseUntil = now + self._reuseCooldown,
	}
	if self._onChange then
		self._onChange(observer, target, nil)
	end
end

-- Removes `target` from every observer's view (elimination, death, leaving).
function CodeBook:retireTarget(target: number, now: number)
	for observer in self._codes do
		self:retire(observer, target, now)
	end
end

-- Empties one observer's view (they died): every plate they could see disappears for them.
function CodeBook:retireView(observer: number, now: number)
	local codes = self._codes[observer]
	if not codes then
		return
	end
	for target in codes do
		self:retire(observer, target, now)
	end
end

-- What does `code` mean to this observer right now?
function CodeBook:lookup(observer: number, code: string, now: number): (Lookup, number?)
	local owners = self._owners[observer]
	if not owners then
		return "unknown", nil
	end
	local target = owners[code]
	if target then
		return "live", target
	end
	local stale = self._stale[observer][code]
	if stale and stale.expires > now then
		return "stale", stale.target
	end
	return "unknown", nil
end

function CodeBook:getCode(observer: number, target: number): string?
	local codes = self._codes[observer]
	return codes and codes[target]
end

-- The observer's current view as a list (safe to send to that observer only).
function CodeBook:snapshot(observer: number): { { target: number, code: string } }
	local list = {}
	local codes = self._codes[observer]
	if codes then
		for target, code in codes do
			table.insert(list, { target = target, code = code })
		end
	end
	return list
end

function CodeBook:purgeStale(now: number)
	for _, stale in self._stale do
		for code, record in stale do
			if record.reuseUntil <= now then
				stale[code] = nil
			end
		end
	end
end

return CodeBook
