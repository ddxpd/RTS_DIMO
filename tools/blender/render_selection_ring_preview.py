import os

import bpy
from mathutils import Vector


PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUTPUT_IMAGE = os.path.join(PROJECT_ROOT, "build", "verification", "selection_ring_preview.png")


def look_at(node, target):
    direction = Vector(target) - node.location
    node.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def material(name, color, metallic=0.0, roughness=0.6, emission=None, emission_strength=0.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1.0)
    nodes = mat.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    principled = nodes.new("ShaderNodeBsdfPrincipled")
    mat.node_tree.links.new(principled.outputs["BSDF"], output.inputs["Surface"])
    principled.inputs["Base Color"].default_value = (*color, 1.0)
    principled.inputs["Metallic"].default_value = metallic
    principled.inputs["Roughness"].default_value = roughness
    if emission is not None:
        emission_input = "Emission Color" if "Emission Color" in principled.inputs else "Emission"
        principled.inputs[emission_input].default_value = (*emission, 1.0)
        if "Emission Strength" in principled.inputs:
            principled.inputs["Emission Strength"].default_value = emission_strength
    return mat


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


def make_floor():
    bpy.ops.mesh.primitive_plane_add(size=18.0, location=(0.0, 0.0, -0.02))
    floor = bpy.context.object
    floor.name = "SelectionRingPreviewFloor"
    floor.data.materials.append(material("SelectionRingPreviewFloor", (0.035, 0.045, 0.05)))
    return floor


def make_ring(name, location, radius):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=radius * 0.94,
        minor_radius=radius * 0.055,
        major_segments=64,
        minor_segments=8,
        location=(location[0], 0.08, location[1]),
    )
    ring = bpy.context.object
    ring.name = name
    ring.data.materials.append(
        material(
            "SelectionRingGreen",
            (0.12, 1.0, 0.2),
            roughness=0.35,
            emission=(0.08, 1.0, 0.14),
            emission_strength=4.0,
        )
    )
    return ring


def set_render_only(roots, helpers):
    visible = set(helpers)
    for root in roots:
        visible.add(root)
        visible.update(root.children_recursive)
    for obj in bpy.context.scene.objects:
        obj.hide_render = obj not in visible


def render_preview():
    soldier = bpy.data.objects.get("soldier")
    building = bpy.data.objects.get("base") or bpy.data.objects.get("bunker")
    if soldier is None or building is None:
        raise RuntimeError("Soldier or building root is missing from the shared source")

    soldier.location = (-2.2, 0.0, 0.0)
    building.location = (2.3, 0.0, 0.0)
    soldier_ring = make_ring("SelectionRingSoldier", (-2.2, 0.0), 1.65)
    building_ring = make_ring("SelectionRingBuilding", (2.3, 0.0), 2.8)
    floor = make_floor()

    camera_data = bpy.data.cameras.new("SelectionRingPreviewCamera")
    camera = bpy.data.objects.new("SelectionRingPreviewCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    bpy.context.scene.camera = camera
    camera.location = (8.8, -12.0, 8.2)
    camera.data.lens = 58.0
    look_at(camera, (0.0, 0.0, 1.2))

    lights = [
        make_area("SelectionRingKey", (3.0, -5.0, 8.0), 1050.0, 4.0, (1.0, 0.88, 0.74), (0.0, 0.0, 1.0)),
        make_area("SelectionRingFill", (-5.0, -2.0, 4.0), 620.0, 5.0, (0.50, 0.70, 1.0), (0.0, 0.0, 1.0)),
        make_area("SelectionRingRim", (0.0, 4.0, 7.0), 900.0, 3.0, (0.35, 0.55, 1.0), (0.0, 0.0, 1.4)),
    ]
    set_render_only([soldier, building, soldier_ring, building_ring], [camera, floor, *lights])

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 700
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world.color = (0.018, 0.023, 0.03)
    scene.render.filepath = OUTPUT_IMAGE
    bpy.ops.render.render(write_still=True)
    print("Rendered", OUTPUT_IMAGE)


if __name__ == "__main__":
    render_preview()
