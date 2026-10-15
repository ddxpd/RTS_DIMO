"""Update animation only on the production blend. Run with the fixed Blender wrapper."""
import sys
from pathlib import Path
sys.path[:0] = [str(Path(__file__).parent), str(Path(__file__).parents[1])]
import bpy
import json
import struct
import hashlib
from mathutils import Matrix
from project_paths import model_path
from mobile_infantry_actions import build_actions
from audit_mobile_infantry_skin import audit

scene = bpy.context.scene
arm = next(obj for obj in scene.objects if obj.type == 'ARMATURE')
mesh = next(obj for obj in scene.objects if obj.type == 'MESH' and any(mod.type == 'ARMATURE' for mod in obj.modifiers))
root = arm.parent
geometry = repr([(tuple(vertex.co), [(g.group, g.weight) for g in vertex.groups]) for vertex in mesh.data.vertices])
before = hashlib.sha256(geometry.encode()).hexdigest()
arm.animation_data_clear()
actions = build_actions(scene, arm)
for name, action in actions.items():
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 0, action)
    track.mute = True
result = audit({'scene': scene, 'arm': arm, 'mesh': mesh, 'actions': actions})
scene.frame_set(0)
for pose in arm.pose.bones:
    pose.matrix_basis = Matrix.Identity(4)
for obj in scene.objects:
    obj.select_set(False)
for obj in [root, arm, mesh]:
    obj.select_set(True)
scene.view_layers[0].objects.active = arm
path = str(model_path('mobile_infantry.glb'))
bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True,
    use_active_scene=True, export_yup=True, export_animations=True, export_animation_mode='ACTIONS',
    export_force_sampling=True, export_def_bones=True, export_extras=True, export_image_format='AUTO')
raw = Path(path).read_bytes()
size = struct.unpack_from('<I', raw, 12)[0]
document = json.loads(raw[20:20+size])
names = {action.name: name for name, action in actions.items()}
document['animations'] = [a for a in document.get('animations', []) if a['name'] in names]
assert len(document['animations']) == 6
for animation in document['animations']:
    animation['name'] = names[animation['name']]
chunk = json.dumps(document, separators=(',', ':')).encode()
chunk += b' '*((-len(chunk))%4)
tail = raw[20+size:]
Path(path).write_bytes(struct.pack('<III', 0x46546C67, 2, 20+len(chunk)+len(tail))+struct.pack('<II',len(chunk),0x4E4F534A)+chunk+tail)
after = hashlib.sha256(repr([(tuple(v.co), [(g.group, g.weight) for g in v.groups]) for v in mesh.data.vertices]).encode()).hexdigest()
assert before == after, 'Animation update must preserve mesh and skin weights'
bpy.data.libraries.write(str(model_path('source/mobile_infantry.blend')), {scene}, fake_user=True, compress=True)
report_path = model_path('source/mobile_infantry_report.json')
report = json.loads(report_path.read_text(encoding='utf-8'))
report.update(result)
report.update(motion_revision=2, motion_geometry_sha256=before, motion_style='weighted low ready, shoulder/pelvis counter rotation, heel/toe roll')
report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print('MOBILE_MOTION_BAKE', result, 'geometry_preserved=', before)
