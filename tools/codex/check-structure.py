"""Read-only layout checks; run via run-structure.ps1."""
import ast
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]
failures = []
checks = 0


def check(ok, label):
    global checks
    checks += 1
    if not ok:
        failures.append(label)


def read(path):
    return path.read_text(encoding='utf-8-sig')


def check_runtime_path(path, label):
    resolved = path.resolve()
    if not resolved.is_relative_to(ROOT):
        check(False, 'Runtime dependency outside project: ' + label)
        return
    relative = resolved.relative_to(ROOT).as_posix()
    forbidden = ('assets/concept_art', '.local', '.godot', 'tools', 'tests', 'archive')
    check(not any(relative == prefix or relative.startswith(prefix + '/') for prefix in forbidden),
          'Runtime dependency must be a distributable resource: ' + label)
    if '%' not in relative and '{' not in relative:
        check(resolved.exists(), 'Runtime dependency exists: ' + label)


def check_runtime_boundaries():
    # Library scans production resources too; only its private data and concept
    # originals are excluded. Runtime assets must have their own project copy.
    files = [ROOT / 'project.godot']
    for folder in ('scripts', 'scenes', 'assets'):
        files.extend(p for p in (ROOT / folder).rglob('*') if p.is_file()
                     and not p.is_relative_to(ROOT / 'assets/concept_art')
                     and not p.is_relative_to(ROOT / 'assets/models/source'))
    for p in files:
        if p.suffix not in ('.gd', '.tscn', '.tres', '.godot', '.json', '.gdshader'):
            continue
        for resource in re.findall(r'''res://([^"'\s)]+)''', read(p)):
            check_runtime_path(ROOT / resource, f'{p.relative_to(ROOT)}: {resource}')
    result = subprocess.run(['git', 'check-ignore', '--no-index', '--stdin'], cwd=ROOT,
                            input='\n'.join(p.relative_to(ROOT).as_posix() for p in files) + '\n',
                            text=True, capture_output=True, encoding='utf-8')
    check(result.returncode in (0, 1), 'Git ignore audit succeeds: ' + result.stderr.strip())
    check(not result.stdout.strip(), 'Runtime files must not be Git-ignored: ' + result.stdout.strip())


def main():
    check_runtime_boundaries()
    registry = json.loads(read(ROOT / 'tools/codex/validation-suites.json'))['suites']
    registered = [entry['script'][6:] for entry in registry]
    check(len(registered) == len(set(registered)), 'Registry has unique paths')
    for entry in registry:
        check((ROOT / entry['script'][6:]).is_file(), entry['script'])
        if entry['full']:
            check(entry['mode'] in ('headless', 'rendered') and bool(entry['marker']), 'Executable suite: ' + entry['name'])
    scripts = {p.relative_to(ROOT).as_posix() for p in (ROOT / 'tests').rglob('*') if p.suffix in ('.gd', '.ps1') and 'fixtures' not in p.parts}
    check(scripts == set(registered), 'Every test/preview/helper is registered')
    for folder in ('scripts', 'assets/art', 'tests', 'tools/balance_designer'):
        for p in (ROOT / folder).rglob('*.gd'):
            for resource in re.findall(r'(?:preload|load)\("(res://[^"%]+)"\)', read(p)):
                check((ROOT / resource[6:]).is_file(), f'{p.relative_to(ROOT)}: {resource}')
    uids = {}
    for p in (ROOT / 'assets/models').rglob('*.import'):
        text = read(p)
        sources = re.findall(r'^source_file="res://(.*)"', text, re.M)
        for source in sources:
            check((ROOT / source).is_file(), 'Import source ' + source)
        uid = re.search(r'^uid="(.*)"', text, re.M)
        if uid:
            check(uid[1] not in uids, 'Unique resource UID: ' + str(p))
            uids[uid[1]] = p
    for p in (ROOT / 'assets/models').rglob('*.glb'):
        data = p.read_bytes()
        length = struct.unpack_from('<I', data, 12)[0]
        doc = json.loads(data[20:20 + length])
        for item in doc.get('images', []) + doc.get('buffers', []):
            uri = item.get('uri', '')
            if uri and not uri.startswith('data:'):
                parsed = urlsplit(uri)
                check(not parsed.scheme and not parsed.netloc, f'GLB dependency must be local: {p.name}: {uri}')
                dependency = p.parent / unquote(parsed.path)
                check(dependency.is_file(), f'GLB dependency {p.name}: {uri}')
                if not p.is_relative_to(ROOT / 'assets/models/source'):
                    check_runtime_path(dependency, f'GLB {p.name}: {uri}')
    for p in (ROOT / 'tools/blender').rglob('*.py'):
        ast.parse(read(p), filename=str(p))
        check(True, 'Python syntax ' + str(p))
    pipelines = json.loads(read(ROOT / 'tools/blender/pipelines.json'))
    def check_pipeline(value):
        if isinstance(value, dict):
            for child in value.values(): check_pipeline(child)
        elif isinstance(value, list):
            for child in value: check_pipeline(child)
        elif isinstance(value, str) and value.endswith('.py'):
            check((ROOT / 'tools/blender' / value).is_file(), 'Recipe: ' + value)
    check_pipeline(pipelines)
    spec = importlib.util.spec_from_file_location('project_paths', ROOT / 'tools/blender/project_paths.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    migration = json.loads(read(ROOT / 'tools/codex/structure-migration.json'))['paths']
    for old, new in migration.items():
        if old.startswith('assets/models/') and not old.endswith('.import'):
            check(module.model_path(Path(old).name) == ROOT / new, 'Recipe output ' + old)
    if len(sys.argv) > 1:
        preserved = json.loads(read(Path(sys.argv[1])))
        for old, digest in preserved.items():
            p = ROOT / migration.get(old, old)
            check(p.is_file() and hashlib.sha256(p.read_bytes()).hexdigest() == digest, 'Preserved bytes: ' + old)
    print(json.dumps({'checks': checks, 'failures': failures}, ensure_ascii=False))
    return bool(failures)


if __name__ == '__main__':
    sys.exit(main())
