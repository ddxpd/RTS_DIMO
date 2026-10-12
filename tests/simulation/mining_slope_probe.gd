extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
    if not ok and not failures.has(message):
        failures.append(message)
        push_error(message)

func _initialize() -> void:
    var sim := Sim.new()
    sim.reset(false, "desert_sample")
    # Reproduce the reported geometry without restoring removed initial ore.
    sim.ores[1] = {"pos": Vector2(1776, 1712), "amount": 100000}
    sim._add_building(1, "refinery", Vector2(2336, 1200), true)
    sim.rebuild_navigation()
    var ids: Array = []
    for i in range(6):
        var id := sim.add_unit(1, "harvester", Vector2(1840 + (i % 2) * 112, 1168 + (i / 2) * 112))
        ids.append(id)
    sim.command(1, {"action": "gather", "units": ids, "target": 1})
    var harvested: Dictionary = {}
    var start_money: int = sim.money[1]
    for tick in range(4000):
        var previous: Dictionary = {}
        for id: int in ids:
            previous[id] = sim.units[id].pos
        sim.step()
        for id: int in ids:
            check(sim.movement_free(previous[id], sim.units[id].pos, 48.0), "Slope motion never crosses static terrain")
            if sim.units[id].cargo > 0:
                harvested[id] = true
        check(Sim.MiningSystem.counts(sim, 1).x <= 5, "Slope reservation capacity")
        if tick % 200 == 199:
            check(sim.validate_snapshot(sim.snapshot()), "Valid slope snapshot: " + sim.last_snapshot_error)
            var states: Array = []
            for id: int in ids:
                var u: Dictionary = sim.units[id]
                states.append({"id": id, "pos": str(u.pos), "cargo": u.cargo, "stuck": u.stuck, "mining": str(u.get("mining", {})), "path": str(u.path.slice(0, 4)), "clear": u.path.is_empty() or sim.movement_free(u.pos, u.path[0], 48.0)})
            print("SLOPE_PROBE ", tick, " ", JSON.stringify(states))
        if harvested.size() == ids.size() and sim.money[1] - start_money >= 360:
            break
    check(harvested.size() == ids.size(), "Every slope worker eventually harvests")
    check(sim.money[1] - start_money >= 360, "Six loads delivered from slope")
    var cargo := 0
    for id: int in ids:
        cargo += sim.units[id].cargo
    check(100000 - sim.ores[1].amount == sim.money[1] - start_money + cargo, "Slope mineral conservation")
    print("SLOPE_RESULT frames=", sim.frame, " workers=", harvested.size(), " credited=", sim.money[1] - start_money, " failures=", failures)
    quit(0 if failures.is_empty() else 1)
