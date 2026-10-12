import sys as _sys
from pathlib import Path as _Path
_blender_tools = _Path(__file__).resolve().parents[1]
_sys.path[:0] = [str(_Path(__file__).resolve().parent), str(_blender_tools), str(_blender_tools / "shared")]
"""Shoulder-only team paint and baked shallow surface detail, preserving v2 recipes."""
import importlib.util
import json
import math
import os

import bpy
import numpy as np

HERE = os.path.dirname(__file__)


def module(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + '.py'))
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


v2 = module('create_mobile_infantry_v2')
base = v2.base
baker = module('bake_mobile_infantry_v2')
finalizer = module('finalize_mobile_infantry_v2')


class Builder(v2.Builder):
    def __init__(self):
        super().__init__()
        self.scene.name = 'MI_V3_AssetStudio'
        self.root['asset_version'] = 3
        self.preserve_high_normals_roles = {'HelmetDome', 'VisorGlass'}

    def part(self, name, rings, kind='armor', center=(0, 0, 0), rotation=None, smooth=False):
        if name == 'BackFaction' or name == 'VisorBrow' or name.startswith(('ForearmBand', 'ShoulderFaction', 'CheekVent')):
            return None
        if name.startswith('ShoulderArmor'):
            kind = 'mark'
        elif name.startswith('KneeFaction'):
            name = name.replace('Faction', 'Armor')
            kind = 'rubber'
        elif name == 'VisorGlass':
            center = (0, -.121, 1.679)
            rings = [(-.043, .172, .020), (-.028, .211, .042), (.026, .215, .040), (.044, .192, .027)]
            smooth = True
        obj = super().part(name, rings, kind, center, rotation, smooth)
        if name == 'VisorGlass':
            # Wrap toward the temples instead of a planar rectangular bar.
            for vertex in obj.data.vertices:
                vertex.co.y += .035 * (vertex.co.x / .108) ** 2
            obj.data.update()
        return obj

    def build_geometry(self):
        super().build_geometry()
        dome = next(o for o in self.objects if o['part_role'] == 'HelmetDome')
        dome.data.materials.clear()
        dome.data.materials.append(self.materials[0])
        for polygon in dome.data.polygons:
            polygon.material_index = 0
        self.scene.view_layers[0].update()

    def validate(self):
        report = super().validate()
        faction = sorted(o['part_role'] for o in self.objects if self.materials[1] in list(o.data.materials))
        assert faction == ['ShoulderArmorL', 'ShoulderArmorR'], faction
        report.update(version=3, reference='assets/concept_art/机动兵2.png', faction_parts=faction,
                      faction_scope='entire shoulder shells only', high_detail_collection='MI_V3_BakeSources')
        return report

    def render(self, filename, *args, **kwargs):
        return super().render(filename.replace('-v2', '-v3'), *args, **kwargs)

    def attach_detail_height(self, material):
        nodes, links = material.node_tree.nodes, material.node_tree.links
        shader = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
        texture = nodes.new('ShaderNodeTexImage')
        texture.name = 'Editable shallow surface relief'
        texture.image = self.detail_height
        bump = nodes.new('ShaderNodeBump')
        bump.inputs['Strength'].default_value = 1.0
        bump.inputs['Distance'].default_value = .003
        links.new(texture.outputs['Color'], bump.inputs['Height'])
        links.new(bump.outputs['Normal'], shader.inputs['Normal'])

    def surface_detail(self):
        """Editable scalar relief used by the high source shader, not runtime geometry.

        Long UV strips carry eight perimeter faces; face 0 is front, face 4 back.
        Height ramps have a physical shallow depth and taper before UV seams.
        """
        size = 2048
        pixels = np.full((size, size, 4), .5, np.float32)
        pixels[:, :, 3] = 1
        lengths = [1.44, math.hypot(.28, .28)] * 4
        boundaries = np.cumsum([0] + lengths) / sum(lengths)
        detail_roles = set()

        def line(value, center, width):
            return np.exp(-((value - center) / width) ** 2)

        def panel(u, v, cx, cy, rx, ry, width):
            # Rounded rectangle signed distance; a soft narrow recessed seam.
            radius = .05
            qx = np.abs(u - cx) - rx + radius
            qy = np.abs(v - cy) - ry + radius
            distance = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - radius
            return np.exp(-(distance / width) ** 2)

        for island in self.islands:
            obj = island['object']
            role, kind = obj['part_role'], island['kind']
            if island['faces'][0] != 0:
                continue
            x, y, w, h = island['rect']
            vv, uu = np.mgrid[0:h, 0:w].astype(np.float32)
            uu = (uu + .5) / w
            vv = (vv + .5) / h
            face = np.clip(np.searchsorted(boundaries, uu, side='right') - 1, 0, 7)
            fu = (uu - boundaries[face]) / (boundaries[face + 1] - boundaries[face])
            fade = np.clip(np.minimum(fu, 1 - fu) * 12, 0, 1) * np.clip(np.minimum(vv, 1 - vv) * 12, 0, 1)
            relief = np.zeros((h, w), np.float32)
            if role == 'HelmetDome':
                # Forehead inset and temple panel seams; no raised brow strip.
                front = face == 0
                relief -= .18 * panel(fu, vv, .5, .52, .27, .31, .014) * front
                relief -= .15 * (line(fu, .20, .014) + line(fu, .80, .014)) * (face == 4)
                relief -= .15 * panel(fu, vv, .5, .46, .30, .25, .016) * ((face == 2) | (face == 6))
            elif role.startswith('CheekArmor') or role == 'RespiratorCore':
                for slot in [.28, .43, .58, .73]:
                    relief -= .22 * line(fu, slot, .022) * np.exp(-((vv - .52) / .24) ** 6)
            elif kind in ['armor', 'mark']:
                relief -= .15 * panel(fu, vv, .5, .50, .36, .33, .016) * ((face % 2) == 0)
                for px in [.19, .81]:
                    for py in [.23, .77]:
                        relief -= .14 * np.exp(-(((fu - px) / .035) ** 2 + ((vv - py) / .035) ** 2)) * ((face % 2) == 0)
            elif kind in ['fabric', 'cloth']:
                # Stitch/edge detail complements the actual high-poly folds.
                relief -= .13 * (line(fu, .14, .022) + line(fu, .86, .022))
                relief += .09 * (line(fu, .19, .018) + line(fu, .81, .018)) * np.maximum(np.cos(vv * 30 * math.pi), 0) ** 4
            elif role.startswith('Rifle_') and role.endswith(('Handguard', 'Receiver', 'Magazine', 'Stock')):
                for slot in [.23, .36, .49, .62, .75]:
                    relief -= .25 * line(fu, slot, .021) * np.exp(-((vv - .50) / .25) ** 6)
            elif role.startswith(('Boot', 'Glove', 'KneeArmor', 'Belt', 'FrontMagPouch', 'RearBeltPouch')):
                relief -= .17 * panel(fu, vv, .5, .5, .35, .30, .030) * ((face % 2) == 0)
                if role.startswith('Boot'):
                    relief -= .12 * line(vv, .33, .035) * (face == 0)
            height = .5 + relief * fade
            if np.max(np.abs(height - .5)) > .01:
                detail_roles.add(role)
            tile = np.repeat(height[:, :, None], 3, axis=2)
            pixels[y-5:y+h+5, x-5:x+w+5, :3] = np.pad(tile, ((5, 5), (5, 5), (0, 0)), mode='edge')
        self.detail_height = bpy.data.images.new('MI_V3_SourceRelief', width=size, height=size, alpha=False)
        self.detail_height.colorspace_settings.name = 'Non-Color'
        self.detail_height.pixels.foreach_set(pixels.ravel())
        baker.packed_save(self.detail_height, os.path.join(base.OUT, 'mobile_infantry_source_relief_v3.png'))
        self.report['surface_detail_parts'] = sorted(detail_roles)

    def audit_helmet_normal(self):
        pixels = np.empty(2048 * 2048 * 4, np.float32)
        self.images['normal'].pixels.foreach_get(pixels)
        pixels = pixels.reshape(2048, 2048, 4)
        island = next(i for i in self.islands if i['object']['part_role'] == 'HelmetDome' and i['faces'][0] == 0)
        x, y, w, h = island['rect']
        region = pixels[y+3:y+h-3, x+3:x+w-3, :3]
        deviation = np.linalg.norm(region[:, :, :2] - .5, axis=2)
        assert float(deviation.max()) > .025, 'Helmet surface relief failed to bake'
        assert np.isfinite(region).all()
        self.report['helmet_normal_detail_max'] = float(deviation.max())
        self.report['helmet_normal_detail_pixels'] = int((deviation > .015).sum())

    def render_surface_review(self):
        """Deliverable close-ups: same camera, normal toggle, then raking light."""
        self.render('mobile-infantry-helmet-v3.png', (1.6, -5, 2.45), target=(0, 0, 1.63), scale=.59, width=1000, height=1000)
        disconnected = []
        lighting = [(o, o.matrix_world.copy(), o.data.energy, o.data.size) for o in self.scene.objects if o.type == 'LIGHT']
        try:
            for material in self.materials:
                shader = next(n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
                for link in list(shader.inputs['Normal'].links):
                    disconnected.append((material, link.from_socket, link.to_socket))
                    material.node_tree.links.remove(link)
            self.render('mobile-infantry-helmet-normal-off-v3.png', (1.6, -5, 2.45), target=(0, 0, 1.63), scale=.59, width=1000, height=1000)
        finally:
            for material, source, target in disconnected:
                material.node_tree.links.new(source, target)
        try:
            for obj, matrix, energy, size in lighting:
                if obj.name.startswith('MI_Key'):
                    obj.location = (-3, -2, 3)
                    obj.data.size = .9
                    obj.rotation_euler = (v2.Vector((0, 0, 1.65)) - obj.location).to_track_quat('-Z', 'Y').to_euler()
                else:
                    obj.data.energy *= .3
            self.render('mobile-infantry-helmet-raking-v3.png', (1.6, -5, 2.45), target=(0, 0, 1.63), scale=.59, width=1000, height=1000)
        finally:
            for obj, matrix, energy, size in lighting:
                obj.matrix_world = matrix
                obj.data.energy = energy
                obj.data.size = size


def create():
    previous = bpy.context.window.scene
    try:
        b = Builder()
        bpy.app.driver_namespace['mi_v3_builder'] = b
        bpy.context.window.scene = b.scene
        b.build_geometry()
        b.layout_uv()
        b.validate()
        b.textures()
        b.surface_detail()
        bpy.app.driver_namespace['mi_v3_status'] = {'stage': 'baking', 'quads': b.report['source_quads']}
        baker.bake(b, base.OUT)
        baker.weather(b, base.OUT)
        b.audit_helmet_normal()
        b.high_collection.name = 'MI_V3_BakeSources'
        b.report['high_detail_collection'] = b.high_collection.name
        b.studio()
        bpy.app.driver_namespace['mi_v3_status'] = {'stage': 'rendering'}
        finalizer.render(b)
        b.render_surface_review()
        # Export after review renders restore the asset root to its origin.
        finalizer.export(b, base)
        with open(os.path.join(base.OUT, 'design-spec-v3.json'), 'w', encoding='utf-8') as stream:
            json.dump({'version': 3, 'reference': 'assets/concept_art/机动兵2.png', 'team_markings': 'entire shoulder shells only',
                       'surface_detail': 'baked tangent-space normals from high geometry plus editable scalar relief',
                       'scope': 'static asset; no production integration or animation', 'report': b.report}, stream, ensure_ascii=False, indent=2)
        return b
    finally:
        bpy.context.window.scene = previous


if __name__ == '__main__':
    create()
