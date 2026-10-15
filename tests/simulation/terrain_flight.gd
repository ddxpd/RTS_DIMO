extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
const Flight = Sim.BarracksFlight
const BASELINE := "res://tests/fixtures/terrain_flight_v17.json"
var checks := 0
var failures: Array[String] = []
var routes: Array[Dictionary] = []


func _initialize() -> void:
    run.call_deferred()


func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok and not failures.has(label):
        failures.append(label)
        push_error(label)


func fixture(profile: String):
    var sim := Sim.new()
    sim.reset(false, "frontier_four")
    sim.ai_enabled = false
    sim.units.clear()
    sim.buildings.clear()
    sim.ores.clear()
    for index in range(sim.terrain.COUNT):
        var p: Vector2 = sim.terrain.center(index)
        var height := 0.0
        var slope := Vector2.ZERO
        if profile == "cliff":
            height = 192.0 if p.x >= 1600 else -96.0
        elif profile == "ridge":
            height = 192.0 if p.x >= 1600 and p.x < 1632 else -96.0
        elif profile == "ramp":
            height = clampf((p.x - 1600) * 0.5, 0, 128)
            if p.x > 1600 and p.x < 1856:
                slope = Vector2(0.5, 0)
        elif profile == "distant_peak" and p.x > 4000:
            height = 192.0
        sim.terrain.heights[index] = height
        sim.terrain.gradients[index] = slope
    sim.terrain.flight_cell_heights.clear()
    sim._add_building(2, "base", Vector2(4352, 2816), true)
    sim.rebuild_navigation()
    return sim


func lift(sim, kind: String, position: Vector2) -> int:
    var id: int = sim._add_building(1, kind, position, true)
    check(sim.command(1, {"action": "building_takeoff", "building": id}).is_empty(), "Takeoff accepted " + kind)
    for tick in range(Flight.duration(sim.buildings[id])):
        sim.step()
    check(sim.buildings[id].flight.state == "airborne", "Takeoff completes " + kind)
    return id


func route(kind: String, profile: String, start: Vector2, finish: Vector2) -> void:
    var sim = fixture(profile)
    var mirror = fixture(profile)
    var id := lift(sim, kind, start)
    var b: Dictionary = sim.buildings[id]
    var ground: float = sim.terrain.flight_ground(b.pos, b.pos, Flight.radius(b))
    check(is_equal_approx(b.flight.height, ground + 144), "Local takeoff clearance " + kind + profile)
    check(sim.command(1, {"action": "building_move", "building": id, "pos": finish}).is_empty(), "Terrain route accepted")
    var climbed_early := false
    var waited := false
    var descending_snapshot := false
    var restored := false
    var trace: Array = []
    for tick in range(650):
        var before: Vector2 = b.pos
        var altitude: float = b.flight.height
        var heading: float = b.flight.heading
        sim.step()
        check(b.flight.height - altitude <= 96.0 / 20.0 + 0.001, "Climb is bounded")
        check(altitude - b.flight.height <= 64.0 / 20.0 + 0.001, "Descent is bounded")
        check(Flight.air_path_clear(sim, id, before, b.pos, altitude, b.flight.height), "Entire swept motion clears terrain")
        check(Flight.valid(b, sim.WORLD, sim.terrain), "Airborne state validates while following terrain")
        if absf(angle_difference(heading, b.flight.heading)) > Flight.HEADING_EPSILON:
            check(before == b.pos, "Rotation does not introduce sideways motion")
        elif before != b.pos:
            check(absf(angle_difference(b.flight.heading, Flight.heading_for_direction(b, b.pos - before))) < 0.001, "Narrow nose/front aligns with actual movement")
        if before == b.pos and b.flight.error == "Rising for terrain clearance":
            waited = true
        if b.pos.x < 1600 - Flight.radius(b) and b.flight.height > ground + 145:
            climbed_early = true
        if b.flight.height > b.flight.cruise + 1:
            descending_snapshot = true
        if tick == 90:
            check(mirror.apply_snapshot(sim.snapshot()), "Midflight restore with dynamic target")
            mirror.next_id = sim.next_id
            restored = true
        elif restored:
            mirror.step()
            check(mirror.snapshot() == sim.snapshot(), "Restored simulation continues deterministically")
        if tick % 20 == 0:
            trace.append([float(tick), b.pos.x, b.pos.y, b.flight.height, b.flight.cruise])
        if not b.flight.moving and is_equal_approx(b.flight.height, b.flight.cruise):
            break
    check((b.pos as Vector2).distance_to(finish) < 0.01, "Route reaches destination " + kind + profile)
    check(is_equal_approx(b.flight.height, sim.terrain.flight_ground(b.pos, b.pos, Flight.radius(b)) + 144), "Settles at local 4.5-cell clearance")
    if profile in ["cliff", "ridge"] and finish.x > start.x:
        check(climbed_early and waited, "Steep cliff anticipates climb and waits when needed")
    if finish.x < start.x or profile == "ridge":
        check(descending_snapshot, "Descent allows actual height above target")
    var bad: Dictionary = sim.snapshot()
    bad.version = "gaia-frontier-16"
    check(not mirror.apply_snapshot(bad), "Old fixed-altitude protocol rejected")
    bad = sim.snapshot()
    bad.buildings[id].flight.cruise += 500
    check(not mirror.apply_snapshot(bad), "Forged terrain-follow target rejected")
    bad = sim.snapshot()
    bad.buildings[id].flight.height = b.flight.ground - 1
    check(not mirror.apply_snapshot(bad), "Underground flight snapshot rejected")
    routes.append({"kind": kind, "profile": profile, "trace": trace})


func stop_and_land(kind: String) -> void:
    var sim = fixture("cliff")
    var id := lift(sim, kind, Vector2(1184, 1408))
    var b: Dictionary = sim.buildings[id]
    sim.command(1, {"action": "building_move", "building": id, "pos": Vector2(2208, 1408)})
    for tick in range(200):
        sim.step()
        if b.flight.height > b.flight.ground + 160:
            break
    check(sim.command(1, {"action": "building_stop", "building": id}).is_empty(), "Stop while climbing")
    var stopped: Vector2 = b.pos
    for tick in range(100):
        sim.step()
        check(b.pos == stopped, "Stopped building continues height correction without translation")
    check(is_equal_approx(b.flight.height, b.flight.ground + 144), "Stop settles at local terrain altitude")
    sim.visible[1].fill(1)
    var destination := Vector2(2304, 1408)
    check(sim.command(1, {"action": "building_deploy", "building": id, "pos": destination}).is_empty(), "High platform landing accepted")
    var last_height: float = b.flight.height
    var began := false
    for tick in range(650):
        sim.step()
        if b.flight.state == "landing" and b.flight.ticks == 0:
            began = true
            check(absf(b.flight.height - last_height) <= 4.8 + 0.001, "Landing freezes actual height without jump")
            check(is_equal_approx(b.flight.cruise, b.flight.height), "Landing upper endpoint is actual altitude")
        last_height = b.flight.height
        if b.flight.state == "grounded":
            break
    check(began and b.flight.state == "grounded" and b.flight.height == 192, "Landing ends on high platform")


func vertical_blocker() -> void:
    var sim = fixture("distant_peak")
    var id := lift(sim, "barracks", Vector2(1024, 1408))
    var b: Dictionary = sim.buildings[id]
    b.flight.height = 180.0
    var other: int = sim._add_building(1, "base", b.pos, true)
    for tick in range(30):
        sim.step()
    check(b.flight.height >= 164 and not b.flight.error.is_empty(), "Descent stops above another hull")
    sim.buildings.erase(other)
    for tick in range(30):
        sim.step()
    check(b.flight.height == 144 and b.flight.error.is_empty(), "Descent resumes after obstruction disappears")


func adjacent_launch() -> void:
    var sim = fixture("distant_peak")
    var origin: Vector2 = sim.snap_building("barracks", Vector2(1024, 1408))
    sim._add_building(1, "base", origin + Vector2(224, 48), true)
    var id := lift(sim, "barracks", origin)
    var b: Dictionary = sim.buildings[id]
    check(b.flight.height == 144 and b.flight.cruise == 144, "Adjacent tower does not raise the entire launch column")
    check(sim.command(1, {"action": "building_move", "building": id, "pos": origin - Vector2(384, 0)}).is_empty(), "Tightly launched building can depart")
    for tick in range(220):
        sim.step()
    check(b.pos == origin - Vector2(384, 0) and b.flight.height == 144, "Departure clears neighbor and settles at terrain height")
    sim.visible[1].fill(1)
    check(sim.command(1, {"action": "building_deploy", "building": id, "pos": origin}).is_empty(), "Return to adjacent landing site accepted from lower altitude")
    for tick in range(350):
        sim.step()
        check(Flight.valid(b, sim.WORLD, sim.terrain), "Tight landing approach and descent validate")
        if b.flight.state == "grounded":
            break
    check(b.flight.state == "grounded" and b.pos == origin, "Tight landing approach clears tall neighbor and returns to ground")


func component_peak() -> void:
    var sim = fixture("distant_peak")
    var surface := Sim.MapTerrain.SampleSurface.new()
    surface.cache_bounds = Rect2(960, 1344, 128, 128)
    surface.columns = 17
    surface.rows = 17
    surface.heights.resize(17 * 17)
    surface.heights.fill(0)
    # An 8-unit peak between coarse 32-unit cell centers must not be missed.
    surface.heights[9 * 17 + 9] = 192
    sim.terrain.sample_surface = surface
    sim.terrain.flight_cell_heights.clear()
    check(sim.terrain.height_at(Vector2(1032, 1416)) == 192, "Component vertex fixture has a narrow peak")
    check(sim.terrain.flight_ground(Vector2(1000, 1408), Vector2(1064, 1408), 12) == 192, "Swept sampler includes narrow component peak")
    check(sim.terrain.flight_ground_rect(Rect2(1024, 1408, 32, 32)) == 192, "Lift column includes every component vertex")


func landing_abort(kind: String) -> void:
    var sim = fixture("distant_peak")
    var id := lift(sim, kind, Vector2(1024, 1408))
    var b: Dictionary = sim.buildings[id]
    # Valid descending state, deliberately not yet at the local hover target.
    b.flight.height = 220.0
    sim.visible[1].fill(1)
    check(sim.command(1, {"action": "building_deploy", "building": id, "pos": b.pos}).is_empty(), "Deploy during altitude correction")
    sim.step()
    check(b.flight.state == "landing" and is_equal_approx(b.flight.cruise, 216.8), "Landing starts from actual descending altitude")
    for tick in range(Flight.duration(b) / 2):
        sim.step()
    var before: float = b.flight.height
    var blocker: int = sim.add_unit(1, "soldier", b.pos)
    sim.step()
    check(b.flight.state == "taking_off" and b.flight.error.begins_with("Landing aborted:"), "Mid-descent intrusion aborts landing")
    check(absf(b.flight.height - before) < 8 and Flight.valid(b, sim.WORLD, sim.terrain), "Aborted descent preserves interpolated height")
    sim.units.erase(blocker)
    for tick in range(Flight.duration(b) + 80):
        sim.step()
    check(b.flight.state == "airborne" and is_equal_approx(b.flight.height, 144), "Aborted landing returns to local hover height")


func run() -> void:
    for kind: String in ["base", "barracks"]:
        route(kind, "distant_peak", Vector2(1024, 1408), Vector2(1312, 1408))
        route(kind, "cliff", Vector2(1024, 1408), Vector2(2304, 1408))
        route(kind, "cliff", Vector2(2304, 1408), Vector2(1024, 1408))
        route(kind, "ridge", Vector2(1024, 1408), Vector2(2304, 1536))
        route(kind, "ramp", Vector2(1024, 1408), Vector2(2304, 1664))
        stop_and_land(kind)
        landing_abort(kind)
    vertical_blocker()
    adjacent_launch()
    component_peak()
    if "--capture-terrain-flight" in OS.get_cmdline_args():
        check(not FileAccess.file_exists(BASELINE), "Never overwrite frozen flight baseline")
        if failures.is_empty():
            var file := FileAccess.open(BASELINE, FileAccess.WRITE)
            file.store_string(JSON.stringify({"protocol": Sim.VERSION, "relative_height": 144, "climb_speed": 96, "descent_speed": 64, "routes": routes}, "  ") + "\n")
    else:
        check(FileAccess.file_exists(BASELINE), "Terrain flight baseline exists")
        if FileAccess.file_exists(BASELINE):
            var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASELINE))
            # Compare at the frozen JSON's serialization precision, not the
            # original binary float precision lost when the fixture was saved.
            check(data.protocol == "gaia-frontier-17" and Sim.VERSION == "gaia-frontier-19" and JSON.stringify(data.routes) == JSON.stringify(routes), "Frozen terrain flight traces unchanged")
    print("TERRAIN_FLIGHT ", JSON.stringify({"checks": checks, "failures": failures}))
    quit(0 if failures.is_empty() else 1)
