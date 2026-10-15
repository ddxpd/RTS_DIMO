extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
const MAIN = preload("res://scenes/main.tscn")
var failures: Array[String] = []
var checks := 0
var game


func _initialize() -> void:
    run.call_deferred()


func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)


func order(sim, id: int, mode: String, point: Vector2 = Vector2.ZERO, ore: int = -1, owner: int = 1) -> String:
    return sim.command(owner, {"action": "set_rally", "building": id, "mode": mode, "pos": point, "ore": ore})


func produce(sim, id: int, kind: String) -> int:
    var before: int = sim.next_id
    sim.buildings[id].queue.assign([{"type": kind, "remaining": 0}])
    sim.EconomySystem.advance_production(sim, sim.buildings[id])
    check(sim.units.has(before), "Production has an unblocked exit for " + kind)
    return before


func click(point: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
    var event := InputEventMouseButton.new()
    event.position = point
    event.button_index = button
    event.pressed = true
    root.push_input(event, true)
    event = event.duplicate()
    event.pressed = false
    root.push_input(event, true)


func key(code: Key) -> void:
    var event := InputEventKey.new()
    event.keycode = code
    event.physical_keycode = code
    event.pressed = true
    root.push_input(event, true)


func run() -> void:
    root.size = Vector2i(1920, 1080)
    root.content_scale_size = root.size
    game = MAIN.instantiate()
    game.selected_map_id = "desert_quarry"
    root.add_child(game)
    game.play_solo()
    game.set_process(false)
    var sim = game.sim
    sim.ai_enabled = false
    sim.units.clear()
    sim.buildings.clear()
    sim.visible[1].fill(1)
    sim.explored[1].fill(1)
    var spot := Vector2(1600, 1900)
    var barracks: int = sim._add_building(1, "barracks", spot, true)
    var depot: int = sim._add_building(1, "refinery", spot + Vector2(500, 0), true)
    var base: int = sim._add_building(1, "base", Vector2(500, 500), true)
    sim.ores[100] = {"pos": spot + Vector2(200, 350), "amount": 1000}
    sim.rebuild_navigation()
    check(sim.buildings[barracks].rally_mode == "none", "Defaults have no rally")
    check(order(sim, base, "ground", spot) != "", "Reject non-producer")
    check(order(sim, barracks, "ground", spot, -1, 2) != "", "Reject foreign building")
    check(order(sim, barracks, "ground", Vector2(INF, 1)) != "", "Reject nonfinite")
    check(order(sim, barracks, "ground", Vector2(-1, 2)) != "", "Reject outside map")
    check(order(sim, barracks, "ore", spot, 100) != "", "Reject infantry mining rally")
    check(order(sim, depot, "ore", spot, 9999) != "", "Reject missing ore")
    sim.visible[1].fill(0)
    check(order(sim, depot, "ore", spot, 100) != "", "Reject hidden ore")
    sim.visible[1].fill(1)
    check(order(sim, barracks, "ground", Vector2.ZERO) == "" and sim.buildings[barracks].rally_mode == "ground", "World origin is a valid explicit rally")
    var destination := spot + Vector2(-180, 200)
    check(order(sim, barracks, "ground", destination) == "", "Set infantry rally")
    for kind: String in ["mobile_infantry"]:
        var id := produce(sim, barracks, kind)
        if sim.units.has(id):
            check(sim.units[id].order == "move" and sim.units[id].arrival.anchor == sim.buildings[barracks].rally, kind + " receives movement on birth")
            var target: Vector2 = sim.units[id].target
            order(sim, barracks, "none")
            check(sim.units[id].target == target and sim.units[id].order == "move", "Clearing does not retask existing units")
        sim.units.clear()
        order(sim, barracks, "ground", destination)
    check(order(sim, depot, "ore", spot, 100) == "", "Set ore rally")
    var miner := produce(sim, depot, "harvester")
    check(sim.units[miner].order == "gather" and sim.units[miner].ore == 100, "Mine designated crystal on birth")
    sim.units.clear()
    sim.ores[100].amount = 0
    miner = produce(sim, depot, "harvester")
    check(sim.units[miner].order == "gather" and sim.units[miner].ore != 100, "Depleted target falls back to visible ore")
    sim.units.clear()
    sim.ores.erase(100)
    sim.visible[1].fill(0)
    miner = produce(sim, depot, "harvester")
    check(sim.units[miner].order == "idle", "Missing ore and no visible alternatives leaves miner idle")
    sim.units.clear()
    sim.visible[1].fill(1)
    sim.ores[100] = {"pos": spot + Vector2(200, 350), "amount": 1000}
    order(sim, depot, "ground", destination)
    miner = produce(sim, depot, "harvester")
    check(sim.units[miner].order == "move", "Ground rally does not start mining")
    sim.units.clear()
    order(sim, depot, "none")
    miner = produce(sim, depot, "harvester")
    check(sim.units[miner].order == "gather", "Clear restores default auto-mining")
    sim.units.clear()
    order(sim, depot, "ore", spot, 100)
    var snapshot: Dictionary = sim.snapshot()
    check(sim.validate_snapshot(snapshot), "v12 snapshot validates")
    for value in [123, "bad"]:
        var invalid := snapshot.duplicate(true)
        invalid.buildings[depot].rally_mode = value
        check(not sim.validate_snapshot(invalid), "Reject malformed rally mode")
    for field: String in ["rally_mode", "rally_ore"]:
        var invalid := snapshot.duplicate(true)
        invalid.buildings[depot].erase(field)
        check(not sim.validate_snapshot(invalid), "Reject missing " + field)
    var invalid := snapshot.duplicate(true)
    invalid.buildings[depot].rally_ore = "100"
    check(not sim.validate_snapshot(invalid), "Reject ore ID type")
    invalid = snapshot.duplicate(true)
    invalid.version = "rts-desert-only-11"
    check(not sim.validate_snapshot(invalid), "Reject old protocol")
    game.camera_controller.focus = spot
    game._update_camera_transform()
    game._clear_selection()
    game.selected_building = barracks
    game.selected_buildings.assign([barracks])
    game._refresh_ui()
    await process_frame
    await process_frame
    var card: Button = game.action_buttons[6]
    click(card.get_global_rect().get_center())
    check(game.pending_command == "rally", "Actual button starts rally placement")
    var point: Vector2 = game._world_to_screen(destination)
    check(game._screen_is_map(point), "Placement fixture lies in playfield")
    click(point)
    check(game.pending_command == "" and sim.buildings[barracks].rally_mode == "ground", "Actual click places rally without losing selection")
    key(KEY_R)
    check(game.pending_command == "rally", "R starts placement")
    var hud_previous: Vector2 = sim.buildings[barracks].rally
    click(game.hud_controller.view.status_frame.get_global_rect().get_center())
    check(game.pending_command == "rally" and sim.buildings[barracks].rally == hud_previous, "HUD click does not place a rally")
    var previous: Vector2 = sim.buildings[barracks].rally
    click(point + Vector2(50, 0), MOUSE_BUTTON_RIGHT)
    check(game.pending_command == "" and sim.buildings[barracks].rally == previous, "Right-click cancels pending placement")
    key(KEY_R)
    key(KEY_ESCAPE)
    check(game.pending_command == "" and not game.menu_visible, "Escape cancels without menu")
    key(KEY_R)
    game._toggle_menu()
    check(game.pending_command == "", "Menu cancels placement")
    game._close_menu()
    key(KEY_R)
    game._clear_selection()
    check(game.pending_command == "", "Selection clear cancels placement")
    game.selected_building = depot
    game.selected_buildings.assign([depot])
    game._right_click(sim.ores[100].pos)
    check(sim.buildings[depot].rally_mode == "ore", "Depot right-click resolves visible ore")
    game.selected_building = barracks
    game.selected_buildings.assign([barracks, depot])
    game._right_click(destination)
    check(sim.buildings[barracks].rally == sim.buildings[depot].rally, "Multiselect updates both producers")
    game._refresh_ui()
    game.hud_controller.view.rally_overlay.refresh()
    check(game.hud_controller.view.rally_overlay.entries.size() == 2, "Two persistent selected rally flags")
    game._control_group_key(2, true, false)
    key(KEY_R)
    game._control_group_key(2, false, false)
    check(game.pending_command == "", "Recalling a building group cancels pending rally")
    key(KEY_R)
    key(KEY_A)
    check(game.pending_command == "rally" and not game.attack_mode, "Unavailable building attack cannot interrupt rally placement")
    key(KEY_ESCAPE)
    game.attack_mode = false
    sim.visible[1].fill(0)
    game.hud_controller.view.rally_overlay.refresh()
    check(game.hud_controller.view.rally_overlay.entries.size() == 2, "Known own orders persist in fog without revealing entities")
    game.local_slot = 2
    game.hud_controller.view.rally_overlay.refresh()
    check(game.hud_controller.view.rally_overlay.entries.is_empty(), "Enemy rally flags are hidden")
    game.local_slot = 1
    sim.visible[1].fill(1)
    sim.buildings[barracks].remaining = 10
    check(order(sim, barracks, "ground", destination) == "", "Construction can preset rally")
    sim.buildings[barracks].remaining = 0
    var takeoff: String = sim.command(1, {"action": "barracks_takeoff", "building": barracks})
    check(takeoff.is_empty(), "Takeoff accepted")
    check(order(sim, barracks, "none") != "" and sim.buildings[barracks].rally == previous, "Takeoff locks editing and retains rally")
    sim.buildings[barracks].flight.state = "grounded"
    sim.buildings[barracks].flight.height = sim.terrain.height_at(spot)
    game.selected_buildings.assign([barracks])
    game._refresh_ui()
    for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(2560, 1080)]:
        root.size = resolution
        root.content_scale_size = resolution
        game._refresh_ui()
        game._sync_visuals()
        for i in range(3):
            await process_frame
        var view = game.hud_controller.view
        view.rally_overlay.refresh()
        check(view.rally_overlay.entries.size() == 1, "Flag persists after resize " + str(resolution))
        for button: Button in game.action_buttons:
            if button.visible:
                check(view.command_frame.get_global_rect().encloses(button.get_global_rect()), "Six commands fit " + str(resolution))
        if DisplayServer.get_name() != "headless":
            await RenderingServer.frame_post_draw
            var folder := "res://assets/concept_art/ui_selection/mechanical_hud/rally_review"
            DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
            check(root.get_texture().get_image().save_png(folder + "/rally-%dx%d.png" % [resolution.x, resolution.y]) == OK, "Save rally review")
    game._refresh_ui()
    await process_frame
    click(game.action_buttons[7].get_global_rect().get_center())
    check(sim.buildings[barracks].rally_mode == "none", "Clear button resets rally")
    game.hud_controller.view.rally_overlay.refresh()
    check(game.hud_controller.view.rally_overlay.entries.is_empty(), "Clearing removes persistent marker")
    var attack_key: int = game.key_bindings.bindings.attack
    game.settings_panel.begin_recording("attack")
    key(KEY_R)
    check(not game.settings_panel.recording.is_empty() and game.key_bindings.bindings.attack == attack_key, "R is reserved from attack rebinding")
    key(KEY_ESCAPE)
    key(KEY_R)
    sim.buildings.erase(barracks)
    game._refresh_ui()
    check(game.pending_command == "", "Destroyed producer cancels placement")
    game.audio_controller.reset_state()
    await process_frame
    await create_timer(0.1).timeout
    game.queue_free()
    await process_frame
    await create_timer(0.1).timeout
    print("RALLY_POINTS checks=", checks, " failures=", failures)
    quit(0 if failures.is_empty() else 1)
