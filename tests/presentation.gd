extends SceneTree
const MAIN = preload("res://scenes/main.tscn")
var game: Node2D
var failures: Array[String] = []
var screenshot := false

func _initialize() -> void:
    screenshot = "--screenshot" in OS.get_cmdline_user_args()
    run.call_deferred()

func check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
        push_error(message)

func click(world: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
    var event := InputEventMouseButton.new()
    event.position     = game.get_global_transform_with_canvas() * world
    event.button_index = button
    event.pressed      = true
    root.push_input(event, true)
    event = event.duplicate()
    event.pressed = false
    root.push_input(event, true)

func run() -> void:
    root.size = Vector2i(1280, 800)
    game = MAIN.instantiate()
    root.add_child(game)
    game.play_solo()
    game.set_process(false)
    game.sim.ai_enabled = false
    await process_frame
    await process_frame
    game.camera.force_update_scroll()
    click(game.sim.units[3].pos)
    check(game.bottom_zones.has_all(["map", "status", "command"]), "Command bar splits into map/status/command zones")
    var map_zone: Control = game.bottom_zones.get("map")
    if map_zone == null or map_zone.custom_minimum_size.x < 200:
        check(false, "Map zone reserves left-side space")
    check(game.selected_units == [3], "Viewport left-click selects friendly unit")
    var initial: Vector2 = game.sim.units[3].pos
    click(Vector2(550, 330))
    check(game.selected_units.is_empty(), "Blank click clears selection")
    check(game.sim.units[3].order == "idle" and game.sim.units[3].pos == initial, "Left-click does not move")
    click(initial)
    click(Vector2(550, 330), MOUSE_BUTTON_RIGHT)
    check(game.sim.units[3].order == "move" and not game.clicks.is_empty(), "Right-click issues move and destination effect")
    var event := InputEventMouseButton.new()
    event.position     = game.get_global_transform_with_canvas() * Vector2(560, 240)
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed      = true
    root.push_input(event, true)
    event          = event.duplicate()
    event.position = game.get_global_transform_with_canvas() * Vector2(680, 340)
    event.pressed  = false
    root.push_input(event, true)
    check(game.selected_units.size() == 2, "Viewport drag selects both soldiers")
    # A drag that ends over the bottom HUD must still complete the selection.
    var hud_press := InputEventMouseButton.new()
    hud_press.button_index = MOUSE_BUTTON_LEFT
    hud_press.pressed = true
    hud_press.position = game.get_global_transform_with_canvas() * Vector2(560, 240)
    root.push_input(hud_press, true)
    var hud_release := InputEventMouseButton.new()
    hud_release.button_index = MOUSE_BUTTON_LEFT
    hud_release.pressed = false
    hud_release.position = game.get_global_transform_with_canvas() * Vector2(700, 1150)
    root.push_input(hud_release, true)
    check(game.selected_units.size() == 6, "Drag ending over HUD completes selection")
    # A canceled release (focus quirk) must not end an active drag.
    var cancel_press := InputEventMouseButton.new()
    cancel_press.button_index = MOUSE_BUTTON_LEFT
    cancel_press.pressed = true
    cancel_press.position = game.get_global_transform_with_canvas() * Vector2(560, 240)
    root.push_input(cancel_press, true)
    var cancel_release := InputEventMouseButton.new()
    cancel_release.button_index = MOUSE_BUTTON_LEFT
    cancel_release.pressed = false
    cancel_release.canceled = true
    cancel_release.position = Vector2(760, 990)
    root.push_input(cancel_release, true)
    check(game.selection_dragging, "Canceled release keeps the drag alive")
    var real_release := InputEventMouseButton.new()
    real_release.button_index = MOUSE_BUTTON_LEFT
    real_release.pressed = false
    real_release.position = game.get_global_transform_with_canvas() * Vector2(700, 1150)
    root.push_input(real_release, true)
    check(game.selected_units.size() == 6, "Real release after cancel completes selection")
    # Lost release events finish via the per-frame tracked-button fallback.
    game._clear_selection()
    game.selection_dragging = true
    game.selection_start = Vector2(560, 240)
    game.selection_current = Vector2(700, 1150)
    game.set_process(true)
    await process_frame
    await process_frame
    game.set_process(false)
    check(game.selected_units.size() == 6 and not game.selection_dragging, "Lost releases finish via frame fallback")
    # A spurious duplicate press mid-drag must not restart the box.
    var box_press := InputEventMouseButton.new()
    box_press.button_index = MOUSE_BUTTON_LEFT
    box_press.pressed = true
    box_press.position = game.get_global_transform_with_canvas() * Vector2(560, 240)
    root.push_input(box_press, true)
    var box_motion := InputEventMouseMotion.new()
    box_motion.position = game.get_global_transform_with_canvas() * Vector2(680, 340)
    root.push_input(box_motion, true)
    var duplicate_press := InputEventMouseButton.new()
    duplicate_press.button_index = MOUSE_BUTTON_LEFT
    duplicate_press.pressed = true
    duplicate_press.position = box_motion.position
    root.push_input(duplicate_press, true)
    check(game.selection_dragging and game.selection_start == Vector2(560, 240), "Duplicate press keeps the original box")
    var box_release := InputEventMouseButton.new()
    box_release.button_index = MOUSE_BUTTON_LEFT
    box_release.pressed = false
    box_release.position = box_motion.position
    root.push_input(box_release, true)
    check(game.selected_units.size() == 2, "Original box completes after duplicate press")
    # A stale drag (lost release, no input for 2s) restarts from the new press.
    game._clear_selection()
    game.selection_dragging = true
    game.left_button_held = true
    game.selection_start = Vector2(560, 240)
    game.selection_current = Vector2(700, 1150)
    game.last_mouse_event_msec = Time.get_ticks_msec() - 2000
    var stale_press := InputEventMouseButton.new()
    stale_press.button_index = MOUSE_BUTTON_LEFT
    stale_press.pressed = true
    stale_press.position = game.get_global_transform_with_canvas() * Vector2(680, 340)
    root.push_input(stale_press, true)
    check(game.selection_dragging and game.selection_start == Vector2(680, 340), "Stale drag restarts from the new press")
    check(game.selected_units.size() == 6, "Stale box completed before restart")
    var stale_release := InputEventMouseButton.new()
    stale_release.button_index = MOUSE_BUTTON_LEFT
    stale_release.pressed = false
    stale_release.position = stale_press.position
    root.push_input(stale_release, true)
    var refinery: int = game.sim._add_building(1, "refinery", Vector2(288, 432), true)
    click(game.sim.buildings[refinery].pos)
    check(game.selected_building == refinery and game.selected_units.is_empty(), "Building selection")
    game._produce("harvester")
    check(game.sim.buildings[refinery].queue.size() == 1, "Production UI callback enqueues")
    game._begin_build("barracks")
    click(Vector2(704, 320))
    check(game.sim.buildings.size() == 4 and game.build_mode == "", "Build preview click creates construction")
    var wheel := InputEventMouseButton.new()
    wheel.position     = Vector2(300, 300)
    wheel.button_index = MOUSE_BUTTON_WHEEL_UP
    wheel.pressed      = true
    var zoom: float = game.camera.zoom.x
    root.push_input(wheel, true)
    check(game.camera.zoom.x > zoom, "Mouse wheel zoom")
    game.camera.zoom = Vector2.ONE
    game.camera.position = Vector2(500, 350)
    game._limit_camera()
    game.selected_building = 9
    for i in range(81):
        game.sim.step()
    game._produce("soldier")
    game._refresh_ui()
    game._clear_selection()
    var one_unit: Array[int] = [3]
    game.selected_units   = one_unit
    game.sim.units[4].pos = game.sim.units[3].pos + Vector2(50, 0)
    game.attack_mode      = true
    game._attack_click(game.sim.units[4].pos)
    game.sim.step()
    check(game.sim.units[4].hp < 100, "Attack mode force-attacks friendly unit")
    game.selected_units = one_unit
    game.attack_mode = true
    game._attack_click(Vector2(600, 160))
    check(game.sim.units[3].order == "attack_move", "Attack mode ground click creates attack-move")
    game._begin_rebind()
    var key_event := InputEventKey.new()
    key_event.pressed = true
    key_event.keycode = KEY_Q
    game._unhandled_input(key_event)
    check(game.attack_keycode == KEY_Q and not game.rebinding_attack, "Attack key can be rebound")
    game.queue_redraw()
    if screenshot:
        await RenderingServer.frame_post_draw
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png("res://build/verification/gameplay.png")
    print("PRESENTATION_TEST failures=", failures)
    quit(0 if failures.is_empty() else 1)
