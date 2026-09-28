"""Nariko's ability clips (internal id Naruto), made in Blender (owner, 2026-09-28: show-like intensity).
  mild      Mirror Decoy: drops into a wide stance and snaps the crossed-fingers hand seal up in front of the
            chest (0.3 s); a little kick up as the decoys appear, seal held
  ultimate  Vortex Orb: the right palm out low at the hip, the left hand circling over it shaping the orb
            (0.6 s), sinking as it grows; then the lunge: body stretched out, palm driven into the target,
            the back leg trailing, and back to the ready stance
"""
from clips_common import LEGS_OFF, LEGS_ON, READY, READY_FEET, WIDE_FEET, jitter, merge
from nau_anim import Clip, foot

C = "Naruto"


def author(rig):
    # Mirror Decoy ---------------------------------------------------------------------------------------
    seal = {  # crossed-fingers seal in front of the chest (placeholder solve)
        "Root": (-6, 0, 0, 0, -0.5, 0.04), "Waist": (-6, 0, 0), "Neck": (-6, 0, 0),
        "RightShoulder": (70, 15, -50), "RightElbow": (30, 0, 0), "RightWrist": (0, 0, 0),
        "LeftShoulder": (70, -15, 50), "LeftElbow": (30, 0, 0), "LeftWrist": (0, 0, 0),
    }
    seal_over = merge(seal, {"Root": (-8, 0, 0, 0, -0.6, 0.06), "RightShoulder": (74, 15, -52), "LeftShoulder": (74, -15, 52)})
    seal_up = merge(seal, {"Root": (-2, 0, 0, 0, -0.36, 0.02), "Waist": (-2, 0, 0), "Neck": (-2, 0, 0)})
    Clip(rig, C, "mild", "windup", 0.3, notes="Mirror Decoy seal") \
        .key(0, pose=READY, feet=READY_FEET, legs_ik=LEGS_ON, ease="snap") \
        .key(0.12, pose=seal_over, feet=WIDE_FEET, ease="overshoot") \
        .key(0.3, pose=seal, feet=WIDE_FEET) \
        .build()
    Clip(rig, C, "mild", "release", 0.35, notes="Mirror Decoy: the decoys appear") \
        .key(0, pose=seal, feet=WIDE_FEET, ease="snap") \
        .key(0.07, pose=seal_up, feet=WIDE_FEET, ease="overshoot") \
        .key(0.2, pose=seal, feet=WIDE_FEET, ease="smooth") \
        .key(0.35, pose=seal, feet=WIDE_FEET) \
        .build()

    # Vortex Orb ----------------------------------------------------------------------------------------
    form_feet = {"Right": foot(fwd=-0.6, out=0.24, yaw=-24), "Left": foot(fwd=0.48, out=0.16, yaw=10)}
    form = {  # right palm out low, left hand over it (placeholder solve)
        "Root": (-8, -16, 0, 0, -0.5, 0.06), "Waist": (-10, -25, 0), "Neck": (0, 30, 0),
        "RightShoulder": (0, 45, 20), "RightElbow": (40, 0, 0), "RightWrist": (0, 0, 0),
        "LeftShoulder": (50, 15, 70), "LeftElbow": (0, 0, 0), "LeftWrist": (0, 0, 0),
    }
    form_over = merge(form, {"Root": (-10, -20, 0, 0, -0.6, 0.08), "Waist": (-12, -30, 0), "Neck": (0, 34, 0)})
    swirl_a = jitter(form, LeftShoulder=(6, 6, -6), Waist=(0, -2, 0))
    swirl_b = jitter(form, LeftShoulder=(-5, -6, 6), Waist=(0, 2, 0))
    form_deep = merge(form, {"Root": (-12, -18, 0, 0, -0.64, 0.08), "Waist": (-14, -28, 0)})
    drive = {
        # The torso leans ~56 degrees into the lunge, so the arm is raised that much more to drive the palm
        # straight at the target (at 92 it pointed into the ground).
        "Root": (-30, 16, 0, 0, -0.42, -0.5), "Waist": (-26, 16, 0), "Neck": (40, -10, 0),
        "RightShoulder": (140, 0, -6), "RightElbow": (0, 0, 0), "RightWrist": (-40, 0, 0),
        "LeftShoulder": (-48, 0, -14), "LeftElbow": (12, 0, 0), "LeftWrist": (0, 0, 0),
        # A running lunge (the server carries him 20 studs): front knee driving, back leg stretched behind.
        "LeftHip": (58, 0, -6), "LeftKnee": (-72, 0, 0), "LeftAnkle": (10, 0, 0),
        "RightHip": (-34, 0, 6), "RightKnee": (-24, 0, 0), "RightAnkle": (20, 0, 0),
    }
    drive_follow = merge(drive, {"Root": (-24, 20, 0, 0, -0.46, -0.44), "Waist": (-20, 20, 0), "RightShoulder": (136, 0, -10), "Neck": (32, -10, 0)})
    Clip(rig, C, "ultimate", "windup", 0.6, notes="Vortex Orb forming") \
        .key(0, pose=READY, feet=READY_FEET, legs_ik=LEGS_ON, ease="snap") \
        .key(0.14, pose=form_over, feet=form_feet, ease="elastic") \
        .key(0.28, pose=form, feet=form_feet, ease="smooth") \
        .key(0.36, pose=swirl_a, feet=form_feet, ease="smooth") \
        .key(0.44, pose=swirl_b, feet=form_feet, ease="smooth") \
        .key(0.52, pose=swirl_a, feet=form_feet, ease="whip") \
        .key(0.6, pose=form_deep, feet=form_feet) \
        .build()
    Clip(rig, C, "ultimate", "release", 0.5, notes="Vortex Orb lunge") \
        .key(0, pose=form_deep, feet=form_feet, legs_ik=LEGS_ON, ease="snap") \
        .key(0.05, pose=drive, feet=form_feet, legs_ik=LEGS_OFF, ease="linear") \
        .key(0.22, pose=drive, feet=form_feet, legs_ik=LEGS_OFF, ease="overshoot") \
        .key(0.32, pose=drive_follow, feet=READY_FEET, legs_ik=LEGS_ON, ease="smooth") \
        .key(0.5, pose=READY, feet=READY_FEET, legs_ik=LEGS_ON) \
        .build()
