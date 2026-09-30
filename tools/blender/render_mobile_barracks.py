"""Render repeatable states of the final GLB; never save the preview scene."""
import math
import os
import sys
import bpy

sys.path.insert(0, os.path.dirname(__file__))
sys.dont_write_bytecode = True
from create_bunker import PROJECT_ROOT, material
from render_bunker_preview import look_at, make_area


def pose(root, height, retraction, ramp, door, engines):
    root.location.z = height
    for suffix in ['LFront', 'LRear', 'RFront', 'RRear']:
        bpy.data.objects['LandingLeg' + suffix].location.z = retraction
    ramp_node = bpy.data.objects['DeploymentRamp']
    ramp_node.rotation_mode = 'XYZ'
    ramp_node.rotation_euler.x = ramp
    for suffix, sign in [('L', -1), ('R', 1)]:
        bpy.data.objects['BarracksDoor' + suffix].location.x = -1.25 + sign * .90 * door
    exhaust = bpy.data.objects['ThrusterGlow']
    # Shorten plumes about each fixed nozzle, never shrink their XY spacing.
    exhaust.scale = (1, 1, engines) if engines > .01 else (.001,) * 3
    exhaust.location.z = .35 * (1 - engines) if engines > .01 else 0
    bpy.context.view_layer.update()


def main():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=os.path.join(PROJECT_ROOT, 'assets', 'models', 'barracks.glb'))
    root = bpy.data.objects['barracks']
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.025))
    bpy.context.object.data.materials.append(material('PreviewGround', (.15, .17, .19), .1, .78))
    camera_data = bpy.data.cameras.new('PreviewCamera')
    camera = bpy.data.objects.new('PreviewCamera', camera_data)
    bpy.context.collection.objects.link(camera)
    camera_data.type = 'ORTHO'
    camera_data.ortho_scale = 14.4
    scene = bpy.context.scene
    scene.camera = camera
    make_area('Key', (-7, 8, 13), 2400, 8, (1, .94, .85))
    make_area('Fill', (9, 3, 8), 1500, 7, (.68, .82, 1))
    make_area('Rim', (0, -8, 11), 2600, 6, (.8, .9, 1))
    make_area('Underfill', (1, 8, 2), 350, 5, (.65, .8, 1))
    background = scene.world.node_tree.nodes.get('Background')
    background.inputs['Color'].default_value = (.20, .23, .27, 1)
    background.inputs['Strength'].default_value = .45
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = 1536
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    cases = [
        ('落地主视角', 0, 0, -.48, 1, .001, (11, 15, 10), (0, 0, 2.2)),
        ('背侧结构', 0, 0, -.48, 0, .001, (-11, -15, 10), (0, 0, 2.2)),
        ('升空过渡', 1.1, .32, 1.25, 0, .85, (11, 15, 10), (0, 0, 2.6)),
        ('飞行底部', 3.4, .62, math.pi / 2, 0, 1, (11, 15, 3.6), (0, 0, 4.8)),
        ('降落部署', .12, 0, .15, 0, .45, (11, 15, 10), (0, 0, 2.2)),
    ]
    for name, height, leg, ramp, door, engine, location, target in cases:
        pose(root, height, leg, ramp, door, engine)
        camera.location = location
        look_at(camera, target)
        scene.render.filepath = os.path.join(PROJECT_ROOT, 'assets', 'concept_art', '兵营模型-方案一-' + name + '-v1.png')
        bpy.ops.render.render(write_still=True)
        print('BARRACKS_RENDER', name, scene.render.filepath)
    print('BARRACKS_RENDER PASS five final-GLB previews')


if __name__ == '__main__':
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
