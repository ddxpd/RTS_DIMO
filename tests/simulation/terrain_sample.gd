extends SceneTree

const Sim = preload("res://scripts/simulation.gd")
var failures: Array[String] = []


func _initialize() -> void:
    run.call_deferred()


func check(value: bool, message: String) -> void:
    if not value:
        failures.append(message)
        push_error(message)


func mining_routes() -> void:
    var sim := Sim.new()
    check(sim.reset(false, "desert_sample"), "Load training resource routes")
    var station := sim._add_building(1, "refinery", Vector2(1952, 1280), true)
    sim.rebuild_navigation()
    for ore_id in [1, 4, 9, 11, 17, 19]:
        var spawn := sim._spawn_position(sim.buildings[station], "harvester")
        check(spawn != Vector2.ZERO, "Training station has a clear full-size production exit")
        var id := sim.add_unit(1, "harvester", spawn)
        var before: int = sim.money[1]
        check(sim.command(1, {"action": "gather", "units": [id], "target": ore_id}).is_empty(), "Accept harvesting from each resource group")
        var clear := true
        var ticks := 0
        while ticks < 2400 and sim.money[1] == before:
            var previous: Vector2 = sim.units[id].pos
            sim.step()
            clear = clear and sim.movement_free(previous, sim.units[id].pos, Sim.UNIT_TYPES.harvester.radius)
            ticks += 1
        check(clear and sim.money[1] == before + 60, "Group %d completes harvesting and unloading without crossing cliffs" % ore_id)
        if sim.money[1] == before:
            print("TRAINING_STUCK ", ore_id, " ", sim.units[id])
        print("TRAINING_MINING ore=", ore_id, " ticks=", ticks, " credited=", sim.money[1] - before)
        sim.units.erase(id)
    var mirror := Sim.new()
    check(mirror.apply_snapshot(sim.snapshot()) and mirror.snapshot() == sim.snapshot(), "Expanded training snapshot restores all deposits and buildings")
    for tick in range(30):
        sim.step()
        mirror.step()
        check(mirror.snapshot() == sim.snapshot(), "Training snapshots continue deterministically")


func run() -> void:
    var sim := Sim.new()
    check(sim.reset(true, "desert_sample"), "Load sample: " + sim.last_snapshot_error)
    if not sim.last_snapshot_error.is_empty():
        quit(1)
        return
    var field = sim.terrain.sample_surface
    check(sim.is_test_map() and not sim.ai_enabled and sim.money[1] == 10000, "Local sandbox defaults")
    check(sim.units.is_empty() and sim.ores.size() == 22 and sim.buildings.size() == 1, "Training starts with one base, 22 deposits and no troops")
    check(sim.buildings[1].type == "base" and sim.buildings[1].owner == 1 and sim.buildings[1].remaining == 0, "The remaining base is complete and controllable")
    check(sim.can_see(1, Vector2(4700, 3100)), "Fully revealed without spectator ownership")
    check(is_equal_approx(field.height_at(Vector2(1766, 1922)), 128), "Flat highland")
    check(is_equal_approx(field.height_at(Vector2(3016, 1782)), -128), "Flat pit floor")
    check(sim.terrain.build_error(Rect2(1776, 1856, 64, 64)).is_empty(), "Buildable plateau pad")
    check(not sim.terrain.build_error(Rect2(1844, 1512, 64, 64)).is_empty(), "No construction on ramp")
    check(not sim.terrain.segment_clear(Vector2(1200, 1882), Vector2(1456, 1882), 14), "No crossing expanded highland cliff")
    var high_area := 0.0
    var low_area := 0.0
    for surface: Dictionary in field.layout.surfaces:
        if surface.component == "plateau_top":
            high_area += surface._rect.get_area()
        elif surface.component == "sand_flat" and surface.position[1] < 0:
            low_area += surface._rect.get_area()
    check(high_area / (Sim.CELL * Sim.CELL) == 576 and low_area == high_area, "Both flat terrain areas expand from 16x16 to 24x24 cells")
    var counts := {128: 0, -128: 0, 0: 0}
    for ore: Dictionary in sim.ores.values():
        counts[int(field.height_at(ore.pos))] += 1
        check(ore.pos == Sim.WorldGrid.cell_center(ore.pos), "Every resource anchor aligns to cell centers")
        check(sim.terrain.build_error(Rect2(ore.pos - Vector2.ONE * 48, Vector2.ONE * 96)).is_empty(), "Entire 3x3 resource clearance sits on flat terrain")
        var worker := {"pos": Vector2(1872, 1328), "type": "harvester"}
        check(Sim.MiningSystem.work_point(sim, worker, sim.ores.find_key(ore)).is_finite(), "Each resource has a reachable harvesting point")
    check(counts == {128: 7, -128: 8, 0: 7}, "Uneven groups distribute resources over highland, pit and flat ground")
    for road: Dictionary in field.roads:
        var points: PackedVector2Array = road.points
        for i in range(1, points.size()):
            check(sim.terrain.segment_clear(points[i - 1], points[i], 14), "Road center remains traversable")
    for ramp: Dictionary in sim.terrain.definition.ramps:
        check(sim.terrain.segment_clear(ramp.start, ramp.end, 24), "Wide ramp center remains clear")
        var direction: Vector2 = (ramp.end - ramp.start).normalized()
        var sideways := Vector2(direction.y, -direction.x)
        var half_width := float(ramp.width) * 0.5
        for side: float in [-1.0, 1.0]:
            var offset := sideways * (half_width - 32.0) * side
            check(sim.terrain.segment_clear(ramp.start + offset, ramp.end + offset, 24), "Both sides retain harvester clearance")
        var middle: Vector2 = (ramp.start + ramp.end) * 0.5
        var gradient: float = field.gradient_at(middle).dot(direction)
        for t in [0.25, 0.75]:
            var p: Vector2 = (ramp.start as Vector2).lerp(ramp.end, t)
            check(absf(field.gradient_at(p).dot(direction) - gradient) < 0.002, "Central ramp has stable grade")
        check(absf(field.gradient_at(ramp.start).dot(direction)) < 0.12, "Sampled short-ramp entry meets flat ground smoothly")
        check(absf(field.gradient_at(ramp.end).dot(direction)) < 0.12, "Sampled short-ramp exit meets flat ground smoothly")
        check(absf(field.height_at(ramp.start - direction * 16)) < 0.01, "Flat approach stays at ground height")
        check(absf(field.height_at(ramp.end + direction * 16) - float(ramp.height)) < 0.01, "Flat departure stays at platform height")
        var ramp_mask: Vector4 = field.ramp_markings(middle)
        check(ramp_mask.x > 0.99, "Authored ramp has a material mask")
        var flat_mask: Vector4 = field.ramp_markings(ramp.start - direction * 64)
        check(flat_mask.length_squared() < 0.001, "Flat road outside connection has no ramp shading")
        var entry_mask: Vector4 = field.ramp_markings(ramp.start + direction * 16)
        var exit_mask: Vector4 = field.ramp_markings(ramp.end - direction * 16)
        check(entry_mask.z > 0.8 if float(ramp.height) > 0 else entry_mask.y > 0.8, "Entry marks toe uphill or crest downhill")
        check(exit_mask.y > 0.8 if float(ramp.height) > 0 else exit_mask.z > 0.8, "Exit marks crest uphill or toe downhill")
        for end: Vector2 in [ramp.start, ramp.end]:
            check(absf(field.height_at(end + Vector2(0, 0.1)) - field.height_at(end - Vector2(0, 0.1))) < 0.1, "Continuous ramp endpoint")
    # Each unit type must actually follow the existing command/navigation path
    # uphill and downhill; sampling heights alone cannot verify that contract.
    sim.units.clear()
    for kind in ["soldier", "harvester"]:
        for x in [1876.0, 2876.0]:
            var start := Vector2(x, 1092)
            # The new depot occupies the old large-unit start; begin outside its
            # swept radius while retaining the same uphill/downhill endpoints.
            if kind == "harvester" and x == 1876.0:
                start.x += 64.0
            var target := Vector2(x, 1882 if x == 1876.0 else 1782)
            var id := sim.add_unit(1, kind, start)
            check(sim.command(1, {"action": "move", "units": [id], "pos": target}).is_empty(), "Accept sample move")
            for tick in range(360):
                sim.step()
                if (sim.units[id].pos as Vector2).distance_to(target) < 14:
                    break
            check((sim.units[id].pos as Vector2).distance_to(target) < 20, "%s reaches ramp destination %s (at %s)" % [kind, target, sim.units[id].pos])
            check(sim.command(1, {"action": "move", "units": [id], "pos": start}).is_empty(), "Accept return over ramp")
            for tick in range(360):
                sim.step()
                if (sim.units[id].pos as Vector2).distance_to(start) < 14:
                    break
            check((sim.units[id].pos as Vector2).distance_to(start) < 20, "%s returns over ramp %s" % [kind, x])
            sim.units.erase(id)
    sim.buildings.clear()
    sim.step()
    check(sim.winner == 0, "Test field has no victory or defeat")
    var repeat := Sim.new()
    check(repeat.reset(false, "desert_sample"), "Reload sample")
    check(repeat.units.is_empty() and repeat.ores.size() == 22 and repeat.buildings.size() == 1, "Reset restores training resources and base-only roster")
    check(repeat.terrain.sample_surface.heights == field.heights, "Repeatable fine surface")
    check(repeat.reset(true, "desert_quarry") and not repeat.is_test_map() and repeat.ai_enabled, "Normal map restores AI")
    check(not repeat.can_see(1, Vector2(4700, 3100)), "Normal map restores fog")
    mining_routes()
    print("TERRAIN_SAMPLE ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
    quit(0 if failures.is_empty() else 1)
