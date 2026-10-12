import sys as _sys
from pathlib import Path as _Path
_blender_tools = _Path(__file__).resolve().parents[1]
_sys.path[:0] = [str(_Path(__file__).resolve().parent), str(_blender_tools), str(_blender_tools / "shared")]
"""Sample baked actions on the evaluated mesh, not just the bone transforms."""
import bpy


def audit(rig):
    previous = bpy.context.window.scene
    arm, mesh, scene = rig['arm'], rig['mesh'], rig['scene']
    action = arm.animation_data.action
    frame = scene.frame_current
    poses = {p.name:p.matrix_basis.copy() for p in arm.pose.bones}
    try:
        bpy.context.window.scene = scene
        weights = [sum(g.weight for g in v.groups) for v in mesh.data.vertices]
        edges = [tuple(e.vertices) for e in mesh.data.edges]
        lengths = [(mesh.data.vertices[a].co-mesh.data.vertices[b].co).length for a,b in edges]
        low, high, samples = 10.0, 0.0, 0
        for name in ['walk','jog','fire','death']:
            clip = rig['actions'][name]
            arm.animation_data.action = clip
            for fraction in [0,.125,.25,.375,.5,.625,.75,.875,1]:
                scene.frame_set(int(clip.frame_range[0]+fraction*(clip.frame_range[1]-clip.frame_range[0])))
                scene.view_layers[0].update()
                evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
                geometry = evaluated.to_mesh()
                try:
                    for (a,b),length in zip(edges,lengths):
                        ratio = (geometry.vertices[a].co-geometry.vertices[b].co).length / max(length,1e-9)
                        low, high = min(low,ratio), max(high,ratio)
                    samples += 1
                finally:
                    evaluated.to_mesh_clear()
        result = {'skin_samples':samples,'skin_min_edge_ratio':low,'skin_max_edge_ratio':high,
                  'skin_unweighted_vertices':sum(w<.99 for w in weights),
                  'skin_max_weight_error':max(abs(w-1) for w in weights)}
        assert result['skin_unweighted_vertices']==0, result
        assert result['skin_max_weight_error']<1e-5, result
        assert low>.10 and high<3.0, result
        return result
    finally:
        arm.animation_data.action = action
        scene.frame_set(frame)
        for pose in arm.pose.bones:
            pose.matrix_basis = poses[pose.name]
        bpy.context.window.scene = previous
