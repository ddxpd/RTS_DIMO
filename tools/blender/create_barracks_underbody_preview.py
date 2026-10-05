"""Build and validate the independent complete-housing / underbody-lift v4 model."""
import os
import sys
import json
import struct
import bpy
sys.path.insert(0,os.path.dirname(__file__))
sys.dont_write_bytecode=True
import create_barracks_mechanical_preview as base
from barracks_underbody import pose_underbody, validate_motion, animate_flight

OUT=os.path.join(base.PROJECT_ROOT,'assets','concept_art','barracks_underbody_v4')


def main(bake=True):
    os.makedirs(OUT,exist_ok=True)
    with open(os.path.join(OUT,'.gdignore'),'w') as stream:
        stream.write('\n')
    base.UNDERBODY=True
    base.REALISTIC=False
    root=base.build()
    report=base.validate(root)
    assert report['triangles']<40000,report
    report['motion']=validate_motion(root)
    print('UNDERBODY_STRUCTURE PASS',json.dumps(report),flush=True)
    if not bake:
        bpy.context.preferences.filepaths.save_version=0
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'structure.blend'))
        base.export(root,os.path.join(OUT,'structure.glb'))
        return
    from barracks_realism_materials import prepare_materials
    report['materials']=prepare_materials(root,OUT)
    animate_flight(root)
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'barracks_underbody_v4.blend'))
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [root,*root.children_recursive]:
        obj.select_set(True)
    bpy.context.view_layer.objects.active=root
    destination=os.path.join(OUT,'barracks_underbody_v4.glb')
    bpy.ops.export_scene.gltf(filepath=destination,export_format='GLB',use_selection=True,
                             export_apply=False,export_animations=True,export_morph=True,
                             export_animation_mode='NLA_TRACKS',export_force_sampling=True,
                             export_frame_range=True,export_anim_slide_to_zero=True)
    with open(destination,'rb') as stream:
        data=stream.read()
    length=struct.unpack_from('<I',data,12)[0]
    gltf=json.loads(data[20:20+length])
    clips={clip['name'] for clip in gltf.get('animations',[])}
    assert {'Takeoff','Landing','Flag_Wind_Loop'} <= clips,clips
    assert all('bufferView' in image for image in gltf['images'])
    report['clips']=sorted(clips)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    group=bpy.data.node_groups.get('glTF Material Output')
    if group:
        bpy.data.node_groups.remove(group,do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=destination)
    root=bpy.data.objects['BarracksMechanicalV2']
    assert len([o for o in root.children_recursive if o.type=='MESH'])==report['meshes']
    # Disable imported clips for geometric pose checks; engine tests exercise actual playback.
    for obj in [root,*root.children_recursive]:
        if obj.animation_data:
            obj.animation_data_clear()
    report['reloaded_motion']=validate_motion(root)
    with open(os.path.join(OUT,'validation.json'),'w',encoding='utf-8') as stream:
        json.dump(report,stream,indent=2)
    print('BARRACKS_UNDERBODY_BUILD PASS',json.dumps(report))


if __name__=='__main__':
    main()
