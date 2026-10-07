"""Isolated soldier rig, texture atlas and three skinned LOD exports."""
import os
import json
import struct
import bpy
import numpy as np


def linear_to_srgb(value):
    return np.where(value <= .0031308, value * 12.92, 1.055 * np.maximum(value, 0) ** (1 / 2.4) - .055)


def make_atlases(mesh, output):
    originals = list(mesh.data.materials)
    # Six large padded material regions. Geometry keeps its silhouette;
    # subpixel fabric/metal texture detail belongs in the atlas.
    size = 1024
    arrays = {name: np.ones((size, size, 4), dtype=np.float32)
              for name in ['color', 'normal', 'orm', 'emission']}
    arrays['normal'][:, :, :3] = (.5, .5, 1)
    arrays['orm'][:, :, :3] = (1, .7, 0)
    arrays['emission'][:, :, :3] = 0
    for slot, material in enumerate(originals):
        node = next(node for node in material.node_tree.nodes if node.type == 'BSDF_PRINCIPLED')
        col, row = slot % 3, slot // 3
        x0, x1 = int(col * size / 3), int((col + 1) * size / 3)
        y0, y1 = int(row * size / 2), int((row + 1) * size / 2)
        yy, xx = np.mgrid[y0:y1, x0:x1]
        detail = np.sin(xx * .71) * np.sin(yy * .83)
        color = np.array(node.inputs['Base Color'].default_value[:3])
        if 'Faction' in material.name:
            color = np.ones(3)
        arrays['color'][y0:y1, x0:x1, :3] = linear_to_srgb(np.clip(color * (1 + detail[..., None] * .025), 0, 1))
        arrays['orm'][y0:y1, x0:x1, 1] = np.clip(node.inputs['Roughness'].default_value + detail * .025, 0, 1)
        arrays['orm'][y0:y1, x0:x1, 2] = node.inputs['Metallic'].default_value
        arrays['normal'][y0:y1, x0:x1, 0] += detail * .025
        arrays['normal'][y0:y1, x0:x1, 1] += np.cos(xx * .71) * .02
        emission = node.inputs['Emission Color'].default_value[:3]
        energy = node.inputs['Emission Strength'].default_value
        arrays['emission'][y0:y1, x0:x1, :3] = linear_to_srgb(np.clip(np.array(emission) * energy, 0, 1))
    images = {}
    for name, values in arrays.items():
        image = bpy.data.images.new('Soldier_' + name, width=size, height=size, alpha=True)
        image.colorspace_settings.name = 'sRGB' if name in ['color', 'emission'] else 'Non-Color'
        image.pixels.foreach_set(values.ravel())
        image.filepath_raw = os.path.join(output, 'soldier_' + name + '.png')
        image.file_format = 'PNG'
        image.save()
        image.pack()
        images[name] = image
    uv = mesh.data.uv_layers.active or mesh.data.uv_layers.new(name='UVMap')
    faction_indices = []
    for polygon in mesh.data.polygons:
        slot = polygon.material_index
        faction_indices.append('Faction' in originals[slot].name)
        dominant = max(range(3), key=lambda axis: abs(polygon.normal[axis]))
        axes = [axis for axis in range(3) if axis != dominant]
        for loop in polygon.loop_indices:
            co = mesh.data.vertices[mesh.data.loops[loop].vertex_index].co
            u = (co[axes[0]] * .24 + .5) % 1
            v = (co[axes[1]] * .24 + .5) % 1
            uv.data[loop].uv = ((slot % 3 + .04 + .92 * u) / 3,
                                (slot // 3 + .04 + .92 * v) / 2)
    materials = []
    for name in ['Soldier_Body', 'Soldier_FactionPaint']:
        material = bpy.data.materials.new(name)
        material.use_nodes = True
        nodes, links = material.node_tree.nodes, material.node_tree.links
        shader = next(node for node in nodes if node.type == 'BSDF_PRINCIPLED')
        for channel in ['color', 'normal', 'orm', 'emission']:
            tex = nodes.new('ShaderNodeTexImage')
            tex.image = images[channel]
            if channel == 'color':
                links.new(tex.outputs['Color'], shader.inputs['Base Color'])
            elif channel == 'normal':
                normal = nodes.new('ShaderNodeNormalMap')
                links.new(tex.outputs['Color'], normal.inputs['Color'])
                links.new(normal.outputs['Normal'], shader.inputs['Normal'])
            elif channel == 'orm':
                separate = nodes.new('ShaderNodeSeparateColor')
                links.new(tex.outputs['Color'], separate.inputs['Color'])
                links.new(separate.outputs['Green'], shader.inputs['Roughness'])
                links.new(separate.outputs['Blue'], shader.inputs['Metallic'])
            elif name == 'Soldier_Body':
                links.new(tex.outputs['Color'], shader.inputs['Emission Color'])
                shader.inputs['Emission Strength'].default_value = 1.0
        material.use_backface_culling = True
        materials.append(material)
    mesh.data.materials.clear()
    for material in materials:
        mesh.data.materials.append(material)
    for polygon, faction in zip(mesh.data.polygons, faction_indices):
        polygon.material_index = int(faction)


def blend_joints(mesh):
    soft = set()
    for polygon in mesh.data.polygons:
        if mesh.data.materials[polygon.material_index].name in ['Heavy_Fabric', 'Heavy_Rubber']:
            soft.update(polygon.vertices)
    for index in soft:
        vertex = mesh.data.vertices[index]
        if not vertex.groups:
            continue
        group = mesh.vertex_groups[vertex.groups[0].group]
        name = group.name
        y, z = vertex.co.z, -vertex.co.y
        other, weight = None, 0.0
        if name.startswith('Clavicle_'):
            # Keep the inner socket sewn to the chest while the outer socket
            # follows the shoulder. Hard shell vertices are excluded above.
            other = 'Spine'
            weight = max(0, min(.65, (.46 - abs(vertex.co.x)) * 3.0))
        elif name.startswith('UpperArm_'):
            other = 'Clavicle_' + name[-1]
            weight = max(0, min(.45, (y - 1.93) * 2.2))
        elif name.startswith('Forearm_'):
            other = 'UpperArm_' + name[-1]
            weight = max(0, .45 * (1 - abs(y - 1.74) / .16))
        elif name.startswith('Shin_'):
            other = 'Thigh_' + name[-1]
            weight = max(0, .4 * (1 - abs(y - .70) / .17))
        elif name.startswith('Thigh_'):
            other = 'Pelvis'
            weight = max(0, min(.4, (y - 1.07) * 2))
        elif name == 'Spine':
            other = 'Pelvis'
            weight = max(0, min(.45, (1.78 - y) * 2))
        elif name.startswith('Foot_') and z > .16:
            other = 'Toe_' + name[-1]
            weight = min(.85, (z - .16) * 4)
        if other and weight > 0:
            target = mesh.vertex_groups.get(other) or mesh.vertex_groups.new(name=other)
            group.add([index], 1 - weight, 'REPLACE')
            target.add([index], weight, 'REPLACE')


def triangles(mesh):
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def finish_assets(root, mesh, rig, points, project):
    output = os.path.join(project, 'assets', 'concept_art', 'soldier_upgrade')
    os.makedirs(output, exist_ok=True)
    blend_joints(mesh)
    make_atlases(mesh, output)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(project, 'assets', 'models', 'source', 'soldier.blend'))
    original = mesh.data.copy()
    report = []
    for level, budget in enumerate([9800, 3400, 880]):
        mesh.data = original.copy()
        bpy.context.view_layer.objects.active = mesh
        modifier = mesh.modifiers.new('RTS geometry LOD', 'DECIMATE')
        modifier.ratio = min(1, budget / triangles(mesh.data))
        modifier.use_collapse_triangulate = True
        # Keep armour seams, atlas regions and deforming limbs distinct.
        modifier.delimit = {'MATERIAL', 'SEAM'}
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        count = triangles(mesh.data)
        assert count <= [10000, 3500, 900][level], (level, count)
        bpy.ops.object.select_all(action='DESELECT')
        root.select_set(True)
        for obj in root.children_recursive:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = root
        suffix = '' if level == 0 else '_lod' + str(level)
        path = os.path.join(project, 'assets', 'models', 'soldier' + suffix + '.glb')
        bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True,
            export_animations=False, export_skins=True, export_yup=True)
        with open(path, 'rb') as stream:
            data = stream.read()
        length = struct.unpack_from('<I', data, 12)[0]
        doc = json.loads(data[20:20+length])
        assert len(doc['skins'][0]['joints']) == 20
        assert len(doc['materials']) == 2
        exported = sum(doc['accessors'][p['indices']]['count'] // 3 for m in doc['meshes'] for p in m['primitives'])
        assert exported <= [10000, 3500, 900][level]
        report.append({'lod': level, 'triangles': exported, 'bones': 20, 'surfaces': 2, 'bytes': len(data)})
    with open(os.path.join(output, 'asset_report.json'), 'w') as stream:
        json.dump(report, stream, indent=2)
    print('SOLDIER_ASSETS PASS', json.dumps(report), flush=True)
