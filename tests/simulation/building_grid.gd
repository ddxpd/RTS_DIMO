extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
const Flight = preload("res://scripts/barracks_flight.gd")
const Dock = preload("res://scripts/simulation_systems/depot_docking.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
    run.call_deferred()


func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)


func clean(sim) -> void:
    sim.units.clear()
    sim.buildings.clear()
    sim.ores.clear()
    sim.obstacles.clear()
    sim.money[1] = 100000
    sim.winner = 0
    sim.ai_enabled = false
    sim._add_building(1, "base", Vector2(384, 384), true)
    sim._add_building(2, "base", Vector2(4416, 2816), true)
    sim.visible[1].fill(1)
    sim.explored[1].fill(1)


func aligned(rect: Rect2) -> bool:
    return (rect.position / Sim.CELL).is_equal_approx((rect.position / Sim.CELL).round()) and (rect.end / Sim.CELL).is_equal_approx((rect.end / Sim.CELL).round())


func run() -> void:
    var sim := Sim.new()
    for map_id: String in ["desert_quarry", "desert_sample"]:
        sim.reset(false, map_id)
        for b: Dictionary in sim.buildings.values():
            check(aligned(sim.footprint(b)), map_id + " initial building aligned")
    sim.reset()
    for kind: String in Sim.BUILD_TYPES:
        for raw: Vector2 in [Vector2(1600, 1900), Vector2(1599.9, 1903.6), Vector2(0, 0)]:
            var point: Vector2 = sim.snap_building(kind, raw)
            var half: Vector2 = Sim.BUILD_TYPES[kind].size * 0.5
            check(aligned(Rect2(point - half, half * 2)), kind + " canonical edges")
            check(sim.snap_building(kind, point) == point, kind + " snapping is idempotent")
            check(absf(raw.x - point.x) <= 16.01 and absf(raw.y - point.y) <= 16.01, kind + " nearest grid footprint")
    check(sim.snap_build(Vector2(1600, 1900)) == Vector2(1600, 1888), "Rally point snapping unchanged")
    var origin := Vector2(1920, 1920)
    for neighbor_kind: String in Sim.BUILD_TYPES:
        for kind: String in Sim.BUILD_TYPES:
            for side: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
                clean(sim)
                var neighbor_size: Vector2 = Sim.BUILD_TYPES[neighbor_kind].size
                var size: Vector2 = Sim.BUILD_TYPES[kind].size
                var id: int = sim._add_building(1, neighbor_kind, origin + neighbor_size * 0.5, true)
                var rect: Rect2 = sim.placement_bounds(neighbor_kind, sim.buildings[id].pos)
                var corner := origin
                if side.x > 0:
                    corner.x = rect.end.x
                elif side.x < 0:
                    corner.x -= size.x
                elif side.y > 0:
                    corner.y = rect.end.y
                else:
                    corner.y = rect.position.y - size.y
                var point := corner + size * 0.5
                var label := neighbor_kind + "/" + kind + "/" + str(side)
                check(sim.build_error(1, kind, point).is_empty(), label + " adjacent accepted: " + sim.build_error(1, kind, point))
                check(sim.build_error(1, kind, point - side * Sim.CELL) == "Building footprint occupied", label + " one-cell overlap rejected")
                var before: int = sim.next_id
                check(sim.command(1, {"action": "build", "type": kind, "pos": point}).is_empty(), label + " host accepts adjacent build")
                check(sim.buildings.has(before) and sim.buildings[before].pos == point, label + " actual position equals preview")
    clean(sim)
    var left: int = sim._add_building(1, "bunker", origin + Vector2(32, 32), true)
    var right: int = sim._add_building(1, "bunker", origin + Vector2(96, 32), false)
    sim.rebuild_navigation()
    var seam := origin + Vector2(64, 32)
    for radius: float in [0.0, 12.0, 16.0, 18.0, 48.0]:
        check(not sim.position_free(seam, radius), "Shared edge blocks body radius " + str(radius))
        check(not sim.movement_free(seam - Vector2(0, 160), seam + Vector2(0, 160), radius), "Sweep cannot cross shared edge " + str(radius))
    var unit: int = sim.add_unit(1, "soldier", seam - Vector2(0, 128))
    sim.command(1, {"action": "move", "units": [unit], "pos": seam + Vector2(0, 128)})
    var legal := true
    for tick in range(240):
        sim.step()
        legal = legal and sim.position_free(sim.units[unit].pos, 16)
    check(legal and sim.units[unit].pos.distance_to(seam + Vector2(0, 128)) < 8, "Actual movement and avoidance route around joined wall")
    sim.buildings[right].pos += Vector2(0, 64)
    sim.rebuild_navigation()
    check(not sim.movement_free(origin + Vector2(32, 96), origin + Vector2(96, 32), 16), "Diagonal corner contact cannot be squeezed through")
    sim.buildings[right].pos = origin + Vector2(160, 32)
    sim.rebuild_navigation()
    var corridor := origin + Vector2(96, 32)
    check(sim.movement_free(corridor - Vector2(0, 160), corridor + Vector2(0, 160), 16), "Two-cell real passage admits soldier")
    check(not sim.movement_free(corridor - Vector2(0, 160), corridor + Vector2(0, 160), 48), "Two-cell passage rejects harvester")
    clean(sim)
    var barracks: int = sim._add_building(1, "barracks", origin + Vector2(64, 48), true)
    var neighbor: int = sim._add_building(1, "base", origin + Vector2(288, 96), true)
    sim.rebuild_navigation()
    var point: Vector2 = sim.buildings[barracks].pos
    check(sim.command(1, {"action": "barracks_takeoff", "building": barracks}).is_empty(), "Adjacent takeoff command accepted")
    for tick in range(80):
        Flight.advance(sim, barracks, sim.buildings[barracks])
    check(Flight.state(sim.buildings[barracks]) == "airborne", "Tight neighbor does not block vertical takeoff")
    var site: Dictionary = sim.deployment_site(1, barracks, point)
    check(site.pos == point and site.error.is_empty() and site.cells.all(func(cell: Dictionary) -> bool: return cell.error.is_empty()), "Adjacent landing grid fully green")
    check(sim.command(1, {"action": "barracks_deploy", "building": barracks, "pos": point}).is_empty(), "Adjacent deployment accepted")
    for tick in range(90):
        Flight.advance(sim, barracks, sim.buildings[barracks])
        if Flight.state(sim.buildings[barracks]) == "landing":
            check(sim.build_error(1, "bunker", point) == "Building footprint occupied", "Landing footprint reserved")
            check(not sim.position_free(point, 16), "Landing reservation blocks units")
    check(Flight.state(sim.buildings[barracks]) == "grounded" and sim.buildings[barracks].pos == point, "Adjacent landing finishes on canonical grid")
    var blocker: int = sim._add_building(1, "barracks", origin + Vector2(64, -48), true)
    sim.rebuild_navigation()
    sim.buildings[barracks].queue.assign([{"type": "mobile_infantry", "remaining": 0}])
    sim.EconomySystem.advance_production(sim, sim.buildings[barracks])
    check(sim.buildings[barracks].queue.size() == 1 and sim.units.is_empty(), "Closed production door waits without spawning through wall")
    sim.buildings.erase(blocker)
    sim.rebuild_navigation()
    sim.EconomySystem.advance_production(sim, sim.buildings[barracks])
    check(sim.buildings[barracks].queue.is_empty() and sim.units.size() == 1, "Production resumes after exit reopens")
    clean(sim)
    var station: int = sim._add_building(1, "refinery", origin + Vector2(176, 160), true)
    var depot: Dictionary = sim.buildings[station]
    for slot in range(2):
        sim._add_building(1, "barracks", Dock.entrance(depot, slot), true)
    sim.rebuild_navigation()
    var miner: int = sim.add_unit(1, "harvester", depot.pos + Vector2(0, -480))
    sim.units[miner].cargo = 60
    sim.units[miner].order = "gather"
    check(Dock.choose_station(sim, sim.units[miner]) == -1, "Closed dock entrances are unreachable")
    check(not sim.position_free(Dock.berth(depot, 0), 48), "Nearby blocking building cannot be ignored during docking")
    for id: int in sim.buildings.keys():
        if sim.buildings[id].type == "barracks":
            sim.buildings.erase(id)
    sim.rebuild_navigation()
    check(Dock.choose_station(sim, sim.units[miner]) == station, "Dock resumes after entrances reopen")
    check(sim.position_free(Dock.berth(depot, 0), 48), "Compact docking stop has full body clearance after obstruction is removed")
    var credits: int = sim.money[1]
    for tick in range(500):
        sim.step()
    check(sim.units[miner].cargo == 0 and sim.money[1] == credits + 60, "Normal unload still completes")
    if sim.units[miner].cargo != 0:
        print("GRID_DOCK_DEBUG ", sim.units[miner])
    var mirror := Sim.new()
    mirror.reset()
    check(mirror.apply_snapshot(sim.snapshot()) and mirror.snapshot() == sim.snapshot(), "Canonical grid state replicates completely")
    var old: Dictionary = sim.snapshot()
    old.version = "rts-desert-only-12"
    check(not mirror.apply_snapshot(old), "Reject previous grid protocol")
    print("BUILDING_GRID checks=", checks, " failures=", failures)
    quit(0 if failures.is_empty() else 1)
