# Numbers Assassin Universe — design & technical reference

Source of truth for approved decisions, contracts and phase status. Code constants live in
`src/shared/Modules/Constants.luau`; this file explains *why*.

## Phase status

| Phase | Status |
|---|---|
| 1 — Design & technical plan | Approved |
| 2 — Playable vertical slice (FFA, graybox lobby + arena, per-observer plates, code entry, respawn, HUD) | Built; 32/32 unit tests; solo live playtest passed; **multi-client check passed (owner, 2026-09-23)** |
| 2.1 — Owner changes (2026-09-23): spawn invisibility, original names, reference-style lobby with portrait bubbles, run FOV | Built and solo-tested; portraits uploaded (asset ids in `CharacterDefs`) and showing in game |
| 2.2 — Owner changes (2026-09-23): 2-step facing plates, arena rework, aggressive FIGHT button, random hidden spawns, smaller HUD, anime sprint | Built; 37/37 unit tests; solo-tested; plate rule between players passed the owner's 3-player check (2026-09-23) |
| 3 prep — Ability sheet | **Approved 2026-09-23** (`docs/ABILITIES.md`; Goku and Gojo changed, Krillin/Sasuke/Gojo reading exceptions) |
| 3 — Team mode, economy, persistence, Robux entitlements, abilities, respawn character select | **Plan approved 2026-09-23** (all 8 items). Built: abilities (all 10), Q/E + touch, character select, saved progress, yen shop, team battle 6v6, animation playback (placeholders); extras: swords, clashes, kill leaderboards, crowd, passive yen, 30 s alert. 114/114 unit tests. **Waiting on the owner:** Game Pass ids (item 6) and Developer Product ids (Robux yen bundles), authored animation clips (item 8), multi-player tests of team battle and saves |
| 4 — Polish, 5 more maps (plan only until map 1 plays well), 12-player stress test | **Approved 2026-09-23 (owner: all items, map 2 planning skipped for now). Built:** settings menu, phone/tablet pass, how-to-play walkthrough, 12-player stress harness + measurements, remote security review (2 fixes), sound (music + effects). Details in the Phase 4 section below |

## Locked decisions

| Topic | Decision |
|---|---|
| Players / modes | ≤12 per match. 6v6 team or FFA. **Rounds are time-based with uncapped eliminations** (owner, 2026-09-23; replaced "first to 20"): most eliminations (player, or team total) when time runs out wins. Uniform random mode + map each round; **repeats allowed, no history** (approved) |
| Round cap | 8 min. Sole leader with ≥1 elimination wins; a tie → 60 s sudden death, starting the instant time runs out (owner, 2026-09-23), next sole leader wins; sudden death expiring → draw. **Everyone in the match gets a "30 SECONDS LEFT" alert** (owner, 2026-09-23), again 30 s before sudden death ends (`Lib/RoundTimer`) |
| Intermission | 15 s. Min 2 queued players to start. Below 2 mid-round → 15 s grace for a joiner, then the round ends with no winner |
| Mid-round join | FIGHT joins instantly if the match has <12; otherwise the player is queued and drops in when a slot opens |
| After a round | 6 s results, everyone returns to the lobby and is auto-queued for the next round (can leave the queue) |
| Codes | 4-character strings `"0000"`–`"9999"`; leading zeros allowed; compared as strings, never numbers |
| Own plate | Not shown. Nobody holds a code for themself, so self-elimination by code is impossible by construction |
| Teammates (6v6) | **Do show plates** (visual consistency, approved). Submitting a teammate's code → "That's a teammate", no strike, no kill |
| Team battle (6v6) | **Built 2026-09-23 (Phase 3 item 7; owner approved all 8 points).** (1) Picked (uniformly with FFA) only when ≥4 fighters are queued; fewer is always FFA. (2) Auto-balanced: the first 12 queued are shuffled and dealt onto the teams in turn (sizes differ by ≤1); mid-round joiners go to the smaller team (tie: the team behind); nobody is moved mid-round. (3) Teams **Crimson** and **Azure**: team colour on every plate border, a name tag over teammates (arena names are otherwise hidden), team colours on the scoreboard, kill list and feed. (4) Abilities never affect teammates, and teammates never clash. (5) Spawns stay random, kept away from enemies only. (6) Scoreboard: YOUR TEAM · clock · enemy team; kill list with your team first. (7) Yen and kill leaderboards unchanged (¥500 per elimination, no win bonus). (8) Ties: same as FFA (sudden death, next team to lead wins, 30 s alerts). Rules in `Lib/TeamRules` + `MatchCore` |
| Wrong codes | **1st wrong code in a life → screen shake; 2nd wrong code in the same life → the submitter is eliminated** (no credit/yen to anyone; normal 3 s respawn). Counter resets every life (approved) |
| Stale codes | A code retired in the last 5 s (someone else got the target first) → "already down", no strike. After 5 s it is an ordinary wrong code |
| Anti-flood | 0.3 s server debounce between submissions; never counts as a strike |
| Abilities | Approved sheet in `docs/ABILITIES.md`. Q = mild, E = ultimate (two on-screen buttons on touch). Server-authoritative: `Lib/AbilityRules` (cooldowns, respawn rule, hit geometry) + `Systems/AbilityService` + one module per character in `Systems/Abilities`. An input lock is recorded in `MatchCore` and rejects submissions with `locked` (never a strike, capped at 2 s, protected fighters immune). Knockbacks and the grapple pull are applied by the affected player's own client (Roblox simulates characters there) |
| Code entry | F / CODE button opens the box. **Confirming a full 4-digit code, right or wrong, closes it; the next code needs F / CODE again** (owner rule, 2026-09-23). The result shows as a HUD toast. An incomplete code doesn't count as confirming: the box stays open and asks for all 4 digits |
| Spawn protection | **For 3 s after every spawn (round start, respawn, mid-round join) the fighter has no plate for anyone and sees no plates** (owner rule, 2026-09-23). Enforced on the server: no codes exist in either direction until it ends, and submissions answer "protected" (no strike). Dying also wipes your own view, so numbers remembered from a previous life never land. Retired codes aren't reissued to the same observer for 30 s |
| Run FOV | Camera FOV widens 70° → 96° while running on the ground, easing back when you stop; held while airborne (owner request: "drastic") |
| Elimination | Exactly 1 elimination + ¥500 to the attacker; victim respawns after 3 s. No line-of-sight check on submit: cover hides numbers, it doesn't block a remembered one. **LOS-on-submit is a possible future variant, not the default** |
| Movement | WalkSpeed 24 (Roblox default 16); no sprint key |
| Plates | **Approved by the owner after testing (2026-09-23).** **Readable only within 11 studs (owner, 2026-09-23; was 7) AND while the fighter faces you (±60°)** (owner rule, 2026-09-23). Enforced on the server: a code is only *disclosed* to an observer once range + facing + clear line of sight hold (small latency slack), so a modified client can't read numbers from afar. **Every opponent always carries a visible blank plate ("••••") within 60 studs of your fighter; the digits replace the mask only while the rule holds** (owner rule, 2026-09-23 — "players can see there is a plate but cannot see the numbers until being faced"). A revealed number stays up 0.5 studs / 5° past the rule so it doesn't flicker. Draw distances are measured from your fighter, not the camera (a camera-based `MaxDistance` culled plates in third person). Spawn-protected fighters show no plate at all. 2 × 0.8 studs (owner, 2026-09-23; was 1.3 × 0.5), just above the tallest point of the avatar incl. accessories, depth-tested. A code you have genuinely seen stays valid to type until it's retired |
| Arena spawns | Random anywhere on the map, nothing marks them (owner rule): sampled on open ground inside the map's `SpawnArea`, never inside cover, as far as possible from living opponents (≥30 studs when possible) |
| Sprint feel | Anime sprint package on top of the run FOV: a few faint edge speed lines (toned down 2026-09-23: 8 lines, was 36) + vignette, camera lean into turns and stride bob, ninja-run pose (lean forward, arms back) on every running fighter, hand wind trails, foot dust. All tunable in Constants |
| Persistence | **Built 2026-09-23 (Phase 3 item 4).** One DataStore record per player (`NAU_Profiles_v1`, key `u_<userId>`): `{version, yen, owned, equipped, session?, updated}`. Saved: yen, characters bought for yen, the equipped character (free characters are always owned; Robux ones will come from Game Passes and are never trusted from a save). Everything loaded is sanitised (`Lib/ProfileData`). **Session lock**: the server a player is in holds their record; a join waits (4 s × 8) for another server's fresh lock, then takes it over; a lock not renewed for 180 s is stale. A save only writes while this server still holds the lock, so a server that lost it never overwrites newer progress. Autosave every 60 s (renews the lock), save + release on leaving and on shutdown (BindToClose, up to 25 s). Yen earned while the profile loads is kept on top. Without DataStores the session runs unsaved and the player gets a toast. **Studio uses separate stores** (every store name + `_Studio`), so testing never touches live saves or leaderboards |
| Passive yen | **Owner, 2026-09-23.** Every player in the server, lobby or match: ¥50 every 2 min (playtime) + ¥100 per Roblox friend in the same server every 5 min (friend booster, counted at payout time). Clocks start at join; saved like any yen. Rules in `Lib/IncomeRules`, applied by `Systems/IncomeService`; friendships looked up once per pair (`IsFriendsWith`, failure = not friends) |
| Robux slots | Game Passes; ids/prices configurable, never invented. Deferred (approved) |
| Robux yen bundles | **Approved 2026-09-23, not built (waiting for the owner's Developer Product ids).** Four Developer Products: ¥5,000 / ¥12,000 / ¥27,500 / ¥75,000 (Robux prices set by the owner on Roblox; suggested 49 / 99 / 199 / 499 R$). A YEN tab in the holo shop, plus a "get more yen" button beside "NEED ¥X MORE". Every receipt is recorded in the player's saved profile before `PurchaseGranted` is returned (duplicates never pay twice; a crash means Roblox retries). Built together with the Sazuki/Gozen Game Passes (item 6) |
| Yen ladder | Placeholder (approved as placeholder): 1,500 / 3,000 / 5,000 / 7,500 / 10,000 / 13,000 |

## Phase 4 (built 2026-09-23)

| Topic | Decision |
|---|---|
| Settings | Gear button top-right (below Roblox's top bar, yen counter to its left). MOTION: speed lines, camera sway, wide running view, screen shake (off → red edge flash instead, so a wrong code is still signalled). VISUALS: crowd Auto / Off / Low / Medium / High (changes rebuild the crowd at once). AUDIO: music and effects volume. Schema shared by client and server (`Modules/Settings`); the server validates every change (all or nothing, one per 0.2 s) and keeps it in the saved profile (`settings`). Hidden state setting `tutorialDone` |
| How to play | Five cards (different number per observer; range + facing; type to eliminate; two misses; abilities and winning). Opens by itself on a first visit (lobby, once the profile loads) until finished or skipped; HOW TO PLAY in settings reopens it (`Controllers/TutorialController`) |
| Phones / tablets | "Phone" = the screen's short side ≤ 500 px (Roblox's own rule). Touch buttons cluster round Roblox's jump button: [E][Q] above [CODE][jump] (`UI.touchCluster`). Touch code entry is two columns (code + keypad) to fit a sideways phone; the kill list hides while it's open on phones and shows 6 rows (your own row always). Touch targets ≥ 44 pt, text ≥ 11 pt. The shop has a compact phone layout (700-unit canvas, scrolling roster) and hides Roblox's touch controls while open |
| Stress test | Studio-only bots (`NAU_DevStressBots`, `Systems/StressTestService`) wearing the player's avatar, running with its run animation; the client dresses them like fighters. Measured on the owner's PC with 12 fighters + full crowd: 60 fps average, 99% of frames ≤ 20 ms, server physics 0.94 ms (details in HANDOFF) |
| Security review | Every client-callable remote checked (validation, identity, rate limits, cost). Fixed: FIGHT / leave-queue rate-limited (0.5 s; each one broadcast to everyone); ability aim rejects infinite vectors (would have made NaN positions). Known and accepted: characters are client-simulated (Roblox), so movement speed/teleports and ability knockbacks aren't server-verified; a server-side movement check is a recommended follow-up |
| Sound | All sounds through `src/client/Audio` (Music and Effects sound groups, set by the settings). Licensed library audio only (APM Music, Pro Sound Effects, DistroKid official), never user uploads; picks listed there and in HANDOFF, all verified to load. Lobby "Sunset Song", arena "Thunder over Kyoto"; effects for round start, eliminations, wrong code, 30 s alert, sudden death, win, ability casts (3D, 120 studs), income and the shop slots |

## Anti-brute-force reasoning

With ≤11 live targets among 10,000 codes, a random guess hits with p ≈ 0.0011. Two misses end a life
and a life costs ≥3 s, so brute force averages roughly 450 lives (~25+ minutes) per elimination —
useless — while a legitimate player who reads a number never pays anything.

## Round state machine

```
Waiting ──(≥MIN queued)──▶ Intermission ──(15 s)──▶ InRound ──(time cap / too few)──▶ RoundEnd ──(6 s)──▶ Waiting
   ▲                             │                    │  ▲
   └──(queue < MIN)──────────────┘                    │  └─ joiners while <12
                                                      ▼
   Player life:  Alive ──(eliminated / 2 misses / fell)──▶ Dead (3 s) ──▶ Protected (3 s: hidden + blind) ──▶ Alive (fresh codes both ways, strikes 0)
```

## Remote contract (`src/shared/Remotes.luau`, folder `ReplicatedStorage.NAURemotes`)

| Remote | Kind | Direction | Payload |
|---|---|---|---|
| RequestFight | Function | C→S | `()` → `{status}`: joined, queued, queued_round_ending, queued_match_full, already_queued, already_in_match, queue_full, rate_limited (FIGHT and leave-queue share a 0.5 s limit) |
| LeaveQueue | Function | C→S | `()` → `{status}` |
| GetRoundState / RoundState | Function / Event | C→S / S→all | `{seq, phase, endsAt, graceEndsAt, mode, mapName, suddenDeath, maxPlayers, minPlayers, participants[], queued[], scores[{userId,score,alive,protected,team?}], teamScores? ({teamName = eliminations}, team battle only), result}` |
| SubmitCode | Function | C→S | `(code: string)` → `{status, strikesLeft?, targetName?, yen?}`; status ∈ eliminated, wrong, self_eliminated, stale, teammate, protected, malformed, rate_limited, not_alive, not_in_match, round_over |
| GetMyCodes | Function | C→S | `()` → caller's own `[{target, code}]` (identity from the invocation, never the payload) |
| CodesChanged | Event | S→one observer | `{reset?, changes[{target, code or false}]}` — never broadcast |
| LifeState | Event | S→one player | `{alive, inMatch, respawnAt?, cause?, byName?, protectedUntil?}` |
| MatchFeed | Event | S→all | `{kind="eliminated", victim, attacker?, cause}` / `{kind="spawned", userId}` |
| RoundAlert | Event | S→each fighter in the match | `{kind="time_left", seconds, suddenDeath}` — the 30-second alert |
| UpdateCurrency | Event | S→one player | `{yen}` |
| IncomeNotice | Event | S→one player | `{source = "passive" or "friends", amount, friends?}` after passive yen is paid (HUD popup; the balance itself comes through UpdateCurrency) |
| Leaderboards | Event | S→all | `{serverTime, offline, boards = {AllTime, Weekly = {rows, you, syncedAt, resetAt?}}}`; rows = top 10 `{userId, name, kills, live, rank, delta}` (`Systems/LeaderboardService`) |
| GetLeaderboards | Function | C→S | `()` → the latest Leaderboards payload (for players who just joined) |
| PurchaseItem | Function | C→S | `(characterId)` → `{status, granted?, price?, yen}`; status ∈ bought, insufficient, owned, not_for_yen, unknown. Rules in `Lib/ShopRules` (yen tier N also grants every lower yen tier); check, spend and grant happen without yielding (`Systems/ShopService`) |
| ProfileState | Event | S→one player | `{status = "loaded" or "offline", settings}` once the saved profile has loaded, or when this session can't be saved (the client shows a toast for `offline`) (`Systems/ProfileService`). Cached in `ClientState.profile` (only the first listener gets an event fired before anyone listens) |
| SetSettings | Function | C→S | `({[key] = value})` → `{status = "ok" or "rate_limited" or "malformed", settings}`; validated against `Modules/Settings`, all or nothing, one change per 0.2 s |
| UseAbility | Function | C→S | `(slot: "mild" or "ultimate", aim: Vector3, eye: Vector3)` → `{status, readyAt?}` (aim = camera direction, eye = camera position, trusted only within 40 studs of the character); status ∈ ok, cooldown, casting, protected, not_alive, not_in_match, not_available, no_target, no_room, clashing, malformed. The aim is only a direction hint; every range/cone/line-of-sight check is server-side |
| EquipCharacter | Function | C→S | `(characterId)` → `{status, equipped?}`; status ∈ equipped, not_owned, in_fight, unknown. Allowed in the lobby or while waiting to respawn |
| AbilityState | Event | S→one player | `{equipped, character?, implemented?, mild = {name, readyAt}?, ultimate = {name, readyAt}?}` |
| AbilityFX | Event | S→all | `{kind, caster, ...}` visuals only, so every tell is visible to everyone. `kind = "cast"` (`character`, `slot`, `castSeconds`) is fired first for every accepted ability and drives the cast animation (`animations/Controllers/AbilityAnim`, guide in `docs/ANIMATING.md`). Also `guard_block` (`target`, `direction`), `clash` (`a`, `b`, `character`, `slot`, `duration`, `midpoint`) and `clash_end` (`a`, `b`, `midpoint`) |
| AbilityEffect | Event | S→one player | `{kind = "knockback", velocity}` / `{kind = "grapple", target, speed}` / `{kind = "clearCode"}` / `{kind = "lock", untilTime}` / `{kind = "clash", untilTime, face, partner}` / `{kind = "clash_end"}` |

Changes from the Phase 1 proposal: `SubmitCode` takes **only the typed code** (the server resolves the
target from the observer's own table, so a client can't probe specific players), and the separate
`ScreenShake` event was folded into the `SubmitCode` reply (`status = "wrong"`).

## Map contract

Every map builder in `assets/Builders/` returns a Model with:
- `PrimaryPart`: an unrotated root at floor level (so `PivotTo` places it exactly);
- `SpawnArea/`: invisible boxes; spawns are sampled at random inside them on open ground (terrain, or
  parts with attribute `Walkable = true`) with room for an avatar. Nothing in the map marks a spawn;
- optional `buildTerrain(origin)` / `clearTerrain(origin)` if the map uses terrain.

Arena origin is `y = 2` (MapService): terrain voxels are 4-stud cells centred on multiples of 4, so a map
that fills terrain to 2 studs below its floor gets a surface exactly at floor level.

Add a map = new builder + one line in `src/shared/Modules/MapRegistry.luau`.

**Map 1, "The Proving Grounds" (v2):** circular martial-arts examination stadium (field radius 72) on
grass-and-dirt terrain; tiered stands, roofed north stand, barred east/west gates, proctor's balcony with
guardian statues, torches and banners; field with a raised sparring platform, broken-pillar ring, rock
outcrops, trees, training posts, low wall ruins and craters. Cover is tagged `CoverClass` Tall / Low.

## Project layout (Rojo)

| Path | Studio location | Owner |
|---|---|---|
| `src/server` | ServerScriptService.Server (Script) — `Systems/`, `Lib/` (pure rules), `Tests/` | scripter |
| `src/shared` | ReplicatedStorage.Shared — `Remotes`, `Modules/` | scripter |
| `src/client` | StarterPlayerScripts.Client (LocalScript) — `Controllers/`, `ClientState`, `UI` | scripter |
| `animations` | ReplicatedStorage.Animations — motion/FX modules | animator |
| `assets` | ServerStorage.Assets — `Builders/` (maps), `Init/` (edit-mode preview) | modeler |

Sync: Rojo 7.4.4 is installed through Rokit (`aftman.toml` pins the version). Run `rojo serve` in the repo
and press **Connect** in the Rojo plugin in Studio; the repo is the source of truth.

Run the unit tests during Play, with the command bar set to the Server (fresh modules every run):
`print(require(game.ServerScriptService.Server.Tests.TestRunner).run())`
From the Edit-mode command bar Studio may serve cached copies of edited modules.

Solo testing in Studio: set attribute `NAU_DevMinPlayers = 1` on ServerScriptService (ignored outside Studio).

## Roster (in game)

| Slot | Character | Franchise | Tier |
|---|---|---|---|
| 1 | Goku | Dragon Ball | Free |
| 2 | Monkey D. Luffy | One Piece | Free |
| 3 | Krillin | Dragon Ball | Yen 1 (¥1,500) |
| 4 | Vegeta | Dragon Ball | Yen 2 (¥3,000) |
| 5 | Roronoa Zoro | One Piece | Yen 3 (¥5,000) |
| 6 | L | Death Note | Yen 4 (¥7,500) |
| 7 | Naruto | Naruto | Yen 5 (¥10,000) |
| 8 | Ichigo | Bleach | Yen 6 (¥13,000) |
| 9 | Sasuke | Naruto | Robux |
| 10 | Satoru Gojo | Jujutsu Kaisen | Robux |

### IP decision (recorded 2026-09-23, updated the same day)

The owner first chose the franchise character names; later on 2026-09-23 the owner **renamed the roster in
game**. Players now see only these names; the franchise is no longer shown on the pedestal card. Internal ids
(code, ability modules, portrait pipeline) keep the old keys and are never shown to players.

| Slot | Internal id | In game |
|---|---|---|
| 1 | Goku | Gokai |
| 2 | Luffy | Luffo |
| 3 | Krillin | Krillo |
| 4 | Vegeta | Vejaro |
| 5 | Zoro | Zorin |
| 6 | L | Eli |
| 7 | Naruto | Nariko |
| 8 | Ichigo | Ichiro |
| 9 | Sasuke | Sazuki (Robux) |
| 10 | Gojo | Gozen (Robux) |

Remaining recorded risk: the lobby portraits are silhouettes cut from franchise reference art the owner
supplied (no license confirmed) and the abilities are modelled on the franchises. No franchise attack names remain
("Instant Transmission" was renamed Phase Shift, 2026-09-23). Selling Robux passes for characters recognisable as licensed ones (Sazuki, Gozen)
is still the highest-risk part. The earlier original-name fallback list is superseded by the table above.

### Lobby bubble portraits

`tools/portraits/make-portraits.ps1` turns `art/reference/*` into 512×512 bubble portraits using the
crop table in `tools/portraits/portraits.csv`: cut-out, white sticker outline, sunburst bubble in the
character's colours. **Style (owner, 2026-09-23): silhouettes** — the figure is a flat dark shadow, so
only its outline shows ("recognizable but not colored in"); output in `art/portraits/silhouette/`.
`-Style color` still builds the old full-colour set in `art/portraits/`. Goku's reference was replaced
by the owner (`goku.png`; the old one is kept as `goku-old.jpg`). L's armchair is removed with the
`dropChair` + seed options, and L's bubble is light grey so the dark silhouette reads. Upload the images to
Roblox, then put each asset id in the character's `portrait` field in `CharacterDefs`; until then
bubbles show initials. `art/` is git-ignored because it holds third-party artwork.

Environments: the lobby ("The Still Harbor") keeps the owner's layout reference (avenue, bubbles on
pedestals, portal at the end) but was rebuilt 2026-09-23 as a walled limestone courtyard (owner: "cleaner
3D models"; water on the sides "covered off"; stone colonnade walls chosen over cliffs/trees): covered
colonnades with marble columns on both long sides, end walls with the FIGHT gate (ember energy field
between limestone pylons, braziers), three segmental stone arches over the avenue, cypress planters, iron
lamp posts, crimson banners and sconces. Built from parts only (no uploads, no third-party assets). Yen
shop (2026-09-23): the south wall moved back 32 studs (z 114 → 146), replacing the sealed harbour gate with
a garden that holds the shop cottage (`assets/Builders/ShopHouse`). It's a storybook cottage on stilts
*inspired by* an owner-supplied Dragon Ball frame (cream walls, red trim, diamond windows, blue arched door,
vines, framing trees), not a copy, same approach as the IP decision above. Its interior is a high-tech
hologram room used by the shop menu, whose style is futuristic holographic glass with neon edges, scanlines
and decorative katakana (no franchise text). Two floating kill leaderboards (all-time and weekly, global via
DataStores) flank the arrival plaza in the same holo style. The arena's stands are a 6-row bowl filled with a
client-built colosseum crowd of ~1,060 stylised spectators, all generic types with no franchise characters. A client-side lighting grade (`animations/Controllers/LightingFX`) gives the
lobby a warm late-afternoon look and restores the place's own lighting exactly inside a match. The
place's `Lighting.Technology` is unchanged (owner's choice). The arena ("The Proving Grounds") is an
original open examination ground.

UI style (owner, 2026-09-23: "cleaner and more aggressive", colours not distracting): charcoal slabs with
sharp corners, Oswald condensed display type, off-white text, one muted blood-red accent used as thin bars.
In-match HUD: a YOU · clock · LEAD scoreboard at the very top of the screen (owner, 2026-09-23), an ELIMINATIONS
leaderboard on the left (every fighter, most to least, you in gold), a draining spawn-protection bar, kill-feed rows with a
coloured edge, toasts, a big banner with a red slash, and a desaturated "ELIMINATED/MISFIRE" screen while
you wait to respawn. Every text panel sizes itself to its text so nothing spills out of its box.

## Acceptance scenarios — coverage

| # | Scenario | Phase 2 coverage |
|---|---|---|
| 1 | Different codes per observer; no cross-use | Unit tests; owner's 3-player check passed (2026-09-23) |
| 2 | Each observer's codes unique | Unit tests (12 players × 300 rounds, forced collisions) |
| 3 | Self / team / repeat / stale all fail | Unit tests |
| 4 | Exactly 1 elim + ¥500, 3 s respawn | Unit tests (credit); live timing check |
| 5 | 20 ends the correct mode | Unit tests (FFA + team logic); team mode not playable until Phase 3 |
| 6 | Mid-round join, cap 12 | Unit tests (cap); live join in the owner's 3-player check passed (2026-09-23) |
| 7 | Later yen tier grants earlier, never Robux | Phase 3 |
| 8 | Cooldowns after respawn | Phase 3 (abilities) |
| 9 | Character change applies next spawn | Phase 3 |
| 10 | Large accessory doesn't cover the plate | Passed in the owner's 3-player check (2026-09-23) |
| 11 | Reconnect keeps yen/unlocks | Phase 3 (persistence) |
| 12 | Malformed / forged / flooded requests do nothing | Unit tests (MatchCore); server handlers take identity from the invocation only |
| — | Spawn protection (hidden + blind 3 s) | Unit tests (4 cases); live solo check of timing and client UI; owner's 3-player check passed (2026-09-23) |
| — | Plates only within 2 steps + facing | Unit tests (5 geometry cases); server disclosure gate live; owner's 3-player check passed (2026-09-23) |
| — | Random hidden spawns | Live: 200 samples, none blocked, spread over the whole field; 12-player opening wave ≥30.5 studs apart |
