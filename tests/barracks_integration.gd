extends SceneTree
const MAIN = preload("res://scenes/main.tscn")
var failures: Array[String] = []
var game


func _initialize() -> void:
    run.call_deferred()


func check(value: bool, message: String) -> void:
    if not value:
        failures.append(message)
        push_error(message)


func key(code: Key) -> void:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = true
    game.input_controller._unhandled_input(event)


func check_ring(visual: EntityVisual, offset: Vector3, label: String) -> void:
    check(visual.selection_ring != null, label + ": selection ring exists")
    if visual.selection_ring == null:
        return
    check(visual.selection_ring.is_visible_in_tree(), label + ": selected ring visible")
    check(visual.selection_ring.global_position.distance_to(visual.global_position + offset) < 0.001,
        label + ": ring follows rendered building with its grounded offset")
    check(visual.selection_ring.global_basis.y.normalized().is_equal_approx(Vector3.UP),
        label + ": ring stays horizontal")


func capture(label: String) -> void:
    if DisplayServer.get_name() == "headless":
        return
    game._refresh_ui()
    for i in range(6):
        await process_frame
    var id: int = game.active_building_id()
    if game.building_visuals.has(id):
        var visual: EntityVisual = game.building_visuals[id].visual
        print("POSE ", label, " pos=", visual.position, " model=", visual.model.transform, " body=", visual.barracks_motion.body.transform,
            " foot=", visual.model.find_child("FootLFront", true, false).position, " jet=", visual.model.find_child("JetLFront", true, false).scale,
            " clip=", visual.barracks_motion.player.current_animation_position)
        check(visual.barracks_motion.body.position.is_zero_approx(), "Flag player never overwrites body height after rendered frames")
        var foot: Node3D = visual.model.find_child("FootLFront", true, false)
        if game.sim.buildings[id].flight.state == "grounded":
            check(foot.position.y < 0.2, "Ground landing gear stays deployed after rendered frames")
    await RenderingServer.frame_post_draw
    check(root.get_texture().get_image().save_png("res://assets/concept_art/barracks-v4-game-" + label + ".png") == OK, "Capture saved")


func run() -> void:
    root.size = Vector2i(1536, 1024)
    for map_id: String in ["prototype", "desert_quarry", "desert_sample"]:
        game = MAIN.instantiate()
        game.selected_map_id = map_id
        root.add_child(game)
        game.set_process(false)
        game.play_solo()
        game.sim.ai_enabled = false
        game.sim.units.clear()
        game.sim.buildings.clear()
        game.sim.visible[1].fill(1)
        var anchor := Vector2(768, 512) if map_id != "desert_sample" else Vector2(2336, 1536)
        check(game.sim.deployment_site(1, -1, anchor).error.is_empty(), "Fixture is legal: " + map_id)
        var id: int = game.sim._add_building(1, "barracks", anchor, true)
        game.sim._add_building(2, "base", Vector2(4416, 2816), true)
        game.sim.rebuild_navigation()
        game.selected_building = id
        game.selected_buildings.assign([id])
        game.camera_controller.focus = anchor
        game.camera_zoom_level = 2.3
        game._update_camera_transform()
        game._sync_visuals()
        game._refresh_ui()
        check(not game.action_buttons[2].disabled and game.action_buttons[2].action_id == "takeoff"
            and game.action_buttons[2].hotkey.text == "L", "Lift button")
        var visual: EntityVisual = game.building_visuals[id].visual
        var ring_offset := visual.selection_ring.global_position - visual.global_position
        check_ring(visual, ring_offset, map_id + " grounded")
        check(visual.barracks_motion.wind != null and visual.barracks_motion.wind.is_playing(), "Flag loop active")
        var flag := visual.model.find_child("BarracksFlag", true, false) as MeshInstance3D
        visual.barracks_motion.wind.seek(0, true)
        var initial_flag := flag.get_blend_shape_value(0)
        visual.barracks_motion.wind.seek(0.5, true)
        check(absf(initial_flag - flag.get_blend_shape_value(0)) > 0.1, "Flag animates in imported runtime model")
        await capture(map_id + "-landed")
        visual.set_faction(2)
        await capture(map_id + "-landed-red")
        visual.set_faction(1)
        key(KEY_L)
        check(game.sim.buildings[id].flight.state == "taking_off", "L issues takeoff")
        for tick in range(80):
            game.sim.step()
            if tick in [20, 40, 60, 79]:
                game.visual_sync._sync_buildings(1.0 / 60.0)
                check_ring(visual, ring_offset, map_id + " takeoff %d" % tick)
                if tick == 40:
                    check(absf(visual.position.y - game.sim.buildings[id].flight.height) > 1.0,
                        "Takeoff fixture exercises interpolated height")
        game._sync_visuals()
        game._refresh_ui()
        check(not game.action_buttons[3].disabled and game.action_buttons[1].disabled, "Airborne actions disable production")
        check(is_equal_approx(visual.position.y, game.sim.buildings[id].flight.height), "Render height matches simulation")
        check(game.airborne_building_at(game.building_screen_position(id), true) == id, "Airborne screen picking")
        check_ring(visual, ring_offset, map_id + " airborne")
        check(visual.selection_ring.global_position.y > game.sim.terrain.height_at(anchor) + 100.0,
            "Airborne ring leaves the terrain")
        game.selected_building = -1
        game.selected_buildings.clear()
        game.visual_sync._sync_buildings()
        check(not visual.selection_ring.visible, "Deselection hides airborne ring")
        game.selected_building = id
        game.selected_buildings.assign([id])
        game.visual_sync._sync_buildings()
        check_ring(visual, ring_offset, map_id + " reselected airborne")
        game.camera_zoom_level = 1.0
        game._update_camera_transform()
        await capture(map_id + "-airborne")
        visual.set_faction(2)
        await capture(map_id + "-airborne-red")
        visual.set_faction(1)
        key(KEY_D)
        check(game.deploy_building == id, "D enters deploy preview")
        game._sync_build_preview()
        check(game.visual_sync.deploy_cells.size() == 12, "Twelve preview cells")
        game.sim.visible[1].fill(1)
        game.visual_sync._sync_deploy_preview(anchor)
        check(game.visual_sync.deploy_cells.all(func(cell: MeshInstance3D) -> bool: return cell.material_override.albedo_color.g > cell.material_override.albedo_color.r), "Legal preview is green")
        await capture(map_id + "-deploy-valid")
        var blocking_unit: int = game.sim.add_unit(1, "soldier", anchor + Vector2(48, 32))
        game.visual_sync._sync_deploy_preview(anchor)
        check(game.visual_sync.deploy_cells.any(func(cell: MeshInstance3D) -> bool: return cell.material_override.albedo_color.r > cell.material_override.albedo_color.g), "Blocked preview contains red cell")
        await capture(map_id + "-deploy-blocked")
        game._deploy_click(anchor)
        check(not game.sim.buildings[id].flight.deploy, "One red cell blocks UI deployment")
        game.sim.units.erase(blocking_unit)
        var invalid := Vector2(5, 5)
        game._deploy_click(invalid)
        check(game.deploy_building == id, "Invalid click keeps preview and rejects order")
        key(KEY_ESCAPE)
        check(game.deploy_building < 0 and not game.menu_visible, "Escape cancels selection without opening menu")
        game._right_click(anchor + Vector2(80, 0))
        check(game.sim.buildings[id].flight.moving, "RMB moves airborne building")
        for tick in range(20):
            game.sim.step()
            for frame in range(3):
                game.visual_sync._sync_buildings(1.0 / 60.0)
        check(game.sim.buildings[id].pos == anchor, "Turn before translation")
        game.sim.step()
        game.visual_sync._sync_buildings(1.0 / 60.0)
        check(visual.position.x > anchor.x, "Moving fixture advances rendered building")
        check(visual.get_visual_forward().dot(Vector3.RIGHT) > .99, "Moving front faces travel direction")
        check(visual.barracks_presentation.rear_jets.all(func(jet: MeshInstance3D) -> bool: return jet.visible), "Actual move enables rear exhaust")
        check_ring(visual, ring_offset, map_id + " moving")
        key(KEY_S)
        check(not game.sim.buildings[id].flight.moving, "S stops flight")
        game.visual_sync._sync_buildings(1.0 / 60.0)
        check(visual.barracks_presentation.rear_jets.all(func(jet: MeshInstance3D) -> bool: return not jet.visible), "Actual stop disables rear exhaust")
        key(KEY_D)
        game.sim.visible[1].fill(1)
        game._deploy_click(anchor)
        for tick in range(180):
            game.sim.step()
            if tick in [20, 40, 60, 81]:
                game.visual_sync._sync_buildings(1.0 / 60.0)
                check_ring(visual, ring_offset, map_id + " landing %d" % tick)
            if game.sim.buildings[id].flight.state == "grounded":
                break
        game._sync_visuals()
        check(game.sim.buildings[id].flight.state == "grounded", "Deploy click completes landing")
        check_ring(visual, ring_offset, map_id + " landed again")
        game.rebinding_attack = true
        key(KEY_D)
        check(game.rebinding_attack and game.attack_keycode != KEY_D, "Reserved shortcut cannot be rebound")
        key(KEY_ESCAPE)
        game.queue_free()
        await process_frame
    print("BARRACKS_INTEGRATION ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
    quit(0 if failures.is_empty() else 1)
