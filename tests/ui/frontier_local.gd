extends SceneTree
var failures := []

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    var app = load("res://scenes/frontier.tscn").instantiate()
    root.add_child(app)
    app._local_server()
    await create_timer(4.0).timeout
    app.service.send("create")
    await create_timer(0.8).timeout
    if app.lobby.is_empty():
        failures.append("local service connects and creates room")
    else:
        var config: Dictionary = app.lobby.config.duplicate(true)
        config.seats[1] = "ai"
        app.service.send("configure", config)
        await create_timer(0.4).timeout
        app.service.send("ready")
        await create_timer(0.4).timeout
        app.service.send("start")
        await create_timer(4.0).timeout
        if app.game == null or not app.game.connected or app.game.sim.frame < 1:
            failures.append("graphical client enters independently hosted match")
        app.return_home()
        await create_timer(0.3).timeout
        if app.game != null or app.mode != "home":
            failures.append("leave match returns home")
    app.service.disconnect_service()
    if app.local_pid > 0 and OS.is_process_running(app.local_pid):
        OS.kill(app.local_pid)
    app.queue_free()
    await process_frame
    print("FRONTIER_LOCAL ", JSON.stringify({"passed": failures.is_empty(), "failures": failures}))
    quit(0 if failures.is_empty() else 1)
