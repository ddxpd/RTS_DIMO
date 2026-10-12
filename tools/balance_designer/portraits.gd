extends SceneTree
const Visual = preload("res://assets/art/entity_visual.gd")


func _initialize() -> void:
    capture.call_deferred()


func capture() -> void:
    root.size = Vector2i(780, 600)
    root.content_scale_size = Vector2i(780, 600)
    var stage := Node3D.new()
    root.add_child(stage)
    var world := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color("#dae5df")
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("#d7e7ec")
    environment.ambient_light_energy = 0.5
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    environment.tonemap_white = 6.0
    environment.glow_enabled = true
    environment.glow_intensity = 0.28
    environment.ssao_enabled = true
    environment.ssao_radius = 4.0
    world.environment = environment
    stage.add_child(world)
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-48, -25, 0)
    light.light_energy = 1.0
    light.shadow_enabled = true
    light.directional_shadow_max_distance = 2000
    stage.add_child(light)
    var fill := DirectionalLight3D.new()
    fill.rotation_degrees = Vector3(-20, 150, 0)
    fill.light_energy = 0.3
    stage.add_child(fill)
    var floor_mesh := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(6000, 6000)
    floor_mesh.mesh = plane
    var material := StandardMaterial3D.new()
    material.albedo_color = Color("#b5c5bb")
    material.roughness = 0.96
    floor_mesh.material_override = material
    floor_mesh.position.y = -1
    stage.add_child(floor_mesh)
    var camera := Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.far = 8000
    stage.add_child(camera)
    camera.current = true
    var folder := "res://assets/concept_art/balance_designer"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
    for kind: String in ["soldier", "mobile_infantry", "harvester", "base", "barracks", "refinery", "bunker"]:
        var visual := Visual.new(kind, 1)
        stage.add_child(visual)
        if visual.model.has_method("set_lod"):
            visual.model.set_lod(0)
        visual.set_heading(Vector2.DOWN if kind in ["soldier", "mobile_infantry"] else Vector2.UP, true)
        for frame in range(6):
            await process_frame
        var bounds := AABB()
        var first := true
        for node in visual.find_children("*", "MeshInstance3D", true, false):
            var mesh := node as MeshInstance3D
            if mesh.mesh == null or not mesh.is_visible_in_tree():
                continue
            var box: AABB = mesh.global_transform * mesh.get_aabb()
            bounds = box if first else bounds.merge(box)
            first = false
        var center := bounds.get_center()
        var span := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
        camera.size = span * 1.35
        camera.position = center + Vector3(0.95, 0.85, 1.4).normalized() * span * 3.0
        if kind not in ["soldier", "mobile_infantry"]:
            camera.position = center + Vector3(0.95, 0.85, -1.4).normalized() * span * 3.0
        camera.look_at(center)
        for frame in range(5):
            await process_frame
        await RenderingServer.frame_post_draw
        var result := root.get_texture().get_image().save_png(folder + "/" + kind + ".png")
        if result != OK:
            push_error("Portrait save failed: " + kind)
            quit(1)
            return
        visual.queue_free()
        await process_frame
    stage.queue_free()
    await process_frame
    print("BALANCE_PORTRAITS PASS count=7")
    quit()
