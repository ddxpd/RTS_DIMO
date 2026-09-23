extends SceneTree

const MAIN = preload("res://scenes/main.tscn")

var game: Node3D
var failures: Array[String] = []


func _initialize() -> void:
    run.call_deferred()


func check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
        push_error(message)


func measure(callable: Callable, iterations: int) -> float:
    var start := Time.get_ticks_usec()
    for index: int in range(iterations):
        callable.call()
    return (Time.get_ticks_usec() - start) / float(iterations) / 1000.0


func run() -> void:
    root.size = Vector2i(1920, 1080)
    game = MAIN.instantiate()
    root.add_child(game)
    game.play_solo()
    game.sim.ai_enabled = false
    await process_frame
    await process_frame
    game._sync_visuals()

    var added := 0
    for row: int in range(12):
        for column: int in range(14):
            var kind := "soldier" if (row + column) % 3 != 0 else "harvester"
            var position := Vector2(600.0 + column * 95.0, 300.0 + row * 105.0)
            var id: int = game.sim.add_unit(1, kind, position)
            game.sim.units[id].order = "move"
            game.sim.units[id].target = position + Vector2(180.0, 160.0)
            added += 1
    game.camera_controller.focus = Vector2(1200.0, 850.0)
    game.camera_zoom_level = 0.7
    game._update_camera_transform()
    game._sync_visuals()
    await process_frame

    var mesh_count := 0
    for entry: Dictionary in game.unit_visuals.values():
        mesh_count += (entry.visual as EntityVisual).model.find_children("*", "MeshInstance3D", true, false).size()

    var sync_units_ms := measure(func(): game._sync_units(), 100)
    var sync_visuals_ms := measure(func(): game._sync_visuals(), 20)
    var refresh_ui_ms := measure(func(): game._refresh_ui(), 50)
    var simulation_ms := measure(func(): game.sim.step(), 20)
    check(game.unit_visuals.size() == game.sim.units.size(), "Every stress-test unit has a visual")
    check(mesh_count <= 2800, "180-unit stress test keeps optimized mesh count below 2800")
    check(sync_visuals_ms < 8.0, "Visual sync stays below 8ms for 180 units")
    check(sync_units_ms < 2.0, "Unit visual state sync stays below 2ms for 180 units")
    check(refresh_ui_ms < 1.0, "HUD refresh stays below 1ms")
    check(simulation_ms < 25.0, "180-unit simulation tick stays below 25ms")

    var result := {
        "added": added,
        "units": game.sim.units.size(),
        "visuals": game.unit_visuals.size(),
        "mesh_count": mesh_count,
        "sync_units_ms": sync_units_ms,
        "sync_visuals_ms": sync_visuals_ms,
        "refresh_ui_ms": refresh_ui_ms,
        "simulation_ms": simulation_ms
    }
    print("VISUAL_PERFORMANCE_TEST ", JSON.stringify(result), " failures=", failures)
    quit(0 if failures.is_empty() else 1)
