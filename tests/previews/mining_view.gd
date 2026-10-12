extends SceneTree
const MAIN = preload("res://scenes/main.tscn")
const Sim = preload("res://scripts/simulation.gd")
var game
var failures: Array[String] = []

func _initialize() -> void:
    run.call_deferred()

func check(ok: bool, message: String) -> void:
    if not ok:
        failures.append(message)
        push_error(message)

func capture(name_value: String) -> void:
    game._sync_visuals(0.05)
    game._refresh_ui()
    for i in range(5):
        await process_frame
    if DisplayServer.get_name() != "headless":
        await RenderingServer.frame_post_draw
        var folder := "res://assets/concept_art/ui_selection/mechanical_hud/mining_grid_review"
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
        check(root.get_texture().get_image().save_png(folder + "/" + name_value + ".png") == OK, "Save review screenshot")

func run() -> void:
    root.size = Vector2i(1920, 1080)
    root.content_scale_size = root.size
    game = MAIN.instantiate()
    game.selected_map_id = "desert_sample"
    root.add_child(game)
    game.play_solo()
    game.set_process(false)
    var sim = game.sim
    sim.ores[1] = {"pos": Vector2(1776, 1712), "amount": 10000}
    sim._add_building(1, "refinery", Vector2(2336, 1200), true)
    sim.rebuild_navigation()
    var ids: Array = []
    for i in range(6):
        ids.append(sim.add_unit(1, "harvester", Vector2(1840 + (i % 2) * 112, 1168 + (i / 2) * 112)))
    sim.command(1, {"action": "gather", "units": ids, "target": 1})
    sim.step()
    game.camera_controller.focus = Vector2(1840, 1550)
    game.camera_zoom_level = 1.3
    game._update_camera_transform()
    game._sync_visuals()
    game._left_click(sim.ores[1].pos)
    check(game.selected_ore == 1, "Crystal click selection")
    await capture("five-reservations-one-waiter")
    check(game.selection_label.text.contains("5/5") and game.selection_label.text.contains("1"), "Crystal capacity in HUD")
    var seen_work := false
    var checked_wait := false
    for tick in range(650):
        sim.step()
        if not checked_wait and sim.units[ids[5]].mining.phase == "wait":
            game._clear_selection()
            game.selected_units.append(ids[5])
            game._sync_visuals()
            game._refresh_ui()
            check(game.selection_label.text == "等待采矿名额", "Waiting unit HUD")
            check(game.visual_sync._unit_animation_state(sim.units[ids[5]]) != "mine", "Waiter never plays mining animation")
            checked_wait = true
        for id: int in ids:
            if sim.units[id].get("mining", {}).get("phase", "") == "work" and not seen_work:
                game._clear_selection()
                game.selected_units.append(id)
                game._sync_visuals()
                check(game.visual_sync._unit_animation_state(sim.units[id]) == "mine", "Authoritative work animation")
                await capture("slope-mining")
                seen_work = true
    check(seen_work and checked_wait, "Both real mining and queue observed")
    game._clear_selection()
    game._left_click(sim.ores[1].pos)
    await capture("slope-circulation")
    game.audio_controller.reset_state()
    game.queue_free()
    await process_frame
    await create_timer(0.1).timeout
    print("MINING_VIEW failures=", failures)
    quit(0 if failures.is_empty() else 1)
