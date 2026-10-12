extends RefCounted
## Synchronous rules; Simulation owns state, caches and tick order.


static func can_target(sim: Simulation, attacker: Dictionary, target: Dictionary) -> bool:
    var layers: Array = Simulation.WEAPON_TARGETS.get(attacker.type, [])
    return sim.weapon_can_target(layers, target)


static func weapon_can_target(sim: Simulation, layers: Array, target: Dictionary) -> bool:
    return ("air" if Simulation.BarracksFlight.is_airborne(target) else "ground") in layers


static func _bunker_target(sim: Simulation, b: Dictionary) -> Dictionary:
    var best: Dictionary = {}
    var best_distance: float = Simulation.BUILD_TYPES.bunker.range
    for id: int in sim.units:
        var u: Dictionary = sim.units[id]
        if u.owner == b.owner or u.hp <= 0 or not sim.can_target(b, u) or not sim.can_see(int(b.owner), u.pos):
            continue
        var distance: float = (b.pos as Vector2).distance_to(u.pos)
        if distance <= best_distance and sim.terrain.line_of_sight(b.pos, u.pos, Simulation.EYE_HEIGHTS.bunker, Simulation.EYE_HEIGHTS[u.type]):
            best = u
            best_distance = distance
    return best


static func _closest_enemy(sim: Simulation, u: Dictionary) -> Array:
    var result: Array = []
    var distance := 190.0
    for kind: String in ["unit", "building"]:
        var collection: Dictionary = sim.units if kind == "unit" else sim.buildings
        for id: int in collection:
            var e: Dictionary = collection[id]
            var d: float = (u.pos as Vector2).distance_to(e.pos)
            if e.owner != u.owner and d < distance and e.hp > 0 and sim.can_target(u, e) and sim.can_see(u.owner, e.pos) and sim.terrain.line_of_sight(u.pos, e.pos, Simulation.EYE_HEIGHTS[u.type], Simulation.EYE_HEIGHTS.get(e.type, 40.0)):
                distance = d
                result = [kind, id]
    return result


static func _fight(sim: Simulation, u: Dictionary, fallback_order: String = "idle") -> bool:
    var collection: Dictionary = sim.units if u.attack_kind == "unit" else sim.buildings
    if not collection.has(int(u.attack_id)) or collection[int(u.attack_id)].hp <= 0 or not sim.can_target(u, collection[int(u.attack_id)]):
        u.attack_kind = ""
        u.attack_id   = -1
        u.order       = fallback_order
        return false
    var enemy: Dictionary = collection[int(u.attack_id)]
    var edge: Vector2 = enemy.pos
    if u.attack_kind == "building":
        edge = (u.pos as Vector2).clamp(sim.footprint(enemy).position, sim.footprint(enemy).end)
    var distance: float = (u.pos as Vector2).distance_to(edge)
    var clear_shot: bool = sim.terrain.line_of_sight(u.pos, edge, Simulation.EYE_HEIGHTS[u.type], Simulation.EYE_HEIGHTS.get(enemy.type, 40.0))
    if (not sim.can_see(u.owner, enemy.pos) or not clear_shot):
        if fallback_order == "attack_move":
            u.attack_kind = ""
            u.attack_id = -1
            return false
        var firing_position: Vector2 = sim._firing_position(u, edge)
        if firing_position.is_finite():
            sim.move_towards(u, firing_position)
        return true
    if distance > Simulation.UNIT_TYPES[u.type].range:
        sim.move_towards(u, edge, 70)
    elif u.cooldown <= 0:
        u.cooldown = Simulation.UNIT_TYPES[u.type].cooldown
        enemy.hp -= Simulation.UNIT_TYPES[u.type].damage
        enemy.flash = 3
        var shot := {"from": u.pos, "to": edge, "life": 5, "kind": "shot", "owner": u.owner, "frame": sim.frame}
        if u.type == "mobile_infantry":
            # Identity survives movement, attacker death and snapshot delivery.
            var source_id := -1
            for id: int in sim.units:
                if is_same(sim.units[id], u):
                    source_id = id
                    break
            shot.impact = {"source_type": "mobile_infantry", "source_id": source_id,
                "target_kind": u.attack_kind, "target_id": int(u.attack_id),
                "target_type": enemy.type, "target_pos": enemy.pos}
        sim.effects.append(shot)
    return true


static func _firing_position(sim: Simulation, u: Dictionary, target: Vector2) -> Vector2:
    var best := Vector2(INF, INF)
    var distance := INF
    for index in range(16):
        var point := target + Vector2.from_angle(index * TAU / 16.0) * 100.0
        if not sim.position_free(point, Simulation.UNIT_TYPES[u.type].radius) or not sim.terrain.line_of_sight(point, target):
            continue
        var radius: float = Simulation.UNIT_TYPES[u.type].radius
        var route: PackedVector2Array = sim.navigation_for(radius).get_point_path(sim.nearest_cell(u.pos, radius), sim.nearest_cell(point, radius))
        if route.is_empty():
            continue
        var length := 0.0
        for step in range(1, route.size()):
            length += route[step].distance_to(route[step - 1])
        if length < distance:
            best = point
            distance = length
    return best


static func advance_bunker(sim: Simulation, b: Dictionary) -> void:
    b.cooldown = maxi(0, int(b.cooldown) - 1)
    if b.cooldown <= 0:
        var target: Dictionary = sim._bunker_target(b)
        if not target.is_empty():
            b.cooldown = Simulation.BUILD_TYPES.bunker.cooldown
            target.hp -= Simulation.BUILD_TYPES.bunker.damage
            target.flash = 3
            sim.effects.append({"from": b.pos, "to": target.pos, "life": 5, "kind": "shot", "owner": b.owner, "frame": sim.frame})


static func advance_attack_move(sim: Simulation, u: Dictionary) -> void:
    if int(u.attack_id) >= 0:
        sim._fight(u, "attack_move")
    if int(u.attack_id) < 0:
        var nearby: Array = sim._closest_enemy(u)
        if not nearby.is_empty():
            u.attack_kind = nearby[0]
            u.attack_id = nearby[1]
        else:
            Simulation.MovementSystem.advance_move(sim, u)


static func advance_idle(sim: Simulation, u: Dictionary) -> void:
    var target: Array = sim._closest_enemy(u)
    if not target.is_empty():
        u.attack_kind = target[0]
        u.attack_id = target[1]
        u.order = "attack"
