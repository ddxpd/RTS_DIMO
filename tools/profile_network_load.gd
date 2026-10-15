extends SceneTree
const Sim = preload("res://scripts/simulation.gd")

func _initialize() -> void:
    var sim := Sim.new()
    sim.reset(false, "desert_quarry")
    for count: int in [50, 100, 200]:
        sim.units.clear()
        var red: Array[int] = []
        for index in range(count):
            var owner := 1 if index < count / 2 else 2
            var local_index := index % (count / 2)
            var id := sim.add_unit(owner, "mobile_infantry", Vector2(2080 + (local_index % 10) * 32, (1250 if owner == 1 else 1800) + (local_index / 10) * 32))
            if owner == 2:
                red.append(id)
        var command_us := 0
        var max_command_us := 0
        var step_us := 0
        var serialization_us := 0
        var snapshot_bytes := 0
        for tick in range(1200):
            if tick % 20 == 0:
                var selected: Array[int] = []
                var number := tick / 20
                for index in range(mini(12, red.size())):
                    selected.append(red[(number * 12 + index) % red.size()])
                var started := Time.get_ticks_usec()
                sim.command(2, {"action": "move", "units": selected, "pos": Vector2(2080 + (number % 4) * 128, 1800 + ((number / 4) % 3) * 96)})
                var elapsed := Time.get_ticks_usec() - started
                command_us += elapsed
                max_command_us = maxi(max_command_us, elapsed)
            if tick % 160 == 0:
                for id: int in sim.units:
                    if sim.units[id].owner == 1:
                        sim.command(1, {"action": "move", "units": [id], "pos": Vector2(2080 + (id % 10) * 32 + ((tick / 160) % 2) * 160, 1250 + ((id / 10) % 10) * 32)})
            var started := Time.get_ticks_usec()
            sim.step()
            step_us += Time.get_ticks_usec() - started
            started = Time.get_ticks_usec()
            snapshot_bytes += var_to_bytes(sim.snapshot()).size()
            serialization_us += Time.get_ticks_usec() - started
        print("NETWORK_LOAD_CPU ", JSON.stringify({"units": count, "command_mean_ms": command_us / 60000.0, "command_max_ms": max_command_us / 1000.0, "tick_mean_ms": step_us / 1200000.0, "snapshot_mean_ms": serialization_us / 1200000.0, "snapshot_mean_bytes": snapshot_bytes / 1200}))
    quit()
