extends RefCounted
const Rules = preload("res://scripts/definitions/gameplay_rules.gd")
## Host-owned reservations, stable work points and bounded overflow routing.
const CAPACITY := 5
const ZONE := 128.0
const SEARCH := 960.0
const REACH = Rules.MINING_REACH
const Catalog = preload("res://scripts/definitions/entity_catalog.gd")
# Place the shortened claws at the crystal surface, not at the old vehicle reach.
const WORK_DISTANCE := Rules.MINING_CONTACT_RADIUS + 1.8 * Catalog.HARVESTER_MODEL_SCALE
const PHASES := ["wait", "approach", "work", "return"]

static func request(sim, u: Dictionary, ore_id: int, preserve_origin: bool = false) -> void:
    var origin: Vector2 = u.get("mining", {}).get("origin", sim.ores[ore_id].pos) if preserve_origin else sim.ores[ore_id].pos
    u.mining = {"ore": ore_id, "origin": origin, "center": sim.ores[ore_id].pos,
        "phase": "wait", "requested": sim.frame, "target": u.pos, "retry": 0,
        "progress": 0, "best": 1.0e9, "waiting_set": false}
    u.order = "gather"
    u.ore = ore_id
    u.path = []
    u.repath = 0

static func reserved(u: Dictionary) -> bool:
    return u.hp > 0 and u.has("mining") and u.mining.phase in ["approach", "work"] and u.order == "gather" and not u.has("dock") and u.cargo < Rules.CAPACITY

static func ignore_pair(a: Dictionary, b: Dictionary) -> bool:
    # Vehicle overlap is a permanent pair rule, independent of owner or order.
    return a.type == "harvester" and b.type == "harvester"

static func counts(sim, ore_id: int) -> Vector2i:
    var result := Vector2i.ZERO
    for u: Dictionary in sim.units.values():
        if u.hp <= 0 or not u.has("mining") or u.mining.ore != ore_id:
            continue
        if reserved(u):
            result.x += 1
        elif u.order == "gather" and u.mining.phase == "wait" and not u.has("dock"):
            result.y += 1
    return result

static func cancel(sim, u: Dictionary) -> void:
    if not u.has("mining"):
        return
    wake_waiters(sim, u.mining.ore)
    u.erase("mining")

static func wake_waiters(sim, ore_id: int) -> void:
    for waiting: Dictionary in sim.units.values():
        if waiting.has("mining") and waiting.mining.phase == "wait" and waiting.mining.ore == ore_id:
            waiting.mining.retry = 0

static func connector(sim, u: Dictionary, point: Vector2) -> bool:
    var radius: float = sim.UNIT_TYPES.harvester.radius
    if not sim.position_free(point, radius):
        return false
    var start: Vector2i = sim.ArrivalPlanner.goal_cell(sim, u.pos, -1, radius)
    var goal: Vector2i = sim.ArrivalPlanner.goal_cell(sim, point, -1, radius)
    if start.x < 0 or goal.x < 0:
        return false
    var nav: AStarGrid2D = sim.navigation_for(radius)
    return not sim.SweptPaths.path(sim, nav, start, goal, radius, nav.get_point_path(start, goal)).is_empty()

static func work_point(sim, u: Dictionary, ore_id: int) -> Vector2:
    var center: Vector2 = sim.ores[ore_id].pos
    var candidates: Array[Vector2] = []
    # Stable angular samples; selected once, never chase the current radial angle.
    for i in range(32):
        candidates.append(center + Vector2.RIGHT.rotated(TAU * i / 32.0) * WORK_DISTANCE)
    candidates.sort_custom(func(a, b): return (u.pos as Vector2).distance_squared_to(a) < (u.pos as Vector2).distance_squared_to(b))
    for point: Vector2 in candidates:
        if connector(sim, u, point):
            return point
    return Vector2.INF

static func waiting_point(sim, u: Dictionary) -> Vector2:
    var center: Vector2 = u.mining.center
    var points: Array[Vector2] = []
    for ring in range(6, 13, 2):
        for i in range(24):
            var p: Vector2 = sim.WorldGrid.cell_center(center + Vector2.RIGHT.rotated(TAU * i / 24.0) * ring * sim.CELL)
            points.append(p)
    points.sort_custom(func(a, b): return (u.pos as Vector2).distance_squared_to(a) < (u.pos as Vector2).distance_squared_to(b))
    for p: Vector2 in points:
        if not connector(sim, u, p):
            continue
        var clear := true
        for other: Dictionary in sim.units.values():
            if is_same(u, other) or other.hp <= 0 or ignore_pair(u, other):
                continue
            var gap: float = sim.UNIT_TYPES.harvester.radius + sim.UNIT_TYPES[other.type].radius + Catalog.BODY_GAP
            var target: Vector2 = other.get("mining", {}).get("target", other.pos)
            if p.distance_to(other.pos) < gap or (other.get("mining", {}).get("phase", "") == "wait" and p.distance_to(target) < gap):
                clear = false
                break
        if clear:
            return p
    return u.pos

static func assign(sim, u: Dictionary, ore_id: int) -> bool:
    if counts(sim, ore_id).x >= CAPACITY:
        return false
    var point := work_point(sim, u, ore_id)
    if not point.is_finite():
        return false
    var m: Dictionary = u.mining
    m.ore = ore_id
    m.center = sim.ores[ore_id].pos
    m.phase = "approach"
    m.target = point
    m.best = (u.pos as Vector2).distance_to(point)
    m.progress = 0
    m.waiting_set = false
    u.ore = ore_id
    u.path = []
    u.repath = 0
    return true

static func prepare(sim) -> void:
    var pending: Array[int] = []
    for id: int in sim.units:
        var u: Dictionary = sim.units[id]
        if u.type != "harvester" or u.hp <= 0:
            continue
        if u.has("mining"):
            var m: Dictionary = u.mining
            if u.order != "gather":
                cancel(sim, u)
                continue
            if u.has("dock") or sim.DepotDocking.returning(sim, u):
                if m.phase in ["approach", "work"]:
                    wake_waiters(sim, m.ore)
                    m.retry = 0
                m.phase = "return"
                continue
            if m.phase == "return":
                m.phase = "wait"
                m.requested = sim.frame
                m.retry = 0
            if m.phase in ["approach", "work"]:
                if not sim.ores.has(int(m.ore)) or sim.ores[m.ore].amount <= 0:
                    m.phase = "wait"
                    m.retry = 0
                else:
                    continue
        if u.order != "gather" or u.has("dock") or sim.DepotDocking.returning(sim, u):
            continue
        if not u.has("mining"):
            if not sim.ores.has(int(u.ore)):
                continue
            request(sim, u, int(u.ore))
        pending.append(id)
    pending.sort_custom(func(a, b):
        var aa: int = sim.units[a].mining.requested
        var bb: int = sim.units[b].mining.requested
        return a < b if aa == bb else aa < bb)
    for id: int in pending:
        var u: Dictionary = sim.units[id]
        var m: Dictionary = u.mining
        if sim.frame < m.retry:
            continue
        m.retry = sim.frame + sim.TICK
        var primary: Dictionary = sim.ores.get(int(u.ore), {})
        if not primary.is_empty() and primary.amount > 0 and sim.can_see(u.owner, primary.pos) and assign(sim, u, int(u.ore)):
            continue
        var alternatives: Array[int] = []
        for ore_id: int in sim.ores:
            var ore: Dictionary = sim.ores[ore_id]
            if ore_id != u.ore and ore.amount > 0 and (ore.pos as Vector2).distance_squared_to(m.origin) < SEARCH * SEARCH and sim.can_see(u.owner, ore.pos) and counts(sim, ore_id).x < CAPACITY:
                alternatives.append(ore_id)
        alternatives.sort_custom(func(a, b):
            var da: float = (sim.ores[a].pos as Vector2).distance_squared_to(m.origin)
            var db: float = (sim.ores[b].pos as Vector2).distance_squared_to(m.origin)
            return a < b if is_equal_approx(da, db) else da < db)
        var assigned := false
        for ore_id: int in alternatives:
            if assign(sim, u, ore_id):
                assigned = true
                break
        if not assigned and (not m.waiting_set or not sim.position_free(m.target, sim.UNIT_TYPES[u.type].radius)):
            m.target = waiting_point(sim, u)
            m.waiting_set = true

static func advance(sim, u: Dictionary) -> void:
    if not u.has("mining"):
        return
    var m: Dictionary = u.mining
    if m.phase == "wait":
        sim.move_towards(u, m.target, 2.0)
        return
    var distance: float = (u.pos as Vector2).distance_to(m.target)
    if distance <= 4.0 and sim.position_free(u.pos, sim.UNIT_TYPES[u.type].radius):
        m.phase = "work"
        var ore: Dictionary = sim.ores.get(int(u.ore), {})
        if ore.is_empty() or ore.amount <= 0:
            return
        sim.MovementSystem.turn_harvester(u, (ore.pos as Vector2) - (u.pos as Vector2))
        u.work += 1
        if u.work >= Rules.MINING_INTERVAL:
            var amount := mini(Rules.MINING_AMOUNT, mini(int(ore.amount), Rules.CAPACITY - int(u.cargo)))
            ore.amount -= amount
            u.cargo += amount
            u.work = 0
            if sim.DepotDocking.returning(sim, u):
                m.phase = "return"
                m.retry = 0
                wake_waiters(sim, m.ore)
        return
    m.phase = "approach"
    sim.move_towards(u, m.target, 2.0)
    if distance < float(m.best) - 1.0:
        m.best = distance
        m.progress = 0
    else:
        m.progress += 1
    if m.progress >= 2 * sim.TICK:
        var point := work_point(sim, u, int(u.ore))
        if point.is_finite():
            m.target = point
        else:
            # Preserve the original overflow anchor when the work point is blocked.
            m.phase = "wait"
            m.retry = sim.frame + sim.TICK
            m.waiting_set = false
            u.path = []
            return
        m.best = (u.pos as Vector2).distance_to(m.target)
        m.progress = 0
        u.path = []
        u.repath = 0

static func validate(sim, state: Dictionary) -> bool:
    var totals: Dictionary = {}
    for u: Dictionary in state.units.values():
        if not u.has("mining"):
            continue
        if u.type != "harvester" or not u.mining is Dictionary:
            return false
        var m: Dictionary = u.mining
        for field in ["ore", "requested", "retry", "progress"]:
            if typeof(m.get(field)) != TYPE_INT or m[field] < 0:
                return false
        if m.requested > state.frame or not m.get("phase") in PHASES or m.has("ghost") or typeof(m.get("waiting_set")) != TYPE_BOOL or not m.get("best") is float or not is_finite(m.best):
            return false
        for field in ["origin", "center", "target"]:
            if not sim._validate_vector2(m.get(field), sim.WORLD, "mining " + field):
                return false
        if m.phase in ["approach", "work"]:
            if u.order != "gather" or u.has("dock") or u.ore != m.ore or not state.ores.has(m.ore) or m.center != state.ores[m.ore].pos or (m.target as Vector2).distance_to(m.center) > REACH:
                return false
            if (m.center as Vector2).distance_squared_to(m.origin) >= SEARCH * SEARCH:
                return false
            totals[m.ore] = int(totals.get(m.ore, 0)) + 1
            if totals[m.ore] > CAPACITY:
                return false
    return true
