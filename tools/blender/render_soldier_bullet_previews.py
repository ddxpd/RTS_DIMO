import os

import bpy
from mathutils import Vector


PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SOLDIER_PREVIEW = os.path.join(PROJECT_ROOT, "build", "verification", "soldier_model_preview.png")
BULLET_PREVIEW = os.path.join(PROJECT_ROOT, "build", "verification", "bullet_model_preview.png")


def look_at(node, target):
    direction = Vector(target) - node.location
    node.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def make_area(name, location, energy, size, color, target):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    light = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(light)
    light.location = location
    look_at(light, target)
    return light


def make_camera():
    data = bpy.data.cameras.new("SoldierBulletPreviewCamera")
    camera = bpy.data.objects.new("SoldierBulletPreviewCamera", data)
    bpy.context.collection.objects.link(camera)
    bpy.context.scene.camera = camera
    return camera


def preview_material(name, color, roughness=0.7):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    principled = mat.node_tree.nodes.get("Principled BSDF")
    if principled is not None:
        principled.inputs["Base Color"].default_value = (*color, 1.0)
        principled.inputs["Roughness"].default_value = roughness
    return mat


def make_floor():
    bpy.ops.mesh.primitive_plane_add(size=20.0, location=(0.0, 0.0, -0.015))
    floor = bpy.context.object
    floor.name = "PreviewFloor"
    floor.data.materials.append(preview_material("PreviewFloorMaterial", (0.055, 0.06, 0.07)))
    return floor


def set_render_only(root, helpers):
    visible = {root, *root.children_recursive, *helpers}
    for obj in bpy.context.scene.objects:
        obj.hide_render = obj not in visible


def configure_scene(output_path, width, height):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world.color = (0.022, 0.026, 0.034)
    scene.render.filepath = output_path


def render_previews():
    soldier = bpy.data.objects.get("soldier")
    bullet = bpy.data.objects.get("bullet")
    if soldier is None or bullet is None:
        raise RuntimeError("Soldier or bullet root is missing from the shared source")

    camera = make_camera()
    floor = make_floor()
    lights = [
        make_area("PreviewKey", (4.0, -4.0, 6.0), 900.0, 4.0, (1.0, 0.86, 0.72), (0.0, 0.0, 1.2)),
        make_area("PreviewFill", (-4.0, -2.5, 3.2), 520.0, 5.0, (0.50, 0.68, 1.0), (0.0, 0.0, 1.2)),
        make_area("PreviewRim", (0.0, 4.0, 5.0), 760.0, 3.0, (0.38, 0.55, 1.0), (0.0, 0.0, 1.4)),
    ]
    helpers = [camera, floor, *lights]

    set_render_only(soldier, helpers)
    camera.location = (4.3, -6.2, 3.2)
    camera.data.lens = 62.0
    look_at(camera, (0.0, 0.0, 1.28))
    configure_scene(SOLDIER_PREVIEW, 900, 1000)
    bpy.ops.render.render(write_still=True)

    set_render_only(bullet, helpers)
    floor.hide_render = True
    bullet.rotation_euler = (0.0, 0.0, -0.90)
    bullet.scale = (3.8, 3.8, 3.8)
    camera.location = (2.4, -4.0, 1.8)
    camera.data.lens = 70.0
    look_at(camera, (0.0, 0.0, 0.0))
    configure_scene(BULLET_PREVIEW, 900, 500)
    bpy.ops.render.render(write_still=True)

    print("Rendered", SOLDIER_PREVIEW)
    print("Rendered", BULLET_PREVIEW)


if __name__ == "__main__":
    render_previews()
