"""Underfloor lift system and articulated landing gear for the isolated v4 study."""
import math
import bpy
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
from create_bunker import empty, cube, cylinder, cone, torus
from create_barracks_mechanical_preview import bar, mesh_object, merge, actuator

SUFFIXES = ['LFront', 'LRear', 'RFront', 'RRear']


def subtract(obj, cutter):
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new('Equipment cavity', 'BOOLEAN')
    mod.operation = 'DIFFERENCE'
    mod.solver = 'EXACT'
    mod.object = cutter
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def build_underbody(root, hull, armor, steel, dark, black, silver, yellow, thrust):
    root['underbody'] = True
    root['housing_clearance_checked'] = 'Complete power housing; four underfloor wells and separate gear bays'
    deck = cube('UnderChassis', (8.9, 5.85, .47), (0, -.22, .655), dark, hull, .06)
    # Structural members route between the engine wells instead of across them.
    for x in [-4.25, 0, 4.25]:
        cube('UnderSpine', (.16, 4.30, .15), (x, -.18, .41), steel, hull, .025)
    cube('UnderCrossmember', (8.35, .18, .14), (0, 0, .40), steel, hull, .025)
    for side in [-1, 1]:
        for end in [-1, 1]:
            suffix = ('L' if side < 0 else 'R') + ('Front' if end > 0 else 'Rear')
            x, y = side*2.85, end*1.60
            cutter = cylinder('EngineWellCut', .71, 1.4, (x, y, .60), dark, 48, hull)
            bpy.context.view_layer.update()
            subtract(deck, cutter)
            cutter = cube('GearBayCut', (1.70, .86, 1.1), (side*3.65, end*2.80, .50), dark, hull, 0)
            bpy.context.view_layer.update()
            subtract(deck, cutter)
            # The top mounting plate closes the engine compartment above the hollow nozzle.
            cube('EngineWellRoof', (1.14, 1.14, .10), (x, y, .88), steel, hull, .035)
            pod = empty('LiftPod'+suffix, (x, y, 0), root)
            rings = [(.82,.43),(.45,.56),(.27,.56),(.27,.47),(.78,.32)]
            vertices = [(math.cos(i*math.tau/32)*r, math.sin(i*math.tau/32)*r, z)
                        for z,r in rings for i in range(32)]
            faces = [(j*32+i,j*32+(i+1)%32,(j+1)*32+(i+1)%32,(j+1)*32+i)
                     for j in range(len(rings)-1) for i in range(32)]
            mesh_object('UnderNozzle', vertices, faces, dark, pod, 0)
            torus('UnderNozzleLip', .52, .035, (0,0,.29), steel, pod)
            cylinder('UnderNozzleThroat', .32, .04, (0,0,.80), black, 24, pod)
            for i in range(8):
                a = i*math.tau/8
                bar('UnderNozzleRib', (.46*math.cos(a),.46*math.sin(a),.70),
                    (.57*math.cos(a),.57*math.sin(a),.32), .018, steel, pod)
            merge(pod)
            jet = empty('Jet'+suffix, (x,y,.31), root)
            cone('ExhaustCore', .025,.36,1.25,(0,0,-.625),thrust,24,jet)
            merge(jet)
            jet.scale = (.001,)*3
            hip = (side*4.15, end*2.75, .78)
            # A real open storage bay, with a roof and bearing rather than a solid box.
            cube('GearBayRoof', (1.43,.79,.08), (side*3.73,end*2.75,.94), steel, hull, .025)
            cylinder('GearBearing', .13,.28, hip, silver, 20, hull, rotation=(math.pi/2,0,0))
            arm = empty('Leg'+suffix, hip, root)
            bar('GearSwingArm',(0,0,0),(side*.60,0,-.32),.095,steel,arm)
            cylinder('GearKnee',.12,.22,(side*.60,0,-.32),silver,16,arm,rotation=(math.pi/2,0,0))
            merge(arm)
            # Separate telescopic cylinder and piston remain vertical through the knee hinge.
            cylinder('GearBarrel'+suffix,.095,1,(0,0,0),dark,16,root)
            cylinder('GearRod'+suffix,.055,1,(0,0,0),silver,16,root)
            foot = empty('Foot'+suffix, (0,0,0), root)
            cube('GearFootRubber',(.72,.64,.14),(0,0,0),black,foot,.025)
            cube('GearFootArmor',(.62,.54,.04),(0,0,.087),steel,foot,.012)
            cube('GearFootMark',(.07,.34,.015),(side*.26,0,.114),yellow,foot,.005)
            merge(foot)
    bpy.context.view_layer.update()


def pose_underbody(root, height, retraction, ramp_angle, doors, engine):
    root.location.z = height
    progress = max(0, min(1, retraction/.9))
    for suffix in SUFFIXES:
        side = -1 if suffix.startswith('L') else 1
        end = 1 if suffix.endswith('Front') else -1
        hip = Vector((side*4.15,end*2.75,.78))
        rotation = side*2.53*progress
        arm = bpy.data.objects['Leg'+suffix]
        arm.rotation_mode = 'XYZ'
        arm.rotation_euler.y = rotation
        knee = hip + Matrix.Rotation(rotation, 3, 'Y') @ Vector((side*.60,0,-.32))
        extension = .36*(1-progress)+.06*progress
        ankle = knee-Vector((0,0,extension))
        split = knee.lerp(ankle,.55)
        actuator(bpy.data.objects['GearBarrel'+suffix], knee, split, .095)
        actuator(bpy.data.objects['GearRod'+suffix], split, ankle, .055)
        foot = bpy.data.objects['Foot'+suffix]
        foot.location = ankle
        foot.rotation_mode = 'XYZ'
        foot.rotation_euler.y = side*.22*math.sin(math.pi*progress)
        jet = bpy.data.objects['Jet'+suffix]
        jet.scale = (1,1,engine) if engine > .01 else (.001,)*3
    ramp = bpy.data.objects['Ramp']
    # Set the hinge just outside the doorway so its complete swing stays in 4x3 cells.
    ramp.location.y = 2.38
    ramp.rotation_mode = 'XYZ'
    ramp.rotation_euler.x = ramp_angle
    for side in [-1,1]:
        bpy.data.objects['Door'+('L' if side<0 else 'R')].location.x = 1.03+side*1.30*doors
        a = Vector((1.03+side*1.59,2.26,1.77))
        b = Vector((1.03+side*1.45,2.38+math.cos(ramp_angle)*1.10,.96+math.sin(ramp_angle)*1.10))
        middle = a.lerp(b,.60)
        actuator(bpy.data.objects['RampCylinder'+str(side)],a,middle,.073)
        actuator(bpy.data.objects['RampRod'+str(side)],middle,b,.038)
    bpy.context.view_layer.update()


def smooth(t):
    t = max(0, min(1, t))
    return t*t*(3-2*t)


def flight_pose(root, seconds, landing=False):
    t = 4-seconds if landing else seconds
    close = smooth(t/.8)
    lift = 3*smooth((t-.8)/2.4)
    retract = .9*smooth((t-1.6)/1.2)
    engine = smooth((t-.6)/.4)
    pose_underbody(root,lift,retract,-.56+(math.pi/2+.56)*close,1-close,engine)


def bounds(obj):
    points = [obj.matrix_world @ Vector(p) for p in obj.bound_box]
    return [min(p[i] for p in points) for i in range(3)], [max(p[i] for p in points) for i in range(3)]


def validate_motion(root):
    meshes = [o for o in root.children_recursive if o.type == 'MESH' and not o.name.startswith('Jet')]
    hull = bpy.data.objects['HullMesh']
    def bvh(obj):
        return BVHTree.FromPolygons([obj.matrix_world @ v.co for v in obj.data.vertices],
                                   [list(p.vertices) for p in obj.data.polygons])
    overlaps = []
    min_ground = 100
    for frame in range(97):
        flight_pose(root,frame/24)
        hull_tree = bvh(hull)
        for suffix in SUFFIXES:
            foot = bpy.data.objects['Foot'+suffix+'Mesh']
            foot_tree = bvh(foot)
            if foot_tree.overlap(hull_tree):
                overlaps.append((frame,suffix,'foot/hull'))
            if foot_tree.overlap(bvh(bpy.data.objects['LiftPod'+suffix+'Mesh'])):
                overlaps.append((frame,suffix,'foot/nozzle'))
            nozzle_tree = bvh(bpy.data.objects['LiftPod'+suffix+'Mesh'])
            if nozzle_tree.overlap(hull_tree):
                overlaps.append((frame,suffix,'nozzle/hull'))
            for name in ['Leg'+suffix+'Mesh','GearBarrel'+suffix,'GearRod'+suffix]:
                part_tree = bvh(bpy.data.objects[name])
                if part_tree.overlap(nozzle_tree):
                    overlaps.append((frame,suffix,name+'/nozzle'))
                if not name.startswith('Leg') and part_tree.overlap(hull_tree):
                    overlaps.append((frame,suffix,name+'/hull'))
        for obj in meshes:
            low, high = bounds(obj)
            min_ground = min(min_ground,low[2])
            assert low[0] >= -128/24 and high[0] <= 128/24 and low[1] >= -4 and high[1] <= 4, (frame,obj.name,low,high)
    assert min_ground > -.04, min_ground
    assert not overlaps, overlaps[:15]
    pose_underbody(root,0,0,-.56,1,0)
    for suffix in SUFFIXES:
        low,_ = bounds(bpy.data.objects['Foot'+suffix+'Mesh'])
        assert abs(low[2]-.03)<.005,low
        low,_ = bounds(bpy.data.objects['LiftPod'+suffix+'Mesh'])
        assert low[2] >= .24,low
    pose_underbody(root,0,.9,math.pi/2,0,0)
    for suffix in SUFFIXES:
        low,high = bounds(bpy.data.objects['Foot'+suffix+'Mesh'])
        assert .40 <= low[2] and high[2] <= .90,(low,high)
    pose_underbody(root,0,0,-.56,1,0)
    return {'sampled_takeoff_frames':97,'foot_intersections':0,'minimum_ground_z':min_ground,
            'nozzle_ground_clearance':.255,'foot_storage_z':[.40,.90]}


def animate_flight(root):
    moving = [root] + [o for o in root.children_recursive if o.type=='EMPTY']
    moving += [bpy.data.objects[prefix+suffix] for prefix in ['GearBarrel','GearRod'] for suffix in SUFFIXES]
    moving += [bpy.data.objects[prefix+str(side)] for prefix in ['RampCylinder','RampRod'] for side in [-1,1]]
    for name,landing in [('Takeoff',False),('Landing',True)]:
        for obj in moving:
            obj.animation_data_create()
            obj.animation_data.action = None
        for frame in range(1,98):
            flight_pose(root,(frame-1)/24,landing)
            for obj in moving:
                obj.rotation_mode='XYZ'
                for path in ['location','rotation_euler','scale']:
                    obj.keyframe_insert(data_path=path,frame=frame,group=name)
        for obj in moving:
            action = obj.animation_data.action
            action.name=name+'_'+obj.name
            track = obj.animation_data.nla_tracks.new()
            track.name=name
            strip = track.strips.new(name,1,action)
            strip.action_frame_start=1
            strip.action_frame_end=97
            strip.blend_type='REPLACE'
            obj.animation_data.action=None
            track.mute=True
    # Export by NLA track name combines all node channels into one coherent clip.
    for obj in moving:
        for track in obj.animation_data.nla_tracks:
            track.mute=False
    flag_keys = bpy.data.objects['BarracksFlag'].data.shape_keys
    flag_action = flag_keys.animation_data.action
    track = flag_keys.animation_data.nla_tracks.new()
    track.name='Flag_Wind_Loop'
    track.strips.new('Flag_Wind_Loop',1,flag_action)
    flag_keys.animation_data.action=None
    bpy.context.scene.frame_end=97
    pose_underbody(root,0,0,-.56,1,0)
