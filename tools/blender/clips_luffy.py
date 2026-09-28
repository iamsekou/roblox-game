"""Luffo's ability clips (internal id Luffy), made in Blender (owner, 2026-09-28).
  mild      Stretch Grapple: cock the arm back (0.3 s tell), fire it out with a lunge, then get yanked off his
            feet along it, legs trailing and fluttering (the rubber arm itself is drawn by AbilityFX)
  ultimate  Blitz Barrage: a bouncing 1 s load-up, fists drawn back, then a flurry at four heights, looped
"""
from clips_common import READY, READY_FEET, merge
from nau_anim import Clip, foot

C = "Luffy"


def author(rig):
    # Stretch Grapple -----------------------------------------------------------------------------
    cock_feet = {"Right": foot(fwd=-0.58, out=0.16, yaw=-22), "Left": foot(fwd=0.46, out=0.06, yaw=6)}
    cock = {
        "Root": (-4, -22, 0, 0, -0.42, 0.08), "Waist": (-4, -34, 0), "Neck": (0, 34, 0),
        "RightShoulder": (-58, 0, 18), "RightElbow": (85, 0, 0), "RightWrist": (-10, 0, 0),
        "LeftShoulder": (58, 0, -6), "LeftElbow": (38, 0, 0), "LeftWrist": (0, 0, 0),
    }
    cock_over = merge(cock, {"Waist": (-4, -42, 0), "RightShoulder": (-68, 0, 20)})
    shoot_feet = {"Right": foot(fwd=-0.48, out=0.16, yaw=10, pitch=-26, lift=0.16), "Left": foot(fwd=0.5, out=0.06, yaw=6)}
    shoot = {
        "Root": (-14, 22, 0, 0, -0.34, -0.32), "Waist": (-14, 36, -4), "Neck": (-4, -30, 0),
        "RightShoulder": (97, 0, -2), "RightElbow": (-4, 0, 0), "RightWrist": (0, 0, 0),
        "LeftShoulder": (-42, 0, -22), "LeftElbow": (30, 0, 0),
    }
    pulled = merge(shoot, {
        "Root": (-40, 20, 0, 0, 0.1, 0), "Waist": (-12, 14, 0), "Neck": (16, -12, 0),
        "RightHip": (-36, -20, 8), "RightKnee": (-72, 0, 0), "RightAnkle": (28, 0, 0),
        "LeftHip": (-18, -20, -8), "LeftKnee": (-46, 0, 0), "LeftAnkle": (20, 0, 0),
        "LeftShoulder": (-56, 0, -36), "LeftElbow": (24, 0, 0),
    })
    flutter = merge(pulled, {"RightHip": (-30, -20, 8), "RightKnee": (-58, 0, 0), "LeftHip": (-26, -20, -8), "LeftKnee": (-62, 0, 0)})
    legs_on, legs_off = {"Right": 1, "Left": 1}, {"Right": 0, "Left": 0}
    Clip(rig, C, "mild", "windup", 0.3, notes="Stretch Grapple tell") \
        .key(0, pose=READY, feet=READY_FEET, ease="snap") \
        .key(0.2, pose=cock_over, feet=cock_feet, ease="smooth") \
        .key(0.3, pose=cock, feet=cock_feet) \
        .build()
    Clip(rig, C, "mild", "release", 0.66, notes="Stretch Grapple shot and pull") \
        .key(0, pose=cock, feet=cock_feet, legs_ik=legs_on, ease="snap") \
        .key(0.04, pose=shoot, feet=shoot_feet, legs_ik=legs_on, ease="hold") \
        .key(0.09, pose=shoot, feet=shoot_feet, legs_ik=legs_on, ease="smooth") \
        .key(0.24, pose=pulled, feet=shoot_feet, legs_ik=legs_off, ease="smooth") \
        .key(0.44, pose=flutter, feet=shoot_feet, legs_ik=legs_off, ease="smooth") \
        .key(0.66, pose=pulled, feet=shoot_feet, legs_ik=legs_off) \
        .build()

    # Blitz Barrage -------------------------------------------------------------------------------
    wide = {"Right": foot(fwd=-0.62, out=0.22, yaw=-20), "Left": foot(fwd=0.52, out=0.14, yaw=8)}
    load = {
        "Root": (8, 0, 0, 0, -0.52, 0.12), "Waist": (10, 0, 0), "Neck": (8, 0, 0),
        "RightShoulder": (-45, 0, 22), "RightElbow": (115, 0, 0), "RightWrist": (-15, 0, 0),
        "LeftShoulder": (-45, 0, -22), "LeftElbow": (115, 0, 0), "LeftWrist": (-15, 0, 0),
    }
    deep = merge(load, {"Root": (12, 0, 0, 0, -0.68, 0.16), "Waist": (15, 0, 0), "RightShoulder": (-54, 0, 24), "LeftShoulder": (-54, 0, -24)})
    Clip(rig, C, "ultimate", "windup", 1.0, notes="Blitz Barrage load-up") \
        .key(0, pose=READY, feet=READY_FEET, ease="snap") \
        .key(0.2, pose=load, feet=wide, ease="smooth") \
        .key(0.42, pose=deep, feet=wide, ease="smooth") \
        .key(0.64, pose=load, feet=wide, ease="whip") \
        .key(0.86, pose=deep, feet=wide, ease="smooth") \
        .key(1.0, pose=deep, feet=wide) \
        .build()

    base = {"Root": (-10, 0, 0, 0, -0.46, -0.16), "Waist": (-14, 0, 0), "Neck": (-2, 0, 0), "RightWrist": (0, 0, 0), "LeftWrist": (0, 0, 0)}
    right_back = {"RightShoulder": (38, 0, 12), "RightElbow": (120, 0, 0)}
    left_back = {"LeftShoulder": (38, 0, -12), "LeftElbow": (120, 0, 0)}
    r_high = merge(base, left_back, {"Root": (-10, 8, 0, 0, -0.46, -0.18), "Waist": (-14, 18, 0), "Neck": (-2, -8, 0), "RightShoulder": (108, 0, -8), "RightElbow": (0, 0, 0)})
    l_mid = merge(base, right_back, {"Root": (-10, -8, 0, 0, -0.48, -0.16), "Waist": (-15, -18, 0), "Neck": (-2, 8, 0), "LeftShoulder": (92, 0, 8), "LeftElbow": (0, 0, 0)})
    r_low = merge(base, left_back, {"Root": (-11, 8, 0, 0, -0.5, -0.16), "Waist": (-17, 16, 2), "Neck": (-2, -6, 0), "RightShoulder": (76, 0, -14), "RightElbow": (0, 0, 0)})
    l_high = merge(base, right_back, {"Root": (-10, -8, 0, 0, -0.46, -0.18), "Waist": (-14, -20, -2), "Neck": (-2, 8, 0), "LeftShoulder": (110, 0, 6), "LeftElbow": (0, 0, 0)})
    Clip(rig, C, "ultimate", "release", 0.28, looped=True, notes="Blitz Barrage flurry") \
        .key(0, pose=r_high, feet=wide, ease="snap") \
        .key(0.07, pose=l_mid, feet=wide, ease="snap") \
        .key(0.14, pose=r_low, feet=wide, ease="snap") \
        .key(0.21, pose=l_high, feet=wide, ease="snap") \
        .key(0.28, pose=r_high, feet=wide) \
        .build()
