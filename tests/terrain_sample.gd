extends SceneTree

const Sim = preload("res://scripts/simulation.gd")
var failures: Array[String] = []


func _initialize() -> void:
    run.call_deferred()


func check(value: bool, message: String) -> void:
    if not value:
        failures.append(message)
        push_error(message)


func run() -> void:
    var sim := Sim.new()
    check(sim.reset(true, "desert_sample"), "Load sample: " + sim.last_snapshot_error)
    if not sim.last_snapshot_error.is_empty():
        quit(1)
        return
    var field = sim.terrain.sample_surface
    check(sim.is_test_map() and not sim.ai_enabled and sim.money[1] == 10000, "Local sandbox defaults")
    check(sim.units.size() == 7 and sim.buildings.size() == 3, "Sample starting roster")
    check(sim.can_see(1, Vector2(4700, 3100)), "Fully revealed without spectator ownership")
    check(is_equal_approx(field.height_at(Vector2(1766, 1922)), 96), "Flat highland")
    check(is_equal_approx(field.height_at(Vector2(3016, 1782)), -96), "Flat pit floor")
    check(sim.terrain.build_error(Rect2(1776, 1856, 64, 64)).is_empty(), "Buildable plateau pad")
    check(not sim.terrain.build_error(Rect2(1844, 1412, 64, 64)).is_empty(), "No construction on ramp")
    check(not sim.terrain.segment_clear(Vector2(1456, 1882), Vector2(1696, 1882), 14), "No crossing highland cliff")
    for road: Dictionary in field.roads:
        var points: PackedVector2Array = road.points
        for i in range(1, points.size()):
            check(sim.terrain.segment_clear(points[i - 1], points[i], 14), "Road center remains traversable")
    for ramp: Dictionary in sim.terrain.definition.ramps:
        check(sim.terrain.segment_clear(ramp.start, ramp.end, 24), "Wide ramp center remains clear")
        for end: Vector2 in [ramp.start, ramp.end]:
            check(absf(field.height_at(end + Vector2(0, 0.1)) - field.height_at(end - Vector2(0, 0.1))) < 0.1, "Continuous ramp endpoint")
    # Each unit type must actually follow the existing command/navigation path
    # uphill and downhill; sampling heights alone cannot verify that contract.
    sim.units.clear()
    for kind in ["soldier", "harvester"]:
        for x in [1876.0, 2876.0]:
            var start := Vector2(x, 1092)
            var target := Vector2(x, 1882 if x == 1876.0 else 1782)
            var id := sim.add_unit(1, kind, start)
            check(sim.command(1, {"action": "move", "units": [id], "pos": target}).is_empty(), "Accept sample move")
            for tick in range(360):
                sim.step()
                if (sim.units[id].pos as Vector2).distance_to(target) < 14:
                    break
            check((sim.units[id].pos as Vector2).distance_to(target) < 20, "%s reaches ramp destination %s (at %s)" % [kind, target, sim.units[id].pos])
            sim.units.erase(id)
    sim.buildings.clear()
    sim.step()
    check(sim.winner == 0, "Test field has no victory or defeat")
    var repeat := Sim.new()
    check(repeat.reset(false, "desert_sample"), "Reload sample")
    check(repeat.terrain.sample_surface.heights == field.heights, "Repeatable fine surface")
    check(repeat.reset(true, "prototype") and not repeat.is_test_map() and repeat.ai_enabled, "Normal map restores AI")
    check(not repeat.can_see(1, Vector2(4700, 3100)), "Normal map restores fog")
    print("TERRAIN_SAMPLE ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
    quit(0 if failures.is_empty() else 1)
