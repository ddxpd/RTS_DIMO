"""Rebuild only the command base in the shared source; runtime owns animation."""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
sys.dont_write_bytecode = True
from create_bunker import material, empty, cube, cone, ensure_source_blend, SOURCE_BLEND

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUTPUT_GLB = os.path.join(PROJECT_ROOT, "assets", "models", "base.glb")


def sector(name, start, end, profile, mat, node):
    """Closed annular section; angles start at the +Y entrance."""
    steps = max(1, math.ceil(abs(end - start) / 5.0))
    vertices = []
    for i in range(steps + 1):
        angle = math.radians(start + (end - start) * i / steps)
        vertices.extend((math.sin(angle) * r, math.cos(angle) * r, z) for r, z in profile)
    count = len(profile)
    faces = [tuple(range(count - 1, -1, -1)), tuple(steps * count + j for j in range(count))]
    for i in range(steps):
        for j in range(count):
            k = (j + 1) % count
            faces.append((i * count + j, i * count + k, (i + 1) * count + k, (i + 1) * count + j))
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = node
    obj.data.materials.append(mat)
    return obj


def slab(name, start, end, inner, outer, bottom, top, mat, node):
    return sector(name, start, end, [(inner, bottom), (outer, bottom), (outer, top), (inner, top)], mat, node)


def hex_body(name, lower, upper, bottom, top, mat, node):
    # Explicit orientation puts a flat face toward +Y, matching the lamp recess.
    vertices = [(r * math.cos(i * math.tau / 6), r * math.sin(i * math.tau / 6), z)
                for r, z in [(lower, bottom), (upper, top)] for i in range(6)]
    faces = [tuple(range(5, -1, -1)), tuple(range(6, 12))]
    faces += [(i, (i + 1) % 6, (i + 1) % 6 + 6, i + 6) for i in range(6)]
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = node
    mesh.materials.append(mat)
    return obj


def merge_static(node):
    # Preserve animated assemblies but batch their static geometry by material.
    meshes = [o for o in node.children if o.type == "MESH"]
    groups = {}
    for obj in meshes:
        groups.setdefault(obj.data.materials[0], []).append(obj)
    for mat, group in groups.items():
        bpy.ops.object.select_all(action="DESELECT")
        for obj in group:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = group[0]
        if len(group) > 1:
            bpy.ops.object.join()
        group[0].name = node.name + "_" + mat.name


def build_base():
    old = bpy.data.objects.get("base")
    if old:
        for obj in list(old.children_recursive)[::-1]:
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.objects.remove(old, do_unlink=True)

    steel = material("Base_Steel", (0.28, 0.30, 0.32), metallic=0.55, roughness=0.48)
    edge = material("Base_Edge", (0.39, 0.41, 0.43), metallic=0.55, roughness=0.42)
    dark = material("Base_Dark", (0.045, 0.055, 0.07), metallic=0.6, roughness=0.48)
    glass = material("Base_FactionWindowGlow", (0.025, 0.12, 0.3), metallic=0.5, roughness=0.22,
                     emission=(0.03, 0.25, 0.85), emission_strength=0.65)
    lamps = [material("Base_FactionTowerGlow_%d" % i, (0.04, 0.35, 0.85), roughness=0.25,
                      emission=(0.02, 0.28, 1.0), emission_strength=3.0) for i in range(6)]
    root = empty("base")
    root["reference"] = "assets/concept_art/基地-指挥中心-v2.png"
    root["footprint_cells"] = "5x5"
    root["authoring_axes"] = "Blender Z-up; front +Y exports to Godot -Z; scale 32"
    root["animation_contract"] = "BaseFoundation; BaseRing_0..3; BaseTower; BaseCrown; TowerLight_0..5 top-down"

    foundation = empty("BaseFoundation", node=root)
    cone("BaseFloor", 2.45, 2.45, 0.12, (0, 0, 0.06), dark, vertices=96, node=foundation)
    cone("BaseCourtyard", 1.65, 1.65, 0.035, (0, 0, 0.135), steel, vertices=64, node=foundation)
    # A single shallow ramp stays inside the 5x5 envelope.
    sector("BaseEntranceRamp", -13, 13, [(1.3, 0.0), (2.45, 0.0), (2.45, 0.025), (1.3, 0.16)], edge, foundation)
    for a in range(0, 360, 30):
        slab("CourtyardJoint", a - 0.18, a + 0.18, 0.87, 1.65, 0.153, 0.157, dark, foundation)
    merge_static(foundation)

    for index, (start, end) in enumerate([(16, 96), (99, 178), (182, 261), (264, 344)]):
        ring = empty("BaseRing_%d" % index, node=root)
        sector("RingLower", start, end, [(1.64, 0.12), (2.4, 0.12), (2.34, 0.45), (1.64, 0.45)], steel, ring)
        slab("WindowSill", start, end, 1.63, 2.35, 0.43, 0.48, dark, ring)
        slab("WindowHeader", start, end, 1.63, 2.29, 0.75, 0.80, dark, ring)
        sector("RingRoof", start, end, [(1.63, 0.79), (2.3, 0.79), (2.12, 1.12), (1.75, 1.12)], edge, ring)
        # Three observation bays per module, with opaque tinted panes facing both sides.
        bay = (end - start - 12) / 3
        for j in range(3):
            a = start + 6 + j * bay
            b = a + bay - 2
            slab("WindowOuter", a, b, 2.275, 2.29, 0.48, 0.75, glass, ring)
            slab("WindowInner", a, b, 1.638, 1.652, 0.48, 0.75, glass, ring)
            slab("WindowMullion", b, b + 2, 1.64, 2.30, 0.47, 0.80, dark, ring)
        for a, b in [(start, start + 6), (end - 6, end)]:
            slab("RingEndWall", a, b, 1.64, 2.32, 0.44, 0.81, steel, ring)
        # Broad piers, with an extra pier on the other side of the entrance.
        for angle in ([start, end] if index == 3 else [start]):
            sector("RingPier", angle - 2.7, angle + 2.7,
                   [(1.59, 0.12), (2.43, 0.12), (2.17, 1.19), (1.73, 1.19)], steel, ring)
        merge_static(ring)

    tower = empty("BaseTower", node=root)
    cone("TowerPlinth", 0.9, 0.86, 0.24, (0, 0, 0.27), steel, vertices=64, node=tower)
    hex_body("TowerBody", 0.76, 0.49, 0.39, 2.71, edge, tower)
    tilt = math.atan((0.76 - 0.49) * math.cos(math.pi / 6) / 2.32)
    def face_y(z):
        return (0.76 - (z - 0.39) / 2.32 * 0.27) * math.cos(math.pi / 6)
    cube("TowerLightRecess", (0.22, 0.035, 1.98), (0, face_y(1.50) + 0.012, 1.50), dark, tower,
         bevel=0.012, rotation=(tilt, 0, 0))
    merge_static(tower)
    for index in range(6):
        z = 2.30 - index * 0.32
        cube("TowerLight_%d" % index, (0.13, 0.017, 0.267), (0, face_y(z) + 0.037, z), lamps[index], tower,
             bevel=0.006, rotation=(tilt, 0, 0))

    crown = empty("BaseCrown", node=root)
    hex_body("CrownSill", 0.515, 0.515, 2.71, 2.79, dark, crown)
    hex_body("CommandWindows", 0.51, 0.49, 2.79, 3.08, glass, crown)
    for index in range(6):
        angle = math.tau * index / 6
        cube("CommandWindowFrame", (0.035, 0.035, 0.30),
             (0.5 * math.cos(angle), 0.5 * math.sin(angle), 2.935), dark, crown, bevel=0.003)
    hex_body("CommandRoof", 0.535, 0.40, 3.08, 3.37, edge, crown)
    merge_static(crown)

    bpy.context.view_layer.update()
    meshes = [o for o in root.children_recursive if o.type == "MESH"]
    points = [o.matrix_world @ Vector(p) for o in meshes for p in o.bound_box]
    extent = [max(p[i] for p in points) - min(p[i] for p in points) for i in range(3)]
    if extent[0] > 5 or extent[1] > 5:
        raise RuntimeError("Base exceeds 5x5 authoring envelope: " + str(extent))
    print("BASE_GEOMETRY", {"extent": extent, "meshes": len(meshes),
                            "triangles": sum(len(p.vertices) - 2 for o in meshes for p in o.data.polygons)})
    return root


def save_and_export(root):
    # Do not overwrite the user's existing .blend1 backup.
    saved_versions = bpy.context.preferences.filepaths.save_version
    bpy.context.preferences.filepaths.save_version = 0
    try:
        bpy.ops.wm.save_as_mainfile(filepath=SOURCE_BLEND)
    finally:
        bpy.context.preferences.filepaths.save_version = saved_versions
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for obj in root.children_recursive:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=OUTPUT_GLB, export_format="GLB", use_selection=True,
                            export_apply=True, export_animations=False, export_materials="EXPORT")


if __name__ == "__main__":
    try:
        ensure_source_blend()
        save_and_export(build_base())
        print("Created", OUTPUT_GLB)
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
