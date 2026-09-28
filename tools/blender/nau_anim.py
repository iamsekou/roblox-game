"""Authoring fight clips on the Blender rig, in the game's own vocabulary (owner, 2026-09-28).

A Clip becomes one Blender action named <Module>_<slot>_<windup|release> (e.g. Melee_m1_4_release), with
its game metadata as custom properties, so export.py can bake it straight into animations/Clips.

Keys are written the way the game's clip data is written (Modules/KeyframeClip):
  pose   {joint: (rx, ry, rz)} in degrees (Root may add px, py, pz in studs). Same axes as the game.
  feet   {"Right"/"Left": foot(...)}: IK goals for the ankles (planted, so crouches bend the knees and the feet
         never slide). Set legs_ik={"Right": 0} to hand a leg to FK angles (kicks, knee drives, airborne).
  hands  {"Right"/"Left": hand(...)}: optional IK goals for the hands (hands_ik={"Right": 1} to use them).
  ease   how the motion leaves this key toward the next one:
           "bezier"    smooth (auto-clamped curves)          "linear"   constant speed
           "snap"      explodes out, settles into the next   "whip"     slow start, cracks into the next
           "overshoot" passes the next key, settles back     "elastic"  springy wobble into the next
           "smooth"    sine in/out                           "hold"     stays, then jumps (impact frame)
Follow-through (overlapping action) is added at export: springs on the head and hands by default.
"""
import bpy
import json
import math
from mathutils import Matrix, Vector

from nau_rig import JOINTS, LEG_JOINTS, SIDES, Rig

FPS = 60

EASES = {
    "bezier": ("BEZIER", None),
    "linear": ("LINEAR", None),
    "hold": ("CONSTANT", None),
    "snap": ("EXPO", "EASE_OUT"),
    "whip": ("EXPO", "EASE_IN"),
    "overshoot": ("BACK", "EASE_OUT"),
    "elastic": ("ELASTIC", "EASE_OUT"),
    "smooth": ("SINE", "EASE_IN_OUT"),
}

# Overlapping action added at export: joint -> (frequency Hz, damping ratio). The primary joints (torso,
# shoulders, elbows) are left exact: blows must land exactly on their keys.
DEFAULT_FOLLOW = {"Neck": (7.0, 0.5), "RightWrist": (10.0, 0.45), "LeftWrist": (10.0, 0.45)}


def foot(fwd=0.0, out=0.0, lift=0.0, pitch=0.0, yaw=0.0, roll=0.0):
    """An ankle goal relative to where it stands at rest: fwd (studs ahead), out (studs away from the body's
    centre line), lift (studs up), and the foot's rotation in degrees (pitch +X lifts the toes; yaw +Y turns it left)."""
    return {"fwd": fwd, "out": out, "lift": lift, "pitch": pitch, "yaw": yaw, "roll": roll}


def hand(x=0.0, y=0.0, z=0.0, rx=0.0, ry=0.0, rz=0.0):
    """A hand goal relative to the wrist at rest, in Roblox axes (x right, y up, z back), plus its rotation."""
    return {"x": x, "y": y, "z": z, "rx": rx, "ry": ry, "rz": rz}


def mirror(pose=None, feet=None):
    """The same pose on the other side (Right <-> Left, sideways rotations and shifts flipped)."""
    out_pose, out_feet = None, None
    if pose is not None:
        out_pose = {}
        for joint, v in pose.items():
            other = "Left" + joint[5:] if joint.startswith("Right") else ("Right" + joint[4:] if joint.startswith("Left") else joint)
            w = list(v)
            w[1], w[2] = -w[1], -w[2]
            if len(w) > 3:
                w[3] = -w[3]
            out_pose[other] = tuple(w)
    if feet is not None:
        out_feet = {}
        for side, f in feet.items():
            other = "Left" if side == "Right" else "Right"
            g = dict(f)
            g["yaw"], g["roll"] = -g["yaw"], -g["roll"]
            out_feet[other] = g
    return out_pose, out_feet


def merge(*poses):
    out = {}
    for p in poses:
        if p:
            out.update(p)
    return out


def _fcurves(action):
    """Every F-curve of an action (Blender 4.4+ keeps them in layers/strips/channelbags)."""
    curves = []
    legacy = getattr(action, "fcurves", None)
    if legacy is not None:
        try:
            return list(legacy)
        except TypeError:
            pass
    for layer in action.layers:
        for strip in layer.strips:
            for slot in action.slots:
                bag = strip.channelbag(slot)
                if bag:
                    curves.extend(bag.fcurves)
    return curves


class Clip:
    def __init__(self, rig: Rig, module, slot, which, length, looped=False, follow=None, notes=""):
        self.rig = rig
        self.name = f"{module}_{slot}_{which}"
        self.module, self.slot, self.which = module, slot, which
        self.length, self.looped = length, looped
        self.follow = DEFAULT_FOLLOW if follow is None else follow
        self.notes = notes
        self.keys = []

    def key(self, t, pose=None, feet=None, legs_ik=None, hands=None, hands_ik=None, ease="bezier"):
        if ease not in EASES:
            raise ValueError(f"{self.name}: unknown ease {ease}")
        self.keys.append({"t": t, "pose": pose or {}, "feet": feet or {}, "legs_ik": legs_ik or {},
                          "hands": hands or {}, "hands_ik": hands_ik or {}, "ease": ease})
        return self

    # Building -------------------------------------------------------------------------------------

    def build(self):
        rig, arm = self.rig, self.rig.armature
        _reset_pose(arm)
        action = bpy.data.actions.get(self.name)
        if action:
            bpy.data.actions.remove(action)
        action = bpy.data.actions.new(self.name)
        action.use_fake_user = True
        arm.animation_data_create()
        arm.animation_data.action = action
        action["nau_module"], action["nau_slot"], action["nau_which"] = self.module, self.slot, self.which
        action["nau_length"], action["nau_looped"] = float(self.length), bool(self.looped)
        action["nau_follow"] = json.dumps(self.follow)
        action["nau_key_times"] = json.dumps(sorted({round(k["t"], 5) for k in self.keys}))
        action["nau_notes"] = self.notes

        ease_at = {}
        last_q = {}
        for k in sorted(self.keys, key=lambda k: k["t"]):
            frame = k["t"] * FPS
            ease_at[round(frame, 3)] = k["ease"]
            for joint, values in k["pose"].items():
                if joint not in JOINTS:
                    raise ValueError(f"{self.name}: unknown joint {joint}")
                self._key_bone(joint, Rig.angles_matrix(values), frame, last_q, with_location=(joint == "Root"))
            for side, f in k["feet"].items():
                s = SIDES[side]
                sign = 1 if side == "Right" else -1
                m = Matrix.Translation(Vector((f["out"] * sign, f["lift"], -f["fwd"]))) @ Rig.angles_matrix((f["pitch"], f["yaw"], f["roll"]))
                self._key_bone("FootTarget." + s, m, frame, last_q, with_location=True, rest_of=side + "Ankle")
            for side, h in k["hands"].items():
                s = SIDES[side]
                m = Matrix.Translation(Vector((h["x"], h["y"], h["z"]))) @ Rig.angles_matrix((h["rx"], h["ry"], h["rz"]))
                self._key_bone("HandTarget." + s, m, frame, last_q, with_location=True, rest_of=side + "Wrist")
            for side, value in k["legs_ik"].items():
                con = arm.pose.bones[side + "Knee"].constraints["IK"]
                con.influence = value
                con.keyframe_insert("influence", frame=frame)
                rot = arm.pose.bones[side + "Ankle"].constraints["FootRotation"]
                rot.influence = value
                rot.keyframe_insert("influence", frame=frame)
            for side, value in k["hands_ik"].items():
                con = arm.pose.bones[side + "Elbow"].constraints["IK"]
                con.influence = value
                con.keyframe_insert("influence", frame=frame)
                rot = arm.pose.bones[side + "Wrist"].constraints["HandRotation"]
                rot.influence = value
                rot.keyframe_insert("influence", frame=frame)

        for fc in _fcurves(action):
            for kp in fc.keyframe_points:
                style = ease_at.get(round(kp.co.x, 3), "bezier")
                interpolation, easing = EASES[style]
                kp.interpolation = interpolation
                if easing:
                    kp.easing = easing
            fc.update()
        return action

    def _key_bone(self, bone, matrix, frame, last_q, with_location, rest_of=None):
        """Key a bone to a Roblox-space local transform (a target bone uses its joint's rest frame)."""
        arm = self.rig.armature
        pb = arm.pose.bones[bone]
        basis = self.rig.transform_to_basis(rest_of or bone, matrix)
        loc, rot, _ = basis.decompose()
        previous = last_q.get(bone)
        if previous is not None and previous.dot(rot) < 0:
            rot.negate()  # stay on the same side of the quaternion sphere: no spins between keys
        last_q[bone] = rot.copy()
        pb.rotation_quaternion = rot
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        if with_location:
            pb.location = loc
            pb.keyframe_insert("location", frame=frame)


def _reset_pose(arm):
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
        for con in pb.constraints:
            if con.name == "IK":
                con.influence = 1 if pb.name.endswith("Knee") else 0
            elif con.name == "FootRotation":
                con.influence = 1
            elif con.name == "HandRotation":
                con.influence = 0
