extends SceneTree
const MAIN = preload("res://scenes/main.tscn")
const PROBE = preload("res://tests/network/network_probe.gd")

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    Engine.max_fps = 120
    var game := MAIN.instantiate()
    game.selected_map_id = "desert_quarry"
    for argument: String in OS.get_cmdline_user_args():
        if argument.begins_with("--map="):
            game.selected_map_id = argument.trim_prefix("--map=")
    root.add_child(game)
    var probe = preload("res://tests/network/weak_network_probe.gd").new() if "--weak" in OS.get_cmdline_user_args() else PROBE.new()
    probe.name = "NetworkProbe"
    probe.game = game
    for argument: String in OS.get_cmdline_user_args():
        if argument.begins_with("--role="):
            probe.role = argument.trim_prefix("--role=")
        elif argument.begins_with("--round="):
            probe.round_number = int(argument.trim_prefix("--round="))
        elif argument.begins_with("--port="):
            game.connection_port = int(argument.trim_prefix("--port="))
    game.bind_ip = "127.0.0.1"
    if probe.role == "mismatch":
        game.multiplayer.connected_to_server.disconnect(game._connected_to_server)
    root.add_child(probe)
    print("NETWORK_BOOTSTRAP_READY")
    probe.start()
