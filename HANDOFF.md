# HANDOFF — Numbers Assassin Universe

Last updated: 2026-09-23. Created this session; no earlier handoff file existed in the repo.

Labels: **[Verified]** = checked directly in this session (test output, measurement, screenshot, or
file/Studio inspection). **[Assumption]** = believed true but not directly checked. **[Not tested]** = not exercised.

## 1. Current goal

Finish verifying the Phase 2 vertical slice, plus the owner's follow-up changes (2.1 and 2.2), before
Phase 3 starts. Phase 3 (team mode, economy/persistence, Robux entitlements, abilities) is blocked on:
1. ~~the multi-client verification~~ — **passed, reported by the owner 2026-09-23** (see below), then
2. the owner approving the ability sheet (`docs/ABILITIES.md`).

Do not begin another feature until the next task is done.

## 2. Implemented systems

| System | Where | Status |
|---|---|---|
| Round flow (**time-based, uncapped eliminations** since 2026-09-23; no "first to 20"): queue → 15 s intermission → round → 6 s results → lobby, auto-requeue, leave queue, mid-round join, full-match queueing, 15 s under-population grace, 8-min cap → sudden death → draw | `Systems/RoundManager` | Built. Solo live run [Verified] before the latest RoundManager edits; round start re-run after them [Verified]; round *end* not re-run since [Not tested] |
| FFA mode (the only enabled mode; Team6v6 logic exists in `MatchCore` but is disabled) | `Lib/MatchCore`, `Constants.ENABLED_MODES` | FFA [Verified]; team logic unit-tested only |
| Per-observer 4-digit codes (unique per observer, never self, retired codes kept out of reuse 30 s) | `Lib/CodeBook` | Unit-tested [Verified] |
| Server-side plate disclosure gate: a code reaches a client only within 11 studs (+2.5 slack), target facing them (±60°, +15° slack), clear line of sight | `Systems/NumberAssignmentService`, `Modules/PlateVisibility` | Geometry unit-tested [Verified]; gate with two real players [Not tested] |
| Number plates (**owner-approved after testing, 2026-09-23**; reworked after "only appears from a specific angle"): every opponent always shows a blank "••••" plate within 60 studs of your fighter; digits appear only within 11 studs while their front faces you (±60°), with 0.5 stud / 5° anti-flicker hold. Protected fighters show none. 2 × 0.8 studs, above the tallest accessory, depth-tested | `Controllers/NumberPlateController`, `Modules/PlateVisibility.plateMode` | Rule unit-tested [Verified, 41/41]; synced + parity [Verified]; solo Play: no errors, 0 plates in lobby as expected [Verified]; rendering with a second player [Not tested] |
| Code entry: F key / CODE button, digits read while moving, Enter to submit, touch keypad. Confirming a full code (right or wrong) closes the box; result shown as a HUD toast (owner rule, 2026-09-23) | `Controllers/SubmissionController` | Keyboard flow [Verified] (keypad keys only, see issues); close-on-submit [Verified 2026-09-23: incomplete stays open, wrong → closes + toast after 0.06 s, self-elim → closes]; touch keypad [Not tested]; shrunken panel not re-screenshotted [Not tested] |
| Eliminations: server-judged; exactly 1 elim + ¥500; strike rule (1st wrong = shake, 2nd = self-elim, no credit); stale window 5 s; 0.3 s debounce | `Lib/MatchCore`, `Systems/EliminationService` | Rules unit-tested [Verified]; strike rule live [Verified] (before spawn protection existed); live kill between players [Not tested] |
| Respawn: 3 s; spawn protection 3 s (hidden + blind, can't submit); death wipes your own view | `Systems/RoundManager`, `Lib/MatchCore` | Unit-tested [Verified]; solo timing and UI [Verified]; between two players [Not tested] |
| Random, unmarked arena spawns, away from opponents | `Systems/MapService.findArenaSpawn/findSpawnIn` | Live sampler test [Verified] |
| Lobby "The Still Harbor" (**rebuilt 2026-09-23**): walled limestone courtyard, colonnades both sides, end walls, FIGHT gate, stone arches, cypresses, lamps, 10 portrait bubbles on pedestals; client lighting grade `LightingFX` | `assets/Builders/Lobby`, `animations/Controllers/LightingFX` | [Verified] screenshots (spawn view, gate, overview): no water visible from the courtyard; 863 parts; lighting switches to the lobby grade in the lobby and back to the exact arena snapshot in a match |
| Arena v2 "The Proving Grounds": circular stadium, terrain, cover | `assets/Builders/ProvingGrounds` | [Verified] screenshots + terrain probe |
| HUD (**battle restyle 2026-09-23**: YOU · clock · LEAD scoreboard, protection bar, self-sizing feed/toasts, banner, desaturated death screen) | `Controllers/HUDController`, `UI` (new style kit) | [Verified] top bar/score/yen screenshots; protection banner states read from client; kill feed with a real kill [Not tested] |
| FIGHT button (230×58, gradient plate, Bangers lettering tilted −4°, pulse/sweep/punch) + queue status | `Controllers/LobbyController`, `UIMotion` | Ready state [Verified] screenshot; QUEUED steel state after the redesign [Not tested] visually |
| Podium inspect card (ProximityPrompt) | `Controllers/LobbyController` | [Not tested] live |
| Yen: in memory only, resets on rejoin (persistence is Phase 3) | `Systems/EconomyService` | ¥0 → no award on self-elim [Verified]; ¥500 award in a real kill [Not tested] |
| Run feel: FOV 70°→96°; SprintFX speed lines, vignette, camera lean/bob, ninja-run pose, hand trails, foot dust | `animations/Controllers/RunFOV`, `SprintFX` | FOV [Verified] numbers; lines/lean [Verified] screenshot; pose [Verified] numbers; trails/dust exist [Verified], appearance [Not tested] |
| Other FX: camera shake, elimination flash/fade, spawn ring, portal pulse, camera faces forward after spawning | `animations/Controllers/*` | Camera heading fix [Verified] (dot 1.00); shake/elimination FX/portal pulse visuals [Not tested] (the shake fires on the "wrong" result, which was verified) |
| Portrait pipeline: reference art → 512×512 bubble portraits; **silhouette style** (owner, 2026-09-23) + new Goku reference | `tools/portraits/*` → `art/portraits/silhouette/` | Silhouettes generated, contact sheet reviewed [Verified]; uploaded with the owner's "Proceed" and live in `CharacterDefs` — lobby screenshot shows them [Verified] |

## 3. Exact files changed

Compared with the only commit, `7719c2f Initial Rojo project setup`. **Nothing is committed.** [Verified via `git status`]

Modified (5): `.gitignore` (added `art/`), `default.project.json` (fixed mapping: nested
`Server`/`Client`/`Shared`, added `Assets` + `Animations`, removed the non-existent `src/gui`),
`src/client/init.client.luau`, `src/server/init.server.luau`, `src/shared/Remotes.luau` (kept
`PurchaseItem`/`UpdateCurrency`, added the rest).

Added (42):
- `CLAUDE.md`, `HANDOFF.md`, `docs/DESIGN.md`, `docs/ABILITIES.md`
- `src/server/Lib/`: `CodeBook.luau`, `MatchCore.luau`
- `src/server/Systems/`: `EconomyService.luau`, `EliminationService.luau`, `MapService.luau`,
  `NumberAssignmentService.luau`, `PlayerLifeService.luau`, `RoundManager.luau`
- `src/server/Tests/`: `TestRunner.luau`, `TestUtil.luau`, `CodeBook.spec.luau`, `MatchCore.spec.luau`, `PlateVisibility.spec.luau`
- `src/shared/Modules/`: `Constants.luau`, `CharacterDefs.luau`, `MapRegistry.luau`, `PlateVisibility.luau`
- `src/client/`: `ClientState.luau`, `UI.luau`, `Controllers/FXController.luau`, `Controllers/HUDController.luau`,
  `Controllers/LobbyController.luau`, `Controllers/NumberPlateController.luau`, `Controllers/SubmissionController.luau`
- `animations/Controllers/`: `CameraShake.luau`, `CharacterFade.luau`, `EliminationFX.luau`, `PortalFX.luau`,
  `RunFOV.luau`, `SpawnFX.luau`, `SprintFX.luau`, `UIMotion.luau`
- `assets/Builders/Lobby.luau`, `assets/Builders/ProvingGrounds.luau`, `assets/Init/BuildPreview.luau`
- `tools/portraits/PortraitMaker.cs`, `tools/portraits/make-portraits.ps1`, `tools/portraits/portraits.csv`

Git-ignored, on disk only (22): `art/reference/*` (the owner's 11 reference images, renamed) and
`art/portraits/*` (10 portraits + `_contact_sheet.png`).

Repo ↔ Studio parity: all 38 synced Luau files match by length + hash [Verified, end of session].

## 4. Changes outside the repo files (Studio, Roblox, machine)

- **Deleted in Studio**: a stray LocalScript `StarterPlayer.StarterPlayerScripts` (with an empty `Controllers`
  folder) and `ReplicatedStorage.Remotes` (ModuleScript). Both were copies of the original scaffold files, left
  by the old broken mapping; their contents are in git history. [Verified absent now]
- **Uploaded to Roblox under the owner's account** (with the owner's "Proceed"): 10 portrait images. The asset IDs
  are in `CharacterDefs.luau`. They display in game [Verified]; whether moderation could still reject them later [Assumption: possible].
- **Rojo plugin permission**: the owner granted Script Injection; sync now works [Verified].
- **Left untouched**: the template `Baseplate` and `SpawnLocation` in Workspace; the game world is built 3000+
  studs away at runtime [Verified]. No terrain is saved in the place; lobby sea and arena terrain are generated
  at runtime [Verified: Edit-mode voxels are Air]. `StreamingEnabled = true`; the place's
  `CharacterAutoLoads = true` (the server sets it false at runtime); HttpService off [Verified]. No lingering
  test attributes [Verified].
- **Team Create**: edits made in Studio sync to the cloud place [Assumption]. Nothing was explicitly published [Verified: never done].
- **Machine**: `rokit trust rojo-rbx/rojo` + `rokit install` installed Rojo 7.4.4 [Verified].
  The old `rojo serve` (pid 9572) was stopped deliberately in the second session for the owner-requested restart.
  `rojo serve` now runs as a detached process (pid 30868, log `%USERPROFILE%\.rokit\rojo-serve.log`) and Studio
  is connected: repo edits reached Studio with matching hashes [Verified]. If it's gone, run `rojo serve` in the
  repo root and press Connect in the Studio plugin.

## 5. Architecture decisions (details in `docs/DESIGN.md`)

- The repo is the source of truth. Rojo syncs it; Studio is never edited directly.
- Pure rule modules (`Lib/CodeBook`, `Lib/MatchCore`, `Modules/PlateVisibility`) plus thin service adapters, so rules are unit-testable without players.
- The server is authoritative throughout. `SubmitCode` sends only the typed code, and identity comes from the invocation.
- Per-observer codes with a **server disclosure gate**, so clients only learn numbers they could actually see.
- Spawn protection and view-wipe-on-death are enforced in `MatchCore`, not on the client.
- Manual spawning (`CharacterAutoLoads = false`, `LoadCharacter` + `PivotTo`), spawn ForceFields removed, `BreakJointsOnDeath = false`.
- Maps are built at runtime from builder modules with persistent streaming. There is a map contract
  (PrimaryPart, SpawnArea, terrain hooks), and the arena origin is at `y = 2` for terrain alignment.
- UI is built in code. Tunables live in `Constants`. Remotes are declared in one module and live in the `NAURemotes` folder.
- Franchise names and portraits are the owner's decision; the risk and an original-name fallback are recorded in `DESIGN.md`.

## 6. Tests actually run and results

Unit tests (`TestRunner`: CodeBook.spec 11, MatchCore.spec 21, PlateVisibility.spec 9):

| When | Context | Result |
|---|---|---|
| Phase 2 build | Edit command bar | 26/26 passed |
| After spawn protection | Play, Server | 32/32 passed |
| Same code, Edit command bar | Edit | 28 passed / 4 failed. Cause confirmed: the cached `Constants` lacked the new field. Re-run in Play: 32/32 |
| After all 2.2 changes | Play, Server | 37/37 passed [Verified] |
| After the plate rework (second session) | Play, Server | 41/41 passed [Verified] |
| **After timed rounds + silhouettes (second session)** | Play, Server | **41/41 passed** [Verified] |

Live solo checks (Studio Play, one player, dev min-players = 1). All [Verified], with measured values:
- Lobby spawn: WalkSpeed 24, no spawn ForceField, leaderstats present.
- FIGHT → queued → intermission countdown → round start. Leave queue shows the toast and resets the button.
- Strike rule: 1st wrong code → server status `wrong` + warning shown; 2nd → `self_eliminated`, Elims 0, Yen 0.
  (Run before spawn protection existed.)
- Respawn delay measured 3.27 s. Void death → "fell" in feed. Under-population → `draw not_enough_players`
  → back to lobby, auto-queued, plates cleared (run before the latest RoundManager edits).
- Camera faces into the arena after a north-end spawn (camera/fighter heading dot = 1.00).
- Spawn protection lasted 3.01 s on the server. On the client: overlay → "SPAWN PROTECTION 2.7s" + code button hidden → button returns.
- Run FOV: 70 → 96 within ~0.5 s of moving; back to 70 within ~0.6 s of stopping (real key input).
- Spawn sampler: 200 samples, 0 blocked, radius 3.2–69.7 of 72, feet at floor/platform level. 12-player opening wave: closest pair 30.5 studs.
- Arena terrain surface 0.00 studs from the floor; sparring platform top at 1.20.
- Ninja-run pose while running: torso leans 12.9°, upper arm points behind the torso (+0.59; before the fix −0.51).
- Screenshots: lobby with portraits, FIGHT button final state, arena overview, speed lines while sprinting.
- Server log: no errors in the final sessions.

**Not tested:**
- Anything needing two players: live cross-player kill + ¥500, the 7-stud/facing plate rule and the disclosure
  gate, different codes per observer live (acceptance #1), mid-round join live (#6), large-accessory plate
  clearance (#10), spawn protection seen from another player.
- Touch/mobile UI, top-row number keys in real play, 12-player performance.
- Inspect card, QUEUED button state after the redesign, shrunken code-entry panel visuals.
- Visuals of the elimination FX, portal pulse, camera shake, trails and dust.
- Team mode, persistence, purchases and abilities (not built).

### Plate rework (2026-09-23, second session)

- Owner reported the plate only appeared from a specific angle. Probable cause [Assumption, by code reading,
  not reproduced]: the plate's `BillboardGui.MaxDistance` was 10 studs, and Roblox measures that from the
  **camera**, which sits ~12 studs behind you in third person, so plates were culled unless the camera swung close.
- Fix: no camera-based `MaxDistance`; the client measures distance from your fighter. New pure rule
  `PlateVisibility.plateMode` (hidden / masked / revealed) + 4 tests. `RoundState.scores[i].protected` added
  so clients hide protected fighters' plates. New constants: `PLATE_BLANK_DRAW_DISTANCE` (60, placeholder),
  `PLATE_HIDE_SLACK_DISTANCE` (0.5), `PLATE_HIDE_SLACK_DEGREES` (5). Server disclosure gate unchanged.
- Unit tests in Play/Server: **41/41 passed** [Verified]. Parity of the 5 changed files [Verified].
- Owner follow-up: plate 1.3 × 0.5 → 2 × 0.8 studs; reading distance 7 → 11 studs; speed lines cut from 36 to 8,
  thinner (1–2 px), shorter (50–130 px), fainter (≤35% opaque), redrawn every 0.09 s. Tests 41/41 again [Verified];
  sprint in Play measured 8 lines, max opacity 0.31, max length 128 px at 24 studs/s + screenshot [Verified].
  Plate size at 11 studs, seen by a real second player [Not tested].
- `rojo serve` restarted as a detached process (log: `%USERPROFILE%\.rokit\rojo-serve.log`) [Verified listening].

### Owner changes (2026-09-23, third batch)

- Plates approved by the owner after their own test.
- Code entry closes after every confirmed code; results moved to HUD toasts. Solo Play check [Verified] (see table).
- Portraits: new Goku reference (`art/reference/goku.png`, old kept as `goku-old.jpg`); generator gained a
  silhouette style (default) and `dropChair`/seed options (used to cut L out of his armchair); L's bubble is now light grey.
  Output in `art/portraits/silhouette/`. Uploaded 2026-09-23 with the owner's "Proceed" (served from a temporary
  localhost-only Python server, stopped right after). Lobby shows them [Verified screenshot].
  Old colour-portrait ids, for rollback: Goku 122903496846585, Luffy 79671763279611, Krillin 91771744627475,
  Vegeta 72069376256964, Zoro 70883204029177, L 102258380243632, Naruto 104230049635730, Ichigo 70771063323340,
  Sasuke 132657356363462, Gojo 117842427607485.
- Rounds are time-based with uncapped eliminations (owner, 2026-09-23). `TARGET_SCORE` removed; `MatchCore` only ends
  a round at the time cap (sole leader with ≥1 elim wins; tie → 60 s sudden death → draw) or on too few players.
  HUD: "FIGHT!  Most eliminations wins" and "You N · Best N · Most eliminations wins". The two old AT5 tests became
  "uncapped" tests (60 eliminations, no winner until the cap). Unit tests **41/41** [Verified]; solo round start
  shows the new text and the 8:00 timer [Verified screenshot]. A full 8-minute round end not re-run [Not tested].

### Owner changes (2026-09-23, fourth batch)

- Goku silhouette cleaned (his single hair strand made a stray white loop): generator gained a `cleanRadius`
  opening; re-uploaded with the owner's "Upload it" → `rbxassetid://83993265658252` (previous silhouette id
  78521110761755). Shows in the lobby [Verified screenshot].
- Lobby rebuilt (see table; owner chose "code rebuild + lighting", "stone colonnade walls", "keep current" lighting technology).
- In-match UI restyled; text overflow fixed (fixed-width labels replaced by self-sizing panels; the code panel's
  2-line strike warning no longer spills). Screenshots [Verified]: scoreboard, code panel, wrong-code toast, kill-feed
  row, MISFIRE screen, colour restored after respawn (saturation 0.00).
- Unit tests 41/41 [Verified]. Not tested: touch layout, the ELIMINATED screen from a real kill, the round-end
  banner, 12-player lobby performance (863 parts, ~60 point lights).

### Multi-client check + lobby flicker fix (2026-09-23)

- **3-player check (Test → Clients and Servers): passed, as reported by the owner.** Run by the owner, not
  observed by Claude; per-item results were not itemised. [Owner-reported]
- Owner reported the thin black edging under the colonnade columns flickering between marble and black:
  z-fighting. The walkway nosing's courtyard face was coplanar with the walkway step's face. Fixed by making the
  nosing stand 0.05 proud; the same fault was fixed on the portal step nosings, the portal lintel's brass band, the
  harbour door's iron bands and the banner trims. A scripted scan of every axis-aligned lobby part for
  same-direction coplanar faces now finds only faces that can't be seen (bottoms resting on the floor, backs buried
  in walls) [Verified]. Flicker itself can't be seen in still screenshots — confirm in Studio [Not tested visually].

## 7. Known issues and risks

- **No plate has ever been seen rendered in game.** The plate rule is only proven by unit tests.
- Git Bash fails to fork on this machine (`dofork ... Resource temporarily unavailable`); use PowerShell.
- Disclosure slack (2.5 studs, 15°) isn't tuned against real latency [Assumption: enough].
- Studio input automation can't press number-row keys (keypad keys were used). Real players' number keys are
  expected to work because the Backpack core GUI is disabled [Assumption].
- The Edit-mode command bar serves stale modules; always run tests in Play/Server.
- Speed lines, camera bob and the wide FOV may bother motion-sensitive players. There's no settings toggle yet.
- On R6 avatars the pose does nothing (trails/dust only) [Assumption: R6 untested].
- Cosmetic: the lobby top bar overlaps distant bubbles at the spawn view. L's silhouette keeps a small scrap of the chair frame at its left edge.
- IP: franchise names/art in game and planned Robux passes for Sasuke/Gojo carry takedown risk (owner's decision, recorded).
- Git: the whole slice is uncommitted. Git will convert LF→CRLF on four files the next time it touches them (warning only).
- `rojo serve` is a detached process on this machine; it won't survive a reboot.

## 8. Single next task

**Owner review of the ability sheet (`docs/ABILITIES.md`).** It is the last gate before Phase 3. Owner: the
owner (approve / change / reject per character). Claude then presents the Phase 3 plan (team mode, persistence,
entitlements, abilities) as an approve/deny list before building anything. No new features until then.
