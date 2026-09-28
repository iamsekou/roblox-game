"""Sazuki's ability clips (internal id Sasuke), made in Blender (owner, 2026-09-28: show-like intensity).
The game puts the Blade in his right hand for Lightning Dash (AbilityPoses) and draws the crackle and trails.
  mild      Lightning Dash: drops into a low charging crouch, blade held down and back, left hand forward
            (0.3 s); then the charge: stretched out mid-stride, blade driven straight ahead
  ultimate  Hunter's Eye: head bowed, one hand raised over the eye, sinking still lower as the mark gathers
            (0.8 s); then the head snaps up and the arm whips out to point at the marked opponent
"""
from clips_common import LEGS_OFF, LEGS_ON, READY, READY_FEET, merge
from nau_anim import Clip, foot

C = "Sasuke"


def author(rig):
    # Lightning Dash -----------------------------------------------------------------------------------
    low_feet = {"Right": foot(fwd=-0.66, out=0.24, yaw=-24), "Left": foot(fwd=0.45, out=0.16, yaw=10)}
    low = {  # blade down and back, left hand forward (placeholder solve for the arms)
        "Root": (-20, -16, 0, 0, -0.78, 0.06), "Waist": (-22, -20, 0), "Neck": (18, 26, 0),
        "RightShoulder": (-36, 0, 22), "RightElbow": (15, 0, 0), "RightWrist": (0, 0, 0),
        "LeftShoulder": (48, 0, 12), "LeftElbow": (40, 0, 0), "LeftWrist": (0, 0, 0),
    }
    low_over = merge(low, {"Root": (-24, -18, 0, 0, -0.9, 0.08), "RightShoulder": (-42, 0, 24)})
    # Stretched mid-stride, blade driven ahead (no IK: the dash carries him). The torso leans ~60 degrees, so the
    # arm is swung that much forward to hang straight down in the world, which points the blade (it leaves the
    # thumb side of the fist) straight ahead.
    charge = {
        "Root": (-34, 18, 0, 0, -0.34, -0.2), "Waist": (-26, 18, 0), "Neck": (40, -16, 0),
        "RightShoulder": (62, 0, -6), "RightElbow": (0, 0, 0), "RightWrist": (0, 0, 0),
        "LeftShoulder": (-40, 0, -12), "LeftElbow": (20, 0, 0), "LeftWrist": (0, 0, 0),
        "LeftHip": (54, 0, -4), "LeftKnee": (-58, 0, 0), "LeftAnkle": (10, 0, 0),
        "RightHip": (-42, 0, 4), "RightKnee": (-40, 0, 0), "RightAnkle": (24, 0, 0),
    }
    stop_feet = {"Right": foot(fwd=-0.6, out=0.24, yaw=-20), "Left": foot(fwd=0.5, out=0.18, yaw=10)}
    stop = merge(charge, {"Root": (-16, 14, 0, 0, -0.64, -0.1), "Waist": (-16, 14, 0), "Neck": (12, -12, 0)})
    Clip(rig, C, "mild", "windup", 0.3, notes="Lightning Dash crouch") \
        .key(0, pose=READY, feet=READY_FEET, legs_ik=LEGS_ON, ease="snap") \
        .key(0.13, pose=low_over, feet=low_feet, ease="elastic") \
        .key(0.3, pose=low, feet=low_feet) \
        .build()
    Clip(rig, C, "mild", "release", 0.3, notes="Lightning Dash charge") \
        .key(0, pose=low, feet=low_feet, legs_ik=LEGS_ON, ease="snap") \
        .key(0.04, pose=charge, feet=low_feet, legs_ik=LEGS_OFF, ease="linear") \
        .key(0.18, pose=charge, feet=stop_feet, legs_ik=LEGS_OFF, ease="whip") \
        .key(0.23, pose=stop, feet=stop_feet, legs_ik=LEGS_ON, ease="overshoot") \
        .key(0.3, pose=stop, feet=stop_feet, legs_ik=LEGS_ON) \
        .build()

    # Hunter's Eye -----------------------------------------------------------------------------------
    hide = {  # head bowed, hand over one eye (placeholder solve)
        "Root": (-4, 0, 0, 0, -0.24, 0.02), "Waist": (-8, 0, 0), "Neck": (-12, 0, 0),
        "RightShoulder": (100, 15, -50), "RightElbow": (60, 0, 0), "RightWrist": (0, 0, 0),
        "LeftShoulder": (-10, 0, -10), "LeftElbow": (16, 0, 0), "LeftWrist": (0, 0, 0),
    }
    hide_low = merge(hide, {"Root": (-6, 0, 0, 0, -0.36, 0.04), "Waist": (-12, 4, 0), "Neck": (-18, -6, 0)})
    point_feet = {"Right": foot(fwd=-0.4, out=0.16, yaw=-16), "Left": foot(fwd=0.36, out=0.08, yaw=8)}
    point = {
        "Root": (0, 10, 0, 0, -0.24, -0.04), "Waist": (-2, 12, 0), "Neck": (8, -10, 0),
        "RightShoulder": (92, 0, -20), "RightElbow": (0, 0, 0), "RightWrist": (0, 0, 0),
        "LeftShoulder": (-14, 0, -14), "LeftElbow": (20, 0, 0), "LeftWrist": (0, 0, 0),
    }
    point_over = merge(point, {"Root": (0, 14, 0, 0, -0.2, -0.08), "Neck": (12, -12, 0), "RightShoulder": (96, 0, -26)})
    Clip(rig, C, "ultimate", "windup", 0.8, notes="Hunter's Eye gathering") \
        .key(0, pose=READY, feet=READY_FEET, legs_ik=LEGS_ON, ease="smooth") \
        .key(0.2, pose=hide, feet=READY_FEET, ease="smooth") \
        .key(0.55, pose=hide_low, feet=READY_FEET, ease="whip") \
        .key(0.8, pose=merge(hide_low, {"Neck": (-20, -6, 0)}), feet=READY_FEET) \
        .build()
    Clip(rig, C, "ultimate", "release", 0.6, notes="Hunter's Eye mark") \
        .key(0, pose=merge(hide_low, {"Neck": (-20, -6, 0)}), feet=READY_FEET, ease="snap") \
        .key(0.05, pose=point_over, feet=point_feet, ease="overshoot") \
        .key(0.18, pose=point, feet=point_feet, ease="smooth") \
        .key(0.6, pose=point, feet=point_feet) \
        .build()
