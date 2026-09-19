extends SceneTree
const MAIN = preload("res://scenes/main.tscn")
const PROBE = preload("res://tests/network_probe.gd")

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    Engine.max_fps = 120
    var game := MAIN.instantiate()
    root.add_child(game)
    var probe := PROBE.new()
    probe.name = "NetworkProbe"
    probe.game = game
    for argument: String in OS.get_cmdline_user_args():
        if argument.begins_with("--role="):
            probe.role = argument.trim_prefix("--role=")
        elif argument.begins_with("--round="):
            probe.round_number = int(argument.trim_prefix("--round="))
    if probe.role == "mismatch":
        game.multiplayer.connected_to_server.disconnect(game._connected_to_server)
    root.add_child(probe)
    probe.start()
