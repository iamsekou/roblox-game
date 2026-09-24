# HANDOFF — Numbers Assassin Universe

Last updated: 2026-09-23, Phase 4 built (settings, phone pass, how to play, stress test, security review, sound).
Current state first; a condensed history is at the end.

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
| 4 Saved progress (yen, owned characters, equipped) | Done 2026-09-23 (section 2), committed |
| 5 Yen shop | Done (shop cottage in the lobby garden); purchases now saved |
| 6 Robux characters via Game Passes | Approved; waiting for the owner to create the two passes and send their ids (steps given 2026-09-23; never invent ids). To be built together with Robux yen bundles (Developer Products; bundle list approved 2026-09-23, see `docs/DESIGN.md`). Owner will supply both sets of ids later |
| 7 Team 6v6 mode alongside FFA | Built 2026-09-23, all 8 decisions approved (section 2); committed; needs a multi-player test |
| 8 Hand-keyframed animations | Playback + fluid placeholders done; clips pending from the owner (`docs/ANIMATING.md`) |

Extras added at the owner's request this session: swords and slash effects, clashes, kill leaderboards,
colosseum crowd, passive yen + friend booster, 30-second alert (the four open choices on these were approved as built).

**Phase 4** (approved 2026-09-23: all items; map 2 planning skipped for now). Built, uncommitted:

| Item | State |
|---|---|
| 1 Settings menu | Done (section 2) |
| 2 Phone / tablet pass | Done (section 2); measured on an emulated 844×390 phone, not on a real device |
| 3 How to play | Done (section 2) |
| 4 12-player stress test | Harness + first measurements done (section 2); a real 12-player test still needs real players |
| 5 Security review | Done: 2 fixes, 1 recommended follow-up (section 7) |
| 6 Map 2 plan | Skipped by the owner for now |
| 7 Sound | Done with Claude's picks from licensed libraries (section 2); owner to listen and swap any |

## 2. Implemented systems

| System | Where | Status |
|---|---|---|
| Round flow: queue → 15 s intermission → 8-min timed round, uncapped eliminations (tie → 60 s sudden death, starting instantly → draw) → 6 s results → lobby + auto-requeue; leave queue; mid-round join; 15 s under-population grace | `Systems/RoundManager`, `Lib/MatchCore` | Unit-tested [Verified]; solo round start [Verified]; with `NAU_DevRoundSeconds = 40`, solo: round end at 0 kills → sudden death at the same instant → draw 60 s later, twice in a row [Verified]; a full 8-min round end [Not tested] |
| **30-second alert** (owner, 2026-09-23): every fighter in the match gets a "30 SECONDS LEFT" banner (subtitle "MOST ELIMINATIONS WINS"), the clock pops; again 30 s before sudden death ends ("SOLE LEADER WINS · OTHERWISE A DRAW") | `Lib/RoundTimer`, `RoundManager` (alertTimeLeft), `RoundAlert` remote, `HUDController` | 1 unit test; solo shortened rounds: alert at 30 s left in regular time and in sudden death, banner on screen [Verified]. Several fighters [Not tested] |
| **Passive yen** (owner, 2026-09-23): ¥50 every 2 min to every player in the server; friend booster ¥100 per Roblox friend in the server every 5 min; clocks from join; "+¥50 PLAYTIME" / "+¥200 FRIEND BOOST · 2 FRIENDS HERE" popup beside the yen counter (queued when both land together) | `Lib/IncomeRules`, `Systems/IncomeService`, `IncomeNotice` remote, `HUDController` | 5 unit tests; solo Play: +¥50 at 2:00 and 4:00, +¥200 at 5:00 with `NAU_DevFriends = 2`, balance saved [Verified]. Real friendships (`IsFriendsWith`) [Not tested — needs two friend accounts on a live server] |
| Modes: FFA + **Team battle 6v6** (picked uniformly, team only with ≥4 queued; auto-balanced Crimson vs Azure; joiners to the smaller team; no friendly fire, teammates never clash; team-coloured plate borders, teammate name tags, YOUR TEAM · clock · enemy scoreboard, kill list/feed in team colours; team ties → sudden death) | `Lib/TeamRules`, `MatchCore`, `RoundManager`, `ClashRules`, `ClientState` (team helpers), `NumberPlateController`, `HUDController` | 6 team unit tests + 1 clash test [Verified]. Solo with `NAU_DevMode = "Team6v6"`: team round starts, I'm Crimson, scores {Crimson 0, Azure 0}, FIGHT banner "YOU'RE CRIMSON…", scoreboard YOUR TEAM/AZURE with team bars, 30 s alert, 0-0 → sudden death → draw [Verified]; 1 queued without the switch → FFA, HUD unchanged [Verified]. **Not tested (needs several players):** team split, joiners, teammate plates/tags, no friendly fire in play, team kill scoring live |
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
| **Kill leaderboards**: all-time + weekly (Monday 00:00 UTC), global via OrderedDataStores; only code eliminations count; kills show live at once, saved every 30 s + on shutdown, top 100 re-read every 60 s. Two floating holo boards by the arrival plaza: top 10 with headshots, podium colours, ▲▼/NEW, "+N LIVE", your line, reset countdown, "SYNCED Xs AGO"; #1's avatar spins above as a hologram | `Lib/WeekClock`, `Lib/LeaderboardRules`, `Systems/SafeStore`, `Systems/LeaderboardService`, `Controllers/LeaderboardController`, `Lobby/Leaderboards` | 5 unit tests; offline mode + injected kills rendering, names, headshots, champion [Verified]. Real DataStores: 3 injected kills written to both stores and read back as the global top list (`offline=false`) [Verified, Studio stores] |
| **Colosseum crowd**: the arena's stands are a 6-row bowl; each client builds ~1,060 stylised spectators (fans with varied builds, outfits, headwear, flags, signs, foam fingers, glow sticks, drums; plus monks, ninjas, guards, robots, mascots, oni, samurai). Heads track the nearest fighter, a wave every 28 s, the bowl erupts on each elimination. Density follows graphics quality | `assets/Builders/ProvingGrounds` (`Crowd/Row*`), `animations/Controllers/Crowd`, `Controllers/FXController` | Screenshots; 60 fps on this PC (16.7 ms avg); cheer lift +0.49 and settles [Verified]. Phones / low settings / 12 players [Not tested] |
| Ownership: free starters + bought; **every character unlocked in Studio** unless `NAU_DevUnlockAll = false` | `AbilityService.owns` | [Verified] |
| Roster (shown names): Gokai, Luffo, Krillo, Vejaro, Zorin, Eli, Nariko, Ichiro, Sazuki (Robux), Gozen (Robux); internal ids keep the old keys | `Modules/CharacterDefs` | [Verified] |
| HUD (battle style): YOU · clock · LEAD at the top; in-round eliminations list; yen + kill feed; [Q][E] beside [F] CODE; toasts; banners | `Controllers/HUDController`, `UI` | [Verified]; several scorers [Not tested] |
| Lobby "The Still Harbor": walled courtyard (colonnades, FIGHT gate, arches, cypresses, lamps), 10 portrait bubbles, the leaderboards, and the shop garden at the south end (south wall moved 114 → 146) | `assets/Builders/Lobby`, `ShopHouse`, `animations/Controllers/LightingFX` | Screenshots [Verified] |
| Arena "The Proving Grounds": circular stadium, terrain, dense cover, random unmarked spawns, crowd bowl | `assets/Builders/ProvingGrounds`, `Systems/MapService` | [Verified] |
| Run feel: FOV 70°→96°, speed lines, camera lean/bob, ninja-run pose, trails, dust | `animations/Controllers/RunFOV`, `SprintFX` | [Verified] |
| **Saved progress**: yen, yen purchases and equipped character in one DataStore record per player; session lock (wait 4 s × 8 for another server's fresh lock, then take over; stale after 180 s); a save only writes while holding the lock; autosave 60 s, save + release on leave and shutdown; loads sanitised; unsaved-session toast. Studio stores are separate (`_Studio` suffix, leaderboards too) | `Lib/ProfileData`, `Systems/ProfileService`, `Systems/SafeStore`, `EconomyService` (applySaved, listeners), `AbilityService` (applySavedEquip, onEquipped) | 5 unit tests. In Studio with real DataStores [Verified]: new profile; bought Vejaro (+Krillo) and equipped → stop → restart restored ¥10,000, 2 bought, Vejaro, `Zorin` still `not_owned`; a planted foreign lock made autosave refuse to overwrite; the next join waited ~26 s then took over and loaded the other server's data. Live servers, real server hops, the offline toast [Not tested] |
| **Settings menu** (Phase 4): gear top-right; speed lines, camera sway, wide running view, screen shake (off → red edge flash), crowd Auto/Off/Low/Medium/High, music + effects volume; HOW TO PLAY button. Saved in the profile, validated by the server | `Modules/Settings`, `Controllers/SettingsController`, `ProfileService` (SetSettings), `SprintFX`/`RunFOV`/`CameraShake`/`Crowd` switches, `src/client/Audio` | 4 unit tests. Real clicks [Verified]: speed lines off → no streaks while running, on → streaks; wide view on → 96°, off → stays 70°; screen shake off → edge flash (35% opaque) and no camera offset; crowd Low 3,336 parts → High 7,498 rebuilt live; bad request refused whole; rate limit; settings restored after stop → start. Camera sway not measured separately [Not tested] |
| **Phone / tablet layouts** (Phase 4): touch cluster round Roblox's jump button; two-column touch keypad; kill list 6 rows on phones and hidden while the keypad is open; 44 pt touch targets on the card, settings, keypad, leave-queue; compact phone shop | `UI` (isTouch, isPhone, viewport, touchCluster, gearSize), `AbilityController`, `SubmissionController`, `HUDController`, `LobbyController`, `SettingsController`, `ShopController` (buildPhonePanels) | Emulated 844×390 phone with a measuring script [Verified]: arena HUD, keypad open, lobby, character card, settings and shop all 0 issues (text ≥ 11 pt, targets ≥ 44 pt, nothing off-screen or under the jump button, no overlaps); desktop shop geometry unchanged. Real phones and tablets [Not tested] |
| **How to play** (Phase 4): five cards on a first visit, reopenable from settings; "seen" saved | `Controllers/TutorialController`, `Settings.tutorialDone` | Opened by itself on first Play, clicked through all five, saved `tutorialDone = true`, didn't reopen after stop → start, HOW TO PLAY reopened it [Verified]. The card-4 mark was changed from ✕ (missing in the font) to X after the last screenshot [Not re-checked visually] |
| **12-player stress test** (Phase 4): Studio-only bots | `Systems/StressTestService`, `SprintFX` (dresses bots) | Owner's PC, Studio Play (client and server in one process), arena + High crowd [Verified]: 1 fighter 16.7 ms avg (60 fps), 99th pct 21.1 ms; 12 fighters 16.8 ms avg (60 fps), 99th pct 20.1 ms, one 91 ms hitch (bots spawning), memory 2,290 → 2,305 MB, server physics 0.00 → 0.94 ms. Studio's network counters are meaningless here (one process). Phones, real network [Not tested] |
| **Sound** (Phase 4): lobby/arena music, effects for round start, elimination (you / of you), wrong code, 30 s alert, sudden death, win, ability casts (3D), income, shop slots | `src/client/Audio`, hooks in `HUDController`, `SubmissionController`, `FXController`, `ShopController` | All 18 candidate ids load here [Verified]. In Play [Verified]: lobby music in the Music group, arena music + round-start gong on entering, ability cast at the caster, wrong code, eliminated, 30 s alert, income. Sudden death, the kill sound, win [Not tested]. How it all sounds: owner to judge (Claude can't listen) |

## 3. Repository state

- Branch `main` on `origin` (github.com/iamsekou/roblox-game). History: `7719c2f` Rojo setup → `a76340c` Phase 2
  slice → `268d746` Phase 3 abilities → `295b311` handoff rewrite → `621b746` animations, swords, clashes →
  `b0ac9f6` fluid motion, ability audit fixes, yen shop, leaderboards, crowd → the saved progress + passive yen +
  30-second alert commit (see `git log`). Not pushed.
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
  (server sets false at runtime), HttpService off. **Studio API access on** (owner, 2026-09-23): Studio uses the
  `_Studio` stores. The owner's Studio test profile was reset to a fresh start at the owner's request: ¥133,500
  (enough to buy all six yen characters one by one), nothing bought, Gokai equipped, default settings, walkthrough
  not yet seen (reset again after the Phase 4 tests). `NAU_DevUnlockAll = false` is
  saved on ServerScriptService in the place (so Studio shows real ownership; delete the attribute to unlock all again).
  The Studio leaderboards show 3 injected kills.
- Rojo 7.4.4 via Rokit. `rojo serve` restarted after the owner's PC crash (2026-09-23 19:05, pids 3068 / 10220);
  the plugin reconnected [Verified]. After a reboot: run `rojo serve` in the repo root, then Connect. If new files
  don't appear in Studio, check `/api/read` and restart serve.

## 5. Architecture decisions (details in `docs/DESIGN.md`)

- Repo is the source of truth; Rojo syncs it; Studio is never edited directly.
- Rules live in pure, unit-tested modules (`Lib/*`, `Modules/PlateVisibility`, `AnimTimeline`, `Spring`); systems
  are thin adapters.
- Server-authoritative: identity from the invocation; `SubmitCode` carries only the typed code; codes reach a
  client only through the disclosure gate; abilities, purchases and equips are requested and decided server-side.
- DataStores go through `Systems/SafeStore` (budget waits, retries, offline detection, `_Studio` names in Studio).
- Heavy visuals are client-built (crowd, sword models, poses, board screens); the server sends events, not parts.
- Every tunable in `Constants`; every remote in `Remotes`; UI and maps built in code; maps follow the map contract.
- Studio-only test switches (ignored live): `NAU_DevMinPlayers`, `NAU_DevSelfTarget`, `NAU_DevUnlockAll`,
  `NAU_DevGrantYen`, `NAU_DevFakeKills`, `NAU_DevRoundSeconds`, `NAU_DevFriends`, `NAU_DevMode` (see CLAUDE.md).

## 6. Tests

- Unit tests (`TestRunner`, in Play on the Server): **118/118** [Verified, 2026-09-23; Settings 4 added, 2 aim checks added to
  AbilityRules]. Specs: CodeBook 11, MatchCore 28,
  PlateVisibility 10, AbilityRules 13, AnimTimeline 8, ClashRules 10, Spring 6, ShopRules 6, Leaderboard 5, ProfileData 5,
  Income 6, TeamRules 6.
- Owner-reported: 3-player check, multi-client ability test and 2-player clash test passed.
- **Not tested**: saves on live servers and real server hops; phones/touch layouts (shop, crowd density);
  12-player performance; the 2-player ability cases listed in section 2; authored animation clips.

## 7. Known issues and risks

- Multi-client behaviour can only be checked by the owner. Solo Play uses the real positive user id.
- After a crash or a very fast server hop, a joining player waits up to ~35 s (shown ¥0) before their save loads.
- The game isn't published with these changes; live saves start only once it is (publishing is the owner's call).
- Placeholder numbers: shop prices, balance values, crowd density; all in `Constants` / `CharacterDefs`.
- Passive yen pays players idling in the lobby too (as asked: "in server"). Roblox disconnects idle players after
  20 min, which should cap plain AFK farming at about ¥500 + friend boosts per session [Assumption]; an auto-clicker
  defeats that.
- Crowd is ~7,500 parts: fine on this PC; low-end devices rely on the quality-based density [Assumption].
- Studio input automation can't press number-row keys (keypad used in tests).
- Security (Phase 4 review): characters are simulated by their own clients (Roblox), so speed hacks/teleports aren't
  caught and a cheater could teleport in front of opponents to read their plates; knockbacks are applied by the
  victim's client and can be ignored. Recommended follow-up (needs approval): a server-side movement sanity check that
  allows the game's own dashes, grapples and knockbacks.
- Sound picks are Claude's (it can't listen). Alternatives that load: arena "Storm of the Shogun" 81644581161031,
  "Blades in Motion" 90151190692214; lobby "Bells and Harp (edit)" 1840049555, "A Delicate Art" 1840471940. Swap in
  `src/client/Audio.luau`.
- Studio's tooling resets the camera after each scripted command, which made the shop camera look wrong in automated
  tests only.
- IP: names are original, but silhouettes come from franchise art, abilities/poses follow the shows, and the shop
  cottage is inspired by a Dragon Ball frame; the Robux passes for Sazuki/Gozen remain the highest-risk part.
- Animation placeholders were tuned on one avatar's proportions; very different avatars may land hands off target.
- `DEV_UNLOCK_ALL_IN_STUDIO` must stay Studio-only (it is).

## 8. Single next task

**Owner: play Phase 4 and approve a commit** (it's uncommitted): listen to the music and effects, try the settings,
the first-visit walkthrough (the Studio profile is reset so it shows), and ideally a phone (Roblox app, or Studio's
device emulator). In parallel the multi-player test of team battle in Test → Clients and Servers (4+ clients): team
split, teammate plates/tags, "That's a teammate", no friendly fire, team scoring; plus saved progress (leave, rejoin).
**Next build:** item 6 + Robux yen bundles (approved) as soon as the owner sends the pass and product ids; or the
movement sanity check (section 7) if approved.

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
  - Committed `b0ac9f6`. API access switched on → leaderboards verified on real DataStores; saved progress (item 4)
    built and tested in Studio (uncommitted).
