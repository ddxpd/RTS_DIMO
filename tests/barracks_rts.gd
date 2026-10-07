extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")

const Presentation = preload("res://assets/art/barracks_presentation.gd")
var failures: Array[String] = []
var world: Node3D
var camera: Camera3D
var output := "res://assets/concept_art/barracks_rts/"
var measurements: Array[Dictionary] = []

class BenchmarkRig extends Node3D:
    var model: Node3D
    var motion: RefCounted


func _initialize() -> void:
    run.call_deferred()


func check(value: bool, message: String) -> void:
    if not value:
        failures.append(message)
        push_error(message)


func counts(model: Node3D, visible_only := false) -> Dictionary:
    var triangles := 0
    var surfaces := 0
    for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
        if visible_only and not mesh.visible:
            continue
        for surface in range(mesh.mesh.get_surface_count()):
            var arrays := mesh.mesh.surface_get_arrays(surface)
            triangles += (arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX].size() > 0 else arrays[Mesh.ARRAY_VERTEX].size()) / 3
            surfaces += 1
    return {"triangles": triangles, "surfaces": surfaces}


func capture(label: String) -> void:
    if DisplayServer.get_name() == "headless":
        return
    for frame in range(4):
        await process_frame
    await RenderingServer.frame_post_draw
    check(root.get_texture().get_image().save_png(output + label + ".png") == OK, "Save " + label)


func check_chassis(model: Node3D, level: int) -> void:
    # Probe the centre and both load-bearing side rails from below. Overall
    # building bounds alone still pass when the entire chassis has disappeared.
    var hull: MeshInstance3D = model.find_child("HullMesh", true, false)
    for x in [-4.25, 0.0, 4.25]:
        for z in [-1.0, 0.0, 1.0]:
            var start := hull.to_local(model.to_global(Vector3(x, -0.1, z)))
            var end := hull.to_local(model.to_global(Vector3(x, 0.99, z)))
            var found := false
            for surface in range(hull.mesh.get_surface_count()):
                var arrays := hull.mesh.surface_get_arrays(surface)
                var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
                var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
                for index in range(0, indices.size(), 3):
                    if Geometry3D.segment_intersects_triangle(start, end, vertices[indices[index]], vertices[indices[index + 1]], vertices[indices[index + 2]]) != null:
                        found = true
                        break
                if found:
                    break
            check(found, "LOD %d chassis coverage at (%s, %s)" % [level, x, z])


func check_weather_texture(texture: Texture2D, suffix: String) -> void:
    # Compare the imported runtime resource with the PNG actually embedded in
    # the production GLB, so a stale importer cache cannot pass silently.
    check(texture != null, "Weathered " + suffix + " texture is assigned")
    if texture == null:
        return
    var file := FileAccess.open("res://assets/models/barracks.glb", FileAccess.READ)
    file.seek(12)
    var json_length := file.get_32()
    file.seek(20)
    var document: Dictionary = JSON.parse_string(file.get_buffer(json_length).get_string_from_utf8())
    var expected := Image.new()
    for embedded: Dictionary in document.images:
        if str(embedded.name).begins_with("barracks_weathered_" + suffix):
            var view: Dictionary = document.bufferViews[embedded.bufferView]
            file.seek(28 + json_length + int(view.get("byteOffset", 0)))
            check(expected.load_png_from_buffer(file.get_buffer(view.byteLength)) == OK, "Decode weathered " + suffix)
            break
    file.close()
    check(not expected.is_empty(), "GLB contains newly baked " + suffix)
    if expected.is_empty():
        return
    var actual := texture.get_image()
    if actual.is_compressed():
        actual.decompress()
    check(actual.get_size() == Vector2i(2048, 2048), "Weather atlas stays 2K")
    if actual.get_size() != expected.get_size():
        return
    var maximum_error := 0.0
    for y in range(23, 2048, 73):
        for x in range(17, 2048, 79):
            var a := actual.get_pixel(x, y)
            var b := expected.get_pixel(x, y)
            maximum_error = maxf(maximum_error, maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))))
    check(maximum_error < .025, "Runtime " + suffix + " matches embedded weather atlas")


func check_far_weather(hull: MeshInstance3D, atlas: Image) -> void:
    if atlas.is_compressed():
        atlas.decompress()
    var error := 0.0
    var samples := 0
    for surface in range(hull.mesh.get_surface_count()):
        if hull.mesh.surface_get_material(surface).resource_name != "RTS_Body":
            continue
        var arrays := hull.mesh.surface_get_arrays(surface)
        var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
        var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
        for index in range(0, colors.size(), 11):
            var uv := uvs[index]
            var expected := atlas.get_pixel(clampi(int(uv.x * atlas.get_width()), 0, atlas.get_width() - 1), clampi(int(uv.y * atlas.get_height()), 0, atlas.get_height() - 1)).srgb_to_linear()
            var actual := colors[index]
            error += absf(expected.r - actual.r) + absf(expected.g - actual.g) + absf(expected.b - actual.b)
            samples += 3
    print("FAR_WEATHER_ERROR ", error / maxf(1, samples))
    check(samples > 0 and error / maxf(1, samples) < .025, "Far vertex colors match atlas orientation and linear colour space")


func run() -> void:
    DirAccess.make_dir_recursive_absolute(output)
    root.size = Vector2i(1280, 1080)
    world = Node3D.new()
    root.add_child(world)
    camera = Camera3D.new()
    world.add_child(camera)
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 320
    camera.position = Vector3(170, 230, -270)
    camera.look_at(Vector3(0, 45, 0))
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-55, -30, 0)
    light.shadow_enabled = true
    world.add_child(light)
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color("303943")
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color("bccde0")
    environment.environment.ambient_light_energy = 0.6
    world.add_child(environment)
    var floor_mesh := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(2200, 2200)
    floor_mesh.mesh = plane
    var floor_material := StandardMaterial3D.new()
    floor_material.albedo_color = Color("615a49")
    floor_mesh.material_override = floor_material
    world.add_child(floor_mesh)
    var visual := EntityVisual.new("barracks", 1)
    world.add_child(visual)
    var presentation: RefCounted = visual.barracks_presentation
    var fixture := {"remaining": 0, "queue": [], "hp": Simulation.BUILD_TYPES.barracks.hp, "flight": {"state": "grounded", "ticks": 0}}
    check(Presentation.choose_lod(150, 0, false) == 0, "Near hysteresis holds")
    check(Presentation.choose_lod(170, 1, false) == 1, "Medium hysteresis holds")
    check(Presentation.choose_lod(70, 1, false) == 2, "Far threshold")
    check(Presentation.choose_lod(85, 2, false) == 2, "Far hysteresis holds")
    check(Presentation.choose_lod(20, 2, true) == 1, "Transitions retain mechanics")
    check(visual._materials.size() <= 7, "Shared per-building material budget")
    check(presentation.materials.RTS_Body.albedo_texture != null and presentation.materials.RTS_Body.normal_texture != null, "Imported body preserves PBR textures")
    check_weather_texture(presentation.materials.RTS_Body.albedo_texture, "basecolor")
    check_weather_texture(presentation.materials.RTS_Body.roughness_texture, "orm")
    check(presentation.materials.RTS_Body.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN, "Roughness reads ORM green")
    check(presentation.materials.RTS_Body.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE, "Metallic reads ORM blue")
    var limits := [[6000, 8400], [3000, 4250], [800, 1650]]
    for level in range(3):
        presentation.set_lod(level)
        var measured := counts(visual.model, true)
        print("LOD_BUDGET ", level, " ", measured)
        check(measured.triangles >= limits[level][0] and measured.triangles <= limits[level][1], "LOD %d triangle budget" % level)
        check(measured.surfaces <= 44, "LOD surface budget")
        for part in ["RearEngineLMesh", "RearEngineRMesh"]:
            var nozzle: MeshInstance3D = visual.model.find_child(part, true, false)
            check(nozzle != null and nozzle.visible, "Rear propulsion retained in LOD %d: %s" % [level, part])
        check_chassis(visual.model, level)
        if level == 2:
            var hull: MeshInstance3D = visual.model.find_child("HullMesh", true, false)
            check(not hull.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR].is_empty(), "Far mesh contains baked colors")
            check(hull.get_active_material(0).vertex_color_use_as_albedo, "Far renderer uses baked colors")
            check_far_weather(hull, presentation.materials.RTS_Body.albedo_texture.get_image())
        check(visual.model.find_children("*", "AnimationPlayer", true, false).size() == 2, "Only mechanical and wind players")
        await capture("lod%d-blue" % level)
    presentation.set_lod(0)
    presentation.update(fixture, 0.01, camera)
    check(presentation.status == "ready", "Idle ready lamp")
    check(presentation.engine.emission_energy_multiplier == 0, "Grounded engines off")
    fixture.queue = [{"remaining": 5}]
    presentation.update(fixture, 0.1, camera)
    check(presentation.status == "training", "Training lamp")
    var first_power: float = presentation.lamp.emission_energy_multiplier
    presentation.update(fixture, 0.3, camera)
    check(not is_equal_approx(first_power, presentation.lamp.emission_energy_multiplier), "Training pulses")
    fixture.queue[0].remaining = 0
    presentation.update(fixture, 0.1, camera)
    check(presentation.status == "blocked" and presentation.lamp.emission.r > presentation.lamp.emission.b, "Blocked exit amber")
    fixture.hp = int(Simulation.BUILD_TYPES.barracks.hp * 0.2)
    presentation.update(fixture, 0.1, camera)
    check(presentation.smoke.emitting and presentation.sparks.emitting and presentation.soot.visible, "Critical damage effects")
    for frame in range(60):
        await process_frame
        presentation.update(fixture, 1.0 / 60.0, camera)
    # Uncapped CI frames can finish before the first particle's emission slot.
    await create_timer(1.0).timeout
    await capture("damaged-blocked")
    visual.visible = false
    presentation.update(fixture, 0.1, camera)
    check(not presentation.smoke.emitting and not presentation.sparks.emitting, "Fog-hidden effects stop")
    visual.visible = true
    camera.position = Vector3(10000, 200, 10000)
    camera.look_at(Vector3(11000, 0, 11000))
    presentation.update(fixture, 0.1, camera)
    check(not presentation.smoke.emitting, "Offscreen effects stop")
    camera.position = Vector3(170, 230, -270)
    camera.look_at(Vector3(0, 45, 0))
    fixture.hp = Simulation.BUILD_TYPES.barracks.hp
    presentation.update(fixture, 0.1, camera)
    check(not presentation.smoke.emitting and not presentation.sparks.emitting and not presentation.soot.visible, "Healing clears all damage effects")
    fixture.flight = {"state": "airborne", "ticks": 80}
    visual.position.y = 144
    camera.size = 500
    camera.look_at(Vector3(0, 90, 0))
    visual.barracks_motion.apply(fixture.flight)
    presentation.update(fixture, 0.1, camera)
    check(presentation.engine.emission_energy_multiplier > 1, "Airborne engines lit")
    await capture("airborne-blue")
    fixture.pos = Vector2.ZERO
    fixture.flight = {"state": "airborne", "ticks": 0, "moving": true, "target": Vector2(0, -120), "heading": 0.0}
    camera.size = 260
    for direction: Vector2 in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
        var heading := atan2(-direction.x, -direction.y)
        fixture.flight.heading = heading
        fixture.flight.target = direction * 120
        visual.rotation.y = heading
        var rear := Vector3(-direction.x, 0, -direction.y)
        camera.position = visual.position + rear * 220 + Vector3(95, 140, 0)
        camera.look_at(visual.position + Vector3(0, 35, 0))
        presentation.update(fixture, .1, camera)
        check(presentation.rear_jets.all(func(jet: MeshInstance3D) -> bool: return jet.is_visible_in_tree()), "Moving rear jets enabled")
        check(visual.get_visual_forward().dot(Vector3(direction.x, 0, direction.y)) > .999, "Front door follows travel direction")
        for jet: MeshInstance3D in presentation.rear_jets:
            check(jet.global_basis.y.normalized().dot(rear) > .999, "Exhaust points opposite travel")
        await capture("direction-%d" % roundi(rad_to_deg(heading)))
    for level in range(3):
        presentation.set_lod(level)
        await capture("rear-engines-lod%d" % level)
    fixture.flight.heading += .4
    presentation.update(fixture, .1, camera)
    check(presentation.rear_jets.all(func(jet: MeshInstance3D) -> bool: return not jet.visible), "Turning disables rear exhaust")
    fixture.flight.heading -= .4
    fixture.flight.moving = false
    presentation.update(fixture, .1, camera)
    check(presentation.rear_jets.all(func(jet: MeshInstance3D) -> bool: return not jet.visible), "Hover disables rear exhaust")
    await capture("rear-engines-hover")
    fixture.flight.moving = true
    visual.visible = false
    presentation.update(fixture, .1, camera)
    check(presentation.rear_jets.all(func(jet: MeshInstance3D) -> bool: return not jet.visible), "Hidden propulsion stops")
    visual.visible = true
    fixture.flight = {"state": "airborne", "ticks": 0}
    visual.rotation.y = 0
    camera.position = Vector3(170, 230, -270)
    camera.size = 500
    camera.look_at(Vector3(0, 90, 0))
    presentation.update(fixture, .1, camera)
    visual.set_faction(2)
    await capture("airborne-red")
    # Look up at each underside: engine/gear openings and retained deck must be
    # visible here, even when hidden behind the walls in the usual RTS view.
    floor_mesh.visible = false
    camera.size = 200
    camera.position = Vector3(170, 40, -230)
    camera.look_at(Vector3(0, 160, 0))
    for level in range(3):
        presentation.set_lod(level)
        await capture("chassis-underside-lod%d" % level)
    presentation.set_lod(0)
    floor_mesh.visible = true
    camera.position = Vector3(170, 230, -270)
    visual.position.y = 0
    camera.look_at(Vector3(0, 45, 0))
    fixture.flight = {"state": "grounded", "ticks": 0}
    fixture.queue = []
    visual.barracks_motion.apply(fixture.flight)
    for pixels in [256, 128, 64]:
        camera.size = 320
        presentation._measure_view(camera)
        camera.size *= presentation.projected_pixels / float(pixels)
        presentation.view_elapsed = 1.0
        presentation.update(fixture, 0.1, camera)
        check(absf(presentation.projected_pixels - pixels) < 1, "Projected pixel selection")
        await capture("silhouette-%d-red" % pixels)
    visual.free()
    var skip_benchmark := DisplayServer.get_name() == "headless" or "--skip-benchmark" in OS.get_cmdline_args()
    if not skip_benchmark:
        await benchmark()
    var report := {"failures": failures, "benchmarks": measurements, "benchmark_skipped": skip_benchmark}
    var file := FileAccess.open(output + ("presentation_report.json" if skip_benchmark else "runtime_report.json"), FileAccess.WRITE)
    file.store_string(JSON.stringify(report, "  "))
    file.close()
    print("BARRACKS_RTS ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
    world.free()
    quit(0 if failures.is_empty() else 1)


func benchmark() -> void:
    var document := GLTFDocument.new()
    var state := GLTFState.new()
    check(document.append_from_file("res://assets/models/source/barracks_rts_baseline.glb", state) == OK, "Load preserved baseline")
    var baseline := document.generate_scene(state)
    var packed := PackedScene.new()
    packed.pack(baseline)
    baseline.free()
    var labels := ["baseline", "near", "medium", "far"]
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
    for amount in [1, 16, 64]:
        for level in range(4):
            var instances: Array[Node3D] = []
            var extent := int(ceil(sqrt(amount)))
            camera.size = maxf(320, extent * 175)
            camera.position = Vector3(500, 700, -900)
            camera.look_at(Vector3(0, 35, 0))
            for i in range(amount):
                var rig := BenchmarkRig.new()
                world.add_child(rig)
                rig.model = (packed if level == 0 else EntityVisual.MODEL_SCENES.barracks).instantiate()
                rig.add_child(rig.model)
                rig.model.scale = Vector3.ONE * 12
                rig.position = Vector3((i % extent - (extent - 1) * 0.5) * 150, 0, (i / extent - (extent - 1) * 0.5) * 125)
                rig.motion = preload("res://assets/art/barracks_motion.gd").new(rig)
                rig.motion.apply({"state": "grounded", "ticks": 0})
                for mesh: MeshInstance3D in rig.model.find_children("*", "MeshInstance3D", true, false):
                    var node_name := str(mesh.name)
                    if level > 1:
                        mesh.mesh = Presentation.shared_lods[level - 2].get(node_name, mesh.mesh)
                    if level == 3:
                        mesh.visible = not (node_name.begins_with("Gear") or node_name.begins_with("RampRod") or node_name.begins_with("RampCylinder") or node_name == "BarracksFlag")
                        for surface in range(mesh.mesh.get_surface_count()):
                            var material := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
                            if material != null:
                                material.vertex_color_use_as_albedo = true
                    # Compare the explicit authored budgets without automatic LOD.
                    mesh.lod_bias = 1000.0
                instances.append(rig)
            for frame in range(20):
                await process_frame
            if amount == 1:
                await capture("comparison-" + labels[level])
            var cpu := 0.0
            var gpu := 0.0
            var draws := 0.0
            var primitives := 0.0
            for frame in range(60):
                await process_frame
                cpu += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
                gpu += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
                draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
                primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
            var result := {"count": amount, "mesh": labels[level], "cpu_render_ms": cpu / 60, "gpu_render_ms": gpu / 60, "draw_calls": draws / 60, "primitives": primitives / 60}
            measurements.append(result)
            print("BARRACKS_BENCHMARK ", result)
            for model in instances:
                model.free()
            await process_frame
