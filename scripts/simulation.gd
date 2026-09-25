extends RefCounted
# The host is the only writer. Clients display snapshots; they never simulate damage.
const VERSION := "rts-economy-2"
const TICK := 20
const CELL := 32
const WORLD := Vector2(4800, 3200)
const GRID := Vector2i(150, 100)
const GRID_CELLS := GRID.x * GRID.y
const MAX_SNAPSHOT_UNITS := 4096
const MAX_SNAPSHOT_BUILDINGS := 1024
const MAX_SNAPSHOT_ORES := 256
const MAX_SNAPSHOT_EFFECTS := 4096
const MAX_SNAPSHOT_ORE_AMOUNT := 100000
const UNIT_TYPES := {
    "soldier": {"hp": 100, "speed": 100.0, "range": 125.0, "damage": 16, "cooldown": 12, "radius": 11.0, "cost": 100, "time": 50},
    "harvester": {"hp": 160, "speed": 75.0, "range": 0.0, "damage": 0, "cooldown": 20, "radius": 14.0, "cost": 200, "time": 70}
}
const BUILD_TYPES := {
    "base": {"hp": 800, "size": Vector2(96, 96), "cost": 500, "time": 140},
    "barracks": {"hp": 420, "size": Vector2(64, 64), "cost": 250, "time": 80},
    "refinery": {"hp": 600, "size": Vector2(80, 80), "cost": 400, "time": 100},
    "bunker": {"hp": 500, "size": Vector2(64, 64), "cost": 300, "time": 120, "range": 190.0, "damage": 14, "cooldown": 14}
}
var units: Dictionary = {}
var buildings: Dictionary = {}
var ores: Dictionary = {}
var money: Dictionary = {1: 600, 2: 600}
var frame := 0
var match_id := 0
var winner := 0
var next_id := 1
var ai_enabled := false
var effects: Array = []
var obstacles: Array[Rect2] = []
var visible: Dictionary = {}
var explored: Dictionary = {}
var nav := AStarGrid2D.new()
var last_snapshot_error := ""

func reset(with_ai: bool = false) -> void:
    match_id += 1
    units.clear()
    buildings.clear()
    ores.clear()
    money      = {1: 6000, 2: 6000}
    frame      = 0
    winner     = 0
    next_id    = 1
    ai_enabled = with_ai
    effects.clear()
    for owner in [1, 2]:
        var cells := PackedByteArray()
        cells.resize(GRID_CELLS)
        cells.fill(0)
        visible[owner] = cells.duplicate()
        explored[owner] = cells.duplicate()
    obstacles = [Rect2(2112, 192, 384, 576), Rect2(2208, 2016, 384, 672), Rect2(2976, 1248, 288, 288), Rect2(1344, 1344, 288, 288)]
    _add_building(1, "base", Vector2(384, 384), true)
    _add_building(2, "base", Vector2(4416, 2816), true)
    add_unit(1, "soldier", Vector2(640, 256))
    add_unit(1, "soldier", Vector2(640, 320))
    add_unit(1, "soldier", Vector2(640, 384))
    add_unit(1, "soldier", Vector2(640, 448))
    add_unit(1, "soldier", Vector2(640, 512))
    add_unit(1, "soldier", Vector2(640, 576))
    add_unit(2, "soldier", Vector2(4160, 2944))
    add_unit(2, "soldier", Vector2(4160, 2880))
    add_unit(2, "soldier", Vector2(4160, 2816))
    add_unit(2, "soldier", Vector2(4160, 2752))
    add_unit(2, "soldier", Vector2(4160, 2688))
    add_unit(2, "soldier", Vector2(4160, 2624))
    ores = {
        1: {"pos": Vector2(704, 704), "amount": 4000}, 2: {"pos": Vector2(4096, 2496), "amount": 4000},
        3: {"pos": Vector2(2400, 1600), "amount": 6000},
        4: {"pos": Vector2(704, 1600), "amount": 5000}, 5: {"pos": Vector2(4096, 1600), "amount": 5000},
        6: {"pos": Vector2(1600, 500), "amount": 6000}, 7: {"pos": Vector2(3200, 2700), "amount": 6000},
        8: {"pos": Vector2(3800, 700), "amount": 7000}, 9: {"pos": Vector2(1000, 2500), "amount": 7000}
    }
    rebuild_navigation()
    update_visibility()

func update_visibility() -> void:
    for owner in [1, 2]:
        var cells: PackedByteArray = visible[owner]
        cells.fill(0)
        for collection: Dictionary in [units, buildings]:
            for entity: Dictionary in collection.values():
                if entity.owner != owner or entity.hp <= 0:
                    continue
                var center: Vector2 = entity.pos
                for x in range(maxi(0, int(center.x / CELL) - 11), mini(GRID.x, int(center.x / CELL) + 12)):
                    for y in range(maxi(0, int(center.y / CELL) - 11), mini(GRID.y, int(center.y / CELL) + 12)):
                        if center.distance_to(Vector2(x * CELL + 16, y * CELL + 16)) <= 340:
                            cells[y * GRID.x + x] = 1
        visible[owner] = cells
        var known: PackedByteArray = explored[owner]
        for i in range(GRID_CELLS):
            if cells[i] == 1:
                known[i] = 1
        explored[owner] = known

func can_see(owner: int, pos: Vector2) -> bool:
    if owner == 0:
        return true
    var cell := Vector2i((pos / CELL).floor()).clamp(Vector2i.ZERO, Vector2i(GRID.x - 1, GRID.y - 1))
    return visible.has(owner) and visible[owner][cell.y * GRID.x + cell.x] == 1

func allocate() -> int:
    var result := next_id
    next_id += 1
    return result

func add_unit(owner: int, kind: String, pos: Vector2) -> int:
    var id := allocate()
    var stats: Dictionary = UNIT_TYPES[kind]
    units[id] = {"owner": owner, "type": kind, "pos": pos, "hp": stats.hp, "order": "idle", "target": Vector2.ZERO,
        "attack_kind": "", "attack_id": -1, "ore": -1, "cargo": 0, "cooldown": 0, "work": 0, "path": [], "repath": 0, "flash": 0, "auto": true, "stuck": 0}
    return id

func _add_building(owner: int, kind: String, pos: Vector2, complete: bool) -> int:
    var id := allocate()
    var stats: Dictionary = BUILD_TYPES[kind]
    buildings[id] = {"owner": owner, "type": kind, "pos": pos, "hp": stats.hp,
        "remaining": 0 if complete else stats.time, "queue": [], "flash": 0, "rally": Vector2.ZERO, "cooldown": 0}
    return id

func footprint(b: Dictionary, margin: float = 0.0) -> Rect2:
    var size: Vector2 = BUILD_TYPES[b.type].size
    return Rect2(b.pos - size / 2.0, size).grow(margin)

# Production jobs now cover unit kinds only; bunkers are placed directly.
func _job_stats(kind: String) -> Dictionary:
    return UNIT_TYPES[kind] if UNIT_TYPES.has(kind) else BUILD_TYPES[kind]

# Nearest visible enemy unit inside bunker range.
func _bunker_target(b: Dictionary) -> Dictionary:
    var best: Dictionary = {}
    var best_distance := BUILD_TYPES.bunker.range
    for id: int in units:
        var u: Dictionary = units[id]
        if u.owner == b.owner or u.hp <= 0 or not can_see(int(b.owner), u.pos):
            continue
        var distance: float = (b.pos as Vector2).distance_to(u.pos)
        if distance <= best_distance:
            best = u
            best_distance = distance
    return best

# Send an automated miner to the nearest visible ore patch.
func _auto_mine(u: Dictionary) -> void:
    var best := -1
    var best_distance := INF
    for id: int in ores:
        var ore: Dictionary = ores[id]
        if ore.amount <= 0 or not can_see(int(u.owner), ore.pos):
            continue
        var distance: float = (u.pos as Vector2).distance_to(ore.pos)
        if distance < best_distance:
            best_distance = distance
            best = id
    if best >= 0:
        u.order = "gather"
        u.ore = best
        u.path = []

func snap_build(pos: Vector2) -> Vector2:
    return (pos / CELL).round() * CELL

func build_error(owner: int, kind: String, position: Vector2) -> String:
    if not BUILD_TYPES.has(kind) or owner not in [1, 2]:
        return "Invalid building"
    var pos := snap_build(position)
    var rect := Rect2(pos - BUILD_TYPES[kind].size / 2, BUILD_TYPES[kind].size).grow(16)
    if not Rect2(Vector2.ZERO, WORLD).encloses(rect):
        return "Outside map"
    if int(money[owner]) < int(BUILD_TYPES[kind].cost):
        return "Not enough credits"
    var nearby := false
    for b: Dictionary in buildings.values():
        if footprint(b, 16).intersects(rect):
            return "Buildings need more space"
        if b.owner == owner and b.remaining == 0 and pos.distance_to(b.pos) < 360:
            nearby = true
    if not nearby:
        return "Build within 360 px of a completed friendly building"
    for rock: Rect2 in obstacles:
        if rock.grow(16).intersects(rect):
            return "Blocked by terrain"
    for ore: Dictionary in ores.values():
        if rect.grow(32).has_point(ore.pos):
            return "Blocked by ore"
    for u: Dictionary in units.values():
        if rect.has_point(u.pos):
            return "Blocked by a unit"
    return ""

func command(owner: int, c: Dictionary) -> String:
    if winner != 0:
        return "Match has ended"
    if owner not in [1, 2]:
        return "Spectators cannot issue orders"
    var action: String = str(c.get("action", ""))
    if action == "build":
        if not c.get("pos") is Vector2:
            return "Invalid position"
        var kind: String = str(c.get("type", ""))
        var pos: Vector2 = c.pos
        if not pos.is_finite():
            return "Invalid position"
        var error := build_error(owner, kind, pos)
        if not error.is_empty():
            return error
        money[owner] -= BUILD_TYPES[kind].cost
        _add_building(owner, kind, snap_build(pos), false)
        rebuild_navigation()
        return ""
    if action in ["produce", "cancel_production"]:
        var id: int = int(c.get("building", -1))
        if not buildings.has(id) or buildings[id].owner != owner or buildings[id].remaining > 0:
            return "Select a completed friendly building"
        var b: Dictionary = buildings[id]
        if action == "cancel_production":
            if not b.queue.is_empty():
                var removed: Dictionary = b.queue.pop_back()
                money[owner] += _job_stats(str(removed.type)).cost
            return ""
        var kind: String = str(c.get("type", ""))
        if not UNIT_TYPES.has(kind):
            return "Wrong production building"
        if kind == "soldier" and b.type != "barracks":
            return "Wrong production building"
        if kind == "harvester" and b.type != "refinery":
            return "Wrong production building"
        if b.queue.size() >= 5:
            return "Queue full (5)"
        var job_stats: Dictionary = _job_stats(kind)
        if money[owner] < job_stats.cost:
            return "Not enough credits"
        money[owner] -= job_stats.cost
        b.queue.append({"type": kind, "remaining": job_stats.time})
        return ""
    if action == "set_rally":
        var rally_id: int = int(c.get("building", -1))
        if not buildings.has(rally_id) or buildings[rally_id].owner != owner:
            return "Select a friendly building"
        if not c.get("pos") is Vector2 or not (c.pos as Vector2).is_finite():
            return "Invalid rally point"
        buildings[rally_id].rally = snap_build(c.pos)
        return ""
    if action not in ["move", "attack", "attack_move", "gather", "stop"]:
        return "Unknown order"
    var requested: Variant = c.get("units", [])
    if not requested is Array or requested.size() > 200:
        return "Invalid unit list"
    if action in ["move", "attack_move"] and (not c.get("pos") is Vector2 or not (c.pos as Vector2).is_finite()):
        return "Invalid destination"
    if action == "attack":
        var collection: Dictionary = units if c.get("kind") == "unit" else buildings
        var target_id: int = int(c.get("target", -1))
        if not collection.has(target_id) or (collection[target_id].owner == owner and not bool(c.get("force", false))):
            return "Invalid enemy"
    if action == "gather" and not ores.has(int(c.get("target", -1))):
        return "Invalid ore field"
    var accepted := 0
    for value: Variant in requested:
        if not (value is int or value is float):
            continue
        var id := int(value)
        if not units.has(id) or units[id].owner != owner:
            continue
        var u: Dictionary = units[id]
        if action == "attack" and u.type != "soldier":
            continue
        if action == "gather" and u.type != "harvester":
            continue
        u.order     = action if action != "stop" else "idle"
        u.path      = []
        u.repath    = 0
        u.attack_id = -1
        # Miners auto-seek the nearest visible ore unless explicitly stopped.
        u.auto = action != "stop"
        if action == "move":
            var index := accepted
            var offset := Vector2((index % 4) * 30, (index / 4) * 30) if requested.size() > 1 else Vector2.ZERO
            var destination: Vector2 = (c.pos + offset).clamp(Vector2(18, 18), WORLD - Vector2(18, 18))
            # Formation offsets can land on terrain; slide them toward the
            # clicked point until the destination is actually reachable.
            for i in range(24):
                if position_free(destination, UNIT_TYPES[u.type].radius):
                    break
                destination = destination.move_toward(u.pos, 8.0)
            u.target = destination
        elif action == "attack":
            u.attack_kind = str(c.kind)
            u.attack_id = int(c.target)
        elif action == "attack_move":
            u.target = (c.pos as Vector2).clamp(Vector2(18, 18), WORLD - Vector2(18, 18))
        elif action == "gather":
            u.ore = int(c.target)
        accepted += 1
    return "" if accepted > 0 else "No compatible friendly units selected"

func rebuild_navigation() -> void:
    nav.region        = Rect2i(0, 0, int(WORLD.x / CELL), int(WORLD.y / CELL))
    nav.cell_size     = Vector2(CELL, CELL)
    nav.offset        = Vector2(CELL / 2, CELL / 2)
    nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
    nav.update()
    for x in range(nav.region.size.x):
        for y in range(nav.region.size.y):
            var point := Vector2(x * CELL + 16, y * CELL + 16)
            nav.set_point_solid(Vector2i(x, y), not position_free(point, 15))
    for u: Dictionary in units.values():
        u.path = []
        u.repath = 0

func position_free(pos: Vector2, radius: float) -> bool:
    if not Rect2(Vector2(radius, radius), WORLD - Vector2.ONE * radius * 2).has_point(pos):
        return false
    for rock: Rect2 in obstacles:
        if rock.grow(radius).has_point(pos):
            return false
    for b: Dictionary in buildings.values():
        if footprint(b, radius).has_point(pos):
            return false
    return true

func nearest_cell(pos: Vector2) -> Vector2i:
    var base := Vector2i((pos / CELL).floor())
    base = base.clamp(Vector2i.ZERO, nav.region.size - Vector2i.ONE)
    if not nav.is_point_solid(base):
        return base
    for radius in range(1, 12):
        for x in range(-radius, radius + 1):
            for y in range(-radius, radius + 1):
                var p := base + Vector2i(x, y)
                if nav.is_in_boundsv(p) and not nav.is_point_solid(p):
                    return p
    return base

func move_towards(u: Dictionary, destination: Vector2, stop_distance: float = 4.0) -> void:
    if (u.pos as Vector2).distance_to(destination) <= stop_distance:
        return
    u.repath = int(u.repath) - 1
    if u.path.is_empty() or u.repath <= 0:
        var start := nearest_cell(u.pos)
        var goal := nearest_cell(destination)
        u.path = Array(nav.get_point_path(start, goal))
        if not u.path.is_empty():
            u.path.pop_front()
        if position_free(destination, UNIT_TYPES[u.type].radius):
            u.path.append(destination)
        u.repath = 20 + absi(hash(str(destination.x) + "_" + str(destination.y))) % 20
    if u.path.is_empty():
        # Final approach: same nav cell as the goal but the exact point is
        # still away — walk straight to it while terrain allows, instead of
        # freezing one cell short forever.
        if (u.pos as Vector2).distance_to(destination) > stop_distance and position_free(destination, UNIT_TYPES[u.type].radius):
            var direct: Vector2 = (u.pos as Vector2).move_toward(destination, UNIT_TYPES[u.type].speed / TICK)
            if position_free(direct, UNIT_TYPES[u.type].radius):
                u.pos = direct
        return
    var waypoint: Vector2 = u.path[0]
    var next: Vector2 = (u.pos as Vector2).move_toward(waypoint, UNIT_TYPES[u.type].speed / TICK)
    if _unit_blocks(u, next) and position_free(next, UNIT_TYPES[u.type].radius):
        # Oncoming traffic: steer to our right so opposing flows form lanes.
        var heading: Vector2 = (waypoint - (u.pos as Vector2)).normalized()
        var lane: Vector2 = (u.pos as Vector2) + heading.rotated(PI / 4.0) * (UNIT_TYPES[u.type].speed / TICK)
        if position_free(lane, UNIT_TYPES[u.type].radius):
            u.pos = lane
        else:
            u.path.pop_front()
    elif position_free(next, UNIT_TYPES[u.type].radius):
        u.pos = next
    else:
        # Blocked (a corner clip or an oncoming unit): escalate sidesteps
        # from diagonal to perpendicular before giving up on the waypoint.
        var heading: Vector2 = (waypoint - (u.pos as Vector2)).normalized()
        var step_length: float = UNIT_TYPES[u.type].speed / TICK
        var radius: float = UNIT_TYPES[u.type].radius
        var sidesteps := [
            (u.pos as Vector2) + heading.rotated(PI / 4.0) * step_length,
            (u.pos as Vector2) + heading.rotated(-PI / 4.0) * step_length,
            (u.pos as Vector2) + heading.rotated(PI / 2.0) * step_length,
            (u.pos as Vector2) + heading.rotated(-PI / 2.0) * step_length
        ]
        var escaped := false
        for sidestep: Vector2 in sidesteps:
            if position_free(sidestep, radius):
                u.pos = sidestep
                escaped = true
                break
        if not escaped:
            u.path.pop_front()
    if next.distance_to(waypoint) < maxf(2.0, UNIT_TYPES[u.type].radius * 0.4) and not u.path.is_empty():
        u.path.pop_front()

func _closest_enemy(u: Dictionary) -> Array:
    var result: Array = []
    var distance := 190.0
    for kind: String in ["unit", "building"]:
        var collection: Dictionary = units if kind == "unit" else buildings
        for id: int in collection:
            var e: Dictionary = collection[id]
            var d: float = (u.pos as Vector2).distance_to(e.pos)
            if e.owner != u.owner and d < distance and e.hp > 0:
                distance = d
                result = [kind, id]
    return result

func _fight(u: Dictionary) -> void:
    var collection: Dictionary = units if u.attack_kind == "unit" else buildings
    if not collection.has(int(u.attack_id)):
        u.attack_id = -1
        u.order = "idle"
        return
    var enemy: Dictionary = collection[int(u.attack_id)]
    var edge: Vector2 = enemy.pos
    if u.attack_kind == "building":
        edge = (u.pos as Vector2).clamp(footprint(enemy).position, footprint(enemy).end)
    var distance: float = (u.pos as Vector2).distance_to(edge)
    if distance > UNIT_TYPES[u.type].range:
        move_towards(u, edge, 70)
    elif u.cooldown <= 0:
        u.cooldown = UNIT_TYPES[u.type].cooldown
        enemy.hp -= UNIT_TYPES[u.type].damage
        enemy.flash = 3
        effects.append({"from": u.pos, "to": edge, "life": 5, "kind": "shot", "owner": u.owner, "frame": frame})

func _gather(u: Dictionary) -> void:
    if u.cargo >= 60 or (u.cargo > 0 and (not ores.has(int(u.ore)) or ores[int(u.ore)].amount <= 0)):
        var closest: Dictionary = {}
        var best := INF
        for b: Dictionary in buildings.values():
            if b.owner == u.owner and b.type == "refinery" and b.remaining == 0:
                var d: float = (u.pos as Vector2).distance_to(b.pos)
                if d < best:
                    best = d
                    closest = b
        if closest.is_empty():
            return
        var edge: Vector2 = (u.pos as Vector2).clamp(footprint(closest).position, footprint(closest).end)
        if (u.pos as Vector2).distance_to(edge) < 44:
            money[u.owner] += int(u.cargo)
            u.cargo = 0
            u.path = []
        else:
            # Approach the outside of the base, rather than a solid footprint cell.
            var approach: Vector2 = edge + ((u.pos as Vector2) - edge).normalized() * 24
            move_towards(u, approach, 4)
        return
    if not ores.has(int(u.ore)) or ores[int(u.ore)].amount <= 0:
        u.order = "idle"
        return
    var ore: Dictionary = ores[int(u.ore)]
    if (u.pos as Vector2).distance_to(ore.pos) > 46:
        move_towards(u, ore.pos, 38)
    else:
        u.work += 1
        if u.work >= 20:
            var amount := mini(10, int(ore.amount))
            ore.amount -= amount
            u.cargo += amount
            u.work = 0

func step() -> void:
    if winner != 0:
        return
    frame += 1
    for e: Dictionary in effects:
        e.life -= 1
    effects = effects.filter(func(e: Dictionary) -> bool: return e.life > 0)
    if ai_enabled and frame % 30 == 0:
        _ai_step()
    for id: int in buildings.keys():
        var b: Dictionary = buildings[id]
        b.flash = maxi(0, int(b.flash) - 1)
        if b.remaining > 0:
            b.remaining -= 1
        elif b.type == "bunker":
            # Bunkers are stationary defensive guns: they auto-fire at visible enemies.
            b.cooldown = maxi(0, int(b.cooldown) - 1)
            if b.cooldown <= 0:
                var target: Dictionary = _bunker_target(b)
                if not target.is_empty():
                    b.cooldown = BUILD_TYPES.bunker.cooldown
                    target.hp -= BUILD_TYPES.bunker.damage
                    target.flash = 3
                    effects.append({"from": b.pos, "to": target.pos, "life": 5, "kind": "shot", "owner": b.owner, "frame": frame})
        elif not b.queue.is_empty():
            var job: Dictionary = b.queue[0]
            job.remaining = maxi(0, int(job.remaining) - 1)
            if job.remaining == 0:
                var spawn := _spawn_position(b)
                if spawn != Vector2.ZERO:
                    var produced := add_unit(int(b.owner), str(job.type), spawn)
                    var new_unit: Dictionary = units[produced]
                    if b.has("rally") and (b.rally as Vector2) != Vector2.ZERO:
                        new_unit.order  = "move"
                        new_unit.target = (b.rally as Vector2).clamp(Vector2(18, 18), WORLD - Vector2(18, 18))
                    elif job.type == "harvester":
                        # Fresh miners head straight for the nearest visible ore.
                        _auto_mine(new_unit)
                    b.queue.pop_front()
    for id: int in units.keys():
        if not units.has(id):
            continue
        var u: Dictionary = units[id]
        if u.hp <= 0:
            continue
        u.flash = maxi(0, int(u.flash) - 1)
        u.cooldown = maxi(0, int(u.cooldown) - 1)
        var pos_before: Vector2 = u.pos
        if u.order == "move":
            move_towards(u, u.target)
            if (u.pos as Vector2).distance_to(u.target) < 5:
                u.order = "idle"
        elif u.order == "attack_move":
            var nearby := _closest_enemy(u)
            if not nearby.is_empty():
                u.attack_kind = nearby[0]
                u.attack_id   = nearby[1]
                u.order       = "attack"
            else:
                move_towards(u, u.target)
                if (u.pos as Vector2).distance_to(u.target) < 5:
                    u.order = "idle"
        elif u.order == "gather":
            _gather(u)
        elif u.order == "attack":
            _fight(u)
        elif u.type == "soldier":
            var target := _closest_enemy(u)
            if not target.is_empty():
                u.attack_kind = target[0]
                u.attack_id   = target[1]
                u.order       = "attack"
        elif u.type == "harvester" and bool(u.get("auto", true)) and frame % 10 == 0:
            # Idle automated miners keep seeking the nearest visible ore.
            _auto_mine(u)
        # Escape hatch: a unit pressed into a corner by its group can stall
        # forever; after ~2s without progress shove it to a nearby free spot.
        if u.order in ["move", "attack_move", "gather"]:
            if (u.pos as Vector2).distance_to(pos_before) < 0.005:
                u.stuck = int(u.stuck) + 1
            else:
                u.stuck = 0
            if int(u.stuck) >= 40:
                _unstick(u)
    _separate_units()
    var removed_building := false
    for kind: String in ["unit", "building"]:
        var collection: Dictionary = units if kind == "unit" else buildings
        for id: int in collection.keys():
            if collection[id].hp <= 0:
                var dead: Dictionary = collection[id]
                effects.append({"from": dead.pos, "to": dead.pos, "life": 10, "kind": "death", "owner": dead.owner, "frame": frame})
                if kind == "building":
                    removed_building = true
                    for job: Dictionary in dead.queue:
                        money[dead.owner] += UNIT_TYPES[job.type].cost
                collection.erase(id)
    if removed_building:
        rebuild_navigation()
    if frame % 4 == 0:
        update_visibility()
    # Victory: a player is eliminated only when every friendly building is gone.
    var has_building := {1: false, 2: false}
    for b: Dictionary in buildings.values():
        if b.owner in [1, 2]:
            has_building[b.owner] = true
    if not has_building[1] and not has_building[2]:
        winner = 3
    elif not has_building[1]:
        winner = 2
    elif not has_building[2]:
        winner = 1

func _spawn_position(b: Dictionary) -> Vector2:
    for ring in range(3, 8):
        for i in range(16):
            var p: Vector2 = b.pos + Vector2.from_angle(float(i) / 16 * TAU) * ring * 24
            var clear := position_free(p, 16)
            for u: Dictionary in units.values():
                if (u.pos as Vector2).distance_to(p) < 34:
                    clear = false
            if clear:
                return p
    return Vector2.ZERO

# Does the proposed position collide with another unit's body?
func _unit_blocks(u: Dictionary, next: Vector2) -> bool:
    for other: Dictionary in units.values():
        if other == u or other.hp <= 0:
            continue
        var clearance: float = UNIT_TYPES[u.type].radius + UNIT_TYPES[other.type].radius - 2.0
        if (other.pos as Vector2).distance_to(next) < clearance:
            return true
    return false

# Shove a wedged unit to the closest free position within a small radius.
func _unstick(u: Dictionary) -> void:
    var radius: float = UNIT_TYPES[u.type].radius
    for ring in range(1, 5):
        for i in range(8):
            var candidate: Vector2 = (u.pos as Vector2) + Vector2.from_angle(TAU * i / 8.0) * ring * 12.0
            if position_free(candidate, radius):
                u.pos = candidate
                u.path = []
                u.repath = 0
                u.stuck = 0
                return
    u.stuck = 0

func _separate_units() -> void:
    # Spatial-hash unit separation keeps dense armies from becoming an O(N^2)
    # scan every iteration. The maximum combined radius is below one cell.
    var cell_size := 64.0
    var grid: Dictionary = {}
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
                    _separate_pair(a, units[cell_ids[j]])
                for offset: Vector2i in offsets:
                    if offset == Vector2i.ZERO:
                        continue
                    var neighbor_ids: Array = grid.get(cell + offset, [])
                    for j in range(neighbor_ids.size()):
                        _separate_pair(a, units[neighbor_ids[j]])


func _separate_pair(a: Dictionary, b: Dictionary) -> void:
    if a.hp <= 0 or b.hp <= 0:
        return
    var delta: Vector2 = b.pos - a.pos
    var minimum: float = UNIT_TYPES[a.type].radius + UNIT_TYPES[b.type].radius + 1
    var distance := delta.length()
    # Touching units let move sidesteps form lanes; separation only resolves
    # deeper overlaps so it cannot fight the path.
    if distance >= minimum - 1.0:
        return
    var normal := Vector2.RIGHT if distance < 0.001 else delta / distance
    var amount := (minimum - distance) / 2.0
    # Slide tangentially as well so head-on units circle around each other
    # instead of pushing straight back and stalling.
    var tangent := normal.rotated(PI / 2.0)
    var slide := amount * 0.6
    var pa: Vector2 = a.pos - normal * amount + tangent * slide
    var pb: Vector2 = b.pos + normal * amount + tangent * slide
    if position_free(pa, UNIT_TYPES[a.type].radius):
        a.pos = pa
    if position_free(pb, UNIT_TYPES[b.type].radius):
        b.pos = pb


func _ai_step() -> void:
    var base := -1
    var refinery := -1
    var barracks := -1
    var bunker := -1
    for id: int in buildings:
        if buildings[id].owner != 2:
            continue
        if buildings[id].type == "base":
            base = id
        elif buildings[id].type == "refinery":
            refinery = id
        elif buildings[id].type == "barracks":
            barracks = id
        elif buildings[id].type == "bunker":
            bunker = id
    var miners := 0
    var soldiers: Array = []
    for id: int in units:
        var u: Dictionary = units[id]
        if u.owner != 2:
            continue
        if u.type == "harvester":
            miners += 1
        elif u.type == "soldier" and u.order == "idle":
            soldiers.append(id)
    # Economy first: refinery, miners, then army production and a bunker.
    if refinery < 0 and base >= 0:
        for offset: Vector2 in [Vector2(192, 0), Vector2(0, -192), Vector2(192, -160)]:
            if command(2, {"action": "build", "type": "refinery", "pos": buildings[base].pos + offset}).is_empty():
                break
    if refinery >= 0 and miners < 5 and buildings[refinery].queue.size() < 2:
        command(2, {"action": "produce", "building": refinery, "type": "harvester"})
    if barracks < 0 and refinery >= 0:
        for offset: Vector2 in [Vector2(-192, 0), Vector2(0, -192), Vector2(-192, -160)]:
            if command(2, {"action": "build", "type": "barracks", "pos": buildings[refinery].pos + offset}).is_empty():
                break
    if barracks >= 0 and buildings[barracks].queue.size() < 2:
        command(2, {"action": "produce", "building": barracks, "type": "soldier"})
    if bunker < 0 and base >= 0 and int(money[2]) > 1200:
        for offset: Vector2 in [Vector2(0, 192), Vector2(-192, 96), Vector2(192, 96)]:
            if command(2, {"action": "build", "type": "bunker", "pos": buildings[base].pos + offset}).is_empty():
                break
    # Defense overrides attack plans: intercept enemies near friendly buildings.
    var threat := _ai_threat()
    if not threat.is_empty():
        var defenders: Array = soldiers.slice(0, mini(6, soldiers.size()))
        if not defenders.is_empty():
            command(2, {"action": "attack", "units": defenders, "kind": "unit", "target": int(threat.id)})
            return
    # Squad tactics: stage near home until strong enough, then hunt the
    # nearest enemy building instead of walking a queue into the enemy base.
    if soldiers.size() >= 6:
        var target := _ai_attack_target()
        if target >= 0:
            command(2, {"action": "attack_move", "units": soldiers, "pos": buildings[target].pos})
    elif not soldiers.is_empty() and base >= 0:
        var staging: Vector2 = buildings[base].pos + Vector2(-192, 0)
        command(2, {"action": "attack_move", "units": soldiers, "pos": staging})

# Nearest enemy unit inside AI territory (near any friendly building).
func _ai_threat() -> Dictionary:
    var best: Dictionary = {}
    var best_distance := 600.0
    for bid: int in buildings:
        if buildings[bid].owner != 2:
            continue
        for id: int in units:
            var u: Dictionary = units[id]
            if u.owner == 1 and u.hp > 0:
                var distance: float = (u.pos as Vector2).distance_to(buildings[bid].pos)
                if distance < best_distance:
                    best_distance = distance
                    best = {"id": id}
    return best

# Enemy building closest to the AI's own base.
func _ai_attack_target() -> int:
    var origin: Vector2 = WORLD / 2.0
    for b: Dictionary in buildings.values():
        if b.owner == 2 and b.type == "base":
            origin = b.pos
            break
    var best := -1
    var best_distance := INF
    for id: int in buildings:
        var b: Dictionary = buildings[id]
        if b.owner != 1:
            continue
        var distance: float = (b.pos as Vector2).distance_to(origin)
        if distance < best_distance:
            best_distance = distance
            best = id
    return best

func snapshot() -> Dictionary:
    return {"version": VERSION, "match": match_id, "frame": frame, "units": units.duplicate(true), "buildings": buildings.duplicate(true),
        "ores": ores.duplicate(true), "money": money.duplicate(true), "winner": winner, "effects": effects.duplicate(true),
        "visible": visible.duplicate(true), "explored": explored.duplicate(true)}

func validate_snapshot(state: Dictionary) -> bool:
    last_snapshot_error = ""
    for field in ["version", "match", "frame", "units", "buildings", "ores", "money", "winner", "effects", "visible", "explored"]:
        if not state.has(field):
            last_snapshot_error = "Snapshot is missing %s." % field
            return false
    if typeof(state.version) != TYPE_STRING or state.version != VERSION:
        last_snapshot_error = "Snapshot version mismatch."
        return false
    if typeof(state.match) != TYPE_INT or int(state.match) < 0:
        last_snapshot_error = "Snapshot match id is invalid."
        return false
    if typeof(state.frame) != TYPE_INT or int(state.frame) < 0:
        last_snapshot_error = "Snapshot frame is invalid."
        return false
    if typeof(state.winner) != TYPE_INT or int(state.winner) not in [0, 1, 2, 3]:
        last_snapshot_error = "Snapshot winner is invalid."
        return false
    if not _validate_snapshot_dictionary(state.units, MAX_SNAPSHOT_UNITS, "units", true):
        return false
    if not _validate_snapshot_dictionary(state.buildings, MAX_SNAPSHOT_BUILDINGS, "buildings", false):
        return false
    if not _validate_snapshot_dictionary(state.ores, MAX_SNAPSHOT_ORES, "ores", false):
        return false
    if not _validate_money(state.money):
        return false
    if not _validate_effects(state.effects, int(state.frame)):
        return false
    if not _validate_visibility(state.visible, "visible"):
        return false
    if not _validate_visibility(state.explored, "explored"):
        return false
    return true


func _validate_snapshot_dictionary(value: Variant, limit: int, label: String, units_table: bool) -> bool:
    if not (value is Dictionary):
        last_snapshot_error = "Snapshot %s table is not a dictionary." % label
        return false
    var table: Dictionary = value
    if table.size() > limit:
        last_snapshot_error = "Snapshot %s table is too large." % label
        return false
    for raw_id: Variant in table.keys():
        if typeof(raw_id) != TYPE_INT or int(raw_id) <= 0:
            last_snapshot_error = "Snapshot %s id is invalid." % label
            return false
        var entry: Variant = table[raw_id]
        if units_table:
            if not _validate_unit_entry(entry):
                return false
        elif label == "buildings":
            if not _validate_building_entry(entry):
                return false
        else:
            if not _validate_ore_entry(entry):
                return false
    return true


func _validate_unit_entry(value: Variant) -> bool:
    if not (value is Dictionary):
        last_snapshot_error = "Snapshot unit entry is not a dictionary."
        return false
    var unit: Dictionary = value
    for field in ["owner", "type", "pos", "hp", "order", "target", "attack_kind", "attack_id", "ore", "cargo", "cooldown", "work", "path", "repath", "flash", "auto", "stuck"]:
        if not unit.has(field):
            last_snapshot_error = "Snapshot unit is missing %s." % field
            return false
    if typeof(unit.owner) != TYPE_INT or int(unit.owner) not in [1, 2] or typeof(unit.type) != TYPE_STRING or not UNIT_TYPES.has(unit.type):
        last_snapshot_error = "Snapshot unit owner or type is invalid."
        return false
    var kind: String = str(unit.type)
    if not _validate_vector2(unit.pos, WORLD, "unit position") or not _validate_vector2(unit.target, WORLD * 2.0, "unit target"):
        return false
    var max_hp: int = int(UNIT_TYPES[kind].hp)
    if typeof(unit.hp) != TYPE_INT or int(unit.hp) < 0 or int(unit.hp) > max_hp:
        last_snapshot_error = "Snapshot unit hp is invalid."
        return false
    if typeof(unit.order) != TYPE_STRING or unit.order not in ["idle", "move", "attack", "attack_move", "gather"]:
        last_snapshot_error = "Snapshot unit order is invalid."
        return false
    if typeof(unit.attack_kind) != TYPE_STRING or unit.attack_kind not in ["", "unit", "building"]:
        last_snapshot_error = "Snapshot unit attack kind is invalid."
        return false
    if typeof(unit.attack_id) != TYPE_INT or int(unit.attack_id) < -1 or int(unit.attack_id) > 1000000:
        last_snapshot_error = "Snapshot unit attack id is invalid."
        return false
    if typeof(unit.ore) != TYPE_INT or int(unit.ore) < -1 or int(unit.ore) > MAX_SNAPSHOT_ORES:
        last_snapshot_error = "Snapshot unit ore id is invalid."
        return false
    if typeof(unit.cargo) != TYPE_INT or int(unit.cargo) < 0 or int(unit.cargo) > 60:
        last_snapshot_error = "Snapshot unit cargo is invalid."
        return false
    if typeof(unit.cooldown) != TYPE_INT or int(unit.cooldown) < 0 or int(unit.cooldown) > int(UNIT_TYPES[kind].cooldown):
        last_snapshot_error = "Snapshot unit cooldown is invalid."
        return false
    if typeof(unit.work) != TYPE_INT or int(unit.work) < 0 or int(unit.work) > 20:
        last_snapshot_error = "Snapshot unit work timer is invalid."
        return false
    if typeof(unit.path) != TYPE_ARRAY or unit.path.size() > 2048:
        last_snapshot_error = "Snapshot unit path is invalid."
        return false
    for point: Variant in unit.path:
        if not _validate_vector2(point, WORLD * 2.0, "unit path point"):
            return false
    if typeof(unit.repath) != TYPE_INT or int(unit.repath) < -100 or int(unit.repath) > 10000:
        last_snapshot_error = "Snapshot unit repath timer is invalid."
        return false
    if typeof(unit.flash) != TYPE_INT or int(unit.flash) < 0 or int(unit.flash) > 10:
        last_snapshot_error = "Snapshot unit flash timer is invalid."
        return false
    if typeof(unit.auto) != TYPE_BOOL:
        last_snapshot_error = "Snapshot unit auto flag is invalid."
        return false
    if typeof(unit.stuck) != TYPE_INT or int(unit.stuck) < 0 or int(unit.stuck) > 10000:
        last_snapshot_error = "Snapshot unit stuck timer is invalid."
        return false
    return true


func _validate_building_entry(value: Variant) -> bool:
    if not (value is Dictionary):
        last_snapshot_error = "Snapshot building entry is not a dictionary."
        return false
    var building: Dictionary = value
    for field in ["owner", "type", "pos", "hp", "remaining", "queue", "flash", "rally", "cooldown"]:
        if not building.has(field):
            last_snapshot_error = "Snapshot building is missing %s." % field
            return false
    if typeof(building.owner) != TYPE_INT or int(building.owner) not in [1, 2] or typeof(building.type) != TYPE_STRING or not BUILD_TYPES.has(building.type):
        last_snapshot_error = "Snapshot building owner or type is invalid."
        return false
    var kind: String = str(building.type)
    if not _validate_vector2(building.pos, WORLD, "building position") or not _validate_vector2(building.rally, WORLD * 2.0, "building rally"):
        return false
    var max_hp: int = int(BUILD_TYPES[kind].hp)
    var max_remaining: int = int(BUILD_TYPES[kind].time)
    if typeof(building.hp) != TYPE_INT or int(building.hp) < 0 or int(building.hp) > max_hp:
        last_snapshot_error = "Snapshot building hp is invalid."
        return false
    if typeof(building.remaining) != TYPE_INT or int(building.remaining) < 0 or int(building.remaining) > max_remaining:
        last_snapshot_error = "Snapshot construction timer is invalid."
        return false
    if typeof(building.queue) != TYPE_ARRAY or building.queue.size() > 5:
        last_snapshot_error = "Snapshot production queue is invalid."
        return false
    for job: Variant in building.queue:
        if not (job is Dictionary) or not job.has("type") or not job.has("remaining") or typeof(job.type) != TYPE_STRING or not UNIT_TYPES.has(job.type) or typeof(job.remaining) != TYPE_INT:
            last_snapshot_error = "Snapshot production job is invalid."
            return false
        if int(job.remaining) < 0 or int(job.remaining) > int(UNIT_TYPES[job.type].time):
            last_snapshot_error = "Snapshot production timer is invalid."
            return false
    if typeof(building.flash) != TYPE_INT or int(building.flash) < 0 or int(building.flash) > 10:
        last_snapshot_error = "Snapshot building flash timer is invalid."
        return false
    var max_cooldown := int(BUILD_TYPES.bunker.cooldown)
    if typeof(building.cooldown) != TYPE_INT or int(building.cooldown) < 0 or int(building.cooldown) > max_cooldown:
        last_snapshot_error = "Snapshot building cooldown is invalid."
        return false
    return true


func _validate_ore_entry(value: Variant) -> bool:
    if not (value is Dictionary):
        last_snapshot_error = "Snapshot ore entry is not a dictionary."
        return false
    var ore: Dictionary = value
    if not ore.has("pos") or not ore.has("amount") or not _validate_vector2(ore.pos, WORLD, "ore position") or typeof(ore.amount) != TYPE_INT or int(ore.amount) < 0 or int(ore.amount) > MAX_SNAPSHOT_ORE_AMOUNT:
        last_snapshot_error = "Snapshot ore entry is invalid."
        return false
    return true


func _validate_money(value: Variant) -> bool:
    if not (value is Dictionary) or value.size() != 2 or not value.has(1) or not value.has(2):
        last_snapshot_error = "Snapshot money table is invalid."
        return false
    for owner: Variant in value.keys():
        if typeof(owner) != TYPE_INT or int(owner) not in [1, 2] or typeof(value[owner]) != TYPE_INT or int(value[owner]) < 0 or int(value[owner]) > 1000000000:
            last_snapshot_error = "Snapshot money entry is invalid."
            return false
    return true


func _validate_effects(value: Variant, snapshot_frame: int) -> bool:
    if not (value is Array) or value.size() > MAX_SNAPSHOT_EFFECTS:
        last_snapshot_error = "Snapshot effects are invalid."
        return false
    for effect: Variant in value:
        if not (effect is Dictionary) or not effect.has("kind") or not effect.has("from") or not effect.has("to") or not effect.has("life") or not effect.has("owner") or not effect.has("frame"):
            last_snapshot_error = "Snapshot effect entry is invalid."
            return false
        if typeof(effect.kind) != TYPE_STRING or effect.kind not in ["shot", "death"] or not _validate_vector2(effect.from, WORLD * 2.0, "effect origin") or not _validate_vector2(effect.to, WORLD * 2.0, "effect target"):
            return false
        if typeof(effect.life) != TYPE_INT or int(effect.life) < 0 or int(effect.life) > 60 or typeof(effect.owner) != TYPE_INT or int(effect.owner) not in [1, 2] or typeof(effect.frame) != TYPE_INT or int(effect.frame) < 0 or int(effect.frame) > snapshot_frame:
            last_snapshot_error = "Snapshot effect metadata is invalid."
            return false
    return true


func _validate_visibility(value: Variant, label: String) -> bool:
    if not (value is Dictionary) or value.size() != 2 or not value.has(1) or not value.has(2):
        last_snapshot_error = "Snapshot %s table is invalid." % label
        return false
    for owner: Variant in value.keys():
        if typeof(owner) != TYPE_INT or int(owner) not in [1, 2] or not (value[owner] is PackedByteArray) or value[owner].size() != GRID_CELLS:
            last_snapshot_error = "Snapshot %s buffer is invalid." % label
            return false
    return true


func _validate_vector2(value: Variant, bounds: Vector2, label: String) -> bool:
    if not (value is Vector2):
        last_snapshot_error = "Snapshot %s is not a Vector2." % label
        return false
    var point: Vector2 = value
    if not is_finite(point.x) or not is_finite(point.y) or absf(point.x) > bounds.x or absf(point.y) > bounds.y:
        last_snapshot_error = "Snapshot %s is out of bounds." % label
        return false
    return true


func apply_snapshot(state: Dictionary) -> bool:
    if not validate_snapshot(state):
        return false
    match_id  = state.match
    frame     = state.frame
    units     = state.units.duplicate(true)
    buildings = state.buildings.duplicate(true)
    ores      = state.ores.duplicate(true)
    money     = state.money.duplicate(true)
    winner    = state.winner
    effects   = state.effects.duplicate(true)
    visible   = state.visible.duplicate(true)
    explored  = state.explored.duplicate(true)
    return true
