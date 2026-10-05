extends SceneTree

const Terrain = preload("res://scripts/maps/map_terrain.gd")
const Sim = preload("res://scripts/simulation.gd")
var failures: Array[String] = []

func _initialize() -> void:
    run.call_deferred()

func check(value: bool, message: String) -> void:
    if not value:
        failures.append(message)
        push_error(message)

func run() -> void:
    var terrain := Terrain.new()
    check(terrain.load_map("desert_quarry"), "Desert assembly: " + terrain.error)
    if not terrain.error.is_empty():
        quit(1)
        return
    check(is_equal_approx(terrain.height_at(Vector2(1536, 1088)), 96.0), "Plateau is 96 high")
    check(is_equal_approx(terrain.height_at(Vector2(1024, 1088)), 48.0), "Ramp midpoint is 48 high")
    check(is_equal_approx(terrain.height_at(Vector2(3936, 704)), -96.0), "Quarry floor is -96")
    check(is_equal_approx(terrain.height_at(Vector2(3488, 704)), -48.0), "Quarry ramp midpoint")
    check(not terrain.segment_clear(Vector2(1180, 850), Vector2(1260, 850), 14), "Cannot cross plateau wall")
    check(terrain.segment_clear(Vector2(800, 1088), Vector2(1300, 1088), 14), "Can cross ramp seams")
    check(not terrain.line_of_sight(Vector2(1180, 850), Vector2(1290, 850)), "Plateau blocks low direct fire")
    check(terrain.line_of_sight(Vector2(1480, 1088), Vector2(1580, 1088)), "Clear fire on same plateau")
    check(not terrain.build_error(Rect2(960, 1024, 64, 64)).is_empty(), "Reject building on ramp")
    check(terrain.build_error(Rect2(1440, 1184, 64, 64)).is_empty(), "Allow building on flat high ground")
    for z in range(5, 3200, 64):
        for x in range(5, 4800, 64):
            var p := Vector2(x, z)
            check(is_equal_approx(terrain.height_at(p), terrain.height_at(Terrain.WORLD - p)), "Symmetric heights at %s" % p)
    for road: Dictionary in terrain.definition.roads:
        for segment in range(road.points.size() - 1):
            check(terrain.segment_clear(road.points[segment], road.points[segment + 1], 11.0), "Authored road follows traversable terrain")
    var second := Terrain.new()
    check(second.load_map("desert_quarry") and second.checksum == terrain.checksum, "Deterministic map checksum")
    var bad := terrain.definition.duplicate(true)
    bad.modules.append(bad.modules[0].duplicate())
    check(not second.assemble(bad) and second.error.contains("Overlapping"), "Reject overlapping modules")
    bad = terrain.definition.duplicate(true)
    bad.modules[1].height = 80.0
    check(not second.assemble(bad) and second.error.contains("seam"), "Reject disconnected ramp heights")
    var sim := Sim.new()
    check(sim.reset(false, "desert_quarry"), "Simulation loads selected map")
    sim.units.clear()
    var unit := sim.add_unit(1, "soldier", Vector2(768, 1088))
    var destination := Vector2(1536, 1088)
    for tick in range(220):
        var before: Vector2 = sim.units[unit].pos
        sim.move_towards(sim.units[unit], destination)
        check(terrain.segment_clear(before, sim.units[unit].pos, 11), "Every movement step stays on navigable ground")
    check((sim.units[unit].pos as Vector2).distance_to(destination) < 8.0, "Unit reaches plateau via ramp")
    sim.units[unit].pos = Vector2(3104, 704)
    for tick in range(240):
        sim.move_towards(sim.units[unit], Vector2(3936, 704))
    check((sim.units[unit].pos as Vector2).distance_to(Vector2(3936, 704)) < 8.0, "Unit reaches quarry floor")
    sim.units.clear()
    var attacker := sim.add_unit(1, "soldier", Vector2(1195, 960))
    var defender := sim.add_unit(2, "soldier", Vector2(1300, 960))
    sim.visible[1].fill(1)
    sim.units[attacker].attack_kind = "unit"
    sim.units[attacker].attack_id = defender
    sim.units[attacker].order = "attack_move"
    sim.units[attacker].target = Vector2(1600, 600)
    sim._fight(sim.units[attacker], "attack_move")
    check(sim.units[defender].hp == 100 and sim.units[attacker].attack_id == -1, "Blocked attack-move releases target without damage")
    var turret := sim._add_building(1, "bunker", Vector2(1152, 928), true)
    check(sim._bunker_target(sim.buildings[turret]).is_empty(), "Bunker cannot shoot through cliff")
    sim.units[attacker].pos = Vector2(1390, 960)
    sim.units[attacker].attack_kind = "unit"
    sim.units[attacker].attack_id = defender
    sim._fight(sim.units[attacker])
    check(sim.units[defender].hp == 84, "Unobstructed highland shot deals normal damage")
    sim.units[attacker].pos = Vector2(1195, 960)
    sim.buildings.erase(turret)
    sim.update_visibility()
    check(not sim.can_see(1, Vector2(1376, 960)), "Cliff conceals terrain behind its lip")
    sim.units[attacker].pos = Vector2(1408, 960)
    sim.update_visibility()
    check(sim.can_see(1, Vector2(1376, 960)), "Climbing highland reveals its surface")
    var high_base := sim._add_building(1, "base", Vector2(1536, 1280), true)
    check(sim.build_error(1, "barracks", Vector2(1728, 1216)).is_empty(), "Simulation permits construction on flat highland")
    check(not sim.build_error(1, "barracks", Vector2(1792, 1376)).is_empty(), "Simulation rejects footprint across cliff")
    sim.buildings.erase(high_base)
    var client := Sim.new()
    client.reset()
    check(client.apply_snapshot(sim.snapshot()) and client.map_id == "desert_quarry", "Snapshot loads host map")
    check(client.terrain.checksum == sim.terrain.checksum, "Client height data agrees with host")
    var invalid := sim.snapshot()
    invalid.map_checksum = "wrong"
    var previous_frame: int = client.frame
    check(not client.apply_snapshot(invalid) and client.frame == previous_frame, "Reject mismatched content without mutation")
    invalid = sim.snapshot()
    invalid.map_id = "missing"
    check(not client.apply_snapshot(invalid), "Reject unknown maps")
    print("TERRAIN_MAPS ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
    quit(0 if failures.is_empty() else 1)
