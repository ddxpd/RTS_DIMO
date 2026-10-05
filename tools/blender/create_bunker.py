import math
import os

import bpy
from mathutils import Vector


PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SOURCE_BLEND = os.path.join(PROJECT_ROOT, "assets", "models", "source", "ironfront_models.blend")
OUTPUT_GLB = os.path.join(PROJECT_ROOT, "assets", "models", "bunker.glb")


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
        if "Emission Color" in principled.inputs:
            principled.inputs["Emission Color"].default_value = (*emission, 1.0)
        elif "Emission" in principled.inputs:
            principled.inputs["Emission"].default_value = (*emission, 1.0)
        if "Emission Strength" in principled.inputs:
            principled.inputs["Emission Strength"].default_value = emission_strength
    return mat


def assign(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    return obj


def parent(obj, node, location, rotation=(0.0, 0.0, 0.0)):
    if node is not None:
        obj.parent = node
    obj.location = location
    obj.rotation_euler = rotation
    return obj


def empty(name, location=(0.0, 0.0, 0.0), node=None):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.empty_display_type = "PLAIN_AXES"
    return parent(obj, node, location)


def cube(name, dimensions, location, mat, node=None, bevel=0.04, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(location=(0.0, 0.0, 0.0))
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        modifier = obj.modifiers.new("SoftArmorEdges", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    assign(obj, mat)
    return parent(obj, node, location, rotation)


def cone(name, radius_bottom, radius_top, depth, location, mat, vertices=32, node=None):
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius_bottom,
        radius2=radius_top,
        depth=depth,
        location=(0.0, 0.0, 0.0),
    )
    obj = bpy.context.object
    obj.name = name
    assign(obj, mat)
    return parent(obj, node, location)


def cylinder(
    name,
    radius,
    depth,
    location,
    mat,
    vertices=32,
    node=None,
    rotation=(0.0, 0.0, 0.0),
):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=(0.0, 0.0, 0.0),
    )
    obj = bpy.context.object
    obj.name = name
    assign(obj, mat)
    return parent(obj, node, location, rotation)


def torus(name, major_radius, minor_radius, location, mat, node=None):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=40,
        minor_segments=10,
        location=(0.0, 0.0, 0.0),
    )
    obj = bpy.context.object
    obj.name = name
    assign(obj, mat)
    return parent(obj, node, location)


def remove_old_bunker():
    bunker = bpy.data.objects.get("bunker")
    if bunker is None:
        return
    descendants = list(bunker.children_recursive)
    for obj in reversed(descendants):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.objects.remove(bunker, do_unlink=True)


def build_bunker():
    remove_old_bunker()

    steel = material("Bunker_IF_Steel", (0.17, 0.19, 0.21), metallic=0.72, roughness=0.50)
    steel_light = material("Bunker_IF_Steel_Light", (0.34, 0.36, 0.37), metallic=0.65, roughness=0.44)
    dark = material("Bunker_IF_Steel_Dark", (0.055, 0.065, 0.075), metallic=0.80, roughness=0.40)
    faction_paint = material("Bunker_FactionPaint", (0.16, 0.40, 0.75), metallic=0.28, roughness=0.38)
    faction_glow = material(
        "Bunker_FactionGlow",
        (0.06, 0.30, 0.95),
        metallic=0.05,
        roughness=0.22,
        emission=(0.03, 0.28, 1.0),
        emission_strength=4.0,
    )
    muzzle = material(
        "Bunker_MuzzleGlow",
        (1.0, 0.20, 0.025),
        metallic=0.0,
        roughness=0.18,
        emission=(1.0, 0.10, 0.01),
        emission_strength=6.0,
    )

    bunker = empty("bunker")
    bunker["asset_role"] = "defensive_bunker"
    bunker["reference"] = "exec-bbaa3646-52d1-4d57-a8ec-67b7b1aa17cd.png"
    bunker["authoring_axes"] = "Blender Z-up; front is +Y and exports to Godot -Z"

    # "Body" is already used by the soldier asset in the shared Blender scene;
    # keep this root globally unique so the GLB path stays deterministic.
    body = empty("BunkerBody", node=bunker)
    cone("Foundation", 1.72, 1.66, 0.16, (0.0, 0.0, 0.08), dark, vertices=32, node=body)
    cone("MainBody", 1.62, 1.38, 0.82, (0.0, 0.0, 0.54), steel, vertices=32, node=body)
    cone("LowerArmorBand", 1.73, 1.62, 0.13, (0.0, 0.0, 0.16), dark, vertices=32, node=body)
    cone("UpperArmorBand", 1.43, 1.27, 0.16, (0.0, 0.0, 0.94), steel_light, vertices=32, node=body)
    cone("FactionBand", 1.51, 1.43, 0.08, (0.0, 0.0, 0.82), faction_paint, vertices=32, node=body)
    torus("BodyTrim", 1.30, 0.035, (0.0, 0.0, 1.04), steel_light, node=body)

    # Separate armor plates make the circular silhouette read at strategic zoom.
    for index in range(10):
        angle = math.tau * index / 10.0
        x = math.sin(angle) * 1.47
        y = math.cos(angle) * 1.47
        cube(
            "ArmorPanel_%02d" % index,
            (0.72, 0.16, 0.62),
            (x, y, 0.58),
            steel_light,
            body,
            bevel=0.045,
            rotation=(0.0, 0.0, -angle),
        )

    lights = empty("FactionLights", node=bunker)
    for side, x in (("L", -0.82), ("R", 0.82)):
        cube(
            "LightHousing_" + side,
            (0.50, 0.11, 0.22),
            (x, 1.34, 0.64),
            dark,
            lights,
            bevel=0.035,
        )
        cube(
            "FactionLight_" + side,
            (0.31, 0.035, 0.085),
            (x, 1.405, 0.64),
            faction_glow,
            lights,
            bevel=0.018,
        )

    turret = empty("Turret", (0.0, 0.0, 1.22), bunker)
    cylinder("TurretRing", 0.78, 0.18, (0.0, 0.0, 0.0), dark, vertices=40, node=turret)
    torus("TurretRingTrim", 0.68, 0.035, (0.0, 0.0, 0.12), steel_light, node=turret)
    cone("TurretMantlet", 0.66, 0.56, 0.24, (0.0, 0.0, 0.22), steel_light, vertices=8, node=turret)
    cube("TurretHousing", (1.02, 0.78, 0.52), (0.0, 0.06, 0.48), steel, turret, bevel=0.095)
    cube("TurretArmor_L", (0.18, 0.70, 0.43), (-0.56, 0.06, 0.47), steel_light, turret, bevel=0.035)
    cube("TurretArmor_R", (0.18, 0.70, 0.43), (0.56, 0.06, 0.47), steel_light, turret, bevel=0.035)
    cube("TurretTopArmor", (0.72, 0.48, 0.12), (0.0, 0.00, 0.79), steel_light, turret, bevel=0.035)

    barrel_rotation = (math.radians(-90.0), 0.0, 0.0)
    cylinder("BarrelCollar", 0.22, 0.20, (0.0, 0.49, 0.48), dark, vertices=24, node=turret, rotation=barrel_rotation)
    barrel = cylinder("Barrel", 0.115, 0.82, (0.0, 0.91, 0.48), steel_light, vertices=24, node=turret, rotation=barrel_rotation)
    barrel["weapon_role"] = "single_rotating_cannon"
    cylinder("MuzzleBrake", 0.18, 0.24, (0.0, 1.43, 0.48), dark, vertices=24, node=turret, rotation=barrel_rotation)
    for index in range(4):
        angle = math.tau * index / 4.0
        cube(
            "MuzzleSlot_%d" % index,
            (0.045, 0.07, 0.075),
            (math.cos(angle) * 0.12, 1.43, 0.48 + math.sin(angle) * 0.12),
            steel_light,
            turret,
            bevel=0.01,
        )
    cylinder("MuzzleFlash", 0.16, 0.20, (0.0, 1.66, 0.48), muzzle, vertices=16, node=turret, rotation=barrel_rotation)
    bpy.context.object.scale = Vector((0.04, 0.04, 0.04))

    bpy.ops.object.select_all(action="DESELECT")
    bunker.select_set(True)
    for obj in bunker.children_recursive:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = bunker


def ensure_source_blend():
    expected = os.path.normcase(os.path.abspath(SOURCE_BLEND))
    current = os.path.normcase(os.path.abspath(bpy.data.filepath))
    if current != expected:
        raise RuntimeError(
            "Open the shared source explicitly with -BlendFile assets/models/source/ironfront_models.blend"
        )


def save_and_export():
    bunker = bpy.data.objects.get("bunker")
    if bunker is None:
        raise RuntimeError("bunker root was not created")

    bpy.ops.wm.save_as_mainfile(filepath=SOURCE_BLEND)
    bpy.ops.object.select_all(action="DESELECT")
    bunker.select_set(True)
    for obj in bunker.children_recursive:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = bunker
    bpy.ops.export_scene.gltf(
        filepath=OUTPUT_GLB,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_animations=False,
        export_materials="EXPORT",
    )


if __name__ == "__main__":
    ensure_source_blend()
    build_bunker()
    save_and_export()
    print("Created", OUTPUT_GLB)
