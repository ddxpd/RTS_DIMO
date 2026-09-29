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


func capture(name: String, focus: Vector2, zoom: float) -> void:
    game.camera_controller.focus = focus
    game.camera_zoom_level = zoom
    game._update_camera_transform()
    game._sync_visuals()
    for i in range(10):
        await process_frame
    await RenderingServer.frame_post_draw
    var shot := root.get_texture().get_image()
    check(shot.save_png("res://assets/concept_art/sample-" + name + "-v1.png") == OK, "Save screenshot")
    if name == "overview":
        check(shot.save_png("res://assets/maps/sample/preview.png") == OK, "Save runtime preview copy")


func frame_measure(label: String) -> void:
    for i in range(30):
        await process_frame
    var times: Array[float] = []
    var last := Time.get_ticks_usec()
    for i in range(120):
        await process_frame
        var now := Time.get_ticks_usec()
        times.append((now - last) / 1000.0)
        last = now
    times.sort()
    var sum := 0.0
    for value in times:
        sum += value
    print("SAMPLE_RENDER ", label, " mean_ms=", sum / times.size(), " p95_ms=", times[int(times.size() * 0.95)], " units=", game.sim.units.size())


func run() -> void:
    root.size = Vector2i(1920, 1080)
    game = MAIN.instantiate()
    game.selected_map_id = "desert_sample"
    root.add_child(game)
    game.set_process(false)
    check(game.map_selector.item_count == 3, "Temporary menu entry")
    check(game.sample_host_button.disabled, "Sample cannot host LAN")
    check(ResourceLoader.exists("res://assets/maps/sample/preview.png"), "Sample preview is an imported runtime asset")
    for kind in ["sand", "soil", "gravel", "rock"]:
        for channel in ["color", "nr"]:
            var texture: Texture2D = load("res://assets/maps/sample/" + kind + "_" + channel + ".png")
            check(texture.get_image().has_mipmaps(), "Terrain texture has mipmaps: " + kind + "_" + channel)
    game.create_host()
    check(not game.connected, "Direct host call rejected before creating server")
    game.play_solo()
    game._sync_visuals()
    check(game.sim.is_test_map() and game.local_slot == 1, "Sample is controllable")
    check(game.terrain_view != null and not game.fog_plane.visible, "Sample geometry active")
    for point: Vector2 in [Vector2(1766,1922), Vector2(1876,1442), Vector2(3016,1782), Vector2(2876,1442)]:
        game.camera_controller.focus = point
        game.camera_zoom_level = 1.5
        game._update_camera_transform()
        check(game._screen_to_world(game._world_to_screen(point)).distance_to(point) < 1.0, "Fine terrain pick round trip %s" % point)
    await preload("res://tests/soldier_heading_checks.gd").routes(game, check, "--heading-capture" in OS.get_cmdline_args())
    var view: Node3D = game.terrain_view
    game.restart_match()
    game._sync_visuals()
    check(game.terrain_view == view and game.sim.units.size() == 7 and game.sim.money[1] == 10000, "Restart resets roster without mesh duplication")
    game.return_to_title()
    game._map_selected(1)
    check(not game.network_session._apply_snapshot_checked(game.sim.snapshot(), "test"), "Network RPC path rejects sample snapshots")
    await process_frame
    check(not game.sample_host_button.disabled, "LAN restored for normal map")
    game.play_solo()
    game._sync_visuals()
    check(not game.sim.is_test_map() and game.terrain_view == null and game.sim.ai_enabled, "Normal map restores simulation and visuals")
    game.return_to_title()
    game._map_selected(2)
    game.play_solo()
    game._sync_visuals()
    if "--capture" in OS.get_cmdline_args():
        game.hud.visible = false
        await capture("overview", Vector2(2356,1592), 0.54)
        await capture("highland", Vector2(1826,1792), 1.15)
        await capture("cliff", Vector2(1596,1852), 2.0)
        await capture("quarry", Vector2(2876,1672), 1.10)
        await capture("materials", Vector2(2306,1462), 2.8)
        game.hud.visible = true
        await capture("gameplay", Vector2(2076,1382), 0.85)
        await frame_measure("initial")
        while game.sim.units.size() < 180:
            var i: int = game.sim.units.size()
            var p := Vector2(2116 + (i % 10) * 34, 1342 + int(i / 10) * 34)
            p = game.sim.nav.get_point_position(game.sim.nearest_cell(p))
            game.sim.add_unit(1, "harvester" if i % 4 == 0 else "soldier", p)
        game._sync_visuals()
        await frame_measure("180-static")
        var started := Time.get_ticks_usec()
        for tick in range(40):
            game.sim.step()
        print("SAMPLE_CPU_180 mean_tick_ms=", (Time.get_ticks_usec() - started) / 40000.0)
        game.set_process(true)
        await frame_measure("180-active")
        game.set_process(false)
    if "--capture" in OS.get_cmdline_args() or "--menu-capture" in OS.get_cmdline_args():
        game.restart_match()
        game.return_to_title()
        game.hud.visible = true
        await capture("menu", Vector2(2356,1592), 0.54)
    print("TERRAIN_SAMPLE_VIEW ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
    game.queue_free()
    await process_frame
    quit(0 if failures.is_empty() else 1)
