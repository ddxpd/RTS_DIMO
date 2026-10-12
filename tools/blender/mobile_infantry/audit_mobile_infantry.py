import sys as _sys
from pathlib import Path as _Path
_blender_tools = _Path(__file__).resolve().parents[1]
_sys.path[:0] = [str(_Path(__file__).resolve().parent), str(_blender_tools), str(_blender_tools / "shared")]
"""Independent positive-area UV intersection check on the actual source faces."""
from collections import defaultdict
import math


def area(poly):
    return sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(poly,poly[1:]+poly[:1]))*.5


def intersection(subject, clip):
    for a,b in zip(clip,clip[1:]+clip[:1]):
        def distance(p):
            return (b[0]-a[0])*(p[1]-a[1])-(b[1]-a[1])*(p[0]-a[0])
        output=[]
        if not subject:
            return []
        previous=subject[-1]; previous_d=distance(previous)
        for current in subject:
            current_d=distance(current)
            if (current_d>=0)!=(previous_d>=0):
                fraction=previous_d/(previous_d-current_d)
                output.append(tuple(previous[i]+fraction*(current[i]-previous[i]) for i in range(2)))
            if current_d>=0:
                output.append(current)
            previous,previous_d=current,current_d
        subject=output
    return subject


def audit(objects):
    # Triangulate UV faces independently, then compare positive-area overlap.
    polygons=[]; cells=defaultdict(list); checked=set(); overlaps=[]
    for obj in objects:
        mesh=obj.data
        mesh.calc_loop_triangles()
        for triangle in mesh.loop_triangles:
            poly=[tuple(mesh.uv_layers.active.data[i].uv) for i in triangle.loops]
            signed=area(poly)
            assert abs(signed)>1e-12, (obj.name,'degenerate UV triangle')
            if signed<0:
                poly.reverse()
            index=len(polygons); polygons.append(poly)
            low=[math.floor(min(p[i] for p in poly)*64) for i in range(2)]
            high=[math.floor(max(p[i] for p in poly)*64) for i in range(2)]
            for x in range(low[0],high[0]+1):
                for y in range(low[1],high[1]+1):
                    for other in cells[x,y]:
                        pair=(other,index)
                        if pair in checked:
                            continue
                        checked.add(pair)
                        # Tolerance <0.005 texel² at 2048², excludes shared edges.
                        if abs(area(intersection(poly,polygons[other])))>1e-9:
                            overlaps.append(pair)
                    cells[x,y].append(index)
    assert not overlaps, overlaps[:10]
    return {'uv_triangle_intersection_pairs':len(overlaps),
            'uv_triangles_checked':len(polygons),
            'uv_candidate_pairs_checked':len(checked)}
