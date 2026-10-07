"""Rebuild the three RTS meshes from the immutable, textured animation baseline.

Run with tools/codex/run-blender.ps1 -Action script -Script res://tools/blender/optimize_barracks_rts.py.
The imported node names, pivots, UV layout and clips survive.
"""
import json
import hashlib
import math
import os
import struct
import shutil
import sys
import bpy
import bmesh
from array import array
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(__file__))
sys.dont_write_bytecode = True
from barracks_underbody import validate_motion
import barracks_weathering

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SOURCE = os.path.join(ROOT, 'assets/models/source/barracks_rts_baseline.glb')
OUT = os.path.join(ROOT, 'assets/concept_art/barracks_rts')


def triangles(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def target(name, level):
    if name == 'HullMesh':
        return [4150, 1750, 900][level]
    if name.startswith('LiftPod'):
        return [360, 190, 64][level]
    if name == 'RampMesh':
        return [360, 140, 36][level]
    if name.startswith('Foot'):
        return [96, 48, 24][level]
    if name.startswith('Door'):
        return [72, 36, 12][level]
    if name == 'PowerFanMesh':
        return [160, 64, 16][level]
    if name.startswith('Jet'):
        return [48, 32, 16][level]
    return [36, 20, 8][level]


def consolidate_materials(meshes):
    # All opaque non-faction body coatings already use the same baked atlas.
    # Their UVs carry the different metal/paint/rubber responses, not material IDs.
    body = bpy.data.materials['V2_Armor']
    body.name = 'RTS_Body'
    for obj in meshes:
        originals = list(obj.data.materials)
        replacements = []
        indices = []
        for mat in originals:
            keep = mat and any(key in mat.name for key in ['Faction', 'Flag', 'Thrust', 'AmberLight'])
            mat = mat if keep else body
            if mat not in replacements:
                replacements.append(mat)
            indices.append(replacements.index(mat))
        polygon_indices = [indices[p.material_index] for p in obj.data.polygons]
        obj.data.materials.clear()
        for mat in replacements:
            obj.data.materials.append(mat)
        for polygon, index in zip(obj.data.polygons, polygon_indices):
            polygon.material_index = index


def simplify_hull(obj, level):
    # Partition complete connected parts, never slice visible surfaces by height.
    # The low assembly includes the deck, engine wells and gear-bay bearings.
    geometry = bmesh.new()
    geometry.from_mesh(obj.data)
    bmesh.ops.remove_doubles(geometry, verts=list(geometry.verts), dist=.00001)
    remaining = set(geometry.verts)
    chassis = set()
    subpixel_details = set()
    while remaining:
        seed = remaining.pop()
        component = {seed}
        pending = [seed]
        while pending:
            for edge in pending.pop().link_edges:
                for vertex in edge.verts:
                    if vertex in remaining:
                        remaining.remove(vertex)
                        component.add(vertex)
                        pending.append(vertex)
        points = [obj.matrix_world @ vertex.co for vertex in component]
        heights = [point.z for point in points]
        if min(heights) < 1.1 and max(heights) < 1.4:
            chassis.update(component)
        elif level == 2 and max(max(p[i] for p in points) - min(p[i] for p in points) for i in range(3)) < .4:
            # Spend the far budget on the deck and recesses rather than tiny
            # wall latches/hinges, which project to less than four pixels.
            subpixel_details.update(component)
    assert chassis, 'Baseline chassis not found'
    bmesh.ops.delete(geometry, geom=list(subpixel_details), context='VERTS')
    geometry.verts.index_update()
    indices = {v.index for v in chassis}
    geometry.to_mesh(obj.data)
    geometry.free()
    lower = obj.copy()
    lower.data = obj.data.copy()
    lower.name = 'RTS_Chassis_Work'
    bpy.context.scene.collection.objects.link(lower)
    for part, keep_lower in [(lower, True), (obj, False)]:
        mesh = bmesh.new()
        mesh.from_mesh(part.data)
        mesh.verts.ensure_lookup_table()
        remove = [v for v in mesh.verts if (v.index in indices) != keep_lower]
        bmesh.ops.delete(mesh, geom=remove, context='VERTS')
        mesh.to_mesh(part.data)
        mesh.free()
    # Retain nearly the medium chassis budget at far zoom: aggressive collapse closes
    # the landing-gear recesses and intersects the fully retracted feet.
    lower_budget = [550, 550, 480][level]
    simplify(lower, lower_budget)
    simplify(obj, target('HullMesh', level) - lower_budget)
    print('RTS_CHASSIS', level, triangles(lower), flush=True)
    bpy.ops.object.select_all(action='DESELECT')
    lower.select_set(True)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.join()


def chassis_samples(obj):
    transform = bpy.data.objects['BarracksMechanicalV2'].matrix_world.inverted() @ obj.matrix_world
    tree = BVHTree.FromPolygons([transform @ v.co for v in obj.data.vertices],
                               [list(face.vertices) for face in obj.data.polygons])
    samples = []
    for x in [-4.25, 0.0, 4.25]:
        for y in [-1.0, 0.0, 1.0]:
            hit = tree.ray_cast(Vector((x, y, -.1)), Vector((0, 0, 1)), 1.09)[0]
            assert hit is not None, ('Missing chassis coverage', x, y)
            samples.append(hit.z)
    return samples


def simplify(obj, budget):
    original_bounds = [(min(v.co[i] for v in obj.data.vertices), max(v.co[i] for v in obj.data.vertices)) for i in range(3)]
    original_z = (min(v.co.z for v in obj.data.vertices), max(v.co.z for v in obj.data.vertices))
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    # glTF duplicates vertices at UV/normal seams. Weld topology while retaining
    # per-loop UVs, otherwise collapse can extrapolate long, open sliver triangles.
    geometry = bmesh.new()
    geometry.from_mesh(obj.data)
    bmesh.ops.remove_doubles(geometry, verts=list(geometry.verts), dist=0.00001)
    bmesh.ops.dissolve_degenerate(geometry, edges=list(geometry.edges), dist=0.00001)
    bmesh.ops.dissolve_limit(geometry, angle_limit=math.radians(5), use_dissolve_boundaries=False,
        verts=list(geometry.verts), edges=list(geometry.edges), delimit={'MATERIAL'})
    geometry.to_mesh(obj.data)
    geometry.free()
    # Collapse works within each disconnected piece; boundaries and material seams
    # survive. The existing 2K tangent normal atlas supplies the surface detail.
    modifier = obj.modifiers.new('RTS mesh budget', 'DECIMATE')
    modifier.ratio = min(1.0, budget / triangles(obj))
    modifier.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    for vertex in obj.data.vertices:
        for axis, (low, high) in enumerate(original_bounds):
            vertex.co[axis] = min(high, max(low, vertex.co[axis]))
    if obj.name.startswith(('Foot', 'Leg', 'Ramp')):
        low = min(v.co.z for v in obj.data.vertices)
        high = max(v.co.z for v in obj.data.vertices)
        for vertex in obj.data.vertices:
            vertex.co.z = original_z[0] + (vertex.co.z - low) / max(0.00001, high - low) * (original_z[1] - original_z[0])


def inspect_glb(path):
    with open(path, 'rb') as stream:
        data = stream.read()
    gltf = json.loads(data[20:20 + struct.unpack_from('<I', data, 12)[0]])
    binary_offset = 28 + struct.unpack_from('<I', data, 12)[0]
    image_hashes = {}
    for image in gltf.get('images', []):
        view = gltf['bufferViews'][image['bufferView']]
        start = binary_offset + view.get('byteOffset', 0)
        image_hashes[image['name']] = hashlib.sha256(data[start:start + view['byteLength']]).hexdigest()
    meshes = gltf['meshes']
    counts = {node['name']: sum(gltf['accessors'][p['indices']]['count'] // 3
              for p in meshes[node['mesh']]['primitives'])
              for node in gltf['nodes'] if 'mesh' in node}
    return {'triangles': sum(counts.values()), 'nodes': counts,
            'surfaces': sum(len(m['primitives']) for m in meshes),
            'materials': len(gltf['materials']), 'images': len(gltf.get('images', [])),
            'image_sha256': image_hashes,
            'clips': [a['name'] for a in gltf.get('animations', [])]}


def bake_far_colors(meshes):
    # At <80 projected pixels retain broad paint/metal colors without stretching
    # a tiny detailed UV island over a large decimated triangle.
    pixels = {}
    for obj in meshes:
        colors = obj.data.color_attributes.new(name='RTS_Color', type='BYTE_COLOR', domain='CORNER')
        uv = obj.data.uv_layers.active.data
        for face in obj.data.polygons:
            material = obj.data.materials[face.material_index]
            bsdf = next(n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
            texture = next((n.image for n in material.node_tree.nodes if n.type == 'TEX_IMAGE' and 'basecolor' in n.image.name), None)
            if texture and texture.name not in pixels:
                values = array('f', [0]) * len(texture.pixels)
                texture.pixels.foreach_get(values)
                pixels[texture.name] = values
            samples = []
            for loop in face.loop_indices:
                if 'Faction' in material.name or not texture:
                    samples.append((1, 1, 1, 1))
                else:
                    width, height = texture.size
                    point = uv[loop].uv
                    offset = (min(height - 1, max(0, int(point.y * height))) * width + min(width - 1, max(0, int(point.x * width)))) * 4
                    pixel = pixels[texture.name][offset:offset + 4]
                    samples.append(tuple(barracks_weathering.srgb_to_linear(c) for c in pixel[:3]) + (pixel[3],))
            # Match the texture-only GLB updater: interpolate sampled corner
            # colours instead of averaging unrelated atlas islands per face.
            for loop, color in zip(face.loop_indices, samples):
                colors.data[loop].color = color
    for material in set(m for obj in meshes for m in obj.data.materials):
        if 'Thrust' in material.name or 'Amber' in material.name:
            continue
        nodes = material.node_tree.nodes
        bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
        for node in list(nodes):
            if node not in [bsdf] and node.type != 'OUTPUT_MATERIAL':
                nodes.remove(node)
        color = nodes.new('ShaderNodeVertexColor')
        color.layer_name = 'RTS_Color'
        material.node_tree.links.new(color.outputs['Color'], bsdf.inputs['Base Color'])
        bsdf.inputs['Roughness'].default_value = .65
        bsdf.inputs['Metallic'].default_value = .15


def normal_sources(meshes):
    sources = {}
    materials = {}
    for obj in meshes:
        if obj.data.shape_keys or obj.name.startswith('Jet'):
            continue
        high = obj.copy()
        high.data = obj.data.copy()
        high.name = obj.name + '_NormalSource'
        bpy.context.scene.collection.objects.link(high)
        sources[obj] = high
        for slot in obj.material_slots:
            original = slot.material
            if original not in materials:
                name = original.name
                original.name = name + '_NormalSource'
                materials[original] = original.copy()
                materials[original].name = name
            slot.material = materials[original]
    return sources


def bake_normals(sources, level):
    bpy.context.scene.render.engine = 'CYCLES'
    bpy.context.scene.cycles.samples = 1
    # Start from the existing atlas so unchanged islands and background padding
    # stay valid. Only selected low-poly islands are overwritten by ray transfer.
    source_image = next(n.image for n in bpy.data.materials['RTS_Body'].node_tree.nodes
                        if n.type == 'TEX_IMAGE' and 'normal' in n.image.name)
    target_image = source_image.copy()
    target_image.name = f'barracks_rts_lod{level}_normal'
    target_image.colorspace_settings.name = 'Non-Color'
    materials = set(mat for obj in sources for mat in obj.data.materials)
    for mat in materials:
        target_node = mat.node_tree.nodes.new('ShaderNodeTexImage')
        target_node.image = target_image
        mat.node_tree.nodes.active = target_node
    for obj, high in sources.items():
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        high.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.bake(type='NORMAL', use_selected_to_active=True,
            cage_extrusion=.15, max_ray_distance=.30, use_clear=False, margin=2)
        print('RTS_NORMAL_BAKE', level, obj.name, flush=True)
    for mat in materials:
        for node in mat.node_tree.nodes:
            if node.type == 'TEX_IMAGE' and node.image == source_image:
                node.image = target_image
    target_image.filepath_raw = os.path.join(OUT, target_image.name + '.png')
    target_image.file_format = 'PNG'
    target_image.save()
    # Image.copy() also copies the old packed PNG. Explicit bytes prevent the
    # exporter from silently preferring that stale packed file after a bake.
    with open(target_image.filepath_raw, 'rb') as stream:
        baked_png = stream.read()
    target_image.pack(data=baked_png, data_len=len(baked_png))
    for high in sources.values():
        bpy.data.objects.remove(high, do_unlink=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, '.gdignore'), 'w') as stream:
        stream.write('\n')
    report = {'baseline': inspect_glb(SOURCE), 'levels': []}
    for level in range(3):
        bpy.ops.object.select_all(action='SELECT')
        bpy.ops.object.delete(use_global=False)
        for mat in list(bpy.data.materials):
            bpy.data.materials.remove(mat)
        bpy.ops.import_scene.gltf(filepath=SOURCE)
        root = bpy.data.objects['BarracksMechanicalV2']
        meshes = [o for o in root.children_recursive if o.type == 'MESH']
        baseline_chassis = chassis_samples(bpy.data.objects['HullMesh'])
        if level == 0:
            barracks_weathering.bake(meshes)
        barracks_weathering.apply_atlases(meshes)
        consolidate_materials(meshes)
        sources = normal_sources(meshes) if level < 2 else {}
        for obj in meshes:
            if obj.data.shape_keys:
                if level == 2:
                    # Flag is subpixel at strategic zoom; its animated near mesh
                    # remains in the runtime rig, but is hidden in this level.
                    bpy.data.objects.remove(obj, do_unlink=True)
                continue
            if obj.name == 'HullMesh':
                simplify_hull(obj, level)
            else:
                simplify(obj, target(obj.name, level))
        if level == 2:
            bake_far_colors([o for o in root.children_recursive if o.type == 'MESH'])
        else:
            bake_normals(sources, level)
        destination = os.path.join(OUT, 'barracks' + (f'_lod{level}' if level else '') + '.glb')
        bpy.ops.export_scene.gltf(filepath=destination, export_format='GLB',
            export_animations=(level == 0), export_morph=True,
            export_animation_mode='NLA_TRACKS', export_force_sampling=True)
        result = inspect_glb(destination)
        if level < 2:
            name = f'barracks_rts_lod{level}_normal'
            with open(os.path.join(OUT, name + '.png'), 'rb') as stream:
                expected = hashlib.sha256(stream.read()).hexdigest()
            assert result['image_sha256'][name] == expected, 'Export used stale packed normal map'
            assert expected != report['baseline']['image_sha256']['barracks_normal']
            for suffix in barracks_weathering.CHANNELS:
                with open(os.path.join(barracks_weathering.OUT, 'barracks_weathered_' + suffix + '.png'), 'rb') as stream:
                    weather_hash = hashlib.sha256(stream.read()).hexdigest()
                assert weather_hash in result['image_sha256'].values(), 'Export lost weathered ' + suffix
                assert weather_hash != report['baseline']['image_sha256']['barracks_' + suffix]
        print('RTS_COUNTS', level, json.dumps(result), flush=True)
        if level == 0:
            assert {'Takeoff', 'Landing', 'Flag_Wind_Loop'} <= set(result['clips']), result
        low, high = [(6000, 8000), (3000, 4000), (800, 1500)][level]
        assert low <= result['triangles'] <= high, result
        assert result['materials'] <= 6 and result['surfaces'] <= 40, result
        # Validate the exported/reimported topology, not just Blender's working mesh.
        bpy.ops.object.select_all(action='SELECT')
        bpy.ops.object.delete(use_global=False)
        bpy.ops.import_scene.gltf(filepath=destination)
        root = bpy.data.objects['BarracksMechanicalV2']
        # Disable animation before probing the exact same 97 mechanical poses.
        for obj in [root, *root.children_recursive]:
            if obj.animation_data:
                obj.animation_data_clear()
        chassis = chassis_samples(bpy.data.objects['HullMesh'])
        result['chassis_max_surface_error'] = max(abs(a - b) for a, b in zip(chassis, baseline_chassis))
        assert result['chassis_max_surface_error'] < .12, result
        result['clearance'] = validate_motion(root)
        report['levels'].append(result)
        print('RTS_LEVEL', level, json.dumps(result), flush=True)
    with open(os.path.join(OUT, 'asset_report.json'), 'w') as stream:
        json.dump(report, stream, indent=2)
    for level in range(3):
        name = 'barracks' + (f'_lod{level}' if level else '') + '.glb'
        shutil.copyfile(os.path.join(OUT, name), os.path.join(ROOT, 'assets/models', name))
    print('BARRACKS_RTS_BUILD PASS', flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
