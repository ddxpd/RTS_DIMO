extends SceneTree
const MAIN = preload("res://scenes/main.tscn")
const Hit = preload("res://assets/art/effects/mobile_hit_effect.gd")
var game
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
    run.call_deferred()


func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)


func capture(tag: String) -> void:
    game._sync_visuals(0.0)
    game._refresh_ui()
    for frame in range(4):
        await process_frame
    if DisplayServer.get_name() != "headless":
        await RenderingServer.frame_post_draw
        var folder := "res://assets/concept_art/mobile_infantry/size_075_review"
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
        check(root.get_texture().get_image().save_png(folder + "/" + tag + ".png") == OK, "Save " + tag)


func run() -> void:
    root.size = Vector2i(1920, 1080)
    root.content_scale_size = root.size
    game = MAIN.instantiate()
    game.selected_map_id = "desert_sample"
    root.add_child(game)
    game.play_solo()
    game.set_process(false)
    var sim = game.sim
    sim.ai_enabled = false
    sim.units.clear()
    sim._add_building(1, "bunker", Vector2(1952, 1056), true)
    sim._add_building(1, "bunker", Vector2(2048, 1056), true)
    sim._add_building(1, "barracks", Vector2(2256, 1408), true)
    var mobile: int = sim.add_unit(1, "mobile_infantry", Vector2(2000, 1264))
    var soldier: int = sim.add_unit(1, "soldier", Vector2(2100, 1264))
    var miner: int = sim.add_unit(1, "harvester", Vector2(1840, 1264))
    sim.rebuild_navigation()
    game.selected_units.assign([mobile, soldier, miner])
    game.camera_controller.focus = Vector2(2016, 1264)
    game.camera_zoom_level = 1.3
    game._update_camera_transform()
    game._sync_visuals(0.05)
    var actor = game.visual_sync.unit_visuals[mobile].visual
    check(is_equal_approx(actor._selection_ring_radius, 15.0), "Actual selected ring radius is 15")
    check(is_equal_approx(actor.SELECTION_RING_WIDTH, game.visual_sync.unit_visuals[soldier].visual.SELECTION_RING_WIDTH), "Ring widths remain uniform")
    var health: Dictionary = game.visual_sync.health_grid_overlay.entries["unit_%d" % mobile]
    check(absf(health.world_position.y - actor.global_position.y - 57.333333) < 0.001, "Actual health bar follows reduced height")
    await capture("comparison")
    sim.command(1, {"action": "move", "units": [mobile], "pos": Vector2(2000, 944)})
    var passage_captured := false
    for tick in range(90):
        sim.step()
        game._sync_visuals(0.05)
        if not passage_captured and absf(sim.units[mobile].pos.y - 1056) < 8:
            check(actor.mobile_motion.clip == "jog", "Full-speed narrow passage plays scaled jog")
            game.camera_controller.focus = Vector2(2000, 1056)
            game._update_camera_transform()
            await capture("one-cell-passage")
            passage_captured = true
    check(passage_captured and sim.units[mobile].pos.distance_to(Vector2(2000, 944)) < 8, "Actual traversal completes")
    sim.units[mobile].pos = Vector2(2000, 1264)
    var enemy: int = sim.add_unit(2, "mobile_infantry", Vector2(2000, 1376))
    sim.visible[1].fill(1)
    sim.explored[1].fill(1)
    sim.units[mobile].order = "attack"
    sim.units[mobile].attack_kind = "unit"
    sim.units[mobile].attack_id = enemy
    sim.units[mobile].cooldown = 0
    sim._fight(sim.units[mobile])
    game.accumulator = 0.0
    game._sync_visuals(0.05)
    check(not sim.effects.is_empty(), "Reduced infantry still makes immediate hits")
    for effect in game.visual_sync.effect_visuals.values():
        if effect is Hit:
            check(effect.muzzle.visible and effect.muzzle.global_position.is_equal_approx(effect.muzzle_socket.global_position), "Flash stays on scaled muzzle socket")
            check(is_equal_approx(effect.muzzle.pixel_size * 32, 8.0), "Gun flash scales with gun")
    game._clear_selection()
    game.selected_units.append(mobile)
    game.camera_controller.focus = Vector2(2000, 1320)
    game.camera_zoom_level = 2.0
    game._update_camera_transform()
    game._sync_visuals(0.05)
    await capture("fire-close")
    game.audio_controller.reset_state()
    game.queue_free()
    await process_frame
    print("MOBILE_SIZE_VIEW checks=", checks, " failures=", failures)
    quit(0 if failures.is_empty() else 1)
