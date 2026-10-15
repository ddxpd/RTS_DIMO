extends "res://tests/simulation/terrain_flight.gd"
const Entity = preload("res://assets/art/entity_visual.gd")
const Sync = preload("res://scripts/presentation/building_visual_sync.gd")


func run() -> void:
    root.size = Vector2i(1440, 900)
    var world := Node3D.new()
    root.add_child(world)
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color(0.08, 0.12, 0.18)
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color(0.7, 0.8, 1.0)
    environment.environment.ambient_light_energy = 0.7
    environment.environment.glow_enabled = true
    environment.environment.glow_intensity = 0.35
    world.add_child(environment)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-55, -35, 0)
    sun.shadow_enabled = true
    world.add_child(sun)
    for spec: Array in [[Vector3(2400, -100, 1600), Vector3(4800, 8, 3200), Color(0.27, 0.24, 0.19)],
            [Vector3(3200, 48, 1600), Vector3(3200, 288, 3200), Color(0.36, 0.32, 0.26)]]:
        var terrain := MeshInstance3D.new()
        var shape := BoxMesh.new()
        shape.size = spec[1]
        terrain.mesh = shape
        terrain.position = spec[0]
        var material := StandardMaterial3D.new()
        material.albedo_color = spec[2]
        terrain.material_override = material
        world.add_child(terrain)
    var camera := Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 1000
    world.add_child(camera)
    camera.position = Vector3(1950, 820, 2650)
    camera.look_at(Vector3(1580, 150, 1408))
    camera.current = true
    var folder := "res://assets/concept_art/building_lifecycle/"
    DirAccess.make_dir_recursive_absolute(folder)
    for kind: String in ["base", "barracks"]:
        var sim = fixture("cliff")
        var id := lift(sim, kind, Vector2(1184, 1408))
        var b: Dictionary = sim.buildings[id]
        var visual := Entity.new(kind)
        world.add_child(visual)
        visual.position = Vector3(b.pos.x, b.flight.height, b.pos.y)
        if kind == "base":
            visual.model.automatic_animation = false
        for returning: bool in [false, true]:
            var destination := Vector2(1184 if returning else 2208, 1408)
            sim.command(1, {"action": "building_move", "building": id, "pos": destination})
            for tick in range(450):
                sim.step()
                for frame in range(3):
                    Sync._sync_flight_pose(visual, b, Vector3(b.pos.x, b.flight.height, b.pos.y), 1.0 / 60.0)
                    if kind == "base":
                        visual.model.apply_flight(b.flight, 1.0 / 60.0, Flight.is_thrusting(b), sim.terrain.height_at)
                    else:
                        visual.barracks_motion.apply(b.flight)
                        visual.barracks_presentation.update(b, 1.0 / 60.0, camera, sim.terrain.height_at)
                    # Independent geometry bound: the cliff begins at x=1600.
                    var half_x: float = sim.BUILD_TYPES[kind].size.x * 0.5
                    if visual.position.x + half_x >= 1600:
                        check(visual.position.y >= 192.0, "Rendered hull clears cliff during interpolated motion")
                    await process_frame
                if tick in [45, 100, 180, 310]:
                    await RenderingServer.frame_post_draw
                    root.get_texture().get_image().save_png(folder + "terrain_flight_%s_%s_%d.png" % [kind, "down" if returning else "up", tick])
                if not b.flight.moving and is_equal_approx(b.flight.height, b.flight.cruise):
                    break
        visual.free()
    world.free()
    print("TERRAIN_FLIGHT_PREVIEW ", JSON.stringify({"checks": checks, "failures": failures}))
    quit(0 if failures.is_empty() else 1)
