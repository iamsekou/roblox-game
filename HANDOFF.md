# HANDOFF — Numbers Assassin Universe

Last updated: 2026-09-23 (end of the second working session). Current state first; the session history is at the end.

Labels: **[Verified]** = checked directly (test output, measurement, screenshot, or file/Studio inspection).
**[Owner-reported]** = the owner tested it; Claude didn't observe it. **[Assumption]** = believed true, not checked.
**[Not tested]** = not exercised.

## 1. Current goal

Phase 3 is under way (plan approved 2026-09-23, all 8 items). Done so far: item 1 (ability system, all 10 characters),
item 2 (Q/E keys + touch buttons), item 3 (choose character at the pedestal or on the respawn screen). The owner is
now play-testing abilities with several clients. Remaining Phase 3 items, in the approved order:
4. saved progress (yen, owned characters, equipped) — needs the owner to switch on *Game Settings → Security →
   Enable Studio Access to API Services* before it can be tested in Studio;
5. yen shop at the pedestals (placeholder prices 1,500–13,000; buying a tier unlocks the tiers below);
6. Robux characters via Game Passes — the owner must create the passes and supply their ids (never invent ids);
7. Team 6v6 mode alongside FFA;
8. hand-keyframed character animations (Animation Editor; Claude writes playback code + an authoring guide).

Don't start the next item until the owner's current ability test comes back (section 8).

## 2. Implemented systems

| System | Where | Status |
|---|---|---|
| Round flow: queue → 15 s intermission → **8-min timed round, uncapped eliminations** (most eliminations wins; tie → 60 s sudden death → draw) → 6 s results → lobby + auto-requeue; leave queue; mid-round join; full-match queueing; 15 s under-population grace | `Systems/RoundManager`, `Lib/MatchCore` | Unit-tested [Verified]; solo round start [Verified]; a full 8-min round end [Not tested] |
| FFA (only enabled mode; Team6v6 rules exist in `MatchCore`, disabled) | `Constants.ENABLED_MODES` | FFA [Verified]; team rules unit-tested only |
| Per-observer 4-digit codes; server disclosure gate (11 studs + facing ±60° + line of sight, small latency slack) | `Lib/CodeBook`, `Systems/NumberAssignmentService`, `Modules/PlateVisibility` | Unit-tested [Verified]; owner's 3-player check passed [Owner-reported] |
| Number plates: blank "••••" over every opponent within 60 studs; digits only within 11 studs while their front faces you; 2 × 0.8 studs; depth-tested | `Controllers/NumberPlateController` | Owner-approved after testing [Owner-reported]. Regression (no plates in multi-client tests) fixed 2026-09-23 — see history; re-confirmation pending in the owner's current test |
| Code entry: F / CODE button; confirming a full code closes the box; results as HUD toasts | `Controllers/SubmissionController` | [Verified] solo; touch keypad [Not tested] |
| Eliminations: exactly 1 elim + ¥500; strike rule (2nd wrong code in a life = self-elimination); stale window 5 s; 0.3 s debounce; ability input locks answer `locked` (never a strike) | `Lib/MatchCore`, `Systems/EliminationService` | Unit-tested [Verified]; live kills between players [Owner-reported, 3-player check] |
| Respawn 3 s; spawn protection 3 s (hidden + blind, no submitting, no abilities, immune to abilities) | `Systems/RoundManager`, `Lib/MatchCore`, `Systems/AbilityService` | Unit-tested + solo [Verified] |
| **Abilities, all 10 characters** (approved sheet + owner changes, `docs/ABILITIES.md`): Q = mild (8 s), E = ultimate (20 s; −10 s per respawn; cooldown belongs to the player, not the character); effect durations ×1.75; reading exceptions for Krillo/Sazuki/Gozen (line of sight only); Shadow Clone decoys; Flash Step / Blink go where you look | `Lib/AbilityRules`, `Systems/AbilityService`, `Systems/Abilities/*`, `Controllers/AbilityController`, `animations/Controllers/AbilityFX` | Every mild + ultimate fired solo with self-effects measured [Verified]. Owner said abilities "feel solid" (slice 1) [Owner-reported]. **Every effect on another player** [Not tested by Claude] |
| Choose a character: EQUIP on the pedestal card, or the NEXT LIFE grid on the respawn screen; never mid-life | `AbilityService`, `LobbyController`, `AbilityController` | [Verified] solo |
| Ownership: free starters (Gokai, Luffo) live; **every character unlocked in Studio** (`Constants.DEV_UNLOCK_ALL_IN_STUDIO`, owner request) | `AbilityService.owns` | [Verified] solo (picker showed 10) |
| Roster renamed in game: Gokai, Luffo, Krillo, Vejaro, Zorin, Eli, Nariko, Ichiro, Sazuki (Robux), Gozen (Robux). Internal ids keep the old keys (never shown) | `Modules/CharacterDefs` | Lobby bubbles [Verified screenshot] |
| HUD (battle style: charcoal, Oswald, muted red): YOU · clock · LEAD scoreboard **at the very top**; ELIMINATIONS leaderboard on the left (most to least, you in gold); yen + kill feed top-right; ability slots [Q][E] beside [F] CODE; toasts; banners; desaturated respawn screen | `Controllers/HUDController`, `UI` | Screenshots [Verified]; leaderboard with several players [Not tested] |
| Lobby "The Still Harbor": walled limestone courtyard (colonnades, end walls, FIGHT gate, arches, cypresses, lamps), 10 silhouette portrait bubbles; client lighting grade in the lobby only | `assets/Builders/Lobby`, `animations/Controllers/LightingFX` | Screenshots [Verified]; flicker fix [Not tested visually] |
| Arena "The Proving Grounds": circular stadium, terrain, dense cover; random unmarked spawns | `assets/Builders/ProvingGrounds`, `Systems/MapService` | [Verified] |
| Run feel: FOV 70°→96°, 8 faint speed lines, camera lean/bob, ninja-run pose, trails, dust | `animations/Controllers/RunFOV`, `SprintFX` | [Verified] numbers/screenshots |
| Yen: in memory only (resets on rejoin) | `Systems/EconomyService` | Persistence is Phase 3 item 4 |
| Portrait pipeline: reference art → 512 × 512 silhouette bubbles | `tools/portraits/*` → `art/portraits/silhouette/` (git-ignored) | Uploaded, ids in `CharacterDefs` [Verified] |

## 3. Repository state

- **Branch `main`, commit `268d746`, pushed to `origin` (github.com/iamsekou/roblox-game)** [Verified]. History:
  `7719c2f` initial Rojo setup → `a76340c` Phase 2 vertical slice → `268d746` Phase 3 abilities + owner fixes.
  Branch `phase2-vertical-slice` points at the same commit. Working tree clean before this handoff edit [Verified].
- 54 synced Luau files; repo ↔ Studio identical by per-file length + rolling hash (combined 1440775114) [Verified].
- Git-ignored, on disk only: `art/reference/*` (owner's reference images, incl. new `goku.png`; old one kept as
  `goku-old.jpg`) and `art/portraits/*` (colour set + `silhouette/` set with contact sheets).
- Git warns LF → CRLF on many files (warning only).

## 4. Outside the repo (Studio, Roblox, machine)

- **Uploaded to Roblox under the owner's account** (each with the owner's approval): 10 colour portraits (superseded),
  10 silhouette portraits, then a cleaned Gokai silhouette. Live ids are in `CharacterDefs.luau`. Colour-set ids for
  rollback: Goku 122903496846585, Luffy 79671763279611, Krillin 91771744627475, Vegeta 72069376256964,
  Zoro 70883204029177, L 102258380243632, Naruto 104230049635730, Ichigo 70771063323340, Sasuke 132657356363462,
  Gojo 117842427607485. Previous Gokai silhouette 78521110761755.
- Deleted in Studio (first session): stray scaffold copies `StarterPlayer.StarterPlayerScripts` LocalScript and
  `ReplicatedStorage.Remotes`.
- Place settings untouched by Claude: `Lighting.Technology` (owner chose "keep current"), `StreamingEnabled = true`,
  `CharacterAutoLoads = true` (server sets false at runtime), HttpService off, template Baseplate/SpawnLocation.
  Nothing has been published [Verified: never done].
- Rojo 7.4.4 via Rokit. `rojo serve` is running detached (pid 30868 = Rokit shim, 9816 = rojo) [Verified]; log at
  `%USERPROFILE%\.rokit\rojo-serve.log`. It won't survive a reboot: run `rojo serve` in the repo root, then Connect.
- Git Bash can't fork on this machine; use PowerShell.

## 5. Architecture decisions (details in `docs/DESIGN.md`)

- Repo is the source of truth; Rojo syncs it; Studio is never edited directly.
- Rules live in pure, unit-tested modules (`Lib/CodeBook`, `Lib/MatchCore`, `Lib/AbilityRules`,
  `Modules/PlateVisibility`); systems are thin adapters.
- Server-authoritative: identity from the invocation; `SubmitCode` carries only the typed code; per-observer codes
  reach a client only through the disclosure gate; abilities are requested, validated and resolved server-side.
  The client's aim and camera position are hints only (normalised, camera trusted within 40 studs).
- Ability effects on another player: locks recorded in `MatchCore`; reading grants, blinding, hidden plates and clone
  roots in `NumberAssignmentService`; speed as a per-player multiplier stack; knockbacks/pulls simulated by the
  affected player's own client (Roblox physics ownership).
- Naruto's clones are MatchCore "decoys" with ids below −1,000,000,000 (Studio test players are −1, −2, …).
- Every tunable in `Constants` (effect durations scale through `EFFECT_TIME` = 1.75); every remote in `Remotes`.
- UI and maps are built in code. Maps follow the map contract (unrotated PrimaryPart, SpawnArea, terrain hooks).

## 6. Tests

- Unit tests (`TestRunner`, run in Play on the Server): **62/62** [Verified, last run 2026-09-23].
  Specs: CodeBook 11, MatchCore 28, PlateVisibility 10, AbilityRules 13.
- Last solo measurements [Verified]: clone runs ~18 studs/s at standing height for its 7 s (94 studs, steering round
  cover); Flash Step lands 0.1–0.2 studs from the aimed spot (10/16/21 studs); Blink lands exactly at 20 studs;
  Vejaro Pride 24 → 31.2; Zorin Guard 24 → 12 → 24; charge slows restore to 24; all 10 characters equip and cast.
- Owner-reported: 3-player check passed; abilities (Gokai/Luffo) feel solid; bugs reported and fixed (see history).
- **Not tested by Claude** (needs 2+ players): every ability effect on another player, clone plates/popping,
  reading at range, Hunter's Eye on a real target, leaderboard ordering with several scorers. Also: touch layout,
  VFX in motion, 12-player performance (lobby 863 parts, ~60 point lights).

## 7. Known issues and risks

- Multi-client behaviour can only be checked by the owner (Studio's Clients and Servers test isn't reachable from
  Claude's tools). Solo Play uses the real positive user id, so it can't catch negative-id bugs.
- Lock cap is now 3.5 s (the approved 2 s × the owner's 1.75). Easy to revert in `Constants.MAX_INPUT_LOCK`.
- Placeholder balance numbers are marked "placeholder" in `Constants`.
- Disclosure slack (2.5 studs, 15°) not tuned against real latency [Assumption: enough].
- Studio input automation can't press number-row keys (keypad used in tests); real players are fine [Assumption].
- The Edit-mode command bar serves stale modules; run tests in Play/Server.
- Speed lines, camera bob and wide FOV may bother motion-sensitive players; no settings toggle yet.
- Cosmetic: Eli's silhouette keeps a small scrap of the chair frame at its left edge.
- IP: names are now original, but the silhouettes come from franchise art and the abilities are modelled on the
  franchises; Robux passes for Sazuki/Gozen remain the highest-risk part (recorded in DESIGN.md).
- `DEV_UNLOCK_ALL_IN_STUDIO` must stay Studio-only (it is: `RunService:IsStudio()`); set false if not wanted.

## 8. Single next task

**Owner's multi-client ability test** (Test → Clients and Servers, 2–3 players; every character unlocked in Studio).
Priority checks:
1. Blank plates are back over every opponent; digits within 11 studs when faced (regression fix).
2. Gokai/Nariko/Vejaro hits show "JAMMED" on the target and block submitting.
3. Nariko's clone shows a plate to others; typing it says "It was a clone!" (no strike).
4. Krillo's flare whites out a facing opponent; Krillo/Sazuki/Gozen read marked plates far away, not through walls.
5. Sazuki's Hunter's Eye marks a real opponent and seals their Q; Zorin's Iron Guard ignores knockback.
6. The leaderboard sorts correctly with several scorers; Flash Step / Blink feel right.

Fix what fails and tune numbers from the owner's feedback; then Phase 3 item 4 (saved progress).

---

## Session history (2026-09-23, condensed)

- **Session 1:** Phase 2 vertical slice built (round flow, codes, plates, code entry, eliminations, respawn, lobby,
  arena, HUD, run feel, portraits). Rojo mapping fixed.
- **Plates:** plate appeared only from certain angles → camera-based `MaxDistance` removed; blank plates always
  shown, digits only when faced; size 2 × 0.8; reading distance 7 → 11. Owner approved plates.
- **Owner changes:** speed lines cut 36 → 8; code box closes on submit; silhouette portraits (+ new Goku art,
  cleaned strand); timed rounds with uncapped eliminations; lobby rebuilt as a walled courtyard + lighting grade;
  battle-style UI with self-sizing panels; lobby z-fighting fixed. Owner's 3-player check passed.
- **Phase 3:** ability sheet approved (Goku and Gojo changed; Krillin/Sasuke/Gojo reading exceptions); all 8 plan
  items approved. Slice 1: ability system + Goku + Luffy (walk-speed restore bug fixed). Slice 2: the other 8
  characters (Blink `no_room` bug fixed).
- **Regressions/bugs fixed after owner testing:** no plates in multi-client tests (negative Studio user ids treated
  as clones); Hunter's Eye never found a target (camera pitch); Shadow Clone flew into the sky (its ground raycast hit
  its own torso) and then barely moved (now steers round cover); dashes overshot ~4 studs (now stop on their point).
- **Owner changes:** effect durations ×1.75 (Deduction set to 7 s); roster renamed; "Instant Transmission" →
  "Phase Shift"; leaderboard added; HUD moved to the top; Flash Step and Blink go where you look.
- Committed and pushed to `main` (`268d746`) at the owner's request.
