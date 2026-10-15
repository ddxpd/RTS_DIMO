extends SceneTree

const Sim = preload("res://scripts/simulation.gd")
const Motion = preload("res://assets/art/units/harvester/hover_harvester_motion.gd")
var game: Node3D
var failures: Array[String] = []
var checks := 0
var metrics: Dictionary = {}


func _initialize() -> void:
    run.call_deferred()
    create_timer(120).timeout.connect(func(): quit(1))


func check(value: bool, message: String) -> void:
    checks += 1
    if not value:
        failures.append(message)
        push_error(message)


func sync(unit: Dictionary, visual: EntityVisual) -> void:
    game._sync_visuals(0.05)
    visual.set_heading(game.visual_sync._unit_heading(unit, game.sim.units.find_key(unit)), true)
    visual.harvester_motion.sample(unit, 0.05, game.sim.terrain)


func run() -> void:
    game = load("res://scenes/main.tscn").instantiate()
    root.add_child(game)
    game.play_solo()
    game.set_process(false)
    game.local_slot = 0
    game.sim.ai_enabled = false
    game.sim.units.clear()
    game.sim.buildings.clear()
    game.sim._add_building(1, "base", Vector2(640, 480), true)
    game.sim.ores = {1: {"pos": Vector2(1616, 1488), "amount": 10000}}
    game.sim.rebuild_navigation()
    var ore_id: int = game.sim.ores.keys()[0]
    var ore: Dictionary = game.sim.ores[ore_id]
    var point: Vector2 = ore.pos
    # A flat, nearby depot; run the real gather command and simulation economy.
    var depot_pos := Vector2(1600, 1900)
    game.sim._add_building(1, "refinery", depot_pos, true)
    game.sim._add_building(2, "base", Vector2(4300, 2600), true)
    game.sim.rebuild_navigation()
    var id: int = game.sim.add_unit(1, "harvester", point + Vector2(0, 110))
    var unit: Dictionary = game.sim.units[id]
    game.sim.update_visibility()
    check(game.sim.command(1, {"action": "gather", "units": [id], "target": ore_id}).is_empty(), "real gather order accepted")
    game._sync_visuals()
    var visual: EntityVisual = game.unit_visuals[id].visual
    check(is_equal_approx(Sim.UNIT_TYPES.harvester.radius, 32.0) and is_equal_approx(Sim.UNIT_TYPES.harvester.speed, 75.0), "two-cell movement envelope; speed unchanged")
    for name: String in ["Drill", "DrillShaft", "LeftWheel_0", "CargoHopper", "CargoGate", "CargoWindows", "CargoGlass"]:
        check(visual.model.find_child(name, true, false) == null, "removed old part " + name)
    for pair: Array in [[0,0],[1,1],[19,1],[20,2],[39,2],[40,3],[60,3]]:
        check(Motion.stage_for(pair[0]) == pair[1], "cargo boundary " + str(pair[0]))
    var saved_pos: Vector2 = unit.pos
    unit.order = "move"
    unit.target = unit.pos + Vector2(500, 0)
    game.visual_sync._unit_heading(unit, id)
    unit.pos += Vector2(0, 5)
    check(game.visual_sync._unit_heading(unit, id).dot(Vector2.DOWN) > 0.99, "harvester follows actual path instead of eastward final goal")
    unit.order = "idle"
    unit.heading = PI * 0.5
    check(game.visual_sync._unit_heading(unit, id).dot(Vector2.DOWN) > 0.99, "stopped harvester retains heading")
    game.connected = true
    game.is_host = false
    game.render_velocities[id] = Vector2.LEFT * 75.0
    unit.order = "move"
    check(game.visual_sync._unit_heading(unit, id).dot(Vector2.LEFT) > 0.99, "guest harvester uses snapshot velocity")
    game.connected = false
    game.render_velocities.erase(id)
    unit.pos = saved_pos
    unit.order = "gather"
    var money_before: int = game.sim.money[1]
    var ore_before: int = ore.amount
    var stages: Dictionary = {}
    var saw_mining := false
    var saw_return := false
    var paid := false
    var contact_distance := INF
    var extension_min := INF
    var extension_max := -INF
    for tick in range(1000):
        game.sim.step()
        sync(unit, visual)
        stages[visual.harvester_motion.cargo_stage] = true
        if int(unit.cargo) > 0 and int(unit.cargo) < 60 and unit.get("mining", {}).get("phase", "") == "work":
            saw_mining = true
            check(visual.animation_state == "mine", "partly loaded machine continues harvesting")
            var amount: float = visual.harvester_motion.extension
            extension_min = minf(extension_min, amount)
            extension_max = maxf(extension_max, amount)
            var jaw: Node3D = visual.model.find_child("Claw_L_A", true, false)
            var tip: Vector3 = jaw.global_transform * Vector3(0, 0, -0.30)
            contact_distance = minf(contact_distance, Vector2(tip.x, tip.z).distance_to(point))
        if int(unit.cargo) == 60:
            saw_return = true
            check(visual.animation_state in ["move", "idle"], "full bin travels or waits at the reserved berth without mining")
        if int(game.sim.money[1]) > money_before:
            paid = true
            check(int(unit.cargo) == 0 and visual.harvester_motion.cargo_stage == 0, "delivery resets cargo and visible contents together")
            break
    check(saw_mining and saw_return and paid, "complete approach / mining / full return / payout cycle")
    check(stages.size() == 4, "real economy visits all four visual cargo stages")
    check(int(game.sim.money[1]) - money_before == 60 and ore_before - int(ore.amount) == 60, "no changes to mineral accounting")
    check(visual.harvester_motion.extension < 0.17, "arms are stowed by delivery")
    check(extension_max - extension_min > 0.05, "sampling produces actual mechanical extension motion")
    check(contact_distance < preload("res://scripts/definitions/gameplay_rules.gd").MINING_CONTACT_RADIUS, "mining claw reaches inside crystal deposit footprint")
    metrics.closest_claw_to_ore = contact_distance
    # Exhausting a deposit with a partly filled bin must also return to the depot.
    unit.pos = point + Vector2(0, 44)
    unit.cargo = 10
    unit.order = "gather"
    ore.amount = 0
    unit.erase("dock")
    unit.erase("mining")
    unit.path = []
    game.sim.step()
    sync(unit, visual)
    check(Sim.DepotDocking.returning(game.sim, unit) and visual.animation_state in ["move", "idle"], "depleted partly loaded machine enters return flow without mining")
    check(game.visual_sync._unit_destination(unit).distance_to(point) > 80, "return facing targets depot rather than exhausted ore")
    check(not game.ore_visuals[ore_id].visual.visible, "depleted ore hides")
    var before_partial: int = game.sim.money[1]
    for tick in range(300):
        game.sim.step()
        sync(unit, visual)
        if int(game.sim.money[1]) > before_partial:
            break
    check(int(game.sim.money[1]) - before_partial == 10 and visual.harvester_motion.cargo_stage == 0, "partial cargo delivers without tipping animation")
    # Snapshot consumers get the same visible stage without new replicated fields.
    unit.cargo = 30
    var mirror := Sim.new()
    mirror.reset(false, game.sim.map_id)
    var applied := mirror.apply_snapshot(game.sim.snapshot())
    check(applied, "current protocol snapshot still applies: " + mirror.last_snapshot_error)
    var replica := EntityVisual.new("harvester", 1)
    root.add_child(replica)
    replica.harvester_motion.sample(mirror.units[id] if applied else unit, 0.0, null)
    check(replica.harvester_motion.cargo_stage == 2, "snapshot peer derives half bin from existing cargo field")
    replica.free()
    # Stopping retracts the arms while retaining collected minerals.
    ore.amount = 100
    unit.pos = point + Vector2(0, 44)
    unit.order = "gather"
    unit.work = 5
    sync(unit, visual)
    check(game.sim.command(1, {"action": "stop", "units": [id]}).is_empty(), "stop accepted")
    for frame in range(45):
        sync(unit, visual)
    check(visual.animation_state == "idle" and visual.harvester_motion.extension < 0.17, "stop retracts mining arms")
    check(visual.harvester_motion.cargo_stage == 2, "stop retains visible cargo")
    # Ground-only routing and terrain cushion, checked along an actual ramp traversal.
    game.sim.rebuild_navigation()
    unit.pos = Vector2(800, 1088)
    var target := Vector2(1450, 1088)
    check(not game.sim.terrain.segment_clear(Vector2(1180,850),Vector2(1260,850),Sim.UNIT_TYPES.harvester.radius), "hover appearance grants no cliff crossing")
    check(game.sim.command(1, {"action": "move", "units": [id], "pos": target}).is_empty(), "ground ramp order accepted")
    var lowest_clearance := INF
    for tick in range(240):
        var previous: Vector2 = unit.pos
        game.sim.step()
        sync(unit, visual)
        check(game.sim.terrain.segment_clear(previous, unit.pos, Sim.UNIT_TYPES.harvester.radius), "ground navigation remains valid on ramp")
        for mesh: MeshInstance3D in visual.model.find_children("*", "MeshInstance3D", true, false):
            if not mesh.name.begins_with("ThrusterMesh"):
                continue
            var aabb := mesh.get_aabb()
            for corner: Vector3 in [Vector3(aabb.position.x,aabb.position.y,aabb.position.z),Vector3(aabb.end.x,aabb.position.y,aabb.end.z)]:
                var p: Vector3 = mesh.global_transform * corner
                lowest_clearance = minf(lowest_clearance, p.y - game.sim.terrain.height_at(Vector2(p.x,p.z)))
        if (unit.pos as Vector2).distance_to(target) < 8:
            break
    check((unit.pos as Vector2).distance_to(target) < 20, "ground harvester reaches plateau using ramp")
    check(lowest_clearance > 0.5, "hover pods stay above terrain on ramp")
    metrics.lowest_pod_clearance = lowest_clearance
    metrics.checks = checks
    metrics.failures = failures
    var file := FileAccess.open("res://assets/concept_art/hover_harvester/runtime-report.json", FileAccess.WRITE)
    file.store_string(JSON.stringify(metrics, "  "))
    print("HOVER_HARVESTER_TEST ", JSON.stringify(metrics))
    game.queue_free()
    await process_frame
    quit(0 if failures.is_empty() else 1)
