-- Numbers Assassin Universe: every tunable gameplay number lives here.
-- Decisions approved by the designer are marked "approved"; "placeholder" values are expected to change.

local Constants = {
	-- Match size and flow
	MAX_PLAYERS = 12,
	MIN_PLAYERS_TO_START = 2, -- approved
	-- Rounds are time-based with no elimination target (owner, 2026-09-23): most eliminations at the cap wins.
	ROUND_TIME_CAP = 8 * 60, -- approved
	SUDDEN_DEATH_SECONDS = 60, -- approved: a tie at the cap goes to sudden death; the next sole leader wins
	INTERMISSION_SECONDS = 15, -- approved
	ROUND_END_SECONDS = 6, -- results banner before everyone returns to the lobby
	UNDERPOPULATED_GRACE = 15, -- a round below MIN_PLAYERS_TO_START waits this long for a joiner, then ends with no winner

	-- Eliminations
	YEN_PER_ELIMINATION = 500,
	RESPAWN_SECONDS = 3,
	CODE_LENGTH = 4, -- codes are strings "0000".."9999"; leading zeros allowed
	WRONG_SUBMISSION_LIMIT = 2, -- approved: 1st wrong code = screen shake, 2nd wrong code in the same life = self-elimination
	SUBMISSION_DEBOUNCE = 0.3, -- seconds between submissions; anti-macro guard, never counts as a strike
	STALE_CODE_GRACE = 5, -- a just-retired code answers "already down" (no strike) for this long
	CODE_REUSE_COOLDOWN = 30, -- a retired code isn't handed back out to the same observer for this long
	SPAWN_PROTECTION_SECONDS = 3, -- approved: after (re)spawning you have no plate for anyone and see no plates

	-- Movement
	MOVE_SPEED = 24, -- Roblox default is 16; sprint-fast is the baseline

	-- Camera: the field of view widens drastically while running (approved), easing back when you stop
	BASE_FOV = 70,
	RUN_FOV = 96,
	FOV_RESPONSE = 5, -- higher = snappier transition
	RUN_FOV_MIN_SPEED = 6, -- horizontal studs/second before the run FOV kicks in

	-- Anime sprint package (owner request, 2026-09-23): speed lines, camera lean and bob, ninja-run pose,
	-- hand wind trails and dust. Everything scales with how fast you are actually running.
	SPRINT_FULL_SPEED = 22, -- studs/second at which the effects are at full strength
	SPRINT_LEAN_DEGREES = 16, -- upper body leans forward
	SPRINT_ARMS_BACK_DEGREES = 60, -- arms sweep back (the classic ninja run)
	SPRINT_CAMERA_ROLL_DEGREES = 5, -- camera leans into turns
	SPRINT_CAMERA_BOB = 0.12, -- studs of vertical bob per stride

	-- Abilities (Phase 3; listed now so balance lives in one place)
	MILD_COOLDOWN = 8,
	ULTIMATE_COOLDOWN = 20,
	ULTIMATE_RESPAWN_REDUCTION = 10,

	-- Number plates (owner rule, 2026-09-23): you can only read someone's number when you're within
	-- reading range (11 studs) AND they are facing you. The server discloses a code only when this holds
	-- (with a little slack for latency), so a modified client can't read numbers from afar.
	PLATE_VIEW_DISTANCE = 11, -- studs (owner, 2026-09-23: raised from 7)
	PLATE_VIEW_CONE_DEGREES = 60, -- the target must face you within this many degrees
	PLATE_SERVER_SLACK_DISTANCE = 2.5,
	PLATE_SERVER_SLACK_DEGREES = 15,
	PLATE_DISCLOSE_INTERVAL = 0.1, -- seconds between server visibility checks
	-- Blank plates (owner rule, 2026-09-23): every opponent always carries a plate you can see, but it
	-- stays masked until the reading rule above holds. Placeholder distance; the mask reveals nothing.
	PLATE_BLANK_DRAW_DISTANCE = 60, -- studs from your fighter
	PLATE_HIDE_SLACK_DISTANCE = 0.5, -- a revealed number stays up this far past the rule, so it doesn't flicker
	PLATE_HIDE_SLACK_DEGREES = 5,
	PLATE_SIZE = Vector2.new(2, 0.8), -- studs (owner, 2026-09-23: up from 1.3 x 0.5 for readability)
	PLATE_CLEARANCE = 0.6, -- studs above the tallest visible point of the avatar (hats and hair included)
	PLATE_MIN_OFFSET = 1.2,
	PLATE_MAX_OFFSET = 9,

	-- Arena spawns (owner rule, 2026-09-23): random anywhere on the map, nothing marks where they are
	SPAWN_MIN_DISTANCE_FROM_OPPONENTS = 30,
	SPAWN_SAMPLE_ATTEMPTS = 60,

	-- Input
	ENTRY_KEY = Enum.KeyCode.F,

	-- Modes the random picker may choose from (uniform, repeats allowed). Team6v6 arrives in Phase 3.
	ENABLED_MODES = { "FFA" },

	-- Studio-only: set this attribute (a number) on ServerScriptService to lower the minimum
	-- player count for solo testing. Ignored in live servers.
	DEV_MIN_PLAYERS_ATTRIBUTE = "NAU_DevMinPlayers",
}

return Constants
