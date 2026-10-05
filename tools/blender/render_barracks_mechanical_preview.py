"""Studio previews of the standalone delivery GLB, never the runtime model."""
import math
import os
import sys
import base64
import struct
import zlib
import bpy

sys.path.insert(0,os.path.dirname(__file__))
sys.dont_write_bytecode=True
from create_bunker import PROJECT_ROOT,material,cube,empty
from create_barracks_mechanical_preview import OUT,pose
from render_bunker_preview import look_at,make_area
VERSION = 'v2'
LABEL = '军用机械'


def png_chunks(data):
    offset = 8
    while offset < len(data):
        size = struct.unpack('>I', data[offset:offset+4])[0]
        yield data[offset+4:offset+8], data[offset+8:offset+8+size]
        offset += size+12


def write_flag_animation(scene, directory):
    # APNG preserves the rendered colors without an external encoder dependency.
    frames = []
    scene.render.resolution_percentage = 50
    temporary = os.path.join(directory, '.barracks-flag-frame.png')
    for frame in range(1, 49, 2):
        scene.frame_set(frame)
        scene.render.filepath = temporary
        bpy.ops.render.render(write_still=True)
        with open(temporary, 'rb') as stream:
            frames.append(list(png_chunks(stream.read())))
    os.remove(temporary)
    result = bytearray(b'\x89PNG\r\n\x1a\n')

    def chunk(kind, payload):
        result.extend(struct.pack('>I', len(payload)) + kind + payload)
        result.extend(struct.pack('>I', zlib.crc32(kind+payload) & 0xffffffff))

    header = frames[0][0][1]
    width, height = struct.unpack('>II', header[:8])
    chunk(b'IHDR', header)
    for kind, payload in frames[0][1:]:
        if kind not in [b'IDAT', b'IEND']:
            chunk(kind, payload)
    chunk(b'acTL', struct.pack('>II', len(frames), 0))
    sequence = 0
    for index, frame in enumerate(frames):
        assert frame[0] == (b'IHDR', header)
        chunk(b'fcTL', struct.pack('>IIIIIHHBB', sequence, width, height, 0, 0, 1, 12, 0, 0))
        sequence += 1
        for kind, payload in frame:
            if kind != b'IDAT':
                continue
            if index == 0:
                chunk(b'IDAT', payload)
            else:
                chunk(b'fdAT', struct.pack('>I', sequence)+payload)
                sequence += 1
    chunk(b'IEND', b'')
    destination = os.path.join(directory, f'兵营模型-{LABEL}-旗帜飘动-{VERSION}.png')
    with open(destination, 'wb') as stream:
        stream.write(result)
    chunks = list(png_chunks(result))
    assert sum(kind == b'fcTL' for kind, _ in chunks) == 24
    # A self-contained browser preview also works when image viewers show only frame 1.
    encoded = base64.b64encode(result).decode('ascii')
    html = '<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>兵营旗帜飘动预览</title>'
    html += '<style>body{margin:0;background:#202830;color:#eee;text-align:center;font:16px sans-serif}img{max-width:100%;height:auto}p{margin:12px}</style>'
    html += '<p>兵营主楼旗帜 · 两秒循环 · 实际 GLB 模型渲染</p>'
    html += '<img alt="蓝白旗帜随风飘动的兵营" src="data:image/png;base64,'+encoded+'"></html>'
    with open(os.path.join(directory, f'兵营旗帜飘动预览-{VERSION}.html'), 'w', encoding='utf-8') as stream:
        stream.write(html)
    print('BARRACKS_FLAG_ANIMATION PASS 24 frames 12 fps 2 seconds')


def main():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT,'barracks_mechanical_v2.glb'))
    root=bpy.data.objects['BarracksMechanicalV2']
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.04))
    bpy.context.object.data.materials.append(material('StudioFloor',(.10,.12,.14),.1,.85))
    camera_data=bpy.data.cameras.new('StudioCamera')
    camera=bpy.data.objects.new('StudioCamera',camera_data)
    bpy.context.collection.objects.link(camera)
    camera_data.type='ORTHO'
    camera_data.ortho_scale=18.5
    scene=bpy.context.scene
    scene.camera=camera
    make_area('Key',(-7,9,15),3100,8,(1,.91,.80))
    make_area('Fill',(10,5,8),1600,8,(.65,.80,1))
    make_area('Rim',(-1,-8,12),2900,7,(.78,.88,1))
    make_area('BottomFill',(3,7,2),280,5,(.7,.8,1))
    background=scene.world.node_tree.nodes.get('Background')
    background.inputs['Color'].default_value=(.14,.17,.20,1)
    background.inputs['Strength'].default_value=.45
    scene.render.engine='BLENDER_EEVEE'
    scene.render.resolution_x=1800
    scene.render.resolution_y=1200
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'
    # A real geometric grid denotes the intended 4x3 footprint at scale 12.
    grid=empty('FootprintGrid')
    gridmat=material('GridPaint',(.19,.35,.44),.0,.9)
    for x in [-128/24,-128/48,0,128/48,128/24]:
        cube('GridLine',(.018,8.0,.012),(x,0,-.025),gridmat,grid,0)
    for y in [-4,-4/3,4/3,4]:
        cube('GridLine',(128/12,.018,.012),(0,y,-.025),gridmat,grid,0)
    font=bpy.data.curves.new('StateTitle','FONT')
    font.size=.25
    font.extrude=0
    title=bpy.data.objects.new('StateTitle',font)
    bpy.context.collection.objects.link(title)
    title.parent=camera
    title.location=(-7.95,4.82,-10)
    font.materials.append(material('TitlePaint',(.78,.83,.86),0,.6,emission=(.6,.7,.8),emission_strength=.6))
    cases=[
        ('落地主视','LANDED',0,0,-.56,1,0,(-12,16,11),(0,0,2.7)),
        ('背侧结构','REAR STRUCTURE',0,0,-.56,0,0,(12,-17,10),(0,0,2.7)),
        ('俯视占地','4 x 3 FOOTPRINT',0,0,-.56,1,0,(0,0,24),(0,0,0)),
        ('升空过渡','LIFT-OFF',1.1,.40,1.1,0,.8,(-12,16,10),(0,0,3.1)),
        ('飞行底部','AIRBORNE',3,.90,math.pi/2,0,1,(-12,16,4.4),(0,0,5.0)),
        ('降落部署','DEPLOY',.10,0,.15,0,.35,(-12,16,10),(0,0,2.7)),
    ]
    for name,label,height,leg,ramp,door,engine,location,target in cases:
        scene.frame_set(7)
        pose(root,height,leg,ramp,door,engine)
        for node in grid.children:
            node.hide_render=label!='4 x 3 FOOTPRINT'
        camera.location=location
        target = (target[0], target[1], target[2]+.85) if name!='俯视占地' else target
        look_at(camera,target)
        font.body='BARRACKS '+VERSION.upper()+'  /  '+label+'\nACTUAL GLB MODEL PREVIEW'
        destination=os.path.join(PROJECT_ROOT,'assets','concept_art',f'兵营模型-{LABEL}-{name}-{VERSION}.png')
        # OpenImageIO can fail to overwrite non-ASCII Windows filenames.
        # Stage beside the destination, then use Python's Unicode-aware rename.
        scene.render.filepath=os.path.join(PROJECT_ROOT,'assets','concept_art','.barracks-v2-render.png')
        bpy.ops.render.render(write_still=True)
        os.replace(scene.render.filepath,destination)
        print('BARRACKS_V2_RENDER',name,destination)
    print('BARRACKS_V2_RENDER PASS six GLB views')
    pose(root,0,0,-.56,1,0)
    camera.location=(-12,16,11)
    look_at(camera,(0,0,3.55))
    font.body='BARRACKS V2  /  FLAG WIND LOOP\nACTUAL ANIMATED GLB PREVIEW'
    write_flag_animation(scene, os.path.join(PROJECT_ROOT,'assets','concept_art'))
    if VERSION == 'v3':
        scene.render.resolution_percentage = 100
        scene.frame_set(7)
        def save_view(name):
            scene.render.filepath=os.path.join(PROJECT_ROOT,'assets','concept_art','.barracks-v3-render.png')
            bpy.ops.render.render(write_still=True)
            os.replace(scene.render.filepath,os.path.join(PROJECT_ROOT,'assets','concept_art',f'兵营模型-轻度写实-{name}-v3.png'))
        camera_data.ortho_scale=8
        camera.location=(-10,-12,9)
        look_at(camera,(-2.5,-1.8,2.8))
        font.body=''
        save_view('推进器间隙近景')
        camera.location=(-9,13,7)
        look_at(camera,(1,2,2.5))
        save_view('入口材质近景')
        camera_data.ortho_scale=18.5
        camera.location=(-12,16,11)
        look_at(camera,(0,0,3.55))
        # Same camera and lighting as the v2 reference, not a flattering alternate setup.
        font.body='BARRACKS V3 / AFTER'
        save_view('对比后')
        floor=bpy.data.materials['StudioFloor'].node_tree.nodes.get('Principled BSDF')
        if floor is None:
            floor=next(n for n in bpy.data.materials['StudioFloor'].node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        old_color=tuple(floor.inputs['Base Color'].default_value)
        floor.inputs['Base Color'].default_value=(.36,.25,.13,1)
        background.inputs['Color'].default_value=(.30,.25,.19,1)
        font.body='BARRACKS V3 / DESERT LIGHT STUDY'
        save_view('荒漠光照')
        floor.inputs['Base Color'].default_value=old_color
        background.inputs['Color'].default_value=(.14,.17,.20,1)
        for obj in list(root.children_recursive)+[root]:
            bpy.data.objects.remove(obj,do_unlink=True)
        bpy.ops.import_scene.gltf(filepath=os.path.join(PROJECT_ROOT,'assets','concept_art','barracks_mechanical_v2','barracks_mechanical_v2.glb'))
        root=bpy.data.objects['BarracksMechanicalV2']
        pose(root,0,0,-.56,1,0)
        scene.frame_set(7)
        font.body='BARRACKS V2 / BEFORE'
        save_view('对比前')
        print('BARRACKS_REALISTIC_EXTRA PASS closeups neutral desert before-after')


if __name__=='__main__':
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
