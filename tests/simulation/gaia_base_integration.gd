extends SceneTree

const Sim = preload("res://scripts/simulation.gd")
const MAIN = preload("res://scenes/main.tscn")
const OUT := "res://assets/concept_art/gaia_command_base/"
var failures: Array[String] = []
var checks := 0
var game: Node3D


func _initialize() -> void:
    run.call_deferred()


func check(condition: bool, message: String) -> void:
    checks += 1
    if not condition:
        failures.append(message)
        push_error(message)


func capture(filename: String) -> void:
    if DisplayServer.get_name() == "headless":
        return
    # This fixture pauses the game loop, so refresh projected HUD anchors after zooming.
    game._sync_visuals()
    for i in range(12):
        await process_frame
    await RenderingServer.frame_post_draw
    check(root.get_texture().get_image().save_png(OUT + filename + ".png") == OK, "saved " + filename)


func run() -> void:
    root.size = Vector2i(1600, 1000)
    game = MAIN.instantiate()
    game.selected_map_id = "desert_quarry"
    root.add_child(game)
    game.play_solo()
    preload("res://tests/fixtures/army_setup.gd").seed(game.sim)
    game.set_process(false)
    game.sim.ai_enabled = false
    game._sync_visuals()
    var sim: RefCounted = game.sim
    for id in [1, 2]:
        var base: Dictionary = sim.buildings[id]
        check(sim.footprint(base).size == Vector2(320, 192), "both starting footprints updated")
        check(game.building_visuals[id].visual.model is GaiaCommandBase, "both starting models replaced")
        check(not base.has("flight"), "base remains a fixed ground building")
        for unit: Dictionary in sim.units.values():
            check(not sim.footprint(base, Sim.UNIT_TYPES[unit.type].radius).has_point(unit.pos), "starting units outside base")
    check(Sim.BUILD_TYPES.base.hp == 800 and Sim.BUILD_TYPES.base.cost == 500 and Sim.BUILD_TYPES.base.time == 140, "base economy unchanged")
    var center: Vector2 = sim.buildings[1].pos
    var path: PackedVector2Array = sim.nav.get_point_path(sim.nearest_cell(center + Vector2(-224, 0)), sim.nearest_cell(center + Vector2(224, 0)))
    check(path.size() > 2, "path routes across base surroundings")
    for point in path:
        check(not sim.footprint(sim.buildings[1], 14).has_point(point), "navigation path avoids expanded base")
    for pair in [["base", "refinery"], ["base", "bunker"], ["refinery", "barracks"]]:
        var offsets: Array[Vector2] = sim._ai_build_offsets(pair[0], pair[1], [Vector2(1, 0), Vector2(0, -1)])
        var a_size: Vector2 = Sim.BUILD_TYPES[pair[0]].size
        var b_size: Vector2 = Sim.BUILD_TYPES[pair[1]].size
        var reachable_candidate := false
        for offset in offsets:
            check(not Rect2(-a_size / 2, a_size).grow(16).intersects(Rect2(offset - b_size / 2, b_size).grow(16)), "AI leaves placement clearance")
            check((offset / Sim.CELL).is_equal_approx((offset / Sim.CELL).round()), "AI candidates align to grid")
            reachable_candidate = reachable_candidate or offset.length() < 360
        check(reachable_candidate, "AI has a candidate within build radius; build_error filters others")
    var site := center + Vector2(0, -256)
    game.selected_building = 1
    game.selected_buildings.assign([1])
    game.camera_controller.focus = center
    game.camera_zoom_level = 1.2
    game._update_camera_transform()
    game._sync_visuals()
    game._refresh_ui()
    await capture("game-main-base")
    game.selected_units.assign([3, 4])
    game._sync_visuals()
    game._refresh_ui()
    await capture("selection-width-comparison")
    game.camera_zoom_level = 0.8
    game._update_camera_transform()
    await capture("selection-width-far")
    game.camera_zoom_level = 1.8
    game._update_camera_transform()
    await capture("selection-width-near")
    game.selected_units.clear()
    var credits: int = sim.money[1]
    check(sim.command(1, {"action": "build", "type": "base", "pos": site}).is_empty(), "base placement accepted")
    var id: int = sim.next_id - 1
    check(sim.money[1] == credits - 500, "base cost deducted once")
    check(sim.buildings[id].remaining == 140, "construction timer retained")
    game.selected_building = id
    game.selected_buildings.assign([id])
    game._sync_buildings()
    var visual: EntityVisual = game.building_visuals[id].visual
    var component := visual.model as GaiaCommandBase
    component.automatic_animation = false
    component.seek_pose("deployed", 0)
    var rest := component.presentation.transform
    check(visual.construction_tint and game.building_visuals[id].build_bar.visible, "construction tint and bar visible at start")
    check(not sim.position_free(site, 0), "construction blocks navigation immediately")
    game.camera_controller.focus = site
    game.camera_zoom_level = 1.8
    game._update_camera_transform()
    for tick in range(70):
        sim.step()
    game._sync_buildings()
    check(sim.buildings[id].remaining == 70, "halfway construction remains unfinished")
    game._refresh_ui()
    check(component.presentation.transform.is_equal_approx(rest), "no construction growth or lift")
    check(visual.animation_state == "construction", "snapshot keeps construction state")
    await capture("game-construction")
    for tick in range(69):
        sim.step()
    check(sim.buildings[id].remaining == 1, "construction cannot complete early")
    sim.step()
    game._sync_buildings()
    check(sim.buildings[id].remaining == 0 and visual.animation_state == "idle", "completion at tick 140")
    check(not visual.construction_tint and not game.building_visuals[id].build_bar.visible, "completion clears tint and progress bar")
    check(component.presentation.transform.is_equal_approx(rest), "completion does not jump or rescale")
    game._refresh_ui()
    await capture("game-completed")
    var mirror := Sim.new()
    mirror.reset()
    mirror.apply_snapshot(sim.snapshot())
    check(mirror.footprint(mirror.buildings[id]) == sim.footprint(sim.buildings[id]), "snapshot uses same footprint without new fields")
    print("GAIA_BASE_INTEGRATION ", checks, " checks; failures=", failures)
    game.queue_free()
    await process_frame
    quit(0 if failures.is_empty() else 1)
