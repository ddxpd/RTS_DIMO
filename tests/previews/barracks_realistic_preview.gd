extends SceneTree

const OUT := "res://assets/concept_art/"
const MODEL := OUT + "barracks_realistic_v3/barracks_mechanical_v2.glb"
var failures: Array[String] = []


func _initialize() -> void:
    run.call_deferred()


func check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
        push_error(message)


func load_study(path: String) -> Node3D:
    var document := GLTFDocument.new()
    var state := GLTFState.new()
    var error := document.append_from_file(path, state)
    check(error == OK, "GLB load failed: " + path)
    if error != OK:
        return null
    return document.generate_scene(state) as Node3D


func capture(name: String) -> void:
    for frame in range(8):
        await process_frame
    await RenderingServer.frame_post_draw
    check(root.get_texture().get_image().save_png(OUT + name + ".png") == OK, "Screenshot save failed")


func run() -> void:
    root.size = Vector2i(1440, 960)
    root.msaa_3d = Viewport.MSAA_4X
    var world := Node3D.new()
    root.add_child(world)
    var study := load_study(MODEL)
    if study == null:
        quit(1)
        return
    world.add_child(study)
    var textured_surfaces := 0
    for node in study.find_children("*", "MeshInstance3D", true, false):
        var mesh := node as MeshInstance3D
        for surface in range(mesh.mesh.get_surface_count()):
            var material := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
            check(material != null, "Missing material")
            if material == null:
                continue
            var texture := material.get_texture(BaseMaterial3D.TEXTURE_ALBEDO)
            if texture != null:
                textured_surfaces += 1
                check(texture.get_width() in [2048, 512], "Unexpected texture size")
                check(material.get_texture(BaseMaterial3D.TEXTURE_NORMAL) != null, "Missing normal texture")
    check(textured_surfaces >= 20, "Too few textured surfaces")
    var players := study.find_children("*", "AnimationPlayer", true, false)
    check(not players.is_empty(), "Missing flag animation player")
    var flag := study.find_child("BarracksFlag", true, false) as MeshInstance3D
    check(flag != null and flag.mesh.get_blend_shape_count() >= 4, "Missing flag morph targets")
    if not players.is_empty() and flag != null:
        var player := players[0] as AnimationPlayer
        var clips := player.get_animation_list()
        check(not clips.is_empty(), "Missing animation clip")
        if not clips.is_empty():
            player.play(clips[0])
            player.seek(0, true)
            var initial := flag.get_blend_shape_value(0)
            player.seek(0.5, true)
            check(absf(flag.get_blend_shape_value(0) - initial) > 0.1, "Flag does not animate in Godot")
            player.get_animation(clips[0]).loop_mode = Animation.LOOP_LINEAR
            player.seek(0.25, true)
    var ground := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(200, 200)
    ground.mesh = plane
    ground.position.y = -0.04
    var floor_material := StandardMaterial3D.new()
    floor_material.albedo_color = Color(0.22, 0.25, 0.28)
    floor_material.roughness = 0.9
    ground.material_override = floor_material
    world.add_child(ground)
    var sun := DirectionalLight3D.new()
    sun.rotation = Vector3(-0.85, -0.65, 0)
    sun.light_color = Color(1, 0.94, 0.85)
    sun.light_energy = 0.55
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 70
    world.add_child(sun)
    var fill := DirectionalLight3D.new()
    fill.position = Vector3(-12, 8, -16)
    fill.light_energy = 0.22
    fill.light_color = Color(0.82, 0.90, 1)
    world.add_child(fill)
    fill.look_at(Vector3(0, 2, 0))
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.13, 0.16, 0.20)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    environment.ambient_light_energy = 0.5
    environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    var sky := Sky.new()
    var sky_material := ProceduralSkyMaterial.new()
    sky_material.sky_energy_multiplier = 0.6
    sky_material.ground_energy_multiplier = 0.6
    sky.sky_material = sky_material
    environment.sky = sky
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    var environment_node := WorldEnvironment.new()
    environment_node.environment = environment
    world.add_child(environment_node)
    var camera := Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 15
    camera.position = Vector3(-12, 11, -16)
    world.add_child(camera)
    camera.look_at(Vector3(0, 3.55, 0))
    camera.current = true
    await capture("兵营模型-轻度写实-Godot近景-v3")
    camera.size = 34
    camera.position = Vector3(-12, 23, -16)
    camera.look_at(Vector3(0, 2, 0))
    await capture("兵营模型-轻度写实-Godot俯视-v3")
    floor_material.albedo_color = Color(0.30, 0.235, 0.16)
    sun.light_color = Color(1, 0.94, 0.83)
    environment.ambient_light_energy = 0.4
    await capture("兵营模型-轻度写实-Godot荒漠俯视-v3")
    study.hide()
    var previous := load_study(OUT + "barracks_mechanical_v2/barracks_mechanical_v2.glb")
    if previous != null:
        world.add_child(previous)
        await capture("兵营模型-轻度写实-Godot升级前-v3")
    print("BARRACKS_REALISTIC_GODOT ", "PASS" if failures.is_empty() else "FAIL", " textured_surfaces=", textured_surfaces,
        " renderer=", RenderingServer.get_current_rendering_method(), " failures=", failures)
    world.queue_free()
    await process_frame
    quit(0 if failures.is_empty() else 1)
