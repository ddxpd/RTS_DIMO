extends RefCounted

const Marker = preload("res://scripts/ui/destination_marker.gd")


static func presentation(game, check: Callable) -> void:
    game.play_solo()
    game.set_process(false)
    game.sim.ai_enabled = false
    game.attack_mode = false
    game.pending_command = ""
    game.camera_controller.focus = Vector2(640, 400)
    game._update_camera_transform()
    var cursor = game.cursor_controller
    var ground := Vector2(800, 450)
    var screen: Vector2 = game._world_to_screen(ground)
    check.call(cursor.state_at(screen) == &"default", "Empty selection uses default cursor")
    check.call(cursor.world_state(game.sim.units[3].pos) == &"select", "Friendly hover selects")
    game.selected_units.assign([3])
    check.call(cursor.state_at(screen) == &"move", "Selected unit uses move on ground")
    game.attack_mode = true
    check.call(cursor.state_at(screen) == &"attack", "Attack mode uses blade cross on ground")
    check.call(cursor.world_state(game.sim.units[4].pos) == &"attack", "Force attack overrides friendly select")
    check.call(cursor.state_at(screen, true) == &"default", "HUD overrides attack mode")
    check.call(cursor.state_at(Vector2(10, 10)) == &"default", "Top UI never has a combat cursor")
    game.menu_visible = true
    check.call(cursor.state_at(screen) == &"default", "Menu restores default")
    game.menu_visible = false
    game.local_slot = 0
    check.call(cursor.state_at(screen) == &"default", "Spectator never sees a command cursor")
    game.local_slot = 1
    game.sim.winner = 1
    check.call(cursor.state_at(screen) == &"default", "Finished match has default cursor")
    game.sim.winner = 0
    game.selected_units.clear()
    check.call(cursor.state_at(screen) == &"blocked", "No selected units blocks explicit attack")
    game.selected_units.assign([3])
    game.pending_command = "move"
    check.call(cursor.state_at(screen) == &"move", "Pending command takes priority over stale attack mode")
    game.pending_command = ""
    game.attack_mode = false
    game.sim.units[9].pos = ground
    game.sim.visible[1].fill(0)
    check.call(cursor.state_at(screen) == &"move", "Hidden enemy cannot reveal itself through cursor")
    check.call(cursor.target_at(ground).is_empty(), "Hidden enemy excluded from hover hit result")
    game.sim.visible[1].fill(1)
    check.call(cursor.state_at(screen) == &"attack", "Visible enemy uses attack")
    game.sim.units[3].type = "harvester"
    check.call(cursor.state_at(screen) == &"blocked", "Noncombat unit cannot directly attack")
    game.attack_mode = true
    game.sim.visible[1].fill(0)
    check.call(cursor.state_at(screen) == &"attack", "Harvester attack-move ground behavior remains unchanged without leaking hidden enemies")
    game.attack_mode = false
    game.pending_command = "gather"
    check.call(cursor.world_state(game.sim.ores[1].pos) == &"move", "Valid gather retains move appearance")
    check.call(cursor.world_state(Vector2(800, 500)) == &"blocked", "Gather without ore is blocked")
    game.sim.units[3].type = "soldier"
    check.call(cursor.world_state(game.sim.ores[1].pos) == &"blocked", "Soldier cannot gather")
    game.pending_command = ""
    game.build_mode = "base"
    check.call(cursor.world_state(game.sim.buildings[1].pos) == &"blocked", "Occupied build footprint is blocked")
    check.call(cursor.world_state(Vector2(160, 384)) == &"default", "Valid build keeps default alongside preview")
    game.build_mode = ""
    check.call(cursor.world_state(Vector2(-10, -10)) == &"blocked", "Outside map blocks pending movement")
    game._clear_selection()
    game.selected_building = 1
    check.call(cursor.world_state(ground) == &"move", "Building selection offers rally cursor")
    game._clear_selection()
    game.selected_units.assign([3])
    game.clicks.clear()
    game._show_order_feedback({"action": "attack", "units": [3]}, ground)
    check.call(game.clicks.size() == 1 and is_equal_approx(game.clicks[0].duration, 0.70), "Direct attack receives timed red feedback")
    game.clicks.clear()
    game._show_order_feedback({"action": "move", "units": []}, ground)
    game._show_order_feedback({"action": "gather", "units": [3]}, ground)
    game._show_order_feedback({"action": "move", "units": [3]}, Vector2(-1, 0))
    game.menu_visible = true
    game._show_order_feedback({"action": "move", "units": [3]}, ground)
    game.menu_visible = false
    check.call(game.clicks.is_empty(), "Empty/incompatible selection, outside map and UI produce no success marker")
    for index in range(20):
        game._show_order_feedback({"action": "move", "units": [3]}, ground + Vector2(index * 2, 0))
    check.call(game.clicks.size() == 16, "Feedback queue retains at most sixteen intents")
    check.call(int(game.clicks.back().id) - int(game.clicks.front().id) == 15, "Click IDs remain monotonically stable")
    game.clicks.clear()
    game.pending_command = "move"
    game._pending_click(Vector2(800, 500))
    check.call(game.clicks.size() == 1 and game.clicks[0].action == "move", "Action-bar pending move shares feedback path")
    game._clear_selection()
    game.selected_building = 1
    game._right_click(Vector2(800, 500))
    check.call(game.clicks.back().action == "rally" and is_equal_approx(game.clicks.back().duration, 0.55), "Rally keeps legacy duration")
    game.clicks.clear()
    cursor.apply_state(&"attack")
    var calls: int = cursor.hardware_updates
    cursor.apply_state(&"attack")
    check.call(cursor.hardware_updates == calls, "Unchanged state does not upload cursor every frame")
    cursor._focus_exited()
    check.call(cursor.current_state == &"default", "Focus loss clears combat cursor")
    cursor.restore_system_cursor()
    check.call(cursor.current_state == &"", "Scene cleanup clears cursor registration cache")
    cursor.apply_state(&"default")


static func visual(game, check: Callable) -> void:
    var cursor = game.cursor_controller
    for state: StringName in cursor.STATES:
        var texture: Texture2D = cursor.textures[state]
        check.call(texture != null and texture.get_size() == Vector2(40, 40), "Cursor asset is 40x40: " + state)
        if texture == null:
            continue
        var image := texture.get_image()
        check.call(image.detect_alpha() != Image.ALPHA_NONE, "Cursor preserves real alpha: " + state)
        check.call(image.get_pixel(0, 0).a < 0.05 and image.get_pixel(39, 39).a < 0.05, "Cursor has no opaque rectangular background: " + state)
        check.call(Rect2(Vector2.ZERO, Vector2(40, 40)).has_point(cursor.HOTSPOTS[state]), "Cursor hotspot inside canvas: " + state)
    check.call(cursor.HOTSPOTS[&"attack"] == Vector2(20, 20), "Blade cross uses center aiming point")
    var move := Marker.new()
    move.configure("move", Vector2(800, 450))
    game.add_child(move)
    var attack := Marker.new()
    attack.configure("attack_move", Vector2(820, 500))
    game.add_child(attack)
    check.call(move.symbol.mesh != attack.symbol.mesh, "Move and attack have different geometric silhouettes")
    var move_colors: PackedColorArray = move.symbol.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
    var attack_colors: PackedColorArray = attack.symbol.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
    check.call(move_colors.has(Marker.MOVE_COLOR) and attack_colors.has(Marker.ATTACK_COLOR), "Destination palettes are blue and red")
    check.call(move.symbol.mesh.get_aabb().size.y < 0.1 and move.rotation == Vector3.ZERO, "Geometry lies flat on XZ, not a billboard")
    check.call(move.symbol.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and not move.material.no_depth_test, "Marker casts no shadow and retains depth occlusion")
    check.call(is_equal_approx(move.diameter, 64.0), "Click starts at 64 world units")
    move.set_age(0.18)
    check.call(move.diameter > 32.0 and move.diameter < 64.0 and is_equal_approx(move.opacity, 1.0), "Converge shrinks without fading")
    move.set_age(0.35)
    check.call(is_equal_approx(move.diameter, 32.0), "Confirmation reaches 32 world units")
    move.set_age(0.52)
    check.call(move.opacity > 0.0 and move.opacity < 1.0, "After confirmation fades")
    check.call(move.position == Vector3(800, 1.5, 450), "Animation never moves the destination center")
    move.set_age(0.70)
    check.call(not move.visible and is_zero_approx(move.opacity), "Marker fully invisible by 0.7 seconds")
    check.call(is_equal_approx(attack.material.albedo_color.a, 1.0), "Fading one marker does not fade another")
    move.free()
    attack.free()

    game.play_solo()
    game.set_process(false)
    game.sim.ai_enabled = false
    game.selected_units.assign([3])
    game._show_order_feedback({"action": "move", "units": [3]}, Vector2(800, 450))
    game._show_order_feedback({"action": "attack_move", "units": [3]}, Vector2(900, 450))
    game._sync_markers()
    var key := "click_%d" % int(game.clicks.back().id)
    var retained: Node3D = game.marker_visuals[key]
    game.clicks.pop_front()
    game._sync_markers()
    check.call(game.marker_visuals[key] == retained and retained.position == Vector3(900, 1.5, 450), "Expiring earlier click never rebinds or moves another visual")
    game.clicks.clear()
    game._sync_markers()
    check.call(game.marker_visuals.is_empty(), "Expired clicks release every visual")
