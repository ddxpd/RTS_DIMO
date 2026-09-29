extends SceneTree

const MAIN = preload("res://scenes/main.tscn")
var game: Node3D
var failures: Array[String] = []

func _initialize() -> void:
    run.call_deferred()

func check(value: bool, message: String) -> void:
    if not value:
        failures.append(message)
        push_error(message)

func capture(filename: String, focus: Vector2, zoom: float) -> void:
    game.camera_controller.focus = focus
    game.camera_zoom_level = zoom
    game._update_camera_transform()
    game._sync_visuals()
    for frame in range(8):
        await process_frame
    await RenderingServer.frame_post_draw
    var image := root.get_texture().get_image()
    check(image.save_png("res://assets/concept_art/" + filename) == OK, "Save " + filename)

func run() -> void:
    root.size = Vector2i(1920, 1080)
    game = MAIN.instantiate()
    root.add_child(game)
    game.set_process(false)
    check(game.selected_map_id == "desert_quarry", "Menu defaults to desert")
    check(game.map_selector.item_count == 3, "Menu lists both maps and temporary sample")
    game.play_solo()
    game.sim.ai_enabled = false
    game.local_slot = 0
    game._sync_map_world()
    game._sync_visuals()
    check(game.terrain_view != null and not game.fog_plane.visible, "Desert uses terrain material fog")
    var id: int = game.sim.add_unit(1, "soldier", Vector2(1536, 1088))
    game.selected_units.assign([id])
    game._sync_visuals()
    check(is_equal_approx(game.unit_visuals[id].visual.position.y, 96.0), "Unit stands on plateau")
    game.camera_controller.focus = Vector2(1536, 1088)
    game.camera_zoom_level = 1.0
    game._update_camera_transform()
    for point: Vector2 in [Vector2(1536, 1088), Vector2(1024, 1088), Vector2(1400, 1200)]:
        var round_trip: Vector2 = game._screen_to_world(game._world_to_screen(point))
        check(round_trip.distance_to(point) < 1.0, "Pick surface at " + str(point))
    game.camera_controller.focus = Vector2(3808, 704)
    game._update_camera_transform()
    var floor_point := Vector2(3936, 704)
    check(game._screen_to_world(game._world_to_screen(floor_point)).distance_to(floor_point) < 1.0, "Pick quarry floor")
    var slope_point := Vector2(1024, 1088)
    var rotation: Vector3 = game.visual_sync._surface_rotation(slope_point)
    var expected_normal := Vector3(-0.25, 1.0, 0).normalized()
    check((Basis.from_euler(rotation) * Vector3.UP).dot(expected_normal) > 0.999, "Markers align with ramp normal")
    var view: Node3D = game.terrain_view
    game.restart_match()
    game._sync_visuals()
    check(game.terrain_view == view and game.sim.map_id == "desert_quarry", "Restart keeps map without duplicating static mesh")
    game.return_to_title()
    game._map_selected(1)
    game.play_solo()
    game._sync_visuals()
    check(game.sim.map_id == "prototype" and game.terrain_view == null and game.fog_plane.visible, "Switch to prototype clears desert")
    game.return_to_title()
    game._map_selected(0)
    game.play_solo()
    game.sim.ai_enabled = false
    game.local_slot = 0
    game._sync_map_world()
    game._sync_visuals()
    if "--screenshot" in OS.get_cmdline_args():
        game.hud.visible = false
        await capture("desert-quarry-overview.png", Vector2(2400, 1600), 0.29)
        await capture("desert-quarry-highland.png", Vector2(1320, 1088), 0.72)
        await capture("desert-quarry-pit.png", Vector2(3808, 704), 0.72)
        game.hud.visible = true
        game.local_slot = 1
        game._sync_map_world()
        await capture("desert-quarry-gameplay.png", Vector2(740, 610), 1.0)
    print("TERRAIN_PRESENTATION ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
    game.queue_free()
    await process_frame
    quit(0 if failures.is_empty() else 1)
