# CLAUDE.md — Numbers Assassin Universe (NAU)

Durable rules for working in this repo. Current state and the next task live in `HANDOFF.md`;
approved design decisions and contracts live in `docs/DESIGN.md` (read it before changing any rule).

## What this is

A 12-player Roblox PvP arena game. Every player sees a *different* 4-digit number above each opponent;
you eliminate someone by typing the number *you* see on them. Studio place: "InDeveopmentPart2"
(placeId 125676427996909, Team Create).

## How to work with the owner

- Work in phases with approval gates. Do not start a large or hard-to-reverse feature without explicit
  approval. The ability sheet (`docs/ABILITIES.md`) is a proposal and is **not approved**; don't implement abilities.
- Present decisions as short approve/deny lists with a recommended default.
- After each milestone, report what changed, what was actually tested (with results), what is untested,
  and the single next task. Never describe something as tested if it wasn't run.
- Use the `roblox-scripter`, `roblox-modeler` and `roblox-animator` skills for their domains. A skill
  loads instructions that you then carry out; never claim a skill "did" work on its own.
- Ask before any outward or hard-to-reverse action: uploading assets to Roblox, publishing, git
  commit/push, installing tools, changing Studio/experience settings (e.g. HttpEnabled, streaming).
- Don't commit or push unless asked.

## Workflow and tooling

- **The repo is the source of truth.** Rojo 7.4.4 (pinned in `aftman.toml`, installed via Rokit at
  `%USERPROFILE%\.rokit\bin\rojo.exe`) syncs it into Studio: run `rojo serve` in the repo root, then press
  Connect in Studio's Rojo plugin. The plugin needs **Script Injection** permission (Plugins → Manage Plugins).
- Rojo writes to the Edit datamodel only. A running Play session must be stopped and restarted to pick up changes.
- If Rojo isn't connected, mirror files into Studio through the Studio tools and **prove parity** with the
  length + rolling-hash comparison (repo files hashed with CR stripped vs Studio `Source`). Never leave Studio
  and the repo out of sync.
- Don't edit scripts in Studio directly. Change the repo file and let Rojo sync it.
- **Run unit tests during Play on the Server:**
  `print(require(game.ServerScriptService.Server.Tests.TestRunner).run())`. The Edit-mode command bar
  caches modules and returns stale results.
- Solo testing: set attribute `NAU_DevMinPlayers = 1` on ServerScriptService *inside a Play session*
  (Studio-only, ignored live). Anything involving two players needs **Test → Clients and Servers**, which
  only the owner can launch.

## Project layout (Rojo)

| Repo path | Studio | Owner skill |
|---|---|---|
| `src/server` | ServerScriptService.Server (Script) — `Systems/`, `Lib/` (pure rules), `Tests/` | scripter |
| `src/shared` | ReplicatedStorage.Shared — `Remotes`, `Modules/` | scripter |
| `src/client` | StarterPlayerScripts.Client (LocalScript) — `Controllers/`, `ClientState`, `UI` | scripter |
| `animations` | ReplicatedStorage.Animations — motion/FX modules | animator |
| `assets` | ServerStorage.Assets — `Builders/` (maps), `Init/` (edit preview) | modeler |
| `tools/portraits` | not synced — portrait generator | — |
| `art/` | not synced, **git-ignored** (third-party reference art + derived portraits) | — |

## Invariants — never break these

- The server is the only authority. Clients only *request*; the server validates type, range, identity,
  cooldown and state before acting. Identity always comes from the remote invocation, never the payload.
- Codes are per-observer. There is no global code table a client can read. A code reaches a client only
  through `NumberAssignmentService`'s disclosure gate (within `PLATE_VIEW_DISTANCE`, the target facing the
  observer, clear line of sight), and only to that one observer via `FireClient`.
- `SubmitCode` carries only the typed string. `MatchCore` resolves it against that observer's own table.
  Eliminations are check-and-set with no yield in between.
- Rules live in pure modules (`src/server/Lib`) with unit tests. Systems are thin adapters. Add or adjust tests
  in `src/server/Tests` whenever a rule changes.
- Every tunable number goes in `src/shared/Modules/Constants.luau`. No magic numbers in systems.
- Every remote is declared in `src/shared/Remotes.luau` (folder `ReplicatedStorage.NAURemotes`).
- Never invent Roblox asset, Game Pass or Developer Product IDs.
- No line-of-sight check on *submit* (approved). Cover hides numbers; it doesn't block a remembered one.
- UI is built in code by client controllers, not authored in StarterGui.
- Maps follow the map contract in `docs/DESIGN.md`: an unrotated PrimaryPart and a `SpawnArea` folder, with optional
  `buildTerrain`/`clearTerrain`. No visible spawn markers. Everything is anchored, exterior-only cover.

## Roblox quirks learned here (verified in this place)

- Avatar joints are **AnimationConstraint**, not Motor6D. Procedural poses must layer onto `.Transform` in
  `RunService.Stepped` and reset in `PreAnimation`. Rotating joint attachments moved the waist but **not** the arms.
- `UIGradient` tints a button's text too, so put gradients on a plate behind the text.
- Children of a **rotated** frame are not clipped. Keep clipping frames unrotated.
- Terrain voxels are 4-stud cells centred on multiples of 4. The arena origin is at `y = 2` so its terrain
  surface lands exactly on the floor.
- Studio's input automation refuses the number-row keys (reserved for the default hotbar). Use keypad keys
  when automating tests. This says nothing about real players.
- `HttpService` is disabled in this experience, so the Studio tools can't fetch local files.
- **Test → Clients and Servers gives players negative UserIds (-1, -2, ...).** Never treat an id's sign as meaning
  anything (a plate bug from exactly this hid every plate in multi-client tests, 2026-09-23). Solo Play uses the real,
  positive id, so solo tests can't catch it.

## IP

Players see the owner's renamed roster (Gokai, Luffo, Krillo, Vejaro, Zorin, Eli, Nariko, Ichiro, Sazuki, Gozen);
internal ids keep the old keys and must never be shown. Portraits are silhouettes from supplied reference art; the risk
is recorded in `docs/DESIGN.md` ("IP decision"). Don't add franchise names, art or named attacks without the owner's
direction. Keep `art/` out of git.
