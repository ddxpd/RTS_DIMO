"""Render the delivered v4 GLB, including its exported takeoff and landing clips."""
import os
import sys
import struct
import zlib
import math
import bpy
sys.path.insert(0, os.path.dirname(__file__))
sys.dont_write_bytecode = True
from create_bunker import PROJECT_ROOT, material, cube, empty
from render_bunker_preview import look_at, make_area
from render_barracks_mechanical_preview import png_chunks

OUT = os.path.join(PROJECT_ROOT, 'assets', 'concept_art')
MODEL = os.path.join(OUT, 'barracks_underbody_v4', 'barracks_underbody_v4.glb')


def select_clip(name):
    found = 0
    for obj in bpy.data.objects:
        owners = [obj]
        if obj.type == 'MESH' and obj.data.shape_keys:
            owners.append(obj.data.shape_keys)
        for owner in owners:
            data = owner.animation_data
            if not data:
                continue
            data.action = None
            for track in data.nla_tracks:
                selected = track.name == name or track.name == 'Flag_Wind_Loop'
                track.mute = not selected
                if track.name == 'Flag_Wind_Loop':
                    for strip in track.strips:
                        strip.repeat = 3
                found += int(track.name == name)
    assert found > 0, ('Missing imported animation', name)


def save_png(scene, name):
    scene.render.filepath = os.path.join(OUT, '.barracks-v4-frame.png')
    bpy.ops.render.render(write_still=True)
    with open(scene.render.filepath, 'rb') as stream:
        data = stream.read()
    if name:
        os.replace(scene.render.filepath, os.path.join(OUT, name+'.png'))
    return data


def write_motion(scene, name):
    scene.render.resolution_percentage = 50
    select_clip(name)
    frames = []
    for frame in range(0, 97, 2):
        scene.frame_set(frame)
        frames.append(list(png_chunks(save_png(scene, None))))
    result = bytearray(b'\x89PNG\r\n\x1a\n')
    def chunk(kind, payload):
        result.extend(struct.pack('>I',len(payload))+kind+payload)
        result.extend(struct.pack('>I',zlib.crc32(kind+payload)&0xffffffff))
    header = frames[0][0][1]
    width, height = struct.unpack('>II',header[:8])
    chunk(b'IHDR',header)
    for kind, payload in frames[0][1:]:
        if kind not in [b'IDAT',b'IEND']:
            chunk(kind,payload)
    chunk(b'acTL',struct.pack('>II',len(frames),0))
    sequence = 0
    for index, frame in enumerate(frames):
        chunk(b'fcTL',struct.pack('>IIIIIHHBB',sequence,width,height,0,0,
                                 8 if index in [0,len(frames)-1] else 1,12,0,0))
        sequence += 1
        for kind,payload in frame:
            if kind != b'IDAT':
                continue
            if index == 0:
                chunk(kind,payload)
            else:
                chunk(b'fdAT',struct.pack('>I',sequence)+payload)
                sequence += 1
    chunk(b'IEND',b'')
    assert sum(k == b'fcTL' for k,p in png_chunks(result)) == 49
    with open(os.path.join(OUT,'barracks-v4-'+name.lower()+'.png'),'wb') as stream:
        stream.write(result)
    scene.render.resolution_percentage = 100
    print('V4_ANIMATION_RENDER PASS',name,'49 frames',flush=True)


def main():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=MODEL)
    print('IMPORTED_TRACKS',[(o.name,[t.name for t in o.animation_data.nla_tracks])
                             for o in bpy.data.objects if o.animation_data],flush=True)
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 1100
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.fps = 24
    floor = cube('StudioFloor',(200,200,.06),(0,0,-.06),material('Studio',(.10,.12,.14),.1,.85),None,0)
    camera_data = bpy.data.cameras.new('PreviewCamera')
    camera = bpy.data.objects.new('PreviewCamera',camera_data)
    bpy.context.collection.objects.link(camera)
    camera_data.type = 'ORTHO'
    camera_data.ortho_scale = 18
    scene.camera = camera
    make_area('Key',(-7,9,15),3100,8,(1,.91,.8))
    make_area('Fill',(10,5,8),1600,8,(.65,.8,1))
    make_area('Rim',(-1,-8,12),2900,7,(.78,.88,1))
    make_area('UnderFill',(1,6,-3),800,6,(.7,.82,1))
    background = scene.world.node_tree.nodes.get('Background')
    background.inputs['Color'].default_value = (.14,.17,.20,1)
    background.inputs['Strength'].default_value = .45
    grid = empty('FootprintGrid')
    gridmat = material('Grid',(.20,.4,.5),0,.9)
    for x in [-128/24,-128/48,0,128/48,128/24]:
        cube('GridLine',(.018,8,.012),(x,0,-.025),gridmat,grid,0)
    for y in [-4,-4/3,4/3,4]:
        cube('GridLine',(128/12,.018,.012),(0,y,-.025),gridmat,grid,0)
    cases = [
        ('landed','Takeoff',1,(-12,16,10),(0,0,3.6),18),
        ('rear','Takeoff',1,(12,-17,10),(0,0,3.6),18),
        ('footprint','Takeoff',1,(0,0,24),(0,0,0),16),
        ('takeoff-mid','Takeoff',53,(-12,16,8),(0,0,4.7),18),
        ('airborne','Takeoff',97,(-12,16,5),(0,0,5.1),18),
        ('landing-mid','Landing',61,(-12,16,7),(0,0,4.1),18),
        ('underbody','Takeoff',97,(-10,12,-6),(0,0,3.8),13),
    ]
    for name,clip,frame,location,target,scale in cases:
        select_clip(clip)
        scene.frame_set(frame-1)
        floor.hide_render = name == 'underbody'
        for obj in grid.children:
            obj.hide_render = name != 'footprint'
        camera.location = location
        camera_data.ortho_scale = scale
        look_at(camera,target)
        save_png(scene,'barracks-v4-'+name)
        print('V4_STATIC_RENDER',name,flush=True)
    floor.hide_render = False
    camera.location = (-12,16,8)
    camera_data.ortho_scale = 19
    look_at(camera,(0,0,5))
    for clip in ['Takeoff','Landing']:
        write_motion(scene,clip)
    os.remove(os.path.join(OUT,'.barracks-v4-frame.png'))
    print('BARRACKS_V4_RENDER PASS seven views plus two actual GLB animations',flush=True)


if __name__ == '__main__':
    main()
