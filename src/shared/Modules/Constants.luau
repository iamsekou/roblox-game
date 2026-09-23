-- Numbers Assassin Universe: every tunable gameplay number lives here.
-- Decisions approved by the designer are marked "approved"; "placeholder" values are expected to change.

-- Owner, 2026-09-23: every ability effect lasts 1.75x longer (locks, blinds, marks, boosts, stances, clones,
-- trails, barriers, readings). Wind-ups, cooldowns, ranges and speeds are unchanged. Base values are the sheet's.
local EFFECT_TIME = 1.75

local Constants = {
	ABILITY_EFFECT_TIME_SCALE = EFFECT_TIME,
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

	-- Abilities (approved sheet, docs/ABILITIES.md). Every character: a mild and an ultimate.
	MILD_COOLDOWN = 8,
	ULTIMATE_COOLDOWN = 20,
	ULTIMATE_RESPAWN_REDUCTION = 10, -- a respawn takes this much off the ultimate's remaining cooldown
	MAX_INPUT_LOCK = 2 * EFFECT_TIME, -- approved cap (2 s), scaled with the owner's 1.75x: 3.5 s
	ABILITY_MILD_KEY = Enum.KeyCode.Q,
	ABILITY_ULTIMATE_KEY = Enum.KeyCode.E,
	ABILITY_CHARGE_SLOW = 0.45, -- walk-speed multiplier while charging an ultimate (placeholder)
	DEFAULT_CHARACTER = "Goku",

	-- Colosseum crowd (owner-approved 2026-09-23): built and animated by each client (animations/Controllers/Crowd).
	CROWD_SEAT_SPACING = 2.6, -- studs between spectators along a row (2.3 made neighbours' arms overlap)
	CROWD_BUILD_PER_FRAME = 80, -- spectators built per frame when the arena appears (no hitch)
	CROWD_UPDATES_PER_FRAME = 260, -- spectators re-posed per frame (the rest keep their last pose)
	CROWD_EXCITE_DECAY = 0.25, -- how fast a cheer dies down (per second, from 1)
	CROWD_FAR_CHEER = 0.7, -- how hard the far side of the bowl cheers, relative to the section nearest a kill
	CROWD_WAVE_EVERY = 28, -- seconds between stadium waves
	CROWD_WAVE_SECONDS = 8, -- one lap of the wave
	CROWD_DENSITY_LOW = 0.45, -- share of seats filled at low graphics quality (1-3)
	CROWD_DENSITY_MID = 0.7, -- at medium quality (4-6)
	CROWD_DENSITY_TOUCH_MAX = 0.55, -- phones and tablets never go above this

	-- Kill leaderboards (owner-approved 2026-09-23): all-time + weekly (Monday 00:00 UTC), global via DataStores.
	LEADERBOARD_FLUSH_SECONDS = 30, -- unsaved kills are added to the stores this often (and on shutdown)
	LEADERBOARD_REFRESH_SECONDS = 60, -- the global top list is re-read this often (per-minute DataStore limits)
	LEADERBOARD_ROWS = 10, -- rows shown on each board
	LEADERBOARD_DEPTH = 100, -- how deep the fetched list goes ("YOU · #37"; deeper = unranked)
	LEADERBOARD_STORE_VERSION = "v1", -- bump to start both boards from zero

	-- Clashes (owner-approved 2026-09-23, rules in Lib/ClashRules): the same attack ability started at each
	-- other by two fighters cancels both and locks them face to face; first correct code wins as usual.
	CLASH_WINDOW = 0.6, -- max seconds between the two casts (and the first must still be winding up)
	CLASH_RANGE = 30, -- max studs between the two fighters
	CLASH_FACING_DEGREES = 35, -- each must aim at the other within this cone
	CLASH_SECONDS = 2.5, -- how long the exchange lasts (ends early if either goes down)
	CLASH_DISTANCE = 7, -- studs apart during the exchange: inside plate reading range, so both numbers show
	CLASH_KNOCKBACK = 45, -- studs/second each is thrown back when it ends (placeholder)
	CLASH_LAUNCH = 18, -- upward studs/second on that throw (placeholder)

	-- Ability cast animations (Phase 3 item 8). Poses: animations/Controllers/AbilityPoses; hand-keyframed clip
	-- ids: Modules/AnimationIds. The wind-up lasts the server's cast time; these shape the blends around it.
	ANIM_BLEND_IN = 0.15, -- seconds to blend from the normal animation into a wind-up (eased)
	ANIM_RELEASE_SNAP = 0.07, -- wind-up target -> release target (the springs below smooth the actual motion)
	ANIM_BLEND_OUT = 0.45, -- release -> back to the normal animation (eased)
	-- Fluid placeholder motion (owner request 2026-09-23: "more fluid hand movement, less blocky"). Every posed
	-- joint follows its target on a damped spring { frequency Hz, damping ratio }. Heavier joints respond
	-- slower, so the body leads and the arms whip after it; damping below 1 adds a little overshoot and settle.
	-- At these rates a wind-up or a return takes about 0.2 s (measured: 6.5 Hz shoulders dropped 130 degrees in
	-- 4 frames, which read as a jerk).
	ANIM_SPRINGS = {
		Waist = { 2.2, 0.85 },
		Neck = { 2.6, 0.85 },
		Shoulder = { 3, 0.7 },
		Elbow = { 3.6, 0.65 },
		Wrist = { 4.5, 0.55 },
	},
	ANIM_STRIKE_BOOST = 2.2, -- springs this much stiffer the instant an ability releases, so strikes stay sharp...
	ANIM_STRIKE_SECONDS = 0.18, -- ...easing back to normal over this long
	ANIM_WRIST_DRAG = 0.06, -- degrees the hand trails per degree/second of arm swing
	ANIM_WRIST_DRAG_MAX = 28, -- degrees
	ANIM_LIFE_DEGREES = 2.2, -- gentle breathing sway on posed joints, so no wind-up or hold is frozen
	ANIM_DEFAULT_HOLD = 0.4, -- seconds a release pose is held when the move doesn't say
	ANIM_MAX_WINDUP = 3, -- ignore cast times above this (sanity cap on the server's number)

	-- Goku (approved 2026-09-23)
	GOKU_TRANSMISSION_DISTANCE = 18, -- Phase Shift lands on a random open spot this far away
	GOKU_TRANSMISSION_TELL = 0.3,
	GOKU_WAVE_CHARGE = 1.2,
	GOKU_WAVE_LENGTH = 60,
	GOKU_WAVE_RADIUS = 3.5, -- placeholder: how close to the beam's centre line counts as a hit
	GOKU_WAVE_LOCK = 2 * EFFECT_TIME,
	GOKU_WAVE_KNOCKBACK = 70, -- studs/second along the beam (placeholder)

	-- Luffy (approved 2026-09-23)
	LUFFY_GRAPPLE_RANGE = 45,
	LUFFY_GRAPPLE_TELL = 0.3,
	LUFFY_GRAPPLE_SPEED = 120, -- studs/second pull
	LUFFY_GATLING_WINDUP = 1,
	LUFFY_GATLING_DURATION = 1.5 * EFFECT_TIME,
	LUFFY_GATLING_PULSES = 5, -- hit checks spread across the flurry (3 at 1.5 s; 5 keeps the same rhythm at 2.6 s)
	LUFFY_GATLING_RANGE = 15,
	LUFFY_GATLING_HALF_ANGLE = 50, -- degrees either side of where Luffy aims (placeholder)
	LUFFY_GATLING_PUSH = 40, -- studs/second per pulse (placeholder)

	-- Krillin
	KRILLIN_FLARE_TELL = 0.4,
	KRILLIN_FLARE_RANGE = 25,
	KRILLIN_FLARE_FACING = 60, -- degrees: opponents looking at Krillin within this cone are blinded
	KRILLIN_FLARE_BLIND = 1.5 * EFFECT_TIME,
	KRILLIN_DISC_TELL = 0.8,
	KRILLIN_DISC_LENGTH = 60,
	KRILLIN_DISC_SPEED = 30, -- "slow disc": 2 s to travel its full length
	KRILLIN_DISC_RADIUS = 5, -- how close it must pass to mark someone (placeholder)
	KRILLIN_DISC_MARK = 5 * EFFECT_TIME,
	KRILLIN_DISC_READ_RANGE = 200, -- approved exception: marked plates readable this far, line of sight only

	-- Vegeta
	VEGETA_PRIDE_TELL = 0.3,
	VEGETA_PRIDE_SPEED = 1.3,
	VEGETA_PRIDE_SECONDS = 4 * EFFECT_TIME,
	VEGETA_BLAST_RANGE = 50,
	VEGETA_BLAST_WARN = 1,
	VEGETA_BLAST_RADIUS = 10, -- placeholder
	VEGETA_BLAST_LOCK = 1.5 * EFFECT_TIME,
	VEGETA_BLAST_LAUNCH = 60, -- upward studs/second (placeholder)

	-- Zoro
	ZORO_GUARD_TELL = 0.3,
	ZORO_GUARD_SECONDS = 2 * EFFECT_TIME,
	ZORO_GUARD_SLOW = 0.5,
	GUARD_SPARK_INTERVAL = 0.25, -- seconds between "blocked" spark effects on one guarding fighter (drags tick every 0.1 s)
	ZORO_TORNADO_WINDUP = 1,
	ZORO_TORNADO_LENGTH = 40,
	ZORO_TORNADO_SPEED = 20,
	ZORO_TORNADO_RADIUS = 7, -- placeholder
	ZORO_TORNADO_DRAG = 30, -- studs/second toward and along with the tornado (placeholder)

	-- L
	L_CAMERA_TELL = 0.3,
	L_CAMERA_SECONDS = 20 * EFFECT_TIME,
	L_CAMERA_RANGE = 25,
	L_DEDUCTION_TELL = 0.8,
	L_DEDUCTION_SECONDS = 7, -- owner, 2026-09-23: set to 7 s (overrides the 1.75x scaling)

	-- Naruto
	NARUTO_CLONE_TELL = 0.3,
	NARUTO_CLONE_SECONDS = 4 * EFFECT_TIME,
	NARUTO_CLONE_SPEED = 18, -- studs/second the clone runs (placeholder)
	NARUTO_SPHERE_WINDUP = 0.6,
	NARUTO_SPHERE_LUNGE = 20,
	NARUTO_SPHERE_SPEED = 80,
	NARUTO_SPHERE_RADIUS = 4, -- placeholder
	NARUTO_SPHERE_LAUNCH = 55, -- forward studs/second; with the upward kick this carries ~25 studs
	NARUTO_SPHERE_LOCK = 2 * EFFECT_TIME,

	-- Ichigo
	ICHIGO_FLASH_TELL = 0.3,
	ICHIGO_FLASH_DISTANCE = 22,
	ICHIGO_FLASH_SPEED = 160,
	ICHIGO_FLASH_HIDE = 0.4 * EFFECT_TIME, -- the plate vanishes for this long
	ICHIGO_WAVE_CHARGE = 1,
	ICHIGO_WAVE_LENGTH = 40,
	ICHIGO_WAVE_WIDTH = 14, -- placeholder
	ICHIGO_TRAIL_SECONDS = 3 * EFFECT_TIME,
	ICHIGO_TRAIL_SLOW = 0.6, -- 40 % slower

	-- Sasuke
	SASUKE_DASH_TELL = 0.3,
	SASUKE_DASH_DISTANCE = 30,
	SASUKE_DASH_SPEED = 170,
	SASUKE_EYE_TELL = 0.8,
	SASUKE_EYE_SECONDS = 6 * EFFECT_TIME,
	SASUKE_EYE_AIM = 15, -- degrees: the marked opponent is the visible one closest to where you aim

	-- Gojo
	GOJO_BLINK_TELL = 0.3,
	GOJO_BLINK_RANGE = 30, -- to where you look (the point at the centre of your screen), capped at this range
	LOOK_EYE_MAX_OFFSET = 40, -- the client's camera position is trusted only this close to its character
	GOJO_INFINITY_TELL = 0.8,
	GOJO_BARRIER_SECONDS = 4 * EFFECT_TIME,
	GOJO_BARRIER_RADIUS = 10,
	GOJO_BARRIER_PUSH = 50, -- placeholder
	GOJO_READ_SECONDS = 10 * EFFECT_TIME, -- approved: reading ends after 3 eliminations or 10 s (now 17.5 s)
	GOJO_READ_ELIMINATIONS = 3,
	UNLIMITED_READ_RANGE = 10000, -- "any distance" for reading exceptions (a finite number travels safely over remotes)

	-- Owner request 2026-09-23: in Studio every character is unlocked for testing. Live servers ignore
	-- this (ownership there comes from the shop and Game Passes).
	DEV_UNLOCK_ALL_IN_STUDIO = true,

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
	-- Studio-only: set this attribute (true) on ServerScriptService and every ability also treats its caster as
	-- an opponent, so a single player can test every on-target effect end to end. Ignored in live servers.
	DEV_SELF_TARGET_ATTRIBUTE = "NAU_DevSelfTarget",
	-- Studio-only: set false on ServerScriptService to see real ownership (the shop) instead of every character
	-- unlocked; set a number on a Player to grant them that much yen. Both ignored in live servers.
	DEV_UNLOCK_ATTRIBUTE = "NAU_DevUnlockAll",
	DEV_GRANT_YEN_ATTRIBUTE = "NAU_DevGrantYen",
	-- Studio-only: "userId:count,..." on ServerScriptService adds test kills to both leaderboards. Ignored live.
	DEV_FAKE_KILLS_ATTRIBUTE = "NAU_DevFakeKills",
}

return Constants
