"""Read-only Blender validation of the retained infantry dependency chain."""
from pathlib import Path
import importlib.util
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from project_paths import PROJECT_ROOT, model_path

recipe = HERE / 'mobile_infantry/create_mobile_infantry_v5.py'
spec = importlib.util.spec_from_file_location('infantry_recipe_audit', recipe)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert Path(module.base.ROOT) == PROJECT_ROOT
assert Path(module.base.GLB) == model_path('mobile_infantry.glb')
assert hasattr(module.v3.v2, 'Builder')
assert hasattr(module.v3.baker, 'bake')
for name in ('soldier.glb', 'base.glb', 'gaia_command_base.glb', 'harvester.glb', 'refinery.glb'):
    assert model_path(name).is_file(), name
print('BLENDER_PIPELINES PASS dependency chain and retained model paths')
