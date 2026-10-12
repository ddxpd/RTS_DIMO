import sys as _sys
from pathlib import Path as _Path
_blender_tools = _Path(__file__).resolve().parents[1]
_sys.path[:0] = [str(_Path(__file__).resolve().parent), str(_blender_tools), str(_blender_tools / "shared")]
"""Independent RTS machine gun, referenced to the three user-supplied views.

Local +X points to the muzzle, +Z is up. Grip anchors retain the infantry's
measured palm centers. No dependency on concept art exists in the exported GLB.
"""
import bpy
import math
import os
import json
import struct
import importlib.util
import numpy as np
from mathutils import Vector, Matrix

HERE = os.path.dirname(__file__)
ROOT = os.path.abspath(os.path.join(HERE, '../../..'))
OUT = os.path.join(ROOT, 'assets/concept_art/mobile_machine_gun')
MODEL = os.path.join(ROOT, 'assets/models/units/mobile_infantry/mobile_infantry_machine_gun.glb')
SOURCE = os.path.join(ROOT, 'assets/models/source/mobile_infantry_machine_gun.blend')


def module(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name+'.py'))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


base = module('create_mobile_infantry')
baker = module('bake_mobile_infantry_v2')
base.OUT = OUT
base.SIZE = 1024
base.COLORS.update(metal=(.055,.075,.085), edge=(.11,.13,.14), rubber=(.025,.03,.033))
base.ROUGH.update(metal=.44, edge=.38)


class Builder(base.Builder):
    def __init__(self):
        super().__init__()
        self.scene.name = 'MobileMachineGun_Source'
        self.root.name = 'MobileMachineGun'
        self.root['display_name'] = '机动兵机枪'
        self.root['asset_stage'] = 'independent_weapon'
        self.materials = self.materials[:1]
        self.materials[0].name = 'MG_DarkAlloy'
        self.high_objects = []
        self.anchors = []

    def build_geometry(self):
        # Octagonal longitudinal shell: one continuous broad body, taller aft.
        q = Matrix.Rotation(math.pi/2,4,'Y').to_quaternion()
        self.part('Receiver', [(-.155,.232,.102),(-.13,.248,.116),(-.025,.248,.12),
                  (.035,.203,.12),(.40,.203,.12),(.445,.174,.108)], 'metal', (0,0,.076), q)
        self.box('LowerRail',(.185,0,-.035),(.48,.104,.035),'edge',.006)
        self.box('RearGrip',(-.085,-.009,-.107),(.052,.050,.15),'rubber',.005)
        self.box('FrontGrip',(.160,-.020,-.079),(.049,.049,.115),'rubber',.006)
        self.box('FeedHousing',(.016,0,-.083),(.105,.085,.105),'metal',.007)
        self.box('FeedBase',(.016,0,-.143),(.12,.096,.022),'edge',.003)
        self.box('StockTop',(-.244,0,.088),(.195,.062,.042),'edge',.006)
        self.limb('StockBrace',(-.325,0,.072),(-.242,0,-.145),.041,.056,'edge')
        self.limb('StockBottom',(-.242,0,-.145),(-.129,0,-.020),.035,.056,'metal')
        self.box('ButtPad',(-.33,0,.019),(.028,.073,.134),'rubber',.005)
        self.box('RearSight',(-.104,0,.209),(.088,.039,.032),'edge',.003)
        self.box('FrontSight',(.378,0,.191),(.085,.042,.019),'edge',.003)
        # Real recessed muzzle with a quad annular rim and dark blind bore.
        verts, faces = [], []
        rings = [(.44,.067),(.463,.074),(.477,.069),(.477,.046),(.43,.046)]
        for x,r in rings:
            for i in range(16):
                a = math.tau*i/16
                verts.append((x, r*math.cos(a), .077+r*math.sin(a)))
        for k in range(len(rings)-1):
            for j in range(16):
                n = (j+1)%16
                faces.append((k*16+j,k*16+n,(k+1)*16+n,(k+1)*16+j))
        for j in range(16):
            n=(j+1)%16
            faces.append((64+j,64+n,n,j))
        mesh=bpy.data.meshes.new('MG_Muzzle')
        mesh.from_pydata(verts,[],faces)
        mesh.update()
        # Ring winding is outward for the X-axis convention.
        import bmesh
        bm=bmesh.new(); bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces)); bm.to_mesh(mesh); bm.free()
        obj=bpy.data.objects.new('MG_Muzzle',mesh)
        self.collection.objects.link(obj); obj.parent=self.root
        obj['part_role']='Muzzle'; obj['surface']='edge'; mesh.materials.append(self.materials[0])
        uv=mesh.uv_layers.new(name='UVMap')
        for p in mesh.polygons:
            for loop,co in zip(p.loop_indices,[(0,0),(1,0),(1,1),(0,1)]): uv.data[loop].uv=co
            self.islands.append({'object':obj,'faces':[p.index],'size':(.025,.025),'kind':'edge'})
        self.objects.append(obj)
        self.box('BoreDark',(.428,0,.077),(.007,.091,.091),'rubber',.001)
        for name,point in [('GripRight',(-.085,-.009,-.107)),('GripLeft',(.160,-.020,-.057)),('MuzzleSocket',(.48,0,.077))]:
            anchor=bpy.data.objects.new(name,None); self.collection.objects.link(anchor)
            anchor.parent=self.root; anchor.location=point; self.anchors.append(anchor)
        self.scene.view_layers[0].update()

    def surface_detail(self):
        size=base.SIZE
        pixels=np.full((size,size,4),.5,np.float32); pixels[:,:,3]=1
        for island in self.islands:
            obj=island['object']; x,y,w,h=island['rect']
            if obj['part_role']!='Receiver' or len(island['faces'])<8: continue
            # UV strip around shell: large lateral panels are the two Y faces.
            vv,uu=np.mgrid[0:h,0:w].astype(np.float32)
            u=(uu+.5)/w; v=(vv+.5)/h
            value=np.zeros((h,w),np.float32)
            for center in [.1059,.6059]:
                lateral=np.exp(-((u-center)/.092)**8)
                # Five diagonal cooling slots, recessed side service panel, screws.
                for slot in [.59,.66,.73,.80,.87]:
                    value-=.32*np.exp(-((v-slot-(u-center)*.8)/.007)**4)*lateral
                panel=np.exp(-((v-.37)/.15)**10)*np.exp(-((u-center)/.055)**10)
                value-=.14*panel
                for a,b in [(center-.065,.19),(center+.065,.19),(center-.065,.50),(center+.065,.50)]:
                    r=np.sqrt(((u-a)*2)**2+(v-b)**2)
                    value-=.20*np.exp(-((r-.011)/.003)**2)
            tile=np.repeat((.5+value)[:,:,None],3,axis=2)
            pixels[y-5:y+h+5,x-5:x+w+5,:3]=np.pad(tile,((5,5),(5,5),(0,0)),mode='edge')
        self.detail_height=bpy.data.images.new('MG_EditableRelief',width=size,height=size,alpha=False)
        self.detail_height.colorspace_settings.name='Non-Color'
        self.detail_height.pixels.foreach_set(pixels.ravel())
        baker.packed_save(self.detail_height,os.path.join(OUT,'machine_gun_relief.png'))

    def attach_detail_height(self,material):
        nodes,links=material.node_tree.nodes,material.node_tree.links
        shader=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
        tex=nodes.new('ShaderNodeTexImage'); tex.image=self.detail_height
        bump=nodes.new('ShaderNodeBump'); bump.inputs['Distance'].default_value=.005
        links.new(tex.outputs['Color'],bump.inputs['Height']); links.new(bump.outputs['Normal'],shader.inputs['Normal'])

    def export_weapon(self):
        # Preserve editable bake sources instead of feeding baked normals back
        # into a subsequent high-to-low bake.
        high_material=bpy.data.materials.new('MG_HighSourceRelief')
        high_material.use_nodes=True
        self.attach_detail_height(high_material)
        for high in self.high_objects:
            high.data.materials.clear()
            high.data.materials.append(high_material)
        copies=[]
        for obj in self.scene.objects: obj.select_set(False)
        for obj in self.objects:
            copy=obj.copy(); copy.data=obj.data.copy(); self.collection.objects.link(copy)
            copy.select_set(True); copies.append(copy)
        self.scene.view_layers[0].objects.active=copies[0]
        bpy.ops.object.join(); combined=bpy.context.object; combined.name='MachineGunMesh'
        self.root.select_set(True)
        for anchor in self.anchors: anchor.select_set(True)
        try:
            bpy.ops.export_scene.gltf(filepath=MODEL,export_format='GLB',use_selection=True,use_active_scene=True,
                export_animations=False,export_extras=True,export_yup=True)
        finally:
            bpy.data.objects.remove(combined,do_unlink=True)
        with open(MODEL,'rb') as stream:
            raw=stream.read(); doc=json.loads(raw[20:20+struct.unpack_from('<I',raw,12)[0]])
        for node in doc['nodes']:
            for anchor in ['GripRight','GripLeft','MuzzleSocket']:
                if node.get('name','').split('.')[0] == anchor:
                    node['name'] = anchor
        chunk=json.dumps(doc,separators=(',',':')).encode('utf-8')
        chunk+=b' '*((-len(chunk))%4)
        tail=raw[20+struct.unpack_from('<I',raw,12)[0]:]
        with open(MODEL,'wb') as stream:
            stream.write(struct.pack('<IIIII',0x46546C67,2,20+len(chunk)+len(tail),len(chunk),0x4E4F534A))
            stream.write(chunk); stream.write(tail)
        triangles=sum(doc['accessors'][p['indices']]['count']//3 for m in doc['meshes'] for p in m['primitives'])
        assert triangles<=2000 and len(doc['materials'])==1
        assert all('uri' not in image for image in doc['images'])
        self.report.update(name='机动兵机枪',stage='independent_weapon',export_triangles=triangles,
            material_count=1,export_triangle_budget=2000,external_dependencies=0,
            reference_images=['机枪1.jpg','机枪2.jpg','机枪3.jpg'],anchors=['GripRight','GripLeft','MuzzleSocket'])
        for path in [os.path.join(OUT,'asset_report.json'),os.path.join(ROOT,'assets/models/source/mobile_infantry_machine_gun_report.json')]:
            with open(path,'w',encoding='utf-8') as stream: json.dump(self.report,stream,ensure_ascii=False,indent=2)
        bpy.data.libraries.write(SOURCE,{self.scene},fake_user=True,compress=True)


def create():
    previous=bpy.context.window.scene
    try:
        b=Builder(); bpy.context.window.scene=b.scene
        bpy.app.driver_namespace['mg_builder']=b
        b.build_geometry(); b.layout_uv(); b.validate(); b.textures(); b.surface_detail()
        bpy.app.driver_namespace['mg_status']={'stage':'baking'}
        baker.bake(b,OUT)
        for key,image in b.images.items():
            image.name='MachineGun_'+key
            baker.packed_save(image,os.path.join(OUT,'machine_gun_'+key+'.png'))
        b.export_weapon()
        b.studio()
        for obj in b.scene.objects:
            if obj.name.startswith('MI_Floor'): obj.location.z=-.19
        b.render('machine-gun-side.png',(0,-4,.08),target=(.07,0,.02),scale=1.04,width=1400,height=800)
        b.render('machine-gun-perspective.png',(.95,-1.6,1.05),target=(.07,0,.02),scale=1.08,width=1400,height=950)
        b.render('machine-gun-muzzle.png',(1.6,-1,.6),target=(.26,0,.07),scale=.62,width=1000,height=1000)
        bpy.app.driver_namespace['mg_status']={'stage':'complete','report':b.report}
    finally:
        bpy.context.window.scene=previous


if __name__=='__main__':
    create()
