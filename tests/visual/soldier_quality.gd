extends SceneTree
const Visual = preload("res://assets/art/entity_visual.gd")
var world: Node3D
var camera: Camera3D
var output := "res://assets/concept_art/soldier_upgrade/"
var version := "before"

class FlatGround:
    func height_at(_point: Vector2) -> float:
        return 0.0


func _initialize() -> void:
    run.call_deferred()


func capture(label: String) -> void:
    for frame in range(4):
        await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(output + version + "-" + label + ".png")


func run() -> void:
    version = "after" if "--after" in OS.get_cmdline_args() else "before"
    var carry_review := "--run-carry" in OS.get_cmdline_args() or "--run-carry-after" in OS.get_cmdline_args()
    if carry_review:
        output = "res://assets/concept_art/soldier_run_carry/"
        version = "after" if "--run-carry-after" in OS.get_cmdline_args() else "before"
    if "--vertical-carry" in OS.get_cmdline_args():
        output = "res://assets/concept_art/soldier_vertical_carry/"
        carry_review = true
        version = "after"
    if "--clear-run" in OS.get_cmdline_args():
        output = "res://assets/concept_art/soldier_clear_run/"
        carry_review = true
        version = "after"
    DirAccess.make_dir_recursive_absolute(output)
    root.size = Vector2i(1280, 900)
    Engine.max_fps = 0
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    world = Node3D.new()
    root.add_child(world)
    camera = Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 100
    world.add_child(camera)
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-45, -35, 0)
    light.shadow_enabled = true
    world.add_child(light)
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color("303941")
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color("b8cde0")
    environment.environment.ambient_light_energy = .7
    world.add_child(environment)
    var floor_mesh := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(3000, 3000)
    floor_mesh.mesh = plane
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color("716959")
    floor_mesh.material_override = mat
    world.add_child(floor_mesh)
    var ground := FlatGround.new()
    var visual := Visual.new("soldier", 1)
    world.add_child(visual)
    for mode: String in ["idle", "move", "attack", "turn-stop"]:
        var position := Vector2.ZERO
        var heading := Vector2.DOWN
        visual.set_heading(heading, true)
        for frame in range(90):
            if mode == "turn-stop" and frame == 30:
                heading = Vector2.LEFT
                visual.set_heading(heading, true)
            var moving := mode == "move" or (mode == "turn-stop" and frame < 60)
            visual.set_animation("move" if moving else "attack" if mode == "attack" else "idle")
            position += heading * (100.0 / 60.0) if moving else Vector2.ZERO
            var motion = visual.soldier_motion
            if motion.has_method("observe_combat"):
                motion.observe_combat(frame, 12 - (frame / 3) % 12 if mode == "attack" else 0)
            motion.sample(position, 1.0 / 60.0, frame, 1.0, ground, true,
                heading * 100.0 if moving else Vector2.ZERO, heading if mode == "attack" else Vector2.ZERO)
            camera.position = visual.position + Vector3(90, 57, 120)
            camera.look_at(visual.position + Vector3(0, 33, 0))
            visual.set_soldier_shadow_distance(camera.position)
            if frame in [20, 28, 36, 44, 60, 72]:
                await capture(mode + "-%03d" % frame)
        camera.position = visual.position + Vector3(120, 43, 0)
        camera.look_at(visual.position + Vector3(0, 35, 0))
        await capture(mode + "-side")
        if carry_review:
            camera.position = visual.position + Vector3(0, 48, 150)
            camera.look_at(visual.position + Vector3(0, 35, 0))
            await capture(mode + "-front")
            camera.position = visual.position + Vector3(-90, 57, -120)
            camera.look_at(visual.position + Vector3(0, 33, 0))
            await capture(mode + "-back")
    if version == "after":
        visual.set_heading(Vector2.DOWN, true)
        visual.set_animation("attack")
        visual.soldier_motion.sample(Vector2.ZERO, .1, 0, 1, ground, true, Vector2.ZERO, Vector2.DOWN)
        camera.position = Vector3(90, 57, 120)
        camera.look_at(Vector3(0, 33, 0))
        for level in 3:
            visual.soldier_motion.lod.select_height([150.0, 70.0, 20.0][level])
            for team in [1, 2]:
                visual.set_faction(team)
                await capture("lod-%d-team-%d" % [level, team])
        if carry_review:
            visual.set_faction(1)
            visual.soldier_motion.lod.select_height(150)
            visual.set_animation("move")
            var step_time := 56.0 / 100.0 / 32.0
            for frame in 64:
                visual.soldier_motion.sample(Vector2(0, frame * 56.0 / 32.0), step_time, frame, 1, ground, true, Vector2(0, 100), Vector2.ZERO)
                camera.position = visual.position + Vector3(120, 43, 0)
                camera.look_at(visual.position + Vector3(0, 35, 0))
                if frame >= 32:
                    await capture("run-loop-%02d" % (frame - 32))
            if "--clear-run" in OS.get_cmdline_args():
                camera.size = 500
                visual.soldier_motion.lod.select_height(20)
                for frame in 64:
                    visual.soldier_motion.sample(Vector2(0, frame * 56.0 / 32.0), step_time, frame, 1, ground, true, Vector2(0, 100), Vector2.ZERO)
                    camera.position = visual.position + Vector3(200, 280, 300)
                    camera.look_at(visual.position + Vector3(0, 33, 0))
                    if frame >= 32:
                        await capture("rts-loop-%02d" % (frame - 32))
    visual.free()
    if "--preview-only" in OS.get_cmdline_args():
        world.free()
        print("SOLDIER_QUALITY_PREVIEW PASS")
        quit()
        return
    var report := {"version": version, "runs": []}
    RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
    for repeat in range(3):
        var army: Array[Node3D] = []
        var origins: Array[Vector2] = []
        for i in range(180):
            var soldier := Visual.new("soldier", 1)
            world.add_child(soldier)
            soldier.set_heading(Vector2.DOWN, true)
            soldier.set_animation("move")
            army.append(soldier)
            origins.append(Vector2((i % 15 - 7) * 36, (i / 15 - 6) * 36))
        camera.size = 720
        camera.position = Vector3(500, 650, 700)
        camera.look_at(Vector3(0, 30, 60))
        var times: Array[float] = []
        var cpu := 0.0
        var gpu := 0.0
        var draws := 0.0
        var primitives := 0.0
        for frame in range(210):
            var began := Time.get_ticks_usec()
            for i in army.size():
                var soldier = army[i]
                if soldier.soldier_motion.has_method("configure_view"):
                    soldier.soldier_motion.configure_view(camera, 1.0 / 60.0)
                soldier.soldier_motion.sample(origins[i] + Vector2(0, frame * 100.0 / 60.0),
                    1.0 / 60.0, frame, 1, ground, true, Vector2(0, 100), Vector2.ZERO)
                soldier.set_soldier_shadow_distance(camera.position)
            var work := (Time.get_ticks_usec() - began) / 1000.0
            await process_frame
            if frame >= 30:
                times.append((Time.get_ticks_usec() - began) / 1000.0)
                cpu += work
                gpu += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
                draws += RenderingServer.viewport_get_render_info(root.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
                primitives += RenderingServer.viewport_get_render_info(root.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
        times.sort()
        var mean := 0.0
        for time: float in times:
            mean += time
        report.runs.append({"frame_ms": mean / times.size(), "p95_ms": times[int(times.size() * .95)],
            "animation_cpu_ms": cpu / times.size(), "gpu_ms": gpu / times.size(),
            "draws": draws / times.size(), "primitives": primitives / times.size()})
        for soldier in army:
            soldier.free()
        await process_frame
    var file := FileAccess.open(output + version + "-performance.json", FileAccess.WRITE)
    file.store_string(JSON.stringify(report, "  "))
    file.close()
    print("SOLDIER_QUALITY ", JSON.stringify(report))
    world.free()
    quit()
