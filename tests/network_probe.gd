extends Node
var game: Node
var role := "host"
var round_number := 1
var reports := 0
var deadline := 0
var failed := false

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
	deadline = Time.get_ticks_msec() + 55000
	if role == "host":
		game.create_host()
		check(game.connected, "Host bind")
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
		if not check(game.sim.units[3].pos == Vector2(304, 160), "Host rejects forged spectator order"):
			return
		print("NETWORK_TEST PASS spectator permissions")
		get_tree().quit(0)
	else:
		await guest()

func guest() -> void:
	game.join_host()
	while not game.connected:
		await get_tree().process_frame
	if not check(game.local_slot == 2, "Red slot assigned on join/reconnect"):
		return
	print("NETWORK_STAGE joined round ", round_number)
	if round_number == 2:
		_request_restart.rpc_id(1)
		while game.sim.winner != 0 or game.sim.frame > 100:
			await get_tree().process_frame
		game.issue({"action": "move", "units": [6], "pos": Vector2(1200, 850)})
		while (game.sim.units[6].pos as Vector2).distance_to(Vector2(1200, 850)) > 5:
			await get_tree().process_frame
		_freeze_report.rpc_id(1)
		return
	game._left_click(game.sim.units[3].pos)
	if not check(game.selected_units.is_empty(), "Enemy selection disallowed"):
		return
	game._left_click(game.sim.units[8].pos)
	if not check(game.selected_units == [8], "Friendly harvester selection"):
		return
	game._right_click(game.sim.ores[2].pos)
	while game.sim.money[2] < 660:
		await get_tree().process_frame
	print("NETWORK_STAGE mined ", game.sim.money[2])
	game.issue({"action": "build", "type": "barracks", "pos": Vector2(1152, 768)})
	var barracks := -1
	while barracks < 0:
		for id: int in game.sim.buildings:
			if game.sim.buildings[id].owner == 2 and game.sim.buildings[id].type == "barracks":
				barracks = id
		await get_tree().process_frame
	while game.sim.buildings[barracks].remaining > 0:
		await get_tree().process_frame
	print("NETWORK_STAGE built")
	game.selected_building = barracks
	game._produce("soldier")
	while game.sim.units.size() < 7:
		await get_tree().process_frame
	print("NETWORK_STAGE produced")
	_setup_target.rpc_id(1)
	while game.sim.units[5].pos != Vector2(1050, 768):
		await get_tree().process_frame
	game._left_click(game.sim.units[6].pos)
	game._right_click(Vector2(1050, 768))
	while game.sim.units.has(5):
		await get_tree().process_frame
	print("NETWORK_STAGE killed unit")
	_setup_base.rpc_id(1)
	while game.sim.buildings[1].pos != Vector2(950, 800):
		await get_tree().process_frame
	game._right_click(Vector2(950, 800))
	while game.sim.winner == 0:
		await get_tree().process_frame
	if not check(game.sim.winner == 2 and not game.sim.buildings.has(1), "Attack and victory replicated"):
		return
	_compare.rpc_id(1, game.sim.snapshot())

@rpc("any_peer", "reliable")
func _setup_target() -> void:
	if role == "host":
		game.sim.units[5].pos = Vector2(1050, 768)
		game.sim.units[5].hp = 32

@rpc("any_peer", "reliable")
func _setup_base() -> void:
	if role == "host":
		game.sim.buildings[1].pos = Vector2(950, 800)
		game.sim.buildings[1].hp = 16
		game.sim.rebuild_navigation()

@rpc("any_peer", "reliable")
func _request_restart() -> void:
	if role == "host":
		game.restart_match()

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
