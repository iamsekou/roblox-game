"""Checks the Blender pipeline's maths on a fresh rig (no files written except a test render):

    blender --background --factory-startup --python tools/blender/selftest.py

  1. At rest every joint exports as zero (the IK poles are tuned so the legs don't twist).
  2. Keyed angles come back out exactly as the game will read them (Blender 'ZYX' == Roblox CFrame.Angles).
  3. Dropping the pelvis keeps the feet planted (the IK bends the knees instead).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402

import export  # noqa: E402
import nau_anim  # noqa: E402
import nau_rig  # noqa: E402

failures = []


def check(ok, what):
    print(("PASS " if ok else "FAIL ") + what)
    if not ok:
        failures.append(what)


bpy.ops.wm.read_factory_settings(use_empty=True)
rig = nau_rig.build(os.path.join(HERE, "rig_r15.json"))

# 1. Rest.
rest = nau_anim.Clip(rig, "Test", "rest", "release", 0.1).key(0, pose={"Waist": (0, 0, 0)}, feet={"Right": nau_anim.foot(), "Left": nau_anim.foot()}).key(0.1, pose={"Waist": (0, 0, 0)})
baked = export._bake(rig, rest.build())
worst = max(abs(v) for _, pose in baked["frames"] for vals in pose.values() for v in vals)
check(worst < 0.05, f"rest pose exports as zero (worst {worst:.4f})")

# 2. Keyed angles round-trip.
POSE = {"RightShoulder": (100, 20, -30), "Waist": (-10, 25, 5), "Neck": (12, -30, 4), "LeftElbow": (95, 0, 0), "Root": (5, -20, 3, 0.1, -0.5, -0.3)}
probe = nau_anim.Clip(rig, "Test", "probe", "release", 0.1, follow={}).key(0, pose=POSE).key(0.1, pose=POSE)
baked = export._bake(rig, probe.build())
last = baked["frames"][-1][1]
for joint, want in POSE.items():
    got = last[joint]
    err = max(abs(a - b) for a, b in zip(got, want))
    check(err < 0.01, f"{joint} keyed {want} exports {[round(v, 3) for v in got]}")

# 3. Planted feet under a crouch.
arm = rig.armature
bpy.context.scene.frame_set(0)
nau_anim._reset_pose(arm)
arm.animation_data.action = None
bpy.context.view_layer.update()
rest_ankle = {s: (arm.matrix_world @ arm.pose.bones[s + "Ankle"].head).copy() for s in ("Right", "Left")}
crouch = nau_anim.Clip(rig, "Test", "crouch", "release", 0.1).key(0, pose={"Root": (-10, 15, 0, 0, -0.6, -0.2)}).key(0.1, pose={"Root": (-10, 15, 0, 0, -0.6, -0.2)})
export._assign(arm, crouch.build())
export._set_time(bpy.context.scene, 0.05)
for s in ("Right", "Left"):
    moved = (arm.matrix_world @ arm.pose.bones[s + "Ankle"].head - rest_ankle[s]).length
    check(moved < 0.01, f"{s} ankle stays planted under a 0.6 stud crouch (moved {moved:.4f})")
knee = arm.convert_space(pose_bone=arm.pose.bones["RightKnee"], matrix=arm.pose.bones["RightKnee"].matrix, from_space="POSE", to_space="LOCAL")
bend = rig.basis_to_transform("RightKnee", knee)
check(nau_rig.Rig.matrix_angles(bend)[0] < -20, f"the knee bends on -X (knee X {nau_rig.Rig.matrix_angles(bend)[0]:.1f})")

export.RENDERS_DIR = os.path.join(HERE, "renders")
export._render_sheet(rig, bpy.data.actions["Test_probe_release"], {"length": 0.1})
print("RESULT", "all passed" if not failures else f"{len(failures)} failed")
