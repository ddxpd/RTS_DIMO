extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
const Flight = Sim.BarracksFlight
const Volumes = Flight.AirVolumes
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


func flyer(sim, pos: Vector2) -> int:
    var id: int = sim._add_building(1, "barracks", pos, true)
    var b: Dictionary = sim.buildings[id]
    b.flight.state = "airborne"
    b.flight.height = 144.0
    Flight.refresh_cruise(sim, b)
    return id


func passage(offset: float) -> void:
    var sim = fixture()
    var origin := Vector2(1600, 1600)
    sim._add_building(1, "base", origin, true)
    var id := flyer(sim, origin + Vector2(offset, -350))
    var b: Dictionary = sim.buildings[id]
    var target := origin + Vector2(offset, 350)
    check(sim.command(1, {"action": "building_move", "building": id, "pos": target}).is_empty(), "Crossing command accepted")
    var mirror = fixture()
    check(mirror.apply_snapshot(sim.snapshot()), "Compound body snapshot accepted")
    var detour := 0.0
    for tick in range(900):
        sim.step()
        mirror.step()
        detour = maxf(detour, absf(b.pos.x - origin.x - offset))
        check(Flight.air_clear(sim, id, b.pos, b.flight.height), "Crossing remains collision free")
        check(b.pos == mirror.buildings[id].pos and b.flight == mirror.buildings[id].flight, "Compound route snapshot continuation matches")
        if not b.flight.moving:
            break
    print("AIR_ROUTE ", offset, " ", b.pos, " ", b.flight.error, " detour=", detour)
    check(b.pos.distance_to(target) < 0.01, "Crossing reaches destination " + str(offset))
    check(b.flight.height == 144, "Crossing retains default terrain-relative altitude")
    check(detour > 70 if offset == 0 else detour < 0.01, "Only central tower route needs a detour")


func collision_rules() -> void:
    var sim = fixture()
    var origin := Vector2(1600, 1600)
    var base: int = sim._add_building(1, "base", origin, true)
    var id := flyer(sim, origin + Vector2(120, 0))
    check(Flight.air_clear(sim, id, origin + Vector2(120, 0), 144), "Low wing permits overflight")
    check(not Flight.air_clear(sim, id, origin, 144), "Mast blocks central overflight")
    check(Flight.air_clear(sim, id, origin, 164), "Four-unit gap above mast permits passage")
    check(not Flight.air_clear(sim, id, origin, 163.5), "Mast safety gap enforced")
    check(not Flight.air_clear(sim, id, origin + Vector2(120, 0), 80), "Low wing is still solid below its roof")
    var b: Dictionary = sim.buildings[id]
    b.pos = origin + Vector2(90, 0)
    check(Flight.air_clear(sim, id, b.pos, 144), "Narrow starting clearance valid")
    check(not Flight.turn_clear(sim, id, PI / 2), "Intermediate turn cannot sweep a corner into mast")
    var tower: Dictionary = sim.buildings[base]
    tower.flight.state = "airborne"
    tower.flight.height = 144.0
    tower.flight.heading = PI / 2
    Flight.refresh_cruise(sim, tower)
    check(Flight.air_clear(sim, id, origin + Vector2(200, 0), 144), "Rotated hull vacates former long-axis extent")
    check(not Flight.air_clear(sim, id, origin + Vector2(0, 160), 144), "Rotated long hull occupies new extent")
    check(Volumes.overlaps("barracks", origin, 144, 0, tower, 0) == Volumes.overlaps("base", origin, 144, PI / 2, {"type": "barracks", "pos": origin, "flight": {"height": 144, "heading": 0}}, 0), "Pair collision symmetric")


func model_coverage() -> void:
    var base = preload("res://assets/art/buildings/gaia/gaia_command_base.tscn").instantiate()
    base.automatic_animation = false
    root.add_child(base)
    for level in range(3):
        for phase in [0.0, 2.0, 4.0]:
            base.seek_pose("deployed", phase)
            # Test maximal cruise pitch with the normal authoritative root altitude.
            for pitch in [0.0, deg_to_rad(-2)]:
                base.presentation.rotation.z = pitch
                var outside := 0
                var bounds := AABB()
                for mesh: MeshInstance3D in base.models[level].find_children("*", "MeshInstance3D", true, false):
                    for surface in range(mesh.mesh.get_surface_count()):
                        var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
                        for vertex in vertices:
                            var point := mesh.global_transform * vertex
                            var covered := false
                            for box: AABB in Volumes.BASE:
                                if box.grow(2.0 if pitch != 0 else 0.01).has_point(point):
                                    covered = true
                                    break
                            if not covered:
                                bounds = bounds.expand(point) if outside else AABB(point, Vector3.ZERO)
                                outside += 1
                if outside:
                    print("UNCOVERED ", level, " ", phase, " ", pitch, " ", outside, " ", bounds)
                check(outside == 0, "Model envelope covers LOD " + str(level) + " phase " + str(phase) + " pitch " + str(pitch))
    base.queue_free()


func run() -> void:
    collision_rules()
    passage(128)
    passage(0)
    model_coverage()
    await process_frame
    if DisplayServer.get_name() != "headless":
        await preview()
    print("AIR_VOLUMES ", JSON.stringify({"checks": checks, "failures": failures}))
    quit(0 if failures.is_empty() else 1)


func preview() -> void:
    root.size = Vector2i(1280, 800)
    var world := Node3D.new()
    root.add_child(world)
    var base = preload("res://assets/art/buildings/gaia/gaia_command_base.tscn").instantiate()
    base.automatic_animation = false
    world.add_child(base)
    var barracks := EntityVisual.new("barracks")
    world.add_child(barracks)
    barracks.position = Vector3(128, 144, 0)
    barracks.barracks_motion.apply({"state": "airborne", "ticks": 0})
    var light := DirectionalLight3D.new()
    world.add_child(light)
    light.rotation_degrees = Vector3(-45, -30, 0)
    light.light_energy = 1.4
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color("#172635")
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color("#bacde0")
    environment.environment.ambient_light_energy = 0.7
    world.add_child(environment)
    var camera := Camera3D.new()
    world.add_child(camera)
    camera.position = Vector3(420, 360, 550)
    camera.look_at(Vector3(0, 100, 0))
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 520
    camera.current = true
    var folder := "res://assets/concept_art/building_lifecycle/"
    DirAccess.make_dir_recursive_absolute(folder)
    for overlay in [false, true]:
        if overlay:
            for i in range(Volumes.BASE.size()):
                var box: AABB = Volumes.BASE[i]
                var mesh := MeshInstance3D.new()
                var shape := BoxMesh.new()
                shape.size = box.size
                mesh.mesh = shape
                mesh.position = box.get_center()
                var material := StandardMaterial3D.new()
                material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
                material.albedo_color = Color(0.2, 0.9, 0.65, 0.20) if i == 0 else Color(1, 0.25, 0.12, 0.3)
                material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
                mesh.material_override = material
                world.add_child(mesh)
        for frame in range(4):
            await process_frame
        await RenderingServer.frame_post_draw
        check(root.get_texture().get_image().save_png(folder + ("air_volumes.png" if overlay else "wing_overflight.png")) == OK, "Overflight preview saved")
    world.queue_free()
    await process_frame
