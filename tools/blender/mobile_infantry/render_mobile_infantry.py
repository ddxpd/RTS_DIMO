import sys as _sys
from pathlib import Path as _Path
_blender_tools = _Path(__file__).resolve().parents[1]
_sys.path[:0] = [str(_Path(__file__).resolve().parent), str(_blender_tools), str(_blender_tools / "shared")]
from project_paths import model_path
"""Four deliverable studio images from the actual static character meshes."""
import bpy
import os
from mathutils import Vector


def bounds(objects):
    points=[o.matrix_world @ Vector(c) for o in objects if o.type=='MESH' for c in o.bound_box]
    return Vector(tuple(min(p[i] for p in points) for i in range(3))),Vector(tuple(max(p[i] for p in points) for i in range(3)))


def render_remaining(builder):
    b=builder
    previous=bpy.context.window.scene
    temporary=[]
    try:
        bpy.context.window.scene=b.scene
        b.render('mobile-infantry-back-v1.png',(-3,5,2.8))
        b.root.location.x=-.72
        red=b.materials[1].copy(); red.name='MI_RedPreview'
        shader=next(n for n in red.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        shader.inputs['Base Color'].default_value=(.58,.035,.022,1)
        duplicate_root=bpy.data.objects.new('MI_RedPreviewRoot',None)
        b.scene.collection.objects.link(duplicate_root); duplicate_root.location.x=.72; temporary.append(duplicate_root)
        for obj in b.objects:
            copy=obj.copy(); copy.data=obj.data.copy()
            b.scene.collection.objects.link(copy); copy.parent=duplicate_root
            if obj.get('surface')=='mark': copy.data.materials[0]=red
            temporary.append(copy)
        b.scene.view_layers[0].update()
        b.render('mobile-infantry-teams-v1.png',(2,-7,3.5),target=(0,0,.95),scale=3.3,width=1600,height=1100)
        for obj in reversed(temporary): bpy.data.objects.remove(obj,do_unlink=True)
        temporary.clear(); b.root.location.x=-1.5
        for file,x,height in [('soldier.glb',0,1.865),('barracks.glb',2.8,1.865*104/68)]:
            existing=set(b.scene.objects)
            bpy.ops.import_scene.gltf(filepath=str(model_path(file)))
            imported=set(b.scene.objects)-existing
            b.scene.view_layers[0].update()
            low,high=bounds(imported)
            reference_root=bpy.data.objects.new('MI_Reference_'+file,None)
            b.scene.collection.objects.link(reference_root)
            for obj in imported:
                if obj.parent is None:
                    world=obj.matrix_world.copy(); obj.parent=reference_root; obj.matrix_world=world
            scale=height/(high.z-low.z)
            reference_root.scale=(scale,)*3
            reference_root.location=(x-(low.x+high.x)*.5*scale,-(low.y+high.y)*.5*scale,-low.z*scale)
            temporary.extend([reference_root,*imported])
        b.scene.view_layers[0].update()
        b.render('mobile-infantry-rts-scale-v1.png',(4,-7,10),target=(1.2,0,.8),scale=7,width=1800,height=1200)
    finally:
        for obj in reversed(temporary):
            if obj.name in bpy.data.objects: bpy.data.objects.remove(obj,do_unlink=True)
        b.root.location=(0,0,0)
        bpy.context.window.scene=previous
