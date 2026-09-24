-- Robux credit bundles (Developer Products; owner's ids, 2026-09-24). Never invent ids: they come from the
-- owner's Creator Dashboard. `yen` is what the server credits (Yern Credits; the internal name stays "yen").
-- `robux` is only a fallback label: the menu shows the live price read from Roblox, which is what players pay.
-- The Game Passes for the Robux characters are on their CharacterDefs entries (gamePassId).
export type Bundle = { productId: number, yen: number, robux: number }

local bundles: { Bundle } = {
	{ productId = 3714587165, yen = 5000, robux = 199 },
	{ productId = 3714587398, yen = 10000, robux = 499 },
	-- Owner, 2026-09-24: 20,000. The product was created as "2000 YERN CREDITS"; rename it on Roblox to match.
	{ productId = 3714587623, yen = 20000, robux = 999 },
	{ productId = 3714587718, yen = 40000, robux = 1999 },
}

local byProductId: { [number]: Bundle } = {}
for _, bundle in bundles do
	byProductId[bundle.productId] = bundle
end

return {
	bundles = bundles,
	byProductId = byProductId,
}
