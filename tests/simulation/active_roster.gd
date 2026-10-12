extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
const Visual = preload("res://assets/art/entity_visual.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
    run.call_deferred()


func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)


func active_only(sim) -> bool:
    for unit: Dictionary in sim.units.values():
        if unit.type not in Sim.ACTIVE_UNIT_TYPES:
            return false
    for building: Dictionary in sim.buildings.values():
        for job: Dictionary in building.queue:
            if job.type not in Sim.ACTIVE_UNIT_TYPES:
                return false
    return true


func run() -> void:
    var sim := Sim.new()
    sim.reset(true)
    check(sim.units.is_empty() and sim.buildings.size() == 2, "Both sides start with only their main base")
    check(sim.buildings.values().all(func(building): return building.type == "base"), "No initial production buildings")
    for tick in range(800):
        sim.step()
        if not active_only(sim):
            check(false, "AI never creates or queues retired soldiers")
            break
    check(sim.units.size() > 0 and active_only(sim), "AI economy and active production still run from base only")
    sim.reset(false, "desert_sample")
    check(sim.units.is_empty() and sim.buildings.size() == 1, "Sample remains base only")
    var barracks := sim._add_building(1, "barracks", Vector2(2240, 1200), true)
    var money: int = sim.money[1]
    check(sim.command(1, {"action": "produce", "building": barracks, "type": "soldier"}) == "This unit is currently unavailable", "Host rejects retired type, even with forged command")
    check(sim.money[1] == money and sim.buildings[barracks].queue.is_empty(), "Rejected retired order has no charge or queue side effects")
    # Existing queued data cannot accidentally revive the retired type.
    sim.money[1] -= Sim.UNIT_TYPES.soldier.cost
    sim.buildings[barracks].queue.append({"type": "soldier", "remaining": 0})
    sim.step()
    check(sim.money[1] == money and sim.units.is_empty() and sim.buildings[barracks].queue.is_empty(), "Stale retired job refunds and never spawns")
    check(sim.command(1, {"action": "produce", "building": barracks, "type": "mobile_infantry"}).is_empty(), "Mobile infantry remains trainable")
    for tick in range(50):
        sim.step()
    check(sim.units.size() == 1 and active_only(sim), "Active infantry actually leaves the barracks")
    for path: String in ["res://assets/models/units/soldier/soldier.glb", "res://assets/art/units/soldier/soldier_motion.gd", "res://assets/art/units/soldier/soldier_lod.gd"]:
        check(ResourceLoader.exists(path), "Archived soldier resource preserved: " + path)
    var archived := Visual.new("soldier", 1)
    root.add_child(archived)
    check(archived.model != null and archived.soldier_motion != null, "Archived model and animation controller still instantiate")
    archived.queue_free()
    await process_frame
    root.size = Vector2i(1920, 1080)
    root.content_scale_size = root.size
    var game = load("res://scenes/main.tscn").instantiate()
    root.add_child(game)
    game.play_solo()
    game.set_process(false)
    var factory: int = game.sim._add_building(1, "barracks", Vector2(800, 600), true)
    game.sim.update_visibility()
    game.selected_building = factory
    game.selected_buildings.assign([factory])
    game.camera_controller.focus = Vector2(800, 600)
    game._update_camera_transform()
    game._sync_visuals()
    game._refresh_ui()
    check(game.action_buttons[1].action_id == "mobile_infantry" and not game.action_buttons[1].disabled, "Barracks offers mobile infantry in primary slot")
    check(game.action_buttons.all(func(button): return button.action_id != "soldier"), "No retired command card")
    check(not game.hud_controller.view.roster_tiles.has("soldier"), "No retired roster tile")
    var queued: int = game.sim.buildings[factory].queue.size()
    game.hud_controller.invoke("soldier")
    check(game.sim.buildings[factory].queue.size() == queued, "Stale UI command cannot produce retired type")
    game.action_buttons[1].emit_signal("pressed")
    check(game.sim.buildings[factory].queue.size() == queued + 1 and game.sim.buildings[factory].queue.back().type == "mobile_infantry", "Production button dispatches active type")
    game._refresh_ui()
    if DisplayServer.get_name() != "headless":
        for frame in range(4):
            await process_frame
        await RenderingServer.frame_post_draw
        var folder := "res://assets/concept_art/ui_selection/mechanical_hud/active_roster_review"
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
        check(root.get_texture().get_image().save_png(folder + "/barracks-mobile-only.png") == OK, "Save active roster review")
    game.audio_controller.reset_state()
    game.queue_free()
    await process_frame
    print("ACTIVE_ROSTER checks=", checks, " failures=", failures)
    quit(0 if failures.is_empty() else 1)
