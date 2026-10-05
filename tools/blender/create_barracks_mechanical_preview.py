"""Standalone 4x3 military barracks study. Never writes runtime assets."""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
sys.dont_write_bytecode = True
from create_bunker import PROJECT_ROOT, material, empty, cube, cylinder, cone, torus
from create_mobile_barracks import merge as merge_meshes

OUT = os.path.join(PROJECT_ROOT, 'assets', 'concept_art', 'barracks_mechanical_v2')
REALISTIC = False
UNDERBODY = False


def clear_power_corner(objects, end=-1):
    outline = [(x, y*(-end)) for x, y in [(-6, -4), (-3.66, -4), (-3.66, -1.60), (-4.10, -1.12), (-6, -1.12)]]
    vertices = [(x, y, z) for z in [-.5, 5] for x, y in outline]
    faces = [(4, 3, 2, 1, 0), (5, 6, 7, 8, 9)]
    faces += [(i, (i+1)%5, (i+1)%5+5, i+5) for i in range(5)]
    cutter = mesh_object('PowerCornerClearanceCutter', vertices, faces, bpy.data.materials['V2_Armor'], None, 0)
    bpy.context.view_layer.update()
    for obj in objects:
        bpy.context.view_layer.objects.active = obj
        modifier = obj.modifiers.new('Propulsion clearance', 'BOOLEAN')
        modifier.operation = 'DIFFERENCE'
        modifier.solver = 'EXACT'
        modifier.object = cutter
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def check_pod_clearance(root, hull):
    from mathutils.bvhtree import BVHTree
    bpy.context.view_layer.update()
    prefixes = ('Power', 'HeatExchanger', 'UpperHeat', 'SegmentedMainArmor', 'StructuralCage',
                'SideMaintenance', 'ArmorLock', 'RearBulkhead', 'PortalArmor')
    objects = [o for o in hull.children if o.type == 'MESH' and o.name.startswith(prefixes) and o.data.polygons]
    def tree(obj):
        return BVHTree.FromPolygons([obj.matrix_world @ v.co for v in obj.data.vertices],
                                   [list(p.vertices) for p in obj.data.polygons])
    failures = []
    for suffix in ['LFront', 'LRear', 'RFront', 'RRear']:
        pod = bpy.data.objects['LiftPod'+suffix+'Mesh']
        pod_tree = tree(pod)
        for obj in objects:
            if pod_tree.overlap(tree(obj)):
                failures.append((suffix, obj.name))
    assert not failures, 'Housing/pod intersections: '+str(failures)
    root['housing_clearance_checked'] = '4 pods vs power/main armor; support attachments excluded'
    print('BARRACKS_CLEARANCE PASS four pods', flush=True)


def merge(node):
    meshes = [obj for obj in node.children if obj.type == 'MESH']
    if len(meshes) == 1:
        meshes[0].name = node.name + 'Mesh'
    elif meshes:
        merge_meshes(node)


def mesh_object(name, verts, faces, mat, parent, bevel=.025):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    if mat is not None:
        mesh.materials.append(mat)
    if bevel:
        bpy.context.view_layer.objects.active = obj
        mod = obj.modifiers.new('Machined bevel', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def tunnel(name, outer, inner, start, end, center, mat, parent):
    """Extruded closed annular XZ profile, with a genuinely open troop aperture."""
    n = len(outer)
    verts = [(x + center, y, z) for y in [start, end] for profile in [outer, inner] for x, z in profile]
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.extend([(i, j, n+j, n+i), (2*n+i, 3*n+i, 3*n+j, 2*n+j),
                      (i, 2*n+i, 2*n+j, j), (n+i, n+j, 3*n+j, 3*n+i)])
    return mesh_object(name, verts, faces, mat, parent, .035)


def panel(name, profile, y0, y1, center, mat, parent):
    n = len(profile)
    verts = [(x + center, y, z) for y in [y0, y1] for x, z in profile]
    faces = [tuple(range(n-1, -1, -1)), tuple(range(n, 2*n))]
    faces += [(i, (i+1) % n, (i+1) % n+n, i+n) for i in range(n)]
    return mesh_object(name, verts, faces, mat, parent)


def bar(name, a, b, radius, mat, parent):
    a, b = Vector(a), Vector(b)
    obj = cylinder(name, radius, (b-a).length, (a+b)*.5, mat, 12, parent)
    obj.rotation_euler = (b-a).to_track_quat('Z', 'Y').to_euler()
    return obj


def pipe(name, coords, radius, mat, parent):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    curve.resolution_u = 8
    spline = curve.splines.new('BEZIER')
    spline.bezier_points.add(len(coords)-1)
    for point, location in zip(spline.bezier_points, coords):
        point.co = location
        point.handle_left_type = 'AUTO'
        point.handle_right_type = 'AUTO'
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    curve.materials.append(mat)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target='MESH')
    return bpy.context.object


def build_flag(root, hull, steel, trim):
    base_x, base_y = .32, -.65
    cube('FlagSocket', (.48, .48, .20), (base_x, base_y, 5.65), steel, hull, .04)
    cylinder('FlagPole', .047, 2.60, (base_x, base_y, 7.05), steel, 16, hull)
    cone('FlagFinial', .085, 0, .17, (base_x, base_y, 8.42), trim, 16, hull)
    cloth = material('FlagBlueFabric', (.035, .19, .40), .0, .9)
    marking = material('FlagWhiteFabric', (.78, .82, .81), .0, .9)
    cloth.use_backface_culling = False
    marking.use_backface_culling = False
    columns, rows = 24, 12
    vertices = []
    for row in range(rows + 1):
        v = row / rows
        for col in range(columns + 1):
            u = col / columns
            vertices.append((base_x + .055 + 2.25*u, base_y, 8.24 - 1.12*v - .12*u))
    faces = []
    for row in range(rows):
        for col in range(columns):
            i = row*(columns+1) + col
            faces.append((i, i+1, i+columns+2, i+columns+1))
    flag = mesh_object('BarracksFlag', vertices, faces, cloth, root, 0)
    flag.data.materials.append(marking)
    for polygon in flag.data.polygons:
        col = polygon.index % columns
        row = polygon.index // columns
        polygon.material_index = int(3 <= col <= 4 or (9 <= col <= 17 and row in [4, 7]))
        polygon.use_smooth = True
    flag.shape_key_add(name='Basis')
    # Four travelling-wave components: the pole edge remains exactly pinned.
    for harmonic, component in [(1, 'Cos'), (1, 'Sin'), (2, 'Cos'), (2, 'Sin')]:
        key = flag.shape_key_add(name=f'Wind{harmonic}{component}')
        key.slider_min = -1
        for i, point in enumerate(key.data):
            u = (i % (columns+1)) / columns
            v = (i // (columns+1)) / rows
            phase = math.tau * (1.20*u if harmonic == 1 else 2.70*u) + v*.65
            wave = math.sin(phase) if component == 'Cos' else -math.cos(phase)
            point.co.y += u * (.24 if harmonic == 1 else .065) * wave
            point.co.z += u * (.045 if harmonic == 1 else .018) * wave
        for frame in range(1, 50):
            phase = math.tau*(frame-1)/48*harmonic
            key.value = math.cos(phase) if component == 'Cos' else math.sin(phase)
            key.keyframe_insert(data_path='value', frame=frame)
    flag.data.shape_keys.animation_data.action.name = 'Flag_Wind_Loop'
    scene = bpy.context.scene
    scene.render.fps = 24
    scene.frame_start = 1
    scene.frame_end = 49
    scene.frame_set(1)


def export(root, path):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [root, *root.children_recursive]:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True,
                             export_apply=False, export_animations=True, export_morph=True,
                             export_frame_range=True, export_force_sampling=True,
                             export_materials='EXPORT')


def build():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    armor = material('V2_Armor', (.56, .57, .54), .42, .47)
    trim = material('V2_ArmorEdge', (.73, .74, .69), .55, .38)
    steel = material('V2_Steel', (.15, .18, .20), .8, .36)
    dark = material('V2_Frame', (.045, .059, .071), .7, .44)
    black = material('V2_Recess', (.014, .022, .028), .25, .70)
    blue = material('V2_FactionPaint', (.06, .22, .40), .35, .43)
    silver = material('V2_Hydraulics', (.43, .50, .53), .92, .22)
    yellow = material('V2_Caution', (.65, .34, .05), .3, .52)
    lamp = material('V2_AmberLight', (.82, .44, .08), .15, .30, (.95, .5, .10), 4)
    glow = material('V2_BlueLight', (.04, .30, .7), .15, .28, (.02, .30, 1), 3)
    thrust = material('V2_Thrust', (.12, .5, .85), .1, .28, (.1, .6, 1), 5)
    root = empty('BarracksMechanicalV2')
    root['target_footprint'] = '128 x 96 world units; front width 4 cells, depth 3'
    root['intended_scale'] = 12.0
    root['preview_only'] = True
    hull = empty('Hull', node=root)
    if not UNDERBODY:
        cube('ArmoredKeel', (8.9, 5.85, .48), (0, -.22, .65), dark, hull, .12)
    for x in ([] if UNDERBODY else [-3.7, -1.4, 1.2, 3.6]):
        cube('LongitudinalRail', (.24, 6.05, .25), (x, -.15, .37), steel, hull, .045)
    for y in ([] if UNDERBODY else [-2.65, -.75, 1.45]):
        cube('CrossMember', (8.8, .24, .20), (0, y, .31), steel, hull, .035)
    # Six-sided canted shell profile: broad sloped shoulders, not a rectangular house.
    outer = [(-2.67, .95), (-2.67, 3.87), (-1.90, 5.55), (1.90, 5.55), (2.67, 3.87), (2.67, .95)]
    inner = [(-2.40, 1.10), (-2.40, 3.78), (-1.74, 5.28), (1.74, 5.28), (2.40, 3.78), (2.40, 1.10)]
    cage = [(x*.975, .95+(z-.95)*.975) for x,z in outer]
    tunnel('StructuralCage', cage, inner, -2.95, 2.05, 1.03, dark, hull)
    for i in range(4):
        y = -2.82 + i * 1.20
        tunnel('SegmentedMainArmor', outer, inner, y, y+1.10, 1.03, armor, hull)
    cube('TroopFloor', (4.75, 4.85, .16), (1.03, -.42, 1.08), steel, hull, .025)
    panel('RearBulkhead', inner, -2.97, -2.82, 1.03, armor, hull)
    cube('RearMaintenanceFrame', (3.84, .14, 2.36), (1.03, -3.02, 2.59), dark, hull, .10)
    for side in [-1, 1]:
        x = 1.03 + side * .94
        cube('RearServiceArmor', (1.66, .13, 2.08), (x, -3.12, 2.59), steel, hull, .08)
        for z in [1.84, 3.34]:
            cube('RearServiceLatch', (.25, .09, .13), (x, -3.22, z), silver, hull, .025)
    cube('RearVentRecess', (2.98, .12, .88), (1.03, -3.04, 4.52), black, hull, .07)
    for i in range(6):
        cube('RearVentLouver', (2.72, .15, .045), (1.03, -3.14, 4.20 + i * .125), steel, hull, .012)
    cube('RearIdentificationBand', (2.56, .08, .13), (1.03, -3.06, 5.08), trim, hull, .025)
    # One broad armored portal and one recessed gasket keep the entrance readable.
    portal_inner = [(-1.52, .98), (-1.52, 3.68), (-1.17, 4.08), (1.17, 4.08), (1.52, 3.68), (1.52, .98)]
    tunnel('PortalStructure', outer, portal_inner, 1.95, 2.36, 1.03, steel, hull)
    portal_outer = [(-2.57, .99), (-2.57, 3.88), (-1.85, 5.44), (1.85, 5.44), (2.57, 3.88), (2.57, .99)]
    mid = [(-1.73, 1.02), (-1.73, 3.80), (-1.30, 4.31), (1.30, 4.31), (1.73, 3.80), (1.73, 1.02)]
    tunnel('PortalArmor', portal_outer, mid, 2.36, 2.51, 1.03, armor, hull)
    tunnel('PortalInnerLip', mid, portal_inner, 2.39, 2.56, 1.03, dark, hull)
    cube('HeaderRecess', (2.12, .07, .14), (1.03, 2.56, 4.48), black, hull, .018)
    cube('HeaderAmber', (1.82, .035, .045), (1.03, 2.61, 4.48), lamp, hull, .008)
    panel('PortalFactionMark', [(.81, 4.83), (.81, 5.31), (1.38, 5.31), (1.59, 4.83)],
          2.515, 2.535, 1.03, blue, hull)
    # Blue identification armor lies on the broad canted shoulder and roof.
    for x in [2.12, -3.30]:
        z = 5.605 if x > 0 else 4.31
        cube('RoofBlueMarking', (.57, 4.12, .035), (x, -.50, z), blue, hull, .01)
    for side in [-1, 1]:
        for y in [-2.3, -.9, .5]:
            x = 1.03 + side*2.72
            cube('SideMaintenanceFrame', (.09, .93, 1.03), (x, y, 2.66), dark, hull, .07)
            cube('SideMaintenancePlate', (.10, .73, .81), (x+side*.035, y, 2.66), steel, hull, .04)
            for z in [2.35, 2.94]:
                cylinder('ArmorLock', .055, .035, (x+side*.10, y+.24, z), silver, 8, hull, rotation=(0, math.pi/2, 0))
    # Left power unit: squat canted equipment housing with deep front and rear heat exchangers.
    before_power = set(hull.children)
    p_outer = [(-1.40, .97), (-1.40, 2.94), (-.97, 4.22), (.97, 4.22), (1.40, 2.94), (1.40, .97)]
    p_inner = [(-1.18, 1.12), (-1.18, 2.85), (-.80, 4.0), (.80, 4.0), (1.18, 2.85), (1.18, 1.12)]
    core = [(x*.97,.97+(z-.97)*.97) for x,z in p_outer]
    tunnel('PowerCore', core, p_inner, -2.88, 1.93, -3.20, dark, hull)
    for y in [-2.82, -1.65, -.48, .69]:
        tunnel('PowerArmor', p_outer, p_inner, y, y+1.07, -3.20, armor, hull)
    for y in [-2.92, 1.95]:
        panel('PowerBulkhead',p_inner,y-.025,y+.025,-3.20,dark,hull)
        cube('HeatExchangerInset', (2.24, .16, 2.20), (-3.20, y, 2.25), black, hull, .09)
        for i in range(10):
            cube('HeatExchangerFin', (2.07, .16, .070), (-3.20, y+(.1 if y>0 else -.1), 1.31+i*.20), steel, hull, .013)
        for x in [-4.28, -2.12]:
            cube('HeatExchangerRib', (.11, .19, 2.32), (x, y, 2.27), trim, hull, .018)
        for i in range(3):
            cube('UpperHeatExchanger',(1.52,.10,.065),(-3.20,y+(.09 if y>0 else -.09),3.51+i*.14),steel,hull,.012)
    # Bundled pipes in the exposed gap connect the power module to the main hall.
    if REALISTIC and not UNDERBODY:
        power_meshes = [o for o in hull.children if o not in before_power and o.type == 'MESH']
        clear_power_corner(power_meshes, -1)
        clear_power_corner(power_meshes, 1)
        bulkhead_material = steel.copy()
        bulkhead_material.name = 'V3_Bulkhead'
        for end in [-1, 1]:
            outline = [(-4.10, end*1.12), (-3.64, end*1.60), (-3.64, end*(2.96 if end < 0 else 1.96))]
            for i in range(2):
                a, b = outline[i:i+2]
                vertices = [(a[0], a[1], .98), (b[0], b[1], .98),
                            (b[0], b[1], 4.17), (a[0], a[1], 4.17)]
                obj = mesh_object('PowerRecessBulkhead', vertices, [(0,1,2,3)], bulkhead_material, hull, 0)
                mod = obj.modifiers.new('Bulkhead thickness', 'SOLIDIFY')
                mod.thickness = .055
                bpy.context.view_layer.objects.active = obj
                bpy.ops.object.modifier_apply(modifier=mod.name)
    for j in range(3):
        x = -1.75+j*.16
        pipe('PowerFeed', [(x, .95, 2.0), (x, .95, 3.15), (x, .70, 3.54), (x, -.4, 3.58), (x+.18, -.65, 4.33)], .066, silver, hull)
        for z in [2.30, 2.65, 2.95]:
            cube('PipeClamp', (.14, .18, .065), (x, .95, z), dark, hull, .008)
    build_flag(root, hull, steel, trim)
    for x, y, z, radius, name in [(-3.20, -.52, 4.34, .74, 'PowerFan')]:
        cylinder('FanDarkWell', radius+.12, .19, (x,y,z-.05), black, 40, hull)
        torus('FanArmoredRim', radius, .10, (x,y,z+.045), trim, hull)
        fan = empty(name, (x,y,z+.10), root)
        cylinder('FanHub', .19, .18, (0,0,.045), steel, 24, fan)
        for i in range(10):
            a = i*math.tau/10
            cube('TurbineBlade', (.13,radius*.78,.05), (math.sin(a)*radius*.55,math.cos(a)*radius*.55,0), steel, fan, .015, rotation=(0,0,-a+.33))
        merge(fan)
        for i in range(2):
            a = i*math.pi/2
            bar('FanGuard', (x+math.cos(a)*radius,y+math.sin(a)*radius,z+.18),
                (x-math.cos(a)*radius,y-math.sin(a)*radius,z+.18), .025, dark, hull)
    for x in [-.43, 2.45]:
        cube('RoofHeatSink', (.59, 1.20, .34), (x,-2.0,5.74), dark, hull, .06)
        for i in range(7):
            cube('HeatSinkFin', (.65,.055,.27), (x,-2.47+i*.15,5.88), steel, hull, .012)
    for x, height in [(-.40,.65), (-.13,.40)]:
        cube('MastSocket', (.24,.26,.28), (x,-2.63,5.73), steel, hull, .045)
        cylinder('Mast', .025, height, (x,-2.63,5.87+height*.5), silver, 12, hull)
    # Exactly four lift pods, with recessed nozzles. Ground feet are separate.
    if UNDERBODY:
        from barracks_underbody import build_underbody
        build_underbody(root, hull, armor, steel, dark, black, silver, yellow, thrust)
    for side in ([] if UNDERBODY else [-1,1]):
        for end in [-1,1]:
            x, y = side*(4.52 if REALISTIC else 4.42), end*2.43
            suffix = ('L' if side<0 else 'R')+('Front' if end>0 else 'Rear')
            pod = empty('LiftPod'+suffix, (x,y,0), root)
            cube('EngineSaddle', (.98,1.30,.49), (0,0,2.77), steel, pod, .14)
            cube('EngineOuterArmor', (1.13,1.38,1.45), (0,0,2.04), armor, pod, .22)
            cube('EngineRecess', (.73,.055,.94), (0,.71,2.04), dark, pod, .05)
            cube('EnginePlate', (.47,.065,.82), (0,.747,2.07), trim, pod, .025)
            cube('EngineStatus', (.25,.05,.055), (0,.79,1.63), lamp, pod, .008)
            cone('EngineShoulder', .47,.56,.34,(0,0,1.23),steel,24,pod)
            # Open nozzle wall, no solid cap over the exhaust opening.
            rings = [(1.14,.43),(.54,.61),(.49,.61),(.54,.48),(1.11,.32)]
            vertices = [(math.cos(i*math.tau/32)*r,math.sin(i*math.tau/32)*r,z) for z,r in rings for i in range(32)]
            faces = [(j*32+i,j*32+(i+1)%32,(j+1)*32+(i+1)%32,(j+1)*32+i) for j in range(len(rings)-1) for i in range(32)]
            mesh_object('NozzleHeatShield',vertices,faces,dark,pod,0)
            torus('NozzleLip',.55,.045,(0,0,.51),steel,pod)
            cylinder('NozzleThroat',.31,.035,(0,0,1.10),black,24,pod)
            for i in range(8):
                a=i*math.tau/8
                bar('NozzleRib',(math.cos(a)*.46,math.sin(a)*.46,1.1),(math.cos(a)*.60,math.sin(a)*.60,.57),.025,steel,pod)
            merge(pod)
            jet = empty('Jet'+suffix,(x,y,.55),root)
            cone('ExhaustCore',.035,.35,1.40,(0,0,-.70),thrust,24,jet)
            merge(jet)
            jet.scale=(.001,)*3
            bar('EngineUpperMount',(side*3.20,y,2.85),(x,y,2.85),.16,steel,hull)
            bar('EngineBrace',(side*3.0,y,.85),(x,y,1.5),.11,steel,hull)
            lx, ly = side*3.35,end*3.05
            cube('LandingSocket',(.59,.55,.61),(lx,ly,1.81),armor,hull,.10)
            bar('LegUpperSleeve',(lx,ly,1.22),(lx,ly,2.12),.19,dark,hull)
            leg=empty('Leg'+suffix,(lx,ly,0),root)
            cylinder('LandingPiston',.115,1.34,(0,0,.90),silver,20,leg)
            cube('LegGuard',(.24,.18,.52),(0,-end*.12,.75),steel,leg,.04)
            foot=empty('Foot'+suffix,(0,0,.13),leg)
            cube('FootPad',(.92,.76,.20),(0,0,0),dark,foot,.06)
            cube('FootArmor',(.75,.61,.065),(0,0,.14),steel,foot,.025)
            for xx in [-.33,.33]:
                cube('FootCaution',(.065,.43,.022),(xx,0,.18),yellow,foot,.007)
            merge(foot)
            merge(leg)
    for side in [-1,1]:
        cube('RCSBlock',(.40,.65,.48),(side*4.25,.45,1.12),steel,hull,.08)
        for y in [.27,.62]:
            cylinder('LateralPort',.10,.16,(side*4.49,y,1.12),black,16,hull,rotation=(0,math.pi/2,0))
    # Split sliding door leaves and a mechanically hinged load ramp.
    for side in [-1,1]:
        leaf=empty('Door'+('L' if side<0 else 'R'),(1.03,2.25,1.10),root)
        cube('DoorBacking',(1.49,.13,2.89),(side*.75,0,1.445),dark,leaf,.04)
        cube('DoorArmorPlate', (1.40, .15, 2.74), (side*.75, .08, 1.445), steel, leaf, .035)
        merge(leaf)
    ramp=empty('Ramp',(1.03,2.55,.96),root)
    length=1.52
    cube('RampBack',(3.03,length,.13),(0,length*.5,0),dark,ramp,.04)
    cube('RampDeck',(2.81,length-.12,.04),(0,length*.5,.095),steel,ramp,.025)
    for x in [-1.43,1.43]:
        cube('RampEdge',(.15,length,.12),(x,length*.5,.10),steel,ramp,.025)
        cube('RampTipMark', (.15, .22, .02), (x, length-.16, .17), yellow, ramp, .008)
        cube('RampUnderRib',(.16,length,.19),(x*.73,length*.5,-.11),steel,ramp,.025)
    for i in range(5):
        cube('RampTread',(2.60,.045,.025),(0,.16+i*.29,.13),steel,ramp,.008)
    for x in [-1.27,-.60,.60,1.27]:
        cylinder('RampHinge',.115,.23,(x,.02,0),steel,20,ramp,rotation=(0,math.pi/2,0))
    merge(ramp)
    for side in [-1,1]:
        # The actuator assemblies are updated from two attachment points in pose().
        barrel=cylinder('RampCylinder'+str(side),.073,1,(0,0,0),steel,16,root)
        rod=cylinder('RampRod'+str(side),.038,1,(0,0,0),silver,16,root)
    if REALISTIC and not UNDERBODY:
        check_pod_clearance(root, hull)
    merge(hull)
    pose(root,0,0,-.56,1,0)
    return root


def actuator(obj, a, b, radius):
    a,b=Vector(a),Vector(b)
    obj.location=(a+b)*.5
    obj.rotation_mode='XYZ'
    obj.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    obj.scale=(1,1,(b-a).length)


def pose(root,height,retraction,ramp_angle,doors,engine):
    if root.get('underbody', False):
        from barracks_underbody import pose_underbody
        pose_underbody(root,height,retraction,ramp_angle,doors,engine)
        return
    root.location.z=height
    for suffix in ['LFront','LRear','RFront','RRear']:
        bpy.data.objects['Leg'+suffix].location.z=retraction
        foot=bpy.data.objects['Foot'+suffix]
        foot.rotation_mode='XYZ'
        foot.rotation_euler.x=retraction/.9*math.pi/2
        jet=bpy.data.objects['Jet'+suffix]
        jet.scale=(1,1,engine) if engine>.01 else (.001,)*3
    ramp=bpy.data.objects['Ramp']
    ramp.rotation_mode='XYZ'
    ramp.rotation_euler.x=ramp_angle
    for side in [-1,1]:
        bpy.data.objects['Door'+('L' if side<0 else 'R')].location.x=1.03+side*1.30*doors
        a=Vector((1.03+side*1.59,2.43,1.77))
        b=Vector((1.03+side*1.45,2.55+math.cos(ramp_angle)*1.10,.96+math.sin(ramp_angle)*1.10))
        middle=a.lerp(b,.60)
        actuator(bpy.data.objects['RampCylinder'+str(side)],a,middle,.073)
        actuator(bpy.data.objects['RampRod'+str(side)],middle,b,.038)
    bpy.context.view_layer.update()


def validate(root):
    meshes=[o for o in root.children_recursive if o.type=='MESH']
    solid=[o for o in meshes if not o.name.startswith('Jet')]
    points=[o.matrix_world@Vector(p) for o in solid for p in o.bound_box]
    low=[min(p[i] for p in points) for i in range(3)]
    high=[max(p[i] for p in points) for i in range(3)]
    triangles=sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons)
    assert low[0]>=-128/24 and high[0]<=128/24,(low,high)
    assert low[1]>=-4 and high[1]<=4,(low,high)
    assert low[2]>-.04 and high[2]<104/12,(low,high)
    assert triangles<65000,triangles
    return {'bounds_min':low,'bounds_max':high,'triangles':triangles,'meshes':len(meshes),'target_world_footprint':[128,96],'scale':12,'preview_only':True}


def main():
    os.makedirs(OUT,exist_ok=True)
    root=build()
    report=validate(root)
    if REALISTIC:
        from barracks_realism_materials import prepare_materials
        assert report['triangles'] < 40000
        report['materials'] = prepare_materials(root, OUT)
        report['housing_clearance'] = root['housing_clearance_checked']
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'barracks_mechanical_v2.blend'))
    export(root,os.path.join(OUT,'barracks_mechanical_v2.glb'))
    # Reload the actual delivery, not an in-memory approximation of it.
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    if REALISTIC and bpy.data.node_groups.get('glTF Material Output'):
        bpy.data.node_groups.remove(bpy.data.node_groups['glTF Material Output'], do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT,'barracks_mechanical_v2.glb'))
    root=bpy.data.objects['BarracksMechanicalV2']
    assert len([o for o in root.children_recursive if o.type=='MESH'])==report['meshes']
    assert bpy.data.objects.get('MainFan') is None
    flag = bpy.data.objects['BarracksFlag']
    assert flag.data.shape_keys.animation_data.action is not None
    samples = []
    for frame in [1, 13, 25, 49]:
        bpy.context.scene.frame_set(frame)
        evaluated = flag.evaluated_get(bpy.context.evaluated_depsgraph_get())
        mesh = evaluated.to_mesh()
        samples.append([v.co.copy() for v in mesh.vertices])
        evaluated.to_mesh_clear()
    movement = max((a-b).length for a,b in zip(samples[0], samples[2]))
    seam = max((a-b).length for a,b in zip(samples[0], samples[3]))
    pinned = [i for i,v in enumerate(samples[0]) if abs(v.x-(.32+.055)) < .0001]
    assert pinned, 'No pinned flag vertices after GLB import'
    assert max((sample[i]-samples[0][i]).length for sample in samples for i in pinned) < .0001
    assert movement > .2 and seam < .0001, (movement, seam)
    report['flag_animation'] = {'clip': 'Flag_Wind_Loop', 'seconds': 2,
                              'max_displacement': movement, 'loop_seam': seam,
                              'pinned_vertices': len(pinned)}
    bpy.context.scene.frame_set(1)
    for state,height,leg,ramp,door,engine in [('Landed',0,0,-.56,1,0),('LiftOff',1.1,.40,1.1,0,.8),('Airborne',3,.9,math.pi/2,0,1),('Deploy',.10,0,.15,0,.35)]:
        pose(root,height,leg,ramp,door,engine)
        assert all(math.isfinite(v) for o in root.children_recursive for row in o.matrix_world for v in row)
    pose(root,0,0,-.56,1,0)
    with open(os.path.join(OUT,'validation.json'),'w',encoding='utf-8') as file:
        json.dump(report,file,indent=2)
    print('BARRACKS_V2_BUILD PASS',json.dumps(report))


if __name__=='__main__':
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
