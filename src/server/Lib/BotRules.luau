-- Training Grounds dummies (owner, 2026-09-29: "i just wanted the bots to be dummies"). Pure, unit-tested; the
-- dummies themselves live in Systems/TrainingService.
--
-- A dummy is a practice target with a real number plate: it stands on the training ground and turns to a new
-- heading every few seconds (so you have to step in front of it to read it, like a real opponent), and it never
-- reads, types or punches. Type its number to eliminate it; it comes back after the normal respawn time.
local BotRules = {}

export type Config = { bots: number }

-- Generic student names for dummies (no franchise names: docs/DESIGN.md "IP decision").
BotRules.NAMES = { "Kenji", "Aiko", "Daichi", "Hana", "Ren", "Mika", "Sora", "Yuki", "Taro", "Emi", "Kaito" }

-- Seconds between a dummy's turns.
BotRules.TURN_MIN = 3
BotRules.TURN_MAX = 6

function BotRules.defaultConfig(defaultBots: number): Config
	return { bots = defaultBots }
end

-- A training-menu request applied to the current settings: `bots` (0..maxBots, whole) is the only setting.
-- Anything else is refused whole. Returns (new config, ok).
function BotRules.applyConfig(current: Config, changes: any, maxBots: number): (Config, boolean)
	if type(changes) ~= "table" then
		return current, false
	end
	local updated = { bots = current.bots }
	for key, value in changes do
		if key ~= "bots" or type(value) ~= "number" or value ~= value or value % 1 ~= 0 or value < 0 or value > maxBots then
			return current, false
		end
		updated.bots = value
	end
	return updated, true
end

-- A dummy's next heading (a random direction) and when it turns again.
function BotRules.nextTurn(rng: Random, now: number): (Vector3, number)
	local angle = rng:NextNumber(0, math.pi * 2)
	return Vector3.new(math.cos(angle), 0, math.sin(angle)), now + rng:NextNumber(BotRules.TURN_MIN, BotRules.TURN_MAX)
end

return BotRules
