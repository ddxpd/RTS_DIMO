extends SceneTree
const Bindings = preload("res://scripts/controllers/key_bindings.gd")
const MAIN = preload("res://scenes/main.tscn")
var failures: Array[String] = []
var checks := 0


func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)


func key(code: int, ctrl: bool = false, shift: bool = false) -> InputEventKey:
    var event := InputEventKey.new()
    event.physical_keycode = code
    event.pressed = true
    event.ctrl_pressed = ctrl
    event.shift_pressed = shift
    return event


func _initialize() -> void:
    run.call_deferred()


func run() -> void:
    var bindings := Bindings.new()
    bindings.settings_path = "res://.godot/settings-bindings-check.cfg"
    var seen := {}
    for action: String in bindings.defaults:
        var value: int = bindings.defaults[action]
        check(not seen.has(value) and Bindings.invalid_reason(value, action).is_empty(), "Unique legal default " + action)
        seen[value] = true
    check(bindings.rebind("attack", KEY_S).contains("停止"), "Conflict names the occupied action")
    check(bindings.bindings.attack == KEY_A and bindings.bindings.stop == KEY_S, "Conflict is non-mutating")
    check(not bindings.rebind("attack", KEY_ALT).is_empty(), "Modifier alone rejected")
    check(not bindings.rebind("attack", KEY_F4 | KEY_MASK_ALT).is_empty(), "System shortcut rejected")
    check(not bindings.rebind("attack", KEY_ESCAPE).is_empty(), "Safe escape reserved")
    check(bindings.rebind("attack", KEY_Q | KEY_MASK_CTRL).is_empty(), "Modified key accepted")
    check(bindings.action_for(key(KEY_Q, true)) == "attack" and bindings.action_for(key(KEY_Q)) == "", "Modifiers match exactly")
    check(bindings.action_for(key(KEY_1, true)) == "group_assign_1" and bindings.action_for(key(KEY_1, false, true)) == "group_append_1", "Group modifiers do not recall group")
    var copy := Bindings.new()
    copy.settings_path = bindings.settings_path
    copy.load_settings()
    check(copy.bindings == bindings.bindings, "All bindings survive restart")
    check(bindings.rebind("menu", KEY_F10).is_empty(), "Menu supports custom key alongside Escape safety")
    bindings.reset_all()
    check(bindings.bindings == bindings.defaults, "Restore defaults")
    var game := MAIN.instantiate()
    root.size = Vector2i(1280, 800)
    root.add_child(game)
    game.play_solo()
    game.set_process(false)
    game.key_bindings.bindings = bindings.defaults.duplicate()
    game.key_bindings.settings_path = bindings.settings_path
    bindings = game.key_bindings
    game.settings_panel.refresh()
    game._toggle_menu()
    game.settings_button.pressed.emit()
    check(game.settings_panel.visible and game.menu_visible and not game.menu.visible, "Settings are nested under menu")
    check(game.camera_speed_slider.get_parent().get_parent().name == "游戏通用", "Speed lives in general settings")
    game.settings_panel.rows.attack.pressed.emit()
    game._input(key(KEY_Q))
    check(bindings.bindings.attack == KEY_Q and game.settings_panel.recording.is_empty(), "Recording consumes and saves key")
    check(not game.attack_mode, "Recorded attack key never triggers gameplay")
    game.settings_panel.begin_recording("stop")
    game._input(key(KEY_ESCAPE))
    check(game.settings_panel.visible and game.settings_panel.recording.is_empty(), "Escape cancels recording without closing settings")
    game._input(key(KEY_ESCAPE))
    check(not game.settings_panel.visible and game.menu.visible and game.menu_visible, "Escape returns to parent menu")
    game._close_menu()
    game.selected_units.assign([game.sim.add_unit(1, "mobile_infantry", Vector2(700, 500))])
    game._unhandled_input(key(KEY_A))
    check(not game.attack_mode, "Old binding no longer invokes command")
    game._unhandled_input(key(KEY_Q))
    check(game.attack_mode, "New binding invokes available command")
    check(game.action_buttons.any(func(button): return button.action_id == "attack" and button.hotkey.text == "Q"), "Command card reflects rebind")
    game.attack_mode = false
    var text := LineEdit.new()
    root.add_child(text)
    text.grab_focus()
    game._unhandled_input(key(KEY_Q))
    check(not game.attack_mode, "Typing cannot invoke gameplay")
    text.release_focus()
    text.free()
    game._clear_selection()
    game._unhandled_input(key(KEY_Q))
    check(not game.attack_mode, "Unavailable action cannot run")
    game.sim.money[1] = 10000
    game.selected_building = 1
    game.selected_buildings.assign([1])
    for pair in [[KEY_B, "barracks"], [KEY_F, "refinery"], [KEY_N, "bunker"], [KEY_H, "base"]]:
        game._unhandled_input(key(pair[0]))
        check(game.build_mode == pair[1], "Build hotkey shares command-card action " + pair[1])
        game._input(key(KEY_ESCAPE))
    game._unhandled_input(key(KEY_L))
    for tick in range(120):
        game.sim.step()
    game._unhandled_input(key(KEY_M))
    check(game.pending_command == "move", "Move key supports airborne base")
    var destination: Vector2 = game.sim.buildings[1].pos + Vector2(120, 0)
    game._pending_click(destination)
    check(game.sim.buildings[1].flight.target == destination and game.sim.buildings[1].flight.moving, "Flight move key uses existing network command")
    game._unhandled_input(key(KEY_S))
    check(not game.sim.buildings[1].flight.moving, "Stop key stops airborne base")
    for pair in [["barracks", KEY_T, "mobile_infantry"], ["refinery", KEY_U, "harvester"]]:
        var producer: int = game.sim._add_building(1, pair[0], Vector2(1000, 500), true)
        game.selected_building = producer
        game.selected_buildings.assign([producer])
        game._unhandled_input(key(pair[1]))
        check(game.sim.buildings[producer].queue.size() == 1, "Production key " + pair[2])
        game._unhandled_input(key(KEY_C))
        check(game.sim.buildings[producer].queue.is_empty(), "Cancel key removes queued production")
        game._unhandled_input(key(KEY_R))
        game._pending_click(Vector2(1100, 500))
        check(game.sim.buildings[producer].rally_mode != "none", "Rally key sets destination")
        game._unhandled_input(key(KEY_R, false, true))
        check(game.sim.buildings[producer].rally_mode == "none" and game.pending_command.is_empty(), "Shift+R clears rather than entering rally mode")
    game._clear_selection()
    game.settings_panel.open()
    game.settings_panel.tabs.current_tab = 1
    if DisplayServer.get_name() != "headless":
        for dimensions: Vector2i in [Vector2i(1280, 800), Vector2i(960, 640)]:
            root.size = dimensions
            for frame in range(3):
                await process_frame
            var logical_size: Vector2 = game.get_viewport().get_visible_rect().size
            check(game.settings_panel.get_rect().end.x <= logical_size.x and game.settings_panel.get_rect().end.y <= logical_size.y, "Settings fit resized window")
            await RenderingServer.frame_post_draw
            var path := "res://assets/concept_art/ui_selection/settings"
            DirAccess.make_dir_recursive_absolute(path)
            root.get_texture().get_image().save_png(path + "/keys-%d.png" % dimensions.x)
        game.settings_panel.tabs.current_tab = 0
        await process_frame
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png("res://assets/concept_art/ui_selection/settings/general.png")
    bindings.reset_all()
    DirAccess.remove_absolute(bindings.settings_path)
    game.audio_controller.reset_state()
    await process_frame
    game.queue_free()
    await process_frame
    await create_timer(0.1).timeout
    print("SETTINGS_TEST checks=", checks, " failures=", failures)
    quit(0 if failures.is_empty() else 1)
