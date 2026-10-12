import sys as _sys
from pathlib import Path as _Path
_blender_tools = _Path(__file__).resolve().parents[1]
_sys.path[:0] = [str(_Path(__file__).resolve().parent), str(_blender_tools), str(_blender_tools / "shared")]
"""Rebuild both independent production assets and their formal held-weapon views."""
import importlib.util
import os


def load(name):
    path=os.path.join(os.path.dirname(__file__),name+'.py')
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def build():
    load('create_mobile_machine_gun').create()
    load('create_mobile_infantry_v5').create(version=6,separate_weapon=True)
    load('compose_mobile_infantry_preview').create()
    load('render_mobile_weapon_review').render()


if __name__=='__main__':
    build()
