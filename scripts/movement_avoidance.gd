extends RefCounted
## Deterministic sampled velocity obstacles. Simulation owns movement; no physics callbacks.
const HORIZON := 0.65
const CELL_SIZE := 128.0
var grid: Dictionary = {}
var velocities: Dictionary = {}
var positions: Dictionary = {}
var cached_unit: Dictionary = {}
var cached_neighbors: Array[Dictionary] = []


func begin_tick(sim) -> void:
    grid.clear()
    cached_unit = {}
    for id: int in sim.units:
        var u: Dictionary = sim.units[id]
        if u.hp <= 0:
            continue
        var cell := Vector2i((u.pos / CELL_SIZE).floor())
        if not grid.has(cell):
            grid[cell] = []
        grid[cell].append(id)
        velocities[id] = ((u.pos as Vector2) - (positions.get(id, u.pos) as Vector2)) * sim.TICK
        positions[id] = u.pos
    for id: int in positions.keys():
        if not sim.units.has(id):
            positions.erase(id)
            velocities.erase(id)


func neighbors(sim, u: Dictionary) -> Array[Dictionary]:
    if is_same(u, cached_unit):
        return cached_neighbors
    var result: Array[Dictionary] = []
    var cell := Vector2i((u.pos / CELL_SIZE).floor())
    for y in range(-2, 3):
        for x in range(-2, 3):
            for id: int in grid.get(cell + Vector2i(x, y), []):
                if not sim.units.has(id):
                    continue
                var other: Dictionary = sim.units[id]
                if not is_same(other, u) and other.hp > 0 and (other.pos as Vector2).distance_squared_to(u.pos) < 210.0 * 210.0:
                    if (u.type == "harvester" or other.type == "harvester") and sim.MiningSystem.ignore_pair(u, other):
                        continue
                    var offset: Vector2 = other.pos - u.pos
                    var gap: float = sim.UNIT_TYPES[u.type].radius + sim.UNIT_TYPES[other.type].radius
                    result.append({"unit": other, "offset": offset, "distance_squared": offset.length_squared(),
                        "gap_squared": gap * gap, "safety": gap + 2.0,
                        "velocity": Vector2.ZERO if other.order == "idle" else velocities.get(id, Vector2.ZERO)})
    cached_unit = u
    cached_neighbors = result
    return result


func next_position(sim, u: Dictionary, preferred: Vector2, continuous_lane: bool = false) -> Vector2:
    var nearby := neighbors(sim, u)
    var radius: float = sim.UNIT_TYPES[u.type].radius
    var direct: Vector2 = u.pos + preferred / sim.TICK
    if _score(preferred, preferred, nearby, sim.TICK) < 0.001 and _navigable(sim, direct, radius, continuous_lane) and sim.movement_free(u.pos, direct, radius) and not sim.ArrivalPlanner.reserved_for_other(sim, u, direct):
        return direct
    var choices: Array[Dictionary] = []
    # Right-hand bias breaks symmetric head-on encounters consistently.
    for angle: float in [0.0, 0.35, -0.35, 0.7, -0.7, 1.05, -1.05, PI / 2, -PI / 2, 2.1, -2.1, 2.6, -2.6, PI]:
        var velocity := preferred.rotated(angle)
        choices.append({"velocity": velocity, "score": _score(velocity, preferred, nearby, sim.TICK) + (0.015 if angle < 0 else 0.0)})
    for fraction: float in [0.5, 0.2, 0.0]:
        var velocity := preferred * fraction
        choices.append({"velocity": velocity, "score": _score(velocity, preferred, nearby, sim.TICK) + (4.0 if fraction == 0.0 else 0.2)})
    choices.sort_custom(func(a, b): return a.score < b.score)
    for choice: Dictionary in choices:
        if not is_finite(choice.score):
            continue
        var next: Vector2 = u.pos + choice.velocity / sim.TICK
        if _navigable(sim, next, radius, continuous_lane) and sim.movement_free(u.pos, next, radius) and not sim.ArrivalPlanner.reserved_for_other(sim, u, next):
            return next
    return u.pos


func _score(velocity: Vector2, preferred: Vector2, nearby: Array[Dictionary], tick_rate: float) -> float:
    var score: float = velocity.distance_squared_to(preferred) / maxf(preferred.length_squared(), 1.0)
    for entry: Dictionary in nearby:
        var offset: Vector2 = entry.offset
        var future: Vector2 = offset - velocity / tick_rate
        var future_squared := future.length_squared()
        # Hard next-step body clearance; allow only separating motion from an existing overlap.
        if future_squared < entry.gap_squared - 0.01 and future_squared < entry.distance_squared + 0.01:
            return INF
        var relative: Vector2 = velocity - entry.velocity
        var closing := offset.dot(relative)
        if closing <= 0.0:
            continue
        var relative_squared := relative.length_squared()
        if relative_squared < 0.001:
            continue
        var t := minf(closing / relative_squared, HORIZON)
        var distance_squared := (offset - relative * t).length_squared()
        var safety: float = entry.safety
        if distance_squared < safety * safety:
            score += 3.0 * (1.0 - sqrt(distance_squared) / safety) / (t + 0.08)
    return score


func stationary_clear(sim, u: Dictionary, from: Vector2, to: Vector2) -> bool:
    for entry: Dictionary in neighbors(sim, u):
        var other: Dictionary = entry.unit
        if other.order != "idle":
            continue
        var gap: float = sim.UNIT_TYPES[u.type].radius + sim.UNIT_TYPES[other.type].radius + 1.0
        var closest := Geometry2D.get_closest_point_to_segment(other.pos, from, to)
        if closest.distance_squared_to(other.pos) < gap * gap:
            return false
    return true


func path(sim, u: Dictionary, start: Vector2i, goal: Vector2i) -> PackedVector2Array:
    var radius: float = sim.UNIT_TYPES[u.type].radius
    var nav: AStarGrid2D = sim.navigation_for(radius)
    var temporary: Array[Vector2i] = []
    # Route around parked bodies instead of repeatedly steering into a settled formation.
    for entry: Dictionary in neighbors(sim, u):
        var other: Dictionary = entry.unit
        if other.order != "idle":
            continue
        var gap: float = radius + sim.UNIT_TYPES[other.type].radius + 2.0
        var center := Vector2i((other.pos / sim.CELL).floor())
        var cells := int(ceil(gap / sim.CELL)) + 1
        for y in range(-cells, cells + 1):
            for x in range(-cells, cells + 1):
                var cell := center + Vector2i(x, y)
                if cell == start or cell == goal or not nav.is_in_boundsv(cell) or nav.is_point_solid(cell):
                    continue
                if nav.get_point_position(cell).distance_squared_to(other.pos) < gap * gap:
                    nav.set_point_solid(cell, true)
                    temporary.append(cell)
    var result := nav.get_point_path(start, goal)
    result = sim.SweptPaths.path(sim, nav, start, goal, radius, result)
    if result.is_empty() and u.has("arrival") and not u.arrival.waiting:
        # The nearest coarse goal node can be boxed in by already-arrived units
        # although the continuous formation slot has a clear approach elsewhere.
        # Try another swept connector; keep every parked body blocked in A*.
        var candidates: Array[Vector2i] = []
        var center := Vector2i(((u.target as Vector2) / sim.CELL).floor())
        for y in range(-2, 3):
            for x in range(-2, 3):
                var cell := center + Vector2i(x, y)
                if cell != goal and nav.is_in_boundsv(cell) and not nav.is_point_solid(cell):
                    candidates.append(cell)
        candidates.sort_custom(func(a, b):
            var da: float = nav.get_point_position(a).distance_squared_to(u.target)
            var db: float = nav.get_point_position(b).distance_squared_to(u.target)
            return (a.y < b.y if a.x == b.x else a.x < b.x) if is_equal_approx(da, db) else da < db)
        for cell in candidates:
            var point := nav.get_point_position(cell)
            if not sim.movement_free(point, u.target, radius) or not stationary_clear(sim, u, point, u.target):
                continue
            result = nav.get_point_path(start, cell)
            if not result.is_empty():
                break
    for cell in temporary:
        nav.set_point_solid(cell, false)
    return result


func _navigable(sim, point: Vector2, radius: float, continuous_lane: bool = false) -> bool:
    if continuous_lane:
        return sim.position_free(point, radius)
    var nav: AStarGrid2D = sim.navigation_for(radius)
    var cell := Vector2i((point / sim.CELL).floor())
    if nav.is_in_boundsv(cell) and not nav.is_point_solid(cell):
        return true
    # Edge slots may sit outside a clear cell; require a swept connection to a clear node.
    return sim.ArrivalPlanner.goal_cell(sim, point, -1, radius).x >= 0
