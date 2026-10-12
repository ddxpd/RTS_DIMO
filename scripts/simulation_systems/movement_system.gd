extends RefCounted
## Synchronous rules; Simulation owns state, caches and tick order.
const Terrain = preload("res://scripts/maps/map_terrain.gd")
const Flight = preload("res://scripts/barracks_flight.gd")
const Arrivals = preload("res://scripts/arrival_planner.gd")


static func rebuild_navigation(sim: Simulation) -> void:
    sim.arrival_nav_regions.clear()
    sim.navigation_by_radius.clear()
    sim.connectivity_by_radius.clear()
    sim.blocked_sight.clear()
    sim.swept_graphs.clear()
    sim.nav = navigation_for(sim, Simulation.UNIT_TYPES.mobile_infantry.radius)
    for u: Dictionary in sim.units.values():
        u.path = []
        u.repath = 0


static func navigation_for(sim: Simulation, radius: float) -> AStarGrid2D:
    if sim.navigation_by_radius.has(radius):
        return sim.navigation_by_radius[radius]
    var grid := AStarGrid2D.new()
    grid.region = Rect2i(0, 0, Simulation.GRID.x, Simulation.GRID.y)
    grid.cell_size = Vector2(Simulation.CELL, Simulation.CELL)
    grid.offset = Vector2(Simulation.CELL / 2, Simulation.CELL / 2)
    grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
    grid.update()
    for y in range(Simulation.GRID.y):
        for x in range(Simulation.GRID.x):
            grid.set_point_solid(Vector2i(x, y), not position_free(sim, Vector2(x * Simulation.CELL + 16, y * Simulation.CELL + 16), radius))
    sim.navigation_by_radius[radius] = grid
    return grid


static func movement_free(sim: Simulation, from: Vector2, to: Vector2, radius: float) -> bool:
    # Terrain and expanded static bodies are tested together at <=8-unit intervals.
    if not position_free(sim, to, radius):
        return false
    var steps := maxi(1, int(ceil(from.distance_to(to) / 8.0)))
    for index in range(1, steps):
        if not position_free(sim, from.lerp(to, float(index) / steps), radius):
            return false
    return true


static func route_visible(sim: Simulation, from: Vector2, to: Vector2, radius: float) -> bool:
    var key := Vector4(from.x / 16.0, from.y / 16.0, to.x, to.y)
    key.x = floorf(key.x)
    key.y = floorf(key.y)
    var profile: Dictionary = sim.blocked_sight.get(radius, {})
    if profile.has(key):
        return false
    if sim.movement_free(from, to, radius):
        return true
    # Cache only blocked shortcuts; actual motion is always swept again.
    if profile.size() >= 2048:
        profile.clear()
    profile[key] = true
    sim.blocked_sight[radius] = profile
    return false


static func position_free(sim: Simulation, pos: Vector2, radius: float) -> bool:
    var terrain: Terrain = sim.terrain
    if not terrain.position_clear(pos, radius):
        return false
    var world: Vector2 = Simulation.WORLD
    if not Rect2(Vector2(radius, radius), world - Vector2.ONE * radius * 2).has_point(pos):
        return false
    for rock: Rect2 in sim.obstacles:
        if rock.grow(radius).has_point(pos):
            return false
    var buildings: Dictionary = sim.buildings
    for id: int in buildings:
        var b: Dictionary = buildings[id]
        var flight_state := Flight.state(b)
        if b.type == "refinery":
            if Simulation.DepotDocking.blocked(pos - (b.pos as Vector2), radius):
                return false
        elif flight_state != "airborne" and sim.footprint(b, radius).has_point(pos):
            return false
    return true


static func nearest_cell(sim: Simulation, pos: Vector2, radius: float = 16.0) -> Vector2i:
    var nav: AStarGrid2D = navigation_for(sim, radius)
    var base := Vector2i((pos / Simulation.CELL).floor())
    base = base.clamp(Vector2i.ZERO, nav.region.size - Vector2i.ONE)
    if not nav.is_point_solid(base):
        return base
    for search_ring in range(1, 12):
        for x in range(-search_ring, search_ring + 1):
            for y in range(-search_ring, search_ring + 1):
                var p := base + Vector2i(x, y)
                if nav.is_in_boundsv(p) and not nav.is_point_solid(p):
                    return p
    return base


static func move_towards(sim: Simulation, u: Dictionary, destination: Vector2, stop_distance: float = 4.0) -> void:
    var radius: float = Simulation.UNIT_TYPES[u.type].radius
    var distance: float = (u.pos as Vector2).distance_to(destination)
    if u.has("arrival") and destination == u.target:
        stop_distance = 0.1
    if distance <= stop_distance:
        return
    if (u.has("dock") and u.dock.phase in ["enter", "exit"]) or Simulation.MiningSystem.intangible(u):
        # A designed berth lane can fit the body without containing a coarse
        # navigation node. Sweep the reserved lane continuously, retaining body
        # clearance and unit avoidance rather than steering toward a remote node.
        if sim.movement_free(u.pos, destination, radius):
            var speed: float = Simulation.UNIT_TYPES[u.type].speed
            var preferred: Vector2 = (destination - (u.pos as Vector2)).limit_length(speed / Simulation.TICK) * Simulation.TICK
            u.pos = sim.avoidance.next_position(sim, u, preferred, true)
            return
        if u.has("dock") and u.dock.phase in ["enter", "exit"]:
            return
    u.repath = int(u.repath) - 1
    if u.path.is_empty() or u.repath <= 0:
        var start: Vector2i = nearest_cell(sim, u.pos, radius)
        var goal: Vector2i = nearest_cell(sim, destination, radius)
        if u.has("mining") and not u.has("dock"):
            start = Arrivals.goal_cell(sim, u.pos, -1, radius)
            goal = Arrivals.goal_cell(sim, destination, -1, radius)
            if start.x < 0 or goal.x < 0:
                return
        if u.has("arrival") and destination == u.target:
            start = Arrivals.goal_cell(sim, u.pos, -1, radius)
            goal = Arrivals.goal_cell(sim, destination, int(u.arrival.region), radius)
            if start.x < 0 or goal.x < 0:
                u.arrival.waiting = true
                return
        u.path = Array(sim.avoidance.path(sim, u, start, goal))
        if u.path.is_empty() and Arrivals.retry_stalled_slot(sim, u):
            return
        if u.path.size() > 1 and sim.movement_free(u.pos, u.path[1], radius):
            u.path.pop_front()
        if not u.path.is_empty() and sim.movement_free(u.path.back(), destination, radius):
            u.path.append(destination)
        u.repath = 30
    # Follow the furthest locally visible waypoint to remove grid corner zigzags.
    while u.path.size() > 1 and route_visible(sim, u.pos, u.path[1], radius) and sim.avoidance.stationary_clear(sim, u, u.pos, u.path[1]):
        u.path.pop_front()
    while not u.path.is_empty() and (u.pos as Vector2).distance_to(u.path[0]) < 1.0:
        u.path.pop_front()
    var waypoint: Vector2 = destination if u.path.is_empty() else u.path[0]
    if u.path.is_empty() and not sim.movement_free(u.pos, waypoint, radius):
        u.repath = 0
        return
    var speed: float = Simulation.UNIT_TYPES[u.type].speed
    if u.has("arrival") and not u.arrival.waiting:
        speed = minf(speed, maxf(8.0, distance * 4.0))
    var preferred: Vector2 = (waypoint - (u.pos as Vector2)).limit_length(speed / Simulation.TICK) * Simulation.TICK
    u.pos = sim.avoidance.next_position(sim, u, preferred)


static func _unit_blocks(sim: Simulation, u: Dictionary, next: Vector2) -> bool:
    for other: Dictionary in sim.units.values():
        if other == u or other.hp <= 0:
            continue
        var clearance: float = Simulation.UNIT_TYPES[u.type].radius + Simulation.UNIT_TYPES[other.type].radius
        if (other.pos as Vector2).distance_to(next) < clearance:
            return true
    return false


static func _unstick(sim: Simulation, u: Dictionary) -> void:
    # Retry routing; never teleport a body through another unit or a wall.
    u.path = []
    u.repath = 0
    u.stuck = 0
    Arrivals.retry_stalled_slot(sim, u)


static func _separate_units(sim: Simulation) -> void:
    # Spatial-hash unit separation keeps dense armies from becoming an O(N^2)
    # scan every iteration. The maximum combined radius is below one cell.
    var cell_size := 128.0
    var grid: Dictionary = {}
    var units: Dictionary = sim.units
    for id: int in units:
        var unit: Dictionary = units[id]
        if unit.hp <= 0:
            continue
        var cell := Vector2i(((unit.pos as Vector2) / cell_size).floor())
        if not grid.has(cell):
            grid[cell] = []
        grid[cell].append(id)

    var offsets := [
        Vector2i.ZERO,
        Vector2i.RIGHT,
        Vector2i.DOWN,
        Vector2i(1, 1),
        Vector2i(-1, 1)
    ]
    for iteration in range(3):
        for cell: Vector2i in grid:
            var cell_ids: Array = grid[cell]
            for i in range(cell_ids.size()):
                var a: Dictionary = units[cell_ids[i]]
                if a.hp <= 0:
                    continue
                for j in range(i + 1, cell_ids.size()):
                    _separate_pair(sim, a, units[cell_ids[j]])
                for offset: Vector2i in offsets:
                    if offset == Vector2i.ZERO:
                        continue
                    var neighbor_ids: Array = grid.get(cell + offset, [])
                    for j in range(neighbor_ids.size()):
                        _separate_pair(sim, a, units[neighbor_ids[j]])


static func _separate_pair(sim: Simulation, a: Dictionary, b: Dictionary) -> void:
    if a.hp <= 0 or b.hp <= 0:
        return
    var delta: Vector2 = b.pos - a.pos
    var unit_types: Dictionary = Simulation.UNIT_TYPES
    var minimum: float = unit_types[a.type].radius + unit_types[b.type].radius + 1
    # Touching units let move sidesteps form lanes; separation only resolves
    # deeper overlaps so it cannot fight the path.
    if delta.length_squared() >= (minimum - 1.0) * (minimum - 1.0):
        return
    if (a.type == "harvester" or b.type == "harvester") and Simulation.MiningSystem.ignore_pair(a, b):
        return
    var distance := delta.length()
    var normal := Vector2.RIGHT if distance < 0.001 else delta / distance
    var amount := minimum - distance
    var a_stopped: bool = a.order == "idle"
    var b_stopped: bool = b.order == "idle"
    var a_weight := 0.0 if a_stopped and not b_stopped else (1.0 if b_stopped and not a_stopped else 0.5)
    var pa: Vector2 = a.pos - normal * amount * a_weight
    var pb: Vector2 = b.pos + normal * amount * (1.0 - a_weight)
    if Arrivals.displace_free(sim, a, pa):
        a.pos = pa
    if Arrivals.displace_free(sim, b, pb):
        b.pos = pb


static func refresh_arrivals(sim: Simulation) -> void:
    Arrivals.refresh(sim)


static func plan_arrivals(sim: Simulation, ids: Array, destination: Vector2) -> Dictionary:
    return Arrivals.plan(sim, ids, destination)


static func begin_tick(sim: Simulation) -> void:
    sim.avoidance.begin_tick(sim)


static func advance_move(sim: Simulation, u: Dictionary) -> void:
    sim.move_towards(u, u.target)
    if (u.pos as Vector2).distance_to(u.target) < (2.0 if u.has("arrival") else 5.0) and (not u.has("arrival") or not u.arrival.waiting):
        u.order = "idle"
        if u.has("arrival"):
            u.arrival.arrived = true


static func track_stall(sim: Simulation, u: Dictionary, pos_before: Vector2) -> void:
    if u.order in ["move", "attack_move", "gather"]:
        if (u.has("arrival") and u.arrival.waiting) or (u.order == "attack_move" and int(u.attack_id) >= 0):
            u.stuck = 0
        else:
            if (u.pos as Vector2).distance_to(pos_before) < 0.005:
                u.stuck = int(u.stuck) + 1
            else:
                u.stuck = 0
            if int(u.stuck) >= 40:
                sim._unstick(u)
