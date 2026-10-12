extends "res://tests/simulation/simulation_systems.gd"
## One-time capture for the approved protocol11 gameplay change. Refuses overwrite.
func _initialize() -> void:
    capture = true
    run.call_deferred()
