import sys as _sys
from pathlib import Path as _Path
_blender_tools = _Path(__file__).resolve().parents[1]
_sys.path[:0] = [str(_Path(__file__).resolve().parent), str(_blender_tools), str(_blender_tools / "shared")]
from project_paths import model_path
"""Deterministic crystal cluster, portable PBR textures and isolated editable source.

Run through tools/codex/run-blender.ps1; never touches the interactive Blender file.
"""
import bpy
import math
import random
import json
import shutil
import numpy as np
from pathlib import Path
from mathutils import Vector, Euler

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'assets/models'
REVIEW = ROOT / 'assets/concept_art/crystal_ore'
REVIEW.mkdir(parents=True, exist_ok=True)
(REVIEW / '.gdignore').touch()
rng = random.Random(7419)


def image(name, rgb, data=False):
    h, w = rgb.shape[:2]
    pixels = np.ones((h, w, 4), dtype=np.float32)
    pixels[:, :, :3] = rgb
    im = bpy.data.images.new(name, width=w, height=h, alpha=False)
    if data:
        im.colorspace_settings.name = 'Non-Color'
    im.pixels.foreach_set(pixels.ravel())
    im.filepath_raw = str(model_path(name + '.png'))
    im.file_format = 'PNG'
    im.save()
    im.pack()
    return im


def noise(x, y, scale, seed):
    gen = np.random.default_rng(seed)
    grid = gen.random((scale + 2, scale + 2)).astype(np.float32)
    xx, yy = x * scale, y * scale
    ix, iy = xx.astype(int), yy.astype(int)
    fx, fy = xx - ix, yy - iy
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    return (grid[iy, ix] * (1-fx) + grid[iy, ix+1] * fx) * (1-fy) + (grid[iy+1, ix] * (1-fx) + grid[iy+1, ix+1] * fx) * fy


def textures():
    n = 2048
    y, x = np.mgrid[0:n, 0:n].astype(np.float32) / n
    cloud = noise(x, y, 9, 12) * .60 + noise(x, y, 35, 18) * .28 + noise(x, y, 110, 13) * .12
    # Warped Voronoi boundaries form connected mineral fractures, with uneven widths.
    xx = x + (noise(x, y, 13, 5)-.5)*.025
    yy = y + (noise(x, y, 17, 8)-.5)*.025
    first = np.full_like(x, 1e5)
    second = first.copy()
    gen = np.random.default_rng(874)
    for px, py in gen.uniform(-.15, 1.15, (120, 2)):
        d = (xx-px)**2 + (yy-py)**2
        second = np.minimum(second, np.maximum(first, d))
        first = np.minimum(first, d)
    boundary = np.sqrt(second) - np.sqrt(first)
    vein = np.exp(-boundary / (.0008 + cloud*.0012))
    halo = np.exp(-boundary / .008) * .20
    fine = np.exp(-np.abs(np.sin((x*1.8+y+cloud*.11)*320)) * 45) * .12
    fracture = np.clip(vein*(.35+.65*cloud) + halo + fine, 0, 1)
    tint = np.stack((.018+cloud*.045, .09+cloud*.23, .25+cloud*.42), -1)
    tint += fracture[:, :, None] * np.array([.48, .73, .72], np.float32)
    crystal = image('ore_crystal_basecolor', np.clip(tint, 0, 1))
    detail = image('ore_crystal_detail', np.stack((fracture, cloud, np.clip(boundary*15,0,1)), -1), True)
    n = 1024
    y, x = np.mgrid[0:n, 0:n].astype(np.float32) / n
    coarse = noise(x,y,8,31)
    grain = noise(x,y,80,44)*.5 + noise(x,y,250,46)*.5
    strata = np.sin((y + noise(x,y,12,38)*.12)*210)*.5+.5
    h = coarse*.5 + grain*.17 + strata*.045
    stone = np.stack((.10+h*.22, .115+h*.23, .14+h*.245), -1)
    rock = image('ore_rock_basecolor', stone)
    gy,gx = np.gradient(h)
    normal = np.stack((-gx*13, -gy*13, np.ones_like(h)), -1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    normal = image('ore_rock_normal', normal*.5+.5, True)
    return crystal, detail, rock, normal


def material(name, color, roughness, normal=None, emission=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    p = nodes.get('Principled BSDF')
    p.inputs['Roughness'].default_value = roughness
    tex = nodes.new('ShaderNodeTexImage')
    tex.image = color
    links.new(tex.outputs['Color'], p.inputs['Base Color'])
    if normal:
        t = nodes.new('ShaderNodeTexImage')
        t.image = normal
        nm = nodes.new('ShaderNodeNormalMap')
        nm.inputs['Strength'].default_value = .45
        links.new(t.outputs['Color'], nm.inputs['Color'])
        links.new(nm.outputs['Normal'], p.inputs['Normal'])
    if emission:
        t = nodes.new('ShaderNodeTexImage')
        t.image = emission
        sep = nodes.new('ShaderNodeSeparateColor')
        links.new(t.outputs['Color'], sep.inputs['Color'])
        p.inputs['Emission Color'].default_value = (.012,.55,1,1)
        links.new(sep.outputs['Red'], p.inputs['Emission Strength'])
        p.inputs['Coat Weight'].default_value = .42
        p.inputs['Coat Roughness'].default_value = .12
    return mat


class Geometry:
    def __init__(self):
        self.vertices, self.faces, self.colors = [], [], []

    def add(self, verts, faces, color=(1,1,1,1)):
        offset = len(self.vertices)
        self.vertices.extend(verts)
        self.faces.extend([tuple(offset+i for i in f) for f in faces])
        self.colors.extend([color] * len(faces))

    def mesh(self, name, mat, parent):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.update()
        ob = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(ob)
        ob.parent = parent
        mesh.materials.append(mat)
        uv = mesh.uv_layers.new(name='UVMap')
        face_uv = mesh.uv_layers.new(name='FacetUV')
        vc = mesh.color_attributes.new(name='FacetTint', type='FLOAT_COLOR', domain='CORNER')
        # Each polygon samples a different patch; stable, flat normals retain crystal facets.
        for poly, col in zip(mesh.polygons, self.colors):
            u,v = rng.uniform(.02,.5),rng.uniform(.02,.5)
            coords = [(0,0),(1,0),(1,1),(0,1)] if len(poly.vertices)==4 else [(0,0),(1,0),(.5,1)]
            if len(poly.vertices)>4:
                coords = [(.5+.48*math.cos(i*math.tau/len(poly.vertices)), .5+.48*math.sin(i*math.tau/len(poly.vertices))) for i in range(len(poly.vertices))]
            for li, xy in zip(poly.loop_indices, coords):
                uv.data[li].uv = (u+xy[0]*.45, v+xy[1]*.45)
                face_uv.data[li].uv = xy
                vc.data[li].color = col
        return ob


def crystal(geo, pos, radius, height, tilt, phase):
    sides=6
    rot = Euler(tilt).to_matrix()
    ring = [(math.cos(phase+i*math.tau/sides)*radius*rng.uniform(.87,1.12), math.sin(phase+i*math.tau/sides)*radius*rng.uniform(.87,1.12)) for i in range(sides)]
    verts=[]
    for z, scale in [(0,.78),(height*.70,1),(height*.87,.72)]:
        for i,(x,y) in enumerate(ring):
            zz=z if z==0 else z+height*.04*math.sin(i*1.8+phase)
            verts.append(Vector(pos)+rot@Vector((x*scale,y*scale,zz)))
    verts.append(Vector(pos)+rot@Vector((radius*.24,-radius*.20,height)))
    faces=[tuple(reversed(range(sides)))]
    for k in range(2):
        for i in range(sides):
            j=(i+1)%sides
            faces.append((k*sides+i,k*sides+j,(k+1)*sides+j,(k+1)*sides+i))
    for i in range(sides):
        faces.append((12+i,12+(i+1)%sides,18))
    tint=rng.uniform(.62,1.0)
    geo.add(verts,faces,(tint,tint,tint,1))


def rock(geo, pos, sx, sy, sz):
    count=8
    verts=[]
    phase=rng.random()*math.tau
    outline=[(-.7,-1),(.64,-1),(1,-.55),(1,.65),(.58,1),(-.65,1),(-1,.53),(-1,-.62)]
    ca,sa=math.cos(phase),math.sin(phase)
    for level, factor in [(0,.82),(.40,1),(1,.68)]:
        for x,y in outline:
            r=rng.uniform(.8,1.15)*factor
            verts.append((pos[0]+(x*ca-y*sa)*sx*r,pos[1]+(x*sa+y*ca)*sy*r,pos[2]+sz*(level+rng.uniform(-.10,.10))))
    faces=[tuple(reversed(range(count))),tuple(range(count*2,count*3))]
    for k in range(2):
        for i in range(count):
            j=(i+1)%count
            faces.append((k*count+i,k*count+j,(k+1)*count+j,(k+1)*count+i))
    geo.add(verts,faces)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    base,detail,stone,normal=textures()
    cm=material('Ore_Crystal',base,.21,emission=detail)
    rm=material('Ore_Basalt',stone,.83,normal=normal)
    root=bpy.data.objects.new('ore',None)
    bpy.context.collection.objects.link(root)
    crystals,rocks=Geometry(),Geometry()
    # Composition authored for the game's southeast view; readable from all sides.
    specs=[((-.07,.12,.15),.235,1.61,(.05,-.09,0)),
           ((-.37,.03,.12),.115,1.04,(-.06,-.19,-.13)),
           ((.35,.08,.13),.138,1.14,(.02,.26,.16)),
           ((.06,-.29,.14),.115,.92,(.13,.04,.4)),
           ((-.25,-.30,.13),.135,.73,(.18,-.22,.2)),
           ((.28,-.24,.13),.095,.60,(.14,.25,.7)),
           ((.12,.39,.13),.105,.86,(-.22,.1,.4)),
           ((-.31,.34,.12),.085,.68,(-.2,-.1,.3))]
    for pos,r,h,tilt in specs:
        crystal(crystals,pos,r,h,tilt,rng.random()*math.tau)
    for i in range(26):
        a=rng.random()*math.tau
        r=rng.uniform(.34,.67)
        crystal(crystals,(math.cos(a)*r,math.sin(a)*r,.06),rng.uniform(.025,.065),rng.uniform(.12,.43),(math.sin(a)*-.22,math.cos(a)*.22,rng.random()),rng.random()*math.tau)
    rock(rocks,(0,0,-.025),.55,.51,.22)
    for i in range(25):
        a=i*2.39996
        r=rng.uniform(.28,.63)
        rock(rocks,(math.cos(a)*r,math.sin(a)*r,-.018),rng.uniform(.08,.19),rng.uniform(.07,.17),rng.uniform(.08,.22))
    for i in range(58):
        a=rng.random()*math.tau
        r=rng.uniform(.55,.77)
        size=rng.uniform(.012,.045)
        rock(rocks,(math.cos(a)*r,math.sin(a)*r,-.006),size,size*.8,size*.7)
    obs=[crystals.mesh('CrystalCluster',cm,root),rocks.mesh('FracturedRockBed',rm,root)]
    # Keep all geometry inside the existing interaction radius (38 / scale 45).
    for ob in obs:
        for v in ob.data.vertices:
            radial=math.hypot(v.co.x,v.co.y)
            if radial>.81:
                v.co.x*=.81/radial
                v.co.y*=.81/radial
    for ob in obs:
        ob.select_set(True)
    root.select_set(True)
    bpy.context.view_layer.objects.active=obs[0]
    if (model_path('ore.glb')).exists() and not (REVIEW/'ore-before.glb').exists():
        shutil.copy2(model_path('ore.glb'),REVIEW/'ore-before.glb')
    bpy.ops.export_scene.gltf(filepath=str(model_path('ore.glb')),export_format='GLB',use_selection=True,export_yup=True,export_animations=False,export_extras=True,export_vertex_color='ACTIVE')
    # Source contains only this asset, never overwrites a user's interactive file.
    bpy.ops.wm.save_as_mainfile(filepath=str(model_path('source/crystal_ore.blend')))
    points=[v.co for ob in obs for v in ob.data.vertices]
    report={'triangles':sum(len(p.vertices)-2 for ob in obs for p in ob.data.polygons),'meshes':len(obs),'crystals':len(specs)+26,'rocks':84,'radius':max(math.hypot(v.x,v.y) for v in points),'height':max(v.z for v in points),'seed':7419,'crystal_texture':2048,'rock_texture':1024,'runtime_material':'res://assets/art/environment/ore/crystal_ore.gdshader','source':'independent editable geometry; portable base PBR; engine layers supplied separately'}
    (model_path('source/crystal_ore_report.json')).write_text(json.dumps(report,indent=2),encoding='utf-8')
    assert report['radius']*45 < 38
    assert report['triangles']<10000
    print('CRYSTAL_ORE_BUILD PASS',json.dumps(report))


if __name__=='__main__':
    main()
