extends SceneTree

const Catalog = preload("res://scripts/maps/component_catalog.gd")
const Layout = preload("res://scripts/maps/component_layout.gd")
const Terrain = preload("res://scripts/maps/map_terrain.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
    run.call_deferred()


func check(value: bool, message: String) -> void:
    checks += 1
    if not value:
        failures.append(message)
        push_error(message)


func run() -> void:
    var layout := Layout.new()
    check(layout.load_file("res://assets/maps/desert_sample_layout.json"), "Load authored layout: " + layout.error)
    if not layout.error.is_empty():
        quit(1)
        return
    var path := "user://terrain-layout-roundtrip.json"
    check(layout.save_file(path) == OK, "Save editable layout")
    var copy := Layout.new()
    check(copy.load_file(path), "Read saved layout")
    check(copy.checksum() == layout.checksum(), "Save/load stable content hash")
    var preset := ConfigFile.new()
    check(preset.load("res://export_presets.cfg") == OK, "Read packaging settings")
    var included := false
    for pattern: String in str(preset.get_value("preset.0", "include_filter", "")).split(","):
        included = included or "assets/maps/desert_sample_layout.json".match(pattern.strip_edges())
    check(included, "Export explicitly includes non-resource layout JSON")
    var packer := PCKPacker.new()
    check(packer.pck_start("res://.godot/terrain-layout-check.pck") == OK, "Create isolated packaging fixture")
    check(packer.add_file("res://packaged-component-layout.json", "res://assets/maps/desert_sample_layout.json") == OK and packer.flush() == OK, "Pack JSON payload")
    check(ProjectSettings.load_resource_pack("res://.godot/terrain-layout-check.pck", false), "Mount packaging fixture")
    var packed := Layout.new()
    check(packed.load_file("res://packaged-component-layout.json") and packed.checksum() == layout.checksum(), "Runtime layout loads from packed resources")
    var reordered: Dictionary = layout.data.duplicate(true)
    reordered.instances.reverse()
    check(copy.configure(reordered) and copy.checksum() == layout.checksum(), "Input order does not change map checksum")
    DirAccess.remove_absolute(path)
    var original := layout.checksum()
    var malformed: Dictionary = layout.data.duplicate(true)
    malformed.instances[0].component = "unknown"
    check(not copy.configure(malformed) and "Unknown component" in copy.error, "Unknown ID rejected")
    malformed = layout.data.duplicate(true)
    malformed.instances[0].position[0] = 99999
    check(not copy.configure(malformed), "Out-of-bounds rejected")
    malformed = layout.data.duplicate(true)
    malformed.instances[0].scale = 2
    check(not copy.configure(malformed), "Terrain scale rejected")
    malformed = layout.data.duplicate(true)
    malformed.instances.append(malformed.instances[0].duplicate(true))
    check(not copy.configure(malformed), "Duplicate ID rejected")
    malformed = layout.data.duplicate(true)
    for i in range(malformed.instances.size()):
        if malformed.instances[i].component == "ramp_run":
            malformed.instances.remove_at(i)
            break
    check(not copy.configure(malformed) and "edge" in copy.error, "Missing ramp connection rejected")
    check(layout.checksum() == original, "Rejected edits do not mutate original")
    for turn in range(4):
        var rotated: Dictionary = layout.data.duplicate(true)
        rotated.bounds = [640, 64, 3200, 3072]
        var basis := Basis(Vector3.UP, turn * PI / 2)
        for instance: Dictionary in rotated.instances:
            var p: Array = instance.position
            var world := basis * Vector3(float(p[0]) - 2400, float(p[1]), float(p[2]) - 1600) + Vector3(2400, 0, 1600)
            instance.position = [world.x, world.y, world.z]
            instance.rotation = float(instance.rotation) + turn * PI / 2
        check(copy.configure(rotated), "All socket connections in rotated layout " + str(turn) + ": " + copy.error)
    var bytes := 0
    var art_report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Catalog.ROOT + "build_report.json"))
    check(art_report.catalog_revision == Catalog.REVISION and art_report.art_revision == 3, "Production art report matches logical catalog")
    for source: String in ["cliff", "rock", "rubble-a", "rubble-b", "rubble-c", "rubble-d"]:
        var mesh: ArrayMesh = load("res://assets/models/source/terrain/" + source + ".res")
        check(mesh != null and mesh.get_surface_count() == 1, "Standalone retained production source " + source)
    for id: String in Catalog.IDS:
        var entry := Catalog.entry(id)
        check(ResourceLoader.exists(entry.scene), "Runtime scene exists " + id)
        check(ResourceLoader.exists(entry.thumbnail), "Imported thumbnail exists " + id)
        var node: MeshInstance3D = load(entry.scene).instantiate()
        check(node.mesh.get_surface_count() > 0 and node.scale == Vector3.ONE, "Native game units " + id)
        var aabb := node.mesh.get_aabb()
        if id.begins_with("cliff"):
            check(node.mesh.get_surface_count() == 2, "Sculpted cliff has continuous backing " + id)
            var backing: StandardMaterial3D = node.mesh.surface_get_material(1)
            check(backing != null and backing.uv1_world_triplanar and backing.albedo_texture.resource_path.ends_with("cliff_basecolor.png"), "Cliff backing uses tiled material instead of rock atlas " + id)
        for surface in range(node.mesh.get_surface_count()):
            var arrays := node.mesh.surface_get_arrays(surface)
            check(arrays[Mesh.ARRAY_NORMAL].size() == arrays[Mesh.ARRAY_VERTEX].size() and arrays[Mesh.ARRAY_TANGENT].size() == arrays[Mesh.ARRAY_VERTEX].size() * 4 and arrays[Mesh.ARRAY_TEX_UV].size() == arrays[Mesh.ARRAY_VERTEX].size(), "PBR mesh attributes " + id)
            var finite := true
            var sockets := true
            for p: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
                finite = finite and p.is_finite()
                if entry.layer == "surface":
                    var edge: bool = minf(minf(absf(p.x), absf(p.x - entry.size.x)), minf(absf(p.z), absf(p.z - entry.size.y))) < 0.001
                    if edge:
                        sockets = sockets and absf(p.y - Catalog.height(id, Vector2(p.x, p.z))) < 0.1
            check(finite and sockets, "Finite geometry and exact border height " + id)
        check(int(art_report.components[id].triangles) < 6000, "Component triangle budget " + id)
        if entry.layer == "decoration":
            check(int(art_report.components[id].lods) > 0, "Rock/rubble automatic LODs " + id)
        check(aabb.size.x <= entry.size.x + 0.1 and aabb.size.z <= entry.size.y + 0.1, "Geometry fits declared footprint " + id)
        node.free()
        if entry.layer == "surface":
            for turn in range(4):
                var instance := {"component": id, "position": [640, 0, 640], "rotation": turn * PI / 2}
                var t := Catalog.transform(instance)
                var p: Vector2 = entry.size * 0.5
                var world := t * Vector3(p.x, Catalog.height(id, p), p.y)
                check(absf(Catalog.world_height(instance, Vector2(world.x, world.z)) - world.y) < 0.01, "Rotated surface height " + id)
    for name_value in ["sand_basecolor", "sand_normal", "cliff_basecolor", "cliff_normal", "rock_basecolor", "rock_normal", "rock_orm"]:
        var texture: Texture2D = load(Catalog.ROOT + name_value + ".png")
        var image := texture.get_image()
        check(image.has_mipmaps() and image.is_compressed(), "GPU-compressed mipmapped texture " + name_value)
        bytes += image.get_data_size()
    check(bytes < 96 * 1024 * 1024, "New shared texture budget under 96 MiB")
    var terrain := Terrain.new()
    check(terrain.load_map("desert_sample"), "Assemble component sample: " + terrain.error)
    check(terrain.sample_surface.layout != null, "Sample uses component authority")
    var field = terrain.sample_surface
    var conservative := true
    for z in range(int(field.bounds.position.y) + 16, int(field.bounds.end.y), 32):
        for x in range(int(field.bounds.position.x) + 16, int(field.bounds.end.x), 32):
            for radius in [11.0, 24.0]:
                var p := Vector2(x, z)
                if field.position_clear(p, radius) and not field.position_clear_precise(p, radius):
                    conservative = false
    check(conservative, "Cached clearance never admits a position rejected by precise checks")
    check(terrain.build_error(Rect2(1760, 1856, 96, 128)).is_empty(), "3x4 barracks pad")
    check(not terrain.build_error(Rect2(1840, 1456, 96, 128)).is_empty(), "Whole footprint spanning toe denied")
    var boulder: Rect2 = field.layout.blockers[0]
    check(not terrain.build_error(boulder).is_empty(), "Blocking boulder denies placement")
    check(not terrain.position_clear(boulder.get_center(), 14), "Boulder blocks navigation")
    for ramp: Dictionary in terrain.definition.ramps:
        check(is_equal_approx(ramp.start.distance_to(ramp.end), 256), "Short ramp length")
        check(terrain.segment_clear(ramp.start, ramp.end, 24), "Short ramp traversable")
        for t in [0.0, 0.125, 0.5, 0.875, 1.0]:
            var p: Vector2 = ramp.start.lerp(ramp.end, t)
            var hit := terrain.ray_hit(Vector3(p.x, 500, p.y), Vector3.DOWN)
            check(hit.is_finite() and absf(hit.y - terrain.height_at(p)) < 0.01, "Picking matches ramp height")
    var pit := terrain.ray_hit(Vector3(3000, 501, 1800), Vector3.DOWN)
    check(pit.is_finite() and absf(pit.y + 128) < 0.01, "Pick lowest pit at non-step-aligned ray")
    check(terrain.load_map("desert_quarry") and terrain.sample_surface != null and not terrain.definition.get("test_only", false), "Formal map shares components without sample-only rules")
    print("TERRAIN_COMPONENTS checks=", checks, " failures=", failures.size(), " texture_mib=", bytes / 1048576.0)
    quit(0 if failures.is_empty() else 1)
