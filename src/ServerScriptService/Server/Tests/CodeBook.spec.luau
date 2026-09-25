-- Unit tests for Lib/CodeBook (per-observer code assignment).
local CodeBook = require(script.Parent.Parent.Lib.CodeBook)
local T = require(script.Parent.TestUtil)

local A, B, C = 101, 202, 303

local tests = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

test("[AT1] observers hold independent codes for the same target", function()
	local fixed = { [A] = { [B] = "5555" }, [C] = { [B] = "1342" } }
	local book = CodeBook.new({
		generator = function(o, t)
			return fixed[o][t]
		end,
	})
	book:addObserver(A)
	book:addObserver(C)
	T.eq(book:issue(A, B, 0), "5555")
	T.eq(book:issue(C, B, 0), "1342")
	T.eq((book:lookup(A, "1342", 0)), "unknown", "A cannot use C's code for B")
	T.eq((book:lookup(C, "5555", 0)), "unknown", "C cannot use A's code for B")
	local kind, target = book:lookup(A, "5555", 0)
	T.eq(kind, "live")
	T.eq(target, B)
end)

test("[AT2] every observer's live codes are unique (12 players x 300 rounds)", function()
	for _ = 1, 300 do
		local book = CodeBook.new()
		for o = 1, 12 do
			book:addObserver(o)
		end
		for o = 1, 12 do
			for t = 1, 12 do
				book:issue(o, t, 0)
			end
		end
		for o = 1, 12 do
			local seen = {}
			local snap = book:snapshot(o)
			T.eq(#snap, 11, "an observer holds codes for the 11 others only")
			for _, entry in snap do
				T.truthy(entry.target ~= o, "no self code")
				T.truthy(not seen[entry.code], "duplicate code " .. entry.code .. " for observer " .. o)
				seen[entry.code] = true
				T.truthy(string.match(entry.code, "^%d%d%d%d$") ~= nil, "4-digit string, got " .. entry.code)
			end
		end
	end
end)

test("[AT2] uniqueness holds even when the generator keeps colliding", function()
	local pool = { "0000", "0001", "0002" }
	local rng = Random.new(7)
	local book = CodeBook.new({
		generator = function()
			return pool[rng:NextInteger(1, #pool)]
		end,
	})
	book:addObserver(1)
	for t = 2, 12 do
		book:issue(1, t, 0)
	end
	local seen = {}
	for _, entry in book:snapshot(1) do
		T.truthy(not seen[entry.code], "duplicate " .. entry.code)
		seen[entry.code] = true
	end
	T.eq(#book:snapshot(1), 11)
end)

test("[AT3] nobody is ever issued a code for themself", function()
	local book = CodeBook.new()
	book:addObserver(A)
	T.eq(book:issue(A, A, 0), nil)
	T.eq(book:getCode(A, A), nil)
	T.eq(#book:snapshot(A), 0)
end)

test("[AT3] a retired code answers 'stale' inside the grace window, then 'unknown'", function()
	local book = CodeBook.new({
		staleWindow = 5,
		generator = function()
			return "4321"
		end,
	})
	book:addObserver(A)
	book:issue(A, B, 0)
	book:retire(A, B, 0)
	local kind, target = book:lookup(A, "4321", 1)
	T.eq(kind, "stale")
	T.eq(target, B)
	T.eq((book:lookup(A, "4321", 6)), "unknown")
end)

test("[AT3] a respawned target never gets back the code that was just retired", function()
	local sequence = { "1234", "1234", "1234", "7777" }
	local i = 0
	local book = CodeBook.new({
		generator = function()
			i += 1
			return sequence[math.min(i, #sequence)]
		end,
	})
	book:addObserver(A)
	T.eq(book:issue(A, B, 0), "1234")
	book:retire(A, B, 0)
	T.eq(book:issue(A, B, 1), "7777")
end)

test("[AT3] a retired code stays out of circulation after its stale window (reuse cooldown)", function()
	local sequence = { "1234", "1234", "7777" }
	local i = 0
	local book = CodeBook.new({
		staleWindow = 5,
		reuseCooldown = 30,
		generator = function()
			i += 1
			return sequence[math.min(i, #sequence)]
		end,
	})
	book:addObserver(A)
	book:issue(A, B, 0)
	book:retire(A, B, 0)
	T.eq((book:lookup(A, "1234", 10)), "unknown", "stale answer window is over")
	T.eq(book:issue(A, B, 10), "7777", "but the old code is still not handed back out")
end)

test("retireView empties one observer's view and nobody else's", function()
	local book = CodeBook.new()
	for _, o in { A, B, C } do
		book:addObserver(o)
	end
	book:issue(A, B, 0)
	book:issue(A, C, 0)
	book:issue(B, C, 0)
	book:retireView(A, 1)
	T.eq(#book:snapshot(A), 0)
	T.truthy(book:getCode(B, C) ~= nil, "other observers keep their view")
end)

test("retireTarget removes the target from every observer", function()
	local book = CodeBook.new()
	for _, o in { A, B, C } do
		book:addObserver(o)
	end
	book:issue(A, C, 0)
	book:issue(B, C, 0)
	book:retireTarget(C, 1)
	T.eq(book:getCode(A, C), nil)
	T.eq(book:getCode(B, C), nil)
end)

test("leading zeros survive as 4-character strings", function()
	local book = CodeBook.new({
		generator = function()
			return "0042"
		end,
	})
	book:addObserver(A)
	local code = book:issue(A, B, 0)
	T.eq(code, "0042")
	T.eq(typeof(code), "string")
	local kind, target = book:lookup(A, "0042", 0)
	T.eq(kind, "live")
	T.eq(target, B)
	T.eq((book:lookup(A, "42", 0)), "unknown", "'42' is not '0042'")
end)

test("onChange reports every issue and retirement (what gets pushed to that observer)", function()
	local log = {}
	local book = CodeBook.new({
		onChange = function(o, t, code)
			table.insert(log, { o = o, t = t, code = code })
		end,
	})
	book:addObserver(A)
	local code = book:issue(A, B, 0)
	book:retire(A, B, 1)
	T.eq(#log, 2)
	T.eq(log[1].code, code)
	T.eq(log[2].code, nil)
	T.eq(log[2].o, A)
end)

return tests
