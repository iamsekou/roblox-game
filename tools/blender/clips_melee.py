"""M1 fight clips, shared by every fighter (owner, 2026-09-28: stronger, more animated, made in Blender).

Timing rule (the game's): a punch lands Constants.M1_WINDUP = 0.13 s after the click, when the server's hit and
the hit-stop arrive. So each wind-up loads, then *whips* (accelerating) into the strike on its last frame,
and each release starts on the strike, held for the impact frame. Reactions start on their hit pose.
The combo keeps one orthodox stance (left foot forward) so the feet never jump between blows:
  m1_1 lead jab (left)   m1_2 rear straight (right)   m1_3 lead hook (left)   m1_4 rear uppercut (launches)
"""
from clips_common import GUARD, GUARD_FEET, feet, merge
from nau_anim import Clip, foot

M = "Melee"
PUNCH_WINDUP = 0.13


def punch(rig, slot, load, strike, follow, strike_feet, load_feet=None, follow_at=0.1, length=0.26, notes=""):
    """Guard -> load (the anticipation) -> whip into the strike on the wind-up's last frame; then the strike
    held (impact frame), an overshooting follow-through, and back to guard."""
    Clip(rig, M, slot, "windup", PUNCH_WINDUP, notes=notes) \
        .key(0, pose=GUARD, feet=GUARD_FEET, ease="smooth") \
        .key(0.075, pose=load, feet=load_feet or GUARD_FEET, ease="whip") \
        .key(PUNCH_WINDUP, pose=strike, feet=strike_feet) \
        .build()
    Clip(rig, M, slot, "release", length, notes=notes) \
        .key(0, pose=strike, feet=strike_feet, ease="hold") \
        .key(0.04, pose=strike, feet=strike_feet, ease="overshoot") \
        .key(follow_at, pose=follow, feet=strike_feet, ease="smooth") \
        .key(length, pose=GUARD, feet=GUARD_FEET) \
        .build()


def author(rig):
    # m1_1 lead jab: a flick from the front hand, the lead foot stepping in.
    jab_load = merge(GUARD, {
        "Root": (-2, -4, 0, 0, -0.36, 0.1), "Waist": (-5, 6, 0),
        "LeftShoulder": (46, 0, -26), "LeftElbow": (130, 0, 0),
    })
    jab_strike = merge(GUARD, {
        "Root": (-5, -16, 0, 0, -0.34, -0.38), "Waist": (-8, -22, 3), "Neck": (1, 20, 0),
        "LeftShoulder": (99, 0, 12), "LeftElbow": (-2, 0, 0), "LeftWrist": (6, 0, 0),
        "RightShoulder": (58, 0, 22), "RightElbow": (128, 0, 0),
    })
    jab_follow = merge(jab_strike, {"Waist": (-7, -27, 3), "LeftShoulder": (95, 0, 8), "LeftElbow": (6, 0, 0)})
    step_in = feet(left=foot(fwd=0.7, out=0.04, yaw=6))
    punch(rig, "m1_1", jab_load, jab_strike, jab_follow, step_in, notes="lead jab")

    # m1_2 rear straight: the whole body turns through it, the back heel lifting as the hips drive.
    cross_load = merge(GUARD, {
        "Root": (-3, -24, 0, 0, -0.38, 0.14), "Waist": (-6, -14, 0), "Neck": (-4, 22, 0),
        "RightShoulder": (38, 0, 32), "RightElbow": (132, 0, 0),
    })
    cross_strike = merge(GUARD, {
        "Root": (-7, 28, 0, 0, -0.32, -0.3), "Waist": (-8, 30, -3), "Neck": (2, -28, 0),
        "RightShoulder": (99, 0, -14), "RightElbow": (-3, 0, 0), "RightWrist": (7, 0, 0),
        "LeftShoulder": (50, 0, -28), "LeftElbow": (132, 0, 0),
    })
    cross_follow = merge(cross_strike, {"Root": (-7, 33, 0, 0, -0.32, -0.33), "Waist": (-7, 36, -3), "RightShoulder": (93, 0, -8), "RightElbow": (8, 0, 0)})
    # The rear foot drags in behind the hips as the heel lifts (planting it 0.5 back would out-reach the leg).
    pivot = feet(right=foot(fwd=-0.34, out=0.14, yaw=14, pitch=-20, lift=0.1))
    punch(rig, "m1_2", cross_load, cross_strike, cross_follow, pivot, notes="rear straight")

    # m1_3 lead hook: the lead arm swings wide and whips across, the lead heel turning out.
    hook_load = merge(GUARD, {
        "Root": (-4, 16, 2, 0, -0.4, 0.06), "Waist": (-7, 18, -3), "Neck": (-3, -16, 0),
        "LeftShoulder": (74, 0, -80), "LeftElbow": (86, 0, 0),
    })
    hook_strike = merge(GUARD, {
        "Root": (-6, -30, -3, 0, -0.38, -0.3), "Waist": (-9, -44, 5), "Neck": (3, 28, 0),
        "LeftShoulder": (90, 0, 52), "LeftElbow": (82, 0, 0), "LeftWrist": (0, 0, 10),
        "RightShoulder": (58, 0, 22), "RightElbow": (128, 0, 0),
    })
    hook_follow = merge(hook_strike, {"Waist": (-8, -54, 5), "LeftShoulder": (84, 0, 72), "LeftElbow": (86, 0, 0)})
    lead_pivot = feet(left=foot(fwd=0.45, out=0.04, yaw=-32, pitch=-16, lift=0.08))
    punch(rig, "m1_3", hook_load, hook_strike, hook_follow, lead_pivot, follow_at=0.12, length=0.3, notes="lead hook")

    # m1_4 rear uppercut: sink deep and coil, then explode up through the fist, the rear knee driving high.
    upper_load = merge(GUARD, {
        "Root": (-18, -30, 2, 0, -0.9, 0.12), "Waist": (-18, -30, 4), "Neck": (20, 26, 0),
        "RightShoulder": (-36, 0, 22), "RightElbow": (118, 0, 0), "RightWrist": (-15, 0, 0),
    })
    upper_strike = merge(GUARD, {
        "Root": (8, 24, 0, 0, 0.22, -0.34), "Waist": (10, 34, -6), "Neck": (14, -10, 0),
        "RightShoulder": (140, 0, -18), "RightElbow": (48, 0, 0), "RightWrist": (0, 0, 0),
        "LeftShoulder": (-32, 0, -22), "LeftElbow": (38, 0, 0),
        # The rear leg leaves the IK for the knee drive:
        "RightHip": (64, -20, 6), "RightKnee": (-82, 0, 0), "RightAnkle": (-22, 0, 0),
    })
    toes = feet(left=foot(fwd=0.42, out=0.04, yaw=10, pitch=-30, lift=0.22))
    upper_follow = merge(upper_strike, {"Root": (10, 28, 0, 0, 0.25, -0.36), "Waist": (13, 38, -6), "RightShoulder": (148, 0, -12), "RightElbow": (40, 0, 0)})
    land = merge(GUARD, {"Root": (-10, -8, 0, 0, -0.62, 0.02), "Waist": (-12, 10, 0)})
    Clip(rig, M, "m1_4", "windup", PUNCH_WINDUP, notes="rear uppercut") \
        .key(0, pose=GUARD, feet=GUARD_FEET, legs_ik={"Right": 1}, ease="smooth") \
        .key(0.085, pose=upper_load, feet=GUARD_FEET, legs_ik={"Right": 1}, ease="whip") \
        .key(PUNCH_WINDUP, pose=upper_strike, feet=toes, legs_ik={"Right": 0}) \
        .build()
    Clip(rig, M, "m1_4", "release", 0.56, notes="rear uppercut") \
        .key(0, pose=upper_strike, feet=toes, legs_ik={"Right": 0}, ease="hold") \
        .key(0.06, pose=upper_strike, feet=toes, legs_ik={"Right": 0}, ease="snap") \
        .key(0.22, pose=upper_follow, feet=toes, legs_ik={"Right": 0}, ease="whip") \
        .key(0.38, pose=land, feet=GUARD_FEET, legs_ik={"Right": 1}, ease="overshoot") \
        .key(0.56, pose=GUARD, feet=GUARD_FEET, legs_ik={"Right": 1}) \
        .build()

    # hit: the head snaps back first, the body rocks back over planted feet, the arms fling loose.
    flinch = merge(GUARD, {
        "Root": (10, -18, 6, 0, -0.42, 0.38), "Waist": (16, -8, 6), "Neck": (24, 14, 0),
        "RightShoulder": (-22, 0, 36), "RightElbow": (34, 0, 0),
        "LeftShoulder": (-16, 0, -42), "LeftElbow": (28, 0, 0),
    })
    Clip(rig, M, "hit", "release", 0.32, follow={"Neck": (6, 0.35), "RightWrist": (9, 0.35), "LeftWrist": (9, 0.35)}, notes="flinch") \
        .key(0, pose=flinch, feet=GUARD_FEET, ease="hold") \
        .key(0.05, pose=flinch, feet=GUARD_FEET, ease="overshoot") \
        .key(0.32, pose=GUARD, feet=GUARD_FEET) \
        .build()

    # launched: thrown by the finisher. Arched back, arms flung, legs trailing (no IK in the air); then a
    # tuck, and the legs reach for the ground and land in a crouch.
    both_off, both_on = {"Right": 0, "Left": 0}, {"Right": 1, "Left": 1}
    launch = {
        "Root": (26, 0, 0, 0, 0.1, 0.25), "Waist": (18, 0, 0), "Neck": (22, 0, 0),
        "RightShoulder": (150, 0, 48), "RightElbow": (24, 0, 0), "LeftShoulder": (146, 0, -52), "LeftElbow": (30, 0, 0),
        "RightHip": (-24, 0, 10), "RightKnee": (-66, 0, 0), "RightAnkle": (22, 0, 0),
        "LeftHip": (18, 0, -8), "LeftKnee": (-44, 0, 0), "LeftAnkle": (12, 0, 0),
    }
    tumble = {
        "Root": (-32, 0, 8, 0, 0.1, 0), "Waist": (-28, 0, 4), "Neck": (-10, 0, 0),
        "RightShoulder": (72, 0, 30), "RightElbow": (92, 0, 0), "LeftShoulder": (66, 0, -26), "LeftElbow": (96, 0, 0),
        "RightHip": (72, 0, 8), "RightKnee": (-102, 0, 0), "RightAnkle": (0, 0, 0),
        "LeftHip": (58, 0, -8), "LeftKnee": (-96, 0, 0), "LeftAnkle": (0, 0, 0),
    }
    crouch = merge(GUARD, {"Root": (-12, -8, 0, 0, -0.78, 0.05), "Waist": (-14, 10, 0), "Neck": (8, 0, 0)})
    Clip(rig, M, "launched", "release", 0.82, follow={"Neck": (5, 0.3), "RightWrist": (8, 0.3), "LeftWrist": (8, 0.3)}, notes="thrown by the finisher") \
        .key(0, pose=launch, feet=GUARD_FEET, legs_ik=both_off, ease="hold") \
        .key(0.08, pose=launch, feet=GUARD_FEET, legs_ik=both_off, ease="smooth") \
        .key(0.44, pose=tumble, feet=GUARD_FEET, legs_ik=both_off, ease="whip") \
        .key(0.66, pose=crouch, feet=GUARD_FEET, legs_ik=both_on, ease="overshoot") \
        .key(0.82, pose=merge(GUARD, {"Root": (-6, -10, 0, 0, -0.5, 0.03)}), feet=GUARD_FEET, legs_ik=both_on) \
        .build()

    # clash: the M1 trade clash, looped for the whole clash. Wide low stance, alternating straight punches
    # at a blur, the hips and head rocking with each.
    wide = {"Right": foot(fwd=-0.62, out=0.22, yaw=-20), "Left": foot(fwd=0.5, out=0.12, yaw=8)}
    base = merge(GUARD, {"Root": (-12, 0, 0, 0, -0.52, 0)})
    right = merge(base, {"Root": (-13, 16, 0, 0, -0.5, -0.2), "Waist": (-15, 26, -3), "Neck": (-3, -18, 0),
                         "RightShoulder": (97, 0, -12), "RightElbow": (2, 0, 0), "LeftShoulder": (48, 0, -24), "LeftElbow": (128, 0, 0)})
    left = merge(base, {"Root": (-13, -16, 0, 0, -0.5, -0.2), "Waist": (-15, -26, 3), "Neck": (-3, 18, 0),
                        "LeftShoulder": (97, 0, 12), "LeftElbow": (2, 0, 0), "RightShoulder": (48, 0, 24), "RightElbow": (128, 0, 0)})
    Clip(rig, M, "clash", "release", 0.3, looped=True, notes="M1 clash exchange") \
        .key(0, pose=right, feet=wide, ease="smooth") \
        .key(0.05, pose=right, feet=wide, ease="whip") \
        .key(0.15, pose=left, feet=wide, ease="smooth") \
        .key(0.2, pose=left, feet=wide, ease="whip") \
        .key(0.3, pose=right, feet=wide) \
        .build()
