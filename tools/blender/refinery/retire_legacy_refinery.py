import sys as _sys
from pathlib import Path as _Path
_blender_tools = _Path(__file__).resolve().parents[1]
_sys.path[:0] = [str(_Path(__file__).resolve().parent), str(_blender_tools), str(_blender_tools / "shared")]
"""Remove the replaced refinery tree while preserving every other source object."""
import bpy
import json
from pathlib import Path

root = Path(__file__).resolve().parents[3]
path = root / 'assets/models/source/ironfront_models.blend'
bpy.ops.wm.open_mainfile(filepath=str(path))
bpy.context.preferences.filepaths.save_version = 0
legacy = bpy.data.objects.get('refinery')
removed = []
if legacy:
    targets = [legacy, *legacy.children_recursive]
    others = {o.name: (o.type, len(o.data.vertices) if o.type == 'MESH' else 0, tuple(tuple(row) for row in o.matrix_world)) for o in bpy.data.objects if o not in targets}
    for obj in reversed(targets):
        removed.append(obj.name)
        bpy.data.objects.remove(obj, do_unlink=True)
    after = {o.name: (o.type, len(o.data.vertices) if o.type == 'MESH' else 0, tuple(tuple(row) for row in o.matrix_world)) for o in bpy.data.objects}
    assert others == after, 'Unrelated source objects changed'
    bpy.ops.wm.save_as_mainfile(filepath=str(path))
print('LEGACY_REFINERY_REMOVAL PASS', json.dumps({'removed': removed, 'remaining_objects': len(bpy.data.objects)}))
