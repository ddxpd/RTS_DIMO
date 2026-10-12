extends SceneTree
const MAIN = preload("res://scenes/main.tscn")
var failures: Array[String] = []
var checks := 0
var game
var view


func _initialize() -> void:
    run.call_deferred()


func check(condition: bool, message: String) -> void:
    checks += 1
    if not condition:
        failures.append(message)
        push_error(message)


func capture(tag: String) -> void:
    if DisplayServer.get_name() == "headless":
        return
    game._sync_visuals()
    game._refresh_ui()
    for i in range(3):
        await process_frame
    await RenderingServer.frame_post_draw
    var folder := "res://assets/concept_art/ui_selection/mechanical_hud/review"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
    check(root.get_texture().get_image().save_png(folder + "/" + tag + ".png") == OK, "Save " + tag)


func click(point: Vector2, pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.position = point
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    root.push_input(event, true)


func check_minimap_raster(minimap) -> void:
    if DisplayServer.get_name() == "headless":
        return
    var terrain: ImageTexture = minimap.terrain_texture
    var fog: ImageTexture = minimap.fog_texture
    var markers: Array[Dictionary] = minimap.markers.duplicate()
    var polygon: PackedVector2Array = minimap.view_polygon.duplicate()
    minimap.set_process(false)
    # Asymmetric world-space quadrants expose either an unflipped terrain or
    # an independently reversed fog layer in the actual CanvasItem rendering.
    var terrain_probe := Image.create(2, 2, false, Image.FORMAT_RGBA8)
    terrain_probe.set_pixel(0, 0, Color.WHITE)
    terrain_probe.set_pixel(1, 0, Color.RED)
    terrain_probe.set_pixel(0, 1, Color.GREEN)
    terrain_probe.set_pixel(1, 1, Color.BLUE)
    var fog_probe := Image.create(2, 2, false, Image.FORMAT_RGBA8)
    fog_probe.fill(Color.TRANSPARENT)
    fog_probe.set_pixel(0, 0, Color.BLACK)
    minimap.terrain_texture = ImageTexture.create_from_image(terrain_probe)
    minimap.fog_texture = ImageTexture.create_from_image(fog_probe)
    minimap.markers.clear()
    minimap.view_polygon.clear()
    minimap.queue_redraw()
    await process_frame
    await RenderingServer.frame_post_draw
    var rendered := root.get_texture().get_image()
    var rect: Rect2 = minimap.map_rect()
    var samples := [Vector2(0.25, 0.25), Vector2(0.75, 0.25), Vector2(0.25, 0.75), Vector2(0.75, 0.75)]
    var expected := [Color.BLUE, Color.GREEN, Color.RED, Color.BLACK]
    for i in range(samples.size()):
        var screen: Vector2 = minimap.get_global_transform_with_canvas() * (rect.position + rect.size * samples[i])
        var actual := rendered.get_pixelv(Vector2i(screen))
        var difference := Vector3(actual.r, actual.g, actual.b) - Vector3(expected[i].r, expected[i].g, expected[i].b)
        check(difference.length() < 0.08, "Rendered minimap terrain/fog quadrant %d: %s" % [i, actual])
    minimap.terrain_texture = terrain
    minimap.fog_texture = fog
    minimap.markers.assign(markers)
    minimap.view_polygon = polygon
    minimap.set_process(true)
    minimap.queue_redraw()


func run() -> void:
    root.size = Vector2i(1920, 1080)
    root.content_scale_size = Vector2i(1920, 1080)
    game = MAIN.instantiate()
    root.add_child(game)
    game.play_solo()
    game.set_process(false)
    game.sim.ai_enabled = false
    game.sim.units.clear()
    game.sim.buildings.clear()
    var spot := Vector2(1600, 1900)
    var soldier: int = game.sim.add_unit(1, "mobile_infantry", spot + Vector2(80, 30))
    var mobile: int = game.sim.add_unit(1, "mobile_infantry", spot + Vector2(170, 20))
    var miner: int = game.sim.add_unit(1, "harvester", spot + Vector2(-180, 30))
    var enemy: int = game.sim.add_unit(2, "mobile_infantry", spot + Vector2(380, 0))
    var barracks: int = game.sim._add_building(1, "barracks", spot + Vector2(0, -140), true)
    game.camera_controller.focus = spot
    game.camera_zoom_level = 1.0
    game._update_camera_transform()
    game.sim.visible[1].fill(1)
    game.sim.explored[1].fill(1)
    game._sync_visuals()
    game.selected_units.assign([soldier])
    game._refresh_ui()
    view = game.hud_controller.view
    await process_frame
    await process_frame
    check(view.current_kind == "mobile_infantry" and view.portrait.texture != null, "Soldier portrait and identity")
    check(view.health.value == 100 and view.health_text.text == "100 / 100", "Real HP, no concept placeholder")
    check(game.action_grid.get_child(0).action_id == "move", "Visual command order independent of dispatch index")
    var roster_id: int = game.roster_row.get_child(0).get_instance_id()
    var queue_id: int = game.production_queue_row.get_child(0).get_instance_id()
    for i in range(100):
        game._refresh_ui()
    check(roster_id == game.roster_row.get_child(0).get_instance_id() and queue_id == game.production_queue_row.get_child(0).get_instance_id(), "HUD reuses roster and queue nodes")
    game.sim.units[soldier].hp = 31
    game._refresh_ui()
    check(view.health.value == 31, "HP updates")
    game.sim.units[soldier].hp = 100
    await capture("soldier-1920")
    for id: int in [mobile, miner]:
        game.selected_units.assign([id])
        game._refresh_ui()
        check(view.portrait.texture == view.PORTRAITS[game.sim.units[id].type], "Correct unit portrait")
    game.sim.units[miner].cargo = 40
    game._refresh_ui()
    check(view.detail.text.contains("40 / 60"), "Miner cargo")
    game.selected_units.assign([soldier, miner])
    game._refresh_ui()
    check(game.roster_row.get_child_count() == 2 and view.title.text.contains("2"), "Mixed selection counts")
    check(not game.action_buttons[2].disabled and not game.action_buttons[3].disabled, "Mixed attack and gather remain available")
    await capture("mixed")
    game._clear_selection()
    game.selected_building = barracks
    game.selected_buildings.assign([barracks])
    var building: Dictionary = game.sim.buildings[barracks]
    building.queue = [{"type": "mobile_infantry", "remaining": 25}, {"type": "mobile_infantry", "remaining": 50}]
    game._refresh_ui()
    check(game.production_queue_row.get_child_count() == 5 and view.queue_tiles[0].texture != null and view.queue_tiles[2].texture == null, "Five stable production slots")
    check(game.production_bar.value == 25 and game.production_bar.max_value == 50, "Real production progress")
    check(game.action_buttons[2].disabled, "Takeoff disabled while producing")
    await capture("barracks-1920")
    for button: Button in game.action_buttons:
        if button.visible:
            check(view.command_frame.get_global_rect().encloses(button.get_global_rect()), "Two-row production button fits command frame")
    building.queue[0].remaining = 0
    game._refresh_ui()
    check(view.detail.text.contains("出口堵塞"), "Exit blocked feedback")
    building.queue.clear()
    for state: String in ["taking_off", "airborne", "landing", "grounded"]:
        building.flight.state = state
        game._refresh_ui()
        check(game.selection_label.text == view.FLIGHT[state], "Flight status " + state)
    building.remaining = 30
    game._refresh_ui()
    check(game.selection_label.text.contains("1.5"), "Construction seconds")
    building.remaining = 0
    for kind: String in ["base", "refinery", "bunker"]:
        var id: int = game.sim._add_building(1, kind, spot + Vector2(-300, -100), true)
        game.selected_building = id
        game.selected_buildings.assign([id])
        game._refresh_ui()
        check(view.current_kind == kind and view.portrait.texture == view.PORTRAITS[kind], "Building portrait " + kind)
        game.sim.buildings.erase(id)
    game._clear_selection()
    game._refresh_ui()
    check(view.portrait.texture == null and view.health.value == 0 and not game.production_bar.visible, "Empty selection clears previous info")
    game.selected_units.assign([soldier])
    game._refresh_ui()
    game.sim.units[soldier].hp = 0
    game._clean_selection()
    game._refresh_ui()
    check(view.current_kind.is_empty(), "Dead selection clears")
    game.sim.units[soldier].hp = 100
    var minimap = view.minimap
    minimap.refresh_intel()
    for point: Vector2 in [Vector2.ZERO, Vector2(2400, 1600), Vector2(4800, 3200)]:
        check(minimap.to_world(minimap.to_map(point)).distance_to(point) < 0.01, "Minimap coordinate roundtrip")
    var map_bounds: Rect2 = minimap.map_rect()
    check(minimap.to_map(Vector2.ZERO).is_equal_approx(map_bounds.end), "World origin is minimap bottom-right")
    check(minimap.to_world(map_bounds.position).is_equal_approx(game.sim.WORLD), "Minimap top-left selects world maximum")
    var ground := Vector3(spot.x, game.sim.terrain.height_at(spot), spot.y)
    for offset: Vector2 in [Vector2(64, 0), Vector2(-64, 0), Vector2(0, 64), Vector2(0, -64)]:
        var projected: Vector2 = game.camera.unproject_position(ground + Vector3(offset.x, 0, offset.y)) - game.camera.unproject_position(ground)
        var mapped: Vector2 = minimap.to_map(spot + offset) - minimap.to_map(spot)
        check(projected.normalized().dot(mapped.normalized()) > 0.99, "Minimap matches camera direction " + str(offset))
    await check_minimap_raster(minimap)
    game.sim.visible[1].fill(0)
    game.sim.explored[1].fill(0)
    minimap.refresh_intel()
    check(not minimap.markers.any(func(m): return m.pos == game.sim.units[enemy].pos), "Hidden enemies never appear")
    check(minimap.fog_image.get_pixel(0, 0).a > 0.99, "Unexplored terrain opaque")
    game.sim.explored[1].fill(1)
    minimap.refresh_intel()
    check(minimap.fog_image.get_pixel(0, 0).a > 0.5 and minimap.fog_image.get_pixel(0, 0).a < 0.7, "Explored fog dimmed")
    game.local_slot = 0
    minimap.refresh_intel()
    check(minimap.markers.any(func(m): return m.pos == game.sim.units[enemy].pos), "Spectator follows existing visibility rule")
    game.local_slot = 1
    game.sim.visible[1].fill(1)
    game.selected_units.assign([soldier])
    game._refresh_ui()
    await process_frame
    var destination: Vector2 = minimap.to_map(Vector2(2400, 1600))
    var screen: Vector2 = minimap.get_global_transform_with_canvas() * destination
    click(screen, true)
    check(minimap.dragging and not game.selection_dragging, "Minimap captures click, no battlefield box")
    check(game.camera_controller.focus.distance_to(Vector2(2400, 1600)) < 1, "Minimap camera positioning")
    var motion := InputEventMouseMotion.new()
    motion.position = minimap.get_global_transform_with_canvas() * minimap.to_map(Vector2(2600, 1700))
    root.push_input(motion, true)
    check(game.camera_controller.focus.distance_to(Vector2(2600, 1700)) < 1, "Minimap drag follows displayed world position")
    click(Vector2(800, 600), false)
    check(not minimap.dragging and not game.selection_dragging and game.selected_units == [soldier], "Drag release outside minimap preserves selection")
    check(game.sim.units[soldier].order == "idle", "Minimap never issues orders")
    game.camera_controller.focus = spot
    game._update_camera_transform()
    for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(2560, 1080)]:
        root.size = resolution
        root.content_scale_size = resolution
        await process_frame
        game._refresh_ui()
        await process_frame
        var rect: Rect2 = game._get_map_screen_rect()
        check(game._screen_is_map(Vector2(resolution.x - 15, resolution.y * 0.5)), "Right battlefield is clickable " + str(resolution))
        check(not game._screen_is_map(view.bottom.get_global_rect().get_center()), "Bottom HUD excluded " + str(resolution))
        check(rect.size.y / resolution.y > 0.70, "Compact battlefield height " + str(resolution))
        for card: Button in game.action_buttons:
            if card.visible:
                check(root.get_visible_rect().encloses(card.get_global_rect()), "Visible card fits " + str(resolution))
        await capture("resolution-%dx%d" % [resolution.x, resolution.y])
    var started := Time.get_ticks_usec()
    for i in range(100):
        game._refresh_ui()
    var hud_ms := (Time.get_ticks_usec() - started) / 100000.0
    started = Time.get_ticks_usec()
    for i in range(10):
        minimap.refresh_intel()
    var map_ms := (Time.get_ticks_usec() - started) / 10000.0
    print("HUD_TIMING refresh_ms=", hud_ms, " minimap_10hz_ms=", map_ms)
    check(hud_ms < 2.0 and map_ms < 10.0, "HUD and cached minimap update budgets")
    game.queue_free()
    await process_frame
    await process_frame
    print("MECHANICAL_HUD checks=", checks, " failures=", failures)
    quit(0 if failures.is_empty() else 1)
