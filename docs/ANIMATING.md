# Authoring the ability animations (Phase 3 item 8)

## Keyframed fight clips, made in Blender (2026-09-27, moved to Blender 2026-09-28)

Every fighter's moves are keyframed (51 clips) and **already play in game**; nothing has to be published first.
Each character keeps their signature body language (owner, 2026-09-28: "similar to their characters in shows"):

| Clips | Moves |
|---|---|
| M1 (every fighter), `Melee` | lead jab, rear straight, lead hook, rear uppercut finisher (one orthodox stance throughout); the flinch; "launched" (thrown by the finisher); the M1 clash exchange (looped) |
| Gokai, `Goku` | Phase Shift (fingers to the forehead, lands low), Energy Wave (straining charge at the hip, palms-together blast by hand IK, recoil) |
| Luffo, `Luffy` | Stretch Grapple (cock, lunge, yanked off his feet), Blitz Barrage (bouncing load, four-height flurry, looped) |
| Krillo, `Krillin` | Blinding Burst (hands framing the face, springs onto his toes at the flash), Tracking Disc (arm straight up, bobbing hold, side-arm throw) |
| Vejaro, `Vegeta` | Rising Fury (shaking crouch, chest-out roar, settles arms crossed by hand IK), Nova Blast (braced arm straining, recoil) |
| Zorin, `Zoro` | Iron Guard (low crossed-blade stance, breathing loop), Cyclone Cut (wound over the left shoulder, leaping full spin, low landing) |
| Eli, `L` | Surveillance Camera (deep knees-up squat, back to the thumb-at-lip slouch), Deduction (thinking slouch, head tilting, snaps up) |
| Nariko, `Naruto` | Mirror Decoy (snapped hand seal), Vortex Orb (orb swirled at the hip, running lunge driving the palm) |
| Ichiro, `Ichigo` | Blur Step (coil, mid-stride blur, lands blade out), Crescent Wave (two-handed overhead charge, diagonal slash, heel pivot) |
| Sazuki, `Sasuke` | Lightning Dash (low charge, mid-stride thrust), Hunter's Eye (hand over the eye, snaps up to point) |
| Gozen, `Gojo` | Blink (two fingers flick up), Boundless (calm sign, arms open slowly): deliberately unhurried |

Lean compensation: when a torso leans hard into a lunge, arms that must hit or point straight ahead get that lean
added back (Nariko's palm, Sazuki's blade); otherwise they point into the floor.

### The Blender pipeline (`tools/blender`, not synced)

| File | What it does |
|---|---|
| `rig_r15.json` | The game's R15 rig, captured in Studio from the player avatar (joint frames, part sizes) |
| `nau_rig.py` | Builds that rig in Blender: one bone per joint, foot IK (planted feet), optional hand IK, poles tuned so the rest pose is exact, body boxes for renders |
| `nau_anim.py` | The authoring API: keys in the game's joint angles, foot and hand goals, eases (`snap`, `whip`, `overshoot`, `elastic`, `hold`, ...), follow-through springs |
| `clips_melee.py`, `clips_goku.py`, `clips_luffy.py` | The moves |
| `build.py` | Makes `NAU_Fights.blend` (every clip as an editable action) |
| `export.py` | Bakes each action (IK solved, 60 fps) into `animations/Clips/<Module>.luau` and renders a review sheet per clip into `tools/blender/renders` |
| `selftest.py` | Checks the maths: the rest pose exports as zero, keyed angles round-trip exactly, a crouch keeps the feet planted |

```bash
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" --background --factory-startup --python tools/blender/build.py
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" tools/blender/NAU_Fights.blend --background --python tools/blender/export.py
```

- **Editing a clip yourself:** open `tools/blender/NAU_Fights.blend`, select `NAU_Rig`, and pick the clip's action
  (e.g. `Melee_m1_4_release`) in the Action Editor. Pose the joint bones; move `FootTarget.R/L` to plant the feet
  and `HandTarget.R/L` to place the hands. IK on or off is the influence of the knee and elbow IK constraints. Save,
  run the export, and the game has it. **Don't rebuild** after hand edits: `build.py` recreates the .blend from the
  `clips_*.py` files and would drop them.
- The export warns when a planted foot is out of the leg's reach (the leg would stretch out flat): lunge less or
  bring the foot in.
- Blender's `ZYX` Euler order is exactly Roblox's `CFrame.Angles`, and on this rig a bone's local pose converts to
  the joint Transform through its rest orientation, so what Blender shows is what the game plays. That was checked
  numerically (`selftest.py`) and on the real avatar in Studio.
- **Format in game:** `src/shared/Modules/KeyframeClip.luau`. The Blender export writes `dense` clips: one key per
  baked frame, linear between, binary-searched. Hand-written sparse clips still work, and `KeyframeClip.stance` /
  `mirror` help with those.
- **Playback:** `AbilityAnim` plays a clip wherever one exists, in place of the placeholder pose. It poses the whole
  body; while a fighter walks on the ground, the legs are handed back to the walk so the feet never skate. A
  published id in `AnimationIds` still wins over both.
- **Timing rule for blows:** the server lands a punch at the end of its wind-up, and the hit-stop freezes both
  fighters at that instant. So a punch reaches its strike on the **last frame of its wind-up**, and a reaction
  **starts** on its hit pose. Otherwise the freeze shows the wrong moment.
- **Impact layer** (`animations/Controllers/ImpactFX.luau`) is added on top: hit-stop, shockwaves, dust,
  afterimages on dashes and launches, and a camera shake plus a black-and-white impact frame for the two fighters
  involved. Both follow the Screen shake setting.

### Publishing (optional)

`tools/clips/build_keyframe_sequences.luau` builds a KeyframeSequence for every clip into
`ServerStorage.AnimationWork.Clips`, named `<Character>_<slot>_<windup|release>` (e.g. `Melee_m1_4_release`). Claude
runs it in Edit mode after changing clips. The sequences are baked at 60 frames a second. Played back, they match the
in-game data playback exactly (checked joint by joint, 2026-09-27: 0.0° difference).

To publish one: right-click it → **Save to Roblox**, under the experience's owner (see step 5 below). Then put its id
in `src/shared/Modules/AnimationIds.luau` at `ids[<Character>][<slot>][<windup|release>]`.

**Trade-off:** a published clip is played by Roblox's Animator, which can't hand the legs back to the walk. Moves
that key the legs (the uppercut, the reactions, the clash, Gokai's and Luffo's moves) would skate the feet if the
fighter walks during them. The data version is already seen by every player, so publishing is only worth it if you
want to keep editing a clip in the Animation Editor.

## Hand-keyframing in Studio's Animation Editor

Every ability already animates, using a procedural placeholder pose (`animations/Controllers/AbilityPoses.luau`).
This guide covers replacing those placeholders with hand-keyframed clips made in Studio's Animation Editor.
Each clip you publish replaces one placeholder the moment its id goes into `src/shared/Modules/AnimationIds.luau`.
Anything left blank keeps the placeholder, so the clips can arrive one at a time.

## How a cast plays

1. The server accepts an ability and tells every client "cast" (who cast it, which character and slot, and the cast time).
2. **Wind-up clip:** plays for the cast time (the tell or charge). A non-looping wind-up is sped up or slowed down
   to end exactly when the ability fires, so its length only needs to be close. A looping wind-up plays at normal speed.
3. **Release clip:** starts the instant the ability fires. A looping release (a flurry or a held stance) runs for the
   hold time below and then fades out. A non-looping release plays once, to its end.
4. The caster's own client plays the clips, and Roblox replicates them to everyone else.
5. Dying cancels the cast immediately.

The code sets the priority to **Action**, so walking never cancels a cast.

## Clip list: 20 abilities, 2 clips each

Suggested order: Gokai and Luffo first (4 abilities, 8 clips). Test those in game before doing the rest.

| Character | Ability (slot) | Wind-up length | Release length | What it should look like (placeholder pose) |
|---|---|---|---|---|
| Gokai | Phase Shift (mild) | 0.3 s | 0.35 s | Two fingers to the forehead, head bowed → lands in a ready crouch |
| Gokai | Energy Wave (ult) | 1.2 s (charge) | 0.6 s | Cupped hands drawn back to the right hip, torso wound right, eyes on target → both arms thrust straight out, palms together |
| Luffo | Stretch Grapple (mild) | 0.3 s | 0.6 s | Right arm cocked back → arm shot straight out and held for the pull |
| Luffo | Blitz Barrage (ult) | 1.0 s | **2.6 s, Looped** | Both fists drawn back, leaning back → rapid alternating straight punches, torso rocking |
| Krillo | Blinding Burst (mild) | 0.4 s | 0.5 s | Open hands framing the face → arms flung wide with the flash, chin up |
| Krillo | Tracking Disc (ult) | 0.8 s | 0.45 s | Right arm straight up, disc on the palm, looking up → side-arm throw across the body |
| Vejaro | Rising Fury (mild) | 0.3 s | 0.7 s | Crouched power-up, fists clenched → chest out, head back, roar |
| Vejaro | Nova Blast (ult) | 1.0 s | 0.5 s | Right arm straight out, open palm, left hand bracing it → recoil |
| Zorin | Iron Guard (mild) | 0.3 s | **3.5 s, Looped** | Blades crossed in front, braced forward, held the whole stance |
| Zorin | Cyclone Cut (ult) | 1.0 s | 0.55 s | Blades raised over the left shoulder, torso wound left → one full spin, arms flung wide |
| Eli | Surveillance Camera (mild) | 0.3 s | 0.6 s | Deep stoop to set the camera down → hunched, thumb at the lip |
| Eli | Deduction (ult) | 0.8 s | 0.9 s | Thinking slouch: hunched, head tilted, thumb at the lip, other arm folded → head comes up |
| Nariko | Mirror Decoy (mild) | 0.3 s | 0.3 s | Crossed-fingers hand seal in front of the chest |
| Nariko | Vortex Orb (ult) | 0.6 s | 0.5 s | Right palm out low with the sphere, left hand shaping it → lunge, right palm driven forward |
| Ichiro | Blur Step (mild) | 0.3 s | 0.35 s | Low forward crouch, arms trailing → arrives with the blade arm out to the side |
| Ichiro | Crescent Wave (ult) | 1.0 s | 0.5 s | Two-handed grip raised over the right shoulder → one big diagonal slash down across the body |
| Sazuki | Lightning Dash (mild) | 0.3 s | 0.3 s | Crouched, crackling blade held low and back in the right hand, left hand forward → blade driven ahead in a thrust |
| Sazuki | Hunter's Eye (ult) | 0.8 s | 0.6 s | Head bowed, hand raised over one eye → head snaps up, arm points at the target |
| Gozen | Blink (mild) | 0.3 s | 0.25 s | Relaxed and upright, two fingers raised in front of the chest |
| Gozen | Boundless (ult) | 0.8 s | 1.0 s | Crossed-finger sign in front of the face → arms open calmly, chin up |

Lengths come from `Constants.luau` (cast times) and `AbilityPoses.luau` (hold times). If a number there changes,
this table goes stale. The wind-up auto-fits either way.

## Rules for the clips

- **Key the upper body only:** waist, neck, shoulders, elbows and wrists. Fighters can walk while casting, and legs keyed
  at Action priority would slide across the floor. The exception is a move you want to root in place. If you do
  that, tell me, and I'll decide with you whether its movement should stop too.
- **Don't key the HumanoidRootPart.** Every movement effect (dashes, teleports, pulls) comes from the server, not the clip.
- **Short tells are short on purpose.** A 0.3 s tell is a readable flick, not a performance. Put the big motion in the release.
- **Leave out effects and swords.** Glows, beams, trails, slash arcs and the swords themselves are added by the game
  on top of the clip.
- Keep the names and attack styling original (see "IP decision" in `DESIGN.md`). The poses can follow the source moves,
  as approved on 2026-09-23.

## Sword fighters (Zorin, Ichiro, Sazuki)

The game puts the sword in the hand by itself. It appears with a flash when the wind-up starts and dissolves after
the strike, so **never key a sword into a clip**. These moves draw swords:

| Character | Moves | Sword(s) |
|---|---|---|
| Zorin | Iron Guard, Cyclone Cut | `KatanaRed` (right hand) + `KatanaDark` (left hand) + `Katana` (in the mouth, blade out past the right cheek) |
| Ichiro | Blur Step, Crescent Wave | `Cleaver` (right hand) |
| Sazuki | Lightning Dash | `Blade` (right hand) |

The blade comes out of the thumb side of the fist, so it points forward from a hanging arm and straight up from an
arm raised forward. Blade trails, glows, crackle and slash arcs are drawn by the game on top of your clip.

**Pose against the real sword.** Copies of all four are in `ServerStorage.AnimationWork.Swords`. To hold one on your
rig while animating, paste this into the command bar (change `Rig` to your rig's name):

```lua
local rig = workspace.Rig
local function hold(kind, handName)
	local sword = game.ServerStorage.AnimationWork.Swords[kind]:Clone()
	local hand = rig[handName]
	local grip = CFrame.new(0, -0.3, 0) -- the same grip the game uses
	if handName == "Head" then -- Zorin's mouth sword, same placement as the game
		local s = hand.Size
		grip = CFrame.new(0, -0.22 * s.Y, -s.Z / 2 - 0.08) * CFrame.Angles(0, math.rad(-90), 0) * CFrame.new(0, 0, -0.18 * s.X)
	end
	sword:PivotTo(hand.CFrame * grip)
	local weld = Instance.new("Weld")
	weld.Part0 = hand
	weld.Part1 = sword.PrimaryPart
	weld.C0 = grip
	weld.Parent = sword.PrimaryPart
	sword.Parent = rig
end
-- Zorin (for Ichiro use hold("Cleaver", "RightHand"); for Sazuki hold("Blade", "RightHand")):
hold("KatanaRed", "RightHand")
hold("KatanaDark", "LeftHand")
hold("Katana", "Head")
```

The editor only records joint keyframes, so the sword isn't saved into the clip. You can leave it on the rig.

## Step by step in Studio

1. **Get a rig.** Avatar tab → Rig Builder → R15 → Block Rig (or your own avatar). All fighters are R15, and the game's
   rigs use AnimationConstraint joints, which the Animation Editor handles.
2. **Open the editor.** Avatar tab → Animation Editor, then click the rig. Name the clip after the table,
   e.g. `Gokai_EnergyWave_Windup`.
3. **Pose it.** Set the length from the table and key the poses. For a looped release (Gatling, Iron Guard), turn on
   **Looping** in the editor so the first and last frames match.
4. **Set the priority** to Action (⋯ → Set Animation Priority → Action). The code sets it anyway; this keeps the file honest.
5. **Publish.** ⋯ → Publish to Roblox. **Publish it under the same owner as the experience** (your account, or the group
   if the place ever moves to one). Roblox won't load another owner's animation in your game, so a clip published
   under the wrong owner silently fails to play.
6. **Copy the id** from the publish dialog (the digits in `rbxassetid://123…`) and paste it into
   `src/shared/Modules/AnimationIds.luau`, in the right character / slot / `windup` or `release` field. Digits alone,
   or the full `rbxassetid://…`, both work. Or send me the ids and I'll paste them in.
7. **Test.** Play solo (Studio attribute `NAU_DevMinPlayers = 1`), equip the character, and press Q or E. Every character
   is unlocked in Studio.

Save the rig and your clips in Studio (for example in a `ServerStorage.AnimationWork` folder) so they can be re-edited.
That folder isn't synced by Rojo.

## Checking your ids

The unit tests (`AnimTimeline.spec`) check that blank, junk and valid ids are read correctly. If an id is typed wrong,
that clip falls back to the placeholder instead of erroring. If a valid id doesn't play, check the Output window for
Roblox's "Failed to load animation" error (or `[NAU] couldn't load ability animation …`). That's almost always the
ownership issue in step 5.
