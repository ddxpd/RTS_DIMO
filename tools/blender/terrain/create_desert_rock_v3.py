import sys as _sys
from pathlib import Path as _Path
_blender_tools = _Path(__file__).resolve().parents[1]
_sys.path[:0] = [str(_Path(__file__).resolve().parent), str(_blender_tools), str(_blender_tools / "shared")]
"""Isolated desert quality study. Run phases through the existing Blender MCP.

Original scene is preserved. Source is written with libraries.write, never
save_as_mainfile. All generated art stays outside production assets.
"""
import bpy
import json
import math
import random
import struct
from pathlib import Path
from mathutils import Vector, noise
import numpy as np

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'assets/concept_art/desert_terrain_kit/v3'
SEED = 91026


def activate(obj):
    for selected in bpy.context.selected_objects:
        selected.select_set(False)
    obj.hide_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def join(objects, name):
    activate(objects[0])
    for obj in objects:
        obj.select_set(True)
    if len(objects) > 1:
        bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    return obj


def slab(scene, center, size, seed):
    """Angular sediment fragment: chipped octagonal contour, tilted fracture planes."""
    rng = random.Random(seed)
    w, d, h = size
    # Chamfers vary independently; straight areas remain rock fracture planes.
    cuts = [rng.uniform(.10, .27) for _ in range(4)]
    outline = [(-.5 + cuts[0], -.5), (.5 - cuts[1], -.5),
               (.5, -.5 + cuts[1]), (.5, .5 - cuts[2]),
               (.5 - cuts[2], .5), (-.5 + cuts[3], .5),
               (-.5, .5 - cuts[3]), (-.5, -.5 + cuts[0])]
    tilt_x, tilt_y = rng.uniform(-.05, .05), rng.uniform(-.055, .055)
    vertices = []
    for row, t in enumerate([0, .25, .77, 1]):
        taper = [.84, 1, .97, .83][row]
        shift = rng.uniform(-.09, .09)
        for i, (x, y) in enumerate(outline):
            jitter = rng.uniform(-.035, .035)
            vertices.append((center[0] + (x * taper + shift + jitter) * w,
                             center[1] + (y * taper + jitter) * d,
                             center[2] + (t - .5) * h + tilt_x * x * w + tilt_y * y * d))
    faces = [tuple(reversed(range(8))), tuple(range(24, 32))]
    for row in range(3):
        for i in range(8):
            a = row * 8 + i
            b = row * 8 + (i + 1) % 8
            faces.append((a, b, b + 8, a + 8))
    mesh = bpy.data.meshes.new('V3_FractureMesh')
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new('V3_Fragment', mesh)
    scene.collection.objects.link(obj)
    activate(obj)
    bevel = obj.modifiers.new('ChippedEdge', 'BEVEL')
    bevel.width = min(h * .06, .045)
    bevel.segments = 1
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    weighted = obj.modifiers.new('FractureNormals', 'WEIGHTED_NORMAL')
    weighted.keep_sharp = True
    weighted.weight = 35
    bpy.ops.object.modifier_apply(modifier=weighted.name)
    return obj


def strata(scene, name, origin, size, layers, seed):
    rng = random.Random(seed)
    width, depth, height = size
    parts = []
    count = 3 if width > 5 else 1
    divisions = [1.05, .79, 1.16] if count == 3 else [1.0]
    cursor = origin[0] - width / 2
    for column, weight in enumerate(divisions):
        w = width * weight / sum(divisions)
        center = (cursor + w / 2, origin[1], origin[2])
        # Each massif is continuous. Narrow strata notches replace detached slabs.
        parts.append(layered_mass(scene, center, (w + .06, depth, height), layers,
                                  seed + column * 37))
        cursor += w
    return join(parts, name)


def layered_mass(scene, center, size, layers, seed):
    rng = random.Random(seed)
    w, d, h = size
    outline = [(-.50,-.26),(-.38,-.50),(-.06,-.49),(.33,-.47),
               (.50,-.26),(.46,.04),(.49,.30),(.28,.49),
               (-.06,.45),(-.35,.48),(-.48,.27),(-.47,.01)]
    outline = [(x + rng.uniform(-.05,.05), y + rng.uniform(-.045,.045)) for x,y in outline]
    detailed_outline = []
    for i, (x,y) in enumerate(outline):
        nx,ny = outline[(i+1) % len(outline)]
        detailed_outline += [(x,y), ((x+nx)/2 + rng.uniform(-.025,.025), (y+ny)/2 + rng.uniform(-.03,.03))]
    outline = detailed_outline
    levels = [(0, .90)]
    for row in range(layers):
        t = row / layers
        levels += [(t + .09/layers, .99), (t + .62/layers, 1.0),
                   (t + .90/layers, .99), (t + .98/layers, .965)]
    levels.append((1, .88))
    vertices = []
    lean_x, lean_y = rng.uniform(-.10,.10), rng.uniform(-.06,.06)
    for row,(t,radius) in enumerate(levels):
        # Unequal strata and broken top planes; points at fracture boundaries
        # move coherently rather than adding uniform random bumps everywhere.
        outline_taper = 1 - .07*t + .055*math.sin(t*8 + seed)
        for i,(x,y) in enumerate(outline):
            n = noise.noise(Vector((x*3 + seed, y*3, t*5)))
            notch = max(0, math.sin(i*2.1 + seed + t*12))**10 * .065
            xx = center[0] + w*(x*radius*outline_taper + lean_x*t + n*.08 - notch)
            yy = center[1] + d*(y*radius*outline_taper + lean_y*t + n*.09)
            zz = center[2] + h*t + (x*.12 + y*.07 + n*.07)*h*math.sin(t*math.pi*.8)
            vertices.append((xx,yy,zz))
    sides = len(outline)
    faces = [tuple(reversed(range(sides)))]
    # Triangulated uneven top, with a raised offset central fracture point.
    top = len(vertices)
    vertices.append((center[0] + w*.08, center[1] - d*.04, center[2] + h*1.035))
    for i in range(sides):
        faces.append(((len(levels)-1)*sides+i, (len(levels)-1)*sides+(i+1)%sides, top))
    for row in range(len(levels)-1):
        for i in range(sides):
            a = row*sides+i; b = row*sides+(i+1)%sides
            faces.append((a,b,b+sides,a+sides))
    mesh = bpy.data.meshes.new('V3_ContinuousFracture')
    mesh.from_pydata(vertices,[],faces); mesh.update()
    obj = bpy.data.objects.new('V3_ContinuousMass',mesh)
    scene.collection.objects.link(obj)
    # Sharp polygonal fracture faces; the source bake contributes surface detail.
    for poly in mesh.polygons:
        poly.use_smooth = False
    return obj


def shader_source():
    mat = bpy.data.materials.new('V3_Editable_Sandstone_Source')
    mat.use_nodes = True
    n, l = mat.node_tree.nodes, mat.node_tree.links
    n.clear()
    output = n.new('ShaderNodeOutputMaterial')
    bsdf = n.new('ShaderNodeBsdfPrincipled')
    bsdf.inputs['Roughness'].default_value = .86
    l.new(bsdf.outputs['BSDF'], output.inputs['Surface'])
    geo = n.new('ShaderNodeNewGeometry')
    stretch = n.new('ShaderNodeVectorMath'); stretch.operation = 'MULTIPLY'
    stretch.inputs[1].default_value = (1.1, 1.1, 15)
    l.new(geo.outputs['Position'], stretch.inputs[0])
    bedding = n.new('ShaderNodeTexNoise')
    bedding.inputs['Scale'].default_value = 2.2
    bedding.inputs['Detail'].default_value = 4
    bedding.inputs['Roughness'].default_value = .72
    l.new(stretch.outputs['Vector'], bedding.inputs['Vector'])
    palette = n.new('ShaderNodeValToRGB')
    ramp = palette.color_ramp
    ramp.elements.remove(ramp.elements[1])
    stops = [(.18, (.07,.046,.025,1)), (.34,(.15,.093,.046,1)),
             (.49,(.28,.175,.084,1)), (.62,(.40,.29,.165,1)),
             (.79,(.51,.40,.265,1))]
    ramp.elements[0].position, ramp.elements[0].color = stops[0]
    for pos, col in stops[1:]:
        ramp.elements.new(pos).color = col
    macro = n.new('ShaderNodeTexNoise')
    macro.inputs['Scale'].default_value = 3.8
    macro.inputs['Detail'].default_value = 5
    macro.inputs['Roughness'].default_value = .75
    l.new(geo.outputs['Position'], macro.inputs['Vector'])
    mixed = n.new('ShaderNodeMixRGB')
    mixed.inputs[0].default_value = .72
    l.new(bedding.outputs['Fac'], mixed.inputs[1])
    l.new(macro.outputs['Fac'], mixed.inputs[2])
    l.new(mixed.outputs[0], palette.inputs[0])
    grain = n.new('ShaderNodeTexNoise')
    grain.inputs['Scale'].default_value = 92
    grain.inputs['Detail'].default_value = 2
    l.new(geo.outputs['Position'], grain.inputs['Vector'])
    grain_color = n.new('ShaderNodeMixRGB'); grain_color.blend_type = 'MULTIPLY'
    grain_color.inputs[0].default_value = .16
    l.new(palette.outputs['Color'], grain_color.inputs[1])
    l.new(grain.outputs['Fac'], grain_color.inputs[2])
    l.new(grain_color.outputs[0], bsdf.inputs['Base Color'])
    bump = n.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = .38
    bump.inputs['Distance'].default_value = .032
    l.new(bedding.outputs['Fac'], bump.inputs['Height'])
    micro = n.new('ShaderNodeBump')
    micro.inputs['Strength'].default_value = .25
    micro.inputs['Distance'].default_value = .009
    l.new(grain.outputs['Fac'], micro.inputs['Height'])
    l.new(bump.outputs['Normal'], micro.inputs['Normal'])
    l.new(micro.outputs['Normal'], bsdf.inputs['Normal'])
    return mat


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    previous = bpy.context.window.scene
    scene = bpy.data.scenes.new('Desert_V3_Quality_Source')
    bpy.context.window.scene = scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 16
    scene.cycles.device = 'CPU'
    scene.render.bake.margin = 12
    scene.world = bpy.data.worlds.new('V3_NeutralWorld')
    scene.world.color = (.6, .6, .6)
    cliff = strata(scene, 'V3_Cliff', (0, 0, 0), (8, 2.9, 4), 6, SEED)
    rock = strata(scene, 'V3_Rock', (11, 0, 0), (3, 2.4, 2.5), 4, SEED + 100)
    rubble = []
    for i, size in enumerate([(1.1,.8,.55),(.7,.65,.55),(.55,.85,.25),(.32,.28,.24)]):
        rubble.append(slab(scene, (15 + i * 2, 0, size[2] / 2), size, SEED + 200 + i))
    for i, obj in enumerate(rubble):
        obj.name = 'V3_Rubble_%d' % i
    assets = [cliff, rock] + rubble
    for obj in assets:
        activate(obj)
        triangulate = obj.modifiers.new('StableBakeTriangles', 'TRIANGULATE')
        triangulate.keep_custom_normals = True
        bpy.ops.object.modifier_apply(modifier=triangulate.name)
    # A single packed atlas shared across all six assets, with non-overlapping UVs.
    activate(cliff)
    for obj in assets:
        obj.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(65), island_margin=.008)
    bpy.ops.object.mode_set(mode='OBJECT')
    high_parts = []
    for obj in assets:
        high = obj.copy(); high.data = obj.data.copy()
        scene.collection.objects.link(high)
        high.name = obj.name + '_High'
        activate(high)
        # Simple subdivision preserves rock fracture planes before erosion.
        subdiv = high.modifiers.new('EditableDetailSubdivision', 'SUBSURF')
        subdiv.subdivision_type = 'SIMPLE'
        subdiv.levels = 3
        bpy.ops.object.modifier_apply(modifier=subdiv.name)
        high.data.update()
        source_normals = [v.normal.copy() for v in high.data.vertices]
        for v, source_normal in zip(high.data.vertices, source_normals):
            p = v.co.copy()
            bed = noise.noise(Vector((p.x * 2.5, p.y * 2.5, p.z * 37)))
            pit = noise.noise(p * 28)
            macro = noise.noise(p * 5)
            v.co += source_normal * (bed * .018 + pit * .007 + macro * .012)
        high.data.update()
        for polygon in high.data.polygons:
            polygon.use_smooth = True
        high_parts.append(high)
    high = join(high_parts, 'V3_High_BakeSource')
    source_mat = shader_source()
    high.data.materials.clear(); high.data.materials.append(source_mat)
    copies = []
    for obj in assets:
        copy = obj.copy(); copy.data = obj.data.copy()
        scene.collection.objects.link(copy); copies.append(copy)
        obj.hide_render = True; obj.hide_set(True)
    target = join(copies, 'V3_Low_BakeTarget')
    material = bpy.data.materials.new('V3_BakeTarget'); material.use_nodes = True
    target.data.materials.clear(); target.data.materials.append(material)
    tex = material.node_tree.nodes.new('ShaderNodeTexImage')
    material.node_tree.nodes.active = tex
    images = {}
    for suffix in ['basecolor', 'normal', 'ao']:
        img = bpy.data.images.new('v3_rock_' + suffix, width=2048, height=2048, alpha=False)
        if suffix != 'basecolor':
            img.colorspace_settings.name = 'Non-Color'
        images[suffix] = img
    state = dict(scene=scene, previous=previous, assets=assets, high=high,
                 target=target, tex=tex, source_mat=source_mat, images=images)
    bpy.context.window.scene = previous
    return state


def save_image(image, suffix):
    image.filepath_raw = str(OUT / ('v3_rock_' + suffix + '.png'))
    image.file_format = 'PNG'
    image.save()
    image.pack()


def bake_stage(state, kind):
    previous = bpy.context.window.scene
    scene = state['scene']
    bpy.context.window.scene = scene
    try:
        target, high = state['target'], state['high']
        target.hide_render = False; high.hide_render = False
        activate(target); high.select_set(True)
        state['tex'].image = state['images'][kind]
        if kind == 'basecolor':
            source = state['source_mat']
            n, l = source.node_tree.nodes, source.node_tree.links
            bsdf = next(node for node in n if node.type == 'BSDF_PRINCIPLED')
            output = next(node for node in n if node.type == 'OUTPUT_MATERIAL')
            emission = n.new('ShaderNodeEmission')
            l.new(bsdf.inputs['Base Color'].links[0].from_socket, emission.inputs['Color'])
            l.new(emission.outputs[0], output.inputs['Surface'])
            bake_type = 'EMIT'
        else:
            bake_type = 'NORMAL' if kind == 'normal' else 'AO'
        bpy.ops.object.bake(type=bake_type, use_selected_to_active=True,
                            cage_extrusion=.085, max_ray_distance=.17, use_clear=True, margin=12)
        if kind == 'basecolor':
            l.new(bsdf.outputs[0], output.inputs['Surface'])
            n.remove(emission)
        save_image(state['images'][kind], kind)
        return {'baked': kind, 'resolution': 2048}
    finally:
        bpy.context.window.scene = previous


def finish(state):
    previous = bpy.context.window.scene
    scene = state['scene']
    bpy.context.window.scene = scene
    try:
        images = state['images']
        # Pack AO / authored varying roughness / dielectric metallic=0.
        pixels = np.empty(2048 * 2048 * 4, np.float32)
        images['ao'].pixels.foreach_get(pixels)
        ao = pixels.reshape(-1, 4)[:, 0].copy()
        images['basecolor'].pixels.foreach_get(pixels)
        light = pixels.reshape(-1,4)[:, :3].mean(axis=1)
        packed = np.ones((2048 * 2048,4), np.float32)
        packed[:,0] = np.clip(ao, .22, 1)
        packed[:,1] = np.clip(.92 - light * .17, .7, .94)
        packed[:,2] = 0
        orm = bpy.data.images.new('v3_rock_orm', width=2048, height=2048, alpha=False)
        orm.colorspace_settings.name = 'Non-Color'
        orm.pixels.foreach_set(packed.ravel()); save_image(orm, 'orm')
        images['orm'] = orm
        mat = bpy.data.materials.new('V3_Shared_Baked_Sandstone'); mat.use_nodes = True
        n, l = mat.node_tree.nodes, mat.node_tree.links
        bsdf = next(node for node in n if node.type == 'BSDF_PRINCIPLED')
        for kind in ['basecolor','normal','orm']:
            tex = n.new('ShaderNodeTexImage'); tex.image = images[kind]
            if kind == 'basecolor':
                l.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
            elif kind == 'normal':
                normal = n.new('ShaderNodeNormalMap')
                normal.inputs['Strength'].default_value = .38
                l.new(tex.outputs['Color'], normal.inputs['Color'])
                l.new(normal.outputs['Normal'], bsdf.inputs['Normal'])
            else:
                sep = n.new('ShaderNodeSeparateColor')
                l.new(tex.outputs['Color'], sep.inputs[0])
                l.new(sep.outputs['Green'], bsdf.inputs['Roughness'])
                l.new(sep.outputs['Blue'], bsdf.inputs['Metallic'])
                group = bpy.data.node_groups.get('glTF Material Output')
                if group is None:
                    group = bpy.data.node_groups.new('glTF Material Output', 'ShaderNodeTree')
                    group.interface.new_socket(name='Occlusion', in_out='INPUT', socket_type='NodeSocketFloat')
                node = n.new('ShaderNodeGroup'); node.node_tree = group
                l.new(sep.outputs['Red'], node.inputs['Occlusion'])
        state['high'].hide_render = True; state['high'].hide_set(True)
        state['target'].hide_render = True; state['target'].hide_set(True)
        report = {'seed': SEED, 'assets': [], 'bakes': ['selected-to-active normal','unlit basecolor','ambient occlusion'],
                  'high_faces': len(state['high'].data.polygons), 'texture_resolution': 2048,
                  'texture_rgb_mip_mib': 48, 'scope': 'quality sample only; no collision/navigation/production integration'}
        for i, obj in enumerate(state['assets']):
            obj.hide_render = False
            activate(obj)
            obj.data.materials.clear(); obj.data.materials.append(mat)
            # Recenter atlas layout offsets without altering the baked UVs.
            offset = 0 if i == 0 else (11 if i == 1 else 15 + (i - 2) * 2)
            if not obj.get('v3_recentered', False):
                for vertex in obj.data.vertices:
                    vertex.co.x -= offset
                obj['v3_recentered'] = True
            obj.location.x = 0
            obj.data.update()
            triangulate = obj.modifiers.new('ExportTriangles', 'TRIANGULATE')
            triangulate.keep_custom_normals = True
            bpy.ops.object.modifier_apply(modifier=triangulate.name)
            filename = ['v3-cliff','v3-rock','v3-rubble-a','v3-rubble-b','v3-rubble-c','v3-rubble-d'][i]
            bpy.ops.export_scene.gltf(filepath=str(OUT / (filename + '.glb')), export_format='GLB',
                                      use_selection=True, use_active_scene=True, export_yup=True, export_apply=True,
                                      export_materials='EXPORT', export_texcoords=True, export_normals=True,
                                      export_tangents=True, export_animations=False, export_cameras=False,
                                      export_lights=False)
            triangles = sum(len(poly.vertices) - 2 for poly in obj.data.polygons)
            report['assets'].append({'file': filename + '.glb', 'triangles': triangles,
                                     'vertices': len(obj.data.vertices), 'uv_layers': len(obj.data.uv_layers)})
            obj.location.x = offset
        # Include source high mesh, low assets, UV atlas and packed maps without
        # changing the user's currently open .blend path or other scenes.
        bpy.data.libraries.write(str(OUT / 'v3-rock-source.blend'), {scene}, fake_user=True, compress=True)
        (OUT / 'v3-build-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
        state['report'] = report
        return report
    finally:
        bpy.context.window.scene = previous


def audit_files():
    """Inspect exported bytes, not the pre-export scene; reject stray scene assets."""
    result = {'checks': 0, 'failures': [], 'files': []}
    def check(condition, message):
        result['checks'] += 1
        if not condition:
            result['failures'].append(message)
    for file in sorted(OUT.glob('*.glb')):
        data = file.read_bytes()
        magic, version, size = struct.unpack_from('<III', data)
        check(magic == 0x46546c67 and version == 2 and size == len(data), file.name + ' header')
        json_size = struct.unpack_from('<I', data, 12)[0]
        doc = json.loads(data[20:20 + json_size])
        blob_start = 28 + json_size
        check(not doc.get('skins') and not doc.get('animations'), file.name + ' stray rig/animation')
        check(all('uri' not in image for image in doc.get('images', [])), file.name + ' external image')
        check(all('uri' not in buffer for buffer in doc.get('buffers', [])), file.name + ' external buffer')
        is_combined = 'transition' in file.name
        check(len(doc.get('materials', [])) == (2 if is_combined else 1), file.name + ' material count')
        check(len(doc.get('meshes', [])) == (2 if is_combined else 1), file.name + ' unexpected mesh')
        triangles = 0
        vertices = 0
        for mesh in doc.get('meshes', []):
            for primitive in mesh['primitives']:
                attrs = primitive['attributes']
                check(all(k in attrs for k in ['POSITION','NORMAL','TEXCOORD_0','TANGENT']), file.name + ' required vertex attribute')
                pos = doc['accessors'][attrs['POSITION']]
                vertices += pos['count']
                view = doc['bufferViews'][pos['bufferView']]
                offset = blob_start + view.get('byteOffset', 0) + pos.get('byteOffset', 0)
                stride = view.get('byteStride', 12)
                check(all(math.isfinite(v) for i in range(pos['count']) for v in struct.unpack_from('<fff',data,offset+i*stride)), file.name + ' nonfinite position')
                triangles += doc['accessors'][primitive['indices']]['count'] // 3
        check(all('normalTexture' in mat for mat in doc['materials']), file.name + ' normal material hookup')
        if not is_combined:
            check(all('occlusionTexture' in mat and 'metallicRoughnessTexture' in mat['pbrMetallicRoughness'] for mat in doc['materials']), file.name + ' ORM hookup')
            check(triangles < 6000, file.name + ' mesh budget')
        result['files'].append({'file':file.name,'triangles':triangles,'vertices':vertices,'bytes':len(data),
                                'meshes':len(doc.get('meshes',[])), 'materials':len(doc['materials'])})
    (OUT / 'v3-export-audit.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    return result
