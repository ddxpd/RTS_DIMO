extends SceneTree

const Dock = preload("res://scripts/simulation_systems/depot_docking.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
    run.call_deferred()


func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)


func run() -> void:
    var sim := Simulation.new()
    sim.reset()
    sim.units.clear()
    var station := sim._add_building(1, "refinery", Vector2(1600, 1900), true)
    var b: Dictionary = sim.buildings[station]
    sim.rebuild_navigation()
    check(sim.position_free(Dock.berth(b, 0), 48), "Left berth has full vehicle clearance")
    check(sim.position_free(Dock.berth(b, 1), 48), "Right berth has full vehicle clearance")
    check(not sim.position_free(b.pos, 48), "Rear housing blocks vehicles")
    check(not sim.position_free(b.pos + Vector2(0, -40), 18), "Central bin blocks infantry")
    check(not sim.position_free(b.pos + Vector2(0, -32), 12), "Forward central bin blocks the former open gap")
    for local: Rect2 in Simulation.EntityCatalog.REFINERY_DOCK_RECTS:
        var pad := Rect2(b.pos + local.position, local.size)
        check(sim.position_free(pad.get_center(), 12), "One-cell lane admits infantry")
        check(not Simulation.BarracksFlight.rect_error(sim, 1, pad, -1, false).is_empty(), "Unloading pad reserves construction and landing space")
    check(sim.placement_rects("refinery", b.pos).size() == 1 and sim.placement_bounds("refinery", b.pos).size == Vector2(128, 128), "All sixteen cells form one reserved square")
    check(sim.footprint(b).size == Vector2(128, 128), "Footprint is 4x4 cells")
    check(sim.build_error(1, "bunker", b.pos + Vector2(-64, -32)) == "Building footprint occupied", "Construction cannot cover a reserved unloading lane")
    for y in range(4):
        for x in range(4):
            var point: Vector2 = b.pos + Vector2(-48 + 32*x, -48 + 32*y)
            var traversable := y < 2 and x in [0, 3]
            check(sim.position_free(point, 0) == traversable, "Each cell matches the approved 12-solid/4-open mask")
    for slot in range(2):
        check(sim.movement_free(Dock.entrance(b, slot), Dock.berth(b, slot), 48), "Full-radius harvester sweeps approach without passing through body")
    var ids: Array[int] = []
    for index in range(4):
        var id := sim.add_unit(1, "harvester", b.pos + Vector2(-336 + 224 * index, -400))
        sim.units[id].order = "gather"
        sim.units[id].auto = false
        sim.units[id].cargo = 60
        ids.append(id)
    var start_money: int = sim.money[1]
    var dual := false
    var queued := false
    var finished := false
    for tick in range(1600):
        sim.step()
        var occupied := {}
        var waiting := 0
        var remaining := 0
        for id in ids:
            var u: Dictionary = sim.units[id]
            remaining += int(u.cargo)
            if u.has("dock"):
                if u.dock.slot >= 0:
                    check(not occupied.has(u.dock.slot), "No duplicate dock reservation")
                    occupied[u.dock.slot] = id
                else:
                    waiting += 1
        dual = dual or occupied.size() == 2
        queued = queued or waiting > 0
        if remaining == 0 and occupied.is_empty():
            finished = true
            break
    check(dual and queued, "Two active berths plus waiting queue")
    check(finished and sim.money[1] == start_money + 240, "Four vehicles unload exactly once and exit")
    if not finished:
        for id in ids:
            print("DEPOT_DEBUG ", id, " ", sim.units[id])
    var mirror := Simulation.new()
    mirror.reset()
    check(mirror.apply_snapshot(sim.snapshot()), "Dock snapshot roundtrip: " + mirror.last_snapshot_error)
    special_cases()
    print("ORE_DEPOT ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures)
    quit(0 if failures.is_empty() else 1)


func fixture() -> Simulation:
    var sim := Simulation.new()
    sim.reset()
    sim.units.clear()
    sim._add_building(1, "refinery", Vector2(1600, 1900), true)
    sim.rebuild_navigation()
    return sim


func carrier(sim: Simulation, pos: Vector2, cargo: int = 60) -> int:
    var id := sim.add_unit(1, "harvester", pos)
    sim.units[id].order = "gather"
    sim.units[id].auto = false
    sim.units[id].cargo = cargo
    return id


func special_cases() -> void:
    var sim := fixture()
    var station: int = sim.next_id - 1
    var b: Dictionary = sim.buildings[station]
    var left := carrier(sim, Dock.berth(b, 0), 17)
    var right := carrier(sim, Dock.berth(b, 1))
    for pair in [[left, 0], [right, 1]]:
        var u: Dictionary = sim.units[pair[0]]
        Dock.request(sim, u, station, 0)
        u.dock.slot = pair[1]
        u.dock.phase = "enter"
        Dock.destination(u, Dock.berth(b, pair[1]))
    var mirror := Simulation.new()
    mirror.reset()
    check(mirror.apply_snapshot(sim.snapshot()) and mirror.snapshot() == sim.snapshot(), "Two occupied berths survive full snapshot")
    for patch: Dictionary in [{"slot": 2}, {"phase": "bogus"}, {"station": -1}, {"station": 99999}, {"target": Vector2(INF, 0)}, {"requested": 100}, {"stalled": 1.5}]:
        var bad := sim.snapshot()
        bad.units[left].dock.merge(patch, true)
        check(not mirror.apply_snapshot(bad), "Reject malformed dock " + str(patch))
    var duplicate := sim.snapshot()
    duplicate.units[right].dock.slot = 0
    check(not mirror.apply_snapshot(duplicate), "Reject duplicate berth claims")
    var legacy := sim.snapshot()
    legacy.version = "rts-desert-only-10"
    check(not mirror.apply_snapshot(legacy), "Protocol10 rejected")
    sim.step()
    check(sim.money[1] == 6077 and sim.units[left].cargo == 0 and sim.units[right].cargo == 0, "Both berths unload full or exhausted partial cargo in same tick")
    check(b.dock_flash == [10, 10], "Unload indicator event lasts10 ticks")
    var before: int = sim.money[1]
    sim.step()
    check(sim.money[1] == before, "Exit does not credit cargo twice")
    sim.command(1, {"action": "stop", "units": [left]})
    check(not sim.units[left].has("dock"), "Stop releases reservation immediately")
    sim.units[right].hp = 0
    sim.step()
    check(not sim.units.has(right), "Dead vehicle releases its berth")
    sim.units.clear()
    var waiting := carrier(sim, b.pos + Vector2(-400, -400))
    Dock.request(sim, sim.units[waiting], station, sim.frame)
    b.hp = 0
    sim.step()
    check(not sim.units[waiting].has("dock") and sim.units[waiting].cargo == 60, "Destroyed station releases cargo safely")
    check(mirror.apply_snapshot(sim.snapshot()), "Destroyed-station snapshot has no dangling reservation")

    sim = fixture()
    station = sim.next_id - 1
    b = sim.buildings[station]
    var second := sim._add_building(1, "refinery", Vector2(2400, 1900), true)
    sim.rebuild_navigation()
    for slot in range(2):
        var blocker := sim.add_unit(1, "harvester", Dock.entrance(b, slot))
        sim.units[blocker].auto = false
    waiting = carrier(sim, b.pos + Vector2(-256, -224))
    Dock.request(sim, sim.units[waiting], station, sim.frame)
    var origin: Vector2 = sim.units[waiting].pos
    var switched := false
    for tick in range(180):
        sim.step()
        if sim.units[waiting].has("dock") and sim.units[waiting].dock.station == second:
            switched = true
            break
    check(switched and sim.units[waiting].cargo == 60, "Blocked entrances retry another reachable station without cargo loss")
    check((sim.units[waiting].pos as Vector2).distance_to(origin) < 20, "Retry changes intent without teleportation")
    sim.command(1, {"action": "move", "units": [waiting], "pos": Vector2(1200, 1500)})
    check(not sim.units[waiting].has("dock"), "Move order releases reservation")
    sim.units.clear()
    var exits: Array[int] = []
    for offset in [Vector2(-240, 96), Vector2(240, 96), Vector2(-112, 224), Vector2(112, 224)]:
        var point: Vector2 = b.pos + offset
        check(sim.position_free(point, 48), "Side/rear production exit clears building body")
        exits.append(sim.add_unit(1, "harvester", point))
    check(sim._spawn_position(b, "harvester") == Vector2.ZERO, "Blocked production waits without spawning into a ramp")
    sim.units.erase(exits[0])
    var spawn := sim._spawn_position(b, "harvester")
    check(spawn != Vector2.ZERO and spawn.y > b.pos.y, "Freed side exit resumes production behind ramps")

    sim = fixture()
    station = sim.next_id - 1
    b = sim.buildings[station]
    waiting = carrier(sim, b.pos + Vector2(-256, -224))
    Dock.request(sim, sim.units[waiting], station, sim.frame)
    Dock.prepare(sim)
    check(sim.units[waiting].dock.slot == 0, "Initial free berth claimed")
    var blocker := sim.add_unit(1, "harvester", Dock.entrance(b, 0))
    sim.units[blocker].auto = false
    sim.units[waiting].dock.stalled = 100
    Dock.retry(sim, sim.units[waiting])
    Dock.prepare(sim)
    check(sim.units[waiting].dock.slot == 1, "Newly blocked berth falls back to other berth at same station")
