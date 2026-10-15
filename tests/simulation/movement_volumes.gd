extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
    run.call_deferred()


func check(value: bool, message: String) -> void:
    checks += 1
    if not value:
        failures.append(message)
        push_error(message)


func run() -> void:
    var sim := Sim.new()
    sim.reset()
    sim.units.clear()
    sim.obstacles = [Rect2(1200, 0, 80, 1760), Rect2(1200, 1824, 80, 1376)]
    sim.rebuild_navigation()
    for radius in [16.0, 48.0]:
        var nav := sim.navigation_for(radius)
        var path := nav.get_point_path(sim.nearest_cell(Vector2(1056, 1792), radius), sim.nearest_cell(Vector2(1472, 1792), radius))
        check(not path.is_empty() if radius == 16.0 else path.is_empty(), "64-wide passage honors body size " + str(radius))
    check(not sim.movement_free(Vector2(1100, 1700), Vector2(1400, 1700), 16), "swept body cannot cross wall between free endpoints")
    sim.reset()
    sim.units.clear()
    var miner := sim.add_unit(1, "harvester", Vector2(384 + Sim.BUILD_TYPES.barracks.size.x * 0.5 + Sim.UNIT_TYPES.harvester.radius * 0.5, 640))
    check(sim.build_error(1, "barracks", Vector2(384, 640)) == "Blocked by a unit", "building placement checks body outside center")
    sim.units.erase(miner)
    var a := sim._add_building(1, "barracks", Vector2(1600, 1900), true)
    var b := sim._add_building(1, "barracks", Vector2(1920, 1900), true)
    for id in [a, b]:
        sim.buildings[id].flight.state = "airborne"
        sim.buildings[id].flight.height = 400.0
        sim.buildings[id].flight.cruise = 400.0
    check(Sim.BarracksFlight.air_clear(sim, a, Vector2(1790, 1900), 400), "Aligned airborne hulls can share a narrow gap")
    check(not Sim.BarracksFlight.air_clear(sim, a, Vector2(1800, 1900), 400), "Actual airborne hull overlap is blocked")
    var original: Vector2 = sim.buildings[a].pos
    sim.buildings[a].pos = Vector2(1790, 1900)
    check(not Sim.BarracksFlight.turn_clear(sim, a, PI / 2), "Turning corner cannot enter neighboring hull")
    sim.buildings[a].pos = original
    check(Sim.BarracksFlight.air_clear(sim, a, Vector2(1790, 1900), 600), "vertically separated air bodies can pass")
    check(not Sim.BarracksFlight.air_clear(sim, a, Vector2(65, 1900), 400), "rotation envelope stays inside map")
    check(sim.command(1, {"action": "barracks_move", "building": a, "pos": Vector2(2200, 1900)}).is_empty(), "first air move accepted")
    check(sim.command(1, {"action": "barracks_move", "building": b, "pos": Vector2(1320, 1900)}).is_empty(), "opposing air move accepted")
    for tick in range(800):
        for id in [a, b]:
            Sim.BarracksFlight.advance(sim, id, sim.buildings[id])
            var body: Dictionary = sim.buildings[id]
            check(Sim.BarracksFlight.air_clear(sim, id, body.pos, body.flight.height, false), "Opposing rotated air hulls never overlap")
    check(not sim.buildings[a].flight.moving and not sim.buildings[b].flight.moving, "air traffic reaches both destinations")
    sim.reset()
    sim.units.clear()
    var squad: Array = []
    for i in range(12):
        squad.append(sim.add_unit(1, "soldier", Vector2(850 + i % 4 * 48, 1700 + i / 4 * 48)))
    check(sim.command(1, {"action": "move", "units": squad, "pos": Vector2(1600, 1900)}).is_empty(), "group receives sized slots")
    for i in range(squad.size()):
        for j in range(i + 1, squad.size()):
            check((sim.units[squad[i]].target as Vector2).distance_to(sim.units[squad[j]].target) >= 40.0 - 0.01, "formation leaves body clearance plus margin")
    for tick in range(650):
        sim.step()
    for id: int in squad:
        check(sim.units[id].order == "idle", "squad member reaches reserved slot " + str(id))
    var settled: Dictionary = {}
    for id: int in squad:
        settled[id] = sim.units[id].pos
    for tick in range(60):
        sim.step()
    for id: int in squad:
        check((sim.units[id].pos as Vector2).distance_to(settled[id]) < 0.1, "arrived unit remains stable")
    print("MOVEMENT_VOLUMES ", checks, " checks; failures=", failures)
    quit(0 if failures.is_empty() else 1)
