extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
const Flight = Sim.BarracksFlight
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
    run.call_deferred()


func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok and not failures.has(message):
        failures.append(message)
        push_error(message)


func fixture():
    var sim := Sim.new()
    sim.reset(false, "frontier_four")
    sim.buildings.clear()
    sim.units.clear()
    sim.ores.clear()
    sim.terrain.heights.fill(0.0)
    sim.terrain.gradients.fill(Vector2.ZERO)
    sim.terrain.flight_cell_heights.clear()
    sim._add_building(2, "base", Vector2(4352, 2816), true)
    return sim


func hovering(sim, position: Vector2, height: float, owner: int = 1) -> int:
    var id: int = sim._add_building(owner, "barracks", position, true)
    var b: Dictionary = sim.buildings[id]
    b.flight.state = "airborne"
    b.flight.height = height
    Flight.refresh_cruise(sim, b)
    return id


func adjacent_repro(owner: int) -> void:
    var sim = fixture()
    var base: int = sim._add_building(1, "base", Vector2(1024, 1408), true)
    var b: Dictionary = sim.buildings[base]
    var barracks: int = sim._add_building(owner, "barracks", b.pos + Vector2(224, 48), true)
    check(sim.command(owner, {"action": "building_takeoff", "building": barracks}).is_empty(), "Adjacent barracks can lift")
    for tick in range(80):
        sim.step()
    var flyer: Dictionary = sim.buildings[barracks]
    check(flyer.flight.state == "airborne" and flyer.flight.height == 144, "Adjacent barracks retains terrain-relative altitude")
    # Occupy the low wing, not the empty space beyond the base's footprint.
    flyer.pos = b.pos + Vector2(112, 0)
    flyer.flight.target = flyer.pos
    Flight.refresh_cruise(sim, flyer)
    check(Flight.air_clear(sim, barracks, flyer.pos, flyer.flight.height), "Barracks can hover above the low wing")
    var original: Dictionary = b.flight.duplicate(true)
    var error: String = sim.command(1, {"action": "building_takeoff", "building": base})
    check(error.contains("升空通道") and b.flight.error == error, "Occupied launch reports actionable error")
    for key: String in original:
        if key != "error":
            check(b.flight[key] == original[key], "Rejected launch preserves " + key)
    check(Flight.valid(b, sim.WORLD, sim.terrain), "Rejected launch remains valid")
    var mirror = fixture()
    check(mirror.apply_snapshot(sim.snapshot()), "Rejection snapshot accepted")
    check(sim.command(owner, {"action": "building_move", "building": barracks, "pos": flyer.pos + Vector2(0, 500)}).is_empty(), "Blocking flyer can leave")
    for tick in range(350):
        sim.step()
    check(b.flight.state == "grounded", "No implicit takeoff after blocker leaves")
    check(sim.command(1, {"action": "building_takeoff", "building": base}).is_empty(), "Explicit retry succeeds after clearance")
    for tick in range(120):
        sim.step()
        check(Flight.valid(b, sim.WORLD, sim.terrain), "Retry produces valid lift states")
    check(b.flight.state == "airborne" and b.flight.error.is_empty(), "Base finishes retry without a stuck state")


func reserved_route(reverse_ids: bool) -> void:
    var sim = fixture()
    var origin := Vector2(1024, 1408)
    var base := -1
    var flyer := -1
    if reverse_ids:
        flyer = hovering(sim, origin + Vector2(400, 0), 164)
        base = sim._add_building(1, "base", origin, true)
    else:
        base = sim._add_building(1, "base", origin, true)
        flyer = hovering(sim, origin + Vector2(400, 0), 164)
    check(sim.command(1, {"action": "building_move", "building": flyer, "pos": origin - Vector2(400, 0)}).is_empty(), "Flyer route issued before takeoff")
    check(sim.command(1, {"action": "building_takeoff", "building": base}).is_empty(), "Clear launch accepted")
    check(not Flight.air_clear(sim, flyer, origin, 164), "Future lift column reserved immediately")
    check(not sim.command(1, {"action": "building_move", "building": flyer, "pos": origin}).is_empty(), "Cannot retarget into active lift column")
    var mirror = fixture()
    check(mirror.apply_snapshot(sim.snapshot()), "Reserved launch snapshot accepted")
    for tick in range(160):
        sim.step()
        mirror.step()
        var b: Dictionary = sim.buildings[base]
        check(Flight.valid(b, sim.WORLD, sim.terrain), "In-flight state validates")
        check(Flight.air_clear(sim, base, b.pos, b.flight.height), "No airborne intruder intersects lift")
        check(b.flight == mirror.buildings[base].flight and sim.buildings[flyer].pos == mirror.buildings[flyer].pos, "Snapshot continuation reserves the same column")
    check(sim.buildings[base].flight.state == "airborne", "Existing crossing route cannot deadlock launch")


func run() -> void:
    for owner in [1, 2]:
        adjacent_repro(owner)
    for reverse in [false, true]:
        reserved_route(reverse)
    var sim = fixture()
    var origin := Vector2(1024, 1408)
    var base: int = sim._add_building(1, "base", origin, true)
    var overhead := hovering(sim, origin, 200)
    check(not sim.command(1, {"action": "building_takeoff", "building": base}).is_empty(), "Direct overhead blocks lift")
    sim.buildings[overhead].flight.height = 308.0
    check(sim.command(1, {"action": "building_takeoff", "building": base}).is_empty(), "Sufficient vertical gap permits lift")
    for tick in range(120):
        sim.step()
    check(sim.buildings[base].flight.state == "airborne", "Upper flyer cannot descend into reserved lift")
    simultaneous_launch()
    await blocked_interface()
    print("LIFT_CLEARANCE ", JSON.stringify({"checks": checks, "failures": failures}))
    quit(0 if failures.is_empty() else 1)


func simultaneous_launch() -> void:
    var sim = fixture()
    var base: int = sim._add_building(1, "base", Vector2(1024, 1408), true)
    var barracks: int = sim._add_building(1, "barracks", sim.buildings[base].pos + Vector2(224, 48), true)
    check(sim.command(1, {"action": "building_takeoff", "building": base}).is_empty(), "First adjacent lift gets reservation")
    check(sim.command(1, {"action": "building_takeoff", "building": barracks}).is_empty(), "Nonoverlapping adjacent lift columns may rise together")
    for tick in range(120):
        sim.step()
    check(sim.buildings[barracks].flight.state == "airborne", "Adjacent barracks completes simultaneous lift")
    sim.buildings[base].hp = 0
    sim.step()
    check(Flight.air_clear(sim, barracks, sim.buildings[barracks].pos, 144), "Destroyed neighbor leaves no stale reservation")
    for tick in range(80):
        sim.step()
    check(sim.buildings[barracks].flight.state == "airborne", "Neighbor lifts after reservation disappears")


func blocked_interface() -> void:
    var game = preload("res://scenes/main.tscn").instantiate()
    game.selected_map_id = "desert_sample"
    root.add_child(game)
    game.play_solo()
    game.set_process(false)
    var b: Dictionary = game.sim.buildings[1]
    var blocker := hovering(game.sim, b.pos + Vector2(160, 0), b.flight.ground + 200)
    game.selected_building = 1
    game.selected_buildings.assign([1])
    game.camera_controller.focus = b.pos
    game.camera_zoom_level = 1.0
    game._update_camera_transform()
    game.issue({"action": "building_takeoff", "building": 1})
    game._sync_visuals()
    game._refresh_ui()
    check(b.flight.state == "grounded", "UI takeoff keeps blocked base grounded")
    check(game.hud_controller.view.detail.text.contains("升空通道"), "Selected building shows blockage reason")
    check(game.action_buttons[0].action_id == "takeoff" and not game.action_buttons[0].disabled, "Retry button stays enabled")
    check(game.action_buttons[2].action_id == "barracks" and not game.action_buttons[2].disabled, "Blocked base retains ground construction controls")
    if DisplayServer.get_name() != "headless":
        for frame in range(8):
            game._sync_visuals(1.0 / 60.0)
            await process_frame
        await RenderingServer.frame_post_draw
        var folder := "res://assets/concept_art/building_lifecycle/"
        DirAccess.make_dir_recursive_absolute(folder)
        check(root.get_texture().get_image().save_png(folder + "takeoff_blocked.png") == OK, "Blocked launch screenshot saved")
    game.sim.buildings.erase(blocker)
    game.issue({"action": "building_takeoff", "building": 1})
    check(b.flight.state == "taking_off" and b.flight.error.is_empty(), "UI retry clears the error and starts takeoff")
    game.queue_free()
    await process_frame
