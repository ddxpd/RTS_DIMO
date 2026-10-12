import sys as _sys
from pathlib import Path as _Path
_blender_tools = _Path(__file__).resolve().parents[1]
_sys.path[:0] = [str(_Path(__file__).resolve().parent), str(_blender_tools), str(_blender_tools / "shared")]
"""Standalone all-quad static infantry. Safe to run in an occupied Blender session.

Source stays quad-based; the glTF exporter triangulates only its output.
All UV islands have unique atlas rectangles, including symmetric body parts.
"""
import bpy
import math
import json
import os
import struct
import traceback
import importlib.util
import numpy as np
from mathutils import Vector, Matrix

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..'))
OUT = os.path.join(ROOT, 'assets/concept_art/mobile_infantry')
BLEND = os.path.join(ROOT, 'assets/models/source/mobile_infantry.blend')
GLB = os.path.join(ROOT, 'assets/models/units/mobile_infantry/mobile_infantry.glb')
SIZE = 2048
BLUE = (0.025, 0.23, 0.52, 1)
RED = (0.58, 0.035, 0.022, 1)
COLORS = {'armor': (.66, .69, .69), 'edge': (.36, .40, .42),
          'cloth': (.075, .085, .09), 'rubber': (.033, .04, .044),
          'metal': (.17, .20, .22), 'visor': (.027, .07, .09),
          'mark': (.8, .8, .8)}
ROUGH = {'armor': .49, 'edge': .46, 'cloth': .88, 'rubber': .8,
         'metal': .36, 'visor': .18, 'mark': .45}
METAL = {'armor': .05, 'edge': .55, 'cloth': 0, 'rubber': 0,
         'metal': .8, 'visor': .18, 'mark': .05}


class Builder:
    def __init__(self):
        os.makedirs(OUT, exist_ok=True)
        self.scene = bpy.data.scenes.new('MI_AssetStudio')
        self.collection = bpy.data.collections.new('MI_Character')
        self.scene.collection.children.link(self.collection)
        self.root = bpy.data.objects.new('MobileInfantry', None)
        self.collection.objects.link(self.root)
        self.root['display_name'] = '机动兵'
        self.root['intended_producer'] = 'barracks'
        self.root['asset_stage'] = 'static_unrigged'
        self.root['godot_display_height'] = 68.0
        self.objects, self.islands = [], []
        self.materials = []
        for name in ['MI_Body', 'MI_FactionPaint']:
            mat = bpy.data.materials.new(name)
            mat.use_nodes = True
            mat.diffuse_color = BLUE if 'Faction' in name else (.55, .58, .59, 1)
            self.materials.append(mat)

    def part(self, name, rings, kind='armor', center=(0, 0, 0), rotation=None, smooth=False):
        """Chamfered octagonal rings with four-quad end caps, never n-gons."""
        outline = [(-.72,-1),(.72,-1),(1,-.72),(1,.72),(.72,1),(-.72,1),(-1,.72),(-1,-.72)]
        verts = [(x*w/2, y*d/2, z) for z,w,d in rings for x,y in outline]
        n = len(rings)
        verts += [(0,0,rings[0][0]), (0,0,rings[-1][0])]
        faces, uvs = [], []
        lengths = [math.dist(outline[i], outline[(i+1)%8]) for i in range(8)]
        cumulative = [0]
        for length in lengths: cumulative.append(cumulative[-1]+length)
        height = rings[-1][0] - rings[0][0]
        for k in range(n-1):
            for j in range(8):
                faces.append((k*8+j,k*8+(j+1)%8,(k+1)*8+(j+1)%8,(k+1)*8+j))
                u0,u1 = cumulative[j]/cumulative[-1], cumulative[j+1]/cumulative[-1]
                v0,v1 = (rings[k][0]-rings[0][0])/height, (rings[k+1][0]-rings[0][0])/height
                uvs.append([(u0,v0),(u1,v0),(u1,v1),(u0,v1)])
        side_count = len(faces)
        for end in [0,n-1]:
            base = end*8
            c = 8*n + (1 if end else 0)
            for j in range(0,8,2):
                ids = [base+j,base+(j+1)%8,base+(j+2)%8,c]
                if not end: ids.reverse()
                faces.append(tuple(ids))
                w,d = rings[end][1:]
                uvs.append([(verts[i][0]/w+.5,verts[i][1]/d+.5) for i in ids])
        mesh = bpy.data.meshes.new('MI_'+name)
        mesh.from_pydata(verts, [], faces)
        mesh.update()
        obj = bpy.data.objects.new('MI_'+name, mesh)
        self.collection.objects.link(obj)
        obj.parent = self.root
        obj.location = center
        if rotation is not None:
            obj.rotation_mode = 'QUATERNION'
            obj.rotation_quaternion = rotation
        obj['part_role'] = name
        obj['surface'] = kind
        mesh.materials.append(self.materials[1 if kind == 'mark' else 0])
        uv = mesh.uv_layers.new(name='UVMap')
        for face, coords in zip(mesh.polygons, uvs):
            face.use_smooth = smooth
            for loop, coordinate in zip(face.loop_indices, coords): uv.data[loop].uv = coordinate
        width = 2*(max(r[1] for r in rings)+max(r[2] for r in rings))*.94
        self.islands.append({'object': obj, 'faces': list(range(side_count)), 'size': (width,height), 'kind':kind})
        for i, end in enumerate([0,n-1]):
            self.islands.append({'object':obj, 'faces':list(range(side_count+4*i,side_count+4*(i+1))), 'size':rings[end][1:], 'kind':kind})
        self.objects.append(obj)
        return obj

    def box(self, name, center, size, kind='armor', bevel=.008, rotation=None):
        w,d,h = size
        bevel = min(bevel,h*.22,w*.15,d*.15)
        return self.part(name,[(-h/2,w-2*bevel,d-2*bevel),(-h/2+bevel,w,d),(h/2-bevel,w,d),(h/2,w-2*bevel,d-2*bevel)],kind,center,rotation)

    def limb(self, name, a, b, width, depth, kind='cloth'):
        a,b=Vector(a),Vector(b)
        length=(b-a).length
        q=(b-a).to_track_quat('Z','Y')
        return self.part(name,[(0,width*.83,depth*.83),(.04*length,width,depth),(.45*length,width*.93,depth*.93),(.9*length,width*.78,depth*.78),(length,width*.7,depth*.7)],kind,a,q,smooth=kind=='cloth')

    def build_geometry(self):
        # Measured human landmarks; small shoulder shells and exposed flexible joints.
        self.part('TorsoSuit',[(1.02,.28,.19),(1.18,.29,.20),(1.40,.39,.235),(1.50,.37,.21),(1.55,.27,.16)],'cloth',smooth=True)
        self.part('PelvisSuit',[(.87,.29,.19),(.93,.34,.23),(1.055,.30,.20)],'cloth',smooth=True)
        self.box('Belt',(0,0,1.045),(.335,.235,.055),'rubber')
        self.box('Buckle',(0,-.132,1.045),(.065,.026,.035),'metal',.004)
        self.part('ChestPlate',[(1.17,.27,.07),(1.22,.335,.085),(1.39,.37,.09),(1.46,.30,.07)],center=(0,-.106,0))
        self.box('ChestFaction',(-.112,-.157,1.365),(.065,.013,.115),'mark',.003)
        self.box('ChestLatch',(.116,-.16,1.36),(.07,.013,.037),'edge',.002)
        self.box('AbdomenPlate',(0,-.106,1.13),(.235,.06,.073),'edge')
        self.part('BackPlate',[(1.18,.27,.065),(1.25,.33,.08),(1.44,.32,.07)],center=(0,.105,0))
        self.box('BackFaction',(0,.152,1.36),(.16,.014,.10),'mark',.003)
        self.box('BackUtility',(0,.153,1.205),(.19,.085,.09),'edge')
        for s in [-1,1]:
            self.box('BeltPouch'+str(s),(s*.12,-.121,1.025),(.08,.061,.09),'cloth')
            hip=(s*.115,0,.94)
            knee=(s*.14,-.027,.57)
            ankle=(s*.165,.014,.155)
            self.limb('ThighSuit'+str(s),hip,knee,.175,.184)
            self.limb('ShinSuit'+str(s),knee,ankle,.133,.143)
            self.box('ThighPlate'+str(s),(s*.141,-.109,.755),(.128,.051,.23),bevel=.010)
            self.box('KneePad'+str(s),(s*.145,-.112,.55),(.113,.054,.095),'edge',.011)
            self.box('ShinPlate'+str(s),(s*.16,-.092,.33),(.113,.048,.255),bevel=.010)
            self.box('Boot'+str(s),(s*.165,-.053,.085),(.155,.27,.15),'rubber',.018)
            self.box('BootToe'+str(s),(s*.165,-.13,.105),(.14,.14,.064),'edge')
            self.box('Sole'+str(s),(s*.165,-.055,.018),(.16,.28,.03),'rubber',.004)
        self.limb('Neck',(0,0,1.47),(0,0,1.635),.125,.13,'rubber')
        self.part('HelmetSeal',[(1.57,.16,.16),(1.61,.20,.19),(1.76,.21,.195),(1.81,.17,.17)],'rubber',smooth=True)
        self.part('HelmetShell',[(1.64,.22,.205),(1.70,.244,.225),(1.79,.235,.22),(1.845,.18,.17),(1.865,.12,.11)],center=(0,.016,0),smooth=True)
        self.box('Brow',(0,-.105,1.754),(.235,.042,.035),'armor',.004)
        self.box('Visor',(0,-.113,1.709),(.196,.031,.061),'visor',.006)
        self.part('ChinGuard',[(1.58,.135,.10),(1.62,.19,.13),(1.67,.20,.12)],center=(0,-.052,0))
        self.box('HelmetStripe',(0,-.004,1.861),(.048,.12,.012),'mark',.001)
        for s in [-1,1]:
            self.box('EarCover'+str(s),(s*.12,.008,1.701),(.034,.10,.11),'edge',.008)
        # Rifle crosses torso at a low-ready angle. Hands are positioned on grips.
        shoulder_r=(.245,0,1.47); elbow_r=(.30,-.045,1.23); hand_r=(.125,-.255,1.16)
        shoulder_l=(-.245,0,1.47); elbow_l=(-.32,-.065,1.245); hand_l=(-.20,-.28,1.155)
        for label,a,b,c in [('R',shoulder_r,elbow_r,hand_r),('L',shoulder_l,elbow_l,hand_l)]:
            self.limb('UpperArm'+label,a,b,.117,.126)
            self.limb('Forearm'+label,b,c,.104,.111)
            self.part('ShoulderShell'+label,[(1.405,.115,.15),(1.42,.15,.18),(1.49,.145,.17),(1.518,.095,.125)],center=(a[0],-.005,0))
            self.box('ShoulderFaction'+label,(a[0],-.007,1.522),(.085,.108,.009),'mark',.001)
            self.box('ShoulderBadge'+label,(a[0]+(.076 if label=='R' else -.076),-.02,1.459),(.009,.09,.052),'mark',.001)
            self.box('ElbowPad'+label,(b[0],b[1]+.019,b[2]),(.112,.115,.093),'edge')
            mid=(Vector(b)+Vector(c))*.5
            arm_rotation=(Vector(c)-Vector(b)).to_track_quat('Z','Y')
            self.box('ForearmPlate'+label,(mid.x,mid.y-.052,mid.z+.01),(.102,.04,(Vector(c)-Vector(b)).length*.65),bevel=.006,rotation=arm_rotation)
            self.box('Glove'+label,c,(.093,.11,.105),'rubber',.015)
            self.box('Knuckles'+label,(c[0],c[1]-.052,c[2]),(.075,.022,.05),'edge',.003)
        # Gun local X runs stock to muzzle, slightly downward toward the left hand.
        weapon_origin=Vector((.105,-.284,1.237))
        weapon_rotation=Matrix.Rotation(math.radians(-9),4,'Y').to_quaternion()
        def gun(name,offset,size,kind='metal',bevel=.004):
            return self.box('Rifle_'+name,weapon_origin+weapon_rotation@Vector(offset),size,kind,bevel,weapon_rotation)
        gun('Receiver',(-.075,0,0),(.30,.072,.105))
        gun('Stock',(.15,0,.015),(.17,.065,.09),'rubber')
        gun('Butt',(.237,0,.015),(.027,.081,.12),'rubber')
        gun('Handguard',(-.302,0,0),(.175,.086,.087),'edge')
        gun('Barrel',(-.43,0,-.005),(.10,.035,.035))
        gun('Muzzle',(-.50,0,-.005),(.055,.049,.049))
        gun('MuzzleDark',(-.529,0,-.005),(.003,.027,.027),'rubber',.001)
        gun('Magazine',(-.078,0,-.112),(.075,.063,.135),'rubber')
        gun('Grip',(.014,.004,-.075),(.055,.059,.09),'rubber')
        gun('TopRail',(-.125,0,.061),(.26,.042,.022))
        gun('Sight',(-.052,0,.085),(.07,.043,.03),'rubber')
        gun('EjectionPort',(-.072,-.037,.004),(.073,.006,.025),'rubber',.001)
        self.scene.view_layers[0].update()

    def layout_uv(self):
        # Shelf pack whole connected strips and planar caps in one shared atlas.
        # 5px dilation gutters per side yield >=10px separation between islands.
        ordered=sorted(self.islands,key=lambda i:max(i['size']),reverse=True)
        density=600
        while True:
            x=y=row_h=0
            for island in ordered:
                w,h=[max(5,int(math.ceil(v*density))) for v in island['size']]
                if x+w+10>SIZE: x=0; y+=row_h; row_h=0
                island['rect']=(x+5,y+5,w,h)
                x+=w+10; row_h=max(row_h,h+10)
            if y+row_h<=SIZE: break
            density*=.96
        for island in self.islands:
            x,y,w,h=island['rect']; mesh=island['object'].data
            for face_id in island['faces']:
                for loop in mesh.polygons[face_id].loop_indices:
                    uv=mesh.uv_layers.active.data[loop].uv
                    uv.x=(x+uv.x*w)/SIZE; uv.y=(y+uv.y*h)/SIZE
        self.density=density

    def textures(self):
        rng=np.random.default_rng(260108)
        arrays={key:np.ones((SIZE,SIZE,4),np.float32) for key in ['basecolor','normal','orm']}
        arrays['basecolor'][:,:,:3]=.12
        arrays['normal'][:,:,:3]=(.5,.5,1)
        arrays['orm'][:,:,:3]=(1,.6,0)
        for island in self.islands:
            x,y,w,h=island['rect']; kind=island['kind']
            xx,yy=np.meshgrid(np.arange(w+10),np.arange(h+10))
            noise=rng.normal(0,.003,(h+10,w+10))
            edge=np.minimum.reduce([xx,np.full_like(xx,w+9)-xx,yy,np.full_like(yy,h+9)-yy])
            wear=np.exp(-np.maximum(edge-4,0)/1.1)*(.07 if kind in ['armor','edge','metal'] else .012)
            color=np.array(COLORS[kind])[None,None,:]*(1+noise[:,:,None])+wear[:,:,None]
            rough=np.clip(ROUGH[kind]+noise*3-wear*.5,0,1)
            if kind in ['armor','edge','metal'] and w>15 and h>15:
                for _ in range(max(1,int(w*h/7000))):
                    sx=int(rng.integers(5,w+4)); sy=int(rng.integers(5,h+4)); length=int(rng.integers(2, max(3,min(w,18))))
                    color[sy:sy+1,sx:min(sx+length,w+5),:]*=.7
                    rough[sy:sy+1,sx:min(sx+length,w+5)]=.37
            region=np.s_[y-5:y+h+5,x-5:x+w+5]
            arrays['basecolor'][region][:,:,:3]=np.clip(color,0,1)
            arrays['orm'][region][:,:,1]=rough
            arrays['orm'][region][:,:,2]=METAL[kind]
            if kind=='cloth':
                arrays['normal'][region][:,:,0]+=.008*np.sin(xx*math.pi/2)
                arrays['normal'][region][:,:,1]+=.008*np.sin(yy*math.pi/2)
        self.images={}
        for key,array in arrays.items():
            image=bpy.data.images.new('MI_'+key,width=SIZE,height=SIZE,alpha=False)
            image.colorspace_settings.name='sRGB' if key=='basecolor' else 'Non-Color'
            image.pixels.foreach_set(array.ravel())
            image.filepath_raw=os.path.join(OUT,'mobile_infantry_'+key+'.png')
            image.file_format='PNG'; image.save(); image.pack()
            self.images[key]=image
        for mat in self.materials:
            nodes,links=mat.node_tree.nodes,mat.node_tree.links
            bsdf=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
            bsdf.inputs['Base Color'].default_value=BLUE if 'Faction' in mat.name else (1,1,1,1)
            for key,image in self.images.items():
                tex=nodes.new('ShaderNodeTexImage'); tex.image=image
                if key=='basecolor' and 'Faction' not in mat.name: links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
                elif key=='normal':
                    normal=nodes.new('ShaderNodeNormalMap'); links.new(tex.outputs['Color'],normal.inputs['Color']); links.new(normal.outputs[0],bsdf.inputs['Normal'])
                elif key=='orm':
                    channels=nodes.new('ShaderNodeSeparateColor'); links.new(tex.outputs['Color'],channels.inputs[0])
                    links.new(channels.outputs['Green'],bsdf.inputs['Roughness']); links.new(channels.outputs['Blue'],bsdf.inputs['Metallic'])
            mat.use_backface_culling=True

    def validate(self):
        faces=sum(len(o.data.polygons) for o in self.objects)
        assert all(len(p.vertices)==4 for o in self.objects for p in o.data.polygons)
        assert faces*2<=6000, faces*2
        rectangles=[]
        for island in self.islands:
            x,y,w,h=island['rect']
            assert min(x,y)>=5 and x+w<=SIZE-5 and y+h<=SIZE-5
            for a,b,c,d in rectangles:
                assert x+w+8<=a or a+c+8<=x or y+h+8<=b or b+d+8<=y, 'UV gutters overlap'
            rectangles.append((x,y,w,h))
        for obj in self.objects:
            assert all(p.area>1e-10 for p in obj.data.polygons)
            assert all(0<=v<=1 for uv in obj.data.uv_layers.active.data for v in uv.uv)
            counts={}
            for p in obj.data.polygons:
                for e in p.edge_keys: counts[e]=counts.get(e,0)+1
            assert all(c==2 for c in counts.values()), obj.name
            obj.data.calc_loop_triangles()
            volume=sum(obj.data.vertices[t.vertices[0]].co.dot(obj.data.vertices[t.vertices[1]].co.cross(obj.data.vertices[t.vertices[2]].co)) for t in obj.data.loop_triangles)/6
            assert volume>0, (obj.name,volume)
        self.report={'name':'机动兵','stage':'static_unrigged','source_quads':faces,'source_triangles':0,'source_ngons':0,'export_triangle_budget':6000,'expected_export_triangles':faces*2,'material_count':2,'uv_islands':len(self.islands),'uv_min_gutter_pixels':10,'uv_overlap_pairs':0,'texture_size':[SIZE,SIZE],'parts':len(self.objects),'godot_display_height':68,'production_integrated':False,'animation_included':False,'uv_method':'unique rectangular allocation; contiguous side strip and planar quad caps; symmetric parts unique'}
        spec = importlib.util.spec_from_file_location('mi_uv_audit', os.path.join(os.path.dirname(__file__), 'audit_mobile_infantry.py'))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.report.update(module.audit(self.objects))
        return self.report

    def export(self):
        for obj in self.scene.objects: obj.select_set(False)
        copies=[]
        for obj in self.objects:
            duplicate=obj.copy(); duplicate.data=obj.data.copy()
            self.collection.objects.link(duplicate); duplicate.select_set(True); copies.append(duplicate)
        self.scene.view_layers[0].objects.active=copies[0]
        bpy.ops.object.join()
        combined=bpy.context.object; combined.name='MI_RenderMesh'
        self.root.select_set(True)
        try:
            bpy.ops.export_scene.gltf(filepath=GLB,export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_animations=False,export_extras=True,export_image_format='AUTO')
        finally:
            data=combined.data; bpy.data.objects.remove(combined,do_unlink=True); bpy.data.meshes.remove(data)
        with open(GLB,'rb') as f:
            f.seek(12); length,kind=struct.unpack('<II',f.read(8)); doc=json.loads(f.read(length))
        assert all('uri' not in im for im in doc.get('images',[]))
        assert all('uri' not in b for b in doc.get('buffers',[]))
        assert len(doc['meshes'])==1, 'Runtime mesh must be consolidated'
        triangles=sum(doc['accessors'][p['indices']]['count']//3 for m in doc['meshes'] for p in m['primitives'])
        assert triangles==self.report['expected_export_triangles']
        self.report.update(export_triangles=triangles,embedded_images=len(doc.get('images',[])),external_dependencies=0,runtime_meshes=1,runtime_surfaces=len(doc['meshes'][0]['primitives']))
        # Write only this scene and its dependencies, never the user's active file.
        bpy.data.libraries.write(BLEND,{self.scene},fake_user=True,compress=True)
        for destination in [os.path.join(OUT,'asset_report.json'), os.path.join(os.path.dirname(BLEND),'mobile_infantry_report.json')]:
            with open(destination,'w',encoding='utf-8') as f:
                json.dump(self.report,f,ensure_ascii=False,indent=2)

    def studio(self):
        scene=self.scene
        scene.render.engine='CYCLES'; scene.cycles.samples=32
        scene.cycles.use_denoising=True
        scene.render.resolution_x=1200; scene.render.resolution_y=1200; scene.render.resolution_percentage=100
        scene.render.image_settings.file_format='PNG'
        scene.world=bpy.data.worlds.new('MI_StudioWorld'); scene.world.use_nodes=True
        background=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND')
        background.inputs[0].default_value=(1,1,1,1)
        background.inputs[1].default_value=.45
        scene.view_settings.view_transform='Standard'; scene.view_settings.look='None'
        cam=bpy.data.objects.new('MI_StudioCamera',bpy.data.cameras.new('MI_StudioCamera'))
        scene.collection.objects.link(cam); cam.data.type='ORTHO'; scene.camera=cam; self.camera=cam
        for name,position,power,size in [('Key',(3,-4,5),380,4),('Fill',(-3,-2,3),180,3),('Rim',(1,3,4),300,3)]:
            data=bpy.data.lights.new('MI_'+name,'AREA'); data.energy=power; data.shape='DISK'; data.size=size
            obj=bpy.data.objects.new('MI_'+name,data); scene.collection.objects.link(obj); obj.location=position
            obj.rotation_euler=(Vector((0,0,1))-obj.location).to_track_quat('-Z','Y').to_euler()
        mesh=bpy.data.meshes.new('MI_Floor'); mesh.from_pydata([(-200,-200,-.002),(200,-200,-.002),(200,200,-.002),(-200,200,-.002)],[],[(0,1,2,3)])
        floor=bpy.data.objects.new('MI_Floor',mesh); scene.collection.objects.link(floor)
        mat=bpy.data.materials.new('MI_StudioWhite'); mat.use_nodes=True
        shader=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        shader.inputs['Base Color'].default_value=(1,1,1,1)
        shader.inputs['Roughness'].default_value=.8
        mesh.materials.append(mat)

    def render(self,filename,position,target=(0,0,.95),scale=2.35,width=1200,height=1200):
        self.camera.location=position; self.camera.rotation_euler=(Vector(target)-self.camera.location).to_track_quat('-Z','Y').to_euler()
        self.camera.data.ortho_scale=scale
        self.scene.render.resolution_x=width; self.scene.render.resolution_y=height
        self.scene.render.filepath=os.path.join(OUT,filename)
        bpy.ops.render.render(write_still=True,scene=self.scene.name)


def create():
    previous=bpy.context.window.scene
    builder=Builder()
    bpy.app.driver_namespace['mi_builder']=builder
    try:
        bpy.context.window.scene=builder.scene
        builder.build_geometry(); builder.layout_uv(); builder.textures(); builder.validate(); builder.export(); builder.studio()
        builder.render('mobile-infantry-front-v1.png',(3,-5,2.8))
    finally:
        bpy.context.window.scene=previous
    return builder


if __name__=='__main__':
    create()
