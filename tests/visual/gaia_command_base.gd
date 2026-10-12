extends SceneTree

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
    run.call_deferred()


func check(value: bool, message: String) -> void:
    checks += 1
    if not value:
        failures.append(message)
        push_error(message)


func bounds(model: Node3D) -> AABB:
    var result := AABB()
    var started := false
    for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
        var transformed: AABB = mesh.global_transform * mesh.get_aabb()
        result = result.merge(transformed) if started else transformed
        started = true
    return result


func run() -> void:
    var base: GaiaCommandBase = load("res://assets/art/buildings/gaia/gaia_command_base.tscn").instantiate()
    base.automatic_animation = false
    root.add_child(base)
    var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/source/gaia_command_base_report.json"))
    var migration: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/codex/structure-migration.json"))
    for path: String in report.legacy_hashes:
        var original := path.replace("\\", "/")
        var current: String = migration.paths.get(original, original)
        check(FileAccess.file_exists("res://" + current), "legacy model/source/recipe retained " + path)
        # The shared source and generator legitimately evolve after this report.
        # The unused legacy base model itself remains byte-identical.
        if original.ends_with("/base.glb"):
            check(FileAccess.get_sha256("res://" + current) == report.legacy_hashes[path], "legacy base model unchanged")
    check(EntityVisual.MODEL_SCENES.base.resource_path == "res://assets/art/buildings/gaia/gaia_command_base.tscn", "game uses GAIA component; legacy asset retained")
    var reference_bounds := bounds(base.models[0])
    for level in range(3):
        base.forced_lod = level
        base.seek_pose("deployed", 0)
        var visible_count := 0
        var meshes: Array[Node] = base.models[level].find_children("*", "MeshInstance3D", true, false)
        var triangles := 0
        var materials: Dictionary = {}
        for mesh: MeshInstance3D in meshes:
            for surface in range(mesh.mesh.get_surface_count()):
                triangles += mesh.mesh.surface_get_array_index_len(surface) / 3
                var arrays := mesh.mesh.surface_get_arrays(surface)
                check(not (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).is_empty(), "UVs exported")
                var material: StandardMaterial3D = mesh.get_active_material(surface)
                materials[material.resource_name] = material
                if material.resource_name in ["GAIA_Armor", "GAIA_Mechanical"]:
                    check(material.albedo_texture != null and material.normal_enabled and material.normal_texture != null, "PBR color and baked normal present")
                    check(material.roughness_texture != null and material.metallic_texture != null, "ORM roughness and metalness present")
        check(triangles <= [150000,45000,12000][level] and triangles > 1000, "LOD triangle budget " + str(level))
        check(meshes.size() <= 20 and materials.size() <= 6, "mesh and material budgets")
        var box := bounds(base.models[level])
        check(box.size.is_equal_approx(Vector3(320, 144, 192)), "grid-aligned presentation dimensions " + str(box.size))
        check(absf(box.position.y - 12.0) < 0.05, "deployment clearance 12")
        check(box.size.distance_to(reference_bounds.size) < 0.1, "LOD silhouette envelope consistent")
        for model in base.models:
            visible_count += int(model.visible)
        check(visible_count == 1, "only one LOD visible")
        if materials.has("GAIA_Armor"):
            check(materials.GAIA_Armor.albedo_texture.get_width() == 4096, "4K armor atlas")
        if materials.has("GAIA_Mechanical"):
            check(materials.GAIA_Mechanical.albedo_texture.get_width() == 2048, "2K mechanical atlas")
    base.forced_lod = 0
    var low := INF
    var high := -INF
    for i in range(121):
        base.seek_pose("deployed", i / 20.0)
        low = minf(low, base.presentation.position.y)
        high = maxf(high, base.presentation.position.y)
    check(is_equal_approx(low,11.5) and is_equal_approx(high,12.5), "idle bob +/- 0.5 over six seconds")
    for fps in [30,60,144]:
        base.seek_pose("deployed", 0)
        base.take_off()
        var last := base.presentation.position.y
        var largest_step := 0.0
        for i in range(fps*6+1):
            base.advance(1.0/fps)
            largest_step = maxf(largest_step, absf(base.presentation.position.y-last))
            last = base.presentation.position.y
        check(base.state == "airborne" and absf(last-108) < 0.1, "six-second takeoff at " + str(fps))
        check(largest_step < 1.0, "continuous takeoff height")
        base.set_cruising(true)
        for i in range(fps*2):
            base.advance(1.0/fps)
        check(absf(base.presentation.rotation.x-deg_to_rad(-2)) < 0.0001, "cruise pitch limited to two degrees")
        base.set_cruising(false)
        for i in range(fps*2):
            base.advance(1.0/fps)
        check(absf(base.presentation.rotation.x) < 0.0001, "stopping restores level attitude")
        base.land()
        for i in range(fps*6+1):
            base.advance(1.0/fps)
        check(base.state == "deployed" and absf(base.presentation.position.y-12) < 0.51, "landing returns to low hover")
    base.seek_pose("deployed", 3)
    var radar: float = base.radar_yaws[0].rotation.y
    base.radar_enabled = false
    base.advance(1)
    check(is_equal_approx(radar,base.radar_yaws[0].rotation.y), "radar independently disabled")
    base.radar_enabled = true
    base.advance(1)
    check(not is_equal_approx(radar,base.radar_yaws[0].rotation.y), "radar independent scan resumes")
    var camera := Camera3D.new()
    root.add_child(camera)
    camera.current = true
    base.forced_lod = -1
    for pair: Array in [[500,0],[1000,1],[1900,2],[1600,1],[800,0]]:
        camera.position = base.presentation.global_position + Vector3(0,0,pair[0])
        base.update_lod()
        check(base.current_lod == pair[1], "automatic LOD distance " + str(pair[0]))
    check(base.lights.size() == 2 and not base.lights[0].shadow_enabled, "maximum two unshadowed bounce lights")
    check(not base.has_method("build") and report.construction_animation.begins_with("not implemented"), "construction animation explicitly deferred")
    var result := {"checks":checks,"failures":failures,"dimensions":reference_bounds.size,"minimum_idle_clearance":low}
    var file := FileAccess.open("res://assets/concept_art/gaia_command_base/runtime-report.json", FileAccess.WRITE)
    file.store_string(JSON.stringify(result,"  "))
    print("GAIA_ASSET_TEST ",JSON.stringify(result))
    base.queue_free()
    camera.queue_free()
    await process_frame
    quit(0 if failures.is_empty() else 1)
