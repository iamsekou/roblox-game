"""Vejaro's ability clips (internal id Vegeta), made in Blender (owner, 2026-09-28: show-like intensity).
  mild      Rising Fury: sinks into a shaking, fists-clenched power-up (0.3 s), then explodes up into a
            chest-out roar, trembling with power, and settles into his proud arms-crossed stance (hand IK)
  ultimate  Nova Blast: steps in and thrusts one arm at the target, open palm, the other hand bracing it; the
            arm strains and shakes as the blast grows (1 s), then the release kicks him back and settles
"""
from clips_common import LEGS_ON, READY, READY_FEET, WIDE_FEET, jitter, merge
from nau_anim import Clip, foot, hand

C = "Vegeta"


def author(rig):
    # Rising Fury ------------------------------------------------------------------------------------
    power_feet = {"Right": foot(fwd=-0.25, out=0.3, yaw=-14), "Left": foot(fwd=0.25, out=0.3, yaw=14)}
    crouch = {
        "Root": (-12, 0, 0, 0, -0.62, 0.05), "Waist": (-10, 0, 0), "Neck": (-12, 0, 0),
        "RightShoulder": (10, 0, 34), "RightElbow": (76, 0, 0), "RightWrist": (-15, 0, 0),
        "LeftShoulder": (10, 0, -34), "LeftElbow": (76, 0, 0), "LeftWrist": (-15, 0, 0),
    }
    roar = {  # tall and chest out, but still sitting a little into the wide stance (fully upright out-reaches it)
        "Root": (12, 0, 0, 0, -0.14, 0.1), "Waist": (14, 0, 0), "Neck": (24, 0, 0),
        "RightShoulder": (-10, 0, 46), "RightElbow": (52, 0, 0), "RightWrist": (-20, 0, 0),
        "LeftShoulder": (-10, 0, -46), "LeftElbow": (52, 0, 0), "LeftWrist": (-20, 0, 0),
    }
    roar_over = merge(roar, {"Waist": (18, 0, 0), "Neck": (30, 0, 0), "RightShoulder": (-16, 0, 52), "LeftShoulder": (-16, 0, -52)})
    # Arms crossed, chin up, head turned a little: the wrists are placed by hand IK.
    crossed = {
        "Root": (2, 0, 0, 0, -0.08, 0.02), "Waist": (4, 0, 0), "Neck": (10, -12, 0),
        "RightShoulder": (60, 0, -40), "RightElbow": (110, 0, 0), "LeftShoulder": (60, 0, 40), "LeftElbow": (110, 0, 0),
    }
    crossed_hands = {"Right": hand(-1.78, 0.7, -0.9, 90, 0, -80), "Left": hand(1.78, 0.6, -0.95, 90, 0, 80)}
    arms_ik = {"Right": 1, "Left": 1}
    arms_off = {"Right": 0, "Left": 0}
    Clip(rig, C, "mild", "windup", 0.3, notes="Rising Fury power-up") \
        .key(0, pose=READY, feet=READY_FEET, legs_ik=LEGS_ON, ease="snap") \
        .key(0.1, pose=crouch, feet=power_feet, ease="linear") \
        .key(0.15, pose=jitter(crouch, Waist=(2, 1.5, 0), Neck=(-2, 0, 0)), feet=power_feet, ease="linear") \
        .key(0.2, pose=jitter(crouch, Waist=(-1.5, -1.5, 0), Root=(0, 0, 0, 0, -0.04, 0)), feet=power_feet, ease="linear") \
        .key(0.25, pose=jitter(crouch, Waist=(2, 1, 0), Neck=(2, 0, 0)), feet=power_feet, ease="whip") \
        .key(0.3, pose=jitter(crouch, Root=(0, 0, 0, 0, -0.06, 0)), feet=power_feet) \
        .build()
    Clip(rig, C, "mild", "release", 0.7, notes="Rising Fury roar") \
        .key(0, pose=jitter(crouch, Root=(0, 0, 0, 0, -0.06, 0)), feet=power_feet, hands_ik=arms_off, ease="snap") \
        .key(0.06, pose=roar_over, feet=power_feet, ease="overshoot") \
        .key(0.14, pose=roar, feet=power_feet, ease="linear") \
        .key(0.2, pose=jitter(roar, Waist=(2, 1, 0), Neck=(-2, 1, 0)), feet=power_feet, ease="linear") \
        .key(0.26, pose=jitter(roar, Waist=(-1.5, -1, 0), Neck=(2, -1, 0)), feet=power_feet, ease="linear") \
        .key(0.32, pose=roar, feet=power_feet, hands_ik=arms_off, ease="smooth") \
        .key(0.52, pose=crossed, feet=READY_FEET, hands=crossed_hands, hands_ik=arms_ik, ease="smooth") \
        .key(0.7, pose=crossed, feet=READY_FEET, hands=crossed_hands, hands_ik=arms_ik) \
        .build()

    # Nova Blast ---------------------------------------------------------------------------------------
    aim = {
        "Root": (-4, 16, 0, 0, -0.42, -0.08), "Waist": (-4, 14, 0), "Neck": (0, -26, 0),
        "RightShoulder": (92, 0, -5), "RightElbow": (0, 0, 0), "RightWrist": (-50, 0, 0),
        "LeftShoulder": (80, 0, 60), "LeftElbow": (0, 0, 0), "LeftWrist": (0, 0, 0),
    }
    aim_over = merge(aim, {"Root": (-6, 20, 0, 0, -0.48, -0.14), "RightShoulder": (95, 0, -7)})
    aim_deep = merge(aim, {"Root": (-6, 18, 0, 0, -0.56, -0.1), "Waist": (-6, 16, 0)})
    blast = merge(aim, {
        "Root": (8, 16, 0, 0, -0.4, 0.3), "Waist": (10, 14, 0), "Neck": (4, -24, 0),
        "RightShoulder": (118, 0, -5), "RightElbow": (16, 0, 0), "LeftShoulder": (96, 0, 60),
    })
    blast_over = merge(blast, {"Root": (12, 16, 0, 0, -0.38, 0.4), "RightShoulder": (126, 0, -5), "RightElbow": (22, 0, 0)})
    Clip(rig, C, "ultimate", "windup", 1.0, notes="Nova Blast aim") \
        .key(0, pose=READY, feet=READY_FEET, ease="snap") \
        .key(0.14, pose=aim_over, feet=WIDE_FEET, ease="overshoot") \
        .key(0.3, pose=aim, feet=WIDE_FEET, ease="linear") \
        .key(0.4, pose=jitter(aim, RightShoulder=(1.5, 0, 0), LeftShoulder=(-1.5, 0, 0)), feet=WIDE_FEET, ease="linear") \
        .key(0.5, pose=jitter(aim, RightShoulder=(-1.5, 0, 0), Waist=(1, 0, 0)), feet=WIDE_FEET, ease="linear") \
        .key(0.6, pose=jitter(aim, RightShoulder=(2, 0, 0), LeftShoulder=(-2, 0, 0)), feet=WIDE_FEET, ease="linear") \
        .key(0.7, pose=jitter(aim, RightShoulder=(-2, 0, 0), Root=(0, 0, 0, 0, -0.06, 0)), feet=WIDE_FEET, ease="linear") \
        .key(0.8, pose=jitter(aim, RightShoulder=(2.5, 0, 0), LeftShoulder=(-2.5, 0, 0)), feet=WIDE_FEET, ease="whip") \
        .key(0.92, pose=aim_deep, feet=WIDE_FEET, ease="linear") \
        .key(1.0, pose=aim_deep, feet=WIDE_FEET) \
        .build()
    Clip(rig, C, "ultimate", "release", 0.6, notes="Nova Blast release") \
        .key(0, pose=aim_deep, feet=WIDE_FEET, ease="snap") \
        .key(0.04, pose=blast_over, feet=WIDE_FEET, ease="elastic") \
        .key(0.2, pose=blast, feet=WIDE_FEET, ease="smooth") \
        .key(0.4, pose=aim, feet=WIDE_FEET, ease="smooth") \
        .key(0.6, pose=READY, feet=READY_FEET) \
        .build()
