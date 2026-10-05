extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
var failures: Array[String] = []
var checks := 0


func check(value: bool, message: String) -> void:
    checks += 1
    if not value:
        failures.append(message)
        push_error(message)


func advance(sim, ticks: int) -> void:
    for i in range(ticks):
        sim.step()


func _initialize() -> void:
    run.call_deferred()


func run() -> void:
    var sim := Sim.new()
    sim.reset()
    sim.units.clear()
    var origin := Vector2(768, 512)
    var destination := Vector2(1088, 512)
    var id := sim._add_building(1, "barracks", origin, true)
    var b: Dictionary = sim.buildings[id]
    sim.rebuild_navigation()
    check(sim.footprint(b).size == Vector2(128, 96), "4x3 footprint")
    check(sim.command(1, {"action": "produce", "building": id, "type": "soldier"}).is_empty(), "Ground training allowed")
    check(not sim.command(1, {"action": "barracks_takeoff", "building": id}).is_empty(), "Queue blocks takeoff")
    sim.command(1, {"action": "cancel_production", "building": id})
    check(not sim.command(2, {"action": "barracks_takeoff", "building": id}).is_empty(), "Enemy cannot lift building")
    check(sim.command(1, {"action": "barracks_takeoff", "building": id}).is_empty(), "Empty completed barracks lifts")
    check(not sim.command(1, {"action": "produce", "building": id, "type": "soldier"}).is_empty(), "No training during takeoff")
    check(not sim.command(1, {"action": "barracks_move", "building": id, "pos": destination}).is_empty(), "No horizontal motion before takeoff ends")
    advance(sim, 16)
    check(not Sim.BarracksFlight.is_airborne(b), "Ground target before physical liftoff")
    advance(sim, 1)
    check(Sim.BarracksFlight.is_airborne(b), "Air target after liftoff")
    check(not sim.can_target({"type": "soldier"}, b), "Ground gun cannot target airborne building")
    check(sim.weapon_can_target(["air"], b), "Anti-air weapon profile hits airborne building")
    check(not sim.weapon_can_target(["air"], {"type": "soldier"}), "Anti-air-only profile excludes ground target")
    check(not sim.can_target({"type": "bunker"}, {"target_layer": "air"}), "Ground bunker cannot target flying unit")
    advance(sim, 63)
    check(b.flight.state == "airborne" and b.flight.height == b.flight.cruise, "Takeoff finishes at cruise height")
    check(sim.position_free(origin, 11), "Old footprint released")
    var snapshot := sim.snapshot()
    var guest := Sim.new()
    guest.reset()
    var accepted := guest.apply_snapshot(snapshot)
    check(accepted, "Flight snapshot round trip: " + guest.last_snapshot_error)
    if accepted:
        check(guest.buildings[id].flight == b.flight, "Flight state synchronized")
    snapshot.buildings[id].flight.height = NAN
    check(not guest.apply_snapshot(snapshot), "Nonfinite flight rejected")
    snapshot = sim.snapshot()
    snapshot.version = "rts-terrain-4"
    check(not guest.apply_snapshot(snapshot), "Old protocol rejected")
    sim.visible[1].fill(1)
    var site := sim.deployment_site(1, id, destination)
    check(site.error.is_empty() and site.cells.size() == 12, "12-cell legal site")
    var blocker := sim.add_unit(1, "soldier", destination + Vector2(48, 32))
    site = sim.deployment_site(1, id, destination)
    check(not site.error.is_empty(), "Single occupied edge cell rejects landing")
    check(site.cells.any(func(cell: Dictionary) -> bool: return not cell.error.is_empty()), "Blocked cell shown in preview")
    sim.units.erase(blocker)
    var credits: int = sim.money[1]
    check(sim.command(1, {"action": "barracks_move", "building": id, "pos": destination}).is_empty(), "Air move accepted")
    advance(sim, 10)
    check(is_equal_approx((b.pos as Vector2).distance_to(origin), 30), "Flight speed 60 per second")
    sim.command(1, {"action": "barracks_stop", "building": id})
    var stopped: Vector2 = b.pos
    advance(sim, 3)
    check(b.pos == stopped and not b.flight.deploy, "Stop hovers and cancels deployment intent")
    sim.visible[1].fill(1)
    check(sim.command(1, {"action": "barracks_deploy", "building": id, "pos": destination}).is_empty(), "Relocation accepted without friendly radius")
    advance(sim, 110)
    check(b.flight.state == "landing", "Arrives then starts landing")
    check(not sim.position_free(destination, 11), "Landing reserves footprint")
    advance(sim, 80)
    check(b.flight.state == "grounded" and b.pos == destination and is_zero_approx(b.flight.height), "Landing completes")
    check(sim.money[1] == credits, "Relocation costs no credits")
    check(sim.can_target({"type": "soldier"}, b), "Landed building targetable again")
    check(sim.command(1, {"action": "produce", "building": id, "type": "soldier"}).is_empty(), "Training resumes after landing")
    advance(sim, 50)
    check(sim.units.size() == 1 and b.queue.is_empty(), "Soldier emerges from new site")
    var soldier: Dictionary = sim.units.values()[0]
    check(soldier.pos.y < b.pos.y - 48, "Soldier spawns outside front door")
    sim.units.clear()
    sim.command(1, {"action": "barracks_takeoff", "building": id})
    advance(sim, 80)
    sim.visible[1].fill(1)
    sim.command(1, {"action": "barracks_deploy", "building": id, "pos": origin})
    var late_blocker := sim.add_unit(1, "soldier", origin)
    advance(sim, 120)
    check(b.flight.state == "airborne" and not b.flight.error.is_empty(), "Occupied-on-arrival site cancels descent and hovers")
    sim.units.erase(late_blocker)
    sim.visible[1].fill(1)
    sim.command(1, {"action": "barracks_deploy", "building": id, "pos": origin})
    advance(sim, 1)
    check(not sim.position_free(origin + Vector2(78, 0), 11), "Landing reserves safety margin for ground units")
    var competitor := sim._add_building(1, "barracks", destination, true)
    sim.command(1, {"action": "barracks_takeoff", "building": competitor})
    advance(sim, 80)
    sim.visible[1].fill(1)
    check(not sim.command(1, {"action": "barracks_deploy", "building": competitor, "pos": origin}).is_empty(), "Competing building cannot deploy on occupied site")
    sim.visible[1].fill(0)
    check(not sim.deployment_site(1, competitor, Vector2(1280, 800)).error.is_empty(), "Hidden landing site rejected")
    for map_id: String in ["desert_quarry", "desert_sample"]:
        var terrain_sim := Sim.new()
        if not terrain_sim.reset(false, map_id):
            check(false, "Map loads: " + map_id)
            continue
        terrain_sim.visible[1].fill(1)
        var found_slope := false
        var found_high := false
        var found_low := false
        for y in range(128, 3000, 64):
            for x in range(128, 4600, 64):
                var p := Vector2(x, y)
                if not found_slope and terrain_sim.terrain.gradient_at(p).length() > 0.02:
                    check(not terrain_sim.deployment_site(1, -1, p).error.is_empty(), "Slope rejects deployment on " + map_id)
                    found_slope = true
                var height: float = terrain_sim.terrain.height_at(p)
                if (not found_high and height > 40) or (not found_low and height < -40):
                    if terrain_sim.deployment_site(1, -1, p).error.is_empty():
                        found_high = found_high or height > 40
                        found_low = found_low or height < -40
            if found_slope and found_high and found_low:
                break
        check(found_slope, "Slope fixture found on " + map_id)
        print("PLATFORM_FIXTURES ", map_id, " high=", found_high, " low=", found_low)
        check(found_high, "Flat highland accepts deployment on " + map_id)
        if map_id == "desert_quarry":
            check(found_low, "Spacious flat valley accepts deployment")
    print("BARRACKS_FLIGHT checks=", checks, " failures=", failures)
    quit(0 if failures.is_empty() else 1)
