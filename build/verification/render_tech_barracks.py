import bpy
import math
from pathlib import Path
from mathutils import Vector

root = bpy.data.objects["barracks"]
objects = list(root.children) + [root]

def top_parent(obj):
    while obj.parent is not None:
        obj = obj.parent
    return obj

for obj in bpy.data.objects:
    is_family = top_parent(obj) == root
    obj.hide_render = not is_family
    obj.hide_viewport = not is_family
    obj.hide_set(not is_family)

points = []
for obj in objects:
    if obj.type == "MESH":
        for vertex in obj.data.vertices:
            points.append(obj.matrix_world @ vertex.co)
min_v = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
max_v = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
center = (min_v + max_v) / 2
size = (max_v - min_v).length
direction = Vector((0.78, -0.58, 0.24)).normalized()
distance = size * 1.25
camera_data = bpy.data.cameras.new("TechBarracksCamera")
camera = bpy.data.objects.new("TechBarracksCamera", camera_data)
bpy.context.collection.objects.link(camera)
camera.location = center + direction * distance
look = (center - camera.location).normalized()
camera.rotation_euler = look.to_track_quat('-Z', 'Y').to_euler()
camera_data.lens = 55
bpy.context.scene.camera = camera

sun_data = bpy.data.lights.new("TechBarracksSun", type="SUN")
sun_data.energy = 2.6
sun_data.angle = math.radians(5)
sun = bpy.data.objects.new("TechBarracksSun", sun_data)
sun.location = center + Vector((6, -8, 10))
sun.rotation_euler = (math.radians(45), math.radians(12), math.radians(30))
bpy.context.collection.objects.link(sun)

fill_data = bpy.data.lights.new("TechBarracksFill", type="AREA")
fill_data.energy = 900
fill_data.size = 10
fill = bpy.data.objects.new("TechBarracksFill", fill_data)
fill.location = center + Vector((-7, 6, 5))
fill.rotation_euler = (math.radians(55), math.radians(-25), math.radians(215))
bpy.context.collection.objects.link(fill)

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 80
scene.cycles.transparent_max_bounces = 12
scene.render.resolution_x = 1800
scene.render.resolution_y = 1200
scene.render.film_transparent = True
scene.render.image_settings.file_format = "PNG"
project_root = Path(bpy.data.filepath).parents[3]
scene.render.filepath = str(project_root / "tools" / "effect-gallery" / "generated" / "barracks_tech_base.png")
bpy.ops.render.render(write_still=True)
print("TECH_BARRACKS_RENDER", scene.render.filepath, "bounds", tuple(round(v, 3) for v in min_v), tuple(round(v, 3) for v in max_v))
