-- Admin panel rules (owner, 2026-09-30: "an admin panel for me and sam"). Pure: no engine calls, so every rule
-- runs in the unit tests.
--
-- Who is an admin: the user ids in Constants.ADMIN_USER_IDS. In Studio every player counts (Test → Clients and
-- Servers hands out negative local ids, and a Studio session only ever holds the team).
--
-- What an admin may ask for: the commands below, each with a fixed argument shape. `validate` turns whatever the
-- client sent into clean arguments or a reason; nothing the client sends is used without passing through it.
local AdminRules = {}

export type Limits = {
	maxCredits: number,
	maxXp: number,
	minSeconds: number,
	maxSeconds: number,
	maxReason: number,
}

-- Argument kinds: "target" (a user id), "credits" / "xp" (a whole amount), "seconds", "mode", "reason", "on"
-- (a boolean) and "duel" (a duel test).
AdminRules.COMMANDS = {
	giveCredits = { "target", "credits" },
	takeCredits = { "target", "credits" },
	giveXp = { "target", "xp" },
	startRound = {},
	endRound = {},
	setTimeLeft = { "seconds" },
	setMode = { "mode" },
	kick = { "target", "reason" },
	unlockAll = { "on" },
	duel = { "duel" },
	ghost = { "on" },
}

AdminRules.MODES = { random = true, FFA = true, Team6v6 = true }
AdminRules.DUELS = { bot = true, watch = true }

function AdminRules.isAdmin(userId: number, adminIds: { number }, isStudio: boolean): boolean
	if isStudio then
		return true
	end
	return table.find(adminIds, userId) ~= nil
end

local function wholeNumber(value: any, low: number, high: number): number?
	if type(value) ~= "number" or value ~= value or value % 1 ~= 0 or value < low or value > high then
		return nil
	end
	return value
end

-- A kick reason: a string, control characters removed, trimmed, at most `max` characters; blank gets a default.
function AdminRules.cleanReason(value: any, max: number): string?
	if type(value) ~= "string" then
		return nil
	end
	local text = string.gsub(value, "%c", " ")
	text = string.match(text, "^%s*(.-)%s*$") or ""
	if #text > max then
		return nil
	end
	return if text == "" then "No reason given" else text
end

-- Checks one request. Returns (args, nil) with clean arguments keyed by kind, or (nil, reason).
function AdminRules.validate(command: any, args: any, limits: Limits): ({ [string]: any }?, string?)
	local shape = type(command) == "string" and AdminRules.COMMANDS[command]
	if not shape then
		return nil, "unknown_command"
	end
	if args ~= nil and type(args) ~= "table" then
		return nil, "malformed"
	end
	args = args or {}
	local clean = {}
	for _, kind in shape do
		local value = args[kind]
		local ok
		if kind == "target" then
			ok = if type(value) == "number" and value == value and value % 1 == 0 then value else nil
		elseif kind == "credits" then
			ok = wholeNumber(value, 1, limits.maxCredits)
		elseif kind == "xp" then
			ok = wholeNumber(value, 1, limits.maxXp)
		elseif kind == "seconds" then
			ok = wholeNumber(value, limits.minSeconds, limits.maxSeconds)
		elseif kind == "mode" then
			ok = if type(value) == "string" and AdminRules.MODES[value] then value else nil
		elseif kind == "duel" then
			ok = if type(value) == "string" and AdminRules.DUELS[value] then value else nil
		elseif kind == "on" then
			ok = if type(value) == "boolean" then value else nil
		elseif kind == "reason" then
			ok = AdminRules.cleanReason(value, limits.maxReason)
		end
		if ok == nil then
			return nil, "bad_" .. kind
		end
		clean[kind] = ok
	end
	return clean, nil
end

return AdminRules
