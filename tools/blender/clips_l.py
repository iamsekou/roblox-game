"""Eli's ability clips (internal id L), made in Blender (owner, 2026-09-28: show-like intensity).
Eli never stands straight: hunched, feet close, head forward, a thumb drifting to his lip.
  mild      Surveillance Camera: drops straight into his deep, knees-up squat to set the camera down
            (0.3 s), holds it a beat, then rises back into the slouch, thumb at the lip, head tilting
  ultimate  Deduction: the thinking slouch deepens (0.8 s): thumb pressed to the lip, the other arm folded,
            head tilting side to side; then the answer lands: the head snaps up, eyes wide, he straightens
"""
from clips_common import LEGS_ON, merge
from nau_anim import Clip, foot

C = "L"

NARROW = {"Right": foot(fwd=0.0, out=-0.02, yaw=-8), "Left": foot(fwd=0.06, out=-0.02, yaw=8)}
SLOUCH = {
    "Root": (-6, 0, 0, 0, -0.26, 0.04), "Waist": (-22, 0, 0), "Neck": (16, 0, 0),
    "RightShoulder": (-8, 0, 8), "RightElbow": (22, 0, 0), "RightWrist": (0, 0, 0),
    "LeftShoulder": (-8, 0, -8), "LeftElbow": (22, 0, 0), "LeftWrist": (0, 0, 0),
}
THUMB = {"RightShoulder": (120, 45, -50), "RightElbow": (60, 0, 0)}  # thumb at the lip (placeholder solve)


def author(rig):
    # Surveillance Camera --------------------------------------------------------------------------
    squat_feet = {"Right": foot(fwd=0.05, out=0.12, yaw=-14), "Left": foot(fwd=0.1, out=0.12, yaw=14)}
    squat = {
        "Root": (-26, 0, 0, 0, -1.12, 0.1), "Waist": (-34, 0, 0), "Neck": (28, 0, 0),
        "RightShoulder": (52, 0, -6), "RightElbow": (28, 0, 0), "RightWrist": (0, 0, 0),
        "LeftShoulder": (20, 0, 6), "LeftElbow": (60, 0, 0), "LeftWrist": (0, 0, 0),
    }
    squat_over = merge(squat, {"Root": (-28, 0, 0, 0, -1.2, 0.12), "RightShoulder": (58, 0, -6)})
    thinking = merge(SLOUCH, THUMB, {"Neck": (12, 0, 8)})
    Clip(rig, C, "mild", "windup", 0.3, notes="Surveillance Camera squat") \
        .key(0, pose=SLOUCH, feet=NARROW, legs_ik=LEGS_ON, ease="whip") \
        .key(0.2, pose=squat_over, feet=squat_feet, ease="overshoot") \
        .key(0.3, pose=squat, feet=squat_feet) \
        .build()
    Clip(rig, C, "mild", "release", 0.6, notes="Surveillance Camera, back to the slouch") \
        .key(0, pose=squat, feet=squat_feet, ease="hold") \
        .key(0.1, pose=squat, feet=squat_feet, ease="smooth") \
        .key(0.34, pose=thinking, feet=NARROW, ease="smooth") \
        .key(0.48, pose=merge(thinking, {"Neck": (12, 0, 12)}), feet=NARROW, ease="smooth") \
        .key(0.6, pose=thinking, feet=NARROW) \
        .build()

    # Deduction -----------------------------------------------------------------------------------------
    deep = {  # the thinking slouch: thumb at the lip, the other arm folded across (placeholder solve)
        "Root": (-8, 0, 0, 0, -0.44, 0.06), "Waist": (-24, 0, 0), "Neck": (14, 0, 10),
        "RightShoulder": (150, 75, -50), "RightElbow": (60, 0, 0), "RightWrist": (0, 0, 0),
        "LeftShoulder": (50, 0, 60), "LeftElbow": (0, 0, 0), "LeftWrist": (0, 0, 0),
    }
    tilt_other = merge(deep, {"Neck": (14, 4, -8), "Waist": (-24, 3, 2)})
    deepest = merge(deep, {"Root": (-10, 0, 0, 0, -0.56, 0.08), "Waist": (-28, 0, 0), "Neck": (10, 0, 12)})
    realize = {
        "Root": (-2, 0, 0, 0, -0.16, 0.02), "Waist": (-12, 0, 0), "Neck": (26, 0, 0),
        "RightShoulder": (130, 60, -40), "RightElbow": (60, 0, 0), "RightWrist": (0, 0, 0),
        "LeftShoulder": (50, 0, 60), "LeftElbow": (0, 0, 0), "LeftWrist": (0, 0, 0),
    }
    realize_over = merge(realize, {"Root": (0, 0, 0, 0, -0.1, 0), "Neck": (32, 0, 0)})
    Clip(rig, C, "ultimate", "windup", 0.8, notes="Deduction thinking") \
        .key(0, pose=SLOUCH, feet=NARROW, legs_ik=LEGS_ON, ease="smooth") \
        .key(0.24, pose=deep, feet=NARROW, ease="smooth") \
        .key(0.46, pose=tilt_other, feet=NARROW, ease="smooth") \
        .key(0.66, pose=deep, feet=NARROW, ease="whip") \
        .key(0.8, pose=deepest, feet=NARROW) \
        .build()
    Clip(rig, C, "ultimate", "release", 0.9, notes="Deduction: the answer lands") \
        .key(0, pose=deepest, feet=NARROW, ease="snap") \
        .key(0.08, pose=realize_over, feet=NARROW, ease="overshoot") \
        .key(0.3, pose=realize, feet=NARROW, ease="smooth") \
        .key(0.9, pose=merge(realize, {"Neck": (20, 0, 4), "Waist": (-15, 0, 0)}), feet=NARROW) \
        .build()
