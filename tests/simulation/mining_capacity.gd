extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
const Mining = Sim.MiningSystem
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
    run.call_deferred()

func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)

func fresh() -> Simulation:
    var sim := Sim.new()
    sim.reset(false, "desert_sample")
    sim.ores = {1: {"pos": Vector2(2256, 1168), "amount": 100000}}
    return sim

func miners(sim, count: int) -> Array:
    var ids: Array = []
    for i in range(count):
        ids.append(sim.add_unit(1, "harvester", Vector2(2096 + (i % 3) * 112, 880 + (i / 3) * 112)))
    sim.command(1, {"action": "gather", "units": ids, "target": 1})
    return ids

func run() -> void:
    var sim := fresh()
    var ids := miners(sim, 6)
    sim.step()
    check(Mining.counts(sim, 1) == Vector2i(5, 1), "Five reservations, sixth waits")
    var waiting: Dictionary = sim.units[ids[5]]
    for i in range(5):
        var u: Dictionary = sim.units[ids[i]]
        u.pos = u.mining.target
    var soldier_id := sim.add_unit(1, "soldier", sim.units[ids[0]].pos)
    sim.units[soldier_id].auto = false
    var soldier_pos: Vector2 = sim.units[soldier_id].pos
    for tick in range(21):
        sim.step()
    check(waiting.cargo == 0, "Waiting never mines")
    for i in range(5):
        check(sim.units[ids[i]].cargo >= 10, "Five overlapping workers all harvest")
        check(Mining.intangible(sim.units[ids[i]]), "Active workers ignore all unit bodies")
    check(sim.units[soldier_id].pos == soldier_pos, "Worker does not push overlapping soldier")
    var snapshot: Dictionary = sim.snapshot()
    var mirror := Sim.new()
    check(mirror.apply_snapshot(snapshot), "Mining state snapshot accepted: " + mirror.last_snapshot_error)
    var forged := snapshot.duplicate(true)
    forged.units[ids[5]].mining = forged.units[ids[0]].mining.duplicate(true)
    forged.units[ids[5]].pos = forged.units[ids[0]].pos
    check(not mirror.apply_snapshot(forged), "Six reservations rejected")
    forged = snapshot.duplicate(true)
    forged.units[ids[5]].mining.ghost = true
    check(not mirror.apply_snapshot(forged), "Waiting vehicle cannot forge overlap permission")
    forged = snapshot.duplicate(true)
    forged.units[ids[0]].mining.requested = sim.frame + 1
    check(not mirror.apply_snapshot(forged), "Future reservation rejected")
    forged = snapshot.duplicate(true)
    forged.buildings[1].pos += Vector2(1, 0)
    check(not mirror.apply_snapshot(forged), "Off-grid building snapshot rejected")
    sim.units[ids[0]].cargo = 60
    sim.step()
    check(sim.units[ids[0]].mining.phase == "exit" and Mining.intangible(sim.units[ids[0]]), "Full cargo releases slot without restoring overlapping collision")
    check(Mining.reserved(waiting), "Waiting vehicle immediately promoted")
    sim.command(1, {"action": "stop", "units": [ids[1]]})
    check(not Mining.reserved(sim.units[ids[1]]) and sim.units[ids[1]].mining.phase == "exit", "Stop releases reservation with safe exit")
    for distance in [29, 30, 31]:
        sim = fresh()
        sim.ores[2] = {"pos": sim.ores[1].pos + Vector2(distance * Sim.CELL, 0), "amount": 100000}
        ids = miners(sim, 6)
        sim.step()
        check(sim.units[ids[5]].ore == (2 if distance == 29 else 1), "Strict range boundary %d" % distance)
        check(Mining.counts(sim, 1).x == 5, "Capacity remains five at boundary")
    sim = fresh()
    sim.ores[2] = {"pos": sim.ores[1].pos + Vector2(320, 0), "amount": 100000}
    ids = miners(sim, 11)
    sim.step()
    check(Mining.counts(sim, 1).x == 5 and Mining.counts(sim, 2).x == 5, "Atomic reservations across two mines")
    check(sim.units[ids[10]].mining.phase == "wait", "Eleventh queues")
    var wait_point: Vector2 = sim.units[ids[10]].mining.target
    Sim.MiningSystem.prepare(sim)
    check(sim.units[ids[10]].mining.target == wait_point, "Queue target remains stable")
    check(sim.units[ids[5]].mining.origin == sim.ores[1].pos, "Overflow retains original search center")
    var origin: Vector2 = sim.units[ids[5]].mining.origin
    sim.ores[3] = {"pos": origin + Vector2(992, 0), "amount": 100000}
    sim.ores[1].amount = 0
    sim.ores[2].amount = 0
    for tick in range(25):
        sim.step()
    check(Mining.counts(sim, 3).x == 0, "No chained overflow beyond origin range")
    sim = fresh()
    ids = miners(sim, 6)
    sim.step()
    sim.units[ids[0]].hp = 0
    for tick in range(21):
        sim.step()
    check(Mining.counts(sim, 1).x == 5, "Dead worker releases reservation")
    sim = fresh()
    ids = miners(sim, 6)
    sim.ores[2] = {"pos": Vector2(2256, 752), "amount": 100000}
    sim.step()
    check(sim.units[ids[5]].mining.phase == "wait", "Unreachable nearby ore rejected")
    sim.ores[2].pos = Vector2(2576, 1168)
    sim.ores[2].amount = 0
    sim.units[ids[5]].mining.retry = 0
    Mining.prepare(sim)
    check(sim.units[ids[5]].mining.phase == "wait", "Depleted alternative rejected")
    sim.ores[2].amount = 100000
    sim.terrain.definition.test_only = false
    sim.visible[1].fill(0)
    sim.units[ids[5]].mining.retry = 0
    Mining.prepare(sim)
    check(sim.units[ids[5]].mining.phase == "wait", "Invisible alternative rejected")
    sim = fresh()
    ids = miners(sim, 5)
    var enemy := sim.add_unit(2, "harvester", Vector2(2512, 1168))
    sim.command(2, {"action": "gather", "units": [enemy], "target": 1})
    sim.step()
    check(Mining.counts(sim, 1) == Vector2i(5, 1), "Capacity is shared across factions")
    var moving: Dictionary = sim.units[ids[0]]
    moving.pos = moving.mining.target
    sim.step()
    var old_position: Vector2 = moving.pos
    sim.command(1, {"action": "stop", "units": [ids[0]]})
    for tick in range(240):
        sim.step()
        if not moving.has("mining"):
            break
    check(not moving.has("mining") and moving.order == "idle" and moving.auto == false, "Stopped overlapping worker safely exits and remains stopped")
    check(moving.pos != old_position and sim.position_free(moving.pos, 48), "Safe exit uses movement and preserves terrain clearance")
    sim = fresh()
    ids = miners(sim, 1)
    sim.step()
    moving = sim.units[ids[0]]
    moving.pos = moving.mining.target
    sim.step()
    var center: Vector2 = sim.ores[1].pos
    sim.obstacles.assign([
        Rect2(center + Vector2(-176, -176), Vector2(352, 32)),
        Rect2(center + Vector2(-176, 144), Vector2(352, 32)),
        Rect2(center + Vector2(-176, -144), Vector2(32, 288)),
        Rect2(center + Vector2(144, -144), Vector2(32, 288))])
    sim.rebuild_navigation()
    sim.command(1, {"action": "stop", "units": ids})
    old_position = moving.pos
    for tick in range(21):
        sim.step()
    check(moving.pos == old_position and moving.mining.phase == "exit", "Sealed work area waits instead of crossing blockers")
    sim.obstacles.clear()
    sim.rebuild_navigation()
    for tick in range(240):
        sim.step()
        if not moving.has("mining"):
            break
    check(not moving.has("mining") and moving.order == "idle", "Work area exit resumes after blocker removal")
    var terrain_data: Dictionary = sim.terrain.definition.duplicate(true)
    terrain_data.ores = [{"pos": Vector2(2200, 1100), "amount": 100}]
    check(not Sim.MapTerrain.new().assemble(terrain_data), "Off-grid authored ore rejected")
    var layout = sim.terrain.sample_surface.layout
    var bad_layout: Dictionary = layout.data.duplicate(true)
    for item: Dictionary in bad_layout.instances:
        if item.component == "rock_large":
            item.position[0] += 1
    check(not preload("res://scripts/maps/component_layout.gd").new().configure(bad_layout), "Off-grid blocking rock rejected")
    check(sim.reset(false, "desert_sample") and sim.units.is_empty(), "Reset drops all reservations")
    for map_id: String in ["desert_sample", "desert_quarry"]:
        sim.reset(false, map_id)
        for b: Dictionary in sim.buildings.values():
            check(Sim.WorldGrid.rect_aligned(sim.footprint(b)), "Initial building aligned")
        for ore: Dictionary in sim.ores.values():
            check(ore.pos == Sim.WorldGrid.cell_center(ore.pos), "Authored ore at cell center")
        if sim.terrain.sample_surface != null:
            for rect: Rect2 in sim.terrain.sample_surface.layout.blockers:
                check(Sim.WorldGrid.rect_aligned(rect), "Blocking rocks use integer cells")
    print("MINING_CAPACITY checks=", checks, " failures=", failures)
    quit(0 if failures.is_empty() else 1)
