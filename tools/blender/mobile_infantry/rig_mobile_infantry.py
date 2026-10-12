import sys as _sys
from pathlib import Path as _Path
_blender_tools = _Path(__file__).resolve().parents[1]
_sys.path[:0] = [str(_Path(__file__).resolve().parent), str(_blender_tools), str(_blender_tools / "shared")]
from project_paths import model_path
"""Independent mobile infantry rig and distance-calibrated baked actions.

Loads the archived v3 asset into an isolated scene, preserving the user's file.
No heavy-soldier skeleton, weights or animation data are used.
"""
import bpy
import json
import math
import os
import struct
import importlib.util
from mathutils import Vector, Matrix, Quaternion

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..'))
ARCHIVE = os.path.join(ROOT, 'assets/concept_art/mobile_infantry/archive-v3')
OUTPUT = os.path.join(ROOT, 'assets/models')
FPS = 30


def transform(head, tail, rest):
    rotation = (rest.to_quaternion() @ Vector((0, 1, 0))).rotation_difference((tail-head).normalized())
    return Matrix.Translation(head) @ rotation.to_matrix().to_4x4() @ rest.to_quaternion().to_matrix().to_4x4()


def build(source_path=None, report_path=None, version=4):
    previous = bpy.context.window.scene
    try:
        with bpy.data.libraries.load(source_path or os.path.join(ARCHIVE, 'mobile_infantry.blend'), link=False) as (source, target):
            target.scenes = list(source.scenes)
        scene = target.scenes[0]
        scene.name = 'MobileInfantry_Rigged_Source'
        bpy.context.window.scene = scene
        scene.render.fps = FPS
        objects = [o for o in scene.objects if o.type == 'MESH' and o.get('part_role') and not o.name.startswith('MI_High_')]
        assert len(objects) >= 10
        root = objects[0].parent
        root['asset_version'] = version
        root['asset_stage'] = 'rigged_game_asset'
        arm = bpy.data.objects.new('MobileInfantryRig', bpy.data.armatures.new('MobileInfantrySkeleton'))
        scene.collection.objects.link(arm)
        arm.parent = root
        arm.show_in_front = True
        for obj in scene.objects:
            obj.select_set(False)
        arm.select_set(True)
        scene.view_layers[0].objects.active = arm
        bpy.ops.object.mode_set(mode='EDIT')
        specs = {}

        def bone(name, head, tail, parent=None, deform=True):
            edit = arm.data.edit_bones.new(name)
            edit.head, edit.tail = head, tail
            edit.use_deform = deform
            if parent:
                edit.parent = arm.data.edit_bones[parent]
            specs[name] = (Vector(head), Vector(tail))

        bone('root', (0, 0, 0), (0, 0, .15))
        bone('pelvis', (0, 0, .94), (0, 0, 1.1), 'root')
        bone('spine', (0, 0, 1.1), (0, 0, 1.28), 'pelvis')
        bone('chest', (0, 0, 1.28), (0, 0, 1.48), 'spine')
        bone('neck', (0, 0, 1.48), (0, 0, 1.59), 'chest')
        bone('head', (0, 0, 1.59), (0, 0, 1.85), 'neck')
        gun_origin = Vector((-.025, -.287, 1.19))
        gun_rotation = Matrix.Rotation(math.radians(35), 4, 'Y')
        for side, sign in [('L', 1), ('R', -1)]:
            shoulder = Vector((sign*.246, 0, 1.429))
            elbow = Vector((.324, -.105, 1.166) if sign == 1 else (-.303, -.094, 1.174))
            hand = gun_origin + gun_rotation.to_3x3() @ Vector((.160, -.020, -.057) if sign == 1 else (-.085, -.009, -.107))
            bone('clavicle.'+side, (sign*.06, 0, 1.45), shoulder, 'chest')
            bone('upper_arm.'+side, shoulder, elbow, 'clavicle.'+side)
            bone('forearm.'+side, elbow, hand, 'upper_arm.'+side)
            bone('hand.'+side, hand, hand+Vector((0, -.08, 0)), 'forearm.'+side)
            hip, knee, ankle = (sign*.105, 0, .945), (sign*.157, -.015, .585), (sign*.18, .008, .205)
            bone('thigh.'+side, hip, knee, 'pelvis')
            bone('shin.'+side, knee, ankle, 'thigh.'+side)
            bone('foot.'+side, ankle, (sign*.18, -.10, .07), 'shin.'+side)
            bone('toe.'+side, (sign*.18, -.10, .07), (sign*.18, -.19, .07), 'foot.'+side)
            bone('CTRL_foot.'+side, ankle, (sign*.18, -.10, .205), 'root', False)
            bone('CTRL_knee.'+side, (sign*.16, -.55, .58), (sign*.16, -.55, .68), 'root', False)
            bone('CTRL_hand.'+side, hand, hand+Vector((0, -.08, 0)), 'root', False)
        bone('weapon', gun_origin, gun_origin+Vector((.15, 0, -.10)), 'hand.R')
        bpy.ops.object.mode_set(mode='OBJECT')
        rest = {b.name: b.matrix_local.copy() for b in arm.data.bones}
        # Socket-local offset, converted from Blender Z-up to glTF/Godot Y-up.
        coordinate = Matrix.Rotation(-math.pi/2, 4, 'X')
        # glTF joint bases keep Blender bone-local axes (C @ bone_rest), while
        # rigid weapon vertices use Y-up object axes (C @ vertex).
        weapon_mount = rest['weapon'].inverted() @ Matrix.Translation(gun_origin) @ gun_rotation @ coordinate.inverted()
        root['weapon_mount'] = [weapon_mount[row][column] for column in range(4) for row in range(3)]
        for p in arm.pose.bones:
            p.rotation_mode = 'QUATERNION'
        for side in ['L', 'R']:
            for member, ctrl in [('shin', 'foot'), ('forearm', 'hand')]:
                ik = arm.pose.bones[member+'.'+side].constraints.new('IK')
                ik.name = 'Authoring IK (enable to edit; export actions are baked)'
                ik.target = arm
                ik.subtarget = 'CTRL_'+ctrl+'.'+side
                ik.chain_count = 2
                ik.mute = True
                if member == 'shin':
                    ik.pole_target = arm
                    ik.pole_subtarget = 'CTRL_knee.'+side

        def weights(role, point):
            side = 'L' if point.x >= 0 else 'R'
            def smooth(value):
                t = max(0.0,min(1.0,value))
                return t*t*(3-2*t)
            if role == 'ContinuousBody':
                z = point.z
                if z > 1.13:
                    t = smooth((z-1.13)/.20)
                    return {'spine':1-t,'chest':t}
                if z > 1.00:
                    t = smooth((z-1.00)/.13)
                    return {'pelvis':1-t,'spine':t}
                if z > .84:
                    if abs(point.x)<.025:
                        return {'pelvis':1.0}
                    t = smooth((z-.84)/.16)
                    if abs(point.x)<.045:
                        t = max(t,.8)
                    return {'pelvis':t,'thigh.'+side:1-t}
                if z > .49:
                    t = smooth((z-.49)/.18)
                    return {'thigh.'+side:t,'shin.'+side:1-t}
                t = smooth((z-.20)/.10)
                return {'shin.'+side:t,'foot.'+side:1-t}
            if role.startswith('ContinuousSleeve'):
                side = role[-1]
                shoulder, elbow = specs['upper_arm.'+side]
                wrist = specs['forearm.'+side][1]
                upper = elbow-shoulder
                lower = wrist-elbow
                # A continuous bisector field avoids hard nearest-segment switches
                # on adjacent inner-elbow vertices when the rifle is raised.
                axis = (upper.normalized()+lower.normalized()).normalized()
                t = smooth(.5+(point-elbow).dot(axis)/.16)
                hand = smooth(1+(point-wrist).dot(lower.normalized())/.06)
                return {'upper_arm.'+side:1-t,'forearm.'+side:t*(1-hand),'hand.'+side:t*hand}
            if role.startswith(('Rifle_',)):
                return {'weapon': 1.0}
            if role.startswith(('Helmet', 'Visor', 'Respirator', 'Cheek', 'Ear')):
                return {'head': 1.0}
            if role == 'NeckSeal':
                return {'neck': 1.0}
            if role.startswith(('ShoulderArmor', 'SleeveUpper')):
                side = role[-1]
                if role.startswith('Shoulder'):
                    return {'upper_arm.'+side: 1.0}
                elbow = specs['forearm.'+side][0]
                mix = max(0, min(.45, (.07-(point-elbow).length)/.14))
                return {'upper_arm.'+side: 1-mix, 'forearm.'+side: mix}
            if role.startswith(('SleeveFore', 'ForearmArmor', 'ElbowGuard')):
                return {'forearm.'+role[-1]: 1.0}
            if role.startswith('Glove'):
                return {'hand.'+role[-1]: 1.0}
            if role.startswith(('Boot', 'Ankle')):
                return {'foot.'+side: 1.0}
            if role.startswith('Knee'):
                return {'shin.'+side: 1.0}
            if role.startswith('TrouserCalf'):
                blend = max(0, min(.45, (point.z-.50)/.20))
                return {'shin.'+side: 1-blend, 'thigh.'+side: blend}
            if role.startswith('TrouserThigh'):
                bottom = max(0, min(.45, (.65-point.z)/.18))
                top = max(0, min(.4, (point.z-.85)/.24))
                return {'thigh.'+side: 1-bottom-top, 'shin.'+side: bottom, 'pelvis': top}
            if role.startswith(('Thigh', 'SideThigh', 'PouchFlap')):
                return {'thigh.'+side: 1.0}
            if role == 'TorsoUndersuit':
                t = max(0, min(1, (point.z-1.13)/.18))
                return {'spine': 1-t, 'chest': t}
            if role.startswith(('UpperChest', 'Chest', 'BackArmor', 'ShoulderHarness', 'BackHarness')):
                return {'chest': 1.0}
            if role == 'AbdomenPlate':
                return {'spine': 1.0}
            return {'pelvis': 1.0}

        for obj in objects:
            for vertex in obj.data.vertices:
                assignment = weights(obj['part_role'], obj.matrix_world @ vertex.co)
                assert abs(sum(assignment.values())-1) < 1e-5
                for name, amount in assignment.items():
                    if amount > 0:
                        group = obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
                        group.add([vertex.index], amount, 'REPLACE')
            modifier = obj.modifiers.new('MobileInfantrySkin', 'ARMATURE')
            modifier.object = arm
        for obj in scene.objects:
            obj.select_set(False)
        for obj in objects:
            obj.select_set(True)
        scene.view_layers[0].objects.active = objects[0]
        bpy.ops.object.join()
        mesh = bpy.context.object
        mesh.name = 'MobileInfantryMesh'
        mesh.parent = arm
        mesh.matrix_parent_inverse = arm.matrix_world.inverted()
        assert all(len(p.vertices) == 4 for p in mesh.data.polygons)
        assert all(v.groups for v in mesh.data.vertices)

        def set_leg(side, ankle):
            thigh = arm.pose.bones['thigh.'+side]
            shin = arm.pose.bones['shin.'+side]
            foot = arm.pose.bones['foot.'+side]
            pelvis_delta = arm.pose.bones['pelvis'].matrix @ rest['pelvis'].inverted()
            hip = pelvis_delta @ specs['thigh.'+side][0]
            length_a = (specs['thigh.'+side][1]-specs['thigh.'+side][0]).length
            length_b = (specs['shin.'+side][1]-specs['shin.'+side][0]).length
            direction = ankle-hip
            distance = min(direction.length, length_a+length_b-.001)
            direction.normalize()
            along = (length_a**2-length_b**2+distance**2)/(2*distance)
            pole = Vector((0, -1, 0))
            pole = (pole-direction*pole.dot(direction)).normalized()
            knee = hip+direction*along+pole*math.sqrt(max(0, length_a**2-along**2))
            thigh.matrix = transform(hip, knee, rest[thigh.name])
            scene.view_layers[0].update()
            shin.matrix = transform(knee, ankle, rest[shin.name])
            scene.view_layers[0].update()
            foot.matrix = Matrix.Translation(ankle) @ rest[foot.name].to_quaternion().to_matrix().to_4x4()
            control = arm.pose.bones['CTRL_foot.'+side]
            control.matrix = Matrix.Translation(ankle) @ rest[control.name].to_quaternion().to_matrix().to_4x4()

        def aim_weapon(recoil):
            new_origin = Vector((-.10, -.29 + recoil*.3, 1.36))
            delta = Matrix.Rotation(-math.pi/2, 4, 'Z') @ gun_rotation.inverted()
            weapon_delta = Matrix.Translation(new_origin) @ delta @ Matrix.Translation(-gun_origin)
            for side, sign in [('L', 1), ('R', -1)]:
                upper = arm.pose.bones['upper_arm.'+side]
                fore = arm.pose.bones['forearm.'+side]
                hand = arm.pose.bones['hand.'+side]
                start = upper.matrix.translation.copy()
                goal = weapon_delta @ specs[hand.name][0]
                a = (specs[upper.name][1]-specs[upper.name][0]).length
                b = (specs[fore.name][1]-specs[fore.name][0]).length
                direction = goal-start
                distance = min(direction.length, a+b-.001)
                direction.normalize()
                along = (a*a-b*b+distance*distance)/(2*distance)
                pole = Vector((sign*.5, .25, -1))
                pole = (pole-direction*pole.dot(direction)).normalized()
                elbow = start+direction*along+pole*math.sqrt(max(0, a*a-along*along))
                upper.matrix = transform(start, elbow, rest[upper.name])
                scene.view_layers[0].update()
                fore.matrix = transform(elbow, goal, rest[fore.name])
                scene.view_layers[0].update()
                hand.matrix = weapon_delta @ rest[hand.name]
                arm.pose.bones['CTRL_hand.'+side].matrix = weapon_delta @ rest['CTRL_hand.'+side]
                scene.view_layers[0].update()
            arm.pose.bones['weapon'].matrix = weapon_delta @ rest['weapon']

        actions = {}
        for name, duration in [('RESET', 1/FPS), ('idle', 2.4), ('walk', 1.0), ('jog', .6), ('fire', .3), ('death', 1.2)]:
            action = bpy.data.actions.new(name)
            action.use_fake_user = True
            arm.animation_data_create()
            arm.animation_data.action = action
            frames = max(1, round(duration*FPS))
            for frame in range(frames+1):
                scene.frame_set(frame)
                t = frame/frames
                for pose in arm.pose.bones:
                    pose.matrix_basis = Matrix.Identity(4)
                pelvis = arm.pose.bones['pelvis']
                if name == 'idle':
                    pelvis.location.y = .0025*math.sin(t*math.tau)
                    arm.pose.bones['chest'].rotation_quaternion = Quaternion((1, 0, 0), .008*math.sin(t*math.tau))
                elif name in ['walk', 'jog']:
                    jog = name == 'jog'
                    pelvis.location.y = (-.065 if jog else -.035) + (.009 if jog else .006)*math.cos(t*math.tau*2)
                    arm.pose.bones['chest'].rotation_quaternion = Quaternion((1, 0, 0), .065 if jog else .025)
                    scene.view_layers[0].update()
                    for side, sign, offset in [('L', 1, 0), ('R', -1, .5)]:
                        phase = (t+offset)%1
                        stance = .42 if jog else .60
                        stride = 1.50 if jog else .80
                        travel = stride*stance
                        if phase < stance:
                            forward = -.5*travel+travel*phase/stance
                            lift = 0
                        else:
                            u = (phase-stance)/(1-stance)
                            smooth = u*u*(3-2*u)
                            forward = .5*travel-travel*smooth
                            lift = (.125 if jog else .075)*math.sin(math.pi*u)**1.4
                        set_leg(side, Vector((sign*.18, .008+forward, .205+lift)))
                elif name == 'fire':
                    recoil = math.sin(min(t/.25, 1)*math.pi)*.06 if t < .25 else 0
                    arm.pose.bones['chest'].rotation_quaternion = Quaternion((1, 0, 0), -recoil)
                    scene.view_layers[0].update()
                    aim_weapon(recoil)
                elif name == 'death':
                    smooth = t*t*(3-2*t)
                    arm.pose.bones['root'].rotation_quaternion = Quaternion((0, 0, 1), -1.47*smooth)
                    arm.pose.bones['root'].location.y = .035*smooth
                    arm.pose.bones['spine'].rotation_quaternion = Quaternion((1, 0, 0), .25*math.sin(t*math.pi))
                scene.view_layers[0].update()
                for pose in arm.pose.bones:
                    pose.keyframe_insert('location', frame=frame, group=pose.name)
                    pose.keyframe_insert('rotation_quaternion', frame=frame, group=pose.name)
            actions[name] = action
        # NLA export strips explicitly name clips, avoiding an all-actions merge.
        arm.animation_data.action = None
        for name, action in actions.items():
            track = arm.animation_data.nla_tracks.new()
            track.name = name
            track.strips.new(name, 0, action)
            track.mute = True
        scene.frame_set(0)
        for pose in arm.pose.bones:
            pose.matrix_basis = Matrix.Identity(4)
        scene.view_layers[0].update()
        for obj in scene.objects:
            obj.select_set(False)
        for obj in [root, arm, mesh]:
            obj.select_set(True)
        scene.view_layers[0].objects.active = arm
        skin_audit = {}
        if version >= 5:
            spec = importlib.util.spec_from_file_location('mi_skin_audit', os.path.join(os.path.dirname(__file__), 'audit_mobile_infantry_skin.py'))
            audit_module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(audit_module)
            skin_audit = audit_module.audit({'scene':scene,'arm':arm,'mesh':mesh,'actions':actions})
        bpy.ops.export_scene.gltf(filepath=str(model_path('mobile_infantry.glb')), export_format='GLB', use_selection=True,
            use_active_scene=True, export_yup=True, export_animations=True, export_animation_mode='ACTIONS',
            export_force_sampling=True, export_def_bones=True, export_extras=True, export_image_format='AUTO')
        # Blender datablocks may gain suffixes in an occupied user session.
        # Keep the exported animation contract stable without renaming user data.
        path = str(model_path('mobile_infantry.glb'))
        with open(path, 'rb') as stream:
            raw = stream.read()
        json_length = struct.unpack_from('<I', raw, 12)[0]
        document = json.loads(raw[20:20+json_length])
        names = {action.name: name for name, action in actions.items()}
        document['animations'] = [animation for animation in document.get('animations', []) if animation['name'] in names]
        assert len(document['animations']) == 6, [a['name'] for a in document['animations']]
        for animation in document['animations']:
            animation['name'] = names[animation['name']]
        chunk = json.dumps(document, separators=(',', ':')).encode('utf-8')
        chunk += b' ' * ((-len(chunk)) % 4)
        tail = raw[20+json_length:]
        with open(path, 'wb') as stream:
            stream.write(struct.pack('<III', 0x46546C67, 2, 20+len(chunk)+len(tail)))
            stream.write(struct.pack('<II', len(chunk), 0x4E4F534A))
            stream.write(chunk)
            stream.write(tail)
        bpy.data.libraries.write(str(model_path('source/mobile_infantry.blend')), {scene}, fake_user=True, compress=True)
        report = json.load(open(report_path or os.path.join(ARCHIVE, 'mobile_infantry_report.json'), encoding='utf-8'))
        report.update(version=version, stage='rigged_game_asset', animation_included=True, production_integrated=True,
                      rig_bones=len(arm.data.bones), deform_bones=sum(b.use_deform for b in arm.data.bones),
                      actions=list(actions), walk_stride_m=.80, jog_stride_m=1.50, source_quads=len(mesh.data.polygons),
                      expected_export_triangles=len(mesh.data.polygons)*2, export_triangles=len(mesh.data.polygons)*2,
                      rig_origin='independently authored mobile infantry rig; source revision %d' % version)
        report.update(skin_audit)
        report['weapon_mount'] = list(root['weapon_mount'])
        for file in [str(model_path('source/mobile_infantry_report.json')), os.path.join(ROOT, 'assets/concept_art/mobile_infantry/asset_report.json')]:
            with open(file, 'w', encoding='utf-8') as stream:
                json.dump(report, stream, ensure_ascii=False, indent=2)
        bpy.app.driver_namespace['mi_rig'] = {'scene': scene, 'arm': arm, 'mesh': mesh, 'root': root, 'actions': actions}
        return report
    finally:
        if bpy.context.object and bpy.context.object.mode != 'OBJECT':
            bpy.ops.object.mode_set(mode='OBJECT')
        bpy.context.window.scene = previous


if __name__ == '__main__':
    build()
