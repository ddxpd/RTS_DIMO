extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
const Catalog = Sim.EntityCatalog
const Dock = Sim.DepotDocking
const Rules = preload("res://scripts/definitions/gameplay_rules.gd")
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
    sim.ai_enabled = false
    sim.units.clear()
    sim.buildings.clear()
    sim.ores.clear()
    sim.terrain.heights.fill(0)
    sim.terrain.gradients.fill(Vector2.ZERO)
    sim.terrain.flight_cell_heights.clear()
    sim._add_building(2, "base", Vector2(4352, 2816), true)
    sim._add_building(1, "refinery", Vector2(1600, 1600), true)
    sim.rebuild_navigation()
    return sim


func geometry() -> void:
    var motion = preload("res://assets/art/units/harvester/hover_harvester_motion.gd")
    check(motion.stage_for(29, 90) == 1 and motion.stage_for(30, 90) == 2 and motion.stage_for(60, 90) == 3, "Cargo presentation follows changed capacity")
    check(Catalog.HARVESTER_RADIUS == 32 and Catalog.HARVESTER_RADIUS * 2 / Sim.CELL == 2, "Approved circular footprint is two cells")
    for size in [Vector2(128, 128), Vector2(160, 192)]:
        for radius in [14.0, 32.0]:
            check(Catalog.dock_fit(radius, size), "Valid changed dimensions accepted")
            for slot in range(Catalog.REFINERY_DOCK_RECTS.size()):
                var entrance := Catalog.dock_point(slot, true, radius, size)
                var berth := Catalog.dock_point(slot, false, radius, size)
                check(is_equal_approx(-size.y * 0.5 - entrance.y - radius, Catalog.BODY_GAP), "Production gap derives from footprint and radius")
                check(-berth.y >= radius, "Dock stop touches or clears rear wall")
                check(entrance.x == berth.x and entrance.x == -size.x * 0.25, "Front-view right lane center derives from current width")

    check(not Catalog.dock_fit(32.01), "Oversize body reports invalid lane fit")
    check(not Catalog.dock_fit(32, Vector2(96, 128)), "Narrowed building reports invalid lane fit")
    check(not Catalog.dock_fit(14, Vector2(128, 48)), "Shortened platform reports invalid lane fit")


func production() -> void:
    var sim = fixture()
    var station: int = sim.next_id - 1
    var b: Dictionary = sim.buildings[station]
    var ids: Array[int] = []
    for slot in range(Catalog.REFINERY_DOCK_RECTS.size()):
        var entrance := Dock.entrance(b, slot)
        var berth := Dock.berth(b, slot)
        check(Catalog.REFINERY_DOCK_RECTS[slot].has_point(berth - b.pos), "Stop is inside the actual platform")
        check(sim.movement_free(entrance, berth, Dock.RADIUS), "Whole body enters platform")
        var id: int = sim.add_unit(1, "mobile_infantry", entrance)
        sim.units[id].auto = false
        ids.append(id)
    var before: int = sim.money[1]
    check(sim.command(1, {"action": "produce", "building": station, "type": "harvester"}).is_empty(), "Production accepts a blocked exit")
    for tick in range(Sim.UNIT_TYPES.harvester.time + 20):
        sim.step()
    check(b.queue.size() == 1 and b.queue[0].remaining == 0 and sim.units.size() == Catalog.REFINERY_DOCK_RECTS.size(), "Completed job waits without remote spawning")
    check(sim.money[1] == before - Sim.UNIT_TYPES.harvester.cost, "Blocked job charged once")
    var mirror = fixture()
    check(mirror.apply_snapshot(sim.snapshot()), "Blocked production snapshot accepted")
    # Allocation is host-only and intentionally absent from guest snapshots.
    # Give this second authoritative test runner the same allocation context.
    mirror.next_id = sim.next_id
    sim.units.erase(ids[0])
    mirror.units.erase(ids[0])
    sim.step()
    mirror.step()
    check(b.queue.is_empty() and sim.units.size() == Catalog.REFINERY_DOCK_RECTS.size(), "Freed exit produces exactly one unit")
    var produced: Dictionary = sim.units[sim.next_id - 1]
    check(produced.pos == Dock.entrance(b, 0), "Birth uses front model boundary plus body clearance")
    check(sim.snapshot() == mirror.snapshot(), "Production resumes identically after snapshot")
    check(sim.money[1] == before - Sim.UNIT_TYPES.harvester.cost, "Retry never charges twice")
    sim.units.clear()
    for slot in range(Catalog.REFINERY_DOCK_RECTS.size()):
        var id: int = sim.add_unit(1, "harvester", b.pos + Vector2(-200 + slot * 400, -200))
        var u: Dictionary = sim.units[id]
        u.order = "gather"
        u.cargo = 60
        Dock.request(sim, u, station, sim.frame)
        u.dock.slot = slot
        u.dock.phase = "approach"
        Dock.destination(u, Dock.entrance(b, slot))
    check(sim._spawn_position(b, "harvester") == Dock.entrance(b, 0), "Approaching harvesters do not block production")
    sim.units.clear()
    sim._add_building(1, "barracks", b.pos + Vector2(0, -112), true)
    sim.rebuild_navigation()
    check(sim._spawn_position(b, "harvester") == Vector2.ZERO, "Adjacent solid blocks production exits")
    sim.buildings.erase(sim.next_id - 1)
    b.pos = Vector2(64, 64)
    sim.rebuild_navigation()
    check(sim._spawn_position(b, "harvester") == Vector2.ZERO, "Map edge cannot spawn outside world")
    b.pos = Vector2(1600, 1600)
    sim.obstacles.append(Rect2(Dock.entrance(b, 0) - Vector2(20, 20), Vector2(40, 40)))
    sim.rebuild_navigation()
    check(sim._spawn_position(b, "harvester") == Vector2.ZERO, "Terrain bodies block both production exits")


func model_fit() -> void:
    var visual := EntityVisual.new("harvester")
    root.add_child(visual)
    var unit := {"cargo": 60, "work": 0}
    var max_extent := 0.0
    for state in ["idle", "move"]:
        visual.set_animation(state)
        for frame in range(12):
            visual.harvester_motion.sample(unit, 0.05, null)
            var extent := 0.0
            for mesh: MeshInstance3D in visual.model.find_children("*", "MeshInstance3D", true, false):
                for surface in range(mesh.mesh.get_surface_count()):
                    var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
                    for vertex in vertices:
                        var point := mesh.global_transform * vertex
                        extent = maxf(extent, Vector2(point.x, point.z).length())
            max_extent = maxf(max_extent, extent)
            check(extent <= Dock.RADIUS, "Animated folded model stays inside circular collision")
    print("HARVESTER_ENVELOPE source_radius=", max_extent / Catalog.HARVESTER_MODEL_SCALE, " diameter_cells=", max_extent * 2 / Sim.CELL)
    check(max_extent * 2 / Sim.CELL > 1.75 and max_extent <= Catalog.HARVESTER_VISUAL_RADIUS, "Actual folded mesh envelope is approximately 1.8 cells")
    check(visual.get_model_height() == Catalog.HARVESTER_HEIGHT, "Height derives from visual scale")
    var sim = fixture()
    var station: Dictionary = sim.buildings[sim.next_id - 1]
    var sync = preload("res://scripts/presentation/unit_visual_sync.gd")
    for slot in range(Catalog.REFINERY_DOCK_RECTS.size()):
        var point := Dock.berth(station, slot)
        var support: float = sync._harvester_deck_offset(sim, point)
        check(support == Catalog.REFINERY_DECK_HEIGHT, "Platform raises the small hovering body above the deck")
        visual.set_position_2d(point, support)
        visual.harvester_motion.sample(unit, 0, sim.terrain)
        var lowest := INF
        for mesh: MeshInstance3D in visual.model.find_children("*", "MeshInstance3D", true, false):
            lowest = minf(lowest, (mesh.global_transform * mesh.get_aabb()).position.y)
        check(lowest >= Catalog.REFINERY_DECK_HEIGHT, "Docked model does not intersect the platform floor")
    check(sync._harvester_deck_offset(sim, station.pos + Vector2(0, -300)) == 0, "Ordinary ground keeps normal hover altitude")
    visual.queue_free()


func off_center_entry() -> void:
    for offset in [Vector2(2.7, 0), Vector2(-2.7, 0), Vector2(2.5, -2.5)]:
        var sim = fixture()
        var station: int = sim.next_id - 1
        var b: Dictionary = sim.buildings[station]
        var id: int = sim.add_unit(1, "harvester", Dock.entrance(b, 0) + offset)
        var u: Dictionary = sim.units[id]
        u.order = "gather"
        u.cargo = Rules.CAPACITY
        Dock.request(sim, u, station, sim.frame)
        u.dock.slot = 0
        u.dock.phase = "approach"
        Dock.destination(u, Dock.entrance(b, 0))
        var before: int = sim.money[1]
        for tick in range(100):
            Dock.advance(sim, u)
            check(sim.position_free(u.pos, Dock.RADIUS), "Off-center arrival retains wall clearance")
            if u.cargo == 0:
                break
        check(u.cargo == 0 and sim.money[1] == before + Rules.CAPACITY, "Off-center vehicle aligns before entering narrow dock")


func run() -> void:
    geometry()
    production()
    off_center_entry()
    model_fit()
    await process_frame
    print("COMPACT_DEPOT ", JSON.stringify({"checks": checks, "failures": failures}))
    quit(0 if failures.is_empty() else 1)
