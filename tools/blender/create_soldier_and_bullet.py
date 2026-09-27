import math
import os

import bpy


PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SOURCE_BLEND = os.path.join(PROJECT_ROOT, "assets", "models", "source", "ironfront_models.blend")
SOLDIER_GLB = os.path.join(PROJECT_ROOT, "assets", "models", "soldier.glb")
BULLET_GLB = os.path.join(PROJECT_ROOT, "assets", "models", "bullet.glb")


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
        modifier = obj.modifiers.new("CleanArmorEdges", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    assign(obj, mat)
    return parent(obj, node, location, rotation)


def cylinder(name, radius, depth, location, mat, node=None, vertices=20, rotation=(0.0, 0.0, 0.0)):
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


def cone(name, radius_bottom, radius_top, depth, location, mat, node=None, vertices=20, rotation=(0.0, 0.0, 0.0)):
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
    return parent(obj, node, location, rotation)


def sphere(name, dimensions, location, mat, node=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, location=(0.0, 0.0, 0.0))
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign(obj, mat)
    return parent(obj, node, location)


def join_meshes(name, objects):
    if not objects:
        raise RuntimeError("Cannot join an empty mesh list: " + name)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.object
    joined.name = name
    return joined


def remove_hierarchy(root_name):
    root = bpy.data.objects.get(root_name)
    if root is None:
        return
    descendants = list(root.children_recursive)
    for obj in reversed(descendants):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.objects.remove(root, do_unlink=True)


def build_soldier():
    remove_hierarchy("soldier")

    steel = material("Soldier_IF_Steel", (0.24, 0.26, 0.28), metallic=0.64, roughness=0.46)
    steel_light = material("Soldier_IF_Steel_Light", (0.47, 0.49, 0.50), metallic=0.58, roughness=0.42)
    dark = material("Soldier_IF_Dark", (0.035, 0.045, 0.055), metallic=0.32, roughness=0.58)
    faction = material(
        "Soldier_FactionGlow",
        (0.08, 0.34, 0.92),
        metallic=0.05,
        roughness=0.24,
        emission=(0.03, 0.28, 1.0),
        emission_strength=3.5,
    )
    visor = material(
        "Soldier_VisorGlow",
        (0.04, 0.30, 0.75),
        metallic=0.08,
        roughness=0.18,
        emission=(0.02, 0.30, 1.0),
        emission_strength=4.0,
    )

    soldier = empty("soldier")
    soldier["asset_role"] = "infantry_soldier"
    soldier["reference"] = "exec-c83c3377-171b-4b9e-b39e-5a03cb723d5d.png"
    soldier["authoring_axes"] = "Blender Z-up; front is -Y and exports to Godot +Z"

    armor_core = empty("ArmorCore", node=soldier)
    join_meshes("ArmorCoreMesh", [
        cube("TorsoShell", (0.82, 0.48, 0.66), (0.0, 0.0, 1.82), steel, armor_core, bevel=0.09),
        cube("ChestPlate", (0.66, 0.12, 0.42), (0.0, -0.27, 1.86), steel_light, armor_core, bevel=0.06),
        cube("Abdomen", (0.54, 0.38, 0.22), (0.0, -0.01, 1.39), dark, armor_core, bevel=0.05),
        cube("Collar", (0.56, 0.42, 0.14), (0.0, 0.0, 2.18), dark, armor_core, bevel=0.04),
    ])

    helmet = empty("Helmet", (0.0, -0.02, 2.48), soldier)
    join_meshes("HelmetMesh", [
        sphere("HelmetShell", (0.56, 0.48, 0.50), (0.0, 0.0, 0.0), steel, helmet),
        cube("FacePlate", (0.44, 0.10, 0.26), (0.0, -0.24, -0.05), dark, helmet, bevel=0.04),
        cube("Visor", (0.34, 0.035, 0.075), (0.0, -0.302, 0.055), visor, helmet, bevel=0.014),
        cube("HelmetCrown", (0.26, 0.34, 0.11), (0.0, 0.0, 0.27), steel_light, helmet, bevel=0.04),
    ])

    for side, x in (("L", -0.53), ("R", 0.53)):
        shoulder = empty("Shoulder_" + side, (x, -0.01, 2.03), soldier)
        join_meshes("Shoulder_" + side + "_Mesh", [
            cube("ShoulderArmor_" + side, (0.34, 0.48, 0.26), (0.0, 0.0, 0.0), steel_light, shoulder, bevel=0.075),
            cube("FactionMark_" + side, (0.19, 0.028, 0.065), (0.0, -0.255, 0.015), faction, shoulder, bevel=0.015),
        ])

    for side, x, inward in (("L", -0.55, 1.0), ("R", 0.55, -1.0)):
        arm = empty("Arm_" + side, (x, -0.04, 1.90), soldier)
        join_meshes("Arm_" + side + "_Mesh", [
            cube("UpperArm_" + side, (0.25, 0.30, 0.34), (0.0, 0.0, -0.18), dark, arm, bevel=0.06),
            cube("Forearm_" + side, (0.27, 0.34, 0.34), (0.10 * inward, -0.12, -0.46), steel_light, arm, bevel=0.065),
            sphere("Glove_" + side, (0.23, 0.25, 0.22), (0.17 * inward, -0.24, -0.66), dark, arm),
        ])

    hips = empty("Hips", (0.0, 0.0, 1.24), soldier)
    join_meshes("HipsMesh", [
        cube("Pelvis", (0.62, 0.42, 0.27), (0.0, 0.0, 0.0), dark, hips, bevel=0.07),
        cube("Belt", (0.72, 0.46, 0.12), (0.0, 0.0, 0.15), steel, hips, bevel=0.04),
    ])

    for side, x in (("L", -0.23), ("R", 0.23)):
        leg = empty("Leg_" + side, (x, 0.0, 1.16), soldier)
        join_meshes("Leg_" + side + "_Mesh", [
            cube("Thigh_" + side, (0.30, 0.37, 0.46), (0.0, 0.0, -0.28), steel_light, leg, bevel=0.07),
            cube("Knee_" + side, (0.32, 0.40, 0.18), (0.0, -0.035, -0.56), dark, leg, bevel=0.05),
            cube("Shin_" + side, (0.31, 0.40, 0.46), (0.0, 0.0, -0.82), steel_light, leg, bevel=0.07),
            cube("Boot_" + side, (0.35, 0.56, 0.22), (0.0, -0.09, -1.07), dark, leg, bevel=0.065),
        ])

    weapon = empty("Weapon", (0.10, -0.48, 1.56), soldier)
    join_meshes("WeaponMesh", [
        cube("WeaponReceiver", (0.25, 0.68, 0.22), (0.0, -0.03, 0.0), steel, weapon, bevel=0.055),
        cube("WeaponStock", (0.20, 0.30, 0.18), (0.0, 0.42, 0.02), dark, weapon, bevel=0.045),
        cylinder("WeaponBarrel", 0.065, 0.46, (0.0, -0.58, 0.0), steel_light, weapon, vertices=16, rotation=(math.radians(90.0), 0.0, 0.0)),
        cube("WeaponGrip", (0.14, 0.18, 0.28), (0.0, 0.10, -0.19), dark, weapon, bevel=0.035, rotation=(math.radians(-12.0), 0.0, 0.0)),
    ])
    empty("Muzzle", (0.10, -1.08, 1.56), soldier)

    return soldier


def build_bullet():
    remove_hierarchy("bullet")

    core = material(
        "Bullet_EnergyCore",
        (0.72, 0.90, 1.0),
        metallic=0.0,
        roughness=0.12,
        emission=(0.62, 0.88, 1.0),
        emission_strength=8.0,
    )
    shell = material(
        "Bullet_EnergyShell",
        (0.04, 0.24, 0.80),
        metallic=0.12,
        roughness=0.22,
        emission=(0.02, 0.18, 1.0),
        emission_strength=5.0,
    )
    trail = material(
        "Bullet_EnergyTrail",
        (0.04, 0.16, 0.55),
        metallic=0.0,
        roughness=0.30,
        emission=(0.01, 0.10, 0.78),
        emission_strength=3.5,
    )

    bullet = empty("bullet")
    bullet["asset_role"] = "energy_projectile"
    bullet["authoring_axes"] = "Blender Z-up; travel direction is -Y and exports to Godot +Z"

    join_meshes("EnergyCore", [
        cylinder("EnergyCoreBody", 0.065, 0.42, (0.0, -0.02, 0.0), core, bullet, vertices=16, rotation=(math.radians(90.0), 0.0, 0.0)),
        sphere("EnergyCoreNose", (0.14, 0.16, 0.14), (0.0, -0.25, 0.0), core, bullet),
    ])
    cylinder("EnergyShell", 0.105, 0.28, (0.0, 0.08, 0.0), shell, bullet, vertices=12, rotation=(math.radians(90.0), 0.0, 0.0))
    cone("EnergyTrail", 0.13, 0.018, 0.48, (0.0, 0.40, 0.0), trail, bullet, vertices=16, rotation=(math.radians(90.0), 0.0, 0.0))
    return bullet


def ensure_source_blend():
    expected = os.path.normcase(os.path.abspath(SOURCE_BLEND))
    current = os.path.normcase(os.path.abspath(bpy.data.filepath))
    if current != expected:
        raise RuntimeError(
            "Open the shared source explicitly with -BlendFile assets/models/source/ironfront_models.blend"
        )


def export_root(root_name, output_path):
    root = bpy.data.objects.get(root_name)
    if root is None:
        raise RuntimeError("Missing export root: " + root_name)
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for obj in root.children_recursive:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_animations=False,
        export_materials="EXPORT",
    )


def save_and_export():
    bpy.ops.wm.save_as_mainfile(filepath=SOURCE_BLEND)
    export_root("soldier", SOLDIER_GLB)
    export_root("bullet", BULLET_GLB)


if __name__ == "__main__":
    ensure_source_blend()
    build_soldier()
    build_bullet()
    save_and_export()
    print("Created", SOLDIER_GLB)
    print("Created", BULLET_GLB)
