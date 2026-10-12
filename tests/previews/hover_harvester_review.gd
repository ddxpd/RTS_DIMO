extends SceneTree

const OUT := "res://assets/concept_art/hover_harvester/"
var stage: Node3D
var camera: Camera3D
var vehicle: EntityVisual
var failures: Array[String] = []
var stats: Dictionary = {}


func _initialize() -> void:
    run.call_deferred()
    create_timer(120).timeout.connect(func(): quit(1))


func capture(name: String) -> void:
    for i in range(12):
        await process_frame
    await RenderingServer.frame_post_draw
    if root.get_texture().get_image().save_png(OUT + name + ".png") != OK:
        failures.append("capture " + name)


func run() -> void:
    root.size = Vector2i(1500, 1000)
    root.msaa_3d = Viewport.MSAA_4X
    stage = Node3D.new()
    root.add_child(stage)
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color("#dce3eb")
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color("#cbd6e8")
    environment.environment.ambient_light_energy = 0.4
    environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    environment.environment.glow_enabled = true
    environment.environment.glow_intensity = 0.35
    var sky := Sky.new()
    var sky_material := ProceduralSkyMaterial.new()
    sky_material.sky_top_color = Color("#9eb4d1")
    sky_material.sky_horizon_color = Color("#e8eef6")
    sky_material.ground_bottom_color = Color("#596471")
    sky_material.ground_horizon_color = Color("#bec9d6")
    sky.sky_material = sky_material
    environment.environment.sky = sky
    environment.environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    stage.add_child(environment)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48, -35, 0)
    sun.light_energy = 0.9
    sun.shadow_enabled = true
    stage.add_child(sun)
    var fill := DirectionalLight3D.new()
    fill.rotation_degrees = Vector3(-32, 140, 0)
    fill.light_energy = 0.25
    fill.light_color = Color("#c5ddff")
    stage.add_child(fill)
    var floor_mesh := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(1500, 1500)
    floor_mesh.mesh = plane
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color("#d0d6dd")
    mat.roughness = 0.92
    floor_mesh.material_override = mat
    stage.add_child(floor_mesh)
    vehicle = EntityVisual.new("harvester", 1)
    stage.add_child(vehicle)
    camera = Camera3D.new()
    camera.fov = 33
    stage.add_child(camera)
    camera.position = Vector3(60, 50, -72)
    camera.look_at(Vector3(0, 16, 0))
    camera.current = true
    vehicle.harvester_motion.sample({"cargo": 60, "work": 0}, 0, null)
    await capture("01-front-full")
    camera.position = Vector3(-60, 50, 72)
    camera.look_at(Vector3(0, 17, 0))
    await capture("02-rear-full")
    camera.position = Vector3(60, 50, -72)
    camera.look_at(Vector3(0, 16, 0))
    for amount in [0, 10, 30, 60]:
        vehicle.harvester_motion.sample({"cargo": amount, "work": 0}, 0, null)
        await capture("03-cargo-%02d" % amount)
    vehicle.set_animation("mine")
    for tick in [0, 5, 10, 15]:
        vehicle.harvester_motion.sample({"cargo": 30, "work": tick}, 0, null)
        await capture("04-mining-%02d" % tick)
    # Genuine game light, map and camera; current runtime assets together.
    stage.queue_free()
    await process_frame
    var game: Node3D = load("res://scenes/main.tscn").instantiate()
    game.selected_map_id = "desert_quarry"
    root.add_child(game)
    game.play_solo()
    game.set_process(false)
    game.set_process_input(false)
    game.set_process_unhandled_input(false)
    game.sim.ai_enabled = false
    game.local_slot = 0
    game._sync_map_world()
    var ore_id: int = game.sim.ores.keys()[0]
    var point: Vector2 = game.sim.ores[ore_id].pos
    var uid: int = game.sim.add_unit(1, "harvester", point + Vector2(0, 44))
    var unit: Dictionary = game.sim.units[uid]
    unit.order = "gather"
    unit.ore = ore_id
    unit.cargo = 30
    unit.work = 5
    game._sync_visuals()
    var visual: EntityVisual = game.unit_visuals[uid].visual
    visual.set_heading(Vector2(0, -1), true)
    visual.harvester_motion.sample(unit, 0, game.sim.terrain)
    if game.unit_visuals[uid].has("cargo_bar"):
        game.unit_visuals[uid].cargo_bar.hide()
    for child in game.get_children():
        if child is CanvasLayer:
            child.hide()
    var focus := Vector3(point.x, game.sim.terrain.height_at(point) + 24, point.y + 12)
    game.camera.position = focus + Vector3(105, 90, 145)
    game.camera.look_at(focus)
    await capture("05-game-mining-detail")
    game.camera_controller.focus = point
    game.camera_zoom_level = 2.0
    game._update_camera_transform()
    await capture("06-game-close")
    game.camera_zoom_level = 1.0
    game._update_camera_transform()
    await capture("07-game-normal")
    stats.renderer = RenderingServer.get_current_rendering_method()
    stats.adapter = RenderingServer.get_video_adapter_name()
    stats.failures = failures
    print("HOVER_HARVESTER_REVIEW ", JSON.stringify(stats))
    game.queue_free()
    await process_frame
    quit(0 if failures.is_empty() else 1)
