"""Bakes every NAU action in NAU_Fights.blend into the game's clip data (animations/Clips/<Module>.luau), and
renders a review sheet per clip (tools/blender/renders, git-ignored).

    blender tools/blender/NAU_Fights.blend --background --python tools/blender/export.py -- [--no-renders] [--only NAME]

Each action is sampled at 60 frames a second plus its exact key times, with IK and constraints solved, then
converted bone by bone to the joint Transforms Roblox uses (nau_rig.Rig.basis_to_transform), as Euler angles
kept continuous frame to frame. Follow-through springs are then run over the joints the clip lists (head and
hands by default); a looped clip runs them over two cycles and keeps the second, so the loop stays seamless.

A clip exports the joints it moves: every bone it keys, the legs whenever it keys the Root, a foot or a leg's
IK, and an arm whenever it uses that hand's IK. Joints it never touches stay with the running animation.
"""
import bpy
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402
from mathutils import Matrix  # noqa: E402

import nau_anim  # noqa: E402
import nau_rig  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
CLIPS_DIR = os.path.join(REPO, "animations", "Clips")
RENDERS_DIR = os.path.join(HERE, "renders")
FPS = 60
SHEET_FRAMES = 7
CELL = (330, 340)


def _args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = argv[argv.index("--only") + 1] if "--only" in argv else None
    return ("--no-renders" not in argv), only


def _keyed_bones(action):
    bones, legs, arms = set(), False, set()
    for fc in nau_anim._fcurves(action):
        path = fc.data_path
        if not path.startswith('pose.bones["'):
            continue
        bone = path.split('"')[1]
        if ".constraints[" in path:
            if bone.endswith("Knee"):
                legs = True
            elif bone.endswith("Elbow"):
                arms.add(bone[:-5])
            continue
        if bone in nau_rig.JOINTS:
            bones.add(bone)
            if bone == "Root" or bone in nau_rig.LEG_JOINTS:
                legs = True
        elif bone.startswith("FootTarget") or bone.startswith("KneePole"):
            legs = True
        elif bone.startswith("HandTarget") or bone.startswith("ElbowPole"):
            arms.add("Right" if bone.endswith(".R") else "Left")
    if legs:
        bones |= nau_rig.LEG_JOINTS
    for side in arms:
        bones |= {side + "Shoulder", side + "Elbow", side + "Wrist"}
    return [j for j in nau_rig.JOINTS if j in bones]


def _assign(arm, action):
    nau_anim._reset_pose(arm)
    arm.animation_data_create()
    arm.animation_data.action = action
    slots = getattr(action, "slots", None)
    if slots and len(slots) > 0 and hasattr(arm.animation_data, "action_slot"):
        arm.animation_data.action_slot = slots[0]


def _set_time(scene, t):
    f = t * FPS
    whole = math.floor(f + 1e-9)
    scene.frame_set(whole, subframe=f - whole)


def _sample_times(action):
    length = float(action["nau_length"])
    times = {round(i / FPS, 5) for i in range(int(math.floor(length * FPS + 1e-6)) + 1)}
    for t in json.loads(action.get("nau_key_times", "[]")):
        if 0 <= t <= length:
            times.add(round(t, 5))
            # a "hold" key jumps at the next key: keep the frame just before that jump too
            times.add(round(max(0.0, t - 0.002), 5))
    times.add(round(length, 5))
    return sorted(times)


def _bake(rig, action):
    arm = rig.armature
    scene = bpy.context.scene
    _assign(arm, action)
    joints = _keyed_bones(action)
    looped = bool(action["nau_looped"])
    length = float(action["nau_length"])
    times = _sample_times(action)
    frames = []
    previous = {}
    reach = {}
    for side in ("Right", "Left"):
        bones = arm.data.bones
        reach[side] = (bones[side + "Hip"].head_local - bones[side + "Knee"].head_local).length + (bones[side + "Knee"].head_local - bones[side + "Ankle"].head_local).length
    overreach = {}
    for t in times:
        _set_time(scene, t)
        # A planted foot the leg can't reach gets a leg stretched flat behind the body: flag it.
        for side, s in (("Right", "R"), ("Left", "L")):
            ik = arm.pose.bones[side + "Knee"].constraints["IK"]
            if ik.influence > 0.5:
                gap = (arm.pose.bones["FootTarget." + s].head - arm.pose.bones[side + "Hip"].head).length / reach[side]
                if gap > 1.0:
                    overreach[side] = max(overreach.get(side, 0), gap)
        pose = {}
        for joint in joints:
            pb = arm.pose.bones[joint]
            local = arm.convert_space(pose_bone=pb, matrix=pb.matrix, from_space="POSE", to_space="LOCAL")
            transform = rig.basis_to_transform(joint, local)
            compat = previous.get(joint)
            e = transform.to_3x3().to_euler("ZYX", compat) if compat else transform.to_3x3().to_euler("ZYX")
            previous[joint] = e
            values = [math.degrees(e.x), math.degrees(e.y), math.degrees(e.z)]
            if joint == "Root":
                p = transform.translation
                values += [p.x, p.y, p.z]
            pose[joint] = values
        frames.append((t, pose))
    for side, gap in overreach.items():
        print(f"[export] WARN {action.name}: the {side.lower()} foot is out of reach ({gap:.0%} of the leg): move it in or lunge less")
    follow = json.loads(action.get("nau_follow", "{}"))
    _follow_through(frames, follow, looped, length)
    return {"length": length, "looped": looped, "frames": frames, "joints": joints}


def _follow_through(frames, follow, looped, length):
    """Overlapping action: each listed joint's angles chase the keyed angles through a damped spring."""
    for joint, (freq, damping) in follow.items():
        if not frames or joint not in frames[0][1]:
            continue
        omega = 2 * math.pi * freq
        passes = 2 if looped else 1
        state = [list(frames[0][1][joint][:3]), [0.0, 0.0, 0.0]]
        for p in range(passes):
            last_t = frames[0][0]
            for i, (t, pose) in enumerate(frames):
                dt = t - last_t if i > 0 else (frames[1][0] - frames[0][0] if (p > 0 and len(frames) > 1) else 0)
                last_t = t
                target = pose[joint][:3]
                x, v = state
                steps = max(1, int(math.ceil(dt / (1 / 240))))
                h = dt / steps if steps else 0
                for _ in range(steps):
                    for a in range(3):
                        acc = omega * omega * (target[a] - x[a]) - 2 * damping * omega * v[a]
                        v[a] += acc * h
                        x[a] += v[a] * h
                if p == passes - 1:
                    pose[joint] = x[:] + pose[joint][3:]


# Writing Luau --------------------------------------------------------------------------------------

def _num(v, places):
    s = f"{v:.{places}f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def _clip_luau(clip, indent):
    lines = [f"{{ length = {_num(clip['length'], 4)},{' looped = true,' if clip['looped'] else ''} dense = true, keys = {{"]
    for t, pose in clip["frames"]:
        parts = []
        for joint in clip["joints"]:
            v = pose[joint]
            nums = [_num(x, 2) for x in v[:3]] + [_num(x, 3) for x in v[3:]]
            parts.append(f"{joint} = {{ {', '.join(nums)} }}")
        lines.append(f"{indent}\t{{ t = {_num(t, 4)}, pose = {{ {', '.join(parts)} }} }},")
    lines.append(f"{indent}}} }}")
    return "\n".join(lines)


def _write_module(module, clips):
    path = os.path.join(CLIPS_DIR, module + ".luau")
    out = [
        f"-- {module}: keyframed fight clips. GENERATED by tools/blender/export.py from tools/blender/NAU_Fights.blend",
        "-- (authored in tools/blender/clips_*.py, owner 2026-09-28: \"implement blender\"). Don't edit by hand: change",
        "-- the clip in Blender (or its clips_*.py and rebuild the .blend) and re-export. Format: Modules/KeyframeClip",
        "-- (dense = one key per baked frame, linear between). Played by AbilityAnim straight away.",
        "return {",
    ]
    for slot in sorted(clips):
        out.append(f"\t{slot} = {{")
        for which in ("windup", "release"):
            if which in clips[slot]:
                out.append(f"\t\t{which} = " + _clip_luau(clips[slot][which], "\t\t") + ",")
        out.append("\t},")
    out.append("}")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")
    return path


# Review sheets -------------------------------------------------------------------------------------

def _render_sheet(rig, action, clip):
    scene = bpy.context.scene
    os.makedirs(RENDERS_DIR, exist_ok=True)
    scene.render.resolution_x, scene.render.resolution_y = CELL
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    _assign(rig.armature, action)
    length = clip["length"]
    times = [length * i / (SHEET_FRAMES - 1) for i in range(SHEET_FRAMES)]
    rows = []
    tmp = os.path.join(RENDERS_DIR, "_cell.png")
    for cam in ("CamSide", "CamFront"):
        scene.camera = bpy.data.objects[cam]
        row = []
        for t in times:
            _set_time(scene, t)
            scene.render.filepath = tmp
            bpy.ops.render.render(write_still=True)
            img = bpy.data.images.load(tmp, check_existing=False)
            px = np.array(img.pixels[:], dtype=np.float32).reshape(CELL[1], CELL[0], 4)
            bpy.data.images.remove(img)
            row.append(px)
        rows.append(np.concatenate(row, axis=1))
    sheet = np.concatenate(rows[::-1], axis=0)  # Blender images are bottom-up: side row ends on top
    h, w = sheet.shape[:2]
    out = bpy.data.images.new(action.name, w, h, alpha=True)
    out.pixels.foreach_set(sheet.ravel())
    out.filepath_raw = os.path.join(RENDERS_DIR, action.name + ".png")
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(out)
    if os.path.exists(tmp):
        os.remove(tmp)


def main():
    renders, only = _args()
    data = nau_rig.load_data(os.path.join(HERE, "rig_r15.json"))
    rig = nau_rig.Rig.from_scene(data)
    modules = {}
    for action in sorted(bpy.data.actions, key=lambda a: a.name):
        if "nau_module" not in action:
            continue
        clip = _bake(rig, action)
        modules.setdefault(action["nau_module"], {}).setdefault(action["nau_slot"], {})[action["nau_which"]] = clip
        print(f"[export] {action.name}: {len(clip['frames'])} frames, joints {len(clip['joints'])}")
        if renders and (only is None or only in action.name):
            _render_sheet(rig, action, clip)
    for module, clips in modules.items():
        print("[export] wrote", _write_module(module, clips))


if __name__ == "__main__":
    main()
