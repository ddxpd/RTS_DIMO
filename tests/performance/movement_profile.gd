extends SceneTree

class ProfileSim extends "res://scripts/simulation.gd":
    var times := {}
    func record(key: String, started: int) -> void:
        times[key] = times.get(key, 0) + Time.get_ticks_usec() - started
    func move_towards(u: Dictionary, destination: Vector2, stop_distance: float = 4.0) -> void:
        var started := Time.get_ticks_usec()
        super.move_towards(u, destination, stop_distance)
        record("move", started)
    func movement_free(from: Vector2, to: Vector2, radius: float) -> bool:
        var started := Time.get_ticks_usec()
        var result := super.movement_free(from, to, radius)
        record("sweep", started)
        return result
    func _separate_units() -> void:
        var started := Time.get_ticks_usec()
        super._separate_units()
        record("separation", started)
    func update_visibility() -> void:
        var started := Time.get_ticks_usec()
        super.update_visibility()
        record("visibility", started)

func _initialize() -> void:
    var sim := ProfileSim.new()
    sim.reset()
    for row in range(12):
        for column in range(14):
            var kind := "soldier" if (row + column) % 3 != 0 else "harvester"
            var radius: float = sim.UNIT_TYPES[kind].radius
            var position := Vector2(600 + column * 95, 300 + row * 105)
            position = sim.navigation_for(radius).get_point_position(sim.nearest_cell(position, radius))
            var id := sim.add_unit(1, kind, position)
            sim.units[id].order = "move"
            sim.units[id].target = position + Vector2(180, 160)
    sim.times.clear()
    var started := Time.get_ticks_usec()
    for tick in range(20):
        var tick_start := Time.get_ticks_usec()
        sim.step()
        print("PROFILE_TICK ", tick, " ms=", (Time.get_ticks_usec() - tick_start) / 1000.0)
    print("MOVEMENT_PROFILE total_ms=", (Time.get_ticks_usec() - started) / 1000.0, " nested_us=", sim.times)
    quit()
