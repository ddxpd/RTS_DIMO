extends SceneTree
# Headless verification for the bottom action bar wiring.
const MAIN = preload("res://scenes/main.tscn")

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    Engine.max_fps = 120
    var game := MAIN.instantiate()
    game.selected_map_id = "prototype"
    root.add_child(game)
    game.play_solo()
    var failures: Array = []

    # Select the first friendly soldier.
    var unit_id := -1
    for id: int in game.sim.units:
        if game.sim.units[id].owner == 1 and game.sim.units[id].type == "soldier":
            unit_id = id
            break
    if unit_id < 0:
        failures.append("no friendly soldier found")
    else:
        game._clear_selection()
        game.selected_units.append(unit_id)
        game._refresh_ui()
        if game.action_buttons[0].action_id != "stop" or game.action_buttons[0].disabled:
            failures.append("STOP button not enabled with hotkey label")
        if game.action_buttons[1].action_id != "move" or game.action_buttons[1].disabled:
            failures.append("MOVE button not enabled with hint label")
        if game.action_buttons[2].action_id != "attack" or game.action_buttons[2].disabled:
            failures.append("ATTACK button not enabled with hotkey label")
        if game.action_buttons[3].disabled == false or game.action_buttons[4].disabled == false:
            failures.append("unused action slots not disabled")

        # Clicking MOVE must arm the pending command instead of issuing instantly.
        game.action_buttons[1].emit_signal("pressed")
        if game.pending_command != "move":
            failures.append("MOVE click did not arm pending command")

        # The next battlefield click issues the move order and clears the mode.
        game._pending_click(Vector2(500, 300))
        if game.sim.units[unit_id].order != "move":
            failures.append("pending click did not issue move order")
        if game.pending_command != "":
            failures.append("pending command not cleared after issue")

        # STOP button must issue the stop order.
        game.action_buttons[0].emit_signal("pressed")
        await process_frame
        await process_frame
        if game.sim.units[unit_id].order != "idle":
            failures.append("STOP click did not stop the unit")

    await verify_cards(game, failures)
    print("ACTION_BAR_TEST failures=", failures)
    quit(0 if failures.is_empty() else 1)


func expect(condition: bool, message: String, failures: Array) -> void:
    if not condition:
        failures.append(message)


func verify_cards(game, failures: Array) -> void:
    game.set_process(false)
    game.sim.ai_enabled = false
    game.sim.add_unit(1, "harvester", Vector2(350, 400))
    game.sim._add_building(1, "barracks", Vector2(600, 600), true)
    game.sim._add_building(1, "refinery", Vector2(800, 600), true)
    var soldier := -1
    var miner := -1
    for id: int in game.sim.units:
        if game.sim.units[id].owner == 1:
            if game.sim.units[id].type == "soldier":
                soldier = id
            else:
                miner = id
    game._clear_selection()
    game.selected_units.assign([soldier, miner])
    game._refresh_ui()
    for i in range(4):
        var card = game.action_buttons[i]
        expect(card.glyph.texture != null and card.text.is_empty(), "Command has icon without caption", failures)
        expect(not card.tooltip_text.is_empty(), "Command has help", failures)
        expect(card.glyph.mouse_filter == Control.MOUSE_FILTER_IGNORE and card.hotkey.mouse_filter == Control.MOUSE_FILTER_IGNORE,
            "Icon and badge do not consume clicks", failures)
    game.attack_keycode = KEY_Q
    game.action_buttons[2].emit_signal("pressed")
    game._refresh_ui()
    expect(game.action_buttons[2].active and game.action_buttons[2].hotkey.text == "Q"
        and "[Q]" in game.action_buttons[2].tooltip_text, "Attack active and rebound badge", failures)
    game.selected_units.assign([miner])
    game._refresh_ui()
    expect(game.action_buttons[2].glyph.texture == null and not game.action_buttons[2].active
        and game.action_buttons[2].tooltip_text.is_empty(), "Miner clears old attack state", failures)
    game.action_buttons[3].emit_signal("pressed")
    expect(game.pending_command == "gather", "Gather icon arms gathering", failures)
    game._clear_selection()
    var barracks := -1
    for id: int in game.sim.buildings:
        var b: Dictionary = game.sim.buildings[id]
        if b.owner != 1:
            continue
        game.selected_building = id
        game._refresh_ui()
        if b.type == "base":
            expect(game.action_buttons[2].action_id == "barracks" and "$250" in game.action_buttons[2].tooltip_text,
                "Barracks construction icon and current cost", failures)
            for slot in [2, 3, 5, 6]:
                expect(game.action_buttons[slot].glyph.texture != null, "Base construction icon %d" % slot, failures)
        elif b.type == "refinery":
            expect(game.action_buttons[1].action_id == "harvester" and "$200" in game.action_buttons[1].tooltip_text,
                "Miner production icon and cost", failures)
        elif b.type == "barracks":
            barracks = id
            expect(game.action_buttons[1].action_id == "soldier" and "$100" in game.action_buttons[1].tooltip_text,
                "Soldier production icon and cost", failures)
    expect(barracks >= 0, "Barracks fixture exists", failures)
    if barracks >= 0:
        game.selected_building = barracks
        var b: Dictionary = game.sim.buildings[barracks]
        b.queue.append({"type": "soldier", "remaining": 50})
        game._refresh_ui()
        expect(game.action_buttons[2].action_id == "takeoff" and game.action_buttons[2].disabled
            and game.action_buttons[2].glyph.texture != null, "Unavailable takeoff retains dimmed icon", failures)
        game.action_buttons[4].emit_signal("pressed")
        game._refresh_ui()
        expect(b.queue.is_empty() and not game.action_buttons[2].disabled, "Cancel icon refunds and unlocks takeoff", failures)
        for state in ["taking_off", "landing"]:
            b.flight.state = state
            game._refresh_ui()
            expect(game.action_buttons.all(func(card): return card.disabled and card.glyph.texture == null),
                "Transition clears commands: " + state, failures)
        b.flight.state = "airborne"
        game._refresh_ui()
        expect(game.action_buttons[3].action_id == "deploy" and game.action_buttons[3].hotkey.text == "D",
            "Airborne deployment card", failures)
        expect(game.action_buttons[1].glyph.texture == null, "Airborne clears production icon", failures)
        b.flight.state = "grounded"
        game._refresh_ui()
        expect(game.action_buttons[2].hotkey.text == "L" and game.action_buttons[3].glyph.texture == null,
            "Landing restores ground cards", failures)
    game._clear_selection()
    game._refresh_ui()
    for card in game.action_buttons:
        expect(card.action_id.is_empty() and card.disabled and card.glyph.texture == null
            and card.hotkey.text.is_empty() and card.tooltip_text.is_empty(),
            "Deselection clears every tile", failures)
    # Exercise real pointer dispatch, including a refresh between press and release.
    game.selected_units.assign([soldier])
    game.attack_mode = false
    game.attack_keycode = KEY_A
    game.camera_controller.focus = game.sim.units[soldier].pos
    game._update_camera_transform()
    game._sync_visuals()
    game._refresh_ui()
    for resolution in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
        root.size = resolution
        await process_frame
        await process_frame
        var button: Button = game.action_buttons[1]
        print("COMMAND_LAYOUT ", resolution, " viewport=", root.get_visible_rect(), " command=", game.bottom_zones.command.get_global_rect())
        for card: Button in game.action_buttons:
            expect(root.get_visible_rect().encloses(card.get_global_rect()),
                "Command fits viewport %s" % resolution, failures)
        var press := InputEventMouseButton.new()
        press.position = button.get_global_rect().get_center()
        press.button_index = MOUSE_BUTTON_LEFT
        press.pressed = true
        root.push_input(press, true)
        game._refresh_ui()
        var release := press.duplicate()
        release.pressed = false
        root.push_input(release, true)
        expect(game.pending_command == "move", "Icon click survives refresh %s" % resolution, failures)
        game.pending_command = ""
        if "--screenshot" in OS.get_cmdline_args() + OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
            await capture("units-%d" % resolution.x, failures)
            game._clear_selection()
            game.selected_building = barracks
            game._refresh_ui()
            await capture("barracks-%d" % resolution.x, failures)
            for id: int in game.sim.buildings:
                if game.sim.buildings[id].owner == 1 and game.sim.buildings[id].type == "base":
                    game.selected_building = id
                    break
            game._refresh_ui()
            var hover := InputEventMouseMotion.new()
            hover.position = game.action_buttons[2].get_global_rect().get_center()
            root.push_input(hover, true)
            await create_timer(0.8).timeout
            await capture("buildings-tooltip-%d" % resolution.x, failures)
            game._clear_selection()
            game.selected_units.assign([soldier])
            game._refresh_ui()


func capture(label: String, failures: Array) -> void:
    await process_frame
    await process_frame
    await RenderingServer.frame_post_draw
    DirAccess.make_dir_recursive_absolute("res://assets/concept_art/command_icons")
    var result := root.get_texture().get_image().save_png("res://assets/concept_art/command_icons/" + label + ".png")
    expect(result == OK, "Preview saved: " + label, failures)
