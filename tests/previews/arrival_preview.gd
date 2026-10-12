extends SceneTree


func _initialize() -> void:
    run.call_deferred()


func run() -> void:
    root.size = Vector2i(1440, 960)
    var game = preload("res://scenes/main.tscn").instantiate()
    game.selected_map_id = "desert_sample"
    root.add_child(game)
    game.set_process(false)
    game.play_solo()
    game.sim.units.clear()
    game._sync_units()
    var ids: Array[int] = []
    for i in range(6):
        ids.append(game.sim.add_unit(1, "soldier", Vector2(1810 + i * 26, 1400)))
    game.selected_units.assign(ids)
    game.camera_controller.focus = Vector2(1740, 1850)
    game.camera_zoom_level = 1.6
    game._update_camera_transform()
    game._sync_visuals()
    var click := Vector2(1600, 1882)
    var screen: Vector2 = game._world_to_screen(click)
    var picked: Vector2 = game._screen_to_world(screen)
    if picked.distance_to(click) > 2:
        push_error("Highland edge screen pick missed its surface")
        quit(1)
        return
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_RIGHT
    event.pressed = true
    event.position = screen
    game._unhandled_input(event)
    for id: int in ids:
        if not game.sim.units[id].has("arrival"):
            push_error("Right click did not issue formation command")
            quit(1)
            return
    for frame in range(2100):
        game._process(1.0 / 60.0)
        await process_frame
        var done := true
        for id: int in ids:
            done = done and game.sim.units[id].order == "idle"
        if done or frame == 600:
            if done:
                for settle in range(20):
                    game._process(1.0 / 60.0)
                    await process_frame
            await RenderingServer.frame_post_draw
            root.get_texture().get_image().save_png("res://assets/concept_art/highland-edge-%s.png" % ("arrived" if done else "approach"))
        if done:
            var region: int = game.sim.terrain.arrival_region_at(picked)
            for id: int in ids:
                if game.sim.terrain.arrival_region_at(game.sim.units[id].pos) != region:
                    push_error("Soldier stopped on another level")
                    quit(1)
                    return
            print("ARRIVAL_PREVIEW PASS six units on clicked platform; frame=", frame)
            game.queue_free()
            await process_frame
            quit()
            return
    push_error("Formation did not finish its actual route")
    quit(1)
