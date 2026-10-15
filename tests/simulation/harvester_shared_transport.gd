extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
const Dock = Sim.DepotDocking
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
    run.call_deferred()


func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok and not failures.has(message):
        failures.append(message)
        push_error(message)


func fixture() -> Simulation:
    var sim := Sim.new()
    sim.reset(false, "desert_sample")
    sim.units.clear()
    sim.ores = {1: {"pos": Vector2(2256, 1168), "amount": 100000}}
    sim._add_building(1, "refinery", Vector2(2240, 1600), true)
    sim.rebuild_navigation()
    return sim


func run() -> void:
    var sim := fixture()
    var station: int = sim.next_id - 1
    var b: Dictionary = sim.buildings[station]
    var ids: Array = []
    for i in range(6):
        var id := sim.add_unit(1, "harvester", Dock.berth(b, 0))
        var u: Dictionary = sim.units[id]
        u.auto = false
        u.order = "gather"
        u.cargo = 10 * (i + 1)
        Dock.request(sim, u, station, sim.frame)
        u.dock.phase = "enter"
        Dock.destination(u, Dock.berth(b, 0))
        ids.append(id)
    var mirror := Sim.new()
    check(mirror.apply_snapshot(sim.snapshot()), "Six simultaneous overlapping unload intents accepted")
    var money: int = sim.money[1]
    sim.step()
    mirror.step()
    check(sim.money[1] == money + 210, "Six vehicles pay their exact cargo in the same tick")
    check(sim.snapshot() == mirror.snapshot(), "Concurrent settlement deterministic after snapshot")
    for id: int in ids:
        check(sim.units[id].cargo == 0 and not sim.units[id].has("dock"), "Payment clears cargo and route atomically")
        check(sim.units[id].pos == Dock.berth(b, 0), "Unloading does not push vehicles apart")
    sim.step()
    check(sim.money[1] == money + 210, "Repeated tick cannot duplicate payment")
    check(sim._spawn_position(b, "harvester") == Dock.entrance(b, 0), "Overlapping docked vehicles do not block factory")
    var enemy := sim.add_unit(2, "harvester", Dock.entrance(b, 0))
    sim.units[enemy].auto = false
    check(sim._spawn_position(b, "harvester") == Dock.entrance(b, 0), "Enemy vehicle also permits spawn overlap")
    var infantry := sim.add_unit(1, "mobile_infantry", Dock.entrance(b, 0))
    sim.units[infantry].auto = false
    check(sim._spawn_position(b, "harvester") == Vector2.ZERO, "Infantry still blocks production lane")
    check(not Sim.MiningSystem.ignore_pair(sim.units[enemy], sim.units[infantry]), "No harvesting exemption against infantry")
    sim.units.erase(infantry)
    sim.units.clear()
    ids.clear()
    for i in range(6):
        var id := sim.add_unit(1, "harvester", Vector2(2096, 880))
        sim.units[id].auto = false
        ids.append(id)
    check(sim.command(1, {"action": "move", "units": ids, "pos": Vector2(2256, 1008)}).is_empty(), "Overlapping group receives move order")
    for id: int in ids:
        sim.units[id].auto = false
        check(sim.units[id].target == sim.units[ids[0]].target, "Harvesters share arrival slot")
    for tick in range(160):
        var previous: Vector2 = sim.units[ids[0]].pos
        sim.step()
        var u: Dictionary = sim.units[ids[0]]
        var travel: Vector2 = u.pos - previous
        if travel.length_squared() > 0.001:
            check(Vector2.from_angle(u.heading).dot(travel.normalized()) > 0.999, "Translation is forward, including turns")
        for id: int in ids:
            check(sim.units[id].pos == u.pos, "Shared group moves without self avoidance or separation")
    check(sim.units[ids[0]].order == "idle", "Overlapping group reaches destination")
    sim.command(1, {"action": "gather", "units": ids, "target": 1})
    money = sim.money[1]
    var delivered := false
    var returned := false
    for tick in range(1600):
        sim.step()
        check(Sim.MiningSystem.counts(sim, 1).x <= 5, "Overlap does not increase mining capacity")
        for id: int in ids:
            var u: Dictionary = sim.units[id]
            check(u.get("mining", {}).get("phase", "") != "exit", "No collision restoration detour")
            if u.cargo == 60 and u.has("dock"):
                returned = true
                check(u.dock.station == station, "Return targets nearest reachable smelter")
        if sim.money[1] >= money + 300:
            delivered = true
            break
    check(returned and delivered, "Five workers finish mine-to-smelter trips while sixth waits for capacity")
    var snapshot := sim.snapshot()
    check(mirror.apply_snapshot(snapshot), "Working transport snapshot accepted")
    var bad := snapshot.duplicate(true)
    bad.version = "gaia-frontier-18"
    check(not mirror.apply_snapshot(bad), "Old transport protocol rejected")
    bad = snapshot.duplicate(true)
    bad.units[ids[0]].heading = NAN
    check(not mirror.apply_snapshot(bad), "Non-finite vehicle heading rejected")
    print("HARVESTER_SHARED_TRANSPORT checks=", checks, " failures=", failures)
    quit(0 if failures.is_empty() else 1)
