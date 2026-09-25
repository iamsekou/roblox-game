-- The in-game currency as players see it. Owner, 2026-09-24: "Yern Credits" replaces yen (avoiding IP issues).
-- Internal names keep the old key, like the character ids: the saved profile's `yen` field, the "Yen" tier,
-- `yenPrice`/`yenTier`, the YEN_* constants and `yen` in remote payloads. Only the text below is ever shown.

local Currency = {
	NAME = "Yern Credits", -- the full name, in sentences
	SHORT = "YC", -- written after an amount: "5,000 YC"
	STAT = "Credits", -- the leaderstats column in Roblox's player list (short: the list truncates long names)
	SHOP = "Credit Shop", -- the shop door's prompt
}

-- An amount with its unit: Currency.amount("5,000") → "5,000 YC". Pass a number already formatted with commas.
function Currency.amount(formatted: string | number): string
	return tostring(formatted) .. " " .. Currency.SHORT
end

-- The same with a smaller unit, for big rich-text counters (the label needs RichText = true).
function Currency.richAmount(formatted: string | number, unitSize: number): string
	return string.format('%s <font size="%d">%s</font>', tostring(formatted), unitSize, Currency.SHORT)
end

return Currency
