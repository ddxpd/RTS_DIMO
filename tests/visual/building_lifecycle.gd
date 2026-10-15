extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
const Destruction = preload("res://assets/art/effects/building_destruction.gd")
const MAIN = preload("res://scenes/main.tscn")
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
    var sim := Sim.new()
    sim.reset(false, "desert_sample")
    var id: int = sim.buildings.keys()[0]
    var b: Dictionary = sim.buildings[id]
    var origin: Vector2 = b.pos
    check(b.type == "base", "Base-only sample fixture")
    check(not sim.command(2, {"action": "building_takeoff", "building": id}).is_empty(), "Enemy cannot lift base")
    check(sim.command(1, {"action": "building_takeoff", "building": id}).is_empty(), "Base accepts takeoff")
    check(not sim.command(1, {"action": "building_move", "building": id, "pos": origin}).is_empty(), "Transition cannot move horizontally")
    var mirror := Sim.new()
    mirror.reset(false, "desert_sample")
    for i in range(120):
        sim.step()
        check(Sim.BarracksFlight.valid(b, sim.WORLD), "Valid base lift tick %d" % i)
    check(b.flight.state == "airborne", "Six-second takeoff completes")
    check(not Sim.BarracksFlight.blocks_ground(b), "Airborne base releases ground occupancy")
    check(mirror.apply_snapshot(sim.snapshot()), "Airborne base snapshot accepted")
    check(sim.command(1, {"action": "building_move", "building": id, "pos": origin + Vector2(64, 0)}).is_empty(), "Base accepts movement")
    for i in range(60):
        sim.step()
    check(b.pos.distance_to(origin) > 0.0, "Base moves after turning")
    sim.command(1, {"action": "building_stop", "building": id})
    var stopped: Vector2 = b.pos
    sim.step()
    check(b.pos == stopped, "Stop cancels translation")
    var site := sim.deployment_site(1, id, origin + Vector2(1, 1))
    check(site.cells.size() == 60 and site.pos == origin and site.error.is_empty(), "Base deployment snaps all 60 cells")
    var blocker := sim.add_unit(1, "mobile_infantry", origin + Vector2(144, 80))
    check(not sim.deployment_site(1, id, origin).error.is_empty(), "Unit at far corner blocks entire base foundation")
    sim.units.erase(blocker)
    sim.visible[1].fill(0)
    check(not sim.deployment_site(1, id, origin).error.is_empty(), "Hidden terrain cannot receive base")
    sim.visible[1].fill(1)
    check(sim.command(1, {"action": "building_deploy", "building": id, "pos": origin}).is_empty(), "Base accepts redeployment")
    for i in range(360):
        sim.step()
    check(b.flight.state == "grounded" and b.pos == origin, "Base returns to aligned foundation")
    check(mirror.apply_snapshot(sim.snapshot()), "Redeployed base snapshot accepted")
    var invalid := sim.snapshot()
    invalid.buildings[id].flight.height = NAN
    check(not mirror.apply_snapshot(invalid), "Invalid base altitude rejected")
    var overhead := sim._add_building(1, "barracks", origin, true)
    sim.buildings[overhead].flight.state = "airborne"
    sim.buildings[overhead].flight.height = b.flight.height + 130.0
    check(not Sim.BarracksFlight.air_clear(sim, id, origin, b.flight.height), "Base tall hull blocks overlapping overhead aircraft")
    sim.buildings.erase(overhead)
    for kind: String in ["base", "barracks", "refinery"]:
        var victim := sim._add_building(1, kind, origin + Vector2(640, 0), true)
        sim.buildings[victim].hp = 0
        sim.step()
        var event: Dictionary = sim.effects[-1]
        check(event.destruction.type == kind and event.destruction.id == victim, "Authoritative death identity " + kind)
        check(not sim.buildings.has(victim), "Death removes gameplay body immediately " + kind)
        check(mirror.apply_snapshot(sim.snapshot()), "Destruction snapshot accepted " + kind)
        var bad := sim.snapshot()
        bad.effects[-1].destruction.heading = INF
        check(not mirror.apply_snapshot(bad), "Invalid destruction heading rejected")
        var effect := Destruction.new()
        root.add_child(effect)
        effect.configure(event, sim.terrain.height_at(event.to))
        check(not effect.hull_meshes.is_empty(), "Visible hull retained " + kind)
        effect.advance(1.5, 0.0)
        check(effect.hull.scale.y < 1.0 and not effect.finished, "Structure collapses " + kind)
        effect.advance(5.5, 0.0)
        check(effect.hull_meshes[0].transparency > 0.0, "Wreck fades " + kind)
        effect.advance(6.1, 0.0)
        check(effect.finished and not effect.visible, "Effect expires " + kind)
        effect.free()
    var game = MAIN.instantiate()
    root.add_child(game)
    game.selected_map_id = "desert_sample"
    game.set_process(false)
    game.play_solo()
    var base_id: int = game.sim.buildings.keys()[0]
    game.selected_building = base_id
    game.selected_buildings.assign([base_id])
    game._refresh_ui()
    check(game.action_buttons[0].action_id == "takeoff" and not game.action_buttons[0].disabled, "Base takeoff command card")
    game._takeoff_barracks()
    for i in range(120):
        game.sim.step()
    game._sync_visuals(0.05)
    var visual = game.visual_sync.building_visuals[base_id].visual
    check(absf(visual.model.presentation.position.y - 12.0) < 0.6, "Authority altitude is not doubled")
    check(visual.model.engine_plumes.size() == 4 and visual.model.engine_plumes[0].visible, "Four active lift plumes")
    game._begin_deploy()
    check(game.deploy_building == base_id, "Base deployment UI enabled")
    game.visual_sync._sync_deploy_preview(game.sim.buildings[base_id].pos)
    check(game.visual_sync.build_preview_model.kind == "base", "Preview uses base model")
    game.sim.buildings[base_id].hp = 0
    game.sim.step()
    game._sync_visuals(0.05)
    var death_keys: Array = game.visual_sync.effect_visuals.keys().filter(func(key): return str(key).begins_with("building_death_"))
    check(death_keys.size() == 1, "Death creates one effect")
    var death_node: Node3D = game.visual_sync.effect_visuals[death_keys[0]]
    for i in range(140):
        game._sync_visuals(0.05)
    check(not game.visual_sync.effect_visuals[death_keys[0]].visible, "Frozen end-state does not replay death")
    check(game.visual_sync.effect_visuals[death_keys[0]] == death_node, "Repeated snapshot does not create duplicate death")
    game.sim.effects.clear()
    game._sync_visuals(0.05)
    check(game.visual_sync.effect_visuals.is_empty(), "Expired event releases completed effect")
    game.visual_sync.reset_world()
    check(game.visual_sync.effect_visuals.is_empty(), "Reset clears death effects")
    game.queue_free()
    await process_frame
    print("BUILDING_LIFECYCLE checks=", checks, " failures=", failures)
    quit(0 if failures.is_empty() else 1)
