extends SceneTree
## Captures actual EntityVisual animation poses; invoke run-godot.ps1 -Rendered.

const OUTPUT := "res://assets/concept_art/base_animation"
var visual: EntityVisual


func _initialize() -> void:
    run.call_deferred()


func capture(filename: String) -> void:
    await process_frame
    await RenderingServer.frame_post_draw
    var result := root.get_texture().get_image().save_png(OUTPUT.path_join(filename))
    assert(result == OK, "Could not save base preview")


func run() -> void:
    if DisplayServer.get_name() == "headless":
        push_error("Base preview requires run-godot.ps1 -Rendered")
        quit(1)
        return
    root.size = Vector2i(900, 720)
    root.content_scale_size = Vector2i(900, 720)
    root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
    root.msaa_3d = Viewport.MSAA_4X
    DisplayServer.window_set_size(root.size)
    var scene := Node3D.new()
    root.add_child(scene)
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color("#393d45")
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color("#c4cfdf")
    environment.environment.ambient_light_energy = 0.65
    scene.add_child(environment)
    var key := DirectionalLight3D.new()
    key.rotation_degrees = Vector3(-55, -35, 0)
    key.light_energy = 1.15
    key.shadow_enabled = true
    scene.add_child(key)
    var ground := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(800, 800)
    ground.mesh = plane
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color("#666872")
    ground.material_override = mat
    ground.position.y = -0.1
    scene.add_child(ground)
    var camera := Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 245
    scene.add_child(camera)
    camera.position = Vector3(-190, 210, -280)
    camera.look_at(Vector3(0, 35, 0))
    visual = EntityVisual.new("base", 1)
    scene.add_child(visual)
    visual.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
    visual.set_construction_tint(true)
    visual.set_animation("construction")
    # Evenly sampled progress makes the offline flipbook match real build timing.
    for frame in range(36):
        visual.set_construction_progress(float(frame) / 35.0, 7.0)
        await capture("build-%02d.png" % frame)
    visual.set_construction_tint(false)
    visual.set_animation("idle")
    for frame in range(24):
        visual.animation_player.seek(float(frame) * 0.1, true)
        await capture("scan-%02d.png" % frame)
    visual.set_faction(2)
    visual.animation_player.seek(0.44, true)
    await capture("red.png")
    print("BASE_PREVIEW saved 61 actual runtime frames to ", OUTPUT)
    scene.queue_free()
    await process_frame
    quit()
