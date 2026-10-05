"""Render the real exported-model source, without saving preview scene changes."""
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(__file__))
sys.dont_write_bytecode = True
from create_bunker import material
from render_bunker_preview import look_at, make_area

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def render_preview():
    root = bpy.data.objects["base"]
    included = {root, *root.children_recursive}
    for obj in bpy.context.scene.objects:
        obj.hide_render = obj not in included
    # Show an actual scan instant, rather than all tower lamps at once.
    for i in range(6):
        mat = bpy.data.materials["Base_FactionTowerGlow_%d" % i]
        shader = next(node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
        shader.inputs["Emission Strength"].default_value = 3.0 if i == 2 else 0.0
        shader.inputs["Base Color"].default_value = (0.04, 0.35, 0.85, 1) if i == 2 else (0.01, 0.025, 0.05, 1)
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.01))
    floor = bpy.context.object
    floor.name = "BasePreviewGround"
    floor.data.materials.append(material("BasePreviewGroundMat", (0.23, 0.21, 0.20), roughness=0.85))
    camera_data = bpy.data.cameras.new("BasePreviewCamera")
    camera = bpy.data.objects.new("BasePreviewCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (-6, 9, 7)
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 7.4
    look_at(camera, (0, 0, 1.0))
    scene = bpy.context.scene
    scene.camera = camera
    make_area("BaseKey", (2, 4, 8), 1600, 6, (1, 0.93, 0.85))
    make_area("BaseFill", (-5, 3, 5), 900, 6, (0.7, 0.8, 1))
    make_area("BaseRim", (1, -5, 6), 1200, 4, (0.8, 0.85, 1))
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.world.color = (0.20, 0.20, 0.20)
    scene.render.filepath = os.path.join(PROJECT_ROOT, "assets", "concept_art", "基地-模型预览.png")
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    try:
        render_preview()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
