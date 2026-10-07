extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
var failures: Array[String] = []
var checks := 0


func check(value: bool, message: String) -> void:
    checks += 1
    if not value:
        failures.append(message)
        push_error(message)


func _initialize() -> void:
    run.call_deferred()


func run() -> void:
    var sim := Sim.new()
    sim.reset()
    sim.units.clear()
    var origin := Vector2(768, 512)
    var id: int = sim._add_building(1, "barracks", origin, true)
    var b: Dictionary = sim.buildings[id]
    sim.command(1, {"action": "barracks_takeoff", "building": id})
    for tick in range(80):
        sim.step()
    var cruise: float = b.flight.height
    # All cardinal headings, using the actual fixed-tick simulation.
    for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
        var start: Vector2 = b.pos
        var start_heading: float = b.flight.heading
        var target_heading := atan2(-direction.x, -direction.y)
        var turn_ticks := roundi(absf(angle_difference(start_heading, target_heading)) / (PI / 40.0))
        sim.command(1, {"action": "barracks_move", "building": id, "pos": start + direction * 120})
        for tick in range(turn_ticks):
            sim.step()
            check(b.pos == start, "No side slip during turn")
            check(is_equal_approx(b.flight.height, cruise), "Turning preserves cruise height")
        check(absf(angle_difference(b.flight.heading, target_heading)) < .0001, "Cardinal heading reached")
        for tick in range(10):
            sim.step()
        check((b.pos as Vector2).is_equal_approx(start + direction * 30), "Aligned motion is 60 units/second")
        check(Sim.BarracksFlight.is_thrusting(b), "Aligned movement enables propulsion")
        sim.command(1, {"action": "barracks_stop", "building": id})
        check(not Sim.BarracksFlight.is_thrusting(b), "Hover disables propulsion")
    var start: Vector2 = b.pos
    sim.command(1, {"action": "barracks_move", "building": id, "pos": start + Vector2(0, 120)})
    for tick in range(10):
        sim.step()
    check(b.pos == start and absf(b.flight.heading) > .1, "Reverse command begins stationary turn")
    # Restore during the turn, then prove both simulations continue identically.
    var restored := Sim.new()
    restored.reset()
    check(restored.apply_snapshot(sim.snapshot()), "Mid-turn snapshot restores")
    for tick in range(45):
        sim.step()
        restored.step()
        check(restored.buildings[id].flight == b.flight and restored.buildings[id].pos == b.pos, "Restored turn and translation stay deterministic")
    for invalid in [NAN, INF, -PI - .1, PI, "east", true]:
        var snapshot := sim.snapshot()
        snapshot.buildings[id].flight.heading = invalid
        check(not restored.apply_snapshot(snapshot), "Invalid heading rejected: " + str(invalid))
    var missing := sim.snapshot()
    missing.buildings[id].flight.erase("heading")
    check(not restored.apply_snapshot(missing), "Missing heading rejected")
    sim.command(1, {"action": "barracks_move", "building": id, "pos": b.pos + Vector2(120, 0)})
    sim.step()
    sim.command(1, {"action": "barracks_stop", "building": id})
    var stopped: Dictionary = b.duplicate(true)
    for tick in range(5):
        sim.step()
    check(b.pos == stopped.pos and b.flight.heading == stopped.flight.heading, "Stop freezes mid-turn heading and position")
    # Deploy at a snapped nearby point, then block it during the final turn.
    var destination: Vector2 = sim.snap_build(b.pos + Vector2(128, 0))
    sim.visible[1].fill(1)
    check(sim.command(1, {"action": "barracks_deploy", "building": id, "pos": destination}).is_empty(), "Deployment accepted")
    for tick in range(160):
        sim.step()
        if (b.pos as Vector2).is_equal_approx(destination):
            break
    check(b.flight.state == "airborne" and b.flight.deploy and absf(b.flight.heading) > .1, "Arrival waits for default orientation")
    check(not Sim.BarracksFlight.is_thrusting(b), "Deployment turn has no horizontal exhaust")
    check(restored.apply_snapshot(sim.snapshot()), "Restore deployment orientation phase")
    restored.command(1, {"action": "barracks_stop", "building": id})
    var canceled_heading: float = restored.buildings[id].flight.heading
    for tick in range(100):
        restored.step()
    var canceled: Dictionary = restored.buildings[id].flight
    check(canceled.state == "airborne" and not canceled.deploy and canceled.heading == canceled_heading,
        "Stop during deployment turn cancels landing and freezes orientation")
    var blocker: int = sim.add_unit(1, "soldier", destination)
    for tick in range(40):
        sim.step()
    check(b.flight.state == "airborne" and not b.flight.deploy and not b.flight.error.is_empty(), "Late blocker cancels descent after turn")
    sim.units.erase(blocker)
    sim.visible[1].fill(1)
    sim.command(1, {"action": "barracks_deploy", "building": id, "pos": destination})
    for tick in range(81):
        sim.step()
    check(b.flight.state == "grounded" and is_zero_approx(b.flight.heading), "Same-position deployment lands facing original direction")
    var invalid_grounded := sim.snapshot()
    invalid_grounded.buildings[id].flight.heading = .5
    check(not restored.apply_snapshot(invalid_grounded), "Rotated grounded footprint rejected")
    var seam := {"heading": PI - .02}
    Sim.BarracksFlight.turn_toward(seam, -PI + .02, Sim.TICK)
    check(absf(angle_difference(seam.heading, -PI + .02)) < .0001, "Rotation crosses angle seam along the short arc")
    # Vector2 movement uses float coordinates: diagonal travel must not insert
    # extra turn ticks due to rounding, especially near the far map boundary.
    var diagonal_sim := Sim.new()
    diagonal_sim.reset()
    diagonal_sim.units.clear()
    var diagonal_id: int = diagonal_sim._add_building(1, "barracks", Vector2(4200, 2700), true)
    var diagonal: Dictionary = diagonal_sim.buildings[diagonal_id]
    diagonal_sim.command(1, {"action": "barracks_takeoff", "building": diagonal_id})
    for tick in range(80):
        diagonal_sim.step()
    for offset: Vector2 in [Vector2(-127, -223), Vector2(193, -81), Vector2(-221, 107)]:
        var diagonal_start: Vector2 = diagonal.pos
        diagonal_sim.command(1, {"action": "barracks_move", "building": diagonal_id, "pos": diagonal_start + offset})
        for tick in range(42):
            if Sim.BarracksFlight.is_thrusting(diagonal):
                break
            diagonal_sim.step()
        for tick in range(ceili(offset.length() / 3.0)):
            var before: Vector2 = diagonal.pos
            var remaining := before.distance_to(diagonal.flight.target)
            diagonal_sim.step()
            check(absf((diagonal.pos as Vector2).distance_to(before) - minf(3.0, remaining)) < .001, "Diagonal travel never stalls for floating-point heading corrections")
    print("BARRACKS_HEADING checks=", checks, " failures=", failures)
    quit(0 if failures.is_empty() else 1)
