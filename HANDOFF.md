# HANDOFF — Numbers Assassin Universe

Last updated: 2026-09-23, end of the third working session (animations, swords, clashes, ability audit, yen shop,
kill leaderboards, colosseum crowd). Current state first; a condensed history is at the end.

Labels: **[Verified]** = checked directly (test output, measurement, screenshot, or file/Studio inspection).
**[Owner-reported]** = the owner tested it; Claude didn't observe it. **[Assumption]** = believed true, not checked.
**[Not tested]** = not exercised.

## 1. Current goal

Phase 3 (plan approved 2026-09-23, 8 items), worked in the owner's order:

| Item | State |
|---|---|
| 1 Ability system, all 10 characters | Done; audited 2026-09-23 (section 2) |
| 2 Q/E keys + touch buttons | Done |
| 3 Choose character at the pedestal / respawn screen | Done |
| 4 **Saved progress** (yen, owned characters, equipped) | **Next.** Needs the owner to switch on *Game Settings → Security → Enable Studio Access to API Services*. Reuses `Systems/SafeStore` |
| 5 Yen shop | Done (shop cottage in the lobby garden). Purchases last only for the session until item 4 |
| 6 Robux characters via Game Passes | Waiting: the owner must create the passes and supply their ids (never invent ids) |
| 7 Team 6v6 mode alongside FFA | Not started (rules exist in `MatchCore`, disabled) |
| 8 Hand-keyframed animations | Playback + fluid placeholders done; clips pending from the owner (`docs/ANIMATING.md`) |

Extras added at the owner's request this session: swords and slash effects, clashes, kill leaderboards,
colosseum crowd.

## 2. Implemented systems

| System | Where | Status |
|---|---|---|
| Round flow: queue → 15 s intermission → 8-min timed round, uncapped eliminations (tie → 60 s sudden death → draw) → 6 s results → lobby + auto-requeue; leave queue; mid-round join; 15 s under-population grace | `Systems/RoundManager`, `Lib/MatchCore` | Unit-tested [Verified]; solo round start [Verified]; a full 8-min round end [Not tested] |
| FFA only (Team6v6 rules exist, disabled) | `Constants.ENABLED_MODES` | FFA [Verified]; team rules unit-tested only |
| Per-observer 4-digit codes; server disclosure gate (11 studs + facing ±60° + line of sight, small slack) | `Lib/CodeBook`, `Systems/NumberAssignmentService`, `Modules/PlateVisibility` | Unit-tested [Verified]; multi-client [Owner-reported] |
| Number plates: blank "••••" within 60 studs, digits within 11 studs when faced; 2 × 0.8; depth-tested | `Controllers/NumberPlateController` | [Owner-reported] |
| Code entry: F / CODE button; confirming closes the box; HUD toasts | `Controllers/SubmissionController` | [Verified] solo; touch keypad [Not tested] |
| Eliminations: 1 elim + ¥500; 2nd wrong code in a life = self-elimination; 5 s stale window; 0.3 s debounce; jams answer `locked` | `Lib/MatchCore`, `Systems/EliminationService` | Unit-tested [Verified]; live kills [Owner-reported] |
| Respawn 3 s; spawn protection 3 s (hidden, blind, no submitting/abilities, immune) | `RoundManager`, `MatchCore`, `AbilityService` | [Verified] |
| **Abilities, all 10 characters** (`docs/ABILITIES.md`): Q mild 8 s, E ultimate 20 s (−10 s per respawn); effects ×1.75 | `Lib/AbilityRules`, `Systems/AbilityService`, `Systems/Abilities/*`, `Controllers/AbilityController`, `animations/Controllers/AbilityFX` | **Audited 2026-09-23** through the real path with `NAU_DevSelfTarget` [Verified]: every jam shows the toast, the server rejects codes, an open box closes; blind whites out; knockbacks, dashes, teleports, speed changes, radar, outlines, clone, grants all behave as documented. Fixed in the audit: Moon Fang trail slowed to 36 % (now 60 %), Eli's camera outlived Eli, Gatling code wipe had no toast. Needs 2 players: Hunter's Eye, clone popping, reading at range, Infinity's 3-kill end, Tornado carry |
| **Cast animations**: server `cast` event → each client animates the caster (wind-up for the cast time → strike → hold → fade). Placeholders: 20 show-inspired poses as spring *targets* (damped springs per joint, strike boost, wrist drag, breathing sway); authored clip ids in `AnimationIds` replace them per clip | `Modules/AnimTimeline`, `Modules/Spring`, `Modules/AnimationIds`, `animations/Controllers/AbilityAnim` + `AbilityPoses`, `docs/ANIMATING.md` | Unit-tested [Verified]; motion measured (largest one-frame hand move 0.19 / 0.38 strike / 0.18 fade studs) [Verified]; feel [Owner to judge]; authored clips [Not tested — no ids yet] |
| **Swords + slash effects**: swords appear for sword moves. Zorin: red + dark katanas in hand + one in the mouth. Ichiro: black cleaver. Sazuki: straight blade. Trails, guard glint, block sparks (`guard_block`), tornado slash arcs, Flash Step arc, Moon Fang glow + crescent wave, blade lightning. Authoring copies in `ServerStorage.AnimationWork.Swords` (not synced) | `animations/Controllers/Swords`, `AbilityFX`, `AbilityAnim` | Screenshots [Verified]; sparks from a real hit [Not tested] |
| **Clashes**: the same attack started at each other (≤0.6 s apart, first still winding up, ≤30 studs, aimed within 35°, line of sight) cancels both and locks the pair face to face 7 studs apart for 2.5 s; first correct code wins; both thrown apart. Exchange visuals: parries, beam struggle, grinding spheres, fists; second fighter half a beat off | `Lib/ClashRules`, `AbilityService` (startClash), `AbilityPoses.clashMove` | 9 unit tests [Verified]; real 2-player clash [Owner-reported] |
| **Yen shop**: cottage on stilts in the lobby's south garden (inspired by the owner's reference); door prompt → camera glides in → hologram of your avatar plays the selected character's abilities → holo menu (roster, fighter file, animated balance, hold-to-buy 1 s, UNLOCKED burst, EQUIP, EXIT/[X]). Prices ¥5,000 / 10,000 / 16,500 / 25,000 / 33,500 / 43,500 (placeholders); tier N also grants lower tiers. Sound slots wired, empty | `Lib/ShopRules`, `Systems/ShopService`, `Systems/EconomyService` (inventory, spend), `assets/Builders/ShopHouse`, `Controllers/ShopController` | 6 unit tests; every purchase status through the remote; menu flow with real clicks [Verified]. Phones, several shoppers, persistence [Not tested] |
| **Kill leaderboards**: all-time + weekly (Monday 00:00 UTC), global via OrderedDataStores; only code eliminations count; kills show live at once, saved every 30 s + on shutdown, top 100 re-read every 60 s. Two floating holo boards by the arrival plaza: top 10 with headshots, podium colours, ▲▼/NEW, "+N LIVE", your line, reset countdown, "SYNCED Xs AGO"; #1's avatar spins above as a hologram | `Lib/WeekClock`, `Lib/LeaderboardRules`, `Systems/SafeStore`, `Systems/LeaderboardService`, `Controllers/LeaderboardController`, `Lobby/Leaderboards` | 5 unit tests; offline mode + injected kills rendering, names, headshots, champion [Verified]. **Real DataStore saving/reading [Not tested]** (Studio API access is off) |
| **Colosseum crowd**: the arena's stands are a 6-row bowl; each client builds ~1,060 stylised spectators (fans with varied builds, outfits, headwear, flags, signs, foam fingers, glow sticks, drums; plus monks, ninjas, guards, robots, mascots, oni, samurai). Heads track the nearest fighter, a wave every 28 s, the bowl erupts on each elimination. Density follows graphics quality | `assets/Builders/ProvingGrounds` (`Crowd/Row*`), `animations/Controllers/Crowd`, `Controllers/FXController` | Screenshots; 60 fps on this PC (16.7 ms avg); cheer lift +0.49 and settles [Verified]. Phones / low settings / 12 players [Not tested] |
| Ownership: free starters + bought; **every character unlocked in Studio** unless `NAU_DevUnlockAll = false` | `AbilityService.owns` | [Verified] |
| Roster (shown names): Gokai, Luffo, Krillo, Vejaro, Zorin, Eli, Nariko, Ichiro, Sazuki (Robux), Gozen (Robux); internal ids keep the old keys | `Modules/CharacterDefs` | [Verified] |
| HUD (battle style): YOU · clock · LEAD at the top; in-round eliminations list; yen + kill feed; [Q][E] beside [F] CODE; toasts; banners | `Controllers/HUDController`, `UI` | [Verified]; several scorers [Not tested] |
| Lobby "The Still Harbor": walled courtyard (colonnades, FIGHT gate, arches, cypresses, lamps), 10 portrait bubbles, the leaderboards, and the shop garden at the south end (south wall moved 114 → 146) | `assets/Builders/Lobby`, `ShopHouse`, `animations/Controllers/LightingFX` | Screenshots [Verified] |
| Arena "The Proving Grounds": circular stadium, terrain, dense cover, random unmarked spawns, crowd bowl | `assets/Builders/ProvingGrounds`, `Systems/MapService` | [Verified] |
| Run feel: FOV 70°→96°, speed lines, camera lean/bob, ninja-run pose, trails, dust | `animations/Controllers/RunFOV`, `SprintFX` | [Verified] |
| Yen: in memory only (resets on rejoin) | `Systems/EconomyService` | Persistence = item 4 |

## 3. Repository state

- Branch `main` on `origin` (github.com/iamsekou/roblox-game). History: `7719c2f` Rojo setup → `a76340c` Phase 2
  slice → `268d746` Phase 3 abilities → `295b311` handoff rewrite → `621b746` animations, swords, clashes →
  this session's commit (fluid motion, ability audit fixes, yen shop, leaderboards, crowd; see `git log`).
- All 75+ synced scripts match Studio by length + rolling hash (h = h·31 + byte mod 2³¹−1, CR stripped) [Verified
  after the crash recovery, and per file after every later change].
- Git-ignored, on disk only: `art/reference/*` and `art/portraits/*` (third-party reference art + derived portraits).
- Git warns LF → CRLF on many files (warning only). Git Bash can't fork on this machine; use PowerShell.

## 4. Outside the repo (Studio, Roblox, machine)

- Uploaded to Roblox under the owner's account (each approved): portraits (ids in `CharacterDefs.luau`; colour-set
  rollback ids: Goku 122903496846585, Luffy 79671763279611, Krillin 91771744627475, Vegeta 72069376256964,
  Zoro 70883204029177, L 102258380243632, Naruto 104230049635730, Ichigo 70771063323340, Sasuke 132657356363462,
  Gojo 117842427607485; previous Gokai silhouette 78521110761755). Nothing else uploaded; nothing published.
- Studio-only additions not in the repo: `ServerStorage.AnimationWork.Swords` (sword copies for animating).
- Place settings untouched by Claude: `Lighting.Technology`, `StreamingEnabled = true`, `CharacterAutoLoads = true`
  (server sets false at runtime), HttpService off, **Studio API access off** (DataStores run offline in Studio).
- Rojo 7.4.4 via Rokit. `rojo serve` restarted after the owner's PC crash (2026-09-23 19:05, pids 3068 / 10220);
  the plugin reconnected [Verified]. After a reboot: run `rojo serve` in the repo root, then Connect. If new files
  don't appear in Studio, check `/api/read` and restart serve.

## 5. Architecture decisions (details in `docs/DESIGN.md`)

- Repo is the source of truth; Rojo syncs it; Studio is never edited directly.
- Rules live in pure, unit-tested modules (`Lib/*`, `Modules/PlateVisibility`, `AnimTimeline`, `Spring`); systems
  are thin adapters.
- Server-authoritative: identity from the invocation; `SubmitCode` carries only the typed code; codes reach a
  client only through the disclosure gate; abilities, purchases and equips are requested and decided server-side.
- DataStores go through `Systems/SafeStore` (budget waits, retries, offline detection).
- Heavy visuals are client-built (crowd, sword models, poses, board screens); the server sends events, not parts.
- Every tunable in `Constants`; every remote in `Remotes`; UI and maps built in code; maps follow the map contract.
- Studio-only test switches (ignored live): `NAU_DevMinPlayers`, `NAU_DevSelfTarget`, `NAU_DevUnlockAll`,
  `NAU_DevGrantYen`, `NAU_DevFakeKills` (see CLAUDE.md).

## 6. Tests

- Unit tests (`TestRunner`, in Play on the Server): **96/96** [Verified, 2026-09-23]. Specs: CodeBook 11, MatchCore 28,
  PlateVisibility 10, AbilityRules 13, AnimTimeline 8, ClashRules 9, Spring 6, ShopRules 6, Leaderboard 5.
- Owner-reported: 3-player check, multi-client ability test and 2-player clash test passed.
- **Not tested**: real DataStore round-trips; phones/touch layouts (shop, crowd density); 12-player performance;
  the 2-player ability cases listed in section 2; authored animation clips.

## 7. Known issues and risks

- Multi-client behaviour can only be checked by the owner. Solo Play uses the real positive user id.
- Leaderboards and (soon) saved progress can't be verified in Studio until API access is switched on.
- Placeholder numbers: shop prices, balance values, crowd density; all in `Constants` / `CharacterDefs`.
- Crowd is ~7,500 parts: fine on this PC; low-end devices rely on the quality-based density [Assumption].
- Studio input automation can't press number-row keys (keypad used in tests).
- Motion-sensitive players: speed lines, camera bob and wide FOV have no settings toggle yet.
- IP: names are original, but silhouettes come from franchise art, abilities/poses follow the shows, and the shop
  cottage is inspired by a Dragon Ball frame; the Robux passes for Sazuki/Gozen remain the highest-risk part.
- Animation placeholders were tuned on one avatar's proportions; very different avatars may land hands off target.
- `DEV_UNLOCK_ALL_IN_STUDIO` must stay Studio-only (it is).

## 8. Single next task

**Saved progress (Phase 3 item 4).** Owner first: switch on *Game Settings → Security → Enable Studio Access to API
Services*. Then Claude (1) verifies the global leaderboards with real DataStores and (2) builds saved progress on
`SafeStore`: yen, owned characters and the equipped character, with session locking, autosave, save-on-leave and
save-on-shutdown.

Owner items in parallel: review the placeholder animations and shop/leaderboard/crowd look; author the first
animation clips (Gokai + Luffo); create the two Game Passes when ready (item 6).

---

## Session history (2026-09-23, condensed)

- **Session 1:** Phase 2 vertical slice (round flow, codes, plates, code entry, eliminations, respawn, lobby, arena,
  HUD, run feel, portraits). Plates fixed and approved; lobby rebuilt as a courtyard; battle-style UI.
- **Session 2:** Phase 3 plan approved; all 10 characters' abilities built; multi-client bugs fixed (negative user
  ids, Hunter's Eye pitch, Shadow Clone physics, dash overshoot); roster renamed; committed `268d746`.
- **Session 3:**
  - Owner's ability test passed → item 8: cast animations for all 20 abilities (poses solved against the rig).
    Swords, then Zorin's mouth sword. Clashes, plus the second-fighter animation fix. Committed `621b746`.
  - Fluid motion: poses became spring targets (the first spring pass had a 0.95-stud jerk at the fade, which was
    fixed).
  - Ability audit with `NAU_DevSelfTarget`: 3 issues fixed (Moon Fang slow stacking, Eli camera lifetime, Gatling
    toast).
  - Yen shop (item 5): shop cottage and garden, purchase rules, holo menu. Fixed: a missing PlayerModule hung the
    menu, and the wall screens showed through the menu.
  - Kill leaderboards on the new SafeStore (offline in Studio). Names now resolve for live updates.
  - Colosseum crowd: 6-row bowl, client-built crowd; spacing and cheer strength tuned.
  - The owner's PC crashed mid-session. Rojo was restarted, and all files were confirmed in sync before continuing.
