extends SceneTree
# Camera suite (3D): zoom floor, edge scrolling, border clamping and recovery.
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
    var size: Vector2 = game.get_viewport().get_visible_rect().size
    game.camera_controller.mouse_position_provider = func() -> Vector2: return mouse_state["pos"]

    # 1) Dynamic zoom floor keeps the world larger than the viewport on both axes.
    var min_zoom: float = game._min_zoom()
    if min_zoom > 0.5:
        failures.append("zoom floor too restrictive for large world")
    if game.camera_zoom_level < 0.9:
        failures.append("reset view starts below reasonable zoom")

    # 2) Repeated wheel-out cannot cross the floor.
    game.camera_zoom_level = 0.15
    for i in range(10):
        var wheel := InputEventMouseButton.new()
        wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
        wheel.pressed = true
        wheel.position = Vector2(960, 540)
        game._unhandled_input(wheel)
    if game.camera_zoom_level < 0.11:
        failures.append("wheel zoom crossed the dynamic floor")

    # 3) Edge scrolling moves the camera focus in all four directions.
    game.camera_zoom_level = 1.0
    var cases := {
        "left": [Vector2(5, 540), Vector2(1, 0)],
        "right": [Vector2(size.x - 5, 540), Vector2(-1, 0)],
        "up": [Vector2(960, 5), Vector2(0, 1)],
        "down": [Vector2(960, size.y - 5), Vector2(0, -1)]
    }
    for direction_name: String in cases:
        game.camera_controller.focus = Vector2(2400, 1600)
        game._update_camera_transform()
        mouse_state["pos"] = cases[direction_name][0]
        game.camera_controller.update(1.0)
        var moved: Vector2 = game.camera_controller.focus - Vector2(2400, 1600)
        var expected: Vector2 = cases[direction_name][1] * 150.0
        if moved.dot(expected) <= 0.0:
            failures.append("edge scroll failed: " + direction_name)

    # 4) The camera focus clamps at world borders instead of escaping them.
    game.camera_controller.focus = Vector2(100, 100)
    game._update_camera_transform()
    mouse_state["pos"] = Vector2(960, 540)
    game.camera_controller.update(1.0)
    if game.camera_controller.focus.x < 50.0 or game.camera_controller.focus.y < 50.0:
        failures.append("camera escaped the world border")

    # 5) Long scrolling toward a border still recovers in the opposite direction.
    game._update_camera_transform()
    mouse_state["pos"] = Vector2(5, 540)
    for i in range(60):
        game.camera_controller.update(0.1)
    var pinned: float = game.camera_controller.focus.x
    mouse_state["pos"] = Vector2(size.x - 5, 540)
    game.camera_controller.update(1.0)
    if game.camera_controller.focus.x >= pinned - 1.0:
        failures.append("camera stayed stuck at the border after reversing")

    # 6) Zoom keeps the world point under the cursor anchored (windowed only).
    if DisplayServer.get_name() != "headless":
        game.camera_zoom_level = 2.0
        game.camera_controller.focus = Vector2(2400, 1600)
        game._update_camera_transform()
        Input.warp_mouse(Vector2(960, 540))
        await process_frame
        var anchor_before: Vector2 = game._screen_to_world(Vector2(960, 540))
        var zoom_event := InputEventMouseButton.new()
        zoom_event.button_index = MOUSE_BUTTON_WHEEL_UP
        zoom_event.pressed = true
        zoom_event.position = Vector2(960, 540)
        game._unhandled_input(zoom_event)
        var anchor_after: Vector2 = game._screen_to_world(Vector2(960, 540))
        if anchor_before.distance_to(anchor_after) > 100.0:
            failures.append("zoom anchor drifted")

    # 7) Camera speed setting scales edge scrolling and syncs the controller.
    # Apply the value explicitly so a persisted player preference cannot make
    # this regression suite depend on the local user://settings.cfg state.
    game._camera_speed_changed(1.8)
    if absf(game.camera_speed_multiplier - 1.8) > 0.01:
        failures.append("camera speed setting does not apply 1.8x")
    game.camera_zoom_level = 1.0
    game.camera_controller.focus = Vector2(3000, 1600)
    game._update_camera_transform()
    mouse_state["pos"] = Vector2(5, 540)
    game._camera_speed_changed(2.0)
    game.camera_controller.update(1.0)
    if game.camera_controller.focus.x <= 3000.0:
        failures.append("speed multiplier does not scale edge scrolling")
    game._camera_speed_changed(1.8)

    print("CAMERA_TEST failures=", failures)
    quit(0 if failures.is_empty() else 1)
