extends SceneTree
## Fixed-wrapper entry point for the same checks used by the MCP preview scene.


func _initialize() -> void:
    run.call_deferred()


func run() -> void:
    var scene: Node = load("res://tests/previews/mobile_infantry_runtime_checks.tscn").instantiate()
    scene.finished.connect(func(success: bool) -> void: quit(0 if success else 1))
    root.add_child(scene)
    # Fail closed if a script error interrupts the asynchronous runner.
    create_timer(90.0).timeout.connect(func() -> void: quit(1))
