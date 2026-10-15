extends SceneTree
const Destruction = preload("res://assets/art/effects/building_destruction.gd")
const Gaia = preload("res://assets/art/buildings/gaia/gaia_command_base.tscn")


func _initialize() -> void:
    run.call_deferred()


func run() -> void:
    root.size = Vector2i(1440, 900)
    var world := Node3D.new()
    root.add_child(world)
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color(0.12, 0.16, 0.2)
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color(0.7, 0.8, 1.0)
    environment.environment.ambient_light_energy = 0.65
    environment.environment.glow_enabled = true
    world.add_child(environment)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-55, -25, 0)
    sun.light_energy = 1.8
    world.add_child(sun)
    var camera := Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 1050
    world.add_child(camera)
    camera.position = Vector3(250, 800, 1100)
    camera.look_at(Vector3(0, 60, 0))
    camera.current = true
    var effects: Array[Node3D] = []
    for i in range(3):
        var kind: String = ["base", "barracks", "refinery"][i]
        var effect := Destruction.new()
        world.add_child(effect)
        effect.configure({"owner": 1, "frame": 10, "to": Vector2(-330 + i * 330, 0), "destruction": {"id": i + 1, "type": kind, "height": 70.0 if i == 0 else 0.0, "heading": 0.0}}, 0)
        effects.append(effect)
    var folder := "res://assets/concept_art/building_lifecycle"
    DirAccess.make_dir_recursive_absolute(folder)
    for age: float in [0.15, 1.2, 3.8]:
        for effect in effects:
            effect.advance(age, 0)
        await process_frame
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png(folder + "/destruction_%.2f.png" % age)
    for effect in effects:
        effect.free()
    var base: GaiaCommandBase = Gaia.instantiate()
    world.add_child(base)
    base.automatic_animation = false
    camera.size = 580
    camera.position = Vector3(400, 400, 600)
    camera.look_at(Vector3(0, 110, 0))
    for phase: String in ["taking_off", "airborne", "landing"]:
        base.position.y = 120 if phase == "airborne" else 60
        base.apply_flight({"state": phase, "ticks": 60 if phase != "airborne" else 0, "moving": phase == "airborne"}, 1.0, phase == "airborne")
        await process_frame
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png(folder + "/base_" + phase + ".png")
    world.free()
    print("BUILDING_LIFECYCLE_PREVIEW PASS")
    quit()
