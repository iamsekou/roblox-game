"""Zorin's ability clips (internal id Zoro), made in Blender (owner, 2026-09-28: show-like intensity).
The game puts the swords in his hands and mouth itself (AbilityPoses: KatanaRed, KatanaDark, Katana).
  mild      Iron Guard: drops into a wide, low stance with both blades crossed in front (0.3 s), then holds
            it, looped for the whole guard: breathing, blades trembling with tension
  ultimate  Cyclone Cut: blades raised crossed over the left shoulder, hips and torso wound hard left, sinking
            as the power builds (1 s); then a leaping full spin, arms flung wide, landing low
"""
from clips_common import LEGS_OFF, LEGS_ON, READY, READY_FEET, WIDE_FEET, jitter, merge
from nau_anim import Clip, foot

C = "Zoro"

GUARD = {  # blades crossed in front (placeholder solve), braced low
    "Root": (-12, 0, 0, 0, -0.56, 0.02), "Waist": (-12, 0, 0), "Neck": (8, 0, 0),
    "RightShoulder": (120, 30, -60), "RightElbow": (0, 0, 0), "RightWrist": (0, 0, 0),
    "LeftShoulder": (120, -30, 60), "LeftElbow": (0, 0, 0), "LeftWrist": (0, 0, 0),
}


def author(rig):
    # Iron Guard ---------------------------------------------------------------------------------------
    guard_feet = {"Right": foot(fwd=-0.55, out=0.28, yaw=-24), "Left": foot(fwd=0.5, out=0.2, yaw=12)}
    guard_over = merge(GUARD, {"Root": (-14, 0, 0, 0, -0.66, 0.04), "Waist": (-14, 0, 0), "RightShoulder": (124, 30, -62), "LeftShoulder": (124, -30, 62)})
    Clip(rig, C, "mild", "windup", 0.3, notes="Iron Guard") \
        .key(0, pose=READY, feet=READY_FEET, legs_ik=LEGS_ON, ease="snap") \
        .key(0.16, pose=guard_over, feet=guard_feet, ease="overshoot") \
        .key(0.3, pose=GUARD, feet=guard_feet) \
        .build()
    breathe_in = jitter(GUARD, Root=(0, 0, 0, 0, 0.03, 0), Waist=(1.5, 0, 0), RightShoulder=(1.5, 0, 0), LeftShoulder=(1.5, 0, 0))
    breathe_out = jitter(GUARD, Root=(0, 0, 0, 0, -0.03, 0), Waist=(-1, 0, 0), RightShoulder=(-1, 0, 0), LeftShoulder=(-1, 0, 0))
    Clip(rig, C, "mild", "release", 0.8, looped=True, notes="Iron Guard held") \
        .key(0, pose=GUARD, feet=guard_feet, ease="smooth") \
        .key(0.2, pose=breathe_in, feet=guard_feet, ease="smooth") \
        .key(0.4, pose=jitter(GUARD, RightShoulder=(0.8, 0, 0.8), LeftShoulder=(-0.8, 0, -0.8)), feet=guard_feet, ease="smooth") \
        .key(0.6, pose=breathe_out, feet=guard_feet, ease="smooth") \
        .key(0.8, pose=GUARD, feet=guard_feet) \
        .build()

    # Cyclone Cut ----------------------------------------------------------------------------------------
    wind_feet = {"Right": foot(fwd=-0.45, out=0.3, yaw=10), "Left": foot(fwd=0.45, out=0.22, yaw=30)}
    wind = {  # blades over the left shoulder, wound left (placeholder solve for the arms)
        "Root": (-6, 32, 0, 0, -0.56, 0.04), "Waist": (0, 46, 0), "Neck": (0, -62, 0),
        "RightShoulder": (130, -15, -70), "RightElbow": (0, 0, 0), "RightWrist": (0, 0, 0),
        "LeftShoulder": (120, 0, 20), "LeftElbow": (90, 0, 0), "LeftWrist": (0, 0, 0),
    }
    wind_over = merge(wind, {"Root": (-6, 38, 0, 0, -0.64, 0.06), "Waist": (0, 54, 0), "Neck": (0, -70, 0)})
    wind_deep = merge(wind, {"Root": (-10, 40, 0, 0, -0.74, 0.06), "Waist": (-4, 56, 0), "Neck": (0, -72, 0)})
    # The spin: a leap with the legs tucked (no IK in the air), arms flung wide, one full turn from the wound
    # position (Root Y 40) round to facing ahead (-320 = 40 - 360), keyed every 90 degrees so it turns one way.
    def spin(y, height):
        return {
            "Root": (-6, y, 0, 0, height, 0), "Waist": (-8, 0, 0), "Neck": (0, -8, 0),
            "RightShoulder": (22, 0, 82), "RightElbow": (5, 0, 0), "LeftShoulder": (22, 0, -82), "LeftElbow": (5, 0, 0),
            "RightHip": (42, 0, 8), "RightKnee": (-84, 0, 0), "RightAnkle": (10, 0, 0),
            "LeftHip": (48, 0, -8), "LeftKnee": (-90, 0, 0), "LeftAnkle": (10, 0, 0),
        }
    land_feet = {"Right": foot(fwd=-0.55, out=0.3, yaw=-20), "Left": foot(fwd=0.5, out=0.24, yaw=12)}
    land = {
        "Root": (-14, -360, 0, 0, -0.72, 0.04), "Waist": (-12, 0, 0), "Neck": (8, 0, 0),
        "RightShoulder": (36, 0, 64), "RightElbow": (10, 0, 0), "LeftShoulder": (36, 0, -64), "LeftElbow": (10, 0, 0),
    }
    finish = merge(land, {"Root": (-8, -360, 0, 0, -0.44, 0.02), "RightShoulder": (44, 0, 50), "LeftShoulder": (44, 0, -50)})
    Clip(rig, C, "ultimate", "windup", 1.0, notes="Cyclone Cut wind-up") \
        .key(0, pose=READY, feet=READY_FEET, legs_ik=LEGS_ON, ease="snap") \
        .key(0.2, pose=wind_over, feet=wind_feet, ease="elastic") \
        .key(0.38, pose=wind, feet=wind_feet, ease="smooth") \
        .key(0.55, pose=jitter(wind, Root=(0, 2, 0, 0, -0.04, 0), Waist=(0, 2, 0)), feet=wind_feet, ease="smooth") \
        .key(0.72, pose=jitter(wind, Waist=(0, -1, 0), RightShoulder=(2, 0, 0)), feet=wind_feet, ease="whip") \
        .key(0.9, pose=wind_deep, feet=wind_feet, ease="linear") \
        .key(1.0, pose=wind_deep, feet=wind_feet) \
        .build()
    Clip(rig, C, "ultimate", "release", 0.6, follow={"Neck": (7.0, 0.5)}, notes="Cyclone Cut spin") \
        .key(0, pose=wind_deep, feet=wind_feet, legs_ik=LEGS_ON, ease="snap") \
        .key(0.05, pose=spin(-50, 0.05), feet=wind_feet, legs_ik=LEGS_OFF, ease="linear") \
        .key(0.12, pose=spin(-140, 0.3), feet=wind_feet, legs_ik=LEGS_OFF, ease="linear") \
        .key(0.19, pose=spin(-230, 0.34), feet=wind_feet, legs_ik=LEGS_OFF, ease="linear") \
        .key(0.26, pose=spin(-320, 0.18), feet=land_feet, legs_ik=LEGS_OFF, ease="whip") \
        .key(0.32, pose=land, feet=land_feet, legs_ik=LEGS_ON, ease="overshoot") \
        .key(0.6, pose=finish, feet=land_feet, legs_ik=LEGS_ON) \
        .build()
