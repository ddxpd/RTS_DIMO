import sys as _sys
from pathlib import Path as _Path
_blender_tools = _Path(__file__).resolve().parents[1]
_sys.path[:0] = [str(_Path(__file__).resolve().parent), str(_blender_tools), str(_blender_tools / "shared")]
from project_paths import model_path
"""Independent, reproducible twin-dock ore depot. Blender Z-up, +Y front; units /20."""
import sys, math, json
from pathlib import Path
import bpy
import numpy as np
from mathutils import Vector
sys.path.insert(0, str(Path(__file__).resolve().parent))
from create_bunker import cube, cylinder, material, empty
ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'assets/models'
TEX = model_path('textures/ore_depot')
TEX.mkdir(parents=True, exist_ok=True)

def image_file(name, pixels):
    h,w,_ = pixels.shape
    image = bpy.data.images.new(name, width=w, height=h, alpha=True)
    image.pixels.foreach_set(np.ascontiguousarray(pixels, dtype=np.float32).ravel())
    image.filepath_raw = str(TEX / (name + '.png'))
    image.file_format = 'PNG'
    image.save()
    return image

def texture(mat, img, socket):
    node=mat.node_tree.nodes.new('ShaderNodeTexImage'); node.image=img
    bsdf=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    mat.node_tree.links.new(node.outputs['Color'],bsdf.inputs[socket])

def materials():
    rng=np.random.default_rng(714)
    n=2048
    arr=np.ones((n,n,4),np.float32)
    colors=[(.69,.73,.76),(.95,.53,.035),(.07,.085,.10),(.055,.27,.48)]
    for i,color in enumerate(colors):
        y,x=divmod(i,2)
        tile=np.array(color)[None,None,:]*(1+rng.normal(0,.024,(n//2,n//2,1)))
        # Worn paint grain and sparse shallow scratches, deliberately restrained.
        for _ in range(350):
            sy,sx=rng.integers(0,1010,2); length=int(rng.integers(2,12))
            tile[sy:sy+1,sx:sx+length]*=.62
        arr[y*1024:(y+1)*1024,x*1024:(x+1)*1024,:3]=tile
    armor=material('Depot_Armor_2K',(1,1,1),.42,.47)
    texture(armor,image_file('armor_albedo',arr),'Base Color')
    rough=np.ones_like(arr); rough[:,:,:3]=.42+rng.random((n,n,1))*.16
    texture(armor,image_file('armor_roughness',rough),'Roughness')
    metal=material('Depot_Mechanism_1K',(1,1,1),.76,.43)
    arr=np.ones((1024,1024,4),np.float32); arr[:,:,:3]=np.array([.10,.13,.16])[None,None,:]*(.85+rng.random((1024,1024,1))*.3)
    texture(metal,image_file('mechanism_albedo',arr),'Base Color')
    rough=np.ones_like(arr); rough[:,:,:3]=.38+rng.random((1024,1024,1))*.18
    texture(metal,image_file('mechanism_roughness',rough),'Roughness')
    glass=material('Depot_Glass',(.19,.55,.72),.05,.12)
    bs=next(n for n in glass.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    bs.inputs['Alpha'].default_value=.16
    glass.diffuse_color=(.19,.55,.72,.16)
    glass.surface_render_method='DITHERED'
    ore=material('Depot_Ore',(.025,.27,.66),.28,.23,(.01,.30,.85),1.2)
    glow=material('Depot_Light',(.08,.65,1),.2,.22,(.015,.5,1),3)
    ink=material('Depot_Marking',(.018,.027,.034),.08,.75)
    return armor,metal,glass,ore,glow,ink

M=None; root=None; level=0

def box(name, size, pos, color=0, bevel=.055, rotation=(0,0,0), mat=None):
    obj=cube(name,size,pos,mat or M[0],root,bevel if level<2 else 0,rotation)
    if mat is None:
        ox=(color%2)*.5; oy=(color//2)*.5
        for uv in obj.data.uv_layers.active.data:
            uv.uv=(ox+.04+float(uv.uv.x)*.42,oy+.04+float(uv.uv.y)*.42)
    return obj

def beam(name,a,b,width,mat=None,color=2):
    v=Vector(b)-Vector(a)
    obj=box(name,(width,width,v.length),(Vector(a)+Vector(b))/2,color,bevel=width*.15,mat=mat)
    obj.rotation_euler=v.to_track_quat('Z','Y').to_euler()
    return obj

def poly(name,vertices,faces,mat):
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices,[],faces);mesh.update()
    obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj);obj.parent=root;obj.data.materials.append(mat)
    return obj

def label(text,pos,size,rotation=(math.pi/2,0,math.pi)):
    curve=bpy.data.curves.new('Stencil','FONT');curve.body=text;curve.size=size;curve.align_x='CENTER';curve.extrude=0
    obj=bpy.data.objects.new('Mark_'+text,curve);bpy.context.collection.objects.link(obj);obj.parent=root;obj.location=pos;obj.rotation_euler=rotation;curve.materials.append(M[5])
    bpy.context.view_layer.objects.active=obj;obj.select_set(True);bpy.ops.object.convert(target='MESH');obj.select_set(False)

def bolt(x,y,z):
    if level==0:
        cylinder('Fastener',.065,.022,(x,y,z),M[1],6,root)

def build_lod(lod):
    global root,level
    level=lod;root=empty('refinery' if lod==0 else 'refinery_LOD'+str(lod))
    # 4x4 cells overall. Rear 4x2 + front central 2x2 are solid.
    root['footprint_cells'] = [4, 4]
    root['reserved_cells'] = 16
    root['solid_cells'] = 12
    root['dock_cells'] = [1, 2]
    box('RearFoundation',(6.4,3.2,.32),(0,-1.6,.20),2,.10)
    box('RearHousing',(6.22,3.04,1.3),(0,-1.6,.99),2,.12)
    box('CentralFoundation',(3.2,3.2,.32),(0,1.6,.20),2,.10)
    for side in [-1,1]:
        x=side*2.4
        box('ServiceShoulder',(1.56,3.04,1.65),(x,-1.6,1.31),0,.10)
        box('RearSafetyCap',(1.56,.20,1.45),(x,-3.07,1.29),1,.045)
        for y in [-2.47,-.79]:
            box('RoofPanel',(1.40,1.42,.12),(x,y,2.17),0,.045)
            if level<2:
                box('VentBed',(.92,.73,.045),(x,y,2.25),2,.018)
                for k in range(5 if level==0 else 3):
                    box('VentFin',(.84,.05,.045),(x,y-.26+k*.13,2.29),mat=M[1],bevel=.006)
                for edge in [-1,1]:
                    bolt(x+edge*.55,y+.55,2.27)
        box('UtilityTower',(.50,.68,1.15),(x,-2.55,2.68),2,.06)
        box('TowerSafety',(.52,.08,.88),(x,-2.17,2.70),1,.02)
        cylinder('Antenna',.025,.76,(x,-2.65,3.22),M[1],8,root)
        box('FactionBadge',(.84,.035,.28),(x,-3.175,1.61),0,.02)
        box('SideStatus',(.035,.62,.08),(side*3.155,-1.52,1.20),mat=M[4],bevel=.008)
        # These two flat 1x2-cell channels are inside the square reservation.
        box('DockFoundation',(1.6,3.2,.10),(x,1.6,.09),mat=M[1],bevel=.022)
        for y in [.55,1.60,2.65]:
            box('DockDeck',(1.42,.97,.025),(x,y,.152),2,.01)
        for edge in [-1,1]:
            box('DockSafety',(.07,3.08,.015),(x+edge*.73,1.6,.172),1,.004)
            box('GuidanceStrip',(.032,2.70,.014),(x+edge*.60,1.6,.175),mat=M[4],bevel=.003)
        for y in [.7,1.7,2.7]:
            poly('DirectionArrow',[(x-.34,y+.06,.179),(x,y-.27,.179),(x+.34,y+.06,.179),(x+.34,y+.23,.179),(x,y-.08,.179),(x-.34,y+.23,.179)],[(0,1,2,3,4,5)],M[4])
        # Yellow receiver frame is recessed in the rear solid half.
        box('ReceiverFrame',(1.56,.24,1.78),(x,-.13,1.12),1,.065)
        box('ReceiverRecess',(1.27,.025,1.44),(x,-.003,1.09),2,.035)
        box('DockLamp_'+('L' if side<0 else 'R'),(.98,.02,.09),(x,-.002,1.69),mat=M[4],bevel=.009)
        if level<2:
            box('ReceiverSocket',(.89,.025,.46),(x,-.003,.95),mat=M[1],bevel=.035)
            label('01' if side<0 else '02',(x,-.002,1.89),.14)
    # Central storage projects to the front edge, separating the long lanes.
    box('CentralPlinth',(3.18,6.20,1.35),(0,0,.98),0,.12)
    box('IdentityPlate',(2.94,.06,.80),(0,3.13,.88),0,.035)
    if level<2:
        label('07',(0,3.168,.94),.48)
        label('ORE DEPOT',(0,3.169,.56),.17)
    box('BinSeat',(3.06,4.98,.22),(0,.16,1.76),2,.065)
    for x in [-1.41,1.41]:
        for y in [-2.20,2.52]:
            box('BinCorner',(.17,.18,1.27),(x,y,2.47),1,.035)
    for z in [1.92,3.07]:
        for y in [-2.20,2.52]:
            box('BinEndRim',(2.98,.12,.11),(0,y,z),mat=M[1],bevel=.018)
        for x in [-1.44,1.44]:
            box('BinSideRim',(.10,4.80,.11),(x,.16,z),mat=M[1],bevel=.018)
    for x in [-1.43,1.43]:
        box('GlassSide',(.018,4.58,1.07),(x,.16,2.49),mat=M[2],bevel=0)
    for y in [-2.14,2.46]:
        box('GlassEnd',(2.75,.018,1.07),(0,y,2.49),mat=M[2],bevel=0)
    box('GlassRoof',(2.77,4.60,.018),(0,.16,3.03),mat=M[2],bevel=0)
    for x in [-.47,.47]:
        box('RoofFrame',(.06,4.68,.05),(x,.16,3.08),mat=M[1],bevel=.007)
    nx,ny=(4,6) if level<2 else (3,4)
    for layer in range(2):
        for col in range(nx):
            for row in range(ny):
                if layer and (col+row)%3==0:
                    continue
                box('FixedOre',(2.55/nx-.05,4.30/ny-.05,.34),
                    (-1.275+(col+.5)*2.55/nx,-1.99+(row+.5)*4.30/ny,2.12+layer*.36),
                    mat=M[3],bevel=.025 if level==0 else 0)
    # Merge static geometry by material; keep berth indicators addressable.
    all_mesh=[o for o in root.children_recursive if o.type=='MESH']
    groups={}
    for obj in all_mesh:
        if obj.name.startswith(('DockLamp','FactionBadge')):continue
        groups.setdefault(obj.data.materials[0].name,[]).append(obj)
    for name,objects in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for o in objects:o.select_set(True)
        bpy.context.view_layer.objects.active=objects[0]
        bpy.ops.object.join();bpy.context.object.name=name+'_Mesh'
    for name,loc in [('DockLeft',(-2.6,5.8,0)),('DockRight',(2.6,5.8,0)),('EntranceLeft',(-2.6,9.6,0)),('EntranceRight',(2.6,9.6,0)),('ProductionLeft',(-12,-4.8,0)),('ProductionRight',(12,-4.8,0))]:
        empty(name,loc,root)
    bpy.context.view_layer.update()
    meshes=[o for o in root.children_recursive if o.type=='MESH']
    corners=[o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    low=[min(v[i] for v in corners) for i in range(3)]
    high=[max(v[i] for v in corners) for i in range(3)]
    assert low[0]>=-3.201 and high[0]<=3.201 and low[1]>=-3.201 and high[1]<=3.201, (low, high)
    triangles=sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons)
    if triangles>[24000,9000,2500][lod]:
        # Only simplify opaque surfaces; glass and indicators retain shape.
        ratio=([23000,8600,2250][lod]-300)/triangles
        for o in meshes:
            if 'Glass' in o.name or 'Lamp' in o.name:continue
            mod=o.modifiers.new('LOD simplification','DECIMATE');mod.ratio=ratio
            bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
    triangles=sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons)
    assert triangles<=[24000,9000,2500][lod], triangles
    bpy.ops.object.select_all(action='DESELECT')
    for o in [root,*root.children_recursive]:o.select_set(True)
    bpy.context.view_layer.objects.active=root
    filename='refinery.glb' if lod==0 else f'refinery_lod{lod}.glb'
    bpy.ops.export_scene.gltf(filepath=str(model_path(filename)),export_format='GLB',use_selection=True,export_yup=True,export_animations=False,export_extras=True)
    return {'lod':lod,'triangles':triangles,'meshes':len(meshes),'materials':len(groups),'file':filename}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version=0
M=materials()
reports=[build_lod(i) for i in range(3)]
# Packed textures make the source portable; export is already external-runtime ready.
for img in bpy.data.images:
    if img.source=='FILE':img.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(model_path('source/ore_depot.blend')))
(model_path('source/ore_depot_report.json')).write_text(json.dumps({'lods':reports,'world_size':[128,128,72],'footprint_cells':[4,4],'solid_cells':12,'dock_cells':[1,2],'reserved_cells':16,'scale':20,'lane_width':32,'lane_spacing':96,'temporary_stop_spacing':104,'cargo_visual':'fixed ~60%, no economy inventory','material_categories':6},indent=2),encoding='utf-8')
print('ORE_DEPOT_BUILD PASS',json.dumps(reports))
