# Ability sheet — APPROVED by the owner 2026-09-23 · all 10 characters implemented 2026-09-23 (placeholder VFX)

Every character has a **mild** ability (8 s cooldown) and an **ultimate** (20 s cooldown). After a
respawn the mild is ready and the ultimate loses 10 s of remaining cooldown (minimum 0).

## Ground rules every ability follows

1. **No ability eliminates anyone.** Eliminations only come from typing a correct number.
2. **No ability shows numbers through walls.** Plates stay depth-tested. Information abilities reveal
   *positions* or make plates *readable in line of sight*, never hidden numbers.
3. **Disruption is short.** The longest "can't submit" lock is 2 s; knockbacks never push anyone out of the arena
   (the invisible barriers already stop that).
4. **Everything has a tell.** Mild: 0.3–0.6 s wind-up. Ultimate: 0.8–1.5 s wind-up with sound and a VFX
   cue visible from range.
5. **Spawn protection:** abilities are disabled while protected (same as submitting), and protected
   fighters are immune to ability effects.
6. **Robux characters are not stronger**, just different. Balance numbers live in Constants.

"Input lock" = the target can't submit codes (their entry box greys out) — it never touches movement.

**Approved exceptions to the 11-stud / facing reading rule** (owner, 2026-09-23): Krillin's Tracking Disc,
Sasuke's Hunter's Eye and Gojo's Infinity let the caster read plates beyond it, **in line of sight only**
(rule 2 still holds). The server extends its disclosure gate for the caster while the effect lasts; nothing
changes for anyone else.

## The sheet

| # | Character | Mild (8 s) | Ultimate (20 s) |
|---|---|---|---|
| 1 | **Goku** | **Phase Shift** (was "Instant Transmission") — teleport to a random open spot about 18 studs from where you stand, in any direction (never inside cover, never off the map) (mobility) | **Energy Wave** — 1.2 s charge, then a straight beam (60 studs). Opponents hit are knocked back and input-locked 2 s (disruption) |
| 2 | **Monkey D. Luffy** | **Stretch Grapple** — fire an arm at a surface up to 45 studs away and pull yourself there (mobility) | **Gatling Barrage** — 1 s wind-up, 1.5 s punch flurry in a cone (15 studs). Hit opponents are pushed back and their half-typed code is cleared (disruption) |
| 3 | **Krillin** | **Solar Flare** — 0.4 s tell, then opponents within 25 studs who are facing you are whited out 1.5 s (can't read plates) (information denial) | **Tracking Disc** — slow disc flies 60 studs; opponents it passes are *marked* for 5 s: their plates are readable to you out to 200 studs, in line of sight (**approved exception**) (information) |
| 4 | **Vegeta** | **Saiyan Pride** — +30 % move speed for 4 s, golden aura (mobility) | **Big Bang Blast** — pick a point within 50 studs; a ground ring warns for 1 s, then a blast launches everyone inside and input-locks them 1.5 s (zone denial) |
| 5 | **Roronoa Zoro** | **Iron Guard** — 2 s stance: immune to ability knockback and locks, projectiles bounce off; move 50 % slower (defense) | **Tornado Slash** — 1 s wind-up, a tornado travels forward 40 studs, dragging opponents together along its path (disruption) |
| 6 | **L** | **Surveillance Camera** — place a small camera; for 20 s opponents within 25 studs of it show as a direction arrow on your HUD (no plate) (information) | **Deduction** — for 3 s every opponent's *outline* (not number) is visible to you through walls; every opponent is warned (information) |
| 7 | **Naruto** | **Shadow Clone** — a clone runs forward for 4 s with its own fake plate (a unique code in each observer's table). Typing a clone's code pops it: **no strike**, no kill, "It was a clone!" (misdirection) | **Spiral Sphere** — 0.6 s wind-up, lunge 20 studs; the first opponent hit is launched 25 studs and input-locked 2 s (mobility + disruption) |
| 8 | **Ichigo** | **Flash Step** — 22-stud dash; your plate vanishes for its 0.4 s (evasive mobility) | **Moon Fang Wave** — 1 s charge, wide crescent wave (40 studs); leaves a trail for 3 s that slows opponents inside by 40 % (zone control) |
| 9 | **Sasuke** (Robux) | **Lightning Dash** — 30-stud dash with a crackling trail (mobility) | **Hunter's Eye** — mark one opponent you can see for 6 s: their plate stays readable to you at any distance in line of sight (**approved exception**), and they can't use their mild ability. The target is warned (information + disruption) |
| 10 | **Satoru Gojo** (Robux) | **Blink** — teleport to a visible point within 30 studs (mobility) | **Infinity** — a 4 s barrier (10-stud radius) pushes opponents out. From activation, you can read **every opponent's number you can see, at any distance or angle** (**approved exception**, line of sight only). The reading ends after **3 eliminations or 10 s**, whichever comes first. Wrong codes still follow the strike rule (information + defense) |

## Decisions recorded (owner, 2026-09-23)

- Abilities approved as above. Goku's mild changed to Instant Transmission (random spot ~18 studs away);
  Gojo's ultimate changed to the reading version above.
- Krillin, Sasuke and Gojo reading beyond 11 studs: deliberate exceptions, line of sight only.
- Attack names: all generic. "Instant Transmission" (the one franchise attack name) was renamed **Phase Shift**
  by the owner on 2026-09-23.
- Naruto's clone: popping it is not a strike.

## Build scope per ability (Phase 3)

- **Scripter:** a server-side `AbilityService` (cooldowns, validation, effects) plus one small
  module per ability. Clients only *request* an ability; the server decides whether it fires and what it hits.
  Reading exceptions are implemented inside `NumberAssignmentService`'s disclosure gate, per caster.
- **Animator:** procedural placeholder VFX first (beams, rings, trails, flashes), built as tween/particle
  modules like the current effects. Character-specific keyframe animations need Roblox's Animation Editor:
  the animator writes the playback code and an authoring guide; the keyframes are posed by hand and handed
  back as Animation ids.
- **Modeler:** props only (L's camera, Krillin's disc; clones reuse the player's avatar).

## Owner changes after approval (2026-09-23)

- **Every effect lasts 1.75x longer** than the sheet above says (`Constants.ABILITY_EFFECT_TIME_SCALE`): input locks
  2 → 3.5 s (Big Bang 1.5 → 2.6 s; the approved 2 s lock cap scales to 3.5 s), Solar Flare 1.5 → 2.6 s, Tracking Disc
  mark 5 → 8.75 s, Saiyan Pride 4 → 7 s, Iron Guard 2 → 3.5 s, Surveillance Camera 20 → 35 s, Deduction 3 → 5.25 s,
  Shadow Clone 4 → 7 s, Flash Step plate hide 0.4 → 0.7 s, Moon Fang trail 3 → 5.25 s, Hunter's Eye 6 → 10.5 s,
  Infinity barrier 4 → 7 s and its reading 10 → 17.5 s (still ends early after 3 eliminations), Gatling flurry
  1.5 → 2.6 s. Wind-ups, cooldowns, ranges and speeds are unchanged.
- **Eli's Deduction lasts 7 s** (owner; replaces the 1.75x value of 5.25 s).
- **Flash Step and Blink go where you look** (owner): to the spot at the centre of your screen (the camera's
  ray), capped at 22 / 30 studs. Looking at ground = land there; at a wall = stop just short; up = go up that way.
  Blink also needs Gozen to see the landing spot. Dashes now home in and stop on their point (was ±4 studs).
- **Shadow Clone** steers round cover so it keeps running its whole life (the arena is dense with cover).
- **In-game character names** changed (see DESIGN.md "IP decision"): Gokai, Luffo, Krillo, Vejaro, Zorin, Eli,
  Nariko, Ichiro, Sazuki, Gozen. The table above keeps the original names as internal ids.

## Implementation notes (2026-09-23) — details the sheet left open

Placeholder numbers are marked in `Constants.luau`; these are the interpretation choices, all easy to change:
- **Cooldowns belong to the player, not the character.** Switching character on the respawn screen doesn't reset an
  ultimate; the approved respawn rule (−10 s) applies as usual.
- **Aim** is the camera direction. Beams, waves, the disc, the tornado and dashes use its horizontal part; the grapple,
  Big Bang Blast's target point and Gojo's Blink use the full 3D direction.
- **Dashes and lunges stop 2 studs short of cover**; teleports only land on open ground inside the arena.
- **Gojo's Blink** lands where you aim if that's open ground, otherwise at the farthest open spot along the aim line.
- **Solar Flare** blinds opponents within 25 studs whose *own* view cone (±60°) contains Krillin, with line of sight.
- **Iron Guard** makes Zoro immune to knockback, drags, input locks and Tracking Disc marks (not to Solar Flare).
- **Gojo's barrier** stops Krillin's disc at its edge.
- **Hunter's Eye** marks the visible opponent closest to your aim within 15°; everyone sees the mark over their head.
- **Deduction** outlines are drawn only on L's screen. **Surveillance Camera** shows arrows around the screen centre;
  a new camera replaces the old one.
- **Shadow Clone** runs 4 s at 18 studs/s using Naruto's own run animation; it disappears if Naruto dies. Clones show
  a plate to everyone but Naruto, readable under the normal 11-stud facing rule.
- **Studio only:** every character is unlocked for testing (`Constants.DEV_UNLOCK_ALL_IN_STUDIO`); live servers
  keep "free starters only" until the shop and Game Passes exist.
