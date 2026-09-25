-- Unit tests for Lib/ShopRules (what the yen shop may sell, and what a purchase grants).
local ShopRules = require(script.Parent.Parent.Lib.ShopRules)
local T = require(script.Parent.TestUtil)

local DEFS = {
	{ id = "Free1", tier = "Free" },
	{ id = "A", tier = "Yen", yenTier = 1, yenPrice = 5000 },
	{ id = "B", tier = "Yen", yenTier = 2, yenPrice = 10000 },
	{ id = "C", tier = "Yen", yenTier = 3, yenPrice = 16500 },
	{ id = "Pass", tier = "Robux" },
}

local tests = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

local function has(list: { string }?, id: string): boolean
	return list ~= nil and table.find(list, id) ~= nil
end

test("[SHOP] buying a tier grants it and every lower tier not yet owned", function()
	local v = ShopRules.check("C", DEFS, { Free1 = true }, 20000)
	T.eq(v.status, "ok")
	T.eq(v.price, 16500, "you pay the bought character's own price")
	T.eq(#(v.grants :: any), 3)
	T.eq((v.grants :: any)[1], "C", "the bought character comes first")
	T.truthy(has(v.grants, "A") and has(v.grants, "B"), "tiers 1 and 2 come with it")
end)

test("[SHOP] lower tiers you already own aren't granted again", function()
	local v = ShopRules.check("C", DEFS, { A = true }, 20000)
	T.eq(v.status, "ok")
	T.truthy(has(v.grants, "B") and not has(v.grants, "A"))
end)

test("[SHOP] tier 1 grants only itself; higher tiers are never granted", function()
	local v = ShopRules.check("A", DEFS, {}, 5000)
	T.eq(v.status, "ok")
	T.eq(#(v.grants :: any), 1)
	T.truthy(not has(v.grants, "B") and not has(v.grants, "C"))
end)

test("[SHOP] not enough yen: refused, with the price", function()
	local v = ShopRules.check("B", DEFS, {}, 9999)
	T.eq(v.status, "insufficient")
	T.eq(v.price, 10000)
	T.eq(v.grants, nil)
	T.eq(ShopRules.check("B", DEFS, {}, 10000).status, "ok", "exactly enough is enough")
end)

test("[SHOP] owned (bought, or unlocked by a higher tier) can't be bought again", function()
	T.eq(ShopRules.check("A", DEFS, { A = true }, 99999).status, "owned")
	T.eq(ShopRules.check("B", DEFS, { A = true, B = true, C = true }, 99999).status, "owned")
end)

test("[SHOP] free and Robux characters aren't sold for yen; unknown ids are refused", function()
	T.eq(ShopRules.check("Free1", DEFS, {}, 99999).status, "not_for_yen")
	T.eq(ShopRules.check("Pass", DEFS, {}, 99999).status, "not_for_yen")
	T.eq(ShopRules.check("Nope", DEFS, {}, 99999).status, "unknown")
	T.eq(ShopRules.check(42, DEFS, {}, 99999).status, "unknown", "a malformed id from a client")
end)

return tests
