extends SceneTree

const Sim = preload("res://scripts/simulation.gd")
var failures: Array[String] = []


func _initialize() -> void:
    run.call_deferred()


func check(value: bool, message: String) -> void:
    if not value and not failures.has(message):
        failures.append(message)
        push_error(message)


func run() -> void:
    var sim := Sim.new()
    sim.reset(false, "desert_sample")
    sim.units.clear()
    var top := Vector2(1876, 1882)
    var region := sim.terrain.arrival_region_at(top)
    check(region >= 0 and region != sim.terrain.arrival_region_at(Vector2(1500, 1882)), "Distinct highland region")
    var squad: Array = []
    for i in range(6):
        squad.append(sim.add_unit(1, "soldier", Vector2(1800 + i * 30, 1200)))
    for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN, Vector2.UP]:
        var click := top
        for d in range(320, 0, -4):
            var p := top + direction * d
            if sim.terrain.arrival_region_at(p) == region and sim.position_free(p, 11):
                click = p
                break
        check(sim.command(1, {"action": "move", "units": squad, "pos": click}).is_empty(), "Accept edge formation")
        for id: int in squad:
            check(sim.terrain.arrival_region_at(sim.units[id].target) == region, "All slots on plateau")
            check((sim.units[id].target as Vector2).distance_to(click) <= 128.01, "Compact slots near click")
        for tick in range(1000):
            sim.step()
            var done := true
            for id: int in squad:
                done = done and sim.units[id].order == "idle"
            if done:
                break
        for id: int in squad:
            if sim.units[id].order != "idle":
                print("UNARRIVED ", sim.units[id])
            check(sim.units[id].order == "idle" and sim.terrain.arrival_region_at(sim.units[id].pos) == region,
                "All six actually arrive on clicked platform")
        print("EDGE_FORMATION ", direction, " click=", click, " positions=", squad.map(func(id): return sim.units[id].pos))
    sim.units.clear()
    squad.clear()
    for i in range(6):
        squad.append(sim.add_unit(1, "harvester" if i % 3 == 0 else "soldier", Vector2(2800 + i * 30, 1200)))
    var pit := Vector2(2996, 1800)
    var pit_region := sim.terrain.arrival_region_at(pit)
    check(sim.command(1, {"action": "attack_move", "units": squad, "pos": pit}).is_empty(), "Mixed attack-move into quarry")
    for id: int in squad:
        sim.units[id].auto = false
    for tick in range(700):
        sim.step()
    for id: int in squad:
        check(sim.units[id].order == "idle" and sim.terrain.arrival_region_at(sim.units[id].pos) == pit_region, "Mixed units arrive on pit floor")
    # Building occupancy changes slots but never the terrain's region identity.
    sim._add_building(1, "barracks", top, true)
    sim.rebuild_navigation()
    check(sim.command(1, {"action": "move", "units": squad, "pos": top}).is_empty(), "Building-covered click uses nearby platform slots")
    for id: int in squad:
        check(sim.position_free(sim.units[id].target, sim.UNIT_TYPES[sim.units[id].type].radius), "Building excludes occupied slots")
    var old_target: Vector2 = sim.units[squad[0]].target
    for index in sim.GRID_CELLS:
        if sim.terrain.arrival_regions.labels[index] == region:
            sim.nav.set_point_solid(Vector2i(index % sim.GRID.x, int(index / sim.GRID.x)), true)
    sim.arrival_nav_regions.clear()
    check(not sim.command(1, {"action": "move", "units": squad, "pos": top}).is_empty(), "Unreachable platform returns feedback")
    check(sim.units[squad[0]].target == old_target, "Failed group command is atomic")
    sim.buildings.clear()
    sim.rebuild_navigation()
    sim.units.clear()
    squad.clear()
    for i in range(180):
        squad.append(sim.add_unit(1, "soldier", Vector2(2150 + (i % 10) * 26, 1100 + int(i / 10) * 26)))
    var began := Time.get_ticks_usec()
    check(sim.command(1, {"action": "move", "units": squad, "pos": top}).is_empty(), "Accept crowded formation")
    var allocation_ms := (Time.get_ticks_usec() - began) / 1000.0
    print("FORMATION_ALLOCATE_180 ms=", allocation_ms)
    check(allocation_ms < 150.0, "180-unit compact allocation stays below 150ms")
    var waiting: Array = []
    var assigned: Array = []
    for id: int in squad:
        if sim.units[id].arrival.waiting:
            waiting.append(id)
        else:
            assigned.append(id)
        check(sim.terrain.arrival_region_at(sim.units[id].target) == region, "Overflow never assigned lower ground")
    check(not waiting.is_empty() and not assigned.is_empty(), "Overflow waits")
    if not waiting.is_empty():
        var pending: Dictionary = sim.units[waiting[0]]
        check(sim.ArrivalPlanner.reserved_for_other(sim, pending, sim.units[assigned[0]].target), "Waiting cannot steal a reserved empty slot")
    var state := sim.snapshot()
    var clone := Sim.new()
    check(clone.apply_snapshot(state), "Arrival snapshot round trip")
    if not waiting.is_empty() and not assigned.is_empty():
        for id: int in assigned:
            sim.units.erase(id)
        sim.frame = 19
        sim.step()
        var promoted := 0
        for id: int in waiting:
            promoted += int(not sim.units[id].arrival.waiting)
        check(promoted > 0, "Released slots serve waiting units")
        var id: int = waiting[0]
        check(sim.command(1, {"action": "stop", "units": [id]}).is_empty() and not sim.units[id].has("arrival"), "Stop clears intent")
        state.units[id].arrival.region = -1
        check(not clone.validate_snapshot(state), "Reject invalid arrival region")
    var retry_start := Time.get_ticks_usec()
    var max_retry_ms := 0.0
    for tick in range(20):
        var began_retry := Time.get_ticks_usec()
        sim.ArrivalPlanner.refresh(sim)
        max_retry_ms = maxf(max_retry_ms, (Time.get_ticks_usec() - began_retry) / 1000.0)
        sim.frame += 1
    print("WAIT_RETRY max_ms=", max_retry_ms, " total_ms=", (Time.get_ticks_usec() - retry_start) / 1000.0)
    check(max_retry_ms < 25.0, "Waiting retries are spread across simulation ticks")
    print("ARRIVAL_FORMATION failures=", failures)
    quit(0 if failures.is_empty() else 1)
