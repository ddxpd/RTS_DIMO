"""Bake portable PBR atlases from restrained procedural coatings and local-only AO."""
import os
import math
import bpy


def select(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]


def procedural(mat):
    tree = mat.node_tree
    nodes, links = tree.nodes, tree.links
    bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    original = tuple(bsdf.inputs['Base Color'].default_value)
    geometry = nodes.new('ShaderNodeNewGeometry')

    def math_node(operation, a, b):
        node = nodes.new('ShaderNodeMath')
        node.operation = operation
        for i, value in enumerate([a, b]):
            if isinstance(value, (int, float)):
                node.inputs[i].default_value = value
            else:
                links.new(value, node.inputs[i])
        return node.outputs[0]

    def noise(scale, detail=2):
        node = nodes.new('ShaderNodeTexNoise')
        node.inputs['Scale'].default_value = scale
        node.inputs['Detail'].default_value = detail
        links.new(geometry.outputs['Position'], node.inputs['Vector'])
        return node.outputs['Fac']

    def mix(a, b, fac):
        node = nodes.new('ShaderNodeMixRGB')
        for slot, value in [(0, fac), (1, a), (2, b)]:
            if hasattr(value, 'node'):
                links.new(value, node.inputs[slot])
            else:
                node.inputs[slot].default_value = value
        return node.outputs[0]

    name = mat.name
    fabric = name.startswith('Flag')
    painted = any(s in name for s in ['Armor', 'Faction', 'Caution'])
    rubber = 'Recess' in name or 'Rubber' in name
    polished = 'Hydraulics' in name
    base = original
    if name == 'V2_Armor':
        base = (.40, .425, .43, 1)
    if name == 'V2_ArmorEdge':
        base = (.48, .50, .50, 1)
    if 'Faction' in name:
        base = (.028, .13, .27, 1)
    metal = 0 if painted or fabric or rubber else (.96 if polished else .82)
    rough = .86 if fabric or rubber else (.22 if polished else (.49 if painted else .38))
    grain = noise(24 if not fabric else 100, 2)
    mottling = noise(2.8, 3)
    tint = mix(tuple(c*.985 for c in base[:3])+(1,), base, mottling)
    separate = nodes.new('ShaderNodeSeparateXYZ')
    links.new(geometry.outputs['Position'], separate.inputs[0])
    dust = math_node('MULTIPLY', math_node('MAXIMUM', math_node('SUBTRACT', 1.8, separate.outputs['Z']), 0), .10)
    dust = math_node('MULTIPLY', dust, mottling)
    if fabric:
        dust = math_node('MULTIPLY', grain, .018)
    color = mix(tint, (.27, .205, .13, 1), dust)
    roughness = math_node('ADD', rough, math_node('MULTIPLY', grain, .035))
    metallic = math_node('MULTIPLY', metal, math_node('SUBTRACT', 1, dust))
    if painted:
        edge = math_node('MULTIPLY', math_node('MAXIMUM', math_node('SUBTRACT', geometry.outputs['Pointiness'], .55), 0), 2)
        edge = math_node('MULTIPLY', edge, math_node('GREATER_THAN', noise(65), .72))
        color = mix(color, (.12, .15, .17, 1), edge)
        metallic = math_node('MAXIMUM', metallic, edge)
    if name == 'V3_Nozzle':
        color = mix(color, (.009, .012, .014, 1), .40)
        roughness = math_node('ADD', roughness, .18)
    if name == 'V3_RampDeck':
        stripes = nodes.new('ShaderNodeTexNoise')
        stripes.inputs['Scale'].default_value = 90
        links.new(geometry.outputs['Position'], stripes.inputs['Vector'])
        wear = math_node('MULTIPLY', math_node('GREATER_THAN', stripes.outputs['Fac'], .64), .15)
        color = mix(color, (.33, .36, .37, 1), wear)
    links.new(color, bsdf.inputs['Base Color'])
    links.new(roughness, bsdf.inputs['Roughness'])
    if hasattr(metallic, 'node'):
        links.new(metallic, bsdf.inputs['Metallic'])
    bump = nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = .025 if not fabric else .10
    bump.inputs['Distance'].default_value = .002 if not fabric else .003
    height = grain
    if name == 'V3_Bulkhead':
        lower = math_node('ABSOLUTE', math_node('SUBTRACT', separate.outputs['Z'], 1.10), 0)
        upper = math_node('ABSOLUTE', math_node('SUBTRACT', separate.outputs['Z'], 4.05), 0)
        band = math_node('LESS_THAN', math_node('MINIMUM', lower, upper), .025)
        height = math_node('ADD', math_node('MULTIPLY', grain, .03), math_node('MULTIPLY', band, noise(45)))
        bump.inputs['Strength'].default_value = .18
        bump.inputs['Distance'].default_value = .015
    links.new(height, bump.inputs['Height'])
    links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    ao = nodes.new('ShaderNodeAmbientOcclusion')
    ao.only_local = True
    ao.samples = 16
    ao.inputs['Distance'].default_value = .24
    packed = nodes.new('ShaderNodeCombineXYZ')
    links.new(ao.outputs['AO'], packed.inputs['X'])
    links.new(roughness, packed.inputs['Y'])
    links.new(metallic, packed.inputs['Z'])
    return color, packed.outputs[0], bsdf.outputs[0]


def bake_group(objects, size, prefix, folder):
    materials = set(m for obj in objects for m in obj.data.materials if m)
    sources = {mat: procedural(mat) for mat in materials}
    targets = {}
    for suffix, colorspace in [('basecolor', 'sRGB'), ('orm', 'Non-Color'), ('normal', 'Non-Color')]:
        image = bpy.data.images.new(prefix+'_'+suffix, width=size, height=size, alpha=False)
        image.colorspace_settings.name = colorspace
        targets[suffix] = image
        for mat in materials:
            nodes, links = mat.node_tree.nodes, mat.node_tree.links
            texture = nodes.get('BakeTarget') or nodes.new('ShaderNodeTexImage')
            texture.name = 'BakeTarget'
            texture.image = image
            nodes.active = texture
            output = next(n for n in nodes if n.type == 'OUTPUT_MATERIAL')
            if suffix == 'normal':
                links.new(sources[mat][2], output.inputs['Surface'])
            else:
                emit = nodes.get('BakeEmission') or nodes.new('ShaderNodeEmission')
                emit.name = 'BakeEmission'
                links.new(sources[mat][0 if suffix == 'basecolor' else 1], emit.inputs[0])
                links.new(emit.outputs[0], output.inputs['Surface'])
        select(objects)
        bpy.ops.object.bake(type='NORMAL' if suffix == 'normal' else 'EMIT', margin=8, use_clear=True)
        image.filepath_raw = os.path.join(folder, prefix+'_'+suffix+'.png')
        image.file_format = 'PNG'
        image.save()
        image.pack()
        print('REALISM_BAKE', prefix, suffix, flush=True)
    # Preserve material names for faction overrides and differences in double-sidedness.
    for mat in materials:
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        nodes.clear()
        output = nodes.new('ShaderNodeOutputMaterial')
        bsdf = nodes.new('ShaderNodeBsdfPrincipled')
        links.new(bsdf.outputs[0], output.inputs[0])
        textures = {}
        for suffix, image in targets.items():
            node = nodes.new('ShaderNodeTexImage')
            node.image = image
            textures[suffix] = node.outputs['Color']
        links.new(textures['basecolor'], bsdf.inputs['Base Color'])
        split = nodes.new('ShaderNodeSeparateColor')
        links.new(textures['orm'], split.inputs[0])
        links.new(split.outputs['Green'], bsdf.inputs['Roughness'])
        links.new(split.outputs['Blue'], bsdf.inputs['Metallic'])
        normal = nodes.new('ShaderNodeNormalMap')
        links.new(textures['normal'], normal.inputs['Color'])
        links.new(normal.outputs[0], bsdf.inputs['Normal'])
        group = bpy.data.node_groups.get('glTF Material Output')
        if group is None:
            group = bpy.data.node_groups.new('glTF Material Output', 'ShaderNodeTree')
            group.interface.new_socket(name='Occlusion', in_out='INPUT', socket_type='NodeSocketFloat')
        settings = nodes.new('ShaderNodeGroup')
        settings.node_tree = group
        links.new(split.outputs['Red'], settings.inputs['Occlusion'])
    return {suffix: image.name for suffix, image in targets.items()}


def prepare_materials(root, folder):
    meshes = [o for o in root.children_recursive if o.type == 'MESH']
    flag = bpy.data.objects['BarracksFlag']
    body = [o for o in meshes if o != flag and not o.name.startswith('Jet')]
    for obj in body:
        for slot in obj.material_slots:
            if slot.material is None:
                slot.material = bpy.data.materials['V2_Armor']
            name = slot.material.name
            target = None
            if obj.name.startswith('Foot') and 'Frame' in name:
                target = 'V3_Rubber'
            elif obj.name.startswith('LiftPod') and 'Frame' in name:
                target = 'V3_Nozzle'
            elif obj.name.startswith('RampMesh') and 'Steel' in name:
                target = 'V3_RampDeck'
            if target:
                replacement = bpy.data.materials.get(target)
                if replacement is None:
                    replacement = slot.material.copy()
                    replacement.name = target
                slot.material = replacement
    # Emissive status lenses retain separate materials; do not bake their light into paint.
    select(body)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=.003, area_weight=.4)
    bpy.ops.object.mode_set(mode='OBJECT')
    uv = flag.data.uv_layers.new(name='UVMap')
    for loop in flag.data.loops:
        index = loop.vertex_index
        uv.data[loop.index].uv = ((index % 25)/24, (index // 25)/12)
    # Back up emission sockets because those surfaces remain distinct in the export.
    emissive = set(m for o in body for m in o.data.materials if m and ('Light' in m.name or 'Thrust' in m.name))
    backups = {m: m.copy() for m in emissive}
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 16
    scene.render.bake.use_selected_to_active = False
    textures = os.path.join(folder, 'textures')
    os.makedirs(textures, exist_ok=True)
    body_images = bake_group(body, 2048, 'barracks', textures)
    flag_images = bake_group([flag], 512, 'flag', textures)
    for obj in body:
        for slot in obj.material_slots:
            if slot.material in backups:
                slot.material = backups[slot.material]
    return {'body': body_images, 'flag': flag_images, 'body_resolution': 2048,
            'flag_resolution': 512, 'ao': 'per-object only; no moving-part shadows baked'}
