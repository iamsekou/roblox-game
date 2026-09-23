# Ability sheet — PROPOSAL, awaiting approval (nothing implemented)

Every character has a **mild** ability (8 s cooldown) and an **ultimate** (20 s cooldown). After a
respawn the mild is ready and the ultimate loses 10 s of remaining cooldown (minimum 0).

## Ground rules every ability follows

1. **No ability eliminates anyone.** Eliminations only come from typing a correct number.
2. **No ability shows numbers through walls.** Plates stay depth-tested. Information abilities reveal
   *positions* or make plates *easier to read in line of sight*, never hidden numbers.
3. **Disruption is short.** The longest "can't submit" lock is 2 s; knockbacks never push anyone out of the arena
   (the invisible barriers already stop that).
4. **Everything has a tell.** Mild: 0.3–0.6 s wind-up. Ultimate: 0.8–1.5 s wind-up with sound and a VFX
   cue visible from range (animator Phase 1 guidance).
5. **Spawn protection:** abilities are disabled while protected (same as submitting), and protected
   fighters are immune to ability effects.
6. **Robux characters are not stronger**, just different. Balance numbers live in Constants.

"Input lock" = the target can't submit codes (their entry box greys out) — it never touches movement.

## The sheet

| # | Character | Mild (8 s) | Ultimate (20 s) |
|---|---|---|---|
| 1 | **Goku** | **Instant Step** — blink 18 studs forward; afterimage at both ends (mobility) | **Energy Wave** — 1.2 s charge, then a straight beam (60 studs). Opponents hit are knocked back and input-locked 2 s (disruption) |
| 2 | **Monkey D. Luffy** | **Stretch Grapple** — fire an arm at a surface up to 45 studs away and pull yourself there (mobility) | **Gatling Barrage** — 1 s wind-up, 1.5 s punch flurry in a cone (15 studs). Hit opponents are pushed back and their half-typed code is cleared (disruption) |
| 3 | **Krillin** | **Solar Flare** — 0.4 s tell, then opponents within 25 studs who are facing you are blinded 1.5 s (white-out: can't read plates) (information denial) | **Tracking Disc** — slow disc flies 60 studs; opponents it passes are *marked* for 5 s: their plates grow and read out to 200 studs for you (in line of sight only) (information) |
| 4 | **Vegeta** | **Saiyan Pride** — +30 % move speed for 4 s, golden aura (mobility) | **Big Bang Blast** — pick a point within 50 studs; a ground ring warns for 1 s, then a blast knocks everyone inside up and input-locks them 1.5 s (zone denial) |
| 5 | **Roronoa Zoro** | **Iron Guard** — 2 s stance: immune to ability knockback/locks and projectiles bounce off; move 50 % slower (defense) | **Tornado Slash** — 1 s wind-up, a tornado travels forward 40 studs, dragging opponents together along its path (groups targets so plates are easier to read) (disruption) |
| 6 | **L** | **Surveillance Camera** — place a small camera; for 20 s opponents within 25 studs of it show as a direction ping on your HUD (no plate) (information) | **Deduction** — for 3 s every opponent's *outline* (not number) is visible to you through walls; every opponent is warned "You've been deduced" (information) |
| 7 | **Naruto** | **Shadow Clone** — a clone runs forward for 4 s with its own fake plate (a unique code in each observer's table). Typing a clone's code pops it: no strike, no kill, "It was a clone!" (misdirection) | **Spiral Sphere** — 0.6 s glowing wind-up, lunge 20 studs; the first opponent hit is launched 25 studs and input-locked 2 s (mobility + disruption) |
| 8 | **Ichigo** | **Flash Step** — 22-stud dash; your plate vanishes for its 0.4 s (evasive mobility) | **Moon Fang Wave** — 1 s charge, wide crescent wave (40 studs); leaves a dark trail for 3 s that slows opponents inside by 40 % (zone control) |
| 9 | **Sasuke** (Robux) | **Lightning Dash** — 30-stud dash with a crackling trail (mobility) | **Hunter's Eye** — mark one opponent you can see for 6 s: their plate stays readable to you at any distance in line of sight, and they can't use their mild ability. The target is warned (information + disruption) |
| 10 | **Satoru Gojo** (Robux) | **Blink** — teleport to a visible point within 30 studs (mobility) | **Infinity** — 4 s barrier (10-stud radius): opponents are pushed out and projectiles stop at the edge. Your number can still be typed by anyone who can see it (defense) |

## Build scope per ability (Phase 3)

- **Scripter:** a server-side `AbilityService` (cooldowns, validation, effects) plus one small
  module per ability. Clients only *request* an ability; the server decides whether it fires and what it hits.
- **Animator:** procedural placeholder VFX first (beams, rings, trails, flashes), built as tween/particle
  modules like the current effects. Character-specific keyframe animations (poses, wind-ups) need Roblox's
  Animation Editor. The animator writes the playback code and a step-by-step authoring guide, and the
  keyframes are posed by hand (you or an animator) and handed back as Animation ids.
- **Modeler:** props only (L's camera, Krillin's disc, clone rigs reuse the player's avatar).

## Open questions for approval

1. Approve / change each ability above.
2. **Attack names:** use generic names as listed, or the signature franchise names (e.g. "Kamehameha",
   "Rasengan", "Getsuga Tenshō", "Chidori")? The franchise names carry the same IP risk as the character names.
3. Naruto's clone: popping a clone is **not** a strike (proposed). Should it be one?
4. Build order: I suggest the two free characters (Goku, Luffy) first as the Phase 3 vertical slice of the
   ability system, then the rest.
