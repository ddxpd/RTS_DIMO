extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
const Config = preload("res://scripts/runtime/match_config.gd")
const Service = preload("res://scripts/runtime/room_service.gd")
var failures: Array = []

func check(value: bool, label: String) -> void:
    if not value:
        failures.append(label)
        push_error(label)

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    var config := Config.defaults()
    config.seats = ["human", "ai", "ai", "ai"]
    config.funds = 3000
    var sim := Sim.new()
    check(sim.reset(false, config.map, config), "four-player reset")
    check(sim.buildings.size() == 4 and sim.players.size() == 4, "four bases")
    check(sim.money[4] == 3000 and sim.ai_players == [2, 3, 4], "funds and AI")
    for i in range(3):
        var first: Vector2 = sim.ores[i + 1].pos
        var opposite: Vector2 = sim.ores[i + 4].pos
        check(first + opposite == Sim.WORLD, "mirrored grid-centered resources")
    var state := sim.snapshot()
    var client := Sim.new()
    check(client.apply_snapshot(Service.unpack(Service.pack(state))), "compressed roundtrip")
    check(client.players == sim.players, "player metadata")
    sim.surrender(1)
    sim.surrender(2)
    sim.surrender(4)
    check(sim.winner == 3 and sim.result.status == "won", "owner three is not draw")
    config.mode = "2v2"
    check(sim.reset(false, config.map, config), "2v2 reset")
    check(sim.allied(1, 3) and not sim.allied(1, 2), "alliance")
    check(sim.visible[1] == sim.visible[3], "shared vision")
    var soldier := sim.add_unit(1, "mobile_infantry", Vector2(720, 720))
    var ally := sim.add_unit(3, "mobile_infantry", Vector2(750, 720))
    check(not sim.command(1, {"action": "attack", "units": [soldier], "kind": "unit", "target": ally, "force": true}).is_empty(), "no allied attack")
    sim.surrender(2)
    sim.surrender(4)
    check(sim.result.team == 1, "team victory")
    var training := Config.defaults(true)
    training.seats[1] = "ai"
    check(sim.reset(false, training.map, training), "sample training supports AI")
    for building: Dictionary in sim.buildings.values():
        check(sim.terrain.build_error(sim.footprint(building)).is_empty(), "aligned clear training spawn")
    var app = load("res://scenes/frontier.tscn").instantiate()
    root.add_child(app)
    await process_frame
    check(app.game == null and app.mode == "home", "home has no battlefield")
    check(app.menu_music.menu_active and app.menu_music.player.playing, "home starts menu music")
    check(app.home_modes.visible and not app.mode_panel.visible, "home modes have no enclosing form panel")
    var versus: Button = app.home_modes.get_node("Multiplayer")
    versus.grab_focus()
    await create_timer(0.20).timeout
    check(versus.highlight > 0.95, "keyboard focus animates mode highlight")
    check(not versus._has_point(Vector2.ZERO) and versus._has_point(versus.size * 0.5), "mode hit area excludes transparent corners")
    versus.pressed.emit()
    check(app.mode == "multiplayer" and not app.home_modes.visible and app.mode_panel.visible, "mode button opens multiplayer form")
    var music_position: float = app.menu_music.player.get_playback_position()
    check(is_zero_approx(versus.highlight), "hidden button resets animation")
    app._home()
    check(app.menu_music.player.playing and app.menu_music.player.get_playback_position() >= music_position, "front-end navigation does not restart music")
    check(app.menu_cursor_applied, "home installs menu cursor")
    check(app.MENU_CURSOR.get_size() == Vector2(40, 40), "menu cursor native dimensions")
    var cursor_image: Image = app.MENU_CURSOR.get_image()
    check(cursor_image.get_pixel(5, 4).a > 0.5, "menu hotspot is on arrow tip")
    app.home_actions.get_node("Settings").pressed.emit()
    check(app.settings_panel.visible and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "home settings")
    app.settings_panel.close()
    check(app.home_actions.is_visible_in_tree(), "settings returns to home actions")
    app.config = Config.defaults(true)
    app.home_modes.get_node("Training").pressed.emit()
    check(app.mode == "training", "training setup")
    check(not app.home_actions.visible, "home actions hidden during configuration")
    app.config.map = "frontier_four"
    app.config.seats[1] = "ai"
    app._start_game({}, 1, false)
    check(not app.menu_music.menu_active, "loading immediately requests music fade out")
    await process_frame
    await process_frame
    await create_timer(.5).timeout
    check(not app.menu_music.player.playing, "battlefield does not retain menu music")
    check(app.game != null and app.game.sim.training and app.game.sim.ai_players == [2], "training with AI")
    app.game.cursor_controller.update_cursor()
    check(not app.menu_cursor_applied, "battlefield owns cursor")
    app.game._toggle_menu()
    app.game.cursor_controller.update_cursor()
    check(app.menu_cursor_applied and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "pause uses menu cursor and releases mouse")
    check(not app.menu_music.menu_active, "battlefield pause does not start title music")
    app.game.settings_panel.open()
    app.game.cursor_controller._focus_exited()
    app.game.cursor_controller._focus_entered()
    check(app.menu_cursor_applied, "settings focus transitions retain menu cursor")
    app.game.settings_panel.close()
    app.game._close_menu()
    app.game.cursor_controller.update_cursor()
    check(not app.menu_cursor_applied and app.game.cursor_controller.current_state != &"", "resume reinstalls battlefield cursor")
    app.game.sim.training = false
    app.game.sim.surrender(2)
    await process_frame
    # Timer-based audio checks resume after processing; allow the front end's
    # next process callback to observe the result before inspecting its UI.
    await process_frame
    check(app.mode == "result" and app.root.visible, "result waits for explicit return")
    check(not app.menu_music.menu_active, "result overlay does not restart title music")
    check(app.menu_cursor_applied, "result uses menu cursor")
    check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not app.game.is_processing_input(), "result releases cursor and blocks battlefield input")
    app.return_home()
    await process_frame
    check(app.game == null and app.mode == "home", "return home")
    check(app.menu_music.menu_active and app.menu_music.player.playing, "return home restarts menu music")
    check(app.menu_cursor_applied, "teardown restores menu cursor after battlefield exits")
    app.apply_menu_cursor(true)
    check(app.menu_cursor_applied, "home focus restores menu cursor")
    if DisplayServer.get_name() != "headless":
        cursor_image.save_png("res://.godot/menu-cursor.png")
        for window_size: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800), Vector2i(960, 640)]:
            root.size = window_size
            await process_frame
            await process_frame
            await RenderingServer.frame_post_draw
            var actions: Rect2 = app.home_actions.get_global_rect()
            check(not actions.intersects(app.mode_panel.get_global_rect()), "actions clear of mode panel at %s" % window_size)
            check(not actions.intersects(app.cards.get_global_rect()), "actions clear of cards at %s" % window_size)
            check(app.root.get_global_rect().encloses(actions), "actions inside window at %s" % window_size)
            check(not app.home_modes.get_global_rect().intersects(actions), "mode cards clear of utility buttons at %s" % window_size)
            check(app.root.get_global_rect().encloses(app.home_modes.get_global_rect()), "mode cards fit window at %s" % window_size)
            root.get_texture().get_image().save_png("res://.godot/frontier-home-%dx%d.png" % [window_size.x, window_size.y])
        root.size = Vector2i(1920, 1080)
        versus.grab_focus()
        await create_timer(0.20).timeout
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png("res://.godot/frontier-mode-highlight.png")
    app.queue_free()
    await process_frame
    # Give the audio mixer a block to release its Ogg playback references.
    await create_timer(.15).timeout
    print("FRONTIER_TEST ", JSON.stringify({"passed": failures.is_empty(), "failures": failures}))
    quit(0 if failures.is_empty() else 1)
