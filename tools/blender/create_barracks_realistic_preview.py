"""Independent realistic revision; the v2 comparison and game resources stay intact."""
import os
import sys
import json
import struct

sys.path.insert(0, os.path.dirname(__file__))
sys.dont_write_bytecode = True
import create_barracks_mechanical_preview as study

study.REALISTIC = True
study.OUT = os.path.join(study.PROJECT_ROOT, 'assets', 'concept_art', 'barracks_realistic_v3')
os.makedirs(study.OUT, exist_ok=True)
with open(os.path.join(study.OUT, '.gdignore'), 'w') as stream:
    stream.write('\n')
study.main()
with open(os.path.join(study.OUT,'barracks_mechanical_v2.glb'),'rb') as stream:
    data=stream.read()
length=struct.unpack_from('<I',data,12)[0]
gltf=json.loads(data[20:20+length])
assert all('bufferView' in image for image in gltf['images']), 'External image dependency'
assert gltf.get('animations'), 'Missing exported animation'
textured=[m for m in gltf['materials'] if 'baseColorTexture' in m.get('pbrMetallicRoughness',{})]
assert len(textured)>=10
assert all('normalTexture' in m and 'occlusionTexture' in m and 'metallicRoughnessTexture' in m['pbrMetallicRoughness'] for m in textured)
print('BARRACKS_REALISTIC_DELIVERY PASS embedded textures, normal/ORM and animation')
