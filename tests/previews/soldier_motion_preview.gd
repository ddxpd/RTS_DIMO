extends SceneTree


func _initialize() -> void:
    run.call_deferred()


func run() -> void:
    var output := "res://assets/concept_art/"
    if "--vertical-carry" in OS.get_cmdline_args():
        output = "res://assets/concept_art/soldier_vertical_carry/game/"
    if "--clear-run" in OS.get_cmdline_args():
        output = "res://assets/concept_art/soldier_clear_run/game/"
    DirAccess.make_dir_recursive_absolute(output)
    root.size = Vector2i(1280, 900)
    var game = preload("res://scenes/main.tscn").instantiate()
    game.selected_map_id = "desert_sample"
    root.add_child(game)
    game.set_process(false)
    game.play_solo()
    game.sim.units.clear()
    game._sync_units()
    var id: int = game.sim.add_unit(1, "soldier", Vector2(2130, 1410))
    game.sim.command(1, {"action": "move", "units": [id], "pos": Vector2(2360, 1560)})
    var version := "before" if "--before" in OS.get_cmdline_args() else "after"
    game.hud.visible = false
    for frame in range(100):
        game._process(1.0 / 60.0)
        var v = game.unit_visuals[id].visual
        game.camera_controller.focus = Vector2(v.position.x, v.position.z)
        game.camera_zoom_level = 4.0
        game._update_camera_transform()
        await process_frame
        if frame in [12, 20, 28, 36, 44, 90]:
            await RenderingServer.frame_post_draw
            var path := output + "heavy-soldier-%s-%03d.png" % [version, frame]
            assert(root.get_texture().get_image().save_png(path) == OK)
    if version == "after":
        for route: String in ["front", "highland", "quarry", "return", "turn-stop", "curve"]:
            game.sim.units.clear()
            game._sync_units()
            var start := Vector2(2230, 1450)
            var target := Vector2(2040, 1300)
            if route == "highland":
                start = Vector2(1876, 1280)
                target = Vector2(1876, 1810)
            elif route in ["quarry", "return"]:
                start = Vector2(2876, 1280 if route == "quarry" else 1670)
                target = Vector2(2876, 1750 if route == "quarry" else 1230)
            elif route == "curve":
                start = Vector2(2350, 1450)
                target = Vector2(2340, 1500)
            id = game.sim.add_unit(1, "soldier", start)
            game.sim.command(1, {"action": "move", "units": [id], "pos": target})
            var min_pelvis := INF
            var max_pelvis_drop := 0.0
            var last_pelvis := 1.24
            for frame in range(180):
                if route == "curve" and frame % 15 == 0:
                    var angle := (frame + 30) / 60.0 * 100.0 / 120.0
                    target = Vector2(2230, 1450) + Vector2(cos(angle), sin(angle)) * 120.0
                    game.sim.command(1, {"action": "move", "units": [id], "pos": target})
                if route == "turn-stop" and frame == 60:
                    game.sim.command(1, {"action": "move", "units": [id], "pos": Vector2(2400, 1500)})
                if route == "turn-stop" and frame == 120:
                    game.sim.units[id].order = "idle"
                    game.sim.units[id].path = []
                game._process(1.0 / 60.0)
                var v = game.unit_visuals[id].visual
                if route == "curve":
                    var m = v.soldier_motion
                    var pelvis: float = m.skeleton.get_bone_global_pose(m.bones.Pelvis).origin.y
                    if frame > 30:
                        min_pelvis = minf(min_pelvis, pelvis)
                        max_pelvis_drop = maxf(max_pelvis_drop, last_pelvis - pelvis)
                    last_pelvis = pelvis
                game.camera_controller.focus = Vector2(v.position.x, v.position.z)
                game._update_camera_transform()
                if route == "front":
                    game.camera.position = v.position + Vector3(85, 63, -150)
                    game.camera.look_at(v.position + Vector3(0, 34, 0))
                await process_frame
                if frame in [40, 70, 95, 119, 128, 145]:
                    await RenderingServer.frame_post_draw
                    assert(root.get_texture().get_image().save_png(output + "heavy-soldier-%s-%03d.png" % [route, frame]) == OK)
            if route == "curve":
                print("GAME_CURVED_GAIT min_pelvis=", min_pelvis, " max_drop=", max_pelvis_drop)
                if min_pelvis < .95 or max_pelvis_drop > .08:
                    push_error("Actual game route collapses the soldier pelvis")
                    quit(1)
                    return
        # Real rendered moving-unit load, separate from headless CPU timings.
        game.sim.units.clear()
        game._sync_units()
        for i in range(180):
            var p := Vector2(2020 + (i % 15) * 36, 1130 + int(i / 15.0) * 36)
            var unit: int = game.sim.add_unit(1, "soldier", p)
            game.sim.command(1, {"action": "move", "units": [unit], "pos": p + Vector2(0, 180)})
        game.camera_zoom_level = .8
        game.camera_controller.focus = Vector2(2150, 1300)
        game._update_camera_transform()
        var times: Array[float] = []
        var cpu_times: Array[float] = []
        for frame in range(150):
            var began := Time.get_ticks_usec()
            game._process(1.0 / 60.0)
            var cpu := (Time.get_ticks_usec() - began) / 1000.0
            await process_frame
            if frame > 29:
                times.append((Time.get_ticks_usec() - began) / 1000.0)
                cpu_times.append(cpu)
        times.sort()
        var mean := 0.0
        for value in times:
            mean += value
        var cpu_mean := 0.0
        for value in cpu_times:
            cpu_mean += value
        print("HEAVY_RENDER_180 mean_ms=", mean / times.size(), " p95_ms=", times[int(times.size() * .95)], " game_cpu_ms=", cpu_mean / cpu_times.size())
    print("SOLDIER_PREVIEW PASS ", version)
    game.queue_free()
    await process_frame
    quit()
