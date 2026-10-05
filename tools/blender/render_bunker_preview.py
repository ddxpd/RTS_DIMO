import math
import os

import bpy
from mathutils import Vector


PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUTPUT_IMAGE = os.path.join(PROJECT_ROOT, "build", "verification", "bunker_model_preview.png")


def look_at(camera, target):
    direction = Vector(target) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def make_area(name, location, energy, size, color):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    light = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(light)
    light.location = location
    look_at(light, (0.0, 0.0, 0.65))
    return light


def render_preview():
    bunker = bpy.data.objects.get("bunker")
    if bunker is None:
        raise RuntimeError("bunker root was not found in the source blend")

    bunker_objects = {bunker, *bunker.children_recursive}
    for obj in bpy.context.scene.objects:
        obj.hide_render = obj not in bunker_objects

    camera_data = bpy.data.cameras.new("BunkerPreviewCamera")
    camera = bpy.data.objects.new("BunkerPreviewCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (4.7, 5.9, 3.35)
    camera_data.lens = 54.0
    camera_data.sensor_width = 36.0
    look_at(camera, (0.0, 0.0, 0.65))
    bpy.context.scene.camera = camera

    make_area("BunkerKey", (4.0, 4.0, 6.0), 850.0, 4.0, (1.0, 0.88, 0.76))
    make_area("BunkerFill", (-4.0, 2.5, 3.2), 500.0, 5.0, (0.55, 0.70, 1.0))
    make_area("BunkerRim", (0.0, -4.0, 5.0), 720.0, 3.0, (0.45, 0.60, 1.0))

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 700
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world.color = (0.025, 0.03, 0.04)
    scene.render.filepath = OUTPUT_IMAGE
    bpy.ops.render.render(write_still=True)
    print("Rendered", OUTPUT_IMAGE)


if __name__ == "__main__":
    render_preview()
