# Authoring the ability animations (Phase 3 item 8)

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
| Luffo | Gatling Barrage (ult) | 1.0 s | **2.6 s, Looped** | Both fists drawn back, leaning back → rapid alternating straight punches, torso rocking |
| Krillo | Solar Flare (mild) | 0.4 s | 0.5 s | Open hands framing the face → arms flung wide with the flash, chin up |
| Krillo | Tracking Disc (ult) | 0.8 s | 0.45 s | Right arm straight up, disc on the palm, looking up → side-arm throw across the body |
| Vejaro | Saiyan Pride (mild) | 0.3 s | 0.7 s | Crouched power-up, fists clenched → chest out, head back, roar |
| Vejaro | Big Bang Blast (ult) | 1.0 s | 0.5 s | Right arm straight out, open palm, left hand bracing it → recoil |
| Zorin | Iron Guard (mild) | 0.3 s | **3.5 s, Looped** | Blades crossed in front, braced forward, held the whole stance |
| Zorin | Tornado Slash (ult) | 1.0 s | 0.55 s | Blades raised over the left shoulder, torso wound left → one full spin, arms flung wide |
| Eli | Surveillance Camera (mild) | 0.3 s | 0.6 s | Deep stoop to set the camera down → hunched, thumb at the lip |
| Eli | Deduction (ult) | 0.8 s | 0.9 s | Thinking slouch: hunched, head tilted, thumb at the lip, other arm folded → head comes up |
| Nariko | Shadow Clone (mild) | 0.3 s | 0.3 s | Crossed-fingers hand seal in front of the chest |
| Nariko | Spiral Sphere (ult) | 0.6 s | 0.5 s | Right palm out low with the sphere, left hand shaping it → lunge, right palm driven forward |
| Ichiro | Flash Step (mild) | 0.3 s | 0.35 s | Low forward crouch, arms trailing → arrives with the blade arm out to the side |
| Ichiro | Moon Fang Wave (ult) | 1.0 s | 0.5 s | Two-handed grip raised over the right shoulder → one big diagonal slash down across the body |
| Sazuki | Lightning Dash (mild) | 0.3 s | 0.3 s | Crouched, crackling blade held low and back in the right hand, left hand forward → blade driven ahead in a thrust |
| Sazuki | Hunter's Eye (ult) | 0.8 s | 0.6 s | Head bowed, hand raised over one eye → head snaps up, arm points at the target |
| Gozen | Blink (mild) | 0.3 s | 0.25 s | Relaxed and upright, two fingers raised in front of the chest |
| Gozen | Infinity (ult) | 0.8 s | 1.0 s | Crossed-finger sign in front of the face → arms open calmly, chin up |

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
| Zorin | Iron Guard, Tornado Slash | `KatanaRed` (right hand) + `KatanaDark` (left hand) + `Katana` (in the mouth, blade out past the right cheek) |
| Ichiro | Flash Step, Moon Fang Wave | `Cleaver` (right hand) |
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
