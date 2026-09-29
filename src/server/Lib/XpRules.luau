-- Character XP and prestige (owner-approved 2026-09-29). Pure, unit-tested.
--   * Every character has its own progress: { p = prestige, l = level, x = xp into the current bar }.
--   * Levels 1..MAX_LEVEL per prestige. At level N the bar holds need(N, p); filling it moves to level N+1, and
--     filling the last bar makes the character ready to prestige: the bar stays full and XP stops there until the
--     player prestiges (a deliberate moment, owner-approved: manual prestige).
--   * Prestige: back to level 1 with an empty bar, one prestige higher, up to MAX_PRESTIGE; every bar is
--     PRESTIGE_GROWTH bigger per prestige (owner: "the bar increases the farther the prestige is").
--   * Numbers are big on purpose (owner: "high incrementals"), bars medium: at prestige 0 the first level takes
--     about one round and a full prestige about 272,000 XP.
-- The numbers come in as a Params table (Constants.XP_*), so tests pin them independently of tuning.
local XpRules = {}

export type Progress = { p: number, l: number, x: number }
export type Params = {
	maxLevel: number,
	maxPrestige: number,
	base: number, -- the level-1 bar at prestige 0
	step: number, -- each level's bar is this much bigger than the last
	growth: number, -- every prestige multiplies every bar by (1 + growth * prestige)
	round: number, -- bars are rounded to a multiple of this
}

-- The game's params from the shared Constants table (XP_*).
function XpRules.params(constants: any): Params
	return {
		maxLevel = constants.XP_MAX_LEVEL,
		maxPrestige = constants.XP_MAX_PRESTIGE,
		base = constants.XP_BAR_BASE,
		step = constants.XP_BAR_STEP,
		growth = constants.XP_PRESTIGE_GROWTH,
		round = constants.XP_BAR_ROUND,
	}
end

function XpRules.new(): Progress
	return { p = 0, l = 1, x = 0 }
end

-- XP the bar at `level` holds, at `prestige`.
function XpRules.need(level: number, prestige: number, params: Params): number
	local raw = (params.base + params.step * (level - 1)) * (1 + params.growth * prestige)
	return math.max(params.round, math.floor(raw / params.round + 0.5) * params.round)
end

-- The last bar is full: nothing more to earn until a prestige (or ever, at the top prestige).
function XpRules.isFull(progress: Progress, params: Params): boolean
	return progress.l >= params.maxLevel and progress.x >= XpRules.need(params.maxLevel, progress.p, params)
end

function XpRules.canPrestige(progress: Progress, params: Params): boolean
	return XpRules.isFull(progress, params) and progress.p < params.maxPrestige
end

-- Adds `amount` XP. Returns the new progress, how many levels were gained, and whether this gain filled the
-- last bar. Never goes past the full last bar (the rest is simply not kept).
function XpRules.add(progress: Progress, amount: number, params: Params): (Progress, number, boolean)
	local result = { p = progress.p, l = progress.l, x = progress.x }
	if XpRules.isFull(result, params) or type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return result, 0, false
	end
	local gained = 0
	result.x += math.floor(amount)
	while true do
		local need = XpRules.need(result.l, result.p, params)
		if result.x < need then
			break
		end
		if result.l >= params.maxLevel then
			result.x = need -- the last bar: full, and it stays full
			return result, gained, true
		end
		result.x -= need
		result.l += 1
		gained += 1
	end
	return result, gained, false
end

-- The next prestige, or nil if the character isn't ready (or is already at the top).
function XpRules.prestige(progress: Progress, params: Params): Progress?
	if not XpRules.canPrestige(progress, params) then
		return nil
	end
	return { p = progress.p + 1, l = 1, x = 0 }
end

-- Total XP from a fresh start at `prestige` to a full last bar (shown in docs; used by tests).
function XpRules.totalFor(prestige: number, params: Params): number
	local total = 0
	for level = 1, params.maxLevel do
		total += XpRules.need(level, prestige, params)
	end
	return total
end

-- A clean progress from anything stored (a save can be old, damaged or tampered with).
function XpRules.sanitize(raw: any, params: Params): Progress
	local progress = XpRules.new()
	if type(raw) ~= "table" then
		return progress
	end
	local function whole(value: any, low: number, high: number): number?
		if type(value) ~= "number" or value ~= value then
			return nil
		end
		return math.clamp(math.floor(value), low, high)
	end
	progress.p = whole(raw.p, 0, params.maxPrestige) or 0
	progress.l = whole(raw.l, 1, params.maxLevel) or 1
	progress.x = whole(raw.x, 0, XpRules.need(progress.l, progress.p, params)) or 0
	-- A full bar below the last level can't exist (it would have levelled): keep it just short.
	local need = XpRules.need(progress.l, progress.p, params)
	if progress.l < params.maxLevel and progress.x >= need then
		progress.x = need - 1
	end
	return progress
end

-- Roman numerals for prestige badges (1..10 and beyond).
local NUMERALS = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }
function XpRules.numeral(prestige: number): string
	return NUMERALS[prestige] or tostring(prestige)
end

return XpRules
