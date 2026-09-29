-- Robux credit bundles (Developer Products; owner's ids for "Numbers Assassin Universe", 2026-09-29, replacing the
-- old experience's products). Never invent ids: they come from the owner's Creator Dashboard. `yen` is what the
-- server credits (Yern Credits; the internal name stays "yen"). `robux` is only a fallback label: the menu shows
-- the live price read from Roblox, which is what players pay.
-- The Game Passes for the Robux characters are on their CharacterDefs entries (gamePassId).
export type Bundle = { productId: number, yen: number, robux: number }

local bundles: { Bundle } = {
	{ productId = 3715355768, yen = 5000, robux = 200 },
	{ productId = 3715356059, yen = 10000, robux = 500 },
	{ productId = 3715356212, yen = 20000, robux = 1000 },
	{ productId = 3715356256, yen = 40000, robux = 2000 },
}

local byProductId: { [number]: Bundle } = {}
for _, bundle in bundles do
	byProductId[bundle.productId] = bundle
end

return {
	bundles = bundles,
	byProductId = byProductId,
}
