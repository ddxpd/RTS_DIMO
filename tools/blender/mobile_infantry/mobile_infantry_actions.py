"""Baked human weight transfer, shared by full asset builds and motion-only updates."""
import bpy
import math
from mathutils import Vector, Matrix, Quaternion

FPS = 30


def smooth(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def build_actions(scene, arm):
    rest = {bone.name: bone.matrix_local.copy() for bone in arm.data.bones}
    specs = {bone.name: (bone.head_local.copy(), bone.tail_local.copy()) for bone in arm.data.bones}
    gun_origin = Vector((-.025, -.287, 1.19))
    gun_rotation = Matrix.Rotation(math.radians(35), 4, 'Y')

    def transform(head, tail, initial):
        rotation = (initial.to_quaternion() @ Vector((0, 1, 0))).rotation_difference((tail-head).normalized())
        return Matrix.Translation(head) @ rotation.to_matrix().to_4x4() @ initial.to_quaternion().to_matrix().to_4x4()

    def leg(side, ankle, roll=0.0):
        thigh, shin, foot = [arm.pose.bones[name+'.'+side] for name in ['thigh', 'shin', 'foot']]
        hip = arm.pose.bones['pelvis'].matrix @ rest['pelvis'].inverted() @ specs[thigh.name][0]
        a = (specs[thigh.name][1]-specs[thigh.name][0]).length
        b = (specs[shin.name][1]-specs[shin.name][0]).length
        axis = (ankle-hip).normalized()
        distance = min((ankle-hip).length, a+b-.001)
        pole = Vector((0, -1, 0))
        pole = (pole-axis*pole.dot(axis)).normalized()
        along = (a*a-b*b+distance*distance)/(2*distance)
        knee = hip+axis*along+pole*math.sqrt(max(0, a*a-along*along))
        thigh.matrix = transform(hip, knee, rest[thigh.name])
        scene.view_layers[0].update()
        shin.matrix = transform(knee, ankle, rest[shin.name])
        scene.view_layers[0].update()
        foot.matrix = Matrix.Translation(ankle) @ Matrix.Rotation(roll, 4, 'X') @ rest[foot.name].to_quaternion().to_matrix().to_4x4()
        arm.pose.bones['CTRL_foot.'+side].matrix = foot.matrix

    def hands(delta):
        for side, sign in [('L', 1), ('R', -1)]:
            upper, fore, hand = [arm.pose.bones[name+'.'+side] for name in ['upper_arm', 'forearm', 'hand']]
            start = upper.matrix.translation.copy()
            goal = delta @ specs[hand.name][0]
            a = (specs[upper.name][1]-specs[upper.name][0]).length
            b = (specs[fore.name][1]-specs[fore.name][0]).length
            axis = (goal-start).normalized()
            distance = min((goal-start).length, a+b-.001)
            along = (a*a-b*b+distance*distance)/(2*distance)
            pole = Vector((sign*.5, .25, -1))
            pole = (pole-axis*pole.dot(axis)).normalized()
            elbow = start+axis*along+pole*math.sqrt(max(0, a*a-along*along))
            upper.matrix = transform(start, elbow, rest[upper.name])
            scene.view_layers[0].update()
            fore.matrix = transform(elbow, goal, rest[fore.name])
            scene.view_layers[0].update()
            hand.matrix = delta @ rest[hand.name]
            arm.pose.bones['CTRL_hand.'+side].matrix = hand.matrix
            scene.view_layers[0].update()
        arm.pose.bones['weapon'].matrix = delta @ rest['weapon']

    actions = {}
    arm.animation_data_create()
    for name, duration in [('RESET', 1/FPS), ('idle', 4.0), ('walk', 1.0), ('jog', .6), ('fire', .3), ('death', 1.2)]:
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        arm.animation_data.action = action
        frames = max(1, round(duration*FPS))
        for frame in range(frames+1):
            scene.frame_set(frame)
            t = frame/frames
            for pose in arm.pose.bones:
                pose.matrix_basis = Matrix.Identity(4)
                pose.rotation_mode = 'QUATERNION'
            pelvis = arm.pose.bones['pelvis']
            chest = arm.pose.bones['chest']
            if name in ['idle', 'fire']:
                breath = math.sin(t*math.tau) if name == 'idle' else 0.0
                # Pelvis-local Y is vertical. A fixed support-side bias avoids
                # a symmetrical mannequin pose; breathing does not move the feet.
                pelvis.location = (-.025, -.040, 0)
                pelvis.rotation_quaternion = Quaternion((0, 1, 0), -.035)
                chest.rotation_quaternion = Quaternion((0, 1, 0), .065) @ Quaternion((1, 0, 0), .035+.009*breath)
                arm.pose.bones['neck'].rotation_quaternion = Quaternion((0, 1, 0), -.025)
                scene.view_layers[0].update()
                leg('L', Vector((.175, -.065, .205)))
                leg('R', Vector((-.17, .065, .205)))
            elif name in ['walk', 'jog']:
                jog = name == 'jog'
                cycle = t*math.tau
                pelvis.location = (.018*math.sin(cycle), (-.052 if jog else -.032)-(.016 if jog else .010)*math.cos(cycle*2), 0)
                pelvis.rotation_quaternion = Quaternion((0, 1, 0), .055*math.sin(cycle)) @ Quaternion((0, 0, 1), .025*math.sin(cycle))
                chest.rotation_quaternion = Quaternion((0, 1, 0), -.040*math.sin(cycle)) @ Quaternion((1, 0, 0), .09 if jog else .04)
                arm.pose.bones['head'].rotation_quaternion = Quaternion((0, 1, 0), .018*math.sin(cycle))
                scene.view_layers[0].update()
                for side, sign, offset in [('L', 1, 0), ('R', -1, .5)]:
                    phase = (t+offset)%1
                    stance = .42 if jog else .60
                    travel = (1.50 if jog else .80)*stance
                    if phase < stance:
                        contact = phase/stance
                        forward = -.5*travel+travel*contact
                        heel = 1-smooth(contact/.20)
                        toe = smooth((contact-.72)/.28)
                        roll = -.12*heel+.22*toe
                        lift = .014*heel+.035*toe
                    else:
                        u = (phase-stance)/(1-stance)
                        forward = .5*travel-travel*smooth(u)
                        lift = (.13 if jog else .085)*math.sin(math.pi*u)**1.3
                        roll = .22*(1-smooth(u/.45))-.12*smooth((u-.70)/.30)
                    leg(side, Vector((sign*.17, .008+forward, .205+lift)), roll)
            elif name == 'death':
                amount = smooth(t)
                arm.pose.bones['root'].rotation_quaternion = Quaternion((0, 0, 1), -1.47*amount)
                arm.pose.bones['root'].location.y = .035*amount
                arm.pose.bones['spine'].rotation_quaternion = Quaternion((1, 0, 0), .25*math.sin(t*math.pi))
            scene.view_layers[0].update()
            if name in ['idle', 'walk', 'jog']:
                # Both hands solve to the same rigid gun, following the chest's
                # weight transfer. No independently wobbling weapon/hand tracks.
                hands(chest.matrix @ rest['chest'].inverted())
            elif name == 'fire':
                recoil = math.sin(min(t/.25, 1)*math.pi)*.06 if t < .25 else 0
                chest.rotation_quaternion = chest.rotation_quaternion @ Quaternion((1, 0, 0), -recoil)
                scene.view_layers[0].update()
                delta = Matrix.Translation(Vector((-.10, -.29+recoil*.3, 1.36))) @ Matrix.Rotation(-math.pi/2, 4, 'Z') @ gun_rotation.inverted() @ Matrix.Translation(-gun_origin)
                hands(delta)
            scene.view_layers[0].update()
            for pose in arm.pose.bones:
                pose.keyframe_insert('location', frame=frame, group=pose.name)
                pose.keyframe_insert('rotation_quaternion', frame=frame, group=pose.name)
        actions[name] = action
    arm.animation_data.action = None
    return actions
