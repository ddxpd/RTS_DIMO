import sys as _sys
from pathlib import Path as _Path
_blender_tools = _Path(__file__).resolve().parents[1]
_sys.path[:0] = [str(_Path(__file__).resolve().parent), str(_blender_tools), str(_blender_tools / "shared")]
from project_paths import model_path
"""Independent hover mining platform. Z up / +Y front, exported Y up / -Z front."""
import bpy
import math
import sys
import json
import random
import shutil
import numpy as np
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).parent))
sys.dont_write_bytecode = True
from create_bunker import material, empty, cube, cylinder, cone, torus

OUT = ROOT / 'assets/models'
REVIEW = ROOT / 'assets/concept_art/hover_harvester'
RNG = random.Random(2581)


def join_direct(node, name):
    meshes = [o for o in node.children if o.type == 'MESH']
    if not meshes:
        return
    bpy.ops.object.select_all(action='DESELECT')
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    ob = meshes[0]
    # Canonical origin makes arm pivots and cargo levels predictable in the engine.
    world = ob.matrix_world.copy()
    for v in ob.data.vertices:
        v.co = node.matrix_world.inverted() @ world @ v.co
    ob.location = (0,0,0)
    ob.rotation_euler = (0,0,0)
    ob.scale = (1,1,1)
    ob.name = name


def skin_texture():
    n=1024
    gen=np.random.default_rng(1234)
    y,x=np.mgrid[0:n,0:n].astype(np.float32)/n
    noise=gen.random((n,n)).astype(np.float32)
    shade=.89+noise*.07
    edge=np.minimum(np.minimum(x,1-x),np.minimum(y,1-y))
    shade-=np.exp(-edge*75)*.12
    # Sparse abrasions only; panel joints and access hatches are actual geometry.
    for i in range(170):
        px,py=gen.integers(4,n-4,2)
        length=int(gen.integers(2,21))
        shade[py:min(n,py+1),px:min(n,px+length)]*=gen.uniform(.50,.85)
    pixels=np.ones((n,n,4),np.float32)
    pixels[:,:,:3]=shade[:,:,None]
    im=bpy.data.images.new('harvester_surface',width=n,height=n,alpha=False)
    im.pixels.foreach_set(pixels.ravel())
    im.filepath_raw=str(model_path('harvester_surface.png'))
    im.file_format='PNG'
    im.save()
    im.pack()
    return im


def metal(name,color,metallic,roughness,texture):
    mat=material(name,color,metallic,roughness)
    nodes,links=mat.node_tree.nodes,mat.node_tree.links
    # Portable colored images avoid exporter-dependent procedural node recognition.
    values=np.empty(1024*1024*4,np.float32)
    texture.pixels.foreach_get(values)
    values=values.reshape((1024,1024,4))
    values[:,:,:3]*=np.array(color,np.float32)
    im=bpy.data.images.new(name+'_BaseColor',width=1024,height=1024,alpha=False)
    im.pixels.foreach_set(values.ravel())
    im.filepath_raw=str(model_path('harvester_'+name.lower()+'.png'))
    im.file_format='PNG'
    im.save()
    im.pack()
    tex=nodes.new('ShaderNodeTexImage')
    tex.image=im
    links.new(tex.outputs['Color'],nodes.get('Principled BSDF').inputs['Base Color'])
    return mat


def beam(name,a,b,width,depth,mat,parent):
    a,b=Vector(a),Vector(b)
    vec=b-a
    ob=cube(name,(width,depth,vec.length),(a+b)/2,mat,parent,.015)
    ob.rotation_euler=vec.to_track_quat('Z','Y').to_euler()
    return ob


def bolt(pos,node,mat,r=.022,rot=(0,0,0)):
    cylinder('FlushFastener',r,.012,pos,mat,8,node,rot)


def hull_shell(name,width,y0,y1,z0,z1,mat,node):
    # Chamfered perimeter plus sloped front shoulders, not stacked cube silhouettes.
    outline=[(-width*.36,y0), (width*.36,y0), (width*.5,y0+.18),
             (width*.5,y1-.16),(width*.32,y1),(-width*.32,y1),
             (-width*.5,y1-.16),(-width*.5,y0+.18)]
    verts=[(x,y,z0) for x,y in outline]
    for x,y in outline:
        z=z1-.17 if y>y1-.20 else z1
        verts.append((x*.88,y,z))
    faces=[tuple(reversed(range(8))),tuple(range(8,16))]
    for i in range(8):
        j=(i+1)%8
        faces.append((i,j,j+8,i+8))
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(verts,[],faces)
    ob=bpy.data.objects.new(name,mesh)
    bpy.context.collection.objects.link(ob)
    ob.parent=node
    mesh.materials.append(mat)
    bpy.context.view_layer.objects.active=ob
    ob.select_set(True)
    bevel=ob.modifiers.new('MachinedEdges','BEVEL')
    bevel.width=.035
    bevel.segments=2
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(island_margin=.03)
    bpy.ops.object.mode_set(mode='OBJECT')
    return ob


def shard(name,pos,r,h,parent,mat):
    phase=RNG.random()*math.tau
    verts=[]
    for z,scale in [(0,.8),(h*.73,1)]:
        for i in range(5):
            a=phase+i*math.tau/5
            verts.append((r*math.cos(a)*scale,r*math.sin(a)*scale,z))
    verts.append((r*.2,-r*.1,h))
    faces=[tuple(reversed(range(5)))]
    for i in range(5):
        j=(i+1)%5
        faces.extend([(i,j,j+5,i+5),(i+5,j+5,10)])
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(verts,[],faces)
    ob=bpy.data.objects.new(name,mesh)
    bpy.context.collection.objects.link(ob)
    ob.parent=parent
    ob.location=pos
    ob.rotation_euler=(RNG.uniform(-.28,.28),RNG.uniform(-.28,.28),0)
    mesh.materials.append(mat)


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    REVIEW.mkdir(parents=True,exist_ok=True)
    (REVIEW/'.gdignore').touch()
    tex=skin_texture()
    white=metal('HH_CeramicArmor',(.70,.73,.74),.26,.36,tex)
    dark=metal('HH_GraphiteMechanism',(.035,.046,.058),.65,.41,tex)
    steel=metal('HH_MachinedSteel',(.19,.22,.25),.78,.29,tex)
    yellow=metal('HH_SafetyOchre',(.92,.60,.035),.3,.38,tex)
    black=material('HH_Recess',(.009,.014,.019),.15,.74)
    faction=material('HH_FactionPaint',(.06,.25,.52),.35,.32)
    glow=material('HH_ThrusterBlue',(.03,.42,.8),.15,.22,(.015,.5,1),3.0)
    mineral=material('HH_CargoCrystal',(.008,.12,.48),.08,.16,(.008,.18,.55),.30)

    root=empty('harvester')
    root['asset_role']='ground_hover_mining_platform'
    root['authoring_axes']='Z up / +Y front; glTF Y up / -Z front'
    root['capacity']=60
    body=empty('HoverBody',node=root)
    static=empty('HullAssembly',node=body)
    # Belly, modular sockets and broad front shell.
    hull_shell('LowerKeel',1.30,-1.12,1.20,.45,.77,dark,static)
    hull_shell('CentralMonocoque',1.36,-.40,1.19,.69,1.27,white,static)
    for side in [-1,1]:
        hull_shell('ShoulderFairing',.44,-.46,.95,.78,1.19,white,static).location.x=side*.65
        cube('SafetyShoulder',(.12,.46,.35),(side*.79,.55,.96),yellow,static,.055)
        cube('HipEquipment',(.24,.42,.28),(side*.78,-.14,.67),dark,static,.05)
        cube('HipFace',(.025,.30,.17),(side*.91,-.14,.68),steel,static,.015)
        for y in [-.48,-.10,.29,.72]:
            bolt((side*.56,y,1.285),static,steel)
        for i in range(5):
            cube('SideVent',(.026,.040,.16),(side*.667,-.25+i*.075,1.04),black,static,.004)
        cube('TeamStripe',(.105,.55,.018),(side*.49,.20,1.289),faction,static,.012)
        cube('ArmorSeam',(.012,.38,.006),(side*.29,.35,1.279),dark,static,.001)
    cube('NoseBezel',(.53,.16,.27),(0,1.175,.99),dark,static,.06)
    cube('NoseSensorGlass',(.40,.025,.105),(0,1.261,1.02),black,static,.025)
    cube('NoseBlueSensor',(.30,.014,.044),(0,1.279,1.025),glow,static,.012)
    cube('RoofServiceInset',(.55,.30,.028),(0,-.18,1.28),dark,static,.045)
    for i in range(6):
        cube('RoofLouver',(.44,.018,.018),(0,-.29+i*.043,1.302),steel,static,.004)
    for x in [-.44,.44]:
        cube('BellyRail',(.095,1.85,.10),(x,-.04,.44),steel,static,.018)
    # Rear freight cassette, visibly independent of the forward chassis.
    cube('CargoMount', (1.34,1.23,.16),(0,-.80,.77),dark,static,.055)
    cube('CargoFloor',(1.22,1.11,.10),(0,-.80,.91),steel,static,.035)
    for x in [-.50,.50]:
        cube('RearDockHousing',(.36,.15,.31),(x,-1.43,.66),dark,static,.035)
        cube('RearDockInset',(.23,.018,.18),(x,-1.517,.67),black,static,.02)
        cube('RearDockRim',(.14,.024,.08),(x,-1.529,.67),steel,static,.012)
    frame=empty('CargoFrame',node=body)
    # Open transport pallet: low armored corners, split rails, no roof or glazing.
    for x in [-.63,.63]:
        for y in [-1.37,-.23]:
            cube('YellowCornerGuard',(.17,.18,.31),(x,y,1.08),yellow,frame,.035)
            bolt((x,y-.095,1.12),frame,steel,.025,(math.pi/2,0,0))
        cube('SideFrameRail',(.10,1.15,.12),(x,-.80,1.12),steel,frame,.025)
        cube('SideSafetyRail',(.12,.74,.035),(x,-.80,1.20),yellow,frame,.012)
        for y in [-1.12,-.48]:
            cube('PalletSideArmor',(.11,.36,.20),(x,y,1.03),white,frame,.025)
    for y in [-1.37,-.23]:
        cube('CrossFrameRail',(1.23,.10,.18),(0,y,1.04),white,frame,.025)
    for x in [-.39,.39]:
        cube('CassetteLatch',(.20,.12,.15),(x,-1.42,.97),steel,frame,.02)
        cube('LatchYellow',(.105,.035,.08),(x,-1.49,.97),yellow,frame,.008)
    for level,name in enumerate(['CargoLow','CargoMid','CargoHigh']):
        layer=empty(name,node=body)
        # Overlapping packed layers avoid disconnected crystals floating in the bin.
        for row in range(4):
            for column in range(4):
                # Higher layers taper to a loose mound rather than a cubic stack.
                if level == 2 and (row in [0,3] or column in [0,3]):
                    continue
                if level == 1 and row in [0,3] and column in [0,3]:
                    continue
                x=-.405+column*.27+RNG.uniform(-.016,.016)
                y=-1.20+row*.265+RNG.uniform(-.016,.016)
                z=.98+level*.245
                shard('StoredMineral',(x,y,z),RNG.uniform(.12,.15),RNG.uniform(.33,.43),layer,mineral)
        join_direct(layer,name+'Mesh')
    # Two broad layered hover discs, with readable concentric mechanical rings.
    for side,label in [(-1,'L'),(1,'R')]:
        pod=empty('Thruster_'+label,(side*1.15,-.03,.70),body)
        cube('SupportSpar',(.48,.37,.16),(-side*.44,0,.02),steel,pod,.025)
        cylinder('TurbineBody',.59,.25,(0,0,0),dark,48,pod)
        cone('UpperArmorSlope',.595,.48,.18,(0,0,.205),white,48,pod)
        torus('SafetyRing',.49,.045,(0,0,.28),yellow,pod)
        cylinder('TurbineTopRecess',.335,.03,(0,0,.30),black,40,pod)
        torus('TopMetalLip',.335,.018,(0,0,.32),steel,pod)
        cylinder('LowerLip',.51,.075,(0,0,-.15),steel,48,pod)
        cylinder('EngineRecess',.43,.06,(0,0,-.205),black,40,pod)
        torus('EngineEmissionRing',.405,.029,(0,0,-.238),glow,pod)
        cylinder('EngineCore',.34,.025,(0,0,-.24),glow,40,pod)
        for i in range(12):
            a=i*math.tau/12
            bolt((.53*math.cos(a),.53*math.sin(a),.265),pod,steel,.018)
            cube('PodBandPanel',(.034,.13,.15),(.594*math.cos(a),.594*math.sin(a),-.012),steel,pod,.008,(0,0,a))
        for a in [0,math.pi]:
            cube('PodYellowTab',(.13,.18,.025),(.51*math.cos(a),0,.30),yellow,pod,.018)
        fan=empty('Fan_'+label,(0,0,.335),pod)
        cylinder('FanHub',.105,.045,(0,0,.005),steel,20,fan)
        for i in range(9):
            a=i*math.tau/9
            cube('FanBlade',(.07,.23,.018),(.20*math.sin(a),.20*math.cos(a),0),steel,fan,.005,(0,0,-a+.30))
        cone('ArmoredFanCap',.30,.235,.055,(0,0,.045),dark,40,fan)
        torus('CapOuterRing',.27,.009,(0,0,.063),steel,fan)
        torus('CapInnerRing',.18,.009,(0,0,.078),steel,fan)
        cylinder('CapCenter',.13,.023,(0,0,.078),dark,24,fan)
        join_direct(fan,'FanMesh_'+label)
        join_direct(pod,'ThrusterMesh_'+label)
    # Socket, protected upper link, telescoping forearm and opposed articulated jaws.
    for side,label in [(-1,'L'),(1,'R')]:
        shoulder=empty('Arm_'+label,(side*.43,1.0,.84),body)
        cylinder('SocketCollar',.18,.16,(0,0,0),steel,24,shoulder,(math.pi/2,0,0))
        torus('SocketSafety',.148,.025,(0,.09,0),yellow,shoulder).rotation_euler=(math.pi/2,0,0)
        cube('UpperArmHousing',(.23,.47,.24),(0,.26,0),white,shoulder,.055)
        cube('UpperArmDorsal',(.13,.32,.027),(0,.27,.132),dark,shoulder,.015)
        for x in [-.075,.075]:
            cylinder('ExposedRam',.025,.40,(x,.35,-.12),steel,12,shoulder,(math.pi/2,0,0))
        extension=empty('ArmExtension_'+label,(0,.34,0),shoulder)
        cube('TelescopicSteel',(.145,.40,.13),(0,.16,0),steel,extension,.018)
        cube('WristHousing',(.25,.21,.21),(0,.39,0),dark,extension,.035)
        cube('WristGuard',(.17,.13,.023),(0,.40,.12),yellow,extension,.012)
        cylinder('WristDrive',.12,.29,(0,.42,0),steel,20,extension,(0,math.pi/2,0))
        for jaw_sign,suffix in [(-1,'A'),(1,'B')]:
            jaw=empty('Claw_'+label+'_'+suffix,(jaw_sign*.14,.43,0),extension)
            beam('FingerRoot',(0,0,0),(jaw_sign*.08,.17,-.035),.075,.11,yellow,jaw)
            beam('FingerTip',(jaw_sign*.08,.17,-.035),(jaw_sign*.005,.30,-.045),.065,.095,dark,jaw)
            cylinder('FingerPin',.045,.12,(0,0,0),steel,12,jaw,(math.pi/2,0,0))
            join_direct(jaw,'ClawMesh_'+label+'_'+suffix)
        join_direct(extension,'ForearmMesh_'+label)
        join_direct(shoulder,'UpperArmMesh_'+label)
    join_direct(static,'HullMesh')
    join_direct(frame,'CargoFrameMesh')
    bpy.context.view_layer.update()
    all_objects=[root,*root.children_recursive]
    for obj in all_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active=root
    if (model_path('harvester.glb')).exists() and not (REVIEW/'harvester-before.glb').exists():
        shutil.copy2(model_path('harvester.glb'),REVIEW/'harvester-before.glb')
    bpy.ops.export_scene.gltf(filepath=str(model_path('harvester.glb')),export_format='GLB',use_selection=True,export_yup=True,export_animations=False,export_extras=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(model_path('source/hover_harvester.blend')))
    meshes=[o for o in all_objects if o.type=='MESH']
    points=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
    report={'triangles':sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons),'meshes':len(meshes),
            'bounds_min':[min(p[i] for p in points) for i in range(3)],'bounds_max':[max(p[i] for p in points) for i in range(3)],
            'axes':'source Z up +Y front; GLB Y up -Z front','cargo_stages':[0,1,20,40],
            'cargo_style':'open low-rail pallet',
            'parts':[o.name for o in all_objects if o.type=='EMPTY'],'scope':'ground unit; visual hover only; no carry-to-bin or tipping animation'}
    assert report['meshes']<=22
    assert report['triangles']<45000
    (model_path('source/hover_harvester_report.json')).write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('HOVER_HARVESTER_BUILD PASS',json.dumps(report))


if __name__=='__main__':
    build()
