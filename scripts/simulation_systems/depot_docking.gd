extends RefCounted
const Rules = preload("res://scripts/definitions/gameplay_rules.gd")
## Shared unloading pad; each vehicle owns only its route and cargo settlement.
const Catalog = preload("res://scripts/definitions/entity_catalog.gd")
const SOLIDS := Catalog.REFINERY_SOLID_RECTS
const RADIUS := Catalog.UNIT_TYPES.harvester.radius
const CONTACT_EPSILON := 0.002


static func blocked(local: Vector2, radius: float) -> bool:
    for rect: Rect2 in SOLIDS:
        # Touching an edge is legal; positive overlap remains blocked. This lets
        # a two-cell circle dock in a two-cell pad without shrinking its body.
        var expanded := rect.grow(radius)
        if local.x > expanded.position.x + CONTACT_EPSILON and local.x < expanded.end.x - CONTACT_EPSILON and local.y > expanded.position.y + CONTACT_EPSILON and local.y < expanded.end.y - CONTACT_EPSILON:
            return true
    return false


static func berth(b: Dictionary, slot: int) -> Vector2:
    return b.pos + Catalog.dock_point(slot, false)


static func entrance(b: Dictionary, slot: int) -> Vector2:
    return b.pos + Catalog.dock_point(slot, true)


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
    var start := sim.ArrivalPlanner.goal_cell(sim, from, -1, RADIUS)
    var goal := sim.ArrivalPlanner.goal_cell(sim, to, -1, RADIUS)
    if start.x < 0 or goal.x < 0:
        return false
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
        for slot in range(Catalog.REFINERY_DOCK_RECTS.size()):
            if lane_available(sim, sim.buildings[id], slot, u) and reachable(sim, u.pos, entrance(sim.buildings[id], slot)):
                return id
    return -1


static func destination(u: Dictionary, point: Vector2) -> void:
    u.dock.target = point
    u.target = point
    u.path = []
    u.repath = 0
    u.erase("arrival")


static func request(sim: Simulation, u: Dictionary, station: int, requested: int) -> void:
    var b: Dictionary = sim.buildings[station]
    u.dock = {"station": station, "slot": 0, "phase": "approach", "requested": requested,
        "target": u.pos, "stalled": 0, "last_pos": u.pos}
    destination(u, entrance(b, 0))


static func lane_available(sim: Simulation, b: Dictionary, slot: int, ignore: Dictionary = {}) -> bool:
    var start := entrance(b, slot)
    var end := berth(b, slot)
    for other: Dictionary in sim.units.values():
        if is_same(other, ignore) or other.hp <= 0 or other.type == "harvester":
            continue
        var gap: float = RADIUS + Simulation.UNIT_TYPES[other.type].radius + Catalog.BODY_GAP
        if Geometry2D.get_closest_point_to_segment(other.pos, start, end).distance_to(other.pos) < gap:
            return false
    return sim.position_free(start, RADIUS) and sim.movement_free(start, end, RADIUS)


static func prepare(sim: Simulation) -> void:
    for b: Dictionary in sim.buildings.values():
        if b.type == "refinery":
            for slot in range(Catalog.REFINERY_DOCK_RECTS.size()):
                b.dock_flash[slot] = maxi(0, b.dock_flash[slot] - 1)
    for id: int in sim.units:
        var u: Dictionary = sim.units[id]
        if u.has("dock") and (u.hp <= 0 or u.order != "gather" or not available(sim, u, u.dock.station)):
            u.erase("dock")
            u.path = []
        if u.hp <= 0 or u.type != "harvester" or u.order != "gather":
            continue
        if not u.has("dock") and returning(sim, u):
            # Stagger unreachable-station retries; avoid path scans every tick.
            if (u.has("mining") and int(u.mining.retry) <= sim.frame) or (not u.has("mining") and (sim.frame + id) % sim.TICK == 0):
                var station := choose_station(sim, u)
                if u.has("mining"):
                    u.mining.retry = sim.frame + Rules.DOCK_RETRY
                if station >= 0:
                    request(sim, u, station, sim.frame)
                elif not u.has("mining") and sim.ores.has(int(u.ore)):
                    sim.MiningSystem.request(sim, u, int(u.ore))
                    u.mining.phase = "return"
                    u.mining.retry = sim.frame + Rules.DOCK_RETRY


static func advance(sim: Simulation, u: Dictionary) -> void:
    if not u.has("dock"):
        return
    var d: Dictionary = u.dock
    if not available(sim, u, d.station):
        u.erase("dock")
        return
    var b: Dictionary = sim.buildings[d.station]
    # Infantry and static obstacles still block a pad; harvesters never do.
    if not lane_available(sim, b, d.slot, u):
        d.stalled += 1
        retry(sim, u)
        return
    var distance: float = (u.pos as Vector2).distance_to(d.target)
    # Exact-fit docking needs tighter alignment than the ordinary arrival radius.
    var tolerance := CONTACT_EPSILON * 0.25
    if distance <= tolerance:
        d.stalled = 0
        if d.phase == "approach":
            d.phase = "enter"
            destination(u, berth(b, d.slot))
        elif d.phase == "enter":
            sim.money[u.owner] += int(u.cargo)
            u.cargo = 0
            b.dock_flash[d.slot] = 10
            u.erase("dock")
            u.path = []
            u.repath = 0
            if u.has("mining"):
                u.mining.retry = 0
        return
    sim.move_towards(u, d.target, tolerance * 0.5)
    d.stalled = int(d.stalled) + 1 if (u.pos as Vector2).distance_to(d.last_pos) < 0.01 else 0
    d.last_pos = u.pos
    retry(sim, u)


static func retry(sim: Simulation, u: Dictionary) -> void:
    var d: Dictionary = u.dock
    if d.stalled >= Rules.DOCK_RETRY:
        # Never teleport or clear cargo. Replan to another reachable station.
        var replacement := choose_station(sim, u, d.station)
        if replacement >= 0:
            request(sim, u, replacement, d.requested)
        else:
            d.stalled = 0
            u.path = []
            u.repath = 0
            d.phase = "approach"
            destination(u, entrance(sim.buildings[d.station], d.slot))


static func valid(sim: Simulation, u: Dictionary) -> bool:
    if not u.has("dock"):
        return true
    var d: Variant = u.dock
    if u.type != "harvester" or u.order != "gather" or not d is Dictionary:
        return false
    for key in ["station", "slot", "requested", "stalled"]:
        if typeof(d.get(key)) != TYPE_INT:
            return false
    if d.station < 0 or d.station > 1000000 or d.slot < 0 or d.slot >= Catalog.REFINERY_DOCK_RECTS.size() or d.requested < 0 or d.stalled < 0 or d.stalled > Rules.DOCK_RETRY:
        return false
    if d.get("phase") not in ["approach", "enter"]:
        return false
    return sim._validate_vector2(d.get("target"), Simulation.WORLD, "dock target") and sim._validate_vector2(d.get("last_pos"), Simulation.WORLD, "dock last position")
