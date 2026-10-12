extends SceneTree

class ProfileSimulation extends "res://scripts/simulation.gd":
    var sight_us := 0
    var movement_us := 0
    var separation_us := 0
    func update_visibility() -> void:
        var start := Time.get_ticks_usec()
        super.update_visibility()
        sight_us += Time.get_ticks_usec() - start
    func move_towards(unit: Dictionary, destination: Vector2, stop_distance: float = 4.0) -> void:
        var start := Time.get_ticks_usec()
        super.move_towards(unit, destination, stop_distance)
        movement_us += Time.get_ticks_usec() - start
    func _separate_units() -> void:
        var start := Time.get_ticks_usec()
        super._separate_units()
        separation_us += Time.get_ticks_usec() - start

func _initialize() -> void:
    var sim := ProfileSimulation.new()
    sim.reset(false, "desert_quarry")
    for row in range(12):
        for column in range(14):
            var p := Vector2(600 + column * 95, 300 + row * 105)
            p = sim.nav.get_point_position(sim.nearest_cell(p))
            var id := sim.add_unit(1, "soldier" if (row + column) % 3 != 0 else "harvester", p)
            sim.units[id].order = "move"
            sim.units[id].target = p + Vector2(180, 160)
    sim.sight_us = 0
    var start := Time.get_ticks_usec()
    for tick in range(80):
        sim.step()
    print("TERRAIN_PROFILE total_ms=", (Time.get_ticks_usec() - start) / 1000.0, " sight=", sim.sight_us / 1000.0, " movement=", sim.movement_us / 1000.0, " separation=", sim.separation_us / 1000.0, " cache=", sim.terrain.visibility_cache.size())
    quit()
