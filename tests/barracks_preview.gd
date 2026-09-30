extends SceneTree


func _initialize() -> void:
    run.call_deferred()


func run() -> void:
    root.size = Vector2i(1536, 1024)
    var game = preload("res://scenes/main.tscn").instantiate()
    game.selected_map_id = "desert_sample"
    root.add_child(game)
    game.set_process(false)
    game.play_solo()
    game.sim.ai_enabled = false
    game.sim.units.clear()
    game.sim.buildings.clear()
    var anchor := Vector2(2336, 1536)
    var id: int = game.sim._add_building(1, "barracks", anchor, true)
    game.sim._add_building(1, "base", anchor + Vector2(-210, 25), true)
    game.sim.rebuild_navigation()
    game.selected_building = id
    game.selected_buildings.assign([id])
    var error: String = game.sim.command(1, {"action": "produce", "building": id, "type": "soldier"})
    if not error.is_empty():
        push_error(error)
        quit(1)
        return
    game.camera_controller.focus = anchor + Vector2(-95, 0)
    game.camera_zoom_level = 2.4
    game._update_camera_transform()
    game._sync_visuals()
    var visual: EntityVisual = game.building_visuals[id].visual
    visual.animation_player.seek(0.83, true)
    if visual.animation_state != "active":
        push_error("New barracks does not respond to production")
        quit(1)
        return
    for tick in range(55):
        game.sim.step()
    if game.sim.units.size() != 1:
        push_error("Barracks production did not create a soldier")
        quit(1)
        return
    game._sync_visuals()
    if visual.animation_state != "idle":
        push_error("Barracks does not return to idle after production")
        quit(1)
        return
    game._refresh_ui()
    for frame in range(12):
        await process_frame
    await RenderingServer.frame_post_draw
    var result := root.get_texture().get_image().save_png("res://assets/concept_art/兵营模型-方案一-荒漠实机-v1.png")
    if result != OK:
        push_error("Unable to save barracks screenshot")
        quit(1)
        return
    print("BARRACKS_PREVIEW PASS actual production, idle return, base and soldier at unchanged gameplay scale")
    game.queue_free()
    await process_frame
    quit()
