"""The game's R15 rig in Blender (owner, 2026-09-28: "implement blender").

Built from rig_r15.json (captured in Studio from the player avatar). Everything is in Roblox coordinates
(x right, y up, z back; a fighter faces -z); the armature object is turned 90 degrees about X only so it
stands up in Blender's viewport, which changes nothing in the bone maths.

Bones:
  * one deform bone per R15 joint, named like the joint (Root, Waist, Neck, RightShoulder, ...), head at the
    joint, pointing along the limb so IK works naturally;
  * FootTarget.R/L: IK goals at the ankles (no parent: planted in the world), and KneePole.R/L under them;
  * HandTarget.R/L and ElbowPole.R/L: optional IK goals for the hands (IK influence 0 unless a clip keys it).

Roblox joint frames on this rig are axis-aligned at rest, so a joint's Transform is the bone's local pose
matrix conjugated by the bone's rest orientation Q:  Transform = Q @ basis @ Q^-1  (and back:
basis = Q^-1 @ Transform @ Q). Euler angles use Blender's 'ZYX' order, which equals Roblox's
CFrame.Angles(x, y, z) (checked 2026-09-28).
"""
import bpy
import json
import math
from mathutils import Euler, Matrix, Vector

# The part each joint moves, and the joint that moves each joint's parent part.
JOINT_PART = {
    "Root": "LowerTorso", "Waist": "UpperTorso", "Neck": "Head",
    "RightShoulder": "RightUpperArm", "RightElbow": "RightLowerArm", "RightWrist": "RightHand",
    "LeftShoulder": "LeftUpperArm", "LeftElbow": "LeftLowerArm", "LeftWrist": "LeftHand",
    "RightHip": "RightUpperLeg", "RightKnee": "RightLowerLeg", "RightAnkle": "RightFoot",
    "LeftHip": "LeftUpperLeg", "LeftKnee": "LeftLowerLeg", "LeftAnkle": "LeftFoot",
}
JOINT_PARENT = {
    "Root": None, "Waist": "Root", "Neck": "Waist",
    "RightShoulder": "Waist", "RightElbow": "RightShoulder", "RightWrist": "RightElbow",
    "LeftShoulder": "Waist", "LeftElbow": "LeftShoulder", "LeftWrist": "LeftElbow",
    "RightHip": "Root", "RightKnee": "RightHip", "RightAnkle": "RightKnee",
    "LeftHip": "Root", "LeftKnee": "LeftHip", "LeftAnkle": "LeftKnee",
}
JOINTS = list(JOINT_PART.keys())
LEG_JOINTS = {"Root", "RightHip", "RightKnee", "RightAnkle", "LeftHip", "LeftKnee", "LeftAnkle"}
SIDES = {"Right": "R", "Left": "L"}

# Body colours for renders (so limbs read clearly in the review sheets).
PART_COLOR = {
    "Head": (0.93, 0.78, 0.62, 1), "UpperTorso": (0.92, 0.92, 0.95, 1), "LowerTorso": (0.25, 0.27, 0.32, 1),
    "RightUpperArm": (0.85, 0.35, 0.30, 1), "RightLowerArm": (0.93, 0.50, 0.42, 1), "RightHand": (0.93, 0.78, 0.62, 1),
    "LeftUpperArm": (0.30, 0.50, 0.85, 1), "LeftLowerArm": (0.45, 0.62, 0.93, 1), "LeftHand": (0.93, 0.78, 0.62, 1),
    "RightUpperLeg": (0.55, 0.20, 0.18, 1), "RightLowerLeg": (0.65, 0.28, 0.25, 1), "RightFoot": (0.15, 0.15, 0.17, 1),
    "LeftUpperLeg": (0.18, 0.30, 0.55, 1), "LeftLowerLeg": (0.25, 0.38, 0.65, 1), "LeftFoot": (0.15, 0.15, 0.17, 1),
}

ARMATURE_NAME = "NAU_Rig"


def _cf_matrix(c):
    """A Roblox CFrame (12 GetComponents numbers) as a 4x4 matrix."""
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = c
    return Matrix(((r00, r01, r02, x), (r10, r11, r12, y), (r20, r21, r22, z), (0, 0, 0, 1)))


class Rig:
    """The armature plus the numbers needed to go between Blender poses and Roblox Transforms."""

    def __init__(self, armature, data):
        self.armature = armature
        self.data = data
        self.joint_pos = {name: Vector(j["frame0"][:3]) for name, j in data["joints"].items()}
        self.ground_y = min(_cf_matrix(p["cframe"]).translation.y - p["size"][1] / 2 for n, p in data["parts"].items() if n.endswith("Foot"))
        bones = armature.data.bones
        self.q = {}  # rest orientation of every bone (armature space), 4x4
        for bone in bones:
            m = bone.matrix_local.to_3x3().to_4x4()
            self.q[bone.name] = m

    # Conversions ---------------------------------------------------------------------------------

    def transform_to_basis(self, bone_name, matrix):
        """A Roblox-space local transform (joint frame) -> the bone's pose basis."""
        q = self.q[bone_name]
        return q.inverted() @ matrix @ q

    def basis_to_transform(self, bone_name, basis):
        q = self.q[bone_name]
        return q @ basis @ q.inverted()

    @staticmethod
    def angles_matrix(values):
        """(rx, ry, rz[, px, py, pz]) in degrees/studs -> 4x4, the same composition as KeyframeClip.toCFrame."""
        rx, ry, rz = (math.radians(v) for v in values[:3])
        rotation = Euler((rx, ry, rz), "ZYX").to_matrix().to_4x4()
        if len(values) > 3:
            return Matrix.Translation(Vector(values[3:6])) @ rotation
        return rotation

    @staticmethod
    def matrix_angles(matrix, with_position=False):
        e = matrix.to_3x3().to_euler("ZYX")
        out = [math.degrees(e.x), math.degrees(e.y), math.degrees(e.z)]
        if with_position:
            p = matrix.translation
            out += [p.x, p.y, p.z]
        return out

    @classmethod
    def from_scene(cls, data):
        return cls(bpy.data.objects[ARMATURE_NAME], data)


def load_data(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _bone_tail(name, data, joint_pos):
    """Where each bone points: along the limb to the next joint (so IK and posing feel natural)."""
    parts = data["parts"]
    tails = {
        "Root": joint_pos["Waist"], "Waist": joint_pos["Neck"], "Neck": joint_pos["Neck"] + Vector((0, 1.1, 0)),
    }
    for side in ("Right", "Left"):
        tails[side + "Shoulder"] = joint_pos[side + "Elbow"]
        tails[side + "Elbow"] = joint_pos[side + "Wrist"]
        hand = _cf_matrix(parts[side + "Hand"]["cframe"]).translation
        tails[side + "Wrist"] = joint_pos[side + "Wrist"] + (hand - joint_pos[side + "Wrist"]) * 2
        tails[side + "Hip"] = joint_pos[side + "Knee"]
        tails[side + "Knee"] = joint_pos[side + "Ankle"]
        foot = parts[side + "Foot"]
        foot_m = _cf_matrix(foot["cframe"])
        toe = Vector((joint_pos[side + "Ankle"].x, foot_m.translation.y - foot["size"][1] * 0.3, foot_m.translation.z - foot["size"][2] / 2))
        tails[side + "Ankle"] = toe
    return tails[name]


def build(json_path):
    """Build the rig into the current (empty) scene. Returns a Rig."""
    data = load_data(json_path)
    joint_pos = {name: Vector(j["frame0"][:3]) for name, j in data["joints"].items()}

    arm_data = bpy.data.armatures.new(ARMATURE_NAME)
    arm = bpy.data.objects.new(ARMATURE_NAME, arm_data)
    bpy.context.scene.collection.objects.link(arm)
    arm.rotation_euler = (math.radians(90), 0, 0)  # stand up in Blender's Z-up viewport
    arm.show_in_front = True
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    for name in JOINTS:
        bone = eb.new(name)
        bone.head = joint_pos[name]
        bone.tail = _bone_tail(name, data, joint_pos)
        bone.roll = 0
    for name in JOINTS:
        parent = JOINT_PARENT[name]
        if parent:
            eb[name].parent = eb[parent]
            eb[name].use_connect = False

    # IK goals. A foot target copies its ankle bone exactly (same rest frame), so posing it is the same maths
    # as posing a joint; the knee pole hangs off it, so the knee follows where the foot points.
    for side, s in SIDES.items():
        ankle = eb[side + "Ankle"]
        target = eb.new("FootTarget." + s)
        target.head, target.tail, target.roll = ankle.head.copy(), ankle.tail.copy(), ankle.roll
        target.use_deform = False
        pole = eb.new("KneePole." + s)
        knee = joint_pos[side + "Knee"]
        pole.head = knee + Vector((0, 0, -2.5))
        pole.tail = pole.head + Vector((0, 0.3, 0))
        pole.parent = target
        pole.use_deform = False
        wrist = eb[side + "Wrist"]
        hand = eb.new("HandTarget." + s)
        hand.head, hand.tail, hand.roll = wrist.head.copy(), wrist.tail.copy(), wrist.roll
        hand.use_deform = False
        epole = eb.new("ElbowPole." + s)
        elbow = joint_pos[side + "Elbow"]
        epole.head = elbow + Vector((0.6 if side == "Right" else -0.6, 0, 2.0))
        epole.tail = epole.head + Vector((0, 0.3, 0))
        epole.parent = hand
        epole.use_deform = False
    bpy.ops.object.mode_set(mode="POSE")

    for side, s in SIDES.items():
        pb = arm.pose.bones
        ik = pb[side + "Knee"].constraints.new("IK")
        ik.name = "IK"
        ik.target, ik.subtarget = arm, "FootTarget." + s
        ik.pole_target, ik.pole_subtarget = arm, "KneePole." + s
        ik.chain_count = 2
        ik.use_tail = True  # the knee bone's tail is the ankle: it reaches the goal (the target bone's head)
        rot = pb[side + "Ankle"].constraints.new("COPY_ROTATION")
        rot.name = "FootRotation"
        rot.target, rot.subtarget = arm, "FootTarget." + s
        rot.target_space = rot.owner_space = "WORLD"
        hik = pb[side + "Elbow"].constraints.new("IK")
        hik.name = "IK"
        hik.target, hik.subtarget = arm, "HandTarget." + s
        hik.pole_target, hik.pole_subtarget = arm, "ElbowPole." + s
        hik.chain_count = 2
        hik.use_tail = True
        hik.influence = 0
        hrot = pb[side + "Wrist"].constraints.new("COPY_ROTATION")
        hrot.name = "HandRotation"
        hrot.target, hrot.subtarget = arm, "HandTarget." + s
        hrot.target_space = hrot.owner_space = "WORLD"
        hrot.influence = 0
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"

    rig = Rig(arm, data)
    _tune_poles(rig)
    _build_meshes(rig)
    _build_stage()
    return rig


def _tune_poles(rig):
    """Pick each IK pole angle that leaves the limb exactly at rest when the goal is at rest."""
    arm = rig.armature
    for side in ("Right", "Left"):
        for joint, name in ((side + "Knee", side + "Hip"), (side + "Elbow", side + "Shoulder")):
            ik = arm.pose.bones[joint].constraints["IK"]
            saved = ik.influence
            ik.influence = 1

            def rest_error(deg):
                ik.pole_angle = math.radians(deg)
                bpy.context.view_layer.update()
                err = 0
                for b in (name, joint):
                    pb = arm.pose.bones[b]
                    local = arm.convert_space(pose_bone=pb, matrix=pb.matrix, from_space="POSE", to_space="LOCAL")
                    err += (local.to_quaternion().rotation_difference(Matrix.Identity(3).to_quaternion())).angle
                return err

            # Coarse sweep in whole degrees, then refine to hundredths around the best.
            best = min(range(-180, 181), key=rest_error)
            step, centre = 0.5, float(best)
            while step > 0.005:
                candidates = [centre + i * step for i in range(-2, 3)]
                centre = min(candidates, key=rest_error)
                step /= 2
            best, best_err = centre, rest_error(centre)
            ik.pole_angle = math.radians(best)
            ik.influence = saved
            print(f"[nau_rig] {joint} pole angle {best:.3f} deg (rest error {math.degrees(best_err):.3f} deg)")
    bpy.context.view_layer.update()


def _build_meshes(rig):
    """A box per body part, rigidly following its bone (for renders only)."""
    arm = rig.armature
    parts = rig.data["parts"]
    part_bone = {part: joint for joint, part in JOINT_PART.items()}
    bpy.context.view_layer.update()
    for part, spec in parts.items():
        bone = part_bone.get(part)
        if not bone:
            continue
        sx, sy, sz = spec["size"]
        mesh = bpy.data.meshes.new(part)
        verts = [(x * sx / 2, y * sy / 2, z * sz / 2) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
        faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        mesh.from_pydata(verts, [], faces)
        obj = bpy.data.objects.new(part, mesh)
        bpy.context.scene.collection.objects.link(obj)
        obj.color = PART_COLOR.get(part, (0.8, 0.8, 0.8, 1))
        obj.parent = arm
        obj.parent_type = "BONE"
        obj.parent_bone = bone
        bpy.context.view_layer.update()
        obj.matrix_world = arm.matrix_world @ _cf_matrix(spec["cframe"])
        if part == "Head":
            # A dark visor on the face (-z), so the review renders show which way the fighter faces.
            _box(arm, bone, "Face", (sx * 0.8, sy * 0.22, 0.12), _cf_matrix(spec["cframe"]) @ Matrix.Translation((0, sy * 0.08, -sz / 2 - 0.04)), (0.08, 0.08, 0.1, 1))


def _box(arm, bone, name, size, matrix, color):
    sx, sy, sz = size
    mesh = bpy.data.meshes.new(name)
    verts = [(x * sx / 2, y * sy / 2, z * sz / 2) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    mesh.from_pydata(verts, [], faces)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.color = color
    obj.parent = arm
    obj.parent_type = "BONE"
    obj.parent_bone = bone
    bpy.context.view_layer.update()
    obj.matrix_world = arm.matrix_world @ matrix


def _build_stage():
    """Floor, light and cameras for the review renders (Roblox y = sole height -> Blender z)."""
    scene = bpy.context.scene
    scene.render.fps = 60
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "OBJECT"
    shading.show_cavity = True
    shading.show_shadows = True
    scene.display.shadow_focus = 0.2
    world = bpy.data.worlds.new("NAU_World")
    world.color = (0.16, 0.17, 0.2)
    scene.world = world
    floor_mesh = bpy.data.meshes.new("Floor")
    s = 12
    floor_mesh.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
    floor = bpy.data.objects.new("Floor", floor_mesh)
    scene.collection.objects.link(floor)
    floor.location = (0, 0, -3.0075)
    floor.color = (0.36, 0.38, 0.44, 1)
    # Side: from the fighter's right (they face right on screen). Front: three-quarters from their front right.
    # Both a little above, so the floor reads.
    for name, loc in (("CamSide", (9, 0, 1.4)), ("CamFront", (6, 8, 1.6))):
        cam_data = bpy.data.cameras.new(name)
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = 7.6
        cam = bpy.data.objects.new(name, cam_data)
        scene.collection.objects.link(cam)
        cam.location = loc
        direction = Vector((0, 0, -0.8)) - Vector(loc)
        cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = bpy.data.objects["CamSide"]
