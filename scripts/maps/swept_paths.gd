extends RefCounted
## Coarse clear nodes can straddle an impassable sliver at ramp/cliff joins.
## Fall back to an edge-validated graph only when a coarse route crosses one.
static func path(sim, nav: AStarGrid2D, start: Vector2i, goal: Vector2i, radius: float, coarse: PackedVector2Array) -> PackedVector2Array:
    # Analytic map modules have continuous interiors; the stitched triangle
    # surface is the map with sub-cell slope/cliff seams requiring this graph.
    if sim.terrain.sample_surface == null:
        return coarse
    var invalid := false
    for i in range(1, coarse.size()):
        if not sim.movement_free(coarse[i - 1], coarse[i], radius):
            invalid = true
            break
    if not invalid:
        return coarse
    if not sim.swept_graphs.has(radius):
        var graph := AStar2D.new()
        # Build from static geometry, independently of transient unit masks.
        for y in range(sim.GRID.y):
            for x in range(sim.GRID.x):
                var cell := Vector2i(x, y)
                var point := nav.get_point_position(cell)
                if sim.position_free(point, radius):
                    graph.add_point(y * sim.GRID.x + x, point)
        for id: int in graph.get_point_ids():
            var cell := Vector2i(id % sim.GRID.x, id / sim.GRID.x)
            for offset: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i(1, 1), Vector2i(-1, 1)]:
                var next := cell + offset
                var next_id: int = next.y * sim.GRID.x + next.x
                if not nav.is_in_boundsv(next) or not graph.has_point(next_id):
                    continue
                if offset.x != 0 and offset.y != 0 and (not graph.has_point(cell.y * sim.GRID.x + next.x) or not graph.has_point(next.y * sim.GRID.x + cell.x)):
                    continue
                if sim.movement_free(graph.get_point_position(id), graph.get_point_position(next_id), radius):
                    graph.connect_points(id, next_id)
        sim.swept_graphs[radius] = graph
    var graph: AStar2D = sim.swept_graphs[radius]
    var disabled: Array[int] = []
    for id: int in graph.get_point_ids():
        if nav.is_point_solid(Vector2i(id % sim.GRID.x, id / sim.GRID.x)):
            graph.set_point_disabled(id, true)
            disabled.append(id)
    var a: int = start.y * sim.GRID.x + start.x
    var b: int = goal.y * sim.GRID.x + goal.x
    var result := graph.get_point_path(a, b) if graph.has_point(a) and graph.has_point(b) else PackedVector2Array()
    for id: int in disabled:
        graph.set_point_disabled(id, false)
    return result
