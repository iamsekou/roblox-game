-- Yen shop rules (Phase 3 item 5, approved 2026-09-23). Pure: no engine calls, unit-tested.
--   * Only Yen-tier characters are sold for yen (Free ones are owned from the start; Robux ones are Game
--     Passes, item 6).
--   * Buying yen tier N also grants every lower yen tier the player doesn't own yet ("buying a tier unlocks
--     the tiers below"). The price is always the bought character's own price.
--   * Nothing is sold twice, and never without enough yen.
local ShopRules = {}

export type Def = { id: string, tier: string, yenTier: number?, yenPrice: number? }

export type Verdict = {
	status: string, -- "ok" | "unknown" | "not_for_yen" | "owned" | "insufficient"
	price: number?,
	grants: { string }?, -- ids to add to the inventory on "ok", the bought character first
}

-- `owned` holds every id the player already owns (including free starters).
function ShopRules.check(id: any, defs: { Def }, owned: { [string]: boolean }, balance: number): Verdict
	local def: Def? = nil
	for _, d in defs do
		if d.id == id then
			def = d
			break
		end
	end
	if not def then
		return { status = "unknown" }
	end
	if def.tier ~= "Yen" or type(def.yenTier) ~= "number" or type(def.yenPrice) ~= "number" then
		return { status = "not_for_yen" }
	end
	if owned[def.id] then
		return { status = "owned" }
	end
	local price = def.yenPrice :: number
	if balance < price then
		return { status = "insufficient", price = price }
	end
	local grants = { def.id }
	for _, d in defs do
		if d.id ~= def.id and d.tier == "Yen" and type(d.yenTier) == "number" and d.yenTier < (def.yenTier :: number) and not owned[d.id] then
			table.insert(grants, d.id)
		end
	end
	return { status = "ok", price = price, grants = grants }
end

return ShopRules
