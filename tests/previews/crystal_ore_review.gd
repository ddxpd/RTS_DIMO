extends SceneTree
## Real Forward+ frames, deposit visibility/footprint checks, and isolated render scaling.

const OUT := "res://assets/concept_art/crystal_ore/"
var game: Node3D
var failures: Array[String] = []
var checks := 0
var report: Dictionary = {}


func _initialize() -> void:
    run.call_deferred()
    create_timer(120.0).timeout.connect(func(): quit(1))


func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)


func settle(count: int = 12) -> void:
    for i in range(count):
        await process_frame


func capture(name: String) -> void:
    await settle()
    await RenderingServer.frame_post_draw
    check(root.get_texture().get_image().save_png(OUT + name + ".png") == OK, "capture " + name)


func bounds(visual: Node3D) -> AABB:
    var box := AABB()
    var first := true
    for mesh: MeshInstance3D in visual.model.find_children("*", "MeshInstance3D", true, false):
        var next := visual.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
        box = next if first else box.merge(next)
        first = false
    return box


func run() -> void:
    root.size = Vector2i(1600, 1000)
    root.content_scale_size = Vector2i(1600, 1000)
    root.msaa_3d = Viewport.MSAA_4X
    report.renderer = RenderingServer.get_current_rendering_method()
    report.adapter = RenderingServer.get_video_adapter_name()
    check(report.renderer == "forward_plus", "Forward+ is active on actual GPU")
    game = load("res://scenes/main.tscn").instantiate()
    game.selected_map_id = "desert_quarry"
    root.add_child(game)
    game.play_solo()
    game.set_process(false)
    game.set_process_input(false)
    game.set_process_unhandled_input(false)
    game.sim.ai_enabled = false
    game.local_slot = 0
    game._sync_map_world()
    game._sync_visuals()
    for child in game.get_children():
        if child is CanvasLayer:
            child.hide()
    await settle()
    var ore_id: int = game.sim.ores.keys()[0]
    var point: Vector2 = game.sim.ores[ore_id].pos
    var visual: Node3D = game.ore_visuals[ore_id].visual
    var box := bounds(visual)
    report.bounds = {"size": str(box.size), "min": str(box.position), "max": str(box.end)}
    check(box.size.x <= 76 and box.size.z <= 76, "cluster stays in original mining footprint")
    check(box.end.y <= visual.get_model_height(), "resource label clears highest crystal")
    var cluster: MeshInstance3D = visual.model.find_child("CrystalCluster", true, false)
    var shared_crystal: Material = cluster.material_override
    check(cluster != null and cluster.get_active_material(0) is ShaderMaterial, "runtime fracture shader attached")
    var rocks: MeshInstance3D = visual.model.find_child("FracturedRockBed", true, false)
    var rock_material := rocks.get_active_material(0) as StandardMaterial3D
    check(rock_material != null and rock_material.albedo_texture != null and rock_material.normal_texture != null, "basalt color and normal textures survive engine integration")
    check(visual.model.find_child("OreCrystal_0", true, false) == null, "old crystal geometry removed")
    check(visual.animation_player.get_animation("idle").get_track_count() == 0, "rigid crystal idle has no scale tracks")
    var light: OmniLight3D = visual.get_node("MineralBounceLight")
    check(light.is_visible_in_tree(), "visible deposit has blue light")
    var amount: int = game.sim.ores[ore_id].amount
    game.sim.ores[ore_id].amount = 0
    game._sync_ores()
    check(not visual.is_visible_in_tree() and not light.is_visible_in_tree(), "depletion hides crystal and light together")
    game.sim.ores[ore_id].amount = amount
    game.local_slot = 1
    var saved_visible: PackedByteArray = game.sim.visible[1].duplicate()
    game.sim.visible[1].fill(0)
    game._sync_ores()
    check(not visual.is_visible_in_tree() and not light.is_visible_in_tree(), "fog hides crystal and light together")
    game.sim.visible[1] = saved_visible
    game.local_slot = 0
    game._sync_ores()
    game.camera_controller.focus = point
    game.camera_zoom_level = 1.0
    game._update_camera_transform()
    await capture("01-game-normal")
    game.camera_zoom_level = 2.0
    game._update_camera_transform()
    await capture("02-game-close")
    # Detail camera is explicitly an asset inspection view, beyond normal zoom.
    var focus := visual.global_position + Vector3(0, 34, 0)
    game.camera.position = focus + Vector3(115, 95, 155)
    game.camera.look_at(focus)
    await capture("03-detail-front")
    game.camera.position = focus + Vector3(-120, 80, -145)
    game.camera.look_at(focus)
    await capture("04-detail-back")
    # Test sample-map material path as well, without exercising harvester movement.
    game.return_to_title()
    game.selected_map_id = "desert_sample"
    game.play_solo()
    game.set_process(false)
    game.local_slot = 0
    game._sync_map_world()
    game._sync_visuals()
    for entry: Dictionary in game.ore_visuals.values():
        var m: MeshInstance3D = entry.visual.model.find_child("CrystalCluster", true, false)
        check(m.get_active_material(0) == shared_crystal, "both maps share crystal material")
    for child in game.get_children():
        if child is CanvasLayer:
            child.hide()
    game.camera_controller.focus = Vector2(2320, 2180)
    game.camera_zoom_level = 1.0
    game._update_camera_transform()
    await capture("05-forward-plus-sample")
    await render_scaling()
    report.checks = checks
    report.failures = failures
    report.harvester_interaction = "deferred by user until new harvester"
    var file := FileAccess.open(OUT + "runtime-report.json", FileAccess.WRITE)
    file.store_string(JSON.stringify(report, "  "))
    print("CRYSTAL_ORE_REVIEW ", JSON.stringify(report))
    game.queue_free()
    await process_frame
    quit(0 if failures.is_empty() else 1)


func render_scaling() -> void:
    # Measure a separate representative 1/24-deposit view; warm shader pipelines first.
    game.hide()
    var stage := Node3D.new()
    root.add_child(stage)
    var env := WorldEnvironment.new()
    env.environment = game.get_node("BattlefieldEnvironment").environment.duplicate()
    stage.add_child(env)
    var floor_mesh := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(720, 540)
    floor_mesh.mesh = plane
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color("#716552")
    mat.roughness = 0.92
    floor_mesh.material_override = mat
    stage.add_child(floor_mesh)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-52, -30, 0)
    sun.light_energy = 0.85
    stage.add_child(sun)
    var camera := Camera3D.new()
    stage.add_child(camera)
    camera.position = Vector3(420, 500, 550)
    camera.look_at(Vector3.ZERO)
    camera.current = true
    var deposits: Array[Node3D] = []
    for i in range(24):
        var ore := EntityVisual.new("ore")
        ore.position = Vector3((i % 6 - 2.5) * 98, 0, (i / 6 - 1.5) * 110)
        stage.add_child(ore)
        deposits.append(ore)
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    Engine.max_fps = 0
    RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
    var measurements: Array[Dictionary] = []
    for count in [0, 1, 24]:
        for i in range(24):
            deposits[i].visible = i < count
        await settle(45)
        var times: Array[float] = []
        var gpu: Array[float] = []
        for frame in range(90):
            var start := Time.get_ticks_usec()
            await process_frame
            times.append((Time.get_ticks_usec() - start) / 1000.0)
            gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
        times.sort()
        gpu.sort()
        measurements.append({"deposits": count, "frame_median_ms": times[45], "frame_p95_ms": times[85], "gpu_median_ms": gpu[45], "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
    report.render_scaling = measurements
    report.render_scaling_resolution = "1600x1000, 4x MSAA, no vsync; isolated deposits, not full match/minimum hardware"
    await capture("06-cluster-field")
    for i in range(24):
        deposits[i].visible = i == 0
    deposits[0].position = Vector3.ZERO
    env.environment.background_color = Color("#151c28")
    env.environment.ambient_light_energy = 0.3
    camera.environment = env.environment
    camera.fov = 35.0
    mat.albedo_color = Color("#282d35")
    camera.position = Vector3(105, 88, 145)
    camera.look_at(Vector3(0, 34, 0))
    await capture("07-godot-asset-preview")
    stage.queue_free()
