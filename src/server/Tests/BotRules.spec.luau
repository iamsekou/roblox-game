-- Unit tests for Lib/BotRules (training dummies and the training menu's setting).
local BotRules = require(script.Parent.Parent.Lib.BotRules)
local T = require(script.Parent.TestUtil)

local tests = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

test("[TRAINING] menu: the dummy count applies (0-11); anything else is refused whole", function()
	local base = BotRules.defaultConfig(3)
	T.eq(base.bots, 3)
	local c, ok = BotRules.applyConfig(base, { bots = 11 }, 11)
	T.eq(ok, true) T.eq(c.bots, 11)
	T.eq(base.bots, 3, "the old config isn't modified")
	T.eq(select(2, BotRules.applyConfig(base, { bots = 0 }, 11)), true, "zero: practise alone")
	for _, bad in { { bots = 12 }, { bots = -1 }, { bots = 2.5 }, { bots = 0 / 0 }, { bots = "3" }, { difficulty = "Hard" }, { junk = 1 }, "bots" :: any } do
		local same, refused = BotRules.applyConfig(base, bad, 11)
		T.eq(refused, false) T.eq(same, base)
	end
end)

test("[TRAINING] dummies turn to a random flat heading every few seconds", function()
	local rng = Random.new(3)
	for _ = 1, 50 do
		local heading, at = BotRules.nextTurn(rng, 100)
		T.truthy(math.abs(heading.Magnitude - 1) < 1e-6, "unit")
		T.eq(heading.Y, 0, "flat")
		T.truthy(at >= 100 + BotRules.TURN_MIN and at <= 100 + BotRules.TURN_MAX, "within the turn interval")
	end
end)

return tests
