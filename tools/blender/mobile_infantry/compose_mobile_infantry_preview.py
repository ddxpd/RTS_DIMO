import sys as _sys
from pathlib import Path as _Path
_blender_tools = _Path(__file__).resolve().parents[1]
_sys.path[:0] = [str(_Path(__file__).resolve().parent), str(_blender_tools), str(_blender_tools / "shared")]
"""Compose a library-only armed preview from the two embedded production GLBs.

The game continues loading separate assets. This file gives the art library the
same weapon attachment and all six animations without any engine-specific code.
"""
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def read(path):
    raw = path.read_bytes()
    length = struct.unpack_from('<I', raw, 12)[0]
    doc = json.loads(raw[20:20+length])
    binary_length = struct.unpack_from('<I', raw, 20+length)[0]
    return doc, raw[28+length:28+length+binary_length]


def create():
    body, body_bin = read(ROOT/'assets/models/units/mobile_infantry/mobile_infantry.glb')
    gun, gun_bin = read(ROOT/'assets/models/units/mobile_infantry/mobile_infantry_machine_gun.glb')
    offsets = {key: len(body.get(key, [])) for key in
               ['nodes','meshes','accessors','bufferViews','materials','textures','images','samplers']}
    for view in gun['bufferViews']:
        view['byteOffset'] = view.get('byteOffset', 0) + len(body_bin)
    for accessor in gun['accessors']:
        accessor['bufferView'] += offsets['bufferViews']
    for image in gun['images']:
        image['bufferView'] += offsets['bufferViews']
    for texture in gun['textures']:
        texture['source'] += offsets['images']
        if 'sampler' in texture:
            texture['sampler'] += offsets['samplers']

    def material_textures(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key.endswith('Texture') and isinstance(item, dict) and 'index' in item:
                    item['index'] += offsets['textures']
                else:
                    material_textures(item)
        elif isinstance(value, list):
            for item in value:
                material_textures(item)

    for material in gun['materials']:
        material_textures(material)
    for mesh in gun['meshes']:
        for primitive in mesh['primitives']:
            primitive['indices'] += offsets['accessors']
            primitive['material'] += offsets['materials']
            primitive['attributes'] = {key: value+offsets['accessors'] for key,value in primitive['attributes'].items()}
    for node in gun['nodes']:
        if 'mesh' in node:
            node['mesh'] += offsets['meshes']
        if 'children' in node:
            node['children'] = [index+offsets['nodes'] for index in node['children']]
    mount = next(node['extras']['weapon_mount'] for node in body['nodes'] if 'weapon_mount' in node.get('extras', {}))
    matrix = [value for column in range(4) for value in mount[column*3:column*3+3]+[1 if column == 3 else 0]]
    for key in offsets:
        body.setdefault(key, []).extend(gun.get(key, []))
    socket = len(body['nodes'])
    body['nodes'].append({'name':'MachineGunAttachment','matrix':matrix,
                          'children':[index+offsets['nodes'] for index in gun['scenes'][gun.get('scene', 0)]['nodes']]})
    bone = next(node for node in body['nodes'][:offsets['nodes']] if node.get('name') == 'weapon')
    bone.setdefault('children', []).append(socket)
    body['buffers'][0]['byteLength'] = len(body_bin)+len(gun_bin)
    body['extensionsUsed'] = sorted(set(body.get('extensionsUsed', [])+gun.get('extensionsUsed', [])))
    body['asset']['extras'] = {'purpose':'Art library assembled preview; game loads the independent body and weapon assets.'}
    data = json.dumps(body, separators=(',', ':')).encode('utf-8')
    data += b' '*((-len(data))%4)
    binary = body_bin+gun_bin
    path = ROOT/'assets/concept_art/mobile_infantry/v6/mobile_infantry_armed_preview.glb'
    path.write_bytes(struct.pack('<IIIII',0x46546C67,2,28+len(data)+len(binary),len(data),0x4E4F534A)+data+
                     struct.pack('<II',len(binary),0x004E4942)+binary)
    return str(path)


if __name__ == '__main__':
    print(create())
