extends RefCounted
## Synchronous rules; Simulation owns state, caches and tick order.


static func _ai_step(sim: Simulation) -> void:
    var base := -1
    var refinery := -1
    var barracks := -1
    var bunker := -1
    for id: int in sim.buildings:
        if sim.buildings[id].owner != 2:
            continue
        if sim.buildings[id].type == "base":
            base = id
        elif sim.buildings[id].type == "refinery":
            refinery = id
        elif sim.buildings[id].type == "barracks":
            barracks = id
        elif sim.buildings[id].type == "bunker":
            bunker = id
    var miners := 0
    var soldiers: Array = []
    for id: int in sim.units:
        var u: Dictionary = sim.units[id]
        if u.owner != 2:
            continue
        if u.type == "harvester":
            miners += 1
        elif sim.is_combat_unit(u.type):
            if u.order == "idle":
                soldiers.append(id)
    # Economy first: refinery, miners, then army production and a bunker.
    if refinery < 0 and base >= 0:
        for offset: Vector2 in sim._ai_build_offsets("base", "refinery", [Vector2(1, 0), Vector2(0, -1), Vector2(1, -1)]):
            if sim.command(2, {"action": "build", "type": "refinery", "pos": sim.buildings[base].pos + offset}).is_empty():
                break
    if refinery >= 0 and miners < 5 and sim.buildings[refinery].queue.size() < 2:
        sim.command(2, {"action": "produce", "building": refinery, "type": "harvester"})
    if barracks < 0 and refinery >= 0:
        for offset: Vector2 in sim._ai_build_offsets("refinery", "barracks", [Vector2(-1, 0), Vector2(0, -1), Vector2(-1, -1)]):
            if sim.command(2, {"action": "build", "type": "barracks", "pos": sim.buildings[refinery].pos + offset}).is_empty():
                break
    if barracks >= 0 and sim.buildings[barracks].queue.size() < 2:
        sim.command(2, {"action": "produce", "building": barracks, "type": "mobile_infantry"})
    if bunker < 0 and base >= 0 and int(sim.money[2]) > 1200:
        for offset: Vector2 in sim._ai_build_offsets("base", "bunker", [Vector2(0, 1), Vector2(-1, 1), Vector2(1, 1)]):
            if sim.command(2, {"action": "build", "type": "bunker", "pos": sim.buildings[base].pos + offset}).is_empty():
                break
    # Defense overrides attack plans: intercept enemies near friendly buildings.
    var threat: Dictionary = sim._ai_threat()
    if not threat.is_empty():
        var defenders: Array = soldiers.slice(0, mini(6, soldiers.size()))
        if not defenders.is_empty():
            sim.command(2, {"action": "attack", "units": defenders, "kind": "unit", "target": int(threat.id)})
            return
    # Squad tactics: stage near home until strong enough, then hunt the
    # nearest enemy building instead of walking a queue into the enemy base.
    if soldiers.size() >= 6:
        var target: int = sim._ai_attack_target()
        if target >= 0:
            sim.command(2, {"action": "attack_move", "units": soldiers, "pos": sim.buildings[target].pos})
    elif not soldiers.is_empty() and base >= 0:
        var staging: Vector2 = sim.buildings[base].pos + Vector2(-192, 0)
        sim.command(2, {"action": "attack_move", "units": soldiers, "pos": staging})


static func _ai_threat(sim: Simulation) -> Dictionary:
    var best: Dictionary = {}
    var best_distance := 600.0
    for bid: int in sim.buildings:
        if sim.buildings[bid].owner != 2:
            continue
        for id: int in sim.units:
            var u: Dictionary = sim.units[id]
            if u.owner == 1 and u.hp > 0:
                var distance: float = (u.pos as Vector2).distance_to(sim.buildings[bid].pos)
                if distance < best_distance:
                    best_distance = distance
                    best = {"id": id}
    return best


static func _ai_attack_target(sim: Simulation) -> int:
    var origin: Vector2 = Simulation.WORLD / 2.0
    for b: Dictionary in sim.buildings.values():
        if b.owner == 2 and b.type == "base":
            origin = b.pos
            break
    var best := -1
    var best_distance := INF
    for id: int in sim.buildings:
        var b: Dictionary = sim.buildings[id]
        if b.owner != 1 or not sim.can_target({"type": "mobile_infantry"}, b):
            continue
        var distance: float = (b.pos as Vector2).distance_to(origin)
        if distance < best_distance:
            best_distance = distance
            best = id
    return best


static func _ai_build_offsets(sim: Simulation, anchor_kind: String, build_kind: String, directions: Array) -> Array[Vector2]:
    var half_sizes: Vector2 = (Simulation.BUILD_TYPES[anchor_kind].size + Simulation.BUILD_TYPES[build_kind].size) * 0.5
    var spacing: Vector2 = Vector2(ceilf((half_sizes.x + Simulation.CELL) / Simulation.CELL), ceilf((half_sizes.y + Simulation.CELL) / Simulation.CELL)) * Simulation.CELL
    var offsets: Array[Vector2] = []
    for direction: Vector2 in directions:
        offsets.append(spacing * direction)
    return offsets
