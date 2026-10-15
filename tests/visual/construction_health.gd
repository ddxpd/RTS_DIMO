extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
const Economy = preload("res://scripts/simulation_systems/economy_system.gd")
const MAIN = preload("res://scenes/main.tscn")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
    run.call_deferred()


func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)


func arithmetic() -> void:
    for maximum in [1, 9, 101, 333, 1000]:
        for duration in [1, 7, 140, 333]:
            var hp := Economy.construction_health(maximum, duration, duration)
            check(hp == ceili(maximum * 0.1), "Initial tenth rounds up")
            for elapsed in range(1, duration + 1):
                var before := Economy.construction_health(maximum, duration, duration - elapsed + 1)
                var after := Economy.construction_health(maximum, duration, duration - elapsed)
                check(after >= before, "Undamaged construction grows monotonically")
                hp += after - before
            check(hp == maximum, "Rounding never loses health at completion")
    var hp := 100
    for remaining in range(139, -1, -1):
        hp += Economy.construction_health(1000, 140, remaining) - Economy.construction_health(1000, 140, remaining + 1)
        if remaining == 70:
            hp -= 100
    check(hp == 900, "1000 maximum minus 100 damage finishes at 900")


func simulation_cases() -> void:
    var sim := Sim.new()
    sim.reset(false, "desert_sample")
    var origin: Vector2 = sim.buildings[1].pos + Vector2(0, -256)
    var mirror := Sim.new()
    mirror.reset(false, "desert_sample")
    for kind: String in Sim.BUILD_TYPES:
        var stats: Dictionary = Sim.BUILD_TYPES[kind]
        var complete := sim._add_building(1, kind, origin, true)
        check(sim.buildings[complete].hp == stats.hp, "Completed factory remains full: " + kind)
        sim.buildings.erase(complete)
        var id := sim._add_building(1, kind, origin, false)
        var b: Dictionary = sim.buildings[id]
        check(b.hp == ceili(stats.hp * 0.1), "New construction starts at ten percent: " + kind)
        for tick in range(int(stats.time) / 2):
            sim.step()
        b.hp -= 40
        check(mirror.apply_snapshot(sim.snapshot()), "Damaged construction snapshot accepted: " + kind)
        var remaining := int(b.remaining)
        for tick in range(remaining):
            if tick == 0:
                b.hp -= 60
                mirror.buildings[id].hp -= 60
            sim.step()
            mirror.step()
            check(b.hp == mirror.buildings[id].hp and b.remaining == mirror.buildings[id].remaining, "Snapshot continuation matches: " + kind)
        check(b.remaining == 0 and b.hp == stats.hp - 100, "Damage survives completion on original deadline: " + kind)
        sim.step()
        check(b.hp == stats.hp - 100, "Finished building does not keep healing: " + kind)
        sim.buildings.erase(id)
    # Real combat during construction and on the completion tick.
    for remaining in [140, 1]:
        var id := sim._add_building(1, "base", origin, false)
        var b: Dictionary = sim.buildings[id]
        b.remaining = remaining
        b.hp = 1
        var attacker := sim.add_unit(2, "mobile_infantry", origin + Vector2(220, 0))
        sim.units[attacker].order = "attack"
        sim.units[attacker].attack_kind = "building"
        sim.units[attacker].attack_id = id
        sim.visible[2].fill(1)
        sim.rebuild_navigation()
        check(not sim.position_free(origin, 0), "Foundation blocks before lethal attack")
        sim.step()
        check(not sim.buildings.has(id), "Attack destroys construction/completion-tick building")
        check(sim.effects.any(func(effect: Dictionary): return effect.has("destruction") and effect.destruction.id == id), "Destruction effect dispatched")
        check(sim.position_free(origin, 0), "Destroyed construction releases footprint")
        sim.units.erase(attacker)
        sim.step()
        check(not sim.buildings.has(id), "Destroyed building cannot regrow")
    var dead := sim._add_building(1, "base", origin, false)
    sim.buildings[dead].hp = 0
    sim.step()
    check(not sim.buildings.has(dead), "Zero-health construction is not resurrected before cleanup")


func capture(name: String) -> void:
    if DisplayServer.get_name() == "headless":
        return
    for i in range(4):
        await process_frame
    await RenderingServer.frame_post_draw
    var folder := "res://assets/concept_art/building_lifecycle/construction_health/"
    DirAccess.make_dir_recursive_absolute(folder)
    check(root.get_texture().get_image().save_png(folder + name + ".png") == OK, "Saved " + name)


func visual_case() -> void:
    root.size = Vector2i(1440, 900)
    var game := MAIN.instantiate()
    game.selected_map_id = "desert_sample"
    root.add_child(game)
    game.play_solo()
    game.set_process(false)
    var sim = game.sim
    var origin: Vector2 = sim.buildings[1].pos + Vector2(0, -256)
    var id: int = sim._add_building(1, "base", origin, false)
    var b: Dictionary = sim.buildings[id]
    game.selected_building = id
    game.selected_buildings.assign([id])
    game.camera_controller.focus = b.pos
    game.camera_zoom_level = 1.6
    game._update_camera_transform()
    for stage in ["start", "half", "damaged", "complete"]:
        if stage == "half" or stage == "complete":
            for tick in range(70):
                sim.step()
        elif stage == "damaged":
            b.hp -= 100
        game._sync_visuals()
        game._refresh_ui()
        var expected: int = {"start": 80, "half": 440, "damaged": 340, "complete": 700}[stage]
        var entry: Dictionary = game.health_grid_overlay.entries["building_%d" % id]
        check(entry.current_hp == expected and entry.max_hp == 800, "World health bar reflects " + stage)
        check(game.hud_controller.view.health_text.text == "%d / 800" % expected, "Selection panel reflects " + stage)
        check(not game.building_visuals[id].has("build_bar"), "No separate progress bar: " + stage)
        check(game.building_visuals[id].visual.construction_tint == (b.remaining > 0), "Construction visual retained: " + stage)
        await capture(stage)
    game.queue_free()
    await process_frame


func run() -> void:
    arithmetic()
    simulation_cases()
    await visual_case()
    print("CONSTRUCTION_HEALTH ", JSON.stringify({"checks": checks, "failures": failures}))
    quit(0 if failures.is_empty() else 1)
