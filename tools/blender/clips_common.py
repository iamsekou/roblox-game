"""Shared stances and poses for the fight clips (Roblox joint angles in degrees; see nau_anim)."""
from nau_anim import foot, merge

# Fighting stance: orthodox (left foot forward), back foot turned out, knees soft. Every M1 blow starts and
# ends here, so the feet never jump between punches.
GUARD_FEET = {
    "Right": foot(fwd=-0.5, out=0.14, yaw=-18),
    "Left": foot(fwd=0.42, out=0.04, yaw=6),
}
GUARD = {
    "Root": (0, -12, 0, 0, -0.34, 0.03),
    "Waist": (-6, 14, 0),
    "Neck": (-3, -2, 0),
    "RightShoulder": (56, 0, 16),
    "RightElbow": (120, 0, 0),
    "RightWrist": (-8, 0, 0),
    "LeftShoulder": (64, 0, -12),
    "LeftElbow": (118, 0, 0),
    "LeftWrist": (-8, 0, 0),
}

# A neutral ready stance for the ability moves (square, knees soft, hands loose and up).
READY_FEET = {"Right": foot(fwd=-0.3, out=0.1, yaw=-8), "Left": foot(fwd=0.3, out=0.06, yaw=6)}
READY = {
    "Root": (0, 0, 0, 0, -0.22, 0),
    "Waist": (-6, 0, 0),
    "Neck": (-2, 0, 0),
    "RightShoulder": (30, 0, 14),
    "RightElbow": (70, 0, 0),
    "RightWrist": (0, 0, 0),
    "LeftShoulder": (30, 0, -14),
    "LeftElbow": (70, 0, 0),
    "LeftWrist": (0, 0, 0),
}


# A wide, low power stance (right foot back) and feet together (upright, poised).
WIDE_FEET = {"Right": foot(fwd=-0.62, out=0.22, yaw=-20), "Left": foot(fwd=0.5, out=0.14, yaw=8)}
TOGETHER_FEET = {"Right": foot(fwd=0.02, out=-0.04, yaw=-4), "Left": foot(fwd=0.06, out=-0.04, yaw=4)}
# Up on the toes (heels lifted), from a feet dict.
def on_toes(base, pitch=-18, lift=0.1):
    return {side: dict(f, pitch=pitch, lift=lift) for side, f in base.items()}

LEGS_ON = {"Right": 1, "Left": 1}
LEGS_OFF = {"Right": 0, "Left": 0}


def feet(right=None, left=None, base=None):
    """A feet dict starting from `base` (GUARD_FEET by default), with either foot replaced."""
    out = dict(base or GUARD_FEET)
    if right is not None:
        out["Right"] = right
    if left is not None:
        out["Left"] = left
    return out


def jitter(pose, **offsets):
    """A pose with small offsets added to some joints (strain tremble, breathing): jitter(P, Waist=(1, 0, 0))."""
    out = dict(pose)
    for joint, delta in offsets.items():
        base = list(out[joint])
        for i, d in enumerate(delta):
            base[i] += d
        out[joint] = tuple(base)
    return out


__all__ = ["GUARD", "GUARD_FEET", "READY", "READY_FEET", "WIDE_FEET", "TOGETHER_FEET", "LEGS_ON", "LEGS_OFF",
           "on_toes", "feet", "merge", "foot", "jitter"]
