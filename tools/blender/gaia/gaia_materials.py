import sys as _sys
from pathlib import Path as _Path
_blender_tools = _Path(__file__).resolve().parents[1]
_sys.path[:0] = [str(_Path(__file__).resolve().parent), str(_blender_tools), str(_blender_tools / "shared")]
"""Portable trim atlases and a real selected-to-active armor normal/AO bake."""
import bpy
import numpy as np
import math
from pathlib import Path


def save_image(name, values, output, data=False):
    size = values.shape[0]
    rgba = np.ones((size, size, 4), np.float32)
    rgba[:, :, :3] = values
    im = bpy.data.images.new(name, width=size, height=size, alpha=False)
    if data:
        im.colorspace_settings.name = 'Non-Color'
    im.pixels.foreach_set(rgba.ravel())
    im.filepath_raw = str(output / (name + '.png'))
    im.file_format = 'PNG'
    im.save()
    im.pack()
    return im


def armor_maps(output):
    size = 4096
    gen = np.random.default_rng(71023)
    rgb = np.empty((size, size, 3), np.float32)
    orm = np.ones_like(rgb)
    for row in range(4):
        for col in range(4):
            n = 1024
            y, x = np.mgrid[0:n, 0:n].astype(np.float32) / n
            edge = np.minimum(np.minimum(x, 1-x), np.minimum(y, 1-y))
            noise = gen.random((n, n)).astype(np.float32)
            stain = (np.sin(x*34+np.sin(y*7))*np.sin(y*18+x*3))*.5+.5
            shade = .84 + noise*.035 - stain*.028 - np.exp(-edge*65)*.10
            color = np.array([.60, .625, .635], np.float32) * (1-.022*((row*4+col)%4))
            tile = shade[:, :, None] * color
            # Sparse edge chips and streaks; the recesses are baked from real geometry.
            chips = (noise > .965) & (edge < .035)
            tile[chips] *= .42
            for _ in range(32):
                px, py = gen.integers(12, n-12, 2)
                length = int(gen.integers(4, 26))
                tile[py:py+2, px:min(n, px+length)] *= .64
            if col == 2:
                tile[760:776, 90:934] *= .42
            if col == 3 and row % 2 == 0:
                tile[122:175, 130:560] *= .36
            rgb[row*n:(row+1)*n, col*n:(col+1)*n] = tile
            orm[row*n:(row+1)*n, col*n:(col+1)*n, 1] = .42 + stain*.10 + noise*.035
            orm[row*n:(row+1)*n, col*n:(col+1)*n, 2] = .22
    color = save_image('gaia_armor_basecolor', rgb, output)
    packed = save_image('gaia_armor_orm', orm, output, True)
    return color, packed


def mechanical_maps(output):
    size = 2048
    gen = np.random.default_rng(226)
    rgb = np.zeros((size, size, 3), np.float32)
    orm = np.ones_like(rgb)
    height = np.zeros((size, size), np.float32)
    colors = [(0.36,.225,.072),(.033,.043,.052),(.18,.21,.235),(.016,.021,.027)]
    for tile, color in enumerate(colors):
        n = 1024
        row, col = divmod(tile, 2)
        y, x = np.mgrid[0:n, 0:n].astype(np.float32)/n
        noise = gen.random((n,n)).astype(np.float32)
        edge = np.minimum(np.minimum(x,1-x),np.minimum(y,1-y))
        shade = .92 + noise*.045 - np.exp(-edge*50)*.15
        if tile == 0:
            shade += np.sin(y*1300)*.014
            shade -= np.exp(-((x-.12)/.007)**2)*.20
        if tile == 3:
            shade *= .60+.40*(np.sin(y*190)>.5)
        region = (slice(row*n,(row+1)*n),slice(col*n,(col+1)*n))
        rgb[region] = shade[:,:,None]*np.array(color)
        orm[region+(1,)] = [.31,.48,.30,.69][tile]+noise*.05
        orm[region+(2,)] = [.82,.60,.85,.25][tile]
        orm[region+(0,)] = 1-np.exp(-edge*60)*.2
        height[region] = noise*.0003 + (np.sin(y*190)*.001 if tile==3 else 0)
    gy,gx=np.gradient(height)
    normal=np.stack((-gx*60,-gy*60,np.ones_like(height)),axis=-1)
    normal/=np.linalg.norm(normal,axis=-1,keepdims=True)
    return (save_image('gaia_mechanical_basecolor',rgb,output),
            save_image('gaia_mechanical_normal',normal*.5+.5,output,True),
            save_image('gaia_mechanical_orm',orm,output,True))


def pbr_material(name, color, normal, orm):
    mat=bpy.data.materials.new(name)
    mat.use_nodes=True
    nodes,links=mat.node_tree.nodes,mat.node_tree.links
    p=nodes.get('Principled BSDF')
    for image, target in [(color,'Base Color'),(normal,'Normal'),(orm,'ORM')]:
        tex=nodes.new('ShaderNodeTexImage')
        tex.image=image
        if target=='Normal':
            nm=nodes.new('ShaderNodeNormalMap')
            links.new(tex.outputs['Color'],nm.inputs['Color'])
            links.new(nm.outputs['Normal'],p.inputs['Normal'])
        elif target=='ORM':
            sep=nodes.new('ShaderNodeSeparateColor')
            links.new(tex.outputs['Color'],sep.inputs['Color'])
            links.new(sep.outputs['Green'],p.inputs['Roughness'])
            links.new(sep.outputs['Blue'],p.inputs['Metallic'])
            group=bpy.data.node_groups.get('glTF Material Output')
            if group is None:
                group=bpy.data.node_groups.new('glTF Material Output','ShaderNodeTree')
                group.interface.new_socket(name='Occlusion',in_out='INPUT',socket_type='NodeSocketFloat')
            g=nodes.new('ShaderNodeGroup')
            g.node_tree=group
            links.new(sep.outputs['Red'],g.inputs['Occlusion'])
        else:
            links.new(tex.outputs['Color'],p.inputs[target])
    return mat


def bake_armor(output, color, orm):
    original=bpy.context.window.scene
    scene=bpy.data.scenes.new('GAIA_Armor_Bake')
    bpy.context.window.scene=scene
    scene.render.engine='CYCLES'
    scene.cycles.samples=8
    scene.render.bake.margin=8
    high=[]
    def block(name, dims, loc, bevel):
        bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
        ob=bpy.context.object
        ob.name=name
        ob.dimensions=dims
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        if bevel:
            m=ob.modifiers.new('HighBevel','BEVEL')
            m.width=bevel
            m.segments=4
            bpy.ops.object.modifier_apply(modifier=m.name)
        high.append(ob)
        return ob
    for row in range(4):
        for col in range(4):
            block('RaisedArmorPanel',(0.965,0.965,.04),(col+.5,row+.5,.016),.009)
            for x in [.055,.945]:
                for y in [.055,.945]:
                    bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=.010,depth=.010,location=(col+x,row+y,.042))
                    high.append(bpy.context.object)
            if (row+col)%3 == 0:
                block('InsetServiceHatch',(.48,.32,.008),(col+.53,row+.54,.041),.018)
            if col==1:
                for i in range(7):
                    block('FineCoolingSlot',(.33,.009,.012),(col+.48,row+.30+i*.035,.042),.003)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in high:
        ob.select_set(True)
    bpy.context.view_layer.objects.active=high[0]
    bpy.ops.object.join()
    source=high[0]
    source.name='GAIA_High_ArmorTrim_Editable'
    bpy.ops.mesh.primitive_plane_add(size=4,location=(2,2,0))
    low=bpy.context.object
    low.name='GAIA_Low_ArmorTrim_BakeTarget'
    target=bpy.data.materials.new('GAIA_BakeTarget')
    target.use_nodes=True
    low.data.materials.append(target)
    node=target.node_tree.nodes.new('ShaderNodeTexImage')
    target.node_tree.nodes.active=node
    normal=bpy.data.images.new('gaia_armor_normal',width=4096,height=4096,alpha=False)
    normal.colorspace_settings.name='Non-Color'
    node.image=normal
    bpy.ops.object.select_all(action='DESELECT')
    source.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active=low
    bpy.ops.object.bake(type='NORMAL',use_selected_to_active=True,cage_extrusion=.15,max_ray_distance=.3,use_clear=True,margin=8)
    normal.filepath_raw=str(output/'gaia_armor_normal.png')
    normal.file_format='PNG'
    normal.save()
    normal.pack()
    # Cycles AO of the same high trim: preserves local edge/hatch occlusion only.
    source_mat=bpy.data.materials.new('GAIA_High_AO')
    source_mat.use_nodes=True
    nodes,links=source_mat.node_tree.nodes,source_mat.node_tree.links
    ao=nodes.new('ShaderNodeAmbientOcclusion')
    ao.inputs['Distance'].default_value=.08
    emit=nodes.new('ShaderNodeEmission')
    links.new(ao.outputs['Color'],emit.inputs['Color'])
    links.new(emit.outputs[0],nodes.get('Material Output').inputs['Surface'])
    source.data.materials.clear()
    source.data.materials.append(source_mat)
    ao_image=bpy.data.images.new('GAIA_LocalAO',width=4096,height=4096,alpha=False)
    ao_image.colorspace_settings.name='Non-Color'
    node.image=ao_image
    bpy.ops.object.bake(type='EMIT',use_selected_to_active=True,cage_extrusion=.15,max_ray_distance=.3,use_clear=True,margin=8)
    values=np.empty(4096*4096*4,np.float32)
    ao_image.pixels.foreach_get(values)
    packed=np.empty_like(values)
    orm.pixels.foreach_get(packed)
    packed[0::4]=np.clip(values[0::4],.45,1)
    orm.pixels.foreach_set(packed)
    orm.save()
    orm.pack()
    bpy.data.images.remove(ao_image)
    # Editable bake sources remain separate from the model and all exports.
    collection=bpy.data.collections.new('GAIA_Editable_Armor_Bake_Source')
    original.collection.children.link(collection)
    for ob in [source,low]:
        collection.objects.link(ob)
        scene.collection.objects.unlink(ob)
    collection.hide_render=True
    collection.hide_viewport=True
    bpy.context.window.scene=original
    bpy.data.scenes.remove(scene)
    return normal
