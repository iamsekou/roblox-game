"""Builds tools/blender/NAU_Fights.blend: the game's R15 rig plus every fight clip as an editable Blender action.

    blender --background --factory-startup --python tools/blender/build.py

Then export them into the game: see export.py. Rebuilding REPLACES the .blend: if you hand-edited clips in
Blender, export from your edited .blend instead of rebuilding (or copy the edits into clips_*.py first).
Open the .blend in Blender to see or edit a clip: pick its action on NAU_Rig in the Action Editor. The IK
goals are the FootTarget / HandTarget bones; IK on/off is the influence of the knee/elbow IK constraints.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402

import clips_gojo  # noqa: E402
import clips_goku  # noqa: E402
import clips_ichigo  # noqa: E402
import clips_krillin  # noqa: E402
import clips_l  # noqa: E402
import clips_luffy  # noqa: E402
import clips_melee  # noqa: E402
import clips_naruto  # noqa: E402
import clips_sasuke  # noqa: E402
import clips_vegeta  # noqa: E402
import clips_zoro  # noqa: E402
import nau_rig  # noqa: E402

CLIP_MODULES = (clips_melee, clips_goku, clips_luffy, clips_krillin, clips_vegeta, clips_zoro, clips_l,
                clips_naruto, clips_ichigo, clips_sasuke, clips_gojo)

bpy.ops.wm.read_factory_settings(use_empty=True)
rig = nau_rig.build(os.path.join(HERE, "rig_r15.json"))
for module in CLIP_MODULES:
    module.author(rig)
    print("[build] authored", module.__name__)
rig.armature.animation_data.action = None
out = os.path.join(HERE, "NAU_Fights.blend")
bpy.ops.wm.save_as_mainfile(filepath=out)
print("[build] saved", out, "with", sum(1 for a in bpy.data.actions if "nau_module" in a), "clips")
