"""Ichiro's ability clips (internal id Ichigo), made in Blender (owner, 2026-09-28: show-like intensity).
The game puts the Cleaver in his right hand itself (AbilityPoses) and draws the blade trails.
  mild      Blur Step: coils into a low forward crouch, arms trailing (0.3 s); then the blur: body stretched
            out mid-stride, and he arrives low, blade arm swept out to the side
  ultimate  Crescent Wave: the huge blade raised two-handed over the right shoulder, body wound back and
            sinking as it charges (1 s); then one diagonal slash down across the body, the back heel
            pivoting, a follow-through, and the blade settles low
"""
from clips_common import LEGS_OFF, LEGS_ON, READY, READY_FEET, jitter, merge
from nau_anim import Clip, foot

C = "Ichigo"


def author(rig):
    # Blur Step ---------------------------------------------------------------------------------------
    crouch_feet = {"Right": foot(fwd=-0.55, out=0.2, yaw=-18), "Left": foot(fwd=0.4, out=0.12, yaw=8)}
    crouch = {
        "Root": (-24, 0, 0, 0, -0.72, 0.04), "Waist": (-26, 0, 0), "Neck": (26, 0, 0),
        "RightShoulder": (-32, 0, 16), "RightElbow": (20, 0, 0), "RightWrist": (0, 0, 0),
        "LeftShoulder": (-42, 0, -12), "LeftElbow": (20, 0, 0), "LeftWrist": (0, 0, 0),
    }
    crouch_deep = merge(crouch, {"Root": (-28, 0, 0, 0, -0.84, 0.06), "RightShoulder": (-40, 0, 18), "LeftShoulder": (-50, 0, -14)})
    blur = {  # stretched mid-stride (no IK: he's off the ground)
        "Root": (-38, 0, 0, 0, -0.3, -0.2), "Waist": (-14, 0, 0), "Neck": (30, 0, 0),
        "RightShoulder": (-58, 0, 22), "RightElbow": (10, 0, 0), "LeftShoulder": (-62, 0, -18), "LeftElbow": (12, 0, 0),
        "LeftHip": (56, 0, -4), "LeftKnee": (-64, 0, 0), "LeftAnkle": (10, 0, 0),
        "RightHip": (-40, 0, 4), "RightKnee": (-36, 0, 0), "RightAnkle": (24, 0, 0),
    }
    arrive_feet = {"Right": foot(fwd=-0.6, out=0.26, yaw=-24), "Left": foot(fwd=0.45, out=0.2, yaw=12)}
    arrive = {
        "Root": (-12, -10, 0, 0, -0.6, 0.04), "Waist": (-12, -8, 0), "Neck": (8, 12, 0),
        "RightShoulder": (36, 0, 58), "RightElbow": (10, 0, 0), "RightWrist": (0, 0, 0),
        "LeftShoulder": (-22, 0, -6), "LeftElbow": (16, 0, 0), "LeftWrist": (0, 0, 0),
    }
    arrive_over = merge(arrive, {"Root": (-16, -12, 0, 0, -0.72, 0.06), "RightShoulder": (40, 0, 66)})
    Clip(rig, C, "mild", "windup", 0.3, notes="Blur Step coil") \
        .key(0, pose=READY, feet=READY_FEET, legs_ik=LEGS_ON, ease="snap") \
        .key(0.16, pose=crouch, feet=crouch_feet, ease="smooth") \
        .key(0.3, pose=crouch_deep, feet=crouch_feet) \
        .build()
    Clip(rig, C, "mild", "release", 0.35, notes="Blur Step blur and arrival") \
        .key(0, pose=crouch_deep, feet=crouch_feet, legs_ik=LEGS_ON, ease="snap") \
        .key(0.04, pose=blur, feet=crouch_feet, legs_ik=LEGS_OFF, ease="linear") \
        .key(0.13, pose=blur, feet=arrive_feet, legs_ik=LEGS_OFF, ease="whip") \
        .key(0.18, pose=arrive_over, feet=arrive_feet, legs_ik=LEGS_ON, ease="overshoot") \
        .key(0.35, pose=arrive, feet=arrive_feet, legs_ik=LEGS_ON) \
        .build()

    # Crescent Wave ------------------------------------------------------------------------------------
    raise_feet = {"Right": foot(fwd=-0.62, out=0.26, yaw=-22), "Left": foot(fwd=0.5, out=0.18, yaw=10)}
    raised = {  # two-handed grip over the right shoulder (placeholder solve)
        "Root": (4, -20, 0, 0, -0.46, 0.1), "Waist": (8, -30, 0), "Neck": (0, 38, 0),
        "RightShoulder": (120, 45, 10), "RightElbow": (50, 0, 0), "RightWrist": (0, 0, 0),
        "LeftShoulder": (140, 15, 70), "LeftElbow": (0, 0, 0), "LeftWrist": (0, 0, 0),
    }
    raised_over = merge(raised, {"Root": (6, -26, 0, 0, -0.54, 0.12), "Waist": (10, -36, 0), "Neck": (0, 44, 0)})
    raised_deep = merge(raised, {"Root": (6, -28, 0, 0, -0.66, 0.14), "Waist": (12, -40, 0), "Neck": (0, 46, 0), "RightShoulder": (126, 45, 12)})
    slash_feet = {"Right": foot(fwd=-0.45, out=0.26, yaw=14, pitch=-24, lift=0.14), "Left": foot(fwd=0.55, out=0.18, yaw=10)}
    slash = {  # one diagonal slash down across the body
        "Root": (-12, 28, 0, 0, -0.6, -0.3), "Waist": (-24, 38, 0), "Neck": (0, -30, 0),
        "RightShoulder": (80, 30, -60), "RightElbow": (0, 0, 0), "RightWrist": (10, 0, 0),
        "LeftShoulder": (30, 0, 40), "LeftElbow": (40, 0, 0), "LeftWrist": (0, 0, 0),
    }
    follow = merge(slash, {"Root": (-14, 32, 0, 0, -0.64, -0.32), "Waist": (-28, 46, 0), "RightShoulder": (62, 30, -80)})
    settle = merge(slash, {"Root": (-6, 16, 0, 0, -0.44, -0.1), "Waist": (-12, 20, 0), "Neck": (4, -18, 0), "RightShoulder": (40, 10, -30)})
    Clip(rig, C, "ultimate", "windup", 1.0, notes="Crescent Wave charge") \
        .key(0, pose=READY, feet=READY_FEET, legs_ik=LEGS_ON, ease="snap") \
        .key(0.18, pose=raised_over, feet=raise_feet, ease="elastic") \
        .key(0.36, pose=raised, feet=raise_feet, ease="smooth") \
        .key(0.52, pose=jitter(raised, Waist=(1.5, -1.5, 0), RightShoulder=(1.5, 0, 0)), feet=raise_feet, ease="smooth") \
        .key(0.68, pose=jitter(raised, Waist=(-1, 1, 0), LeftShoulder=(1.5, 0, 0)), feet=raise_feet, ease="whip") \
        .key(0.88, pose=raised_deep, feet=raise_feet, ease="linear") \
        .key(1.0, pose=raised_deep, feet=raise_feet) \
        .build()
    Clip(rig, C, "ultimate", "release", 0.55, notes="Crescent Wave slash") \
        .key(0, pose=raised_deep, feet=raise_feet, ease="snap") \
        .key(0.05, pose=slash, feet=slash_feet, ease="hold") \
        .key(0.09, pose=slash, feet=slash_feet, ease="overshoot") \
        .key(0.22, pose=follow, feet=slash_feet, ease="smooth") \
        .key(0.55, pose=settle, feet=raise_feet) \
        .build()
