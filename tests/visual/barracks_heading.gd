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
    var destination: Vector2 = sim.snap_building("barracks", b.pos + Vector2(128, 0))
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
    check_base_nose()
    check_base_visual_owner()
    if DisplayServer.get_name() != "headless":
        await check_rendered_base_motion()
    print("BARRACKS_HEADING checks=", checks, " failures=", failures)
    quit(0 if failures.is_empty() else 1)


func check_base_nose() -> void:
    var sim := Sim.new()
    sim.reset()
    sim.ai_enabled = false
    sim.units.clear()
    var id: int = sim._add_building(1, "base", Vector2(768, 512), true)
    var b: Dictionary = sim.buildings[id]
    check(sim.command(1, {"action": "building_takeoff", "building": id}).is_empty(), "Base takeoff accepted")
    for tick in range(120):
        sim.step()
    var model := preload("res://assets/art/buildings/gaia/gaia_command_base.gd").new()
    root.add_child(model)
    for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP, Vector2(1, 1).normalized(), Vector2(-1, -1).normalized()]:
        var start: Vector2 = b.pos
        var previous_heading: float = b.flight.heading
        check(sim.command(1, {"action": "building_move", "building": id, "pos": start + direction * 120}).is_empty(), "Base travel accepted")
        var restored := Sim.new()
        restored.reset()
        check(restored.apply_snapshot(sim.snapshot()), "Base turn snapshot restores")
        var translated := false
        for tick in range(100):
            var before: Vector2 = b.pos
            sim.step()
            restored.step()
            check(restored.buildings[id].flight == b.flight and restored.buildings[id].pos == b.pos, "Base heading stays deterministic after restore")
            var displacement: Vector2 = b.pos - before
            var turned := absf(angle_difference(previous_heading, b.flight.heading)) > 0.001
            check(not turned or displacement.length() < 0.001, "Base turns in place without side slip")
            if displacement.length() > 0.001:
                var nose := Basis(Vector3.UP, b.flight.heading) * Vector3.RIGHT
                check(Vector2(nose.x, nose.z).dot(displacement.normalized()) > 0.999, "Actual +X narrow nose follows velocity, including reverse")
                translated = true
            model.apply_flight(b.flight, 0.0, Sim.BarracksFlight.is_thrusting(b))
            if turned and not Sim.BarracksFlight.is_thrusting(b):
                check(is_zero_approx(model.presentation.rotation.z), "Turning base uses level hover attitude")
            previous_heading = b.flight.heading
            if not b.flight.moving:
                break
        check(translated and (b.pos as Vector2).distance_to(start + direction * 120) < 0.01, "Base reaches each cardinal and diagonal destination")
    sim.visible[1].fill(1)
    var site: Vector2 = sim.snap_building("base", b.pos)
    check(sim.command(1, {"action": "building_deploy", "building": id, "pos": site}).is_empty(), "Base deployment accepted after reverse")
    for tick in range(200):
        sim.step()
    check(b.flight.state == "grounded" and is_zero_approx(b.flight.heading), "Base restores grid orientation before landing")
    model.free()


func check_base_visual_owner() -> void:
    var visual := preload("res://assets/art/entity_visual.gd").new("base", 1)
    root.add_child(visual)
    visual.rotation.y = PI * 0.5
    for frame in range(12):
        visual._process(1.0 / 60.0)
    check(absf(angle_difference(visual.rotation.y, PI * 0.5)) < 0.001,
        "Base entity does not override flight-owned heading between visual updates")
    var sync = preload("res://scripts/presentation/building_visual_sync.gd")
    # Exercise both 20 Hz local simulation and the 5 Hz room snapshot cadence.
    for fps: int in [30, 60, 144]:
        for snapshot_hz: int in [5, 20]:
            visual.position = Vector3(768, 144, 512)
            var b := {"type": "base", "pos": Vector2(768, 512),
                "flight": {"state": "airborne", "heading": 0.0}}
            visual.rotation.y = 0.0
            var target := visual.position
            var aligned := true
            var stationary_turn := true
            for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2(1, 1).normalized(), Vector2.LEFT]:
                # A stopped simulation pose must not translate while turning.
                visual.position = target
                b.flight.heading = Sim.BarracksFlight.heading_for_direction(b, direction)
                for frame in range(fps):
                    var before := visual.position
                    sync._sync_flight_pose(visual, b, target, 1.0 / fps)
                    visual._process(1.0 / fps)
                    stationary_turn = stationary_turn and before.is_equal_approx(visual.position)
                for frame in range(fps):
                    if frame % maxi(1, roundi(float(fps) / snapshot_hz)) == 0:
                        target += Vector3(direction.x, 0, direction.y) * 60.0 / snapshot_hz
                    var before := visual.position
                    sync._sync_flight_pose(visual, b, target, 1.0 / fps)
                    visual._process(1.0 / fps)
                    var motion := visual.position - before
                    if motion.length() > 0.001:
                        aligned = aligned and (visual.basis * Vector3.RIGHT).dot(motion.normalized()) > 0.999
                # Arrival damping follows the same flight axis, without a late yaw reset.
                for frame in range(fps):
                    var before := visual.position
                    sync._sync_flight_pose(visual, b, target, 1.0 / fps)
                    visual._process(1.0 / fps)
                    var motion := visual.position - before
                    if motion.length() > 0.001:
                        aligned = aligned and (visual.basis * Vector3.RIGHT).dot(motion.normalized()) > 0.999
            check(aligned, "Rendered narrow nose follows motion at %d FPS / %d Hz" % [fps, snapshot_hz])
            check(stationary_turn, "Rendered turn holds position at %d FPS / %d Hz" % [fps, snapshot_hz])
    visual.free()


func check_rendered_base_motion() -> void:
    var world := Node3D.new()
    root.add_child(world)
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color("#152633")
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color("#b8d9ee")
    environment.environment.ambient_light_energy = 0.7
    world.add_child(environment)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-55, -25, 0)
    sun.light_energy = 1.7
    world.add_child(sun)
    var camera := Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 650
    world.add_child(camera)
    camera.current = true
    var visual := preload("res://assets/art/entity_visual.gd").new("base", 1)
    world.add_child(visual)
    visual.model.automatic_animation = false
    visual.position = Vector3(0, 144, 0)
    var b := {"type": "base", "pos": Vector2.ZERO,
        "flight": {"state": "airborne", "heading": 0.0, "ticks": 0}}
    var sync = preload("res://scripts/presentation/building_visual_sync.gd")
    var samples := 0
    var max_error := 0.0
    for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2(1, 1).normalized()]:
        var moved_ticks := 0
        for frame in range(210):
            if frame % 3 == 0:
                if Sim.BarracksFlight.turn_toward(b.flight, Sim.BarracksFlight.heading_for_direction(b, direction), 20):
                    b.pos += direction * 3.0
                    moved_ticks += 1
            var before := visual.position
            sync._sync_flight_pose(visual, b, Vector3(b.pos.x, 144, b.pos.y), 1.0 / 60.0)
            visual.model.apply_flight(b.flight, 1.0 / 60.0, moved_ticks > 0)
            camera.position = visual.position + Vector3(380, 390, 500)
            camera.look_at(visual.position + Vector3(0, 45, 0))
            await process_frame
            await RenderingServer.frame_post_draw
            var motion := visual.position - before
            if motion.length() > 0.001:
                samples += 1
                max_error = maxf(max_error, acos(clampf((visual.global_basis * Vector3.RIGHT).dot(motion.normalized()), -1.0, 1.0)))
            if moved_ticks == 20:
                root.get_texture().get_image().save_png("res://.godot/base-flight-%d.png" % samples)
                break
    check(samples > 100 and max_error < 0.01, "Real rendered frames preserve narrow-end forward alignment")
    print("BASE_RENDER_MOTION samples=", samples, " max_error_degrees=", rad_to_deg(max_error))
    world.free()
