"""Build the only barracks asset; validate a staged GLB before replacing the old tree."""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
sys.dont_write_bytecode = True
from create_bunker import material, empty, cube, cylinder, cone, torus, ensure_source_blend, SOURCE_BLEND, PROJECT_ROOT


def merge(node):
    meshes = [o for o in node.children if o.type == 'MESH']
    if not meshes:
        return
    bpy.ops.object.select_all(action='DESELECT')
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    meshes[0].name = node.name + 'Mesh'


def signature(root):
    return [(o.name, o.type, tuple(o.location), tuple(o.scale),
             len(o.data.vertices) if o.type == 'MESH' else 0)
            for o in [root, *root.children_recursive]]


def build():
    armor = material('MobileBarracks_Armor', (.66, .69, .69), .35, .48)
    edge = material('MobileBarracks_Edge', (.40, .44, .46), .65, .38)
    dark = material('MobileBarracks_Chassis', (.055, .072, .085), .7, .46)
    black = material('MobileBarracks_Recess', (.018, .026, .034), .3, .64)
    blue = material('MobileBarracks_FactionPaint', (.085, .30, .55), .35, .40)
    glow = material('MobileBarracks_FactionGlow', (.04, .34, .8), .2, .3,
                    emission=(.02, .30, 1), emission_strength=2)
    warm = material('MobileBarracks_EntryLamp', (.9, .73, .38), .2, .3,
                    emission=(1, .65, .22), emission_strength=2)
    caution = material('MobileBarracks_Caution', (.68, .40, .07), .2, .55)
    engine = material('MobileBarracks_Engine', (.04, .55, .9), .1, .3,
                      emission=(.025, .5, 1), emission_strength=5)
    root = empty('MobileBarracksCandidate')
    root['asset_role'] = 'mobile_frontline_barracks'
    root['authoring_axes'] = 'Z up, +Y front; GLB Y up, -Z front'
    root['reference'] = 'barracks concept direction 01, modular frontline'
    static = empty('BarracksHull', node=root)
    cube('Keel', (6.85, 5.5, .38), (0, -.3, .60), dark, static, .14)
    for x in [-2.6, 0, 2.6]:
        cube('UnderbodyRail', (.28, 5.45, .24), (x, -.3, .36), edge, static, .04)
    # Hollow primary module: the entrance is an actual opening, not a painted rectangle.
    cube('Floor', (3.95, 4.85, .18), (-1.25, -.35, .82), edge, static, .04)
    for x in [-3.20, .70]:
        cube('MainSide', (.20, 4.85, 3.5), (x, -.35, 2.57), armor, static, .10)
    cube('MainRear', (3.85, .20, 3.5), (-1.25, -2.70, 2.57), armor, static, .09)
    cube('InteriorRear', (3.5, .035, 2.9), (-1.25, -2.57, 2.36), dark, static, .01)
    cube('RoofGasket', (4.10, 5.02, .20), (-1.25, -.35, 4.27), dark, static, .10)
    cube('MainRoof', (4.12, 5.05, .32), (-1.25, -.35, 4.46), armor, static, .15)
    for x in [-2.87, .37]:
        cube('FrontPier', (.68, .38, 3.60), (x, 2.04, 2.56), armor, static, .13)
        cube('PierGuard', (.30, .08, 2.0), (x, 2.265, 2.0), edge, static, .045)
    cube('DoorHeader', (3.42, .48, .52), (-1.25, 2.08, 4.02), armor, static, .12)
    for x in [-2.42, -.08]:
        cube('DoorTrack', (.17, .30, 3.12), (x, 2.02, 2.40), dark, static, .03)
        cube('EntryLight', (.055, .05, 1.12), (x, 2.20, 2.80), warm, static, .015)
    cube('EntryAwning', (3.6, .70, .16), (-1.25, 2.23, 4.04), edge, static, .06)
    cube('EntryStripe', (1.65, .04, .10), (-1.25, 2.60, 4.055), blue, static, .015)
    # The low equipment wing is offset, preserving direction 01's asymmetry.
    cube('EquipmentGasket', (2.68, 4.60, 2.8), (2.04, -.45, 2.16), dark, static, .12)
    cube('EquipmentArmor', (2.62, 4.54, 2.68), (2.04, -.45, 2.20), armor, static, .20)
    cube('EquipmentRoof', (2.79, 4.7, .25), (2.04, -.45, 3.62), armor, static, .12)
    cube('JoiningRib', (.26, 4.4, .25), (.71, -.4, 3.70), edge, static, .04)
    cube('ServiceDoorRecess', (1.17, .08, 2.28), (2.03, 1.86, 1.97), dark, static, .055)
    cube('ServiceDoor', (.92, .07, 2.04), (2.03, 1.915, 1.97), edge, static, .055)
    cube('ServiceDoorInset', (.61, .035, 1.29), (2.03, 1.96, 2.1), dark, static, .025)
    cube('ServiceStatus', (.08, .045, .25), (2.62, 1.94, 2.18), glow, static, .01)
    # Broad panel divisions, ribs and vent slats survive strategic zoom.
    for x, z in [(-1.25, 4.64), (2.04, 3.77)]:
        for y in [-1.8, -.1, 1.2]:
            cube('RoofPanel', (2.28 if x > 0 else 3.35, .83, .045), (x, y, z), edge, static, .06)
        cube('RoofFactionBand', (.35, 4.32, .045), (x + .64, -.38, z + .028), blue, static, .015)
    for side in [-1, 1]:
        x = -3.315 if side < 0 else 3.37
        for y in [-1.7, .2]:
            cube('SideVentRecess', (.035, 1.36, .58), (x, y, 2.65), black, static, .01)
            for index in range(5):
                cube('VentSlat', (.055, 1.23, .045), (x + side * .023, y, 2.43 + index * .105), edge, static, .006)
        for y in [-2.55, -.85, 1.0]:
            cube('ModuleRib', (.17, .14, 2.45), (x, y, 2.07), edge, static, .025)
        cube('SideFactionPanel', (.04, .82, .35), (x + side * .1, .80, 3.0), blue, static, .02)
    for x in [-2.5, -1.25, 0, 1.65, 2.6]:
        cube('RearVent', (.63, .045, .65), (x, -2.82, 2.1), dark, static, .04)
        for i in range(4):
            cube('RearLouver', (.56, .05, .045), (x, -2.85, 1.87 + i * .14), edge, static, .008)
    # Permanently attached external gear and antenna mast.
    cube('UtilityCase', (.70, .36, .85), (2.4, -2.92, 1.25), edge, static, .075)
    for x in [-.2, .13]:
        cylinder('RearPipe', .07, 1.8, (x, -2.91, 2.48), edge, 12, static)
    for x, y, h in [(-2.8, -2.0, .82), (-2.45, -2.15, .55)]:
        cube('AntennaBase', (.30, .30, .24), (x, y, 4.75), dark, static, .035)
        cylinder('Antenna', .025, h, (x, y, 4.88 + h / 2), edge, 8, static)
    # Roof fan assembly, grouped with its own rotation pivot.
    for name, x, y, z, radius in [('BarracksFanFront', 1.82, -.52, 3.97, .69), ('BarracksFanRear', -1.85, -1.05, 4.84, .56)]:
        cylinder('FanWell', radius + .13, .16, (x, y, z - .06), black, 32, static)
        torus('FanRim', radius, .075, (x, y, z + .035), edge, static)
        fan = empty(name, (x, y, z), root)
        cylinder('FanHub', .16, .12, (0, 0, .04), edge, 20, fan)
        for i in range(8):
            a = i * math.tau / 8
            cube('FanBlade', (.13, radius * .72, .05),
                 (math.sin(a) * radius * .52, math.cos(a) * radius * .52, 0), edge, fan, .015,
                 rotation=(0, 0, -a + .35))
        merge(fan)
    # Recessed downward engines, separate from landing struts.
    exhaust = empty('ThrusterGlow', node=root)
    for side in [-1, 1]:
        # Small horizontal ports provide visible attitude-control hardware.
        cube('AttitudePod', (.45, .64, .43), (side * 3.48, -.42, 1.12), edge, static, .09)
        for y in [-.57, -.27]:
            cylinder('AttitudeNozzle', .11, .16, (side * 3.73, y, 1.12), dark, 16, static,
                     rotation=(0, math.pi / 2, 0))
        for y in [-1.6, .85]:
            x = side * 3.37
            cube('EngineMount', (.75, 1.08, .76), (x, y, 1.14), armor, static, .18)
            cone('EngineBell', .43, .31, .50, (x, y, .58), dark, 24, static)
            torus('NozzleRim', .36, .048, (x, y, .32), edge, static)
            cylinder('NozzleCore', .255, .035, (x, y, .37), black, 24, static)
            for j in [-1, 0, 1]:
                cube('CoolingSlot', (.04, .64, .045), (x + side * .389, y, 1.02 + j * .14), dark, static, .008)
            cone('Exhaust', .045, .29, .9, (x, y, -.10), engine, 20, exhaust)
        for end, y in [('Front', 1.9), ('Rear', -2.65)]:
            x = side * 3.35
            cube('LegSocket', (.65, .62, .52), (x, y, .93), dark, static, .075)
            leg = empty('LandingLeg%s%s' % ('L' if side < 0 else 'R', end), (x, y, 0), root)
            cylinder('HydraulicPiston', .105, .7, (0, 0, .49), edge, 16, leg)
            cube('LegArmor', (.22, .23, .39), (0, -.06, .41), armor, leg, .05)
            cube('LandingFoot', (.65, .61, .12), (0, 0, .06), dark, leg, .04)
            cube('FootStripe', (.31, .06, .016), (0, .20, .125), caution, leg, .005)
            merge(leg)
    merge(exhaust)
    exhaust.scale = (.001, .001, .001)
    # Split sliding leaves retract into the front armor; pivots retain authored offsets.
    for side, name in [(-1, 'BarracksDoorL'), (1, 'BarracksDoorR')]:
        door = empty(name, (-1.25, 2.05, .88), root)
        cube('Shutter', (1.065, .12, 2.91), (side * .535, 0, 1.455), dark, door, .035)
        for i in range(6):
            cube('ShutterArmor', (.99, .08, .41), (side * .535, .08, .25 + i * .47), edge, door, .035)
        cube('DoorFactionStripe', (.14, .018, 2.62), (side * .70, .131, 1.46), blue, door, .008)
        merge(door)
    ramp = empty('DeploymentRamp', (-1.25, 2.20, .81), root)
    length = 1.69
    cube('RampDeck', (2.22, length, .10), (0, length / 2, 0), edge, ramp, .025)
    for x in [-1.02, 1.02]:
        cube('RampRail', (.11, length, .085), (x, length / 2, .075), caution, ramp, .015)
    for i in range(8):
        cube('Grip', (1.85, .045, .022), (0, .10 + i * .205, .062), dark, ramp, .005)
    merge(ramp)
    ramp.rotation_euler.x = -.48
    lamp = empty('BarracksStatusLight', (-1.25, 2.34, 3.91), root)
    cube('StatusLamp', (.48, .06, .055), (0, 0, 0), glow, lamp, .01)
    merge(lamp)
    merge(static)
    bpy.context.view_layer.update()
    return root


def export(root, path):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [root, *root.children_recursive]:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True,
                             export_apply=True, export_animations=False, export_materials='EXPORT')


def main():
    ensure_source_blend()
    others = {o.name: signature(o) for o in bpy.context.scene.objects if o.parent is None and o.name != 'barracks'}
    old = bpy.data.objects.get('barracks')
    obsolete_meshes = {o.data for o in old.children_recursive if o.type == 'MESH'} if old else set()
    obsolete_materials = {m for mesh in obsolete_meshes for m in mesh.materials if m}
    # Free the contract names for a repeat build, but keep old geometry until validation succeeds.
    if old:
        for obj in old.children_recursive:
            obj.name = 'PreviousBarracks_' + obj.name
    root = build()
    meshes = [o for o in root.children_recursive if o.type == 'MESH']
    points = [o.matrix_world @ Vector(p) for o in meshes if o.parent.name != 'ThrusterGlow' for p in o.bound_box]
    extent = [max(p[i] for p in points) - min(p[i] for p in points) for i in range(3)]
    tris = sum(len(p.vertices) - 2 for o in meshes for p in o.data.polygons)
    assert extent[0] <= 8.0 and extent[1] <= 8.0, extent
    assert tris < 40000, tris
    assert all(len(o.data.polygons) > 0 for o in meshes)
    staged = os.path.join(PROJECT_ROOT, '.godot', 'mobile-barracks-staged.glb')
    export(root, staged)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=staged)
    imported = set(bpy.data.objects) - before
    assert sum(o.type == 'MESH' for o in imported) == len(meshes), 'GLB mesh loss'
    imported_meshes = {o.data for o in imported if o.type == 'MESH'}
    imported_materials = {m for mesh in imported_meshes for m in mesh.materials if m}
    for obj in imported:
        bpy.data.objects.remove(obj, do_unlink=True)
    old = bpy.data.objects.get('barracks')
    if old:
        for obj in [*reversed(list(old.children_recursive)), old]:
            bpy.data.objects.remove(obj, do_unlink=True)
    root.name = 'barracks'
    for name, sig in others.items():
        assert signature(bpy.data.objects[name]) == sig, 'Unrelated model modified: ' + name
    # Remove only orphaned mesh/material datablocks left by the replaced tree and reimport.
    for data in obsolete_meshes | imported_meshes:
        if data.users == 0:
            bpy.data.meshes.remove(data)
    for data in obsolete_materials | imported_materials:
        if data.users == 0:
            bpy.data.materials.remove(data)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=SOURCE_BLEND)
    export(root, os.path.join(PROJECT_ROOT, 'assets', 'models', 'barracks.glb'))
    print('MOBILE_BARRACKS_BUILD PASS', {'extent': extent, 'triangles': tris, 'meshes': len(meshes), 'other_roots_unchanged': len(others)})


if __name__ == '__main__':
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
