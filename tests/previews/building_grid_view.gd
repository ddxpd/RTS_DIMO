extends SceneTree
const MAIN = preload("res://scenes/main.tscn")
var game
var failures: Array[String] = []


func _initialize() -> void:
    run.call_deferred()


func check(ok: bool, message: String) -> void:
    if not ok:
        failures.append(message)
        push_error(message)


func capture(label: String) -> void:
    for index in range(4):
        await process_frame
    if DisplayServer.get_name() != "headless":
        await RenderingServer.frame_post_draw
        var folder := "res://assets/concept_art/ui_selection/mechanical_hud/grid_alignment_review"
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
        check(root.get_texture().get_image().save_png(folder + "/" + label + ".png") == OK, "Save " + label)


func run() -> void:
    root.size = Vector2i(1920, 1080)
    root.content_scale_size = root.size
    game = MAIN.instantiate()
    root.add_child(game)
    game.play_solo()
    game.set_process(false)
    var sim = game.sim
    sim.ai_enabled = false
    sim.units.clear()
    sim.buildings.clear()
    sim.ores.clear()
    sim.obstacles.clear()
    sim.money[1] = 10000
    sim.visible[1].fill(1)
    sim.explored[1].fill(1)
    var base: int = sim._add_building(1, "base", Vector2(2080, 1888), true)
    var barracks: int = sim._add_building(1, "barracks", Vector2(2304, 1840), true)
    var refinery: int = sim._add_building(1, "refinery", Vector2(2096, 2144), true)
    sim.rebuild_navigation()
    game.camera_controller.focus = Vector2(2150, 1960)
    game.camera_zoom_level = 1.05
    game._update_camera_transform()
    game._refresh_ui()
    game._sync_visuals()
    var site := Vector2(2304, 1936)
    game._begin_build("barracks")
    game.visual_sync._sync_build_preview(site)
    var overlay = game.visual_sync.footprint_overlay
    check(overlay.error.is_empty(), "Three neighboring edges remain valid")
    check(overlay.footprint.position.x == sim.footprint(sim.buildings[base]).end.x, "Preview shares base edge")
    check(overlay.footprint.position.y == sim.footprint(sim.buildings[barracks]).end.y, "Preview shares barracks edge")
    check(overlay.footprint.end.y == sim.footprint(sim.buildings[refinery]).position.y, "Preview shares refinery edge")
    for edge: Dictionary in overlay.segments:
        check((edge.a / sim.CELL).is_equal_approx((edge.a / sim.CELL).round()) and (edge.b / sim.CELL).is_equal_approx((edge.b / sim.CELL).round()), "Projected lines use the same global grid")
    await capture("three-neighbors-valid")
    game.visual_sync._sync_build_preview(site - Vector2(32, 0))
    check(overlay.error == "Building footprint occupied", "One-cell overlap shown invalid")
    await capture("one-cell-overlap")
    var frame: int = sim.frame
    game.visual_sync._sync_build_preview(site)
    game._place_building(site)
    game._sync_visuals()
    check(sim.frame == frame and sim.buildings.size() == 4, "Placement creates adjacent building at requested grid")
    game.audio_controller.reset_state()
    await process_frame
    await create_timer(0.1).timeout
    game.queue_free()
    await process_frame
    await create_timer(0.1).timeout
    print("BUILDING_GRID_VIEW failures=", failures)
    quit(0 if failures.is_empty() else 1)
