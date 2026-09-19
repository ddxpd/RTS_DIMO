extends SceneTree
# Camera suite: zoom floor, edge scrolling, border clamping and recovery.
const MAIN = preload("res://scenes/main.tscn")

var mouse_state := {"pos": Vector2(960, 540)}

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    Engine.max_fps = 120
    var game := MAIN.instantiate()
    root.add_child(game)
    game.play_solo()
    var failures: Array = []
    var size: Vector2 = game.get_viewport_rect().size
    # Inject a deterministic mouse position for headless edge-scroll tests.
    game.camera_controller.mouse_position_provider = func() -> Vector2: return mouse_state["pos"]

    # 1) Dynamic zoom floor keeps the world larger than the viewport on both axes.
    var min_zoom: float = game._min_zoom()
    var fit_zoom := maxf(size.x / 1600.0, size.y / 960.0)
    if min_zoom <= fit_zoom:
        failures.append("zoom floor lets the world fit the viewport")
    if game.camera.zoom.x < min_zoom - 0.001:
        failures.append("reset view starts below the zoom floor")

    # 2) Repeated wheel-out cannot cross the floor.
    game.camera.zoom = Vector2.ONE * min_zoom
    for i in range(10):
        var wheel := InputEventMouseButton.new()
        wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
        wheel.pressed = true
        wheel.position = Vector2(960, 540)
        game._unhandled_input(wheel)
    if game.camera.zoom.x < min_zoom - 0.001:
        failures.append("wheel zoom crossed the dynamic floor")

    # 3) Edge scrolling moves in all four directions at zoom 2.
    game.camera.zoom = Vector2.ONE * 2.0
    var map := Rect2(0, 52, size.x - 260, size.y - 184)
    var map_center := map.get_center()
    var cases := {
        "left": [Vector2(map.position.x + 5, map_center.y), Vector2(-1, 0)],
        "right": [Vector2(map.end.x - 5, map_center.y), Vector2(1, 0)],
        "up": [Vector2(map_center.x, 10), Vector2(0, -1)],
        "down": [Vector2(map_center.x, size.y - 10), Vector2(0, 1)]
    }
    for direction_name: String in cases:
        game.camera.position = Vector2(800, 480)
        mouse_state["pos"] = cases[direction_name][0]
        game.camera_controller.update(1.0)
        var moved: Vector2 = game.camera.position - Vector2(800, 480)
        var expected: Vector2 = cases[direction_name][1] * 150.0
        if moved.dot(expected) <= 0.0:
            failures.append("edge scroll failed: " + direction_name)

    # 3b) The old in-map edge strips no longer trigger vertical scrolling.
    for dead_y: float in [60.0, map.end.y - 8.0]:
        game.camera.position = Vector2(800, 480)
        mouse_state["pos"] = Vector2(map_center.x, dead_y)
        game.camera_controller.update(1.0)
        if game.camera.position != Vector2(800, 480):
            failures.append("old map strip still scrolls at y=" + str(dead_y))

    # 4) The camera clamps at world borders instead of escaping them.
    game.camera.position = Vector2(100, 100)
    mouse_state["pos"] = Vector2(960, 540)
    game.camera_controller.update(1.0)
    if game.camera.position.x < 479.0 or game.camera.position.y < 269.0:
        failures.append("camera escaped the world border")

    # 5) Long scrolling toward a border still recovers in the opposite direction.
    mouse_state["pos"] = Vector2(5, 540)
    for i in range(60):
        game.camera_controller.update(0.1)
    var pinned: float = game.camera.position.x
    if absf(pinned - 480.0) > 1.0:
        failures.append("camera did not pin at the left border")
    mouse_state["pos"] = Vector2(1650, 540)
    game.camera_controller.update(1.0)
    if game.camera.position.x <= pinned + 1.0:
        failures.append("camera stayed stuck at the border after reversing")

    # 6) Zoom keeps the world point under the cursor anchored (windowed only).
    if DisplayServer.get_name() != "headless":
        game.camera.zoom = Vector2.ONE * 2.0
        game.camera.position = Vector2(800, 480)
        Input.warp_mouse(Vector2(960, 540))
        await process_frame
        var anchor_before: Vector2 = game.get_global_mouse_position()
        var zoom_event := InputEventMouseButton.new()
        zoom_event.button_index = MOUSE_BUTTON_WHEEL_UP
        zoom_event.pressed = true
        zoom_event.position = Vector2(960, 540)
        game._unhandled_input(zoom_event)
        var anchor_after: Vector2 = game.get_global_mouse_position()
        if anchor_before.distance_to(anchor_after) > 2.0:
            failures.append("zoom anchor drifted")

    # 7) Camera speed setting scales edge scrolling and syncs the controller.
    if absf(game.camera_speed_multiplier - 1.4) > 0.01:
        failures.append("default camera speed is not the faster 1.4x")
    game.camera.zoom = Vector2.ONE * 2.0
    game.camera.position = Vector2(1000, 480)
    mouse_state["pos"] = Vector2(5, 500)
    game._camera_speed_changed(2.0)
    game.camera_controller.update(1.0)
    if absf((1000.0 - game.camera.position.x) - 420.0) > 2.0:
        failures.append("speed multiplier does not scale edge scrolling")
    game._camera_speed_changed(1.4)

    print("CAMERA_TEST failures=", failures)
    quit(0 if failures.is_empty() else 1)
