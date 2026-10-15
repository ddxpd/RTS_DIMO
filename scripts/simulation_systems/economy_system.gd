extends RefCounted
const Rules = preload("res://scripts/definitions/gameplay_rules.gd")
## Synchronous rules; Simulation owns state, caches and tick order.


static func _job_stats(sim: Simulation, kind: String) -> Dictionary:
    return Simulation.UNIT_TYPES[kind] if Simulation.UNIT_TYPES.has(kind) else Simulation.BUILD_TYPES[kind]


static func _auto_mine(sim: Simulation, u: Dictionary) -> void:
    var best := -1
    var best_distance := INF
    for id: int in sim.ores:
        var ore: Dictionary = sim.ores[id]
        if ore.amount <= 0 or not sim.can_see(int(u.owner), ore.pos):
            continue
        var distance: float = (u.pos as Vector2).distance_to(ore.pos)
        if distance < best_distance:
            best_distance = distance
            best = id
    if best >= 0:
        Simulation.MiningSystem.request(sim, u, best)


static func snap_build(sim: Simulation, pos: Vector2) -> Vector2:
    return (pos / Simulation.CELL).round() * Simulation.CELL


static func build_error(sim: Simulation, owner: int, kind: String, position: Vector2) -> String:
    if not Simulation.BUILD_TYPES.has(kind) or owner not in (sim.players if not sim.match_config.is_empty() else [1, 2, 3, 4]):
        return "Invalid building"
    var pos: Vector2 = sim.snap_building(kind, position)
    var rects := sim.placement_rects(kind, pos)
    for rect: Rect2 in rects:
        if not Rect2(Vector2.ZERO, Simulation.WORLD).encloses(rect):
            return "Outside map"
        var ground_error: String = sim.terrain.build_error(rect.grow(16))
        if not ground_error.is_empty():
            return ground_error
    if int(sim.money[owner]) < int(Simulation.BUILD_TYPES[kind].cost):
        return "Not enough credits"
    var nearby := false
    for b: Dictionary in sim.buildings.values():
        if Simulation.BarracksFlight.blocks_ground(b):
            for occupied: Rect2 in sim.placement_rects(b.type, b.pos):
                for rect: Rect2 in rects:
                    if occupied.intersects(rect):
                        return "Building footprint occupied"
        if b.owner == owner and b.remaining == 0 and Simulation.BarracksFlight.state(b) == "grounded" and pos.distance_to(b.pos) < Rules.BUILD_REACH:
            nearby = true
    if not nearby:
        return "Build within %d px of a completed friendly building" % Rules.BUILD_REACH
    for rect: Rect2 in rects:
        for rock: Rect2 in sim.obstacles:
            if rock.grow(16).intersects(rect.grow(16)):
                return "Blocked by terrain"
        for ore: Dictionary in sim.ores.values():
            if rect.grow(48).has_point(ore.pos):
                return "Blocked by ore"
        for u: Dictionary in sim.units.values():
            if rect.grow(Simulation.UNIT_TYPES[u.type].radius).has_point(u.pos):
                return "Blocked by a unit"
    return ""


static func _gather(sim: Simulation, u: Dictionary) -> void:
    if u.has("dock") or Simulation.DepotDocking.returning(sim, u):
        Simulation.DepotDocking.advance(sim, u)
        return
    if not u.has("mining") and not sim.ores.has(int(u.ore)):
        u.order = "idle"
        return
    Simulation.MiningSystem.advance(sim, u)


static func _spawn_position(sim: Simulation, b: Dictionary, kind: String = "mobile_infantry") -> Vector2:
    var radius: float = Simulation.UNIT_TYPES[kind].radius
    var catalog = Simulation.EntityCatalog
    var size: Vector2 = Simulation.BUILD_TYPES[b.type].size
    if b.type == "refinery":
        if not catalog.dock_fit(radius, size):
            push_error("Production unit does not fit unloading lanes")
            return Vector2.ZERO
        for slot in range(catalog.REFINERY_DOCK_RECTS.size()):
            var point: Vector2 = b.pos + catalog.dock_point(slot, true, radius, size)
            if Simulation.DepotDocking.lane_available(sim, b, slot) and spawn_clear(sim, b, point, radius, kind):
                return point
        return Vector2.ZERO
    if b.type == "barracks":
        for lane in [0, -1, 1, -2, 2]:
            var x: float = size.x * catalog.BARRACKS_DOOR_X_FRACTION + lane * (radius * 2 + catalog.BODY_GAP)
            if absf(x) + radius > size.x * 0.5:
                continue
            var front: Vector2 = b.pos + Vector2(x, -size.y * 0.5 - radius - catalog.BODY_GAP)
            if spawn_clear(sim, b, front, radius, kind):
                return front
        return Vector2.ZERO
    # Fallback uses the building boundary rather than a fixed world-space ring.
    for ring in range(5):
        for i in range(16):
            var direction := Vector2.from_angle(float(i) / 16 * TAU)
            var distance := 1.0 / maxf(absf(direction.x) / (size.x * 0.5), absf(direction.y) / (size.y * 0.5))
            var p: Vector2 = b.pos + direction * (distance + radius + catalog.BODY_GAP + ring * (radius * 2 + catalog.BODY_GAP))
            if spawn_clear(sim, b, p, radius, kind):
                return p
    return Vector2.ZERO


static func spawn_clear(sim: Simulation, building: Dictionary, point: Vector2, radius: float, kind: String = "mobile_infantry") -> bool:
    if not sim.position_free(point, radius) or absf(sim.terrain.height_at(point) - sim.terrain.height_at(building.pos)) > 0.1:
        return false
    for unit: Dictionary in sim.units.values():
        if Simulation.MiningSystem.ignore_pair({"type": kind}, unit):
            continue
        if unit.hp > 0 and (unit.pos as Vector2).distance_to(point) < radius + Simulation.UNIT_TYPES[unit.type].radius + Simulation.EntityCatalog.BODY_GAP:
            return false
    return true


static func command(sim: Simulation, owner: int, c: Dictionary) -> String:
    var action: String = str(c.get("action", ""))
    if action == "build":
        if not c.get("pos") is Vector2:
            return "Invalid position"
        var kind: String = str(c.get("type", ""))
        var pos: Vector2 = c.pos
        if not pos.is_finite():
            return "Invalid position"
        var error: String = sim.build_error(owner, kind, pos)
        if not error.is_empty():
            return error
        sim.money[owner] -= Simulation.BUILD_TYPES[kind].cost
        sim._add_building(owner, kind, sim.snap_building(kind, pos), false)
        sim.rebuild_navigation()
        return ""
    if action in ["produce", "cancel_production"]:
        var id: int = int(c.get("building", -1))
        if not sim.buildings.has(id) or sim.buildings[id].owner != owner or sim.buildings[id].remaining > 0:
            return "Select a completed friendly building"
        var b: Dictionary = sim.buildings[id]
        if action == "cancel_production":
            if not b.queue.is_empty():
                var removed: Dictionary = b.queue.pop_back()
                sim.money[owner] += sim._job_stats(str(removed.type)).cost
            return ""
        var kind: String = str(c.get("type", ""))
        if not Simulation.UNIT_TYPES.has(kind):
            return "Wrong production building"
        if kind not in Simulation.ACTIVE_UNIT_TYPES:
            return "This unit is currently unavailable"
        if Simulation.BarracksFlight.state(b) != "grounded":
            return "Land before training units"
        if Simulation.EntityCatalog.PRODUCERS.get(kind) != b.type:
            return "Wrong production building"
        if b.queue.size() >= Rules.QUEUE_LIMIT:
            return "Queue full (%d)" % Rules.QUEUE_LIMIT
        var job_stats: Dictionary = sim._job_stats(kind)
        if sim.money[owner] < job_stats.cost:
            return "Not enough credits"
        sim.money[owner] -= job_stats.cost
        b.queue.append({"type": kind, "remaining": job_stats.time})
        return ""
    if action == "set_rally":
        return Simulation.RallySystem.command(sim, owner, c)
    return "Unknown order"


static func advance_production(sim: Simulation, b: Dictionary) -> void:
    var job: Dictionary = b.queue[0]
    if job.type not in Simulation.ACTIVE_UNIT_TYPES:
        sim.money[b.owner] += Simulation.UNIT_TYPES[job.type].cost
        b.queue.pop_front()
        return
    job.remaining = maxi(0, int(job.remaining) - 1)
    if job.remaining == 0:
        var spawn: Vector2 = sim._spawn_position(b, str(job.type))
        if spawn != Vector2.ZERO:
            var produced: int = sim.add_unit(int(b.owner), str(job.type), spawn)
            Simulation.RallySystem.dispatch(sim, b, produced)
            b.queue.pop_front()


static func construction_health(max_hp: int, total: int, remaining: int) -> int:
    if total <= 0:
        return max_hp
    # Cumulative integer entitlement avoids per-tick rounding loss.
    @warning_ignore("integer_division")
    var initial: int = (max_hp + 9) / 10
    var elapsed := clampi(total - remaining, 0, total)
    @warning_ignore("integer_division")
    return initial + (max_hp - initial) * elapsed / total


static func advance_construction(_sim: Simulation, b: Dictionary) -> void:
    if b.hp <= 0 or b.remaining <= 0:
        return
    var stats: Dictionary = Simulation.BUILD_TYPES[b.type]
    var before := construction_health(int(stats.hp), int(stats.time), int(b.remaining))
    b.remaining = maxi(0, int(b.remaining) - 1)
    var after := construction_health(int(stats.hp), int(stats.time), int(b.remaining))
    # Add only this tick's construction contribution; never heal past damage.
    b.hp = mini(int(stats.hp), int(b.hp) + after - before)


static func refund_destroyed_building(sim: Simulation, b: Dictionary) -> void:
    for job: Dictionary in b.queue:
        sim.money[b.owner] += Simulation.UNIT_TYPES[job.type].cost
