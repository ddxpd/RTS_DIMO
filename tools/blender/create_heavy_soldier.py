"""Rebuild only the soldier in the shared source; all coordinates below are Y-up."""
import os
import sys
import math
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import create_soldier_and_bullet as base

parts = []


def xyz(p):
    return (p[0], -p[2], p[1])


def bind(obj, bone):
    obj.vertex_groups.new(name=bone).add(list(range(len(obj.data.vertices))), 1.0, 'REPLACE')
    parts.append(obj)
    return obj


def block(name, pos, size, mat, bone, bevel=0.035):
    return bind(base.cube(name, (size[0], size[2], size[1]), xyz(pos), mat, bevel=bevel), bone)


def oval(name, pos, size, mat, bone):
    obj = base.sphere(name, (size[0], size[2], size[1]), xyz(pos), mat)
    for face in obj.data.polygons:
        face.use_smooth = True
    return bind(obj, bone)


def segment(name, a, b, width, depth, mat, bone):
    mid = (Vector(a) + Vector(b)) * 0.5
    obj = base.cone(name, width, width * 0.86, (Vector(b)-Vector(a)).length,
                    xyz(mid), mat, vertices=12)
    obj.rotation_euler = Vector(xyz(Vector(b)-Vector(a))).to_track_quat('Z','Y').to_euler()
    obj.scale.y = depth / width
    return bind(obj, bone)


def plate(name, pos, rings, mat, bone):
    # Chamfered octagonal cross sections, tapered along body height.
    vertices = []
    for height, width, depth in rings:
        for x, z in [(-.7,-1),(.7,-1),(1,-.65),(1,.65),(.7,1),(-.7,1),(-1,.65),(-1,-.65)]:
            vertices.append(xyz((pos[0]+x*width/2, pos[1]+height, pos[2]+z*depth/2)))
    faces = [tuple(reversed(range(8)))]
    for i in range(len(rings)-1):
        for j in range(8):
            faces.append((i*8+j,i*8+(j+1)%8,(i+1)*8+(j+1)%8,(i+1)*8+j))
    faces.append(tuple(range((len(rings)-1)*8,len(rings)*8)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    base.assign(obj, mat)
    bevel = obj.modifiers.new('Armor bevel', 'BEVEL')
    bevel.width = .016
    bevel.segments = 2
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return bind(obj, bone)


def build():
    base.ensure_source_blend()
    base.remove_hierarchy('soldier')
    root = base.empty('soldier')
    root['reference'] = '士兵重设计-03-重装步兵-v1.png'
    root['rig_version'] = 2
    root['stride_world_units'] = 56.0
    armor = base.material('Heavy_Ceramic', (.58,.61,.62), .28, .56)
    trim = base.material('Heavy_Edge', (.30,.34,.37), .55, .42)
    cloth = base.material('Heavy_Fabric', (.065,.079,.09), .0, .85)
    rubber = base.material('Heavy_Rubber', (.025,.032,.04), .05, .8)
    faction = base.material('Heavy_FactionPaint', (.1,.38,.85), .12, .5)
    visor = base.material('Heavy_Visor', (.03,.19,.30), .35, .25, (.05,.45,.8), 1.1)
    points = {'Pelvis': (0,1.27,0), 'Spine': (0,1.57,0), 'Head': (0,2.30,0),
              'Weapon': (.17,1.77,.65)}
    parents = {'Pelvis': None, 'Spine':'Pelvis', 'Head':'Spine', 'Weapon':'Spine'}
    for suffix, sign in [('L',-1),('R',1)]:
        points.update({f'Thigh_{suffix}':(.22*sign,1.27,0), f'Shin_{suffix}':(.22*sign,.70,.04),
                       f'Foot_{suffix}':(.22*sign,.16,0), f'UpperArm_{suffix}':(.47*sign,2.12,0),
                       f'Forearm_{suffix}':(.56*sign,1.74,.23),
                       f'Hand_{suffix}': ((-.04,1.79,.90) if sign<0 else (.20,1.73,.57))})
        parents.update({f'Thigh_{suffix}':'Pelvis',f'Shin_{suffix}':f'Thigh_{suffix}',
                        f'Foot_{suffix}':f'Shin_{suffix}',f'UpperArm_{suffix}':'Spine',
                        f'Forearm_{suffix}':f'UpperArm_{suffix}',f'Hand_{suffix}':f'Forearm_{suffix}'})
    arm_data = bpy.data.armatures.new('HeavySkeleton')
    rig = bpy.data.objects.new('HeavyRig', arm_data)
    bpy.context.collection.objects.link(rig)
    rig.parent = root
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for name, p in points.items():
        bone = arm_data.edit_bones.new(name)
        bone.head = xyz(p)
        bone.tail = xyz((p[0],p[1]+.16,p[2]))
        if parents[name]:
            bone.parent = arm_data.edit_bones[parents[name]]
    bpy.ops.object.mode_set(mode='OBJECT')

    oval('Torso suit',(0,1.91,0),(.80,.77,.43),cloth,'Spine')
    plate('Breastplate',(0,1.64,.055),[(0,.57,.39),(.26,.87,.54),(.49,.91,.50),(.60,.68,.41)],armor,'Spine')
    plate('Upper chest',(0,2.08,.28),[(0,.60,.08),(.16,.72,.11),(.22,.58,.05)],trim,'Spine')
    for i in range(3):
        plate('Abdominal overlap',(0,1.47+i*.075,.17),[(0,.49,.12),(.085,.55,.14)],trim,'Spine')
    oval('Pelvis',(0,1.27,0),(.60,.33,.40),cloth,'Pelvis')
    block('Belt',(0,1.43,0),(.67,.10,.43),rubber,'Pelvis')
    for x in [-.26,0,.26]:
        block('Ammo pouch',(x,1.42,.27),(.18,.23,.15),trim,'Pelvis',.02)
    block('Backpack',(0,1.96,-.32),(.52,.55,.21),trim,'Spine',.07)
    block('Backpack panel',(0,2.0,-.44),(.36,.33,.035),armor,'Spine',.03)
    oval('Neck',(0,2.28,0),(.28,.20,.29),rubber,'Head')
    oval('Helmet',(0,2.51,0),(.48,.51,.47),armor,'Head')
    plate('Mask',(0,2.30,.15),[(0,.20,.18),(.15,.39,.24),(.28,.40,.18)],trim,'Head')
    block('Visor band',(0,2.57,.221),(.37,.083,.05),visor,'Head',.018)
    block('Helmet crown',(0,2.74,-.02),(.19,.05,.30),trim,'Head',.02)
    for suffix, sign in [('L',-1),('R',1)]:
        thigh, shin, foot = [points[f'{n}_{suffix}'] for n in ['Thigh','Shin','Foot']]
        upper, elbow, hand = [points[f'{n}_{suffix}'] for n in ['UpperArm','Forearm','Hand']]
        segment('Thigh suit',thigh,shin,.16,.16,cloth,f'Thigh_{suffix}')
        plate('Thigh armor',(.22*sign,.84,.04),[(0,.28,.29),(.24,.34,.36),(.40,.33,.33)],armor,f'Thigh_{suffix}')
        oval('Knee joint',shin,(.27,.24,.27),rubber,f'Shin_{suffix}')
        plate('Knee cap',(.22*sign,.61,.19),[(0,.22,.13),(.17,.29,.17),(.23,.21,.12)],trim,f'Shin_{suffix}')
        segment('Calf suit',shin,foot,.13,.14,cloth,f'Shin_{suffix}')
        plate('Shin armor',(.22*sign,.23,.045),[(0,.26,.29),(.23,.32,.36),(.35,.30,.32)],armor,f'Shin_{suffix}')
        block('Boot sole',(.22*sign,.045,.11),(.31,.09,.48),rubber,f'Foot_{suffix}',.022)
        block('Boot upper',(.22*sign,.16,.09),(.28,.18,.43),trim,f'Foot_{suffix}',.06)
        plate('Boot toe',(.22*sign,.10,.25),[(0,.28,.21),(.12,.25,.18)],armor,f'Foot_{suffix}')
        segment('Upper sleeve',upper,elbow,.13,.14,cloth,f'UpperArm_{suffix}')
        plate('Shoulder shell',(.49*sign,1.99,-.015),[(0,.30,.40),(.15,.40,.44),(.28,.27,.33)],armor,f'UpperArm_{suffix}')
        block('Team shoulder',(.49*sign,2.14,.221),(.22,.072,.025),faction,f'UpperArm_{suffix}',.009)
        oval('Elbow',elbow,(.23,.23,.23),rubber,f'Forearm_{suffix}')
        segment('Forearm',elbow,hand,.135,.13,armor,f'Forearm_{suffix}')
        oval('Glove',hand,(.19,.18,.22),rubber,f'Hand_{suffix}')
        for finger in range(4):
            block('Finger',(hand[0]-.045+finger*.03,hand[1]-.055,hand[2]+.08),(.025,.055,.08),trim,f'Hand_{suffix}',.009)
    block('Rifle receiver',(.17,1.85,.70),(.15,.17,.58),trim,'Weapon',.025)
    block('Rifle stock',(.17,1.86,.30),(.13,.16,.26),rubber,'Weapon',.025)
    block('Rifle handguard',(.17,1.83,1.0),(.16,.15,.28),armor,'Weapon',.02)
    segment('Rifle barrel',(.17,1.84,1.1),(.17,1.84,1.34),.034,.034,trim,'Weapon')
    block('Rifle magazine',(.17,1.65,.76),(.15,.22,.20),rubber,'Weapon',.015)
    block('Rifle grip',(.17,1.72,.52),(.10,.20,.12),rubber,'Weapon',.02)
    block('Rifle sight',(.17,1.975,.70),(.08,.07,.13),rubber,'Weapon',.013)

    # One skinned draw object; materials remain independently tintable.
    mesh = base.join_meshes('HeavySoldierMesh', parts)
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    mesh.parent = rig
    modifier = mesh.modifiers.new('Heavy skin','ARMATURE')
    modifier.object = rig
    base.empty('Muzzle', xyz((.17,1.84,1.36)), root)
    bpy.context.view_layer.update()
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=base.SOURCE_BLEND)
    bpy.ops.object.select_all(action='DESELECT')
    root.select_set(True)
    for obj in root.children_recursive:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=base.SOLDIER_GLB, export_format='GLB', use_selection=True,
                              export_animations=False, export_skins=True, export_yup=True)
    print('HEAVY_SOLDIER_BUILD PASS', len(mesh.data.polygons), 'polygons', len(arm_data.bones), 'bones')


if __name__ == '__main__':
    build()
