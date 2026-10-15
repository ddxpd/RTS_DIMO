extends SceneTree
const Visual = preload("res://assets/art/entity_visual.gd")

class Floor:
    var slope := 0.0
    func height_at(point: Vector2) -> float:
        return point.y * slope

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    root.size = Vector2i(1200, 900)
    var world := Node3D.new()
    root.add_child(world)
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color("a5a8a6")
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color.WHITE
    environment.environment.ambient_light_energy = 0.65
    world.add_child(environment)
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-55, -30, 0)
    light.shadow_enabled = true
    world.add_child(light)
    var ground := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(2000, 2000)
    ground.mesh = plane
    var material := StandardMaterial3D.new()
    material.albedo_color = Color("b6a88b")
    ground.material_override = material
    world.add_child(ground)
    var camera := Camera3D.new()
    world.add_child(camera)
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 85
    camera.current = true
    var folder := "res://assets/concept_art/mobile_infantry/motion_review/"
    DirAccess.make_dir_recursive_absolute(folder)
    var prefix := "before" if "--before" in OS.get_cmdline_args() else "after"
    for action: String in ["idle", "walk", "jog", "fire", "stop_turn", "uphill", "rts"]:
        var actor := Visual.new("mobile_infantry", 1)
        world.add_child(actor)
        actor.set_process(false)
        var floor := Floor.new()
        floor.slope = 0.35 if action == "uphill" else 0.0
        ground.rotation.x = -atan(floor.slope)
        camera.size = 250 if action == "rts" else 85
        actor.set_animation("attack" if action == "fire" else "move" if action in ["walk", "jog"] else "idle")
        var speed := 30.0 if action == "walk" else 100.0 if action == "jog" else 70.0 if action in ["stop_turn", "uphill", "rts"] else 0.0
        for frame in range(150):
            var travel_frame := mini(frame, 60) if action == "stop_turn" else frame
            var aim := Vector2(-100, 0) if action == "stop_turn" and frame > 75 else Vector2(0, 100)
            actor.mobile_motion.sample({"pos": Vector2(0, speed * travel_frame / 60.0), "cooldown": 5 if action == "fire" else 0}, 1.0 / 60.0, frame / 3, floor, aim)
            camera.position = actor.position + Vector3(90, 90, 125)
            camera.look_at(actor.position + Vector3(0, 23, 0))
            await process_frame
            if frame in [90, 105, 120, 135]:
                await RenderingServer.frame_post_draw
                root.get_texture().get_image().save_png(folder + "%s_%s_%d.png" % [prefix, action, frame])
        actor.free()
    world.free()
    print("MOBILE_MOTION_REVIEW ", prefix)
    quit()
