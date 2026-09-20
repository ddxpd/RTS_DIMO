extends SceneTree
# Headless verification for double-click select, control groups,
# production progress UI and building rally points.
const MAIN = preload("res://scenes/main.tscn")

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    Engine.max_fps = 120
    var game := MAIN.instantiate()
    root.add_child(game)
    game.play_solo()
    var failures: Array = []
    if DisplayServer.get_name() != "headless" and Input.mouse_mode != Input.MOUSE_MODE_CONFINED:
        failures.append("match start did not confine the mouse to the window")

    # Feature 1: double-click selects every on-screen unit of the same type.
    var soldier_ids: Array[int] = []
    for id: int in game.sim.units:
        if game.sim.units[id].owner == 1 and game.sim.units[id].type == "soldier":
            soldier_ids.append(id)
    if soldier_ids.size() < 2:
        failures.append("expected two friendly soldiers")
    else:
        var first_pos: Vector2 = game.sim.units[soldier_ids[0]].pos
        game._left_click(first_pos)
        game._left_click(first_pos)
        for id: int in soldier_ids:
            if not game.selected_units.has(id):
                failures.append("double-click missed same-type unit %d" % id)

    # Feature 3: Ctrl+N assigns, N recalls, Shift+N appends; buildings can group too.
    game._clear_selection()
    for id: int in soldier_ids:
        game.selected_units.append(id)
    game._control_group_key(2, true, false)
    var group_state: Dictionary = game.control_groups.get(2) as Dictionary
    if (group_state.get("units") as Array).size() != soldier_ids.size():
        failures.append("Ctrl+2 did not assign the selection")
    game._clear_selection()
    game._control_group_key(2, false, false)
    if game.selected_units.size() != soldier_ids.size():
        failures.append("pressing 2 did not recall the group")
    var harvester_id: int = game.sim.add_unit(1, "harvester", Vector2(700, 900))
    game._clear_selection()
    game._clear_selection()
    game.selected_units.append(harvester_id)
    game._control_group_key(2, false, true)
    group_state = game.control_groups.get(2) as Dictionary
    if (group_state.get("units") as Array).size() != soldier_ids.size() + 1:
        failures.append("Shift+2 did not append to the group")
    # A building-only group must be recallable by pressing its number.
    game._clear_selection()
    game.selected_building = 1
    game._control_group_key(3, true, false)
    game._clear_selection()
    game._control_group_key(3, false, false)
    if game.selected_building != 1:
        failures.append("pressing 3 did not recall the building group")
    # A mixed group recalls its units first (they receive orders).
    game._clear_selection()
    game.selected_building = 1
    game._control_group_key(2, false, true)
    game._clear_selection()
    game._control_group_key(2, false, false)
    if game.selected_units.size() != soldier_ids.size() + 1 or game.selected_building != -1:
        failures.append("mixed group recall did not prefer units")

    # Feature 2: bottom bar shows current production progress and queue.
    var refinery_id: int = game.sim._add_building(1, "refinery", Vector2(288, 432), true)
    game._clear_selection()
    game.selected_building = refinery_id
    var order_error: String = game.sim.command(1, {"action": "produce", "building": refinery_id, "type": "harvester"})
    if not order_error.is_empty():
        failures.append("produce order rejected: " + order_error)
    game.sim.step()
    game._refresh_ui()
    if not game.production_bar.visible:
        failures.append("production progress bar not visible")
    if not game.production_queue_label.text.contains("HARVESTER"):
        failures.append("production queue does not list the job")

    # Feature 4: rally point sends freshly produced units to the marker.
    game._right_click(Vector2(600, 500))
    var expected_rally := Vector2(608, 512)
    if (game.sim.buildings[refinery_id].rally as Vector2) != expected_rally:
        failures.append("rally point not set/snapped: %s" % str(game.sim.buildings[refinery_id].rally))
    var guard := 0
    while not game.sim.buildings[refinery_id].queue.is_empty() and guard < 160:
        game.sim.step()
        guard += 1
    var rallied := false
    for id: int in game.sim.units:
        var u: Dictionary = game.sim.units[id]
        if u.type == "harvester" and u.order == "move" and (u.target as Vector2) == expected_rally:
            rallied = true
    if not rallied:
        failures.append("produced harvester did not receive the rally move order")

    # Building double-click selects all on-screen same-type buildings.
    game.sim.reset(true)
    game.sim.command(1, {"action": "build", "type": "barracks", "pos": Vector2(704, 320)})
    var first_barracks: int = game.sim.next_id - 1
    game.sim.buildings[first_barracks].remaining = 0
    game.sim.command(1, {"action": "build", "type": "barracks", "pos": Vector2(900, 500)})
    var second_barracks: int = game.sim.next_id - 1
    game.sim.buildings[second_barracks].remaining = 0
    game._clear_selection()
    game._left_click(game.sim.buildings[first_barracks].pos)
    game._left_click(game.sim.buildings[first_barracks].pos)
    if game.selected_buildings.size() != 2:
        failures.append("double-click did not select all same-type buildings")
    else:
        # Production orders spread across selected producers by shortest queue.
        for i in range(4):
            game._produce("soldier")
        var queue_sizes := []
        for id: int in game.selected_buildings:
            queue_sizes.append(game.sim.buildings[id].queue.size())
        if queue_sizes != [2, 2]:
            failures.append("production not distributed: %s" % str(queue_sizes))
    # Mixed-type selections cycle their action panel with Tab.
    game._clear_selection()
    game.selected_units.append(3)
    var mixed_miner: int = game.sim.add_unit(1, "harvester", Vector2(700, 900))
    game.selected_units.append(mixed_miner)
    game._refresh_ui()
    var attack_text: String = game.action_buttons[2].text
    var tab_event := InputEventKey.new()
    tab_event.keycode = KEY_TAB
    tab_event.pressed = true
    game._unhandled_input(tab_event)
    game._refresh_ui()
    if game.action_buttons[2].text == attack_text:
        failures.append("Tab did not cycle the mixed-type action panel")
    # Group cards show the number and the first unit name; clicking recalls.
    game._control_group_key(5, true, false)
    game._refresh_ui()
    if not game.group_cards[4].text.contains("SOLDIER"):
        failures.append("group card missing first unit name")
    game._clear_selection()
    game.group_cards[4].emit_signal("pressed")
    if game.selected_units.size() != 2:
        failures.append("group card click did not recall the group")

    # Bunker: placed directly like a barracks, constructed with progress, then auto-fires.
    game.sim.reset(true)
    var bunker_error: String = game.sim.command(1, {"action": "build", "type": "bunker", "pos": Vector2(256, 64)})
    if not bunker_error.is_empty():
        failures.append("bunker placement rejected: " + bunker_error)
    var bunker_id := -1
    for id: int in game.sim.buildings:
        if game.sim.buildings[id].type == "bunker" and game.sim.buildings[id].owner == 1:
            bunker_id = id
            break
    if bunker_id < 0:
        failures.append("bunker was not placed directly")
    else:
        if int(game.sim.buildings[bunker_id].remaining) <= 0:
            failures.append("bunker should construct with a progress timer")
        var bunker_guard := 0
        while int(game.sim.buildings[bunker_id].remaining) > 0 and bunker_guard < 160:
            game.sim.step()
            bunker_guard += 1
        var bunker: Dictionary = game.sim.buildings[bunker_id]
        var raider: int = game.sim.add_unit(2, "soldier", (bunker.pos as Vector2) + Vector2(60, 0))
        game.sim.units[raider].hp = 100
        game.sim.step()
        game.sim.step()
        game.sim.step()
        if game.sim.units[raider].hp >= 100:
            failures.append("bunker did not fire at the enemy in range")
        if game.sim.units.has(bunker_id):
            failures.append("bunker unexpectedly registered as a movable unit")

    game.return_to_title()
    if DisplayServer.get_name() != "headless" and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
        failures.append("returning to the title did not release the mouse")
    print("FEATURES_TEST failures=", failures)
    quit(0 if failures.is_empty() else 1)
