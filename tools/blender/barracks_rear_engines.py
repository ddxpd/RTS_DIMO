"""Rear propulsion geometry shared by all three barracks LOD builds."""
import math
import bpy


def add_rear_engines(root, level):
    """Blender +Y is the front door; exhaust points along -Y (Godot +Z)."""
    metal = bpy.data.materials.get('RTS_EngineMetal')
    if metal is None:
        metal = bpy.data.materials.new('RTS_EngineMetal')
        metal.use_nodes = True
        shader = next(node for node in metal.node_tree.nodes if node.type == 'BSDF_PRINCIPLED')
        shader.inputs['Base Color'].default_value = (.19, .22, .24, 1)
        shader.inputs['Metallic'].default_value = .75
        shader.inputs['Roughness'].default_value = .62
        colors = metal.node_tree.nodes.new('ShaderNodeVertexColor')
        colors.layer_name = 'Color'
        metal.node_tree.links.new(colors.outputs['Color'], shader.inputs['Base Color'])
    glow = next(mat for mat in bpy.data.materials if 'Thrust' in mat.name)
    segments = [16, 10, 6][level]
    created = []
    for side, label in [(-1, 'L'), (1, 'R')]:
        vertices, faces, colors, slots = [], [], [], []
        # A flared, hollow nozzle with dark recessed throat and thick metal lip.
        rings = [(.44, .68, (.16, .19, .20, 1)),
                 (.64, .35, (.23, .27, .29, 1)),
                 (.64, -.48, (.13, .16, .18, 1)),
                 (.52, -.55, (.31, .34, .36, 1)),
                 (.43, -.50, (.08, .095, .11, 1)),
                 (.27, .12, (.012, .018, .024, 1))]
        for radius, depth, color in rings:
            for i in range(segments):
                angle = math.tau * i / segments
                vertices.append((math.cos(angle) * radius, depth, math.sin(angle) * radius))
                colors.append(color)
        for ring in range(len(rings) - 1):
            for i in range(segments):
                a = ring * segments + i
                b = ring * segments + (i + 1) % segments
                faces.append((a, b, b + segments, a + segments))
                slots.append(0)
        vertices.append((0, .14, 0))
        colors.append((1, 1, 1, 1))
        for i in range(segments):
            faces.append(((len(rings) - 1) * segments + i,
                          (len(rings) - 1) * segments + (i + 1) % segments,
                          len(vertices) - 1))
            slots.append(1)
        mesh = bpy.data.meshes.new('RearEngine' + label + 'Geometry')
        mesh.from_pydata(vertices, [], faces)
        mesh.materials.append(metal)
        mesh.materials.append(glow)
        attribute = mesh.color_attributes.new(name='Color', type='FLOAT_COLOR', domain='POINT')
        for entry, color in zip(attribute.data, colors):
            entry.color = color
        for polygon, slot in zip(mesh.polygons, slots):
            polygon.material_index = slot
        obj = bpy.data.objects.new('RearEngine' + label + 'Mesh', mesh)
        bpy.context.collection.objects.link(obj)
        obj.parent = root
        obj.location = (side * 2.7, -3.38, 2.65)
        created.append(obj)
    return created
