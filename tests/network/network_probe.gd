extends Node
var game: Node
var role := "host"
var round_number := 1
var reports := 0
var deadline := 0
var failed := false
var saw_dock_entry := false
var saw_dock_exit := false
var saw_mobile_unit_hit := false
var saw_mobile_building_hit := false

func _observe_impacts(_frame: int) -> void:
    for unit: Dictionary in game.sim.units.values():
        if unit.has("dock"):
            saw_dock_entry = saw_dock_entry or unit.dock.phase == "enter"
            saw_dock_exit = saw_dock_exit or unit.dock.phase == "exit"
    for event: Dictionary in game.sim.effects:
        if event.has("impact") and event.impact.source_type == "mobile_infantry":
            if event.impact.target_kind == "unit" and event.impact.target_id == 5:
                saw_mobile_unit_hit = true
            if event.impact.target_kind == "building" and event.impact.target_id == 1:
                saw_mobile_building_hit = true

func check(condition: bool, message: String) -> bool:
    if not condition:
        failed = true
        push_error("NETWORK_TEST " + role + ": " + message)
        get_tree().quit(1)
    return condition

func _process(_delta: float) -> void:
    if deadline > 0 and Time.get_ticks_msec() > deadline and not failed:
        check(false, "Timeout")

func start() -> void:
    deadline = Time.get_ticks_msec() + 180000
    if role == "host":
        game.create_host()
        check(game.connected, "Host bind")
        check(game.sim.units.is_empty() and game.sim.buildings.size() == 2, "Network host starts with bases only")
        preload("res://tests/fixtures/army_setup.gd").seed(game.sim)
    elif role == "mismatch":
        game.join_host()
        while game.peer == null or game.peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
            await get_tree().process_frame
        # The normal hello is suppressed by runner; send an incompatible protocol.
        game._hello.rpc_id(1, "obsolete-client")
        await get_tree().create_timer(1).timeout
        check(not game.connected and not game.active, "Version mismatch rejected")
        print("NETWORK_TEST PASS protocol mismatch")
        get_tree().quit(0)
    elif role == "spectator":
        game.join_host()
        while not game.connected:
            await get_tree().process_frame
        if not check(game.local_slot == 0, "Extra guest assigned spectator"):
            return
        game._order.rpc_id(1, {"action": "move", "units": [3], "pos": Vector2(600, 600), "owner": 1})
        await get_tree().create_timer(0.4).timeout
        if not check(game.sim.units[3].pos == Vector2(640, 256), "Host rejects forged spectator order"):
            return
        print("NETWORK_TEST PASS spectator permissions")
        get_tree().quit(0)
    else:
        await guest()

func guest() -> void:
    game.network_session.snapshot_applied.connect(_observe_impacts)
    game.join_host()
    while not game.connected:
        await get_tree().process_frame
    if not check(game.local_slot == 2, "Red slot assigned on join/reconnect"):
        return
    if not check(game.sim.map_id == game.selected_map_id, "Host-selected map identity replicated"):
        return
    print("NETWORK_STAGE joined round ", round_number, " map=", game.sim.map_id, " checksum=", game.sim.terrain.checksum)
    if round_number == 2:
        _request_restart.rpc_id(1)
        while game.sim.winner != 0 or game.sim.frame > 100:
            await get_tree().process_frame
        if not check(game.sim.units.is_empty() and game.sim.buildings.size() == 2, "Base-only restart replicated to guest"):
            return
        _setup_restart_army.rpc_id(1)
        while game.sim.units.is_empty():
            await get_tree().process_frame
        var mover := -1
        for id: int in game.sim.units:
            if game.sim.units[id].owner == 2:
                mover = id
                break
        if not check(mover >= 0, "Red mover exists after restart"):
            return
        var destination := Vector2(4000, 2800)
        game.issue({"action": "move", "units": [mover], "pos": destination})
        while (game.sim.units[mover].pos as Vector2).distance_to(destination) > 5:
            await get_tree().process_frame
        _freeze_report.rpc_id(1)
        return
    game._left_click(game.sim.units[3].pos)
    if not check(game.selected_units.is_empty(), "Enemy selection disallowed"):
        return
    # Measure RPC applications rather than render frames, which can receive batches.
    var received: Array[int] = []
    var record := func(frame: int) -> void: received.append(frame)
    game.network_session.snapshot_applied.connect(record)
    while received.size() < 31:
        await get_tree().process_frame
    game.network_session.snapshot_applied.disconnect(record)
    var interval_ok := true
    for index in range(1, received.size()):
        interval_ok = interval_ok and received[index] - received[index - 1] == 1
    if not check(interval_ok, "Guest receives one snapshot per logic tick (20 Hz)"):
        return
    if not check(game.render_velocities.size() >= game.sim.units.size() - 1, "Guest computes render velocities"):
        return
    # The refinery economy: build the drop-off, produce a miner, then gather.
    _setup_mining_capacity.rpc_id(1)
    while not game.sim.ores.has(250):
        await get_tree().process_frame
    print("NETWORK_STAGE capacity fixture replicated")
    var capacity_ids: Array = []
    for id: int in game.sim.units:
        if game.sim.units[id].type == "harvester" and game.sim.units[id].owner == 2:
            capacity_ids.append(id)
    game.issue({"action": "gather", "units": capacity_ids, "target": 250})
    var capacity_start: int = game.sim.frame
    while game.sim.MiningSystem.counts(game.sim, 250).x < 5:
        if game.sim.frame - capacity_start > 40:
            check(false, "Mining capacity setup failed: " + str(game.sim.MiningSystem.counts(game.sim, 250)))
            return
        await get_tree().process_frame
    if not check(game.sim.MiningSystem.counts(game.sim, 250) == Vector2i(5, 1), "Five mining reservations and one waiter replicated"):
        return
    game.issue({"action": "stop", "units": [capacity_ids[0]]})
    while not game.sim.MiningSystem.reserved(game.sim.units[capacity_ids[5]]):
        await get_tree().process_frame
    if not check(game.sim.MiningSystem.counts(game.sim, 250).x == 5, "Released mining slot promoted on host and replicated"):
        return
    _clear_mining_capacity.rpc_id(1)
    while game.sim.ores.has(250):
        await get_tree().process_frame
    print("NETWORK_STAGE mining capacity replicated")
    game.issue({"action": "build", "type": "refinery", "pos": Vector2(4416, 2496)})
    var refinery := -1
    while refinery < 0:
        for id: int in game.sim.buildings:
            if game.sim.buildings[id].owner == 2 and game.sim.buildings[id].type == "refinery":
                refinery = id
        await get_tree().process_frame
    while game.sim.buildings[refinery].remaining > 0:
        await get_tree().process_frame
    game.selected_building = refinery
    game.issue({"action": "set_rally", "building": refinery, "mode": "ore", "ore": 2, "pos": game.sim.ores[2].pos})
    while game.sim.buildings[refinery].rally_mode != "ore":
        await get_tree().process_frame
    if not check(game.sim.buildings[refinery].rally_ore == 2, "Guest mining rally accepted by host and replicated"):
        return
    game._produce("harvester")
    var miner := -1
    while miner < 0:
        for id: int in game.sim.units:
            if game.sim.units[id].owner == 2 and game.sim.units[id].type == "harvester":
                miner = id
                break
        await get_tree().process_frame
    game._clear_selection()
    if not check(game.sim.units[miner].order == "gather" and game.sim.units[miner].ore == 2, "New miner follows authoritative ore rally without a second order"):
        return
    game._left_click(game.sim.units[miner].pos)
    if not check(game.selected_units == [miner], "Friendly produced miner selection"):
        return
    game._right_click(game.sim.ores[2].pos)
    while game.sim.money[2] < 5460:
        await get_tree().process_frame
    if not check(saw_dock_entry and saw_dock_exit, "Authoritative dock entry and credited exit replicated"):
        return
    print("NETWORK_STAGE mined ", game.sim.money[2])
    var training_site := Vector2(4128, 2304)
    var training_error: String = game.sim.build_error(2, "barracks", training_site)
    if not check(training_error.is_empty(), "Network training site valid: " + training_error):
        return
    game.issue({"action": "build", "type": "barracks", "pos": training_site})
    var barracks := -1
    while barracks < 0:
        for id: int in game.sim.buildings:
            if game.sim.buildings[id].owner == 2 and game.sim.buildings[id].type == "barracks":
                barracks = id
        await get_tree().process_frame
    while game.sim.buildings[barracks].remaining > 0:
        await get_tree().process_frame
    print("NETWORK_STAGE built")
    if not check(game.sim.buildings[barracks].pos == game.sim.snap_building("barracks", training_site), "Host snaps odd-depth building onto shared grid"):
        return
    var adjoining_site := Vector2.ZERO
    for offset: Vector2 in [Vector2(96, -16), Vector2(-96, -16), Vector2(-32, 80), Vector2(-32, -80)]:
        var candidate: Vector2 = game.sim.buildings[barracks].pos + offset
        if game.sim.build_error(2, "bunker", candidate).is_empty():
            adjoining_site = candidate
            break
    if not check(adjoining_site != Vector2.ZERO, "Guest finds a directly adjoining grid footprint"):
        return
    game.issue({"action": "build", "type": "bunker", "pos": adjoining_site})
    var adjoining := -1
    while adjoining < 0:
        for id: int in game.sim.buildings:
            if game.sim.buildings[id].owner == 2 and game.sim.buildings[id].type == "bunker" and game.sim.buildings[id].pos == adjoining_site:
                adjoining = id
        await get_tree().process_frame
    if not check(not game.sim.footprint(game.sim.buildings[barracks]).intersects(game.sim.footprint(game.sim.buildings[adjoining])), "Adjacent foundation replicated without overlap"):
        return
    print("NETWORK_STAGE adjoining grid build replicated")
    game.selected_building = barracks
    game.issue({"action": "set_rally", "building": barracks, "pos": training_site + Vector2(-160, 160)})
    while game.sim.buildings[barracks].rally_mode != "ground":
        await get_tree().process_frame
    var rally_position: Vector2 = game.sim.buildings[barracks].rally
    # Preserve the existing extra mining cycle after paying for the new
    # adjoining-building regression fixture as well as the training building.
    var funding_target: int = 5310 - int(game.sim.BUILD_TYPES.bunker.cost)
    print("NETWORK_STAGE funding ", game.sim.money[2], " target=", funding_target)
    while game.sim.money[2] < funding_target:
        await get_tree().process_frame
    game.feedback = ""
    game.issue({"action": "produce", "building": barracks, "type": "soldier"})
    var retired_deadline := Time.get_ticks_msec() + 5000
    while not game.feedback.contains("currently unavailable") and Time.get_ticks_msec() < retired_deadline:
        await get_tree().process_frame
    if not check(game.feedback.contains("currently unavailable") and game.sim.buildings[barracks].queue.is_empty(), "Host rejects guest request for retired soldier"):
        return
    game._produce("mobile_infantry")
    while game.sim.units.size() < 14:
        await get_tree().process_frame
    print("NETWORK_STAGE produced")
    while not game.sim.buildings[barracks].queue.is_empty():
        await get_tree().process_frame
    game.issue({"action": "barracks_takeoff", "building": barracks})
    var takeoff_deadline := Time.get_ticks_msec() + 8000
    while game.sim.buildings[barracks].flight.state != "airborne":
        if Time.get_ticks_msec() > takeoff_deadline:
            check(false, "Takeoff timeout: " + str(game.sim.buildings[barracks].flight) + " / " + game.feedback)
            return
        await get_tree().process_frame
    if not check(game.sim.buildings[barracks].flight.height > 100, "Airborne height replicated"):
        return
    var turn_origin: Vector2 = game.sim.buildings[barracks].pos
    game.issue({"action": "barracks_move", "building": barracks, "pos": turn_origin + Vector2(96, 0)})
    var saw_turn := false
    while (game.sim.buildings[barracks].pos as Vector2).is_equal_approx(turn_origin):
        var heading: float = game.sim.buildings[barracks].flight.heading
        if absf(heading) > 0.01 and absf(heading) < PI / 2.0 - 0.01:
            saw_turn = true
        await get_tree().process_frame
    if not check(saw_turn and absf(angle_difference(game.sim.buildings[barracks].flight.heading, -PI / 2.0)) < .001,
            "Stationary turn then aligned translation replicated"):
        return
    game.issue({"action": "barracks_stop", "building": barracks})
    while game.sim.buildings[barracks].flight.moving:
        await get_tree().process_frame
    var stopped_heading: float = game.sim.buildings[barracks].flight.heading
    await get_tree().create_timer(.2).timeout
    if not check(is_equal_approx(game.sim.buildings[barracks].flight.heading, stopped_heading), "Stopped heading persists on guest"):
        return
    # Keep the deployed hull clear of the soldier waiting outside the production door.
    var landing_site := training_site + Vector2(0, -192)
    var landing_error: String = game.sim.deployment_site(2, barracks, landing_site).error
    if not check(landing_error.is_empty(), "Network landing site valid: " + landing_error):
        return
    game.issue({"action": "barracks_deploy", "building": barracks, "pos": landing_site})
    while game.sim.buildings[barracks].flight.state != "landing":
        await get_tree().process_frame
    if not check(game.sim.buildings[barracks].pos == game.sim.snap_building("barracks", landing_site), "Aligned deployment reservation position replicated"):
        return
    if not check(is_zero_approx(game.sim.buildings[barracks].flight.heading), "Landing restores default heading on guest"):
        return
    while game.sim.buildings[barracks].flight.state != "grounded":
        await get_tree().process_frame
    if not check(is_equal_approx(game.sim.buildings[barracks].flight.height, game.sim.terrain.height_at(landing_site)), "Landing height replicated"):
        return
    print("NETWORK_STAGE barracks relocation replicated")
    if not check(game.sim.buildings[barracks].rally == rally_position, "Rally survives replicated takeoff and landing"):
        return
    game.issue({"action": "set_rally", "building": barracks, "mode": "none"})
    while game.sim.buildings[barracks].rally_mode != "none":
        await get_tree().process_frame
    if not check(game.sim.buildings[barracks].rally_ore == -1, "Clear rally replicated"):
        return
    _setup_target.rpc_id(1)
    while (game.sim.units[5].pos as Vector2).distance_to(Vector2(1050, 768)) > 5.0:
        await get_tree().process_frame
    var striker := -1
    for id: int in game.sim.units:
        if game.sim.units[id].owner == 2 and game.sim.units[id].type == "mobile_infantry":
            striker = id
            break
    if not check(striker >= 0, "Independent mobile infantry attacker replicated"):
        return
    game._left_click(game.sim.units[striker].pos)
    game._right_click(Vector2(1050, 768))
    print("NETWORK_STAGE attack ordered frame=", game.sim.frame, " selected=", game.selected_units, " from=", game.sim.units[striker].pos)
    while game.sim.units.has(5):
        await get_tree().process_frame
    if not check(saw_mobile_unit_hit, "Mobile infantry target-bound unit impact replicated"):
        return
    print("NETWORK_STAGE killed unit")
    _setup_base.rpc_id(1)
    while game.sim.buildings[1].pos != game.sim.snap_building("base", Vector2(950, 800)):
        await get_tree().process_frame
    game._right_click(Vector2(950, 800))
    while game.sim.winner == 0:
        await get_tree().process_frame
    _observe_impacts(game.sim.frame)
    if not check(saw_mobile_building_hit, "Lethal building impact replicated after target removal"):
        return
    if not check(game.sim.winner == 2 and not game.sim.buildings.has(1), "Attack and victory replicated"):
        return
    _compare.rpc_id(1, game.sim.snapshot())

@rpc("any_peer", "reliable")

func _setup_target() -> void:
    if role == "host":
        game.sim.units[5].pos = Vector2(1050, 768)
        game.sim.units[5].hp = 32
        game.sim.add_unit(2, "mobile_infantry", Vector2(1050, 864))

@rpc("any_peer", "reliable")
func _setup_mining_capacity() -> void:
    if role != "host":
        return
    game.sim.ores[250] = {"pos": Vector2(1616, 1904), "amount": 5000}
    for i in range(6):
        var point := Vector2(1488 + (i % 3) * 112, 1712 + (i / 3) * 112)
        if not check(game.sim.position_free(point, 48.0), "Capacity fixture starts on clear flat terrain"):
            return
        var id: int = game.sim.add_unit(2, "harvester", point)
        game.sim.units[id].auto = false
    game.sim.update_visibility()
    check(game.sim.validate_snapshot(game.sim.snapshot()), "Capacity fixture snapshot valid: " + game.sim.last_snapshot_error)
    print("NETWORK_STAGE capacity fixture created")

@rpc("any_peer", "reliable")
func _clear_mining_capacity() -> void:
    if role != "host":
        return
    for id: int in game.sim.units.keys():
        if game.sim.units[id].type == "harvester":
            game.sim.units.erase(id)
    game.sim.ores.erase(250)

@rpc("any_peer", "reliable")

func _setup_base() -> void:
    if role == "host":
        game.sim.buildings[1].pos = game.sim.snap_building("base", Vector2(950, 800))
        game.sim.buildings[1].hp = 16
        game.sim.rebuild_navigation()

@rpc("any_peer", "reliable")

func _request_restart() -> void:
    if role == "host":
        game.restart_match()


@rpc("any_peer", "reliable")
func _setup_restart_army() -> void:
    if role == "host":
        preload("res://tests/fixtures/army_setup.gd").seed(game.sim)

@rpc("any_peer", "reliable")

func _freeze_report() -> void:
    if role == "host":
        game.active = false
        _frozen.rpc_id(multiplayer.get_remote_sender_id(), game.sim.snapshot())

@rpc("authority", "reliable")

func _frozen(state: Dictionary) -> void:
    game.sim.apply_snapshot(state)
    _compare.rpc_id(1, game.sim.snapshot())

@rpc("any_peer", "reliable")

func _compare(state: Dictionary) -> void:
    if role != "host":
        return
    if not check(state == game.sim.snapshot(), "All replicated state identical including money / queues / HP / result"):
        return
    reports += 1
    print("NETWORK_TEST PASS round ", reports, " complete snapshot identical")
    _passed.rpc_id(multiplayer.get_remote_sender_id())
    if reports == 2:
        await get_tree().create_timer(1).timeout
        get_tree().quit(0)

@rpc("authority", "reliable")

func _passed() -> void:
    print("NETWORK_TEST PASS guest round ", round_number)
    if round_number == 2:
        await game.multiplayer.server_disconnected
        await get_tree().process_frame
        if not check(not game.active and not game.connected, "Host exit stops guest simulation"):
            return
        print("NETWORK_TEST PASS host disconnect handled")
    else:
        await get_tree().create_timer(0.3).timeout
    get_tree().quit(0)
