import sys as _sys
from pathlib import Path as _Path
_blender_tools = _Path(__file__).resolve().parents[1]
_sys.path[:0] = [str(_Path(__file__).resolve().parent), str(_blender_tools), str(_blender_tools / "shared")]
"""Bake rounded armor and sculpted cloth detail onto unique low-poly UVs."""
import bpy
import math
import os
import numpy as np
from mathutils import Vector


def packed_save(image, path):
    image.filepath_raw=path
    image.file_format='PNG'
    image.save()
    with open(path,'rb') as stream:
        data=stream.read()
    image.pack(data=data,data_len=len(data))


def join_objects(scene, objects, name):
    for obj in scene.objects:
        obj.select_set(False)
    for obj in objects:
        obj.select_set(True)
    scene.view_layers[0].objects.active=objects[0]
    bpy.ops.object.join()
    result=bpy.context.object
    result.name=name
    return result


def bake(b, output):
    size = b.images['basecolor'].size[0]
    previous=bpy.context.window.scene
    bake_scene=bpy.data.scenes.new('MI_V2_TemporaryBake')
    bake_scene.render.engine='CYCLES'
    bake_scene.cycles.samples=16
    bake_scene.render.bake.margin=5
    high_collection=bpy.data.collections.new('MI_V2_BakeSources')
    b.scene.collection.children.link(high_collection)
    b.high_collection=high_collection
    temporaries=[]
    try:
        bpy.context.window.scene=bake_scene
        low_copies=[]; high_copies=[]
        for index, obj in enumerate(b.objects):
            high=obj.copy(); high.data=obj.data.copy(); high.parent=None
            high.matrix_world=obj.matrix_world.copy()
            high.name='MI_High_'+obj['part_role']
            bake_scene.collection.objects.link(high)
            for selected in bake_scene.objects:
                selected.select_set(False)
            high.select_set(True); bake_scene.view_layers[0].objects.active=high
            soft=obj.get('surface') in ['cloth','fabric']
            if soft:
                subdivision=high.modifiers.new('DetailSubdivision','SUBSURF')
                subdivision.levels=3; subdivision.render_levels=3
                bpy.ops.object.modifier_apply(modifier=subdivision.name)
                z_values=[v.co.z for v in high.data.vertices]
                low_z=min(z_values); span=max(z_values)-low_z
                for vertex in high.data.vertices:
                    t=(vertex.co.z-low_z)/max(span,.0001)
                    angle=math.atan2(vertex.co.y,vertex.co.x)
                    envelope=math.sin(math.pi*max(0,min(1,t)))**1.5
                    strength=.006 if 'Trouser' in high.name else .004
                    folds=math.sin(t*38+2.1*math.sin(angle*2))*.65+math.sin(t*62-angle*3)*.35
                    vertex.co += vertex.normal * (strength*envelope*folds)
                for face in high.data.polygons:
                    face.use_smooth=True
            elif obj['part_role'] not in getattr(b, 'preserve_high_normals_roles', set()):
                bevel=high.modifiers.new('BakedBevel','BEVEL')
                bevel.width=.0023 if obj.get('surface')!='mark' else .0007
                bevel.segments=3; bevel.limit_method='ANGLE'; bevel.angle_limit=.24
                bpy.ops.object.modifier_apply(modifier=bevel.name)
                for face in high.data.polygons:
                    face.use_smooth=True
                weighted=high.modifiers.new('DetailNormals','WEIGHTED_NORMAL')
                weighted.keep_sharp=True
                bpy.ops.object.modifier_apply(modifier=weighted.name)
            high.data.update()
            # Keep editable assembled high detail in the deliverable source.
            high_collection.objects.link(high)
            bake_scene.collection.objects.unlink(high)
            b.high_objects.append(high)
            high_copy=high.copy(); high_copy.data=high.data.copy()
            low_copy=obj.copy(); low_copy.data=obj.data.copy(); low_copy.parent=None
            low_copy.matrix_world=obj.matrix_world.copy()
            offset=Vector((index%12*4,index//12*4,0))
            high_copy.location+=offset; low_copy.location+=offset
            bake_scene.collection.objects.link(high_copy); bake_scene.collection.objects.link(low_copy)
            low_copies.append(low_copy); high_copies.append(high_copy)
        high=join_objects(bake_scene,high_copies,'MI_BakeHigh')
        low=join_objects(bake_scene,low_copies,'MI_BakeLow')
        temporaries.extend([high,low])
        # Source material supplies only geometry normals, then local occlusion.
        source=bpy.data.materials.new('MI_BakeSourceMaterial'); source.use_nodes=True
        if hasattr(b, 'detail_height'):
            b.attach_detail_height(source)
        high.data.materials.clear(); high.data.materials.append(source)
        target=bpy.data.materials.new('MI_BakeTargetMaterial'); target.use_nodes=True
        low.data.materials.clear(); low.data.materials.append(target)
        node=target.node_tree.nodes.new('ShaderNodeTexImage')
        target.node_tree.nodes.active=node
        normal=bpy.data.images.new('MI_V2_BakedNormal',width=size,height=size,alpha=False)
        normal.colorspace_settings.name='Non-Color'
        node.image=normal
        for obj in bake_scene.objects:
            obj.select_set(False)
        high.select_set(True); low.select_set(True); bake_scene.view_layers[0].objects.active=low
        bpy.ops.object.bake(type='NORMAL',use_selected_to_active=True,cage_extrusion=.035,max_ray_distance=.07,use_clear=True,margin=5)
        # The smooth helmet dome already has its desired curvature. Keep authored
        # normals here: the narrow crown produces ray-transfer bands after beveling.
        dome_pixels=np.empty(size*size*4,np.float32)
        normal.pixels.foreach_get(dome_pixels)
        dome_pixels=dome_pixels.reshape(size,size,4)
        for island in b.islands:
            if island['object']['part_role']=='HelmetDome' and not hasattr(b, 'detail_height'):
                x,y,w,h=island['rect']
                dome_pixels[y-5:y+h+5,x-5:x+w+5,:3]=(.5,.5,1)
        normal.pixels.foreach_set(dome_pixels.ravel())
        packed_save(normal,os.path.join(output,'mobile_infantry_normal.png'))
        ao=bpy.data.images.new('MI_V2_BakedAO',width=size,height=size,alpha=False)
        ao.colorspace_settings.name='Non-Color'; node.image=ao
        nodes=source.node_tree.nodes; links=source.node_tree.links
        output_node=next(n for n in nodes if n.type=='OUTPUT_MATERIAL')
        occlusion=nodes.new('ShaderNodeAmbientOcclusion'); occlusion.inputs['Distance'].default_value=.06
        emission=nodes.new('ShaderNodeEmission'); links.new(occlusion.outputs['Color'],emission.inputs['Color']); links.new(emission.outputs[0],output_node.inputs['Surface'])
        bpy.ops.object.bake(type='EMIT',use_selected_to_active=True,cage_extrusion=.035,max_ray_distance=.07,use_clear=True,margin=5)
        # Transfer baked occlusion to R; roughness and metallic retain separate channels.
        pixels=np.empty(size*size*4,np.float32); ao.pixels.foreach_get(pixels)
        baked=pixels.reshape(size,size,4)
        orm=np.empty_like(pixels); b.images['orm'].pixels.foreach_get(orm)
        orm=orm.reshape(size,size,4); orm[:,:,0]=np.clip(baked[:,:,0],.25,1)
        b.images['orm'].pixels.foreach_set(orm.ravel())
        packed_save(b.images['orm'],os.path.join(output,'mobile_infantry_orm.png'))
        packed_save(ao,os.path.join(output,'mobile_infantry_ao.png'))
        old=b.images['normal']; b.images['normal']=normal
        for material in b.materials:
            nodes=material.node_tree.nodes; links=material.node_tree.links
            for tex in nodes:
                if tex.type=='TEX_IMAGE' and tex.image==old:
                    tex.image=normal
            # glTF's recognized group exports ORM.R as ambient occlusion.
            group=bpy.data.node_groups.get('glTF Material Output')
            if group is None:
                group=bpy.data.node_groups.new('glTF Material Output','ShaderNodeTree')
                group.interface.new_socket(name='Occlusion',in_out='INPUT',socket_type='NodeSocketFloat')
            gltf=nodes.new('ShaderNodeGroup'); gltf.node_tree=group
            separate=next(n for n in nodes if n.type=='SEPARATE_COLOR')
            links.new(separate.outputs['Red'],gltf.inputs['Occlusion'])
        b.baked=True
        b.report.update(normal_baked=True,ao_baked=True,normal_bake_exclusions=['HelmetDome: authored smooth normals'],ao_method='high-to-low local per-part occlusion; no pose shadows baked',high_detail_faces=sum(len(o.data.polygons) for o in b.high_objects))
        if hasattr(b, 'detail_height'):
            b.report['normal_bake_exclusions'] = []
            b.report['surface_detail_method'] = 'Editable high-source height shader baked with geometry normals into tangent-space normal atlas'
    finally:
        for obj in temporaries:
            data=obj.data
            bpy.data.objects.remove(obj,do_unlink=True)
            if data.users==0:
                bpy.data.meshes.remove(data)
        bpy.context.window.scene=previous
        bpy.data.scenes.remove(bake_scene)
        high_collection.hide_render=True
        high_collection.hide_viewport=True


def weather(b, output):
    """Low contrast fabric weave, grime and restrained chipped paint at atlas edges."""
    image=b.images['basecolor']; pixels=np.empty(2048*2048*4,np.float32); image.pixels.foreach_get(pixels)
    color=pixels.reshape(2048,2048,4)
    rng=np.random.default_rng(81026)
    palette={'fabric':(.48,.465,.42),'armor':(.58,.58,.54),'cloth':(.052,.059,.061),
             'edge':(.115,.133,.143),'metal':(.13,.15,.16),'mark':(.8,.8,.8),
             'rubber':(.033,.04,.044),'visor':(.027,.07,.09)}
    for island in b.islands:
        x,y,w,h=island['rect']; kind=island['kind']
        color[y-5:y+h+5,x-5:x+w+5,:3]=palette[kind]
        region=color[y:y+h,x:x+w,:3]
        noise=rng.random((h,w))
        if kind in ['armor','fabric','mark']:
            coarse=rng.random((max(2,h//12+1),max(2,w//12+1)))
            rows=np.array([np.interp(np.linspace(0,coarse.shape[1]-1,w),np.arange(coarse.shape[1]),row) for row in coarse])
            coarse=np.array([np.interp(np.linspace(0,rows.shape[0]-1,h),np.arange(rows.shape[0]),rows[:,column]) for column in range(w)]).T
            region *= (1-.075*coarse[:,:,None])
            flecks=(noise>.993)&(coarse>.48)
            region[flecks] *= .58 if kind=='armor' else .80
        if kind in ['fabric','cloth']:
            yy,xx=np.indices((h,w))
            region *= (1+.014*np.sin(xx*math.pi)*np.cos(yy*math.pi/2))[:,:,None]
        if kind=='armor' and w>12 and h>12:
            for _ in range(max(2,w*h//2400)):
                sx=int(rng.integers(2,w-2)); sy=int(rng.integers(2,h-2))
                length=int(rng.integers(2,max(3,min(w//6,11))))
                region[sy:sy+1,sx:min(w,sx+length)] *= .61
        # Dilation matches the finished island so mip filtering does not reveal seams.
        color[y-5:y+h+5,x-5:x+w+5,:3]=np.pad(region.copy(),((5,5),(5,5),(0,0)),mode='edge')
    image.pixels.foreach_set(color.ravel())
    packed_save(image,os.path.join(output,'mobile_infantry_basecolor.png'))
