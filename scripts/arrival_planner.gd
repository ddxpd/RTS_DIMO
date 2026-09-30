extends RefCounted
## Host-side compact reservations. Intent lives in units and survives snapshots.


static func goal_cell(sim, point: Vector2, region: int, radius: float) -> Vector2i:
    var base := Vector2i((point / sim.CELL).floor())
    if sim.nav.is_in_boundsv(base) and not sim.nav.is_point_solid(base):
        var index: int = base.y * sim.GRID.x + base.x
        if sim.terrain.arrival_regions.labels[index] == region and sim.movement_free(sim.nav.get_point_position(base), point, radius):
            return base
    var result := Vector2i(-1, -1)
    var best := INF
    for y in range(-2, 3):
        for x in range(-2, 3):
            var cell := base + Vector2i(x, y)
            if not sim.nav.is_in_boundsv(cell) or sim.nav.is_point_solid(cell):
                continue
            var index: int = cell.y * sim.GRID.x + cell.x
            if sim.terrain.arrival_regions.labels[index] != region:
                continue
            var p: Vector2 = sim.nav.get_point_position(cell)
            var d := p.distance_squared_to(point)
            if d < best and sim.movement_free(p, point, radius):
                best = d
                result = cell
    return result


static func plan(sim, ids: Array, anchor: Vector2, region: int = -1) -> Dictionary:
    if region < 0:
        region = sim.terrain.arrival_region_at(anchor)
    if region < 0:
        return {"error": "点击位置没有可到达的平台，请点击平台内部。"}
    var candidates: Array[Vector2] = sim.terrain.arrival_candidates(anchor, region)
    _ensure_connectivity(sim)
    var occupied := {}
    for id: int in sim.units:
        var other: Dictionary = sim.units[id]
        if other.hp <= 0 or ids.has(id):
            continue
        _occupy(occupied, other.pos, sim.UNIT_TYPES[other.type].radius)
        if other.has("arrival") and not other.arrival.waiting:
            _occupy(occupied, other.target, sim.UNIT_TYPES[other.type].radius)
    var result := {}
    var reachable := {}
    var goal_cache := {}
    var full_radii := {}
    for id: int in ids:
        var u: Dictionary = sim.units[id]
        var radius: float = sim.UNIT_TYPES[u.type].radius
        var source_region: int = sim.terrain.arrival_region_at(u.pos)
        var start := goal_cell(sim, u.pos, source_region, radius)
        if start.x < 0:
            return {"error": "单位当前位置没有通往目标平台的路线。"}
        var fallback := Vector2(INF, INF)
        var selected := Vector2(INF, INF)
        for p: Vector2 in candidates:
            if fallback.is_finite() and not _space_free(occupied, p, radius):
                continue
            var slot_key := Vector3(p.x, p.y, radius)
            if not goal_cache.has(slot_key):
                goal_cache[slot_key] = goal_cell(sim, p, region, radius) if sim.position_free(p, radius) else Vector2i(-1, -1)
            var goal: Vector2i = goal_cache[slot_key]
            if goal.x < 0:
                continue
            var key := Vector4i(start.x, start.y, goal.x, goal.y)
            if not reachable.has(key):
                reachable[key] = sim.arrival_nav_regions[start.y * sim.GRID.x + start.x] == sim.arrival_nav_regions[goal.y * sim.GRID.x + goal.x]
            if not reachable[key]:
                continue
            if not fallback.is_finite():
                fallback = p
            if full_radii.has(radius):
                break
            if _space_free(occupied, p, radius):
                selected = p
                break
        if not fallback.is_finite():
            return {"error": "目标平台不可达，原有命令保持不变。"}
        var waiting := not selected.is_finite()
        if waiting:
            full_radii[radius] = true
        result[id] = {"target": fallback if waiting else selected,
            "arrival": {"anchor": anchor, "region": region, "waiting": waiting, "arrived": false}}
        if not waiting:
            _occupy(occupied, selected, radius)
    return {"orders": result}


static func _ensure_connectivity(sim) -> void:
    if not sim.arrival_nav_regions.is_empty():
        return
    sim.arrival_nav_regions.resize(sim.GRID_CELLS)
    sim.arrival_nav_regions.fill(-1)
    var label := 0
    for seed in sim.GRID_CELLS:
        var cell := Vector2i(seed % sim.GRID.x, int(seed / sim.GRID.x))
        if sim.arrival_nav_regions[seed] >= 0 or sim.nav.is_point_solid(cell):
            continue
        var queue: Array[Vector2i] = [cell]
        sim.arrival_nav_regions[seed] = label
        var head := 0
        while head < queue.size():
            var p := queue[head]
            head += 1
            for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
                var n := p + d
                if not sim.nav.is_in_boundsv(n) or sim.nav.is_point_solid(n):
                    continue
                var i: int = n.y * sim.GRID.x + n.x
                if sim.arrival_nav_regions[i] < 0:
                    sim.arrival_nav_regions[i] = label
                    queue.append(n)
        label += 1


static func _occupy(grid: Dictionary, point: Vector2, radius: float) -> void:
    var cell := Vector2i((point / 32.0).floor())
    if not grid.has(cell):
        grid[cell] = []
    grid[cell].append(Vector3(point.x, point.y, radius))


static func _space_free(grid: Dictionary, point: Vector2, radius: float) -> bool:
    var cell := Vector2i((point / 32.0).floor())
    for y in range(-1, 2):
        for x in range(-1, 2):
            for entry: Vector3 in grid.get(cell + Vector2i(x, y), []):
                if point.distance_squared_to(Vector2(entry.x, entry.y)) < pow(radius + entry.z + 2.0, 2):
                    return false
    return true


static func refresh(sim) -> void:
    var groups := {}
    for id: int in sim.units:
        var u: Dictionary = sim.units[id]
        if not u.has("arrival") or u.hp <= 0:
            continue
        # Every unit retries once per second, distributed over the 20 ticks.
        if id % sim.TICK != sim.frame % sim.TICK:
            continue
        if u.order not in ["move", "attack_move", "idle"]:
            u.erase("arrival")
            continue
        if u.arrival.arrived and u.order == "idle":
            continue
        if not sim.position_free(u.target, sim.UNIT_TYPES[u.type].radius):
            u.arrival.waiting = true
        if not u.arrival.waiting:
            continue
        var key := Vector3(u.arrival.anchor.x, u.arrival.anchor.y, u.arrival.region)
        if not groups.has(key):
            groups[key] = []
        groups[key].append(id)
    for key: Vector3 in groups:
        var ids: Array = groups[key]
        ids.sort()
        var allocation := plan(sim, ids, Vector2(key.x, key.y), int(key.z))
        if allocation.has("error"):
            continue
        for id: int in ids:
            var u: Dictionary = sim.units[id]
            var next: Dictionary = allocation.orders[id]
            if u.target != next.target or u.arrival.waiting != next.arrival.waiting:
                u.path = []
                u.repath = 0
            u.target = next.target
            u.arrival = next.arrival


static func displace_free(sim, u: Dictionary, point: Vector2) -> bool:
    if not sim.movement_free(u.pos, point, sim.UNIT_TYPES[u.type].radius):
        return false
    if u.has("arrival") and u.arrival.arrived and u.order == "idle":
        return sim.terrain.arrival_region_at(point) == int(u.arrival.region)
    return true


static func reserved_for_other(sim, u: Dictionary, point: Vector2) -> bool:
    if not u.has("arrival") or not u.arrival.waiting or int(u.attack_id) >= 0:
        return false
    var radius: float = sim.UNIT_TYPES[u.type].radius
    for other: Dictionary in sim.units.values():
        if other == u or other.hp <= 0 or other.owner != u.owner or not other.has("arrival") or other.arrival.waiting:
            continue
        var gap: float = radius + sim.UNIT_TYPES[other.type].radius + 4.0
        if point.distance_squared_to(other.target) < gap * gap:
            return true
    return false
