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
    var harvester_id := -1
    for id: int in game.sim.units:
        if game.sim.units[id].owner == 1 and game.sim.units[id].type == "harvester":
            harvester_id = id
            break
    if harvester_id < 0:
        failures.append("no friendly harvester for group append test")
    else:
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
