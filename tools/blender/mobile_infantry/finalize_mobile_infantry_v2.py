import sys as _sys
from pathlib import Path as _Path
_blender_tools = _Path(__file__).resolve().parents[1]
_sys.path[:0] = [str(_Path(__file__).resolve().parent), str(_blender_tools), str(_blender_tools / "shared")]
"""Export only production collections; render actual low-mesh review boards."""
import bpy
import math
import os


def export(b, base):
    studio=b.scene
    previous=bpy.context.window.scene
    asset=bpy.data.scenes.new('MobileInfantry_V%d_Source' % b.root.get('asset_version', 2))
    asset.collection.children.link(b.collection)
    asset.collection.children.link(b.high_collection)
    # Source high detail uses its own materials without the low-mesh baked normals.
    high_materials={}
    for high in b.high_objects:
        for slot in high.material_slots:
            original=slot.material
            if original not in high_materials:
                mat=original.copy(); mat.name='MI_HighSource_'+original.name
                shader=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
                for link in list(shader.inputs['Normal'].links):
                    mat.node_tree.links.remove(link)
                if hasattr(b, 'detail_height'):
                    b.attach_detail_height(mat)
                high_materials[original]=mat
            slot.material=high_materials[original]
    try:
        b.scene=asset
        bpy.context.window.scene=asset
        base.Builder.export(b)
    finally:
        b.scene=studio
        bpy.context.window.scene=previous


def duplicate(b, name, location, rotation=0, red=False):
    root=bpy.data.objects.new(name,None)
    b.scene.collection.objects.link(root)
    root.location=location; root.rotation_euler.z=math.radians(rotation)
    material=None
    if red:
        material=b.materials[1].copy()
        shader=next(n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        shader.inputs['Base Color'].default_value=(.40,.022,.013,1)
    copies=[root]
    for obj in b.objects:
        copy=obj.copy()
        if red and any('Faction' in mat.name for mat in obj.data.materials):
            copy.data=obj.data.copy()
            for index,mat in enumerate(copy.data.materials):
                if 'Faction' in mat.name:
                    copy.data.materials[index]=material
        copy.parent=root
        b.scene.collection.objects.link(copy); copies.append(copy)
    return copies


def cleanup(objects):
    for obj in reversed(objects):
        bpy.data.objects.remove(obj,do_unlink=True)


def render(b):
    previous=bpy.context.window.scene
    copies=[]
    try:
        bpy.context.window.scene=b.scene
        b.scene.cycles.samples=64
        for obj in b.scene.objects:
            if obj.name.startswith('MI_Floor'):
                material=obj.data.materials[0]
                shader=next(n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
                shader.inputs['Emission Color'].default_value=(1,1,1,1)
                shader.inputs['Emission Strength'].default_value=.65
        b.render('mobile-infantry-front-v2.png',(2.5,-6,2.8),target=(0,0,.95),scale=2.17)
        b.render('mobile-infantry-back-v2.png',(-2.5,6,2.8),target=(0,0,.95),scale=2.17)
        b.root.location.x=-1.05
        copies+=duplicate(b,'MI_V2_Side',(0,0,0),90)
        copies+=duplicate(b,'MI_V2_Back',(1.05,0,0),180)
        b.scene.view_layers[0].update()
        b.render('mobile-infantry-views-v2.png',(0,-8,1.22),target=(0,0,.94),scale=3.60,width=1900,height=1150)
        cleanup(copies); copies=[]
        b.root.location.x=-.7
        copies+=duplicate(b,'MI_V2_Red',(.7,0,0),0,True)
        b.scene.view_layers[0].update()
        b.render('mobile-infantry-teams-v2.png',(1.3,-7,2.8),target=(0,0,.95),scale=3.10,width=1600,height=1200)
    finally:
        cleanup(copies)
        b.root.location=(0,0,0)
        bpy.context.window.scene=previous
