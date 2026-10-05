extends SceneTree
## Real renderer + hardware cursor probe. Optional Win32 capture reads .godot/cursor-probe.json.
const MAIN = preload("res://scenes/main.tscn")
const Marker = preload("res://scripts/ui/destination_marker.gd")
const OUTPUT := "res://assets/concept_art/cursor_runtime"
var game
var panel: Control


func _initialize() -> void:
    run.call_deferred()


func label_at(text: String, point: Vector2, size: int = 20) -> void:
    var label := Label.new()
    label.text = text
    label.position = point
    label.add_theme_font_size_override("font_size", size)
    panel.add_child(label)


func capture(filename: String) -> void:
    await process_frame
    await RenderingServer.frame_post_draw
    assert(root.get_texture().get_image().save_png(OUTPUT.path_join(filename)) == OK)


func run() -> void:
    if DisplayServer.get_name() == "headless":
        push_error("Use run-godot.ps1 -Rendered")
        quit(1)
        return
    DirAccess.make_dir_recursive_absolute(OUTPUT)
    root.size = Vector2i(1200, 800)
    root.content_scale_size = root.size
    root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
    root.msaa_3d = Viewport.MSAA_4X
    DisplayServer.window_set_size(root.size)
    game = MAIN.instantiate()
    game.selected_map_id = "prototype"
    root.add_child(game)
    game.play_solo()
    game.set_process(false)
    game.sim.ai_enabled = false
    game.camera_zoom_level = 2.0
    game.camera_controller.focus = Vector2(700, 450)
    game._update_camera_transform()
    game.sim.visible[1].fill(1)
    game.sim.explored[1].fill(1)
    game._sync_visuals()
    game.hud.visible = false
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    var overlay := CanvasLayer.new()
    root.add_child(overlay)
    panel = Control.new()
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.add_child(panel)
    label_at("INDUSTRIAL ARMOR / runtime assets (40 px + 4x detail)", Vector2(30, 12))
    for row in range(2):
        var backdrop := ColorRect.new()
        backdrop.color = Color("#293039") if row == 0 else Color("#d4cfc2")
        backdrop.position = Vector2(20, 50 + row * 250)
        backdrop.size = Vector2(1160, 240)
        backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
        panel.add_child(backdrop)
        for i in range(5):
            var state: StringName = game.cursor_controller.STATES[i]
            for multiplier in [1, 4]:
                var texture := TextureRect.new()
                texture.texture = game.cursor_controller.textures[state]
                texture.position = Vector2(55 + i * 228, 80 + row * 250 + (55 if multiplier == 4 else 0))
                texture.size = Vector2(40, 40) * multiplier
                texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
                texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
                texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
                panel.add_child(texture)
            label_at(str(state), Vector2(105 + i * 228, 90 + row * 250), 16)
    await capture("cursor-assets.png")
    # Drive real hover/mode state, then independently inspect the resulting OS cursor.
    panel.visible = false
    root.grab_focus()
    await create_timer(0.5).timeout
    var run_id := Time.get_ticks_msec()
    for state: StringName in game.cursor_controller.STATES:
        game._clear_selection()
        game.attack_mode = false
        game.pending_command = ""
        var point := Vector2(780, 440)
        if state == &"select":
            point = game.sim.units[6].pos
        elif state in [&"move", &"attack", &"blocked"]:
            game.selected_units.assign([3])
        if state == &"attack":
            var key := InputEventKey.new()
            key.keycode = KEY_A
            key.pressed = true
            root.push_input(key, true)
        elif state == &"blocked":
            game._begin_pending("gather")
        root.warp_mouse(game._world_to_screen(point))
        await create_timer(0.2).timeout
        game.cursor_controller.update_cursor()
        if game.cursor_controller.current_state != state:
            print("CURSOR_CONTEXT screen=", root.get_mouse_position(), " expected_screen=", game._world_to_screen(point), " world=", game._screen_to_world(root.get_mouse_position()), " hovered=", root.gui_get_hovered_control(), " focus=", root.has_focus(), " map=", game._screen_is_map(root.get_mouse_position()))
            push_error("Real cursor state mismatch: %s != %s" % [game.cursor_controller.current_state, state])
            quit(1)
            return
        var probe := FileAccess.open("res://.godot/cursor-probe.json", FileAccess.WRITE)
        probe.store_string(JSON.stringify({"pid": OS.get_process_id(), "run": run_id, "state": state, "hotspot_x": game.cursor_controller.HOTSPOTS[state].x, "hotspot_y": game.cursor_controller.HOTSPOTS[state].y}))
        probe.close()
        # Allows the separate native cursor reader to observe all five states.
        await create_timer(3.0).timeout
    game.pending_command = ""
    game.attack_mode = false
    game.hud.visible = true
    game.cursor_controller.apply_state(&"default")
    var move := Marker.new()
    move.configure("move", Vector2(780, 440))
    game.add_child(move)
    var attack := Marker.new()
    attack.configure("attack_move", Vector2(880, 440))
    game.add_child(attack)
    for seconds in [0.0, 0.18, 0.35, 0.52, 0.70]:
        move.set_age(seconds)
        attack.set_age(seconds)
        await capture("destination-%03d.png" % roundi(seconds * 100))
    move.set_age(0.18)
    attack.set_age(0.18)
    game.camera_zoom_level = 1.3
    game.camera_controller.focus += Vector2(100, 80)
    game._update_camera_transform()
    await capture("destination-camera.png")
    move.free()
    attack.free()
    game.cursor_controller.restore_system_cursor()
    var probe := FileAccess.open("res://.godot/cursor-probe.json", FileAccess.WRITE)
    probe.store_string(JSON.stringify({"pid": OS.get_process_id(), "run": run_id, "state": "done"}))
    probe.close()
    game.queue_free()
    await process_frame
    print("CURSOR_RENDER_PREVIEW_PASS")
    quit(0)
