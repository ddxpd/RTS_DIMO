import sys as _sys
from pathlib import Path as _Path
_blender_tools = _Path(__file__).resolve().parents[1]
_sys.path[:0] = [str(_Path(__file__).resolve().parent), str(_blender_tools), str(_blender_tools / "shared")]
from project_paths import model_path
"""Independent GAIA command platform; preserves all legacy base assets byte-for-byte.
Z up / +Y front. Three explicit LOD exports share portable trim-atlas materials.
"""
import bpy
import bmesh
import math
import sys
import json
import hashlib
import struct
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[3]
OUT=model_path('gaia_command_base.glb').parent
SOURCE=model_path('source')
REVIEW=ROOT/'assets/concept_art/gaia_command_base'
sys.path.insert(0,str(Path(__file__).parent))
sys.dont_write_bytecode=True
from gaia_materials import armor_maps, mechanical_maps, bake_armor, pbr_material

MATERIALS={}
LEVEL=0
PARTS={}
GROUPS={}
COUNTER=0


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def empty(name, parent=None, location=(0,0,0)):
    ob=bpy.data.objects.new(name,None)
    bpy.context.collection.objects.link(ob)
    ob.parent=parent
    ob.location=location
    return ob


def group(name, parent, location=(0,0,0)):
    ob=empty(name,parent,location)
    PARTS[ob]=[]
    GROUPS[name]=ob
    return ob


def activate(ob):
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active=ob


def finish(ob, name, parent, kind, tile=0, bevel=0, smooth=False):
    global COUNTER
    ob.name=name
    ob.parent=parent
    if bevel and LEVEL<2:
        activate(ob)
        mod=ob.modifiers.new('SilhouetteBevel','BEVEL')
        mod.width=bevel
        mod.segments=2 if LEVEL==0 else 1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    mesh=ob.data
    bm=bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.clear()
    mesh.materials.append(MATERIALS[kind])
    # Explicit trim UVs, exported to every LOD. Reuse is intentional for modular armor.
    uv=mesh.uv_layers.active or mesh.uv_layers.new(name='UVMap')
    dims=[max(v.co[i] for v in mesh.vertices)-min(v.co[i] for v in mesh.vertices) for i in range(3)]
    for poly in mesh.polygons:
        axis=max(range(3),key=lambda i:abs(poly.normal[i]))
        axes=[i for i in range(3) if i!=axis]
        low=[min(mesh.vertices[i].co[a] for i in poly.vertices) for a in axes]
        high=[max(mesh.vertices[i].co[a] for i in poly.vertices) for a in axes]
        grid=4 if kind=='armor' else 2
        index=(tile+COUNTER+poly.index)%16 if kind=='armor' else tile
        col,row=index%grid,index//grid
        for li in poly.loop_indices:
            v=mesh.vertices[mesh.loops[li].vertex_index].co
            xy=[(v[a]-low[k])/max(high[k]-low[k],.00001) for k,a in enumerate(axes)]
            if poly.area<.008:
                xy=[.5+u*.01 for u in xy]
            uv.data[li].uv=((col+.012+xy[0]*.976)/grid,(row+.012+xy[1]*.976)/grid)
        poly.use_smooth=smooth
    if smooth:
        mesh.set_sharp_from_angle(angle=math.radians(40))
    PARTS[parent].append(ob)
    COUNTER+=1
    return ob


def box(name,dims,pos,parent,kind='armor',tile=0,bevel=.035,rot=(0,0,0)):
    bpy.ops.mesh.primitive_cube_add(size=1)
    ob=bpy.context.object
    ob.dimensions=dims
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    finish(ob,name,parent,kind,tile,bevel)
    ob.location=pos
    ob.rotation_euler=rot
    return ob


def cylinder(name,radius,depth,pos,parent,kind='mechanical',tile=2,rot=(0,0,0),r2=None):
    segments=[64,32,12][LEVEL]
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=segments,radius=radius,depth=depth)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=segments,radius1=radius,radius2=r2,depth=depth)
    ob=bpy.context.object
    finish(ob,name,parent,kind,tile,.012 if LEVEL==0 else 0,True)
    ob.location=pos
    ob.rotation_euler=rot
    return ob


def shell(name,outline,z0,z1,parent,kind='armor',tile=0,top_scale=1.0,bevel=.035):
    n=len(outline)
    vertices=[(x,y,z0) for x,y in outline]+[(x*top_scale,y*top_scale,z1) for x,y in outline]
    faces=[tuple(reversed(range(n))),tuple(range(n,n*2))]
    faces.extend((i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n))
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(vertices,[],faces)
    mesh.update()
    ob=bpy.data.objects.new(name,mesh)
    bpy.context.collection.objects.link(ob)
    return finish(ob,name,parent,kind,tile,bevel)


def tapered(name,dims0,dims1,z0,z1,pos,parent,kind='armor',tile=0):
    x0,y0=dims0[0]/2,dims0[1]/2
    x1,y1=dims1[0]/2,dims1[1]/2
    vertices=[(-x0,-y0,z0),(x0,-y0,z0),(x0,y0,z0),(-x0,y0,z0),
              (-x1,-y1,z1),(x1,-y1,z1),(x1,y1,z1),(-x1,y1,z1)]
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(vertices,[],[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)])
    ob=bpy.data.objects.new(name,mesh)
    bpy.context.collection.objects.link(ob)
    finish(ob,name,parent,kind,tile,.035)
    ob.location=pos
    return ob


def beam(name,a,b,width,parent,kind='mechanical',tile=2):
    a,b=Vector(a),Vector(b)
    v=b-a
    ob=box(name,(width,width,v.length),(a+b)/2,parent,kind,tile,.015)
    ob.rotation_euler=v.to_track_quat('Z','Y').to_euler()
    return ob


def louver(name,dims,pos,parent,axis='front'):
    box(name+'Recess',dims,pos,parent,'mechanical',3,.015)
    if LEVEL==2:
        return
    width,depth,height=dims
    count=7 if LEVEL==0 else 4
    for i in range(count):
        z=pos[2]-height*.40+i*height*.80/(count-1)
        box(name+'Slat',(width*.91,.035,.045),(pos[0],pos[1]+depth*.55,z),parent,'mechanical',2,.007)


def text_mark(label,pos,size,parent,rotation=(0,0,0)):
    if LEVEL==2:
        return
    curve=bpy.data.curves.new('Stencil','FONT')
    curve.body=label
    curve.size=size
    curve.extrude=0
    curve.align_x='CENTER'
    ob=bpy.data.objects.new('Stencil_'+label,curve)
    bpy.context.collection.objects.link(ob)
    activate(ob)
    bpy.ops.object.convert(target='MESH')
    finish(ob,'Stencil_'+label,parent,'mechanical',1)
    ob.location=pos
    ob.rotation_euler=rotation


def join(parent):
    objects=PARTS[parent]
    if not objects:
        return
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.object.join()
    ob=objects[0]
    world=ob.matrix_world.copy()
    inv=parent.matrix_world.inverted()
    for v in ob.data.vertices:
        v.co=inv@world@v.co
    ob.location=(0,0,0)
    ob.rotation_euler=(0,0,0)
    ob.scale=(1,1,1)
    ob.name=parent.name+'Mesh'
    # Frozen triangulation makes exported budgets exact and LOD deterministic.
    activate(ob)
    tri=ob.modifiers.new('ExportTriangles','TRIANGULATE')
    bpy.ops.object.modifier_apply(modifier=tri.name)


def build_geometry(level):
    global LEVEL,PARTS,GROUPS,COUNTER
    LEVEL=level
    PARTS={}
    GROUPS={}
    COUNTER=0
    root=empty('GAIA_CommandBase')
    body=empty('PlatformBody',root)
    deck=group('Deck',body)
    spine=group('CentralSpine',body)
    tower=group('CommandTower',body)
    equipment=group('DeckEquipment',body)
    windows=group('FactionWindows',body)
    emitters=group('ThrusterEmitters',body)
    underside=group('Undercarriage',body)
    antenna=group('AntennaArray',body)
    # Continuous stepped outline: wide wings, long narrow fore/aft spine.
    outline=[(-8.8,-2.8),(-8.2,-3.45),(-2.05,-3.45),(-1.48,-4.9),
             (1.48,-4.9),(2.05,-3.45),(8.2,-3.45),(8.8,-2.8),
             (8.8,2.8),(8.2,3.45),(2.05,3.45),(1.35,4.9),
             (-1.35,4.9),(-2.05,3.45),(-8.2,3.45),(-8.8,2.8)]
    shell('ArmoredWingMonocoque',outline,2.30,3.05,deck,top_scale=.997,bevel=.065)
    lower=[(x*.90,y*.88) for x,y in outline]
    shell('RecessedMechanicalKeel',lower,1.35,2.35,underside,'mechanical',1,.92,.055)
    # Separate long armored sponsons shelter the four exposed gold drums.
    for sx in [-1,1]:
        for sy in [-1,1]:
            side=group('Reactor_'+('L' if sx<0 else 'R')+('F' if sy>0 else 'B'),body)
            x,y=sx*5.35,sy*4.02
            box('OverhangingEdgeDeck',(5.8,1.65,.54),(sx*5.95,sy*3.12,3.02),deck,bevel=.055)
            cylinder('GoldReactorDrum',.60,4.45,(x,y,2.22),side,'mechanical',0,(0,math.pi/2,0))
            for offset in [-2.29,2.29]:
                cylinder('ReactorEndCap',.69,.26,(x+offset,y,2.22),side,'mechanical',1,(0,math.pi/2,0))
                cylinder('EndCapInset',.49,.275,(x+offset,y,2.22),side,'mechanical',2,(0,math.pi/2,0))
            for offset in [-1.60,-.65,.65,1.60]:
                cylinder('DrumBand',.615,.052,(x+offset,y,2.22),side,'mechanical',2,(0,math.pi/2,0))
            for offset in [-2.12,2.12]:
                box('DrumMount',(.28,1.15,.32),(x+offset,y,2.76),side,'mechanical',1)
            if LEVEL<2:
                for dx in [-1.98,1.98]:
                    beam('FeedPipe',(x+dx,y-sy*.48,1.95),(x+dx,sy*1.8,1.58),.105,side)
            # Strong, recessed end-face windows rather than glow covering the hull.
            box('WingEndBlackInset',(.055,1.21,.35),(sx*8.89,sy*2.9,3.05),deck,'mechanical',3,.012)
            for i in range(3 if LEVEL<2 else 1):
                box('EndFaceBrace',(.09,.045,.35),(sx*8.94,sy*2.9+(i-1)*.35,3.05),deck,'mechanical',2,.007)
    # Sparse large real panel breaks, with baked detail within each modular panel.
    if LEVEL<2:
        for sx in [-1,1]:
            for row in range(4):
                for col in range(5):
                    box('WingDeckPanel',(1.12,1.10,.035),(sx*(2.3+col*1.28),-1.72+row*1.14,3.072),deck,bevel=.012)
            for i in range(8):
                x=sx*(1.8+i*.88)
                box('FasciaPanel',(.80,.045,.40),(x,3.96,3.04),deck,bevel=.007)
                box('FasciaPanelRear',(.80,.045,.40),(x,-3.96,3.04),deck,bevel=.007)
    # Fore/aft central command spine integrates into the deck instead of stacking boxes.
    spine_outline=[(-1.4,-5),(1.4,-5),(1.9,-3.0),(1.82,2.6),(1.28,5),(-1.28,5),(-1.82,2.6),(-1.9,-3)]
    shell('CentralCommandSpine',spine_outline,2.82,3.96,spine,top_scale=.83,bevel=.06)
    box('ForwardBridgeVisor',(1.77,.04,.28),(0,4.48,3.72),spine,'mechanical',3,.02)
    box('BridgeWindow',(1.48,.024,.055),(0,4.509,3.75),windows,'team',bevel=.006)
    for sx in [-1,1]:
        box('LateralWindowRecess',(.06,4.60,.19),(sx*1.60,-.30,3.62),spine,'mechanical',3,.015)
        box('LateralWindowRibbon',(.018,4.28,.036),(sx*1.64,-.30,3.64),windows,'team',bevel=.003)
        for y in [-3.4,-2.45,2.8,3.6]:
            box('SpineSidePanel',(.16,.65,.62),(sx*1.37,y,3.33),spine,bevel=.035)
    text_mark('G8-01',(0,3.72,4.013),.42,spine)
    text_mark('GAIA',(0,-4.20,3.998),.24,spine,(0,0,math.pi))
    # Battered, sloped command tower; successive ledges form the reference's silhouette.
    tapered('TowerFoundation',(3.65,3.15),(2.6,2.5),3.92,5.36,(0,-.35,0),tower)
    tapered('TowerUpper',(2.6,2.5),(1.62,1.70),5.36,6.67,(0,-.35,0),tower)
    box('TowerObservationLedge',(2.63,2.57,.18),(0,-.35,5.44),tower,'mechanical',2,.025)
    tapered('BridgeCabin',(1.62,1.70),(1.23,1.32),6.65,7.27,(0,-.35,0),tower)
    box('UpperRoof',(1.75,1.84,.16),(0,-.35,7.31),tower,'mechanical',1,.03)
    for sy in [-1,1]:
        box('TowerDarkWindow',(1.17,.035,.14),(0,-.35+sy*.73,6.86),tower,'mechanical',3,.016)
        box('TowerBlueWindow',(.94,.016,.032),(0,-.35+sy*.751,6.87),windows,'team',bevel=.002)
    for sx in [-1,1]:
        for i in range(3 if LEVEL<2 else 1):
            box('TowerArmorFacet',(.065,.58,.76),(sx*(1.22-i*.14),-.98+i*.60,5.18+i*.20),tower,bevel=.018,rot=(0,sx*-.28,0))
        louver('TowerVent',(.80,.09,.86),(sx*.71,-1.53,5.56),tower)
        beam('TowerExternalCable',(sx*1.12,-1.34,4.55),(sx*.66,-1.18,6.30),.07,tower)
    louver('MainTowerCooling',(.75,.10,1.35),(0,.99,4.85),tower)
    # Fitted armor panels follow the battered faces; avoid a plain stepped pyramid.
    if LEVEL<2:
        for sy in [-1,1]:
            for row in range(3):
                z=4.20+row*.37
                y=-.35+sy*(1.58-(z-3.92)*.225+.025)
                for x in [-1.13,-.66,.66,1.13]:
                    box('FittedLowerTowerPlate',(.43,.035,.33),(x,y,z),tower,bevel=.009,rot=(sy*.222,0,0))
            for row in range(3):
                z=5.62+row*.32
                y=-.35+sy*(1.25-(z-5.36)*.305+.025)
                for x in [-.76,-.25,.25,.76]:
                    box('FittedUpperTowerPlate',(.46,.035,.28),(x,y,z),tower,bevel=.009,rot=(sy*.296,0,0))
            box('ObservationWindowBank',(1.16,.065,.22),(0,-.35+sy*.79,6.91),tower,'mechanical',3,.015)
            for i in range(5):
                box('ObservationMullion',(.025,.07,.23),((i-2)*.22,-.35+sy*.81,6.91),tower,'mechanical',2,.004)
        for sx in [-1,1]:
            box('OverhangingObservationCabin',(.68,1.13,.34),(sx*1.05,-.68,6.02),tower,bevel=.045)
            box('CabinVisor',(.03,.89,.15),(sx*1.405,-.68,6.06),tower,'mechanical',3,.008)
            for row in range(3):
                z=4.25+row*.36
                x=sx*(1.825-(z-3.92)*.365+.018)
                for y in [-1.26,-.74,-.22,.30]:
                    box('TowerSidePanel',(.035,.48,.30),(x,y,z),tower,bevel=.008,rot=(0,-sx*.35,0))
        text_mark('01',(0,1.017,5.02),.25,tower,(math.pi/2,0,math.pi))
        for sx in [-1,1]:
            for y in [-3.45,3.42]:
                box('DeckServiceEquipment',(.86,.78,.19),(sx*2.62,y,3.42),equipment,'mechanical',1,.035)
                box('ServiceTopLid',(.77,.69,.045),(sx*2.62,y,3.54),equipment,bevel=.014)
            # Narrow pipes and junction blocks exposed underneath the perimeter.
            for y in [-1.15,0,1.15]:
                beam('ExposedUtilityPipe',(sx*2.4,y,1.67),(sx*7.8,y,1.67),.09,underside)
            for x in [2.7,4.4,6.2,7.6]:
                box('UnderwingJunction',(.50,.57,.40),(sx*x,0,1.45),underside,'mechanical',2,.025)
    # Distributed small control islands, not weapons.
    for sx in [-1,1]:
        for sy in [-1,1]:
            x,y=sx*6.62,sy*1.36
            tapered('AuxiliaryIsland',(1.1,.95),(.73,.69),3.08,3.78,(x,y,0),equipment)
            cylinder('SensorCap',.18,.20,(x,y,3.85),equipment,'mechanical',2)
            cylinder('AuxiliaryWhip',.019,.72,(x+.22,y,4.10),antenna)
            if LEVEL<2:
                box('IslandServiceDoor',(.30,.023,.38),(x,y+.40,3.42),equipment,'mechanical',1,.018)
                for j in range(3):
                    box('DeckIntake',(1.10,.075,.07),(sx*3.10,y+j*.12,3.13),equipment,'mechanical',1,.007)
    # Six broad suspended lift modules, structurally connected by struts.
    for sx in [-1,0,1]:
        for sy in [-1,1]:
            x,y=sx*5.65,sy*2.20
            beam('PodPylon',(x,y,1.78),(x,y,.86),.32,underside)
            box('PylonYoke',(1.48,.74,.17),(x,y,1.04),underside,'mechanical',2)
            tapered('LiftModuleShell',(2.65,1.38),(2.72,1.30),.03,.85,(x,y,0),underside)
            louver('LiftModuleIntake',(2.35,.045,.54),(x,y+.72,.45),underside)
            box('PodSideAccess',(.045,.94,.49),(x+1.39,y,.47),underside,bevel=.02)
            box('ThrusterChamber',(2.23,1.02,.065),(x,y,.055),underside,'mechanical',1,.025)
            for j in range(3):
                box('LiftEmissionSlit',(1.89,.06,.015),(x,y+(j-1)*.27,.003),emitters,'emission',bevel=.003)
            if LEVEL==0:
                for dx in [-1.00,1.00]:
                    beam('HydraulicBrace',(x+dx,y,.84),(x+dx*.6,y,1.60),.09,underside)
    # Visible underside beams, cable trays and integrated service hatches.
    for x in [-6,-3,0,3,6]:
        box('KeelCrossmember',(.19,5.0,.24),(x,0,1.40),underside,'mechanical',2)
        box('BellyMaintenancePanel',(1.7,1.52,.06),(x,0,1.30),underside,'mechanical',1,.025)
    if LEVEL<2:
        for x in [-6.3,-3.2,3.2,6.3]:
            beam('LongPipe',(x,-2.45,1.49),(x,2.45,1.49),.065,underside)
        for sx in [-1,1]:
            for i in range(14):
                box('DeckRailPost',(.035,.035,.28),(sx*(2.1+i*.47),-2.32,3.21),equipment,'mechanical',2,.005)
            beam('DeckHandrail',(sx*2.1,-2.32,3.35),(sx*8.21,-2.32,3.35),.035,equipment)
    # Independent radar yaw and pitch, with a concave dish and rear support ribs.
    cylinder('RadarPedestal',.29,.34,(0,-.35,7.55),tower,'mechanical',2)
    yaw=empty('RadarYaw',body,(0,-.35,7.72))
    pitch=empty('RadarPitch',yaw)
    dish=group('RadarDish',pitch)
    radius=.62
    segments=[64,32,12][LEVEL]
    rings=[9,5,3][LEVEL]
    verts=[]
    faces=[]
    for j in range(rings+1):
        r=max(.002,radius*j/rings)
        for i in range(segments):
            a=math.tau*i/segments
            verts.append((r*math.cos(a),.22*(r/radius)**2,r*math.sin(a)+.26))
    for j in range(rings):
        for i in range(segments):
            faces.append((j*segments+i,j*segments+(i+1)%segments,(j+1)*segments+(i+1)%segments,(j+1)*segments+i))
    mesh=bpy.data.meshes.new('ConcaveRadarSurface')
    mesh.from_pydata(verts,[],faces)
    ob=bpy.data.objects.new('ConcaveRadarSurface',mesh)
    bpy.context.collection.objects.link(ob)
    finish(ob,'ConcaveRadarSurface',dish,'armor',smooth=True)
    activate(ob)
    m=ob.modifiers.new('DishThickness','SOLIDIFY')
    m.thickness=.018
    bpy.ops.object.modifier_apply(modifier=m.name)
    for a in [0,math.pi*.5,math.pi,math.pi*1.5]:
        beam('DishFeedSupport',(.58*math.cos(a),.20,.26+.58*math.sin(a)),(0,.68,.26),.018,dish)
    cylinder('RadarFeed',.065,.16,(0,.65,.26),dish,'mechanical',2,(math.pi/2,0,0))
    # Asymmetric antennas create the recognizable command silhouette.
    for x,y,h in [(-.58,-.55,1.59),(.57,-.90,1.15),(-.9,.40,.75)]:
        cylinder('AntennaFoot',.095,.13,(x,y,7.41),antenna,'mechanical',1)
        cylinder('Mast',.035,h,(x,y,7.41+h/2),antenna,'mechanical',2,r2=.011)
        if LEVEL<2:
            for z in [7.65,7.95]:
                beam('AntennaCrossbar',(x-.13,y,z),(x+.13,y,z),.018,antenna)
    for parent in PARTS:
        join(parent)
    # Enforce the agreed presentation envelope once, consistently for all LODs.
    bpy.context.view_layer.update()
    meshes=[ob for ob in root.children_recursive if ob.type=='MESH']
    points=[ob.matrix_world@v.co for ob in meshes for v in ob.data.vertices]
    low=Vector(tuple(min(p[i] for p in points) for i in range(3)))
    high=Vector(tuple(max(p[i] for p in points) for i in range(3)))
    factors=Vector((18/(high.x-low.x),10/(high.y-low.y),9/(high.z-low.z)))
    # Apply the same tiny envelope correction to positions and geometry, not root scale.
    for ob in root.children_recursive:
        ob.location=Vector((ob.location.x*factors.x,ob.location.y*factors.y,ob.location.z*factors.z))
        if ob.type=='MESH':
            for v in ob.data.vertices:
                v.co=Vector((v.co.x*factors.x,v.co.y*factors.y,v.co.z*factors.z))
    body.location.z=-low.z*factors.z
    root['display_scale']=[320/18,192/10,16]
    root['deployment_clearance']=12.0
    root['lod']=level
    root['construction_animation']='Deferred: awaiting user construction reference'
    root['asset_scope']='Standalone art asset; no gameplay or network integration'
    return root


def share_glb_textures(path, overwrite=False):
    """GLB geometry with adjacent shared image URIs: all three LODs use one atlas set."""
    raw=path.read_bytes()
    json_length=struct.unpack_from('<I',raw,12)[0]
    doc=json.loads(raw[20:20+json_length])
    bin_offset=20+json_length
    bin_length=struct.unpack_from('<I',raw,bin_offset)[0]
    binary=raw[bin_offset+8:bin_offset+8+bin_length]
    image_views=set()
    for im in doc.get('images',[]):
        index=im.pop('bufferView')
        image_views.add(index)
        view=doc['bufferViews'][index]
        data=binary[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']]
        name='gaia_shared_'+im['name']+'.png'
        target=model_path(name)
        if target.exists() and not overwrite:
            assert target.read_bytes()==data,'Different LOD texture contents'
        else:
            target.write_bytes(data)
        im['uri']=name
        im.pop('mimeType',None)
    views=[]
    remap={}
    new_binary=bytearray()
    for index,view in enumerate(doc['bufferViews']):
        if index in image_views:
            continue
        while len(new_binary)%4:
            new_binary.append(0)
        remap[index]=len(views)
        copy=dict(view)
        copy['byteOffset']=len(new_binary)
        new_binary.extend(binary[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']])
        views.append(copy)
    for accessor in doc['accessors']:
        if 'bufferView' in accessor:
            accessor['bufferView']=remap[accessor['bufferView']]
    doc['bufferViews']=views
    doc['buffers'][0]['byteLength']=len(new_binary)
    encoded=json.dumps(doc,separators=(',',':')).encode()
    encoded+=b' '*((-len(encoded))%4)
    new_binary+=b'\0'*((-len(new_binary))%4)
    total=12+8+len(encoded)+8+len(new_binary)
    path.write_bytes(struct.pack('<III',0x46546C67,2,total)+struct.pack('<I4s',len(encoded),b'JSON')+encoded+struct.pack('<I4s',len(new_binary),b'BIN\0')+new_binary)


def main():
    preserved=[model_path('base.glb'),SOURCE/'ironfront_models.blend',ROOT/'tools/blender/legacy_base/create_base.py']
    before={str(p.relative_to(ROOT)):digest(p) for p in preserved}
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    REVIEW.mkdir(parents=True,exist_ok=True)
    (REVIEW/'.gdignore').touch()
    print('GAIA: generating trim atlases',flush=True)
    color,orm=armor_maps(OUT)
    normal=bake_armor(OUT,color,orm)
    MATERIALS['armor']=pbr_material('GAIA_Armor',color,normal,orm)
    MATERIALS['mechanical']=pbr_material('GAIA_Mechanical',*mechanical_maps(OUT))
    for kind,col,energy in [('team',(.018,.16,.26,1),.45),('emission',(.025,.24,.40,1),2.0)]:
        mat=bpy.data.materials.new('GAIA_'+kind.title())
        mat.use_nodes=True
        p=mat.node_tree.nodes.get('Principled BSDF')
        p.inputs['Base Color'].default_value=col
        p.inputs['Metallic'].default_value=.35
        p.inputs['Roughness'].default_value=.22
        p.inputs['Emission Color'].default_value=col
        p.inputs['Emission Strength'].default_value=energy
        MATERIALS[kind]=mat
    report={'source_dimensions':[18,10,9],'display_dimensions':[320,192,144],'display_scale':[320/18,192/10,16],
            'armor_atlas':4096,'mechanical_atlas':2048,'normal_method':'Cycles selected-to-active high detail armor trim bake; mechanical height normal',
            'ao_method':'Cycles high trim local AO baked into ORM.R','legacy_hashes':before,'lods':[]}
    roots=[]
    for level in range(3):
        print('GAIA: building LOD',level,flush=True)
        collection=bpy.data.collections.new('GAIA_LOD'+str(level))
        bpy.context.scene.collection.children.link(collection)
        layer=bpy.context.view_layer.layer_collection.children[collection.name]
        bpy.context.view_layer.active_layer_collection=layer
        root=build_geometry(level)
        roots.append(root)
        meshes=[o for o in root.children_recursive if o.type=='MESH']
        bpy.context.view_layer.update()
        points=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
        entry={'level':level,'triangles':sum(len(o.data.polygons) for o in meshes),'meshes':len(meshes),
               'materials':len({m.name for o in meshes for m in o.data.materials}),
               'bounds_min':[min(p[i] for p in points) for i in range(3)],'bounds_max':[max(p[i] for p in points) for i in range(3)]}
        assert entry['triangles'] <= [150000,45000,12000][level],entry
        assert entry['meshes']<=20 and entry['materials']<=6,entry
        for ob in meshes:
            assert ob.data.uv_layers.active is not None
            assert all(math.isfinite(c) for v in ob.data.vertices for c in v.co)
        report['lods'].append(entry)
        bpy.ops.object.select_all(action='DESELECT')
        for ob in [root,*root.children_recursive]:
            ob.select_set(True)
        bpy.context.view_layer.objects.active=root
        suffix='' if level==0 else '_lod'+str(level)
        bpy.ops.export_scene.gltf(filepath=str(model_path('gaia_command_base'+suffix+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_animations=False,export_extras=True)
        share_glb_textures(model_path('gaia_command_base'+suffix+'.glb'), overwrite=level==0)
        collection.hide_render=level!=0
        collection.hide_viewport=level!=0
    assert before=={str(p.relative_to(ROOT)):digest(p) for p in preserved},'Legacy asset changed'
    report['legacy_unchanged']=True
    report['construction_animation']='not implemented; awaiting reference'
    report['texture_packaging']='GLBs reference adjacent gaia_shared_*.png; deliver together'
    report['presentation']={'scene':'res://assets/art/buildings/gaia/gaia_command_base.tscn','preview':'res://tests/previews/gaia_command_base_preview.tscn',
        'clearance':12,'idle_bob_amplitude':0.5,'idle_period_seconds':6,'takeoff_landing_seconds':6,'lift':96,
        'cruise_pitch_degrees':2,'radar_period_seconds':24,'lod_out_distances':[950,1850],'lod_in_distances':[850,1750],
        'animation_delivery':'Independent Godot controller; GLB contains rigid part hierarchy, not embedded animation clips'}
    (SOURCE/'gaia_command_base_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'gaia_command_base.blend'))
    print('GAIA_BUILD PASS',json.dumps(report),flush=True)


if __name__=='__main__':
    main()
