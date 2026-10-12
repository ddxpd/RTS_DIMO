extends RefCounted
const Rules = preload("res://scripts/definitions/gameplay_rules.gd")
## Host-authoritative dock reservations live on units; no second entity store.
const Catalog = preload("res://scripts/definitions/entity_catalog.gd")
const SOLIDS := Catalog.REFINERY_SOLID_RECTS
const RADIUS := 48.0


static func blocked(local: Vector2, radius: float) -> bool:
    for rect: Rect2 in SOLIDS:
        if rect.grow(radius).has_point(local):
            return true
    return false


static func berth(b: Dictionary, slot: int) -> Vector2:
    return b.pos + Vector2(-Rules.DOCK_OFFSET if slot == 0 else Rules.DOCK_OFFSET, Rules.DOCK_DEPTH)


static func entrance(b: Dictionary, slot: int) -> Vector2:
    return b.pos + Vector2(-Rules.DOCK_OFFSET if slot == 0 else Rules.DOCK_OFFSET, Rules.DOCK_ENTRANCE)


static func returning(sim: Simulation, u: Dictionary) -> bool:
    return u.cargo >= Rules.CAPACITY or (u.cargo > 0 and (not sim.ores.has(int(u.ore)) or sim.ores[int(u.ore)].amount <= 0))


static func available(sim: Simulation, u: Dictionary, id: int) -> bool:
    if not sim.buildings.has(id):
        return false
    var b: Dictionary = sim.buildings[id]
    return b.type == "refinery" and b.owner == u.owner and b.hp > 0 and b.remaining == 0


static func reachable(sim: Simulation, from: Vector2, to: Vector2) -> bool:
    if not sim.position_free(to, RADIUS):
        return false
    var nav: AStarGrid2D = sim.navigation_for(RADIUS)
    var start := sim.nearest_cell(from, RADIUS)
    var goal := sim.nearest_cell(to, RADIUS)
    return sim.movement_free(nav.get_point_position(goal), to, RADIUS) and not nav.get_id_path(start, goal).is_empty()


static func choose_station(sim: Simulation, u: Dictionary, excluded: int = -1) -> int:
    var candidates: Array = []
    for id: int in sim.buildings:
        if id != excluded and available(sim, u, id):
            candidates.append(id)
    candidates.sort_custom(func(a, b):
        var da: float = (sim.buildings[a].pos as Vector2).distance_squared_to(u.pos)
        var db: float = (sim.buildings[b].pos as Vector2).distance_squared_to(u.pos)
        return a < b if is_equal_approx(da, db) else da < db)
    for id: int in candidates:
        for slot in range(2):
            if reachable(sim, u.pos, entrance(sim.buildings[id], slot)) and sim.movement_free(entrance(sim.buildings[id], slot), berth(sim.buildings[id], slot), RADIUS):
                return id
    return -1


static func destination(u: Dictionary, point: Vector2) -> void:
    u.dock.target = point
    u.target = point
    u.path = []
    u.repath = 0
    u.erase("arrival")


static func waiting_point(sim: Simulation, u: Dictionary, station: int) -> Vector2:
    var b: Dictionary = sim.buildings[station]
    var candidates: Array[Vector2] = []
    # Waiting pockets sit beside the station, never on either entrance/exit lane.
    for row in range(8):
        for side in [-1, 1]:
            for column in range(3):
                candidates.append(b.pos + Vector2(side * (256 + column * 112), -224 + row * 112))
    candidates.sort_custom(func(a, c): return a.distance_squared_to(u.pos) < c.distance_squared_to(u.pos))
    for point: Vector2 in candidates:
        if not sim.position_free(point, RADIUS):
            continue
        var clear := true
        for other: Dictionary in sim.units.values():
            if is_same(u, other) or other.hp <= 0:
                continue
            var gap: float = RADIUS + Simulation.UNIT_TYPES[other.type].radius + 8.0
            var reserved: Vector2 = other.dock.target if other.has("dock") else other.pos
            if point.distance_to(other.pos) < gap or point.distance_to(reserved) < gap:
                clear = false
                break
        if clear and reachable(sim, u.pos, point):
            return point
    return u.pos


static func request(sim: Simulation, u: Dictionary, station: int, requested: int) -> void:
    u.dock = {"station": station, "slot": -1, "phase": "wait", "requested": requested,
        "target": u.pos, "stalled": 0, "last_pos": u.pos}
    destination(u, waiting_point(sim, u, station))


static func lane_clear(sim: Simulation, u: Dictionary, b: Dictionary, slot: int) -> bool:
    var start := entrance(b, slot)
    var end := berth(b, slot)
    for other: Dictionary in sim.units.values():
        if is_same(other, u) or other.hp <= 0:
            continue
        if other.has("dock") and other.dock.station == u.dock.station and other.dock.slot == slot:
            return false
        var gap: float = RADIUS + Simulation.UNIT_TYPES[other.type].radius + 4
        if Geometry2D.get_closest_point_to_segment(other.pos, start, end).distance_to(other.pos) < gap:
            return false
    return sim.movement_free(start, end, RADIUS) and reachable(sim, u.pos, start)


static func prepare(sim: Simulation) -> void:
    for b: Dictionary in sim.buildings.values():
        if b.type == "refinery":
            for slot in range(2):
                b.dock_flash[slot] = maxi(0, b.dock_flash[slot] - 1)
    var pending: Array[int] = []
    for id: int in sim.units:
        var u: Dictionary = sim.units[id]
        if u.has("dock") and (u.hp <= 0 or u.order != "gather" or not available(sim, u, u.dock.station)):
            u.erase("dock")
            u.path = []
        if u.hp <= 0 or u.type != "harvester" or u.order != "gather":
            continue
        if u.has("mining") and u.mining.phase == "exit":
            continue
        if not u.has("dock") and returning(sim, u):
            # Stagger unreachable-station retries; avoid path scans every tick.
            if (sim.frame + id) % 20 == 0:
                var station := choose_station(sim, u)
                if station >= 0:
                    request(sim, u, station, sim.frame)
        if u.has("dock") and u.dock.phase == "wait":
            pending.append(id)
    pending.sort_custom(func(a, b):
        var at: int = sim.units[a].dock.requested
        var bt: int = sim.units[b].dock.requested
        return a < b if at == bt else at < bt)
    for id: int in pending:
        var u: Dictionary = sim.units[id]
        var b: Dictionary = sim.buildings[u.dock.station]
        for slot in range(2):
            if lane_clear(sim, u, b, slot):
                u.dock.slot = slot
                u.dock.phase = "approach"
                destination(u, entrance(b, slot))
                break


static func advance(sim: Simulation, u: Dictionary) -> void:
    if not u.has("dock"):
        return
    var d: Dictionary = u.dock
    if not available(sim, u, d.station):
        u.erase("dock")
        return
    var b: Dictionary = sim.buildings[d.station]
    var distance: float = (u.pos as Vector2).distance_to(d.target)
    if distance <= 4.0:
        d.stalled = int(d.stalled) + 1 if d.phase == "wait" else 0
        if d.phase == "wait":
            retry(sim, u)
        elif d.phase == "approach":
            d.phase = "enter"
            destination(u, berth(b, d.slot))
        elif d.phase == "enter":
            sim.money[u.owner] += int(u.cargo)
            u.cargo = 0
            b.dock_flash[d.slot] = 10
            d.phase = "exit"
            destination(u, entrance(b, d.slot))
        elif d.phase == "exit":
            d.phase = "leave"
            destination(u, waiting_point(sim, u, d.station))
        elif d.phase == "leave":
            u.erase("dock")
            u.path = []
        return
    sim.move_towards(u, d.target, 2.0)
    d.stalled = int(d.stalled) + 1 if (u.pos as Vector2).distance_to(d.last_pos) < 0.01 else 0
    d.last_pos = u.pos
    retry(sim, u)


static func retry(sim: Simulation, u: Dictionary) -> void:
    var d: Dictionary = u.dock
    if d.stalled >= Rules.DOCK_RETRY:
        # Never teleport or clear cargo. Replan to another reachable station.
        var replacement := choose_station(sim, u, d.station) if d.phase not in ["exit", "leave"] else -1
        if replacement >= 0:
            request(sim, u, replacement, d.requested)
        else:
            d.stalled = 0
            u.path = []
            u.repath = 0
            if d.phase in ["approach", "enter"]:
                d.phase = "wait"
                d.slot = -1
            if d.phase == "wait":
                destination(u, waiting_point(sim, u, d.station))


static func valid(sim: Simulation, u: Dictionary) -> bool:
    if not u.has("dock"):
        return true
    var d: Variant = u.dock
    if u.type != "harvester" or u.order != "gather" or not d is Dictionary:
        return false
    for key in ["station", "slot", "requested", "stalled"]:
        if typeof(d.get(key)) != TYPE_INT:
            return false
    if d.station < 0 or d.station > 1000000 or d.slot not in [-1, 0, 1] or d.requested < 0 or d.stalled < 0 or d.stalled > Rules.DOCK_RETRY:
        return false
    if d.get("phase") not in ["wait", "approach", "enter", "exit", "leave"] or (d.phase == "wait") != (d.slot == -1):
        return false
    return sim._validate_vector2(d.get("target"), Simulation.WORLD, "dock target") and sim._validate_vector2(d.get("last_pos"), Simulation.WORLD, "dock last position")
