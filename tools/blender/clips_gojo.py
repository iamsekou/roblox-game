"""Gozen's ability clips (internal id Gojo), made in Blender (owner, 2026-09-28: show-like intensity).
Gozen is the opposite of everyone else: unhurried, loose, completely at ease; the power shows in how little
he has to move. Smooth eases, hips relaxed, weight on one leg.
  mild      Blink: two fingers flick up in front of the chest (0.3 s); he arrives already relaxed
  ultimate  Boundless: the crossed-finger sign raised in front of the face, held calmly (0.8 s); then the
            arms open slowly, chin up, as the barrier forms around him
"""
from clips_common import LEGS_ON, merge
from nau_anim import Clip, foot

C = "Gojo"

EASY_FEET = {"Right": foot(fwd=-0.12, out=0.08, yaw=-12), "Left": foot(fwd=0.14, out=0.02, yaw=10)}
EASY = {  # weight on one hip, hands loose at the sides
    "Root": (2, 0, 4, 0.08, -0.06, 0), "Waist": (4, 0, -3), "Neck": (4, 0, 2),
    "RightShoulder": (-6, 0, 12), "RightElbow": (30, 0, 0), "RightWrist": (0, 0, 0),
    "LeftShoulder": (-6, 0, -12), "LeftElbow": (30, 0, 0), "LeftWrist": (0, 0, 0),
}


def author(rig):
    # Blink --------------------------------------------------------------------------------------------
    fingers = merge(EASY, {"RightShoulder": (90, 30, -40), "RightElbow": (50, 0, 0), "Neck": (6, 0, 0)})  # placeholder solve
    fingers_over = merge(fingers, {"RightShoulder": (96, 32, -42), "RightElbow": (46, 0, 0)})
    arrive = merge(EASY, {"Root": (4, 0, 2, 0.04, -0.08, 0.04), "RightShoulder": (40, 0, -10), "RightElbow": (60, 0, 0)})
    Clip(rig, C, "mild", "windup", 0.3, notes="Blink") \
        .key(0, pose=EASY, feet=EASY_FEET, legs_ik=LEGS_ON, ease="snap") \
        .key(0.12, pose=fingers_over, feet=EASY_FEET, ease="overshoot") \
        .key(0.3, pose=fingers, feet=EASY_FEET) \
        .build()
    Clip(rig, C, "mild", "release", 0.25, notes="Blink arrival") \
        .key(0, pose=arrive, feet=EASY_FEET, ease="smooth") \
        .key(0.25, pose=EASY, feet=EASY_FEET) \
        .build()

    # Boundless ------------------------------------------------------------------------------------------
    sign = merge(EASY, {  # crossed-finger sign in front of the face (placeholder solve)
        "Root": (0, 0, 0, 0, -0.06, 0), "Waist": (4, 0, 0), "Neck": (4, 0, 0),
        "RightShoulder": (110, -15, -60), "RightElbow": (20, 0, 0), "LeftShoulder": (14, 0, -10), "LeftElbow": (24, 0, 0),
    })
    sign_focus = merge(sign, {"Neck": (0, 0, 0), "Waist": (2, 0, 0)})
    open_ = merge(EASY, {
        "Root": (4, 0, 0, 0, -0.04, 0.02), "Waist": (8, 0, 0), "Neck": (12, 0, 0),
        "RightShoulder": (28, 0, 48), "RightElbow": (20, 0, 0), "LeftShoulder": (28, 0, -48), "LeftElbow": (20, 0, 0),
    })
    open_wide = merge(open_, {"RightShoulder": (32, 0, 56), "LeftShoulder": (32, 0, -56), "Neck": (14, 0, 0)})
    Clip(rig, C, "ultimate", "windup", 0.8, notes="Boundless sign") \
        .key(0, pose=EASY, feet=EASY_FEET, legs_ik=LEGS_ON, ease="smooth") \
        .key(0.26, pose=sign, feet=EASY_FEET, ease="smooth") \
        .key(0.8, pose=sign_focus, feet=EASY_FEET) \
        .build()
    Clip(rig, C, "ultimate", "release", 1.0, notes="Boundless opening") \
        .key(0, pose=sign_focus, feet=EASY_FEET, ease="smooth") \
        .key(0.45, pose=open_wide, feet=EASY_FEET, ease="smooth") \
        .key(1.0, pose=open_, feet=EASY_FEET) \
        .build()
