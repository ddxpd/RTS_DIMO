extends "res://tests/barracks_realistic_preview.gd"

const V4_MODEL := "res://assets/concept_art/barracks_underbody_v4/barracks_underbody_v4.glb"


func sample(player: AnimationPlayer, clip: String, time: float) -> void:
    player.play(clip)
    player.seek(time, true)
    player.pause()


func run() -> void:
    root.size = Vector2i(1440, 960)
    root.msaa_3d = Viewport.MSAA_4X
    var world := Node3D.new()
    root.add_child(world)
    var study := load_study(V4_MODEL)
    if study == null:
        quit(1)
        return
    world.add_child(study)
    var players := study.find_children("*", "AnimationPlayer", true, false)
    check(not players.is_empty(), "Missing animation player")
    if players.is_empty():
        quit(1)
        return
    var player := players[0] as AnimationPlayer
    print("V4_CLIPS ", player.get_animation_list())
    for clip in ["Takeoff", "Landing", "Flag_Wind_Loop"]:
        check(player.has_animation(clip), "Missing clip: " + clip)
    if not failures.is_empty():
        quit(1)
        return
    print("V4_DURATIONS ", player.get_animation("Takeoff").length, " ", player.get_animation("Landing").length)
    check(is_equal_approx(player.get_animation("Takeoff").length, 4.0), "Takeoff duration")
    check(is_equal_approx(player.get_animation("Landing").length, 4.0), "Landing duration")
    check(is_equal_approx(player.get_animation("Flag_Wind_Loop").length, 2.0), "Flag duration")
    var hull := study.find_child("BarracksMechanicalV2", true, false) as Node3D
    if hull == null and study.name == "BarracksMechanicalV2":
        hull = study
    var foot := study.find_child("FootLFront", true, false) as Node3D
    var leg := study.find_child("LegLFront", true, false) as Node3D
    var ramp := study.find_child("Ramp", true, false) as Node3D
    var flag := study.find_child("BarracksFlag", true, false) as MeshInstance3D
    check(hull != null and foot != null and leg != null and ramp != null and flag != null, "Missing mechanical hierarchy")
    if not failures.is_empty():
        quit(1)
        return
    sample(player, "Takeoff", 0)
    var initial_foot := foot.position
    var initial_ramp := ramp.rotation
    var initial_leg := leg.quaternion
    check(absf(hull.position.y) < 0.01, "Takeoff starts on ground")
    sample(player, "Takeoff", 1.5)
    check(hull.position.y > 0.3, "Body must rise before leg retraction")
    check(foot.position.distance_to(initial_foot) < 0.01, "Leg retracted before clearance")
    check(ramp.rotation.distance_to(initial_ramp) > 1.0, "Ramp did not close")
    sample(player, "Takeoff", 4)
    check(absf(hull.position.y - 3.0) < 0.01, "Takeoff height incorrect")
    check(foot.position.y > 0.4 and foot.position.y < 0.9, "Foot not stored inside chassis")
    check(absf(foot.position.x) < 3.8, "Foot did not fold inward")
    check(leg.quaternion.angle_to(initial_leg) > 2.0, "Leg arm did not rotate")
    sample(player, "Landing", 0)
    check(absf(hull.position.y - 3.0) < 0.01, "Landing starts airborne")
    sample(player, "Landing", 2.5)
    check(hull.position.y > 0.3, "Landing support must extend before touchdown")
    check(foot.position.distance_to(initial_foot) < 0.01, "Landing gear did not extend")
    sample(player, "Landing", 4)
    check(absf(hull.position.y) < 0.01, "Landing did not reach ground")
    check(ramp.rotation.distance_to(initial_ramp) < 0.01, "Landing did not reopen ramp")

    # A separate player demonstrates that flag movement stays independent of flight state.
    var wind := AnimationPlayer.new()
    player.get_parent().add_child(wind)
    wind.root_node = player.root_node
    var library := AnimationLibrary.new()
    var wind_clip := player.get_animation("Flag_Wind_Loop").duplicate() as Animation
    wind_clip.loop_mode = Animation.LOOP_LINEAR
    library.add_animation("Flag_Wind_Loop", wind_clip)
    wind.add_animation_library("", library)
    sample(wind, "Flag_Wind_Loop", 0)
    var initial_flag := flag.get_blend_shape_value(0)
    sample(wind, "Flag_Wind_Loop", 0.5)
    check(absf(flag.get_blend_shape_value(0) - initial_flag) > 0.1, "Flag morph is not animated")
    check(absf(hull.position.y) < 0.01, "Flag clip changes building height")
    wind.play("Flag_Wind_Loop")
    var textured_surfaces := 0
    for node in study.find_children("*", "MeshInstance3D", true, false):
        var mesh := node as MeshInstance3D
        for surface in range(mesh.mesh.get_surface_count()):
            var mat := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
            if mat != null and mat.get_texture(BaseMaterial3D.TEXTURE_ALBEDO) != null:
                textured_surfaces += 1
                check(mat.get_texture(BaseMaterial3D.TEXTURE_NORMAL) != null, "Missing normal map")
    check(textured_surfaces >= 20, "Missing embedded materials")

    var ground := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(200, 200)
    ground.mesh = plane
    ground.position.y = -0.04
    var floor_mat := StandardMaterial3D.new()
    floor_mat.albedo_color = Color(0.22, 0.25, 0.28)
    floor_mat.roughness = 0.9
    ground.material_override = floor_mat
    world.add_child(ground)
    var sun := DirectionalLight3D.new()
    sun.rotation = Vector3(-0.85, -0.65, 0)
    sun.light_color = Color(1, 0.94, 0.85)
    sun.light_energy = 0.65
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 70
    world.add_child(sun)
    var fill := DirectionalLight3D.new()
    fill.position = Vector3(-12, 8, -16)
    fill.light_energy = 0.25
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
    var sky_mat := ProceduralSkyMaterial.new()
    sky_mat.sky_energy_multiplier = 0.6
    sky_mat.ground_energy_multiplier = 0.6
    sky.sky_material = sky_mat
    environment.sky = sky
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    var env := WorldEnvironment.new()
    env.environment = environment
    world.add_child(env)
    var camera := Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 15
    camera.position = Vector3(-12, 10, -16)
    world.add_child(camera)
    camera.look_at(Vector3(0, 3.55, 0))
    camera.current = true
    sample(player, "Takeoff", 0)
    await capture("barracks-v4-godot-landed")
    sample(player, "Takeoff", 2.2)
    camera.look_at(Vector3(0, 4.7, 0))
    await capture("barracks-v4-godot-transition")
    sample(player, "Takeoff", 4)
    camera.position = Vector3(-12, 5, -16)
    camera.look_at(Vector3(0, 5.1, 0))
    await capture("barracks-v4-godot-airborne")
    print("BARRACKS_UNDERBODY_GODOT ", "PASS" if failures.is_empty() else "FAIL",
        " textured_surfaces=", textured_surfaces, " failures=", failures)
    world.queue_free()
    await process_frame
    quit(0 if failures.is_empty() else 1)
