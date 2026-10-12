import sys as _sys
from pathlib import Path as _Path
_blender_tools = _Path(__file__).resolve().parents[1]
_sys.path[:0] = [str(_Path(__file__).resolve().parent), str(_blender_tools), str(_blender_tools / "shared")]
"""Continuous quad body, sleeves and helmet; preserve the independent infantry rig."""
import bpy
import math
import os
import json
import importlib.util
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(__file__)


def module(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + '.py'))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


v3 = module('create_mobile_infantry_v3')
base = v3.base
OUT = os.path.join(base.OUT, 'v5')
os.makedirs(OUT, exist_ok=True)
base.OUT = OUT


class Builder(v3.Builder):
    def __init__(self):
        super().__init__()
        self.scene.name = 'MI_V5_ContinuousStudio'
        self.root['asset_version'] = 5
        self.preserve_high_normals_roles = {'HelmetShell'}

    def part(self, name, *args, **kwargs):
        return super().part(name, *args, **kwargs)

    def custom(self, role, vertices, faces, surface, face_kinds=None):
        mesh = bpy.data.meshes.new('MI_' + role)
        mesh.from_pydata(vertices, [], faces)
        mesh.update()
        obj = bpy.data.objects.new('MI_' + role, mesh)
        self.collection.objects.link(obj)
        obj.parent = self.root
        obj['part_role'] = role
        obj['surface'] = surface
        mesh.materials.append(self.materials[0])
        uv = mesh.uv_layers.new(name='UVMap')
        for polygon in mesh.polygons:
            polygon.use_smooth = True
            coords = [mesh.vertices[i].co for i in polygon.vertices]
            width = (coords[0]-coords[1]).length + (coords[2]-coords[3]).length
            height = (coords[0]-coords[3]).length + (coords[1]-coords[2]).length
            for loop, point in zip(polygon.loop_indices, [(0, 0), (1, 0), (1, 1), (0, 1)]):
                uv.data[loop].uv = point
            kind = face_kinds[polygon.index] if face_kinds else surface
            self.islands.append({'object': obj, 'faces': [polygon.index], 'size': (width/2, height/2), 'kind': kind})
        self.objects.append(obj)
        return obj

    @staticmethod
    def ring(vertices, center, width, depth, count=16):
        first = len(vertices)
        for j in range(count):
            angle = j * 2*math.pi/count
            vertices.append((center[0]+width*.5*math.cos(angle), center[1]+depth*.5*math.sin(angle), center[2]))
        return list(range(first, first+count))

    @staticmethod
    def bridge(faces, lower, upper):
        for j in range(len(lower)):
            k = (j+1) % len(lower)
            faces.append((lower[j], lower[k], upper[k], upper[j]))

    @staticmethod
    def cap(vertices, faces, loop, top):
        center = sum((Vector(vertices[i]) for i in loop), Vector()) / len(loop)
        index = len(vertices)
        vertices.append(tuple(center))
        for j in range(0, len(loop), 2):
            face = (loop[j], loop[(j+1)%len(loop)], loop[(j+2)%len(loop)], index)
            faces.append(face if top else tuple(reversed(face)))

    def body(self):
        vertices, faces = [], []
        tops = []
        for sign in [1, -1]:
            previous = None
            # Extra knee loops support smooth flexion instead of two capped tubes.
            for z, x, width, depth, y in [(.20,.18,.125,.144,.008), (.28,.177,.14,.16,.009),
                    (.40,.17,.162,.174,.005), (.49,.163,.159,.176,-.003),
                    (.55,.158,.153,.171,-.013), (.585,.157,.153,.178,-.015),
                    (.62,.151,.166,.19,-.014), (.69,.137,.179,.203,-.008),
                    (.80,.117,.195,.221,0), (.90,.094,.20,.224,0)]:
                loop = self.ring(vertices, (sign*x,y,z), width,depth,10)
                if previous is None:
                    self.cap(vertices, faces, loop, False)
                else:
                    self.bridge(faces, previous, loop)
                previous = loop
            tops.append(previous)
        # Share the three crotch vertices: both leg tubes become one manifold trunk.
        mapping = {}
        for left_j, right_j, y in [(4,1,.066),(5,0,0),(6,9,-.066)]:
            left, right = tops[0][left_j], tops[1][right_j]
            vertices[left] = (0,y,.905 if y else .915)
            mapping[right] = left
        faces = [tuple(mapping.get(i,i) for i in f) for f in faces]
        tops[1] = [mapping.get(i,i) for i in tops[1]]
        edges = {}
        for loop in tops:
            for j,a in enumerate(loop):
                b = loop[(j+1)%len(loop)]
                key = tuple(sorted((a,b)))
                edges.setdefault(key, []).append((a,b))
        boundary = {pair[0][0]: pair[0][1] for pair in edges.values() if len(pair)==1}
        loop = [tops[0][0]]
        while boundary[loop[-1]] != loop[0]:
            loop.append(boundary[loop[-1]])
        assert len(loop)==16
        angles = [math.atan2(vertices[i][1], vertices[i][0]) for i in loop]
        for z,width,depth,y in [(.965,.35,.252,0), (1.025,.313,.219,0), (1.09,.302,.205,0),
                (1.18,.325,.224,0), (1.30,.38,.24,0), (1.405,.41,.246,0),
                (1.465,.36,.205,0), (1.515,.21,.146,0)]:
            next_loop = []
            for angle in angles:
                next_loop.append(len(vertices))
                vertices.append((width*.5*math.cos(angle), y+depth*.5*math.sin(angle),z))
            self.bridge(faces, loop, next_loop)
            loop = next_loop
        self.cap(vertices, faces, loop, True)
        # Remove unused duplicate crotch vertices before skinning.
        used = sorted(set(i for f in faces for i in f))
        remap = {i:j for j,i in enumerate(used)}
        vertices, faces = [vertices[i] for i in used], [tuple(remap[i] for i in f) for f in faces]
        kinds = ['fabric' if sum(vertices[i][2] for i in f)/4 < 1.045 else 'cloth' for f in faces]
        return self.custom('ContinuousBody', vertices, faces, 'fabric', kinds)

    def helmet(self):
        vertices, faces = [], []
        previous = None
        for z,w,d,y in [(1.55,.135,.15,-.022),(1.585,.181,.20,-.008),(1.63,.235,.23,.004),
                (1.66,.25,.237,.009),(1.685,.256,.235,.013),(1.712,.262,.252,.014),
                (1.755,.263,.255,.014),(1.802,.231,.22,.014),(1.835,.15,.151,.014),(1.849,.055,.073,.014)]:
            loop = self.ring(vertices,(0,y,z),w,d)
            if 1.66 <= z <= 1.712:
                for index in loop:
                    x,vy,vz = vertices[index]
                    if vy < -.055:
                        vertices[index] = (x,vy+(.006 if z==1.685 else 0),vz+.009*(abs(x)/.13)**2)
            if previous is None:
                self.cap(vertices,faces,loop,False)
            else:
                self.bridge(faces,previous,loop)
            previous = loop
        self.cap(vertices,faces,previous,True)
        kinds = []
        for face in faces:
            center = sum((Vector(vertices[i]) for i in face),Vector())/4
            if 1.66 < center.z < 1.712 and center.y < -.072:
                kinds.append('visor')
            elif center.z < 1.672 and center.y < -.063 and abs(center.x)<.078:
                kinds.append('rubber')
            else:
                kinds.append('armor')
        return self.custom('HelmetShell', vertices, faces, 'armor', kinds)

    def sleeves(self):
        rotation = v3.v2.tilt(35)
        origin = Vector((-.025,-.287,1.19))
        for side, sign in [('L',1),('R',-1)]:
            shoulder = Vector((sign*.246,0,1.429))
            elbow = Vector((.324,-.105,1.166) if sign==1 else (-.303,-.094,1.174))
            hand = origin + rotation @ Vector((.160,-.020,-.057) if sign==1 else (-.085,-.009,-.107))
            vertices, faces = [], []
            points = []
            for t in [0,.18,.45,.68]:
                points.append((shoulder.lerp(elbow,t), .142-(.022*t), .158-(.035*t)))
            a = elbow-(elbow-shoulder).normalized()*.075
            b = elbow+(hand-elbow).normalized()*.075
            for t in [0,.2,.4,.6,.8,1]:
                points.append(((1-t)**2*a+2*t*(1-t)*elbow+t*t*b,.120,.123))
            for t in [.55,.80,1]:
                points.append((elbow.lerp(hand,t),.120-.030*t,.123-.035*t))
            previous = None
            for index,(point,w,d) in enumerate(points):
                tangent = points[min(index+1,len(points)-1)][0]-points[max(0,index-1)][0]
                q = tangent.to_track_quat('Z','Y')
                loop = []
                for j in range(10):
                    angle = j*math.tau/10
                    loop.append(len(vertices))
                    vertices.append(tuple(point+q@Vector((w*.5*math.cos(angle),d*.5*math.sin(angle),0))))
                if previous is None:
                    self.cap(vertices,faces,loop,False)
                else:
                    self.bridge(faces,previous,loop)
                previous = loop
            self.cap(vertices,faces,previous,True)
            self.custom('ContinuousSleeve'+side,vertices,faces,'cloth')

    def build_geometry(self):
        # Call v2 directly: v3's post-pass expects the old separate dome.
        v3.v2.Builder.build_geometry(self)
        for obj in self.objects:
            if obj['part_role'].startswith('SideThighPouch'):
                obj.location.x = math.copysign(.230,obj.location.x)
        removed = [o for o in self.objects if o['part_role'].startswith(('Trouser','Sleeve','Helmet','Visor','Respirator','Cheek',
                    'ThighStrap','PouchFlap','ShoulderHarness','BackHarness','EarInset','BootInstep','GloveKnuckle','AnkleGaiter'))
                    or o['part_role'] in ['TorsoUndersuit','ChestCollar']]
        self.islands = [i for i in self.islands if i['object'] not in removed]
        self.objects = [o for o in self.objects if o not in removed]
        for obj in removed:
            bpy.data.objects.remove(obj,do_unlink=True)
        self.body()
        self.helmet()
        self.sleeves()
        self.scene.view_layers[0].update()

    def surface_detail(self):
        # Existing part strips retain relief; custom face islands use high-source
        # shape normals and folds, without painting a panel around every quad.
        saved = self.islands
        self.islands = [i for i in saved if not i['object']['part_role'].startswith(('Continuous','HelmetShell'))]
        try:
            super().surface_detail()
        finally:
            self.islands = saved
        pixels = np.empty(2048*2048*4,np.float32)
        self.detail_height.pixels.foreach_get(pixels)
        pixels = pixels.reshape(2048,2048,4)
        for island in self.islands:
            role = island['object']['part_role']
            if not role.startswith(('Continuous','HelmetShell')):
                continue
            x,y,w,h = island['rect']
            p = self.patch_points(island)
            px,py,pz = p[:,:,0],p[:,:,1],p[:,:,2]
            relief = np.zeros((h,w),np.float32)
            if role == 'HelmetShell':
                gate = np.clip((pz-1.726)/.012,0,1)*np.clip((1.829-pz)/.012,0,1)*(py<-.03)
                relief -= .18*np.exp(-((np.abs(px)-(.050+(pz-1.73)*.17))/.0018)**2)*gate
                mouth = (pz>1.575)&(pz<1.642)&(py<-.075)
                for slot in [-.043,-.026,0,.026,.043]:
                    relief -= .12*np.exp(-((px-slot)/.0016)**2)*mouth
            else:
                # Continuous anatomical folds and seams, evaluated in source space.
                around_knee = np.exp(-((pz-.59)/.09)**2)
                around_hip = np.exp(-((pz-.86)/.10)**2)
                relief += .16*np.sin(pz*170+px*23+py*31)*(around_knee+around_hip)
                relief -= .10*np.exp(-((py-.035)/.002)**2)*(np.abs(px)>.12)*(pz<.9)
            tile = np.repeat((.5+relief)[:,:,None],3,axis=2)
            pixels[y-5:y+h+5,x-5:x+w+5,:3] = np.pad(tile,((5,5),(5,5),(0,0)),mode='edge')
        self.detail_height.pixels.foreach_set(pixels.ravel())
        v3.baker.packed_save(self.detail_height,os.path.join(OUT,'mobile_infantry_source_relief_v5.png'))
        self.report['surface_detail_parts'] += ['HelmetShell','ContinuousBody','ContinuousSleeveL','ContinuousSleeveR']

    def patch_points(self,island):
        obj = island['object']
        polygon = obj.data.polygons[island['faces'][0]]
        a,b,c,d = [np.array(obj.data.vertices[i].co,dtype=np.float32) for i in polygon.vertices]
        _,_,w,h = island['rect']
        vv,uu = np.mgrid[0:h,0:w].astype(np.float32)
        u,v = ((uu+.5)/w)[:,:,None],((vv+.5)/h)[:,:,None]
        return a*(1-u)*(1-v)+b*u*(1-v)+c*u*v+d*(1-u)*v

    def continuous_weather(self):
        pixels = np.empty(2048*2048*4,np.float32)
        self.images['basecolor'].pixels.foreach_get(pixels)
        pixels = pixels.reshape(2048,2048,4)
        for island in self.islands:
            if not island['object']['part_role'].startswith(('Continuous','HelmetShell')):
                continue
            x,y,w,h = island['rect']
            p = self.patch_points(island)
            noise = np.sin(p[:,:,0]*93+p[:,:,1]*71)*np.cos(p[:,:,2]*81+p[:,:,0]*35)
            palette = {'armor':(.58,.58,.54),'fabric':(.48,.465,.42),'cloth':(.052,.059,.061),
                       'rubber':(.033,.04,.044),'visor':(.012,.034,.046)}
            color = np.array(palette[island['kind']])[None,None,:]*(1+.022*noise[:,:,None])
            if island['kind']=='visor':
                rim = np.exp(-((p[:,:,2]-1.704)/.003)**2)
                color += rim[:,:,None]*np.array((.015,.11,.18))[None,None,:]
            pixels[y-5:y+h+5,x-5:x+w+5,:3] = np.pad(color,((5,5),(5,5),(0,0)),mode='edge')
        self.images['basecolor'].pixels.foreach_set(pixels.ravel())
        v3.baker.packed_save(self.images['basecolor'],os.path.join(OUT,'mobile_infantry_basecolor.png'))

    def audit_relief(self):
        pixels = np.empty(2048*2048*4,np.float32)
        self.images['normal'].pixels.foreach_get(pixels)
        pixels = pixels.reshape(2048,2048,4)
        values = []
        for island in self.islands:
            if island['object']['part_role']=='HelmetShell':
                x,y,w,h = island['rect']
                values.append(float(np.linalg.norm(pixels[y:y+h,x:x+w,:2]-.5,axis=2).max()))
        self.report['helmet_normal_detail_max'] = max(values)
        assert max(values)>.025

    def render(self, filename, *args, **kwargs):
        suffix = '-v%d' % self.root.get('asset_version', 5)
        return base.Builder.render(self,filename.replace('-v2',suffix).replace('-v3',suffix).replace('-v5',suffix),*args,**kwargs)

    def validate(self):
        report = base.Builder.validate(self)
        counts = {}
        for obj in self.objects:
            if not obj['part_role'].startswith(('Continuous','HelmetShell')):
                continue
            adjacent = {v.index:set() for v in obj.data.vertices}
            for edge in obj.data.edges:
                a,b = edge.vertices
                adjacent[a].add(b)
                adjacent[b].add(a)
            remaining = set(adjacent)
            components = 0
            while remaining:
                components += 1
                stack = [remaining.pop()]
                while stack:
                    for neighbor in adjacent[stack.pop()] & remaining:
                        remaining.remove(neighbor)
                        stack.append(neighbor)
            assert components==1, (obj.name,components)
            counts[obj['part_role']] = components
        report.update(version=5, faction_parts=['ShoulderArmorL','ShoulderArmorR'],
                      continuous_parts=['ContinuousBody','ContinuousSleeveL','ContinuousSleeveR','HelmetShell'],
                      continuous_component_counts=counts,
                      reference='assets/concept_art/机动兵2.png')
        return report


def create(version=5, separate_weapon=False):
    global OUT
    if version != 5:
        OUT = os.path.join(base.ROOT, 'assets/concept_art/mobile_infantry/v%d' % version)
        os.makedirs(OUT, exist_ok=True)
        base.OUT = OUT
    previous = bpy.context.window.scene
    try:
        b = Builder()
        bpy.app.driver_namespace['mi_v5_builder'] = b
        bpy.context.window.scene = b.scene
        b.build_geometry()
        if separate_weapon:
            removed = [o for o in b.objects if o['part_role'].startswith('Rifle_')]
            b.islands = [i for i in b.islands if i['object'] not in removed]
            b.objects = [o for o in b.objects if o not in removed]
            for obj in removed:
                bpy.data.objects.remove(obj, do_unlink=True)
        b.layout_uv()
        b.validate()
        b.root['asset_version'] = version
        b.report.update(version=version, separate_weapon=separate_weapon)
        b.textures()
        b.surface_detail()
        bpy.app.driver_namespace['mi_v5_status'] = {'stage':'baking','quads':b.report['source_quads'],'parts':len(b.objects)}
        v3.baker.bake(b,OUT)
        v3.baker.weather(b,OUT)
        b.continuous_weather()
        b.audit_relief()
        b.report['normal_bake_exclusions'] = []
        b.high_collection.name = 'MI_V5_BakeSources'
        # Export staging source first: rig reads this without replacing runtime v4.
        base.BLEND = os.path.join(OUT,'mobile_infantry_unrigged.blend')
        base.GLB = os.path.join(OUT,'mobile_infantry_unrigged.glb')
        v3.finalizer.export(b,base)
        b.studio()
        b.scene.cycles.samples = 32
        bpy.app.driver_namespace['mi_v5_status'] = {'stage':'rendering','report':b.report}
        b.render('mobile-infantry-front-v5.png',(2.5,-6,2.8),target=(0,0,.95),scale=2.17)
        b.render('mobile-infantry-helmet-v5.png',(1.6,-5,2.45),target=(0,0,1.63),scale=.59,width=1000,height=1000)
        rig = module('rig_mobile_infantry')
        report = rig.build(base.BLEND,os.path.join(OUT,'mobile_infantry_report.json'),version)
        bpy.app.driver_namespace['mi_v5_status'] = {'stage':'rigged','report':report}
        return b
    finally:
        bpy.context.window.scene = previous


if __name__ == '__main__':
    create()
