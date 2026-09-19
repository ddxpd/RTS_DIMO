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
    check(game.selected_units == [3], "Viewport left-click selects friendly unit")
    var initial: Vector2 = game.sim.units[3].pos
    click(Vector2(550, 330))
    check(game.selected_units.is_empty(), "Blank click clears selection")
    check(game.sim.units[3].order == "idle" and game.sim.units[3].pos == initial, "Left-click does not move")
    click(initial)
    click(Vector2(550, 330), MOUSE_BUTTON_RIGHT)
    check(game.sim.units[3].order == "move" and not game.clicks.is_empty(), "Right-click issues move and destination effect")
    var event := InputEventMouseButton.new()
    event.position     = game.get_global_transform_with_canvas() * Vector2(275, 125)
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed      = true
    root.push_input(event, true)
    event          = event.duplicate()
    event.position = game.get_global_transform_with_canvas() * Vector2(330, 240)
    event.pressed  = false
    root.push_input(event, true)
    check(game.selected_units.size() == 2, "Viewport drag selects both soldiers")
    var refinery: int = game.sim._add_building(1, "refinery", Vector2(288, 432), true)
    click(game.sim.buildings[refinery].pos)
    check(game.selected_building == refinery and game.selected_units.is_empty(), "Building selection")
    game._produce("harvester")
    check(game.sim.buildings[refinery].queue.size() == 1, "Production UI callback enqueues")
    game._begin_build("barracks")
    click(Vector2(448, 160))
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
