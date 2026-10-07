"""Bake maintained field wear into the existing UV atlas; never change geometry."""
import hashlib
import json
import os
import struct
import sys
from array import array

import bpy
import bmesh

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(ROOT, 'assets/concept_art/barracks_weathering')
SOURCE = os.path.join(ROOT, 'assets/models/source/barracks_rts_baseline.glb')
CHANNELS = ('basecolor', 'orm')


def srgb_to_linear(value):
    return value / 12.92 if value <= .04045 else ((value + .055) / 1.055) ** 2.4


def component_bounds(obj):
    # Bake-only attributes let the shader locate each original armour panel's
    # edges. Pointiness on imported split normals would dirty entire flat faces.
    geometry = bmesh.new()
    geometry.from_mesh(obj.data)
    bmesh.ops.remove_doubles(geometry, verts=list(geometry.verts), dist=.00001)
    pending_vertices = set(geometry.verts)
    lookup = {}
    while pending_vertices:
        seed = pending_vertices.pop()
        component = {seed}
        pending = [seed]
        while pending:
            for edge in pending.pop().link_edges:
                for vertex in edge.verts:
                    if vertex in pending_vertices:
                        pending_vertices.remove(vertex)
                        component.add(vertex)
                        pending.append(vertex)
        points = [obj.matrix_world @ v.co for v in component]
        bounds = tuple(tuple(fn(p[i] for p in points) for i in range(3)) for fn in (min, max))
        for vertex in component:
            lookup[tuple(round(c, 4) for c in vertex.co)] = bounds
    for index, name in enumerate(('WeatherMin', 'WeatherMax')):
        attribute = obj.data.attributes.get(name) or obj.data.attributes.new(name, 'FLOAT_VECTOR', 'POINT')
        for vertex in obj.data.vertices:
            attribute.data[vertex.index].vector = lookup[tuple(round(c, 4) for c in vertex.co)][index]
    geometry.free()


def coating(mat):
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    old_color = bsdf.inputs['Base Color'].links[0].from_socket
    old_orm = next(n for n in nodes if n.type == 'TEX_IMAGE' and 'orm' in n.image.name).outputs['Color']

    def connect(value, socket):
        if hasattr(value, 'node'):
            links.new(value, socket)
        else:
            socket.default_value = value

    def calc(operation, a, b=0):
        node = nodes.new('ShaderNodeMath')
        node.operation = operation
        connect(a, node.inputs[0])
        connect(b, node.inputs[1])
        return node.outputs[0]

    def mix(a, b, factor):
        node = nodes.new('ShaderNodeMixRGB')
        for value, socket in zip((factor, a, b), node.inputs):
            connect(value, socket)
        return node.outputs[0]

    def clamp(value):
        return calc('MINIMUM', 1, calc('MAXIMUM', 0, value))

    geometry = nodes.new('ShaderNodeNewGeometry')
    position = nodes.new('ShaderNodeSeparateXYZ')
    normal = nodes.new('ShaderNodeSeparateXYZ')
    links.new(geometry.outputs['Position'], position.inputs[0])
    links.new(geometry.outputs['Normal'], normal.inputs[0])
    x, y, z = position.outputs
    limits = []
    for name in ('WeatherMin', 'WeatherMax'):
        attribute = nodes.new('ShaderNodeAttribute')
        attribute.attribute_name = name
        separate = nodes.new('ShaderNodeSeparateXYZ')
        links.new(attribute.outputs['Vector'], separate.inputs[0])
        limits.append(separate.outputs)
    distances = [calc('MINIMUM', calc('ABSOLUTE', calc('SUBTRACT', p, limits[0][i])),
                      calc('ABSOLUTE', calc('SUBTRACT', p, limits[1][i]))) for i, p in enumerate((x, y, z))]
    minimum = calc('MINIMUM', distances[0], calc('MINIMUM', distances[1], distances[2]))
    maximum = calc('MAXIMUM', distances[0], calc('MAXIMUM', distances[1], distances[2]))
    edge_distance = calc('SUBTRACT', calc('ADD', distances[0], calc('ADD', distances[1], distances[2])), calc('ADD', minimum, maximum))

    def noise(scale, detail=3):
        node = nodes.new('ShaderNodeTexNoise')
        node.inputs['Scale'].default_value = scale
        node.inputs['Detail'].default_value = detail
        links.new(geometry.outputs['Position'], node.inputs['Vector'])
        return node.outputs['Fac']

    def spot(cx, cy, radius):
        dx = calc('SUBTRACT', x, cx)
        dy = calc('SUBTRACT', y, cy)
        distance = calc('SQRT', calc('ADD', calc('MULTIPLY', dx, dx), calc('MULTIPLY', dy, dy)))
        return calc('POWER', clamp(calc('SUBTRACT', 1, calc('DIVIDE', distance, radius))), 1.4)

    split = nodes.new('ShaderNodeSeparateColor')
    links.new(old_orm, split.inputs[0])
    broad = noise(1.8)
    patches = clamp(calc('MULTIPLY', calc('SUBTRACT', broad, .28), 2.5))
    fine = noise(32, 2)
    upward = clamp(normal.outputs['Z'])
    lower = clamp(calc('DIVIDE', calc('SUBTRACT', 1.6, z), 1.6))
    cavity = clamp(calc('MULTIPLY', calc('SUBTRACT', 1, split.outputs['Red']), 1.8))
    dust = clamp(calc('ADD', calc('MULTIPLY', patches, calc('ADD', .12, calc('MULTIPLY', upward, .25))),
                      calc('ADD', calc('MULTIPLY', lower, .24), calc('MULTIPLY', cavity, .38))))
    name = mat.name
    faction = 'Faction' in name
    armor = 'Armor' in name or faction
    rubber = 'Recess' in name or 'Rubber' in name
    hydraulics = 'Hydraulics' in name
    color = old_color
    roughness = .62 if armor else (.90 if rubber else (.28 if hydraulics else .46))
    metallic = 0.0 if armor or rubber else .82
    if armor and not faction:
        # Visible mid-grey paint, rather than white panels under game lighting.
        color = mix(old_color, (.13, .155, .16, 1), .55)
    elif faction:
        # Runtime converts this paint to neutral and applies the team colour.
        dust = calc('MULTIPLY', dust, .35)
    elif rubber:
        color = mix(old_color, (.045, .05, .052, 1), .45)
    elif 'Frame' in name:
        color = mix(old_color, (.085, .10, .115, 1), .40)
    color = mix(color, (.095, .084, .065, 1), dust)
    roughness = calc('ADD', roughness, calc('MULTIPLY', patches, .12))
    roughness = calc('ADD', roughness, calc('MULTIPLY', dust, .18))
    metallic = calc('MULTIPLY', metallic, calc('SUBTRACT', 1, dust))

    # Equipment-local soot, not uniform black noise over every panel.
    roof = calc('GREATER_THAN', z, 3.8)
    roof_soot = calc('MAXIMUM', spot(-.43, -2.0, 1.5), spot(2.45, -2.0, 1.5))
    roof_soot = calc('MAXIMUM', roof_soot, calc('MULTIPLY', spot(-3.2, -.52, 1.65), .85))
    soot = calc('MULTIPLY', roof_soot, roof)
    engine_soot = 0
    for cx in [-2.85, 2.85]:
        for cy in [-1.6, 1.6]:
            engine_soot = calc('MAXIMUM', engine_soot, spot(cx, cy, 1.02))
    soot = calc('MAXIMUM', soot, calc('MULTIPLY', engine_soot, calc('LESS_THAN', z, 1.12)))
    soot = calc('MULTIPLY', soot, calc('ADD', .65, calc('MULTIPLY', patches, .30)))
    if faction:
        soot = calc('MULTIPLY', soot, .35)
    color = mix(color, (.018, .021, .022, 1), soot)
    roughness = calc('ADD', roughness, calc('MULTIPLY', soot, .14))

    if armor and not faction:
        seam = calc('MULTIPLY', clamp(calc('SUBTRACT', 1, calc('DIVIDE', edge_distance, .18))), patches)
        color = mix(color, (.055, .051, .043, 1), calc('MULTIPLY', seam, .50))
        stretch = nodes.new('ShaderNodeVectorMath')
        stretch.operation = 'MULTIPLY'
        links.new(geometry.outputs['Position'], stretch.inputs[0])
        stretch.inputs[1].default_value = (8, 8, .55)
        streaks = nodes.new('ShaderNodeTexNoise')
        streaks.inputs['Scale'].default_value = 1
        streaks.inputs['Detail'].default_value = 2
        links.new(stretch.outputs['Vector'], streaks.inputs['Vector'])
        rain = clamp(calc('MULTIPLY', calc('SUBTRACT', streaks.outputs['Fac'], .47), 3))
        rain = calc('MULTIPLY', rain, calc('LESS_THAN', calc('ABSOLUTE', normal.outputs['Z']), .35))
        color = mix(color, (.075, .07, .058, 1), calc('MULTIPLY', rain, .23))
        edge = clamp(calc('SUBTRACT', 1, calc('DIVIDE', edge_distance, .04)))
        wear = calc('MULTIPLY', edge, calc('GREATER_THAN', fine, .58))
        color = mix(color, (.13, .16, .18, 1), calc('MULTIPLY', wear, .65))
        metallic = calc('MAXIMUM', metallic, calc('MULTIPLY', wear, .70))
    if 'RampDeck' in name:
        traffic = calc('MAXIMUM', clamp(calc('SUBTRACT', 1, calc('MULTIPLY', calc('ABSOLUTE', calc('SUBTRACT', x, .35)), 3))),
                       clamp(calc('SUBTRACT', 1, calc('MULTIPLY', calc('ABSOLUTE', calc('SUBTRACT', x, 1.70)), 3))))
        color = mix(color, (.22, .235, .24, 1), calc('MULTIPLY', traffic, .48))
    if hydraulics:
        oil = calc('MULTIPLY', patches, .32)
        color = mix(color, (.024, .027, .025, 1), oil)
        roughness = calc('SUBTRACT', roughness, oil)
    packed = nodes.new('ShaderNodeCombineXYZ')
    connect(split.outputs['Red'], packed.inputs[0])
    connect(clamp(roughness), packed.inputs[1])
    connect(clamp(metallic), packed.inputs[2])
    return color, packed.outputs[0]


def bake(meshes):
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, '.gdignore'), 'w') as stream:
        stream.write('\n')
    body = [obj for obj in meshes if not obj.data.shape_keys and not obj.name.startswith('Jet')]
    for obj in body:
        component_bounds(obj)
    materials = set(m for obj in body for m in obj.data.materials if m)
    selected = {mat for mat in materials if any(n.type == 'TEX_IMAGE' and 'barracks_basecolor' in n.image.name for n in mat.node_tree.nodes)}
    sources = {mat: coating(mat) for mat in selected}
    # Emissive lenses occupy atlas space too, but their runtime materials stay intact.
    for mat in materials - selected:
        bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
        sources[mat] = (tuple(bsdf.inputs['Base Color'].default_value), (1, .4, .1, 1))
    original_outputs = {mat: next(n for n in mat.node_tree.nodes if n.type == 'OUTPUT_MATERIAL').inputs['Surface'].links[0].from_socket for mat in materials}
    bpy.context.scene.render.engine = 'CYCLES'
    bpy.context.scene.cycles.samples = 1
    for channel, suffix in enumerate(CHANNELS):
        image = bpy.data.images.new('barracks_weathered_' + suffix, width=2048, height=2048, alpha=False)
        image.colorspace_settings.name = 'sRGB' if suffix == 'basecolor' else 'Non-Color'
        for mat in materials:
            nodes, links = mat.node_tree.nodes, mat.node_tree.links
            target = nodes.get('WeatherBakeTarget') or nodes.new('ShaderNodeTexImage')
            target.name = 'WeatherBakeTarget'
            target.image = image
            nodes.active = target
            emission = nodes.get('WeatherBakeEmission') or nodes.new('ShaderNodeEmission')
            emission.name = 'WeatherBakeEmission'
            value = sources[mat][channel]
            if hasattr(value, 'node'):
                links.new(value, emission.inputs['Color'])
            else:
                for link in list(emission.inputs['Color'].links):
                    links.remove(link)
                emission.inputs['Color'].default_value = value
            output = next(n for n in nodes if n.type == 'OUTPUT_MATERIAL')
            links.new(emission.outputs[0], output.inputs['Surface'])
        bpy.ops.object.select_all(action='DESELECT')
        for obj in body:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = body[0]
        bpy.ops.object.bake(type='EMIT', margin=8, use_clear=True, use_selected_to_active=False)
        image.filepath_raw = os.path.join(OUT, 'barracks_weathered_' + suffix + '.png')
        image.file_format = 'PNG'
        image.save()
        print('WEATHER_BAKE', suffix, flush=True)
    for mat in materials:
        output = next(n for n in mat.node_tree.nodes if n.type == 'OUTPUT_MATERIAL')
        mat.node_tree.links.new(original_outputs[mat], output.inputs['Surface'])
        for name in ['WeatherBakeTarget', 'WeatherBakeEmission']:
            mat.node_tree.nodes.remove(mat.node_tree.nodes[name])


def apply_atlases(meshes):
    images = {}
    for suffix in CHANNELS:
        path = os.path.join(OUT, 'barracks_weathered_' + suffix + '.png')
        image = bpy.data.images.load(path, check_existing=False)
        image.colorspace_settings.name = 'sRGB' if suffix == 'basecolor' else 'Non-Color'
        with open(path, 'rb') as stream:
            data = stream.read()
        image.pack(data=data, data_len=len(data))
        images[suffix] = image
    for mat in set(m for obj in meshes for m in obj.data.materials if m):
        for node in mat.node_tree.nodes:
            if node.type == 'TEX_IMAGE' and node.image:
                for suffix in CHANNELS:
                    if node.image.name.startswith('barracks_' + suffix):
                        node.image = images[suffix]


def read_glb(path):
    with open(path, 'rb') as stream:
        data = stream.read()
    size = struct.unpack_from('<I', data, 12)[0]
    return json.loads(data[20:20 + size]), bytearray(data[28 + size:])


def view_bytes(doc, binary, index):
    view = doc['bufferViews'][index]
    start = view.get('byteOffset', 0)
    return binary[start:start + view['byteLength']]


def accessor_values(doc, binary, index):
    accessor = doc['accessors'][index]
    view = doc['bufferViews'][accessor['bufferView']]
    dimensions = {'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'SCALAR': 1}[accessor['type']]
    code, size = {5126: ('f', 4), 5123: ('H', 2), 5121: ('B', 1), 5125: ('I', 4)}[accessor['componentType']]
    start = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
    stride = view.get('byteStride', dimensions * size)
    return [struct.unpack_from('<' + code * dimensions, binary, start + i * stride) for i in range(accessor['count'])]


def geometry_hash(doc, binary):
    digest = hashlib.sha256()
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            for key, index in sorted(primitive['attributes'].items()):
                if key != 'COLOR_0':
                    digest.update(repr(accessor_values(doc, binary, index)).encode())
            digest.update(repr(accessor_values(doc, binary, primitive['indices'])).encode())
            for target in primitive.get('targets', []):
                for key, index in sorted(target.items()):
                    digest.update(repr(accessor_values(doc, binary, index)).encode())
    for animation in doc.get('animations', []):
        for sampler in animation['samplers']:
            for key in ('input', 'output'):
                digest.update(repr(accessor_values(doc, binary, sampler[key])).encode())
    digest.update(json.dumps(doc.get('nodes'), sort_keys=True).encode())
    digest.update(json.dumps(doc.get('animations'), sort_keys=True).encode())
    return digest.hexdigest()


def patch_glb(path, destination, atlas):
    doc, binary = read_glb(path)
    original_geometry = geometry_hash(doc, binary)
    replacements = {}
    hashes = {}
    for image in doc.get('images', []):
        for suffix in CHANNELS:
            if image['name'] in ('barracks_' + suffix, 'barracks_weathered_' + suffix):
                with open(os.path.join(OUT, 'barracks_weathered_' + suffix + '.png'), 'rb') as stream:
                    replacements[image['bufferView']] = stream.read()
                image['name'] = 'barracks_weathered_' + suffix
                hashes[suffix] = hashlib.sha256(replacements[image['bufferView']]).hexdigest()
    if not doc.get('images'):
        pixels = array('f', [0]) * len(atlas.pixels)
        atlas.pixels.foreach_get(pixels)
        width, height = atlas.size
        for mesh in doc['meshes']:
            for primitive in mesh['primitives']:
                if doc['materials'][primitive['material']]['name'] != 'RTS_Body':
                    continue
                attributes = primitive['attributes']
                accessor = doc['accessors'][attributes['COLOR_0']]
                view = doc['bufferViews'][accessor['bufferView']]
                code, size, factor = {5126: ('f', 4, 1), 5123: ('H', 2, 65535), 5121: ('B', 1, 255)}[accessor['componentType']]
                dimensions = 4 if accessor['type'] == 'VEC4' else 3
                stride = view.get('byteStride', dimensions * size)
                for i, (u, v) in enumerate(accessor_values(doc, binary, attributes['TEXCOORD_0'])):
                    # glTF UVs start at the top; Blender image pixels start at
                    # the bottom. Failing to flip V samples unrelated islands.
                    offset = (min(height - 1, max(0, int((1 - v) * height))) * width + min(width - 1, max(0, int(u * width)))) * 4
                    color = list(pixels[offset:offset + dimensions])
                    color[:3] = [srgb_to_linear(c) for c in color[:3]]
                    if dimensions == 4:
                        color[3] = 1
                    if factor != 1:
                        color = [round(max(0, min(1, c)) * factor) for c in color]
                    start = view.get('byteOffset', 0) + accessor.get('byteOffset', 0) + i * stride
                    struct.pack_into('<' + code * dimensions, binary, start, *color)
    packed = bytearray()
    for index, view in enumerate(doc['bufferViews']):
        contents = replacements.get(index, view_bytes(doc, binary, index))
        packed.extend(b'\x00' * (-len(packed) % 4))
        view['byteOffset'] = len(packed)
        view['byteLength'] = len(contents)
        packed.extend(contents)
    packed.extend(b'\x00' * (-len(packed) % 4))
    doc['buffers'][0]['byteLength'] = len(packed)
    encoded = json.dumps(doc, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    assert geometry_hash(doc, packed) == original_geometry, 'Material edit changed geometry/rig'
    with open(destination, 'wb') as stream:
        stream.write(struct.pack('<III', 0x46546C67, 2, 28 + len(encoded) + len(packed)))
        stream.write(struct.pack('<II', len(encoded), 0x4E4F534A))
        stream.write(encoded)
        stream.write(struct.pack('<II', len(packed), 0x004E4942))
        stream.write(packed)
    return {'geometry_sha256': original_geometry, 'textures': hashes}


def apply_existing_atlases():
    import shutil
    atlas = bpy.data.images.load(os.path.join(OUT, 'barracks_weathered_basecolor.png'), check_existing=False)
    reports = {}
    for name in ['barracks.glb', 'barracks_lod1.glb', 'barracks_lod2.glb']:
        path = os.path.join(ROOT, 'assets/models', name)
        reports[name] = patch_glb(path, os.path.join(OUT, name), atlas)
    for name in reports:
        shutil.copyfile(os.path.join(OUT, name), os.path.join(ROOT, 'assets/models', name))
    with open(os.path.join(OUT, 'material_report.json'), 'w') as stream:
        json.dump(reports, stream, indent=2)
    print('BARRACKS_WEATHERING PASS', json.dumps(reports), flush=True)


def main():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
    bake(meshes)
    apply_existing_atlases()


if __name__ == '__main__':
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
