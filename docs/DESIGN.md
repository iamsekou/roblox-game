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
| 3 prep — Ability sheet | Proposed in `docs/ABILITIES.md`, **awaiting approval** |
| 3 — Team mode, economy, persistence, Robux entitlements, abilities, respawn character select | Not started (needs the ability sheet approved) |
| 4 — Polish, 5 more maps (plan only until map 1 plays well), 12-player stress test | Not started |

## Locked decisions

| Topic | Decision |
|---|---|
| Players / modes | ≤12 per match. 6v6 team or FFA. **Rounds are time-based with uncapped eliminations** (owner, 2026-09-23; replaced "first to 20"): most eliminations (player, or team total) when time runs out wins. Uniform random mode + map each round; **repeats allowed, no history** (approved) |
| Round cap | 8 min. Sole leader with ≥1 elimination wins; a tie → 60 s sudden death, next sole leader wins; sudden death expiring → draw |
| Intermission | 15 s. Min 2 queued players to start. Below 2 mid-round → 15 s grace for a joiner, then the round ends with no winner |
| Mid-round join | FIGHT joins instantly if the match has <12; otherwise the player is queued and drops in when a slot opens |
| After a round | 6 s results, everyone returns to the lobby and is auto-queued for the next round (can leave the queue) |
| Codes | 4-character strings `"0000"`–`"9999"`; leading zeros allowed; compared as strings, never numbers |
| Own plate | Not shown. Nobody holds a code for themself, so self-elimination by code is impossible by construction |
| Teammates (6v6) | **Do show plates** (visual consistency, approved). Submitting a teammate's code → "That's a teammate", no strike, no kill |
| Wrong codes | **1st wrong code in a life → screen shake; 2nd wrong code in the same life → the submitter is eliminated** (no credit/yen to anyone; normal 3 s respawn). Counter resets every life (approved) |
| Stale codes | A code retired in the last 5 s (someone else got the target first) → "already down", no strike. After 5 s it is an ordinary wrong code |
| Anti-flood | 0.3 s server debounce between submissions; never counts as a strike |
| Code entry | F / CODE button opens the box. **Confirming a full 4-digit code, right or wrong, closes it; the next code needs F / CODE again** (owner rule, 2026-09-23). The result shows as a HUD toast. An incomplete code doesn't count as confirming: the box stays open and asks for all 4 digits |
| Spawn protection | **For 3 s after every spawn (round start, respawn, mid-round join) the fighter has no plate for anyone and sees no plates** (owner rule, 2026-09-23). Enforced on the server: no codes exist in either direction until it ends, and submissions answer "protected" (no strike). Dying also wipes your own view, so numbers remembered from a previous life never land. Retired codes aren't reissued to the same observer for 30 s |
| Run FOV | Camera FOV widens 70° → 96° while running on the ground, easing back when you stop; held while airborne (owner request: "drastic") |
| Elimination | Exactly 1 elimination + ¥500 to the attacker; victim respawns after 3 s. No line-of-sight check on submit: cover hides numbers, it doesn't block a remembered one. **LOS-on-submit is a possible future variant, not the default** |
| Movement | WalkSpeed 24 (Roblox default 16); no sprint key |
| Plates | **Approved by the owner after testing (2026-09-23).** **Readable only within 11 studs (owner, 2026-09-23; was 7) AND while the fighter faces you (±60°)** (owner rule, 2026-09-23). Enforced on the server: a code is only *disclosed* to an observer once range + facing + clear line of sight hold (small latency slack), so a modified client can't read numbers from afar. **Every opponent always carries a visible blank plate ("••••") within 60 studs of your fighter; the digits replace the mask only while the rule holds** (owner rule, 2026-09-23 — "players can see there is a plate but cannot see the numbers until being faced"). A revealed number stays up 0.5 studs / 5° past the rule so it doesn't flicker. Draw distances are measured from your fighter, not the camera (a camera-based `MaxDistance` culled plates in third person). Spawn-protected fighters show no plate at all. 2 × 0.8 studs (owner, 2026-09-23; was 1.3 × 0.5), just above the tallest point of the avatar incl. accessories, depth-tested. A code you have genuinely seen stays valid to type until it's retired |
| Arena spawns | Random anywhere on the map, nothing marks them (owner rule): sampled on open ground inside the map's `SpawnArea`, never inside cover, as far as possible from living opponents (≥30 studs when possible) |
| Sprint feel | Anime sprint package on top of the run FOV: a few faint edge speed lines (toned down 2026-09-23: 8 lines, was 36) + vignette, camera lean into turns and stride bob, ninja-run pose (lean forward, arms back) on every running fighter, hand wind trails, foot dust. All tunable in Constants |
| Persistence | Profile pattern (session lock, retry/backoff, autosave, save-on-leave) — Phase 3. **Phase 2 yen is in-memory only** |
| Robux slots | Game Passes; ids/prices configurable, never invented. Deferred (approved) |
| Yen ladder | Placeholder (approved as placeholder): 1,500 / 3,000 / 5,000 / 7,500 / 10,000 / 13,000 |

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
| RequestFight | Function | C→S | `()` → `{status}`: joined, queued, queued_round_ending, queued_match_full, already_queued, already_in_match, queue_full |
| LeaveQueue | Function | C→S | `()` → `{status}` |
| GetRoundState / RoundState | Function / Event | C→S / S→all | `{seq, phase, endsAt, graceEndsAt, mode, mapName, suddenDeath, maxPlayers, minPlayers, participants[], queued[], scores[{userId,score,alive,protected}], result}` |
| SubmitCode | Function | C→S | `(code: string)` → `{status, strikesLeft?, targetName?, yen?}`; status ∈ eliminated, wrong, self_eliminated, stale, teammate, protected, malformed, rate_limited, not_alive, not_in_match, round_over |
| GetMyCodes | Function | C→S | `()` → caller's own `[{target, code}]` (identity from the invocation, never the payload) |
| CodesChanged | Event | S→one observer | `{reset?, changes[{target, code or false}]}` — never broadcast |
| LifeState | Event | S→one player | `{alive, inMatch, respawnAt?, cause?, byName?, protectedUntil?}` |
| MatchFeed | Event | S→all | `{kind="eliminated", victim, attacker?, cause}` / `{kind="spawned", userId}` |
| UpdateCurrency | Event | S→one player | `{yen}` |
| PurchaseItem | Function | C→S | reserved for Phase 3 (answers `coming_soon`) |

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

### IP decision (recorded 2026-09-23)

The owner overrode the original-character plan: the game uses the franchise character names, and the
lobby bubbles use portraits cut from reference art the owner supplied. No license has been confirmed.
Recorded risk: franchise holders can issue takedowns against Roblox experiences, and selling Robux
passes for licensed characters (Sasuke, Gojo) is the highest-risk part. If the experience ever needs
to go IP-clean, this is the prepared fallback mapping (names only; looks and abilities would also need
to be distinct):

| Slot | In game | Original fallback |
|---|---|---|
| 1 | Goku | Kael, the Wandering Cultivator |
| 2 | Monkey D. Luffy | Rennick Voss, the Coilreach |
| 3 | Krillin | Doss, the Ringcaster |
| 4 | Vegeta | Thren Vask, the Iron Commander |
| 5 | Roronoa Zoro | Kestrel Doriane, the Stance-Shifter |
| 6 | L | Whisper, the Analyst |
| 7 | Naruto | Sable Fennshade, the Mirage |
| 8 | Ichigo | Kaidon Reave, the Riftblade |
| 9 | Sasuke | Corvin Ashwraith, the Stormmark |
| 10 | Satoru Gojo | Aureth, the Unseen |

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
between limestone pylons, braziers) and a sealed harbour gate, three segmental stone arches over the
avenue, cypress planters, iron lamp posts, crimson banners and sconces. Built from parts only (no uploads,
no third-party assets). A client-side lighting grade (`animations/Controllers/LightingFX`) gives the
lobby a warm late-afternoon look and restores the place's own lighting exactly inside a match. The
place's `Lighting.Technology` is unchanged (owner's choice). The arena ("The Proving Grounds") is an
original open examination ground.

UI style (owner, 2026-09-23: "cleaner and more aggressive", colours not distracting): charcoal slabs with
sharp corners, Oswald condensed display type, off-white text, one muted blood-red accent used as thin bars.
In-match HUD: a YOU · clock · LEAD scoreboard, a draining spawn-protection bar, kill-feed rows with a
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
