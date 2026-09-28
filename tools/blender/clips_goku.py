"""Gokai's ability clips (internal id Goku), made in Blender (owner, 2026-09-28).
  mild      Phase Shift: two fingers snap to the forehead (0.3 s tell), then he lands low from the teleport
  ultimate  Energy Wave: a 1.2 s charge with the hands cupped at the hip (straining, sinking lower), then the
            blast: palms pressed together straight at the target (hand IK), a recoil, and the strain
"""
from clips_common import READY, READY_FEET, merge
from nau_anim import Clip, foot, hand

C = "Goku"


def author(rig):
    # Phase Shift ---------------------------------------------------------------------------------
    together = {"Right": foot(fwd=0.02, out=-0.04, yaw=-4), "Left": foot(fwd=0.06, out=-0.04, yaw=4)}
    focus = {
        "Root": (0, 0, 0, 0, -0.04, 0), "Waist": (-4, 0, 0), "Neck": (-12, 0, 0),
        "RightShoulder": (160, 60, -50), "RightElbow": (20, 0, 0), "RightWrist": (0, 0, 0),
        "LeftShoulder": (8, 0, -8), "LeftElbow": (10, 0, 0), "LeftWrist": (0, 0, 0),
    }
    focus_snap = merge(focus, {"Neck": (-18, 0, 0), "RightShoulder": (166, 62, -52)})
    landing_feet = {"Right": foot(fwd=-0.38, out=0.32, yaw=-16), "Left": foot(fwd=0.52, out=0.26, yaw=12)}
    landing = {
        "Root": (-24, 6, 0, 0, -0.98, 0.02), "Waist": (-14, 6, 0), "Neck": (18, -4, 0),
        "RightShoulder": (12, 0, 72), "RightElbow": (34, 0, 0), "RightWrist": (0, 0, 0),
        "LeftShoulder": (16, 0, -68), "LeftElbow": (32, 0, 0), "LeftWrist": (0, 0, 0),
    }
    Clip(rig, C, "mild", "windup", 0.3, notes="Phase Shift tell") \
        .key(0, pose=READY, feet=READY_FEET, ease="snap") \
        .key(0.1, pose=focus_snap, feet=together, ease="smooth") \
        .key(0.3, pose=focus, feet=together) \
        .build()
    Clip(rig, C, "mild", "release", 0.46, notes="Phase Shift landing") \
        .key(0, pose=landing, feet=landing_feet, ease="hold") \
        .key(0.06, pose=landing, feet=landing_feet, ease="overshoot") \
        .key(0.28, pose=READY, feet=READY_FEET, ease="smooth") \
        .key(0.46, pose=READY, feet=READY_FEET) \
        .build()

    # Energy Wave -------------------------------------------------------------------------------------
    charge_feet = {"Right": foot(fwd=-0.7, out=0.24, yaw=-26), "Left": foot(fwd=0.56, out=0.08, yaw=10)}
    charge = {
        "Root": (-6, -14, 0, 0, -0.64, 0.06), "Waist": (-8, -40, 0), "Neck": (0, 50, 0),
        "RightShoulder": (-15, 0, -40), "RightElbow": (100, 0, 0), "RightWrist": (-20, 0, 0),
        "LeftShoulder": (15, 0, 80), "LeftElbow": (40, 0, 0), "LeftWrist": (-20, 0, 0),
    }
    charge_over = merge(charge, {"Root": (-6, -18, 0, 0, -0.74, 0.08), "Waist": (-9, -46, 0), "Neck": (0, 54, 0)})
    strain_a = merge(charge, {"Waist": (-10, -43, 1.5), "Neck": (2, 51, 0), "RightElbow": (104, 0, 0)})
    strain_b = merge(charge, {"Root": (-6, -14, 0, 0, -0.68, 0.06), "Waist": (-7, -38, -1.5), "Neck": (-1, 48, 0), "LeftShoulder": (17, 0, 82)})
    deep = merge(charge, {"Root": (-8, -20, 0, 0, -0.82, 0.12), "Waist": (-12, -52, 0), "Neck": (2, 60, 0)})
    Clip(rig, C, "ultimate", "windup", 1.2, notes="Energy Wave charge") \
        .key(0, pose=READY, feet=READY_FEET, hands_ik={"Right": 0, "Left": 0}, ease="snap") \
        .key(0.16, pose=charge_over, feet=charge_feet, ease="elastic") \
        .key(0.34, pose=charge, feet=charge_feet, ease="smooth") \
        .key(0.46, pose=strain_a, feet=charge_feet, ease="smooth") \
        .key(0.58, pose=strain_b, feet=charge_feet, ease="smooth") \
        .key(0.7, pose=strain_a, feet=charge_feet, ease="smooth") \
        .key(0.82, pose=strain_b, feet=charge_feet, ease="smooth") \
        .key(0.94, pose=strain_a, feet=charge_feet, ease="whip") \
        .key(1.06, pose=deep, feet=charge_feet, ease="smooth") \
        .key(1.2, pose=deep, feet=charge_feet, hands_ik={"Right": 0, "Left": 0}) \
        .build()

    # The blast: palms pressed together straight at the target (hand IK), the body lunging in behind them.
    fire_body = {
        "Root": (-5, 6, 0, 0, -0.56, -0.18), "Waist": (-8, 6, 0), "Neck": (4, -6, 0),
        "RightShoulder": (104, 0, -24), "RightElbow": (0, 0, 0), "LeftShoulder": (104, 0, 24), "LeftElbow": (0, 0, 0),
    }
    palms = {"Right": hand(-1.3, 0.95, -1.85, 60, 0, -8), "Left": hand(1.3, 0.95, -1.85, 60, 0, 8)}
    palms_over = {"Right": hand(-1.3, 0.9, -2.05, 62, 0, -8), "Left": hand(1.3, 0.9, -2.05, 62, 0, 8)}
    recoil_body = merge(fire_body, {"Root": (-2, 6, 0, 0, -0.5, 0.12), "Waist": (-3, 6, 0), "Neck": (8, -6, 0)})
    recoil_palms = {"Right": hand(-1.3, 1.0, -1.55, 58, 0, -8), "Left": hand(1.3, 1.0, -1.55, 58, 0, 8)}
    strain_palms_a = {"Right": hand(-1.28, 0.97, -1.72, 60, 0, -8), "Left": hand(1.32, 0.93, -1.72, 60, 0, 8)}
    strain_palms_b = {"Right": hand(-1.32, 0.93, -1.72, 60, 0, -8), "Left": hand(1.28, 0.97, -1.72, 60, 0, 8)}
    both_ik = {"Right": 1, "Left": 1}
    Clip(rig, C, "ultimate", "release", 0.8, notes="Energy Wave blast") \
        .key(0, pose=deep, feet=charge_feet, hands_ik={"Right": 0, "Left": 0}, ease="snap") \
        .key(0.035, pose=fire_body, feet=charge_feet, hands=palms_over, hands_ik=both_ik, ease="snap") \
        .key(0.1, pose=fire_body, feet=charge_feet, hands=palms, ease="snap") \
        .key(0.2, pose=recoil_body, feet=charge_feet, hands=recoil_palms, ease="elastic") \
        .key(0.36, pose=merge(fire_body, {"Waist": (-7, 5, 1.5)}), feet=charge_feet, hands=strain_palms_a, ease="smooth") \
        .key(0.46, pose=merge(fire_body, {"Waist": (-9, 7, -1.5)}), feet=charge_feet, hands=strain_palms_b, ease="smooth") \
        .key(0.56, pose=merge(fire_body, {"Waist": (-7, 5, 1.5)}), feet=charge_feet, hands=strain_palms_a, hands_ik=both_ik, ease="smooth") \
        .key(0.8, pose=READY, feet=READY_FEET, hands_ik={"Right": 0, "Left": 0}) \
        .build()
