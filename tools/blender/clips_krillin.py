"""Krillo's ability clips (internal id Krillin), made in Blender (owner, 2026-09-28: show-like intensity).
  mild      Blinding Burst: a quick squat as the open hands snap up to frame the face (0.4 s tell), a tense
            tremble, then the flash: he springs up onto his toes, arms flung wide, chest and chin up
  ultimate  Tracking Disc: the arm shoots straight up with the disc spinning on the palm, eyes up, a bobbing
            hold as it grows (0.8 s), a wind back onto the rear foot, then a whipping side-arm throw
"""
from clips_common import LEGS_ON, READY, READY_FEET, jitter, merge, on_toes
from nau_anim import Clip, foot

C = "Krillin"


def author(rig):
    # Blinding Burst ---------------------------------------------------------------------------------
    squat_feet = {"Right": foot(fwd=-0.2, out=0.18, yaw=-10), "Left": foot(fwd=0.24, out=0.16, yaw=10)}
    frame = {  # open hands either side of the face (placeholder solve)
        "Root": (4, 0, 0, 0, -0.34, 0.02), "Waist": (-2, 0, 0), "Neck": (5, 0, 0),
        "RightShoulder": (20, 45, 120), "RightElbow": (80, 0, 0), "RightWrist": (0, 0, 0),
        "LeftShoulder": (20, -45, -120), "LeftElbow": (80, 0, 0), "LeftWrist": (0, 0, 0),
    }
    frame_over = merge(frame, {"Root": (4, 0, 0, 0, -0.44, 0.02), "Neck": (2, 0, 0), "RightShoulder": (24, 48, 126), "LeftShoulder": (24, -48, -126)})
    flash = {
        "Root": (9, 0, 0, 0, -0.04, 0.1), "Waist": (12, 0, 0), "Neck": (18, 0, 0),
        "RightShoulder": (104, 0, 48), "RightElbow": (8, 0, 0), "RightWrist": (-20, 0, 0),
        "LeftShoulder": (104, 0, -48), "LeftElbow": (8, 0, 0), "LeftWrist": (-20, 0, 0),
    }
    flash_over = merge(flash, {"Waist": (15, 0, 0), "Neck": (22, 0, 0), "RightShoulder": (110, 0, 62), "LeftShoulder": (110, 0, -62)})
    Clip(rig, C, "mild", "windup", 0.4, notes="Blinding Burst tell") \
        .key(0, pose=READY, feet=READY_FEET, legs_ik=LEGS_ON, ease="snap") \
        .key(0.12, pose=frame_over, feet=squat_feet, ease="overshoot") \
        .key(0.24, pose=frame, feet=squat_feet, ease="linear") \
        .key(0.3, pose=jitter(frame, Waist=(1.5, 0, 0), Neck=(-2, 0, 0)), feet=squat_feet, ease="linear") \
        .key(0.35, pose=jitter(frame, Waist=(-1, 0, 0), Neck=(1.5, 0, 0)), feet=squat_feet, ease="whip") \
        .key(0.4, pose=frame_over, feet=squat_feet) \
        .build()
    Clip(rig, C, "mild", "release", 0.5, notes="Blinding Burst flash") \
        .key(0, pose=frame_over, feet=squat_feet, ease="snap") \
        .key(0.05, pose=flash_over, feet=on_toes(squat_feet, -20, 0.12), ease="overshoot") \
        .key(0.14, pose=flash, feet=on_toes(squat_feet, -12, 0.06), ease="smooth") \
        .key(0.3, pose=flash, feet=squat_feet, ease="smooth") \
        .key(0.5, pose=READY, feet=READY_FEET) \
        .build()

    # Tracking Disc ----------------------------------------------------------------------------------
    raise_ = {
        "Root": (6, 0, 0, 0, -0.28, 0.04), "Waist": (8, 0, 0), "Neck": (18, 0, 0),
        "RightShoulder": (176, 0, 4), "RightElbow": (4, 0, 0), "RightWrist": (0, 0, 0),
        "LeftShoulder": (18, 0, -40), "LeftElbow": (30, 0, 0), "LeftWrist": (0, 0, 0),
    }
    raise_over = merge(raise_, {"Root": (8, 0, 0, 0, -0.2, 0.04), "Neck": (24, 0, 0), "RightShoulder": (182, 0, 2)})
    wind_feet = {"Right": foot(fwd=-0.55, out=0.18, yaw=-22), "Left": foot(fwd=0.32, out=0.08, yaw=8)}
    wind = merge(raise_, {
        "Root": (4, -30, 0, 0, -0.42, 0.04), "Waist": (4, -28, 0), "Neck": (6, 36, 0),
        "RightShoulder": (158, 0, 26), "RightElbow": (22, 0, 0), "LeftShoulder": (40, 0, -30),
    })
    throw_feet = {"Right": foot(fwd=-0.42, out=0.18, yaw=12, pitch=-22, lift=0.12), "Left": foot(fwd=0.46, out=0.08, yaw=8)}
    throw = {
        "Root": (-8, 24, 0, 0, -0.36, -0.28), "Waist": (-18, 30, 0), "Neck": (2, -26, 0),
        "RightShoulder": (72, 0, -40), "RightElbow": (8, 0, 0), "RightWrist": (10, 0, 0),
        "LeftShoulder": (-26, 0, -14), "LeftElbow": (30, 0, 0), "LeftWrist": (0, 0, 0),
    }
    follow = merge(throw, {"Waist": (-20, 40, 0), "RightShoulder": (60, 0, -72), "RightElbow": (14, 0, 0)})
    Clip(rig, C, "ultimate", "windup", 0.8, notes="Tracking Disc raise") \
        .key(0, pose=READY, feet=READY_FEET, ease="snap") \
        .key(0.13, pose=raise_over, feet=READY_FEET, ease="overshoot") \
        .key(0.3, pose=raise_, feet=READY_FEET, ease="smooth") \
        .key(0.42, pose=jitter(raise_, Root=(0, 0, 0, 0, 0.03, 0), Neck=(3, 0, 0)), feet=READY_FEET, ease="smooth") \
        .key(0.54, pose=raise_, feet=READY_FEET, ease="smooth") \
        .key(0.64, pose=jitter(raise_, Root=(0, 0, 0, 0, 0.03, 0), Neck=(3, 0, 0)), feet=READY_FEET, ease="whip") \
        .key(0.8, pose=wind, feet=wind_feet) \
        .build()
    Clip(rig, C, "ultimate", "release", 0.45, notes="Tracking Disc throw") \
        .key(0, pose=wind, feet=wind_feet, ease="snap") \
        .key(0.06, pose=throw, feet=throw_feet, ease="overshoot") \
        .key(0.16, pose=follow, feet=throw_feet, ease="smooth") \
        .key(0.45, pose=READY, feet=READY_FEET) \
        .build()
