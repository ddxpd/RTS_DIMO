"""Stable output locations shared by asset recipes after the directory migration."""
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
MODEL_ROOT = PROJECT_ROOT / 'assets/models'


def model_path(name):
    """Resolve a model basename; preserve explicit source/texture/group paths."""
    relative = Path(name)
    if relative.is_absolute() or '..' in relative.parts:
        raise ValueError('Expected a model-relative path')
    if len(relative.parts) > 1 or str(relative) in ('source', 'textures'):
        return MODEL_ROOT / relative
    groups = (
        ('mobile_infantry', 'units/mobile_infantry'), ('soldier', 'units/soldier'),
        ('harvester', 'units/harvester'), ('barracks', 'buildings/barracks'),
        ('gaia', 'buildings/gaia'), ('base', 'buildings/legacy_base'),
        ('refinery', 'buildings/refinery'), ('bunker', 'buildings/bunker'),
        ('bullet', 'effects'), ('ore', 'environment/ore'),
    )
    for prefix, group in groups:
        if relative.name.startswith(prefix):
            return MODEL_ROOT / group / relative
    raise ValueError(f'Unregistered model output: {name}')
