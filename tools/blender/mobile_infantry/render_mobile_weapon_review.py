import sys as _sys
from pathlib import Path as _Path
_blender_tools = _Path(__file__).resolve().parents[1]
_sys.path[:0] = [str(_Path(__file__).resolve().parent), str(_blender_tools), str(_blender_tools / "shared")]
"""Render the actual rig and separate weapon; preserve the user's Blender scene."""
import bpy
import os
import math
import importlib.util
from mathutils import Matrix, Vector

HERE=os.path.dirname(__file__)


def render():
    spec=importlib.util.spec_from_file_location('review_base',os.path.join(HERE,'create_mobile_infantry.py'))
    base=importlib.util.module_from_spec(spec); spec.loader.exec_module(base)
    base.OUT=os.path.join(base.ROOT,'assets/concept_art/mobile_infantry/v6')
    rig=bpy.app.driver_namespace['mi_rig']
    gun=bpy.app.driver_namespace['mg_builder']
    previous=bpy.context.window.scene
    scene=rig['scene']; arm=rig['arm']
    bpy.context.window.scene=scene
    proxy=type('Review',(),{})(); proxy.scene=scene
    copies=[]
    try:
        base.Builder.studio(proxy)
        scene.cycles.samples=32
        for obj in gun.objects:
            copy=obj.copy(); copy.data=obj.data; copy.parent=None
            scene.collection.objects.link(copy); copies.append((obj,copy))
        for action,frame in [('idle',0),('fire',7),('jog',7)]:
            arm.animation_data.action=rig['actions'][action]
            scene.frame_set(frame); scene.view_layers[0].update()
            rest=arm.data.bones['weapon'].matrix_local
            placement=arm.pose.bones['weapon'].matrix @ rest.inverted() @ Matrix.Translation(Vector((-.025,-.287,1.19))) @ Matrix.Rotation(math.radians(35),4,'Y')
            for source,copy in copies: copy.matrix_world=placement @ source.matrix_world
            scene.view_layers[0].update()
            base.Builder.render(proxy,'mobile-infantry-armed-'+action+'-v6.png',(2.5,-6,2.8),target=(0,0,.95),scale=2.17)
    finally:
        for source,copy in copies: bpy.data.objects.remove(copy,do_unlink=True)
        arm.animation_data.action=None
        for pose in arm.pose.bones: pose.matrix_basis=Matrix.Identity(4)
        scene.frame_set(0)
        bpy.context.window.scene=previous


if __name__=='__main__':
    render()
