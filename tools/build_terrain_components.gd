extends SceneTree
## Rebuild production assets from retained art sources, never modifies originals.
const Catalog = preload("res://scripts/maps/component_catalog.gd")
const Layout = preload("res://scripts/maps/component_layout.gd")
const OUT := "res://assets/maps/components/"
var instances: Array = []
var counter := 0
var failures: Array[String] = []
var report: Dictionary = {}


func _initialize() -> void:
    run.call_deferred()


func add(id: String, x: float, y: float, z: float, turn: int = 0, scale_value: float = 1) -> void:
    counter += 1
    instances.append({"id": "%s_%03d" % [id, counter], "component": id, "position": [x, y, z], "rotation": turn * PI / 2, "scale": scale_value})


func ramp(x: float, y: float, z: float, turn: int) -> void:
    var t := Transform3D(Basis(Vector3.UP, turn * PI / 2), Vector3(x, y, z))
    for part in [["ramp_toe", 0, 0], ["ramp_run", 16, 32], ["ramp_crest", 112, 224]]:
        var p := t * Vector3(0, part[1], part[2])
        add(part[0], p.x, p.y, p.z, turn)


func make_layout() -> void:
    # 512-square pads with 64-unit cliff aprons and a 256-wide entrance.
    for x in range(2):
        for z in range(2):
            add("plateau_top", 1632 + x * 256, 128, 1728 + z * 256)
            add("sand_flat", 2656 + x * 256, -128, 1600 + z * 256)
    ramp(1760, 0, 1472, 0)
    ramp(3040, -128, 1600, 2)
    add("cliff_end", 1632, 0, 1664)
    add("cliff_end", 2016, 0, 1664)
    for i in range(2):
        add("cliff_straight", 1568, 0, 1984 + i * 256, 1)
        add("cliff_straight", 2208, 0, 1728 + i * 256, 3)
        add("cliff_straight", 1888 + i * 256, 0, 2304, 2)
    add("cliff_outer", 1568, 0, 1664)
    add("cliff_outer", 2208, 0, 1664, 3)
    add("cliff_outer", 1568, 0, 2304, 1)
    add("cliff_outer", 2208, 0, 2304, 2)
    add("cliff_end", 2784, -128, 1600, 2)
    add("cliff_end", 3168, -128, 1600, 2)
    for i in range(2):
        add("cliff_straight", 2656, -128, 1600 + i * 256, 3)
        add("cliff_straight", 3168, -128, 1856 + i * 256, 1)
        add("cliff_straight", 2656 + i * 256, -128, 2112)
    add("cliff_inner", 2656, -128, 1600, 2)
    add("cliff_inner", 3168, -128, 1600, 1)
    add("cliff_inner", 2656, -128, 2112, 3)
    add("cliff_inner", 3168, -128, 2112)
    # Deliberate blocking boulders are away from paths and building pads.
    add("rock_large", 1504, 0, 1952, 0)
    add("rock_medium", 2336, 0, 2080, 1)
    var random := RandomNumberGenerator.new()
    random.seed = 29531
    var terrain_layout := Layout.new()
    var data := {"version": 2, "catalog_revision": Catalog.REVISION, "seed": 29531, "bounds": [1376, 832, 2048, 1536], "instances": instances}
    if not terrain_layout.configure(data):
        failures.append(terrain_layout.error)
        return
    # Persist every decoration instance; batching remains a disposable cache.
    for i in range(44):
        var side := i % 4
        var x := random.randf_range(1610, 2180)
        var z := random.randf_range(1700, 2290)
        if side == 0:
            x = 1588
        elif side == 1:
            x = 2188
        elif side == 2:
            z = 2276
        else:
            continue
        add("rubble_cluster", x, terrain_layout.height_at(Vector2(x, z)) - 3, z, i % 4, random.randf_range(0.3, 0.65))
    data.instances = instances
    if not terrain_layout.configure(data):
        failures.append(terrain_layout.error)
        return
    if terrain_layout.save_file("res://assets/maps/desert_sample_layout.json") != OK:
        failures.append("Cannot save layout")


func material(kind: String) -> StandardMaterial3D:
    var result := StandardMaterial3D.new()
    result.albedo_texture = load(OUT + kind + "_basecolor.png")
    result.normal_enabled = true
    result.normal_texture = load(OUT + kind + "_normal.png")
    result.normal_scale = 0.38 if kind == "rock" else 0.18
    result.roughness = 0.93
    if kind == "rock":
        result.roughness_texture = load(OUT + "rock_orm.png")
        result.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
        result.ao_enabled = true
        result.ao_texture = result.roughness_texture
    result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    ResourceSaver.save(result, OUT + kind + ".tres")
    return result


func append_mesh(st: SurfaceTool, node: Node3D, parent: Transform3D) -> void:
    var transform_value := parent * node.transform
    if node is MeshInstance3D:
        for i in range(node.mesh.get_surface_count()):
            st.append_from(node.mesh, i, transform_value)
    for child in node.get_children():
        if child is Node3D:
            append_mesh(st, child, transform_value)


func source_mesh(name_value: String) -> ArrayMesh:
    var doc := GLTFDocument.new()
    var state := GLTFState.new()
    var path := "res://assets/concept_art/desert_terrain_kit/v3/v3-" + name_value + ".glb"
    if doc.append_from_file(path, state) != OK:
        failures.append("Cannot read " + path)
        return ArrayMesh.new()
    var node := doc.generate_scene(state)
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    append_mesh(st, node, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 32), Vector3.ZERO))
    node.free()
    return st.commit()


func save_scene(id: String, mesh: ArrayMesh, mat: Material) -> void:
    var importer := ImporterMesh.new()
    importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(0), [], {}, mat)
    if Catalog.entry(id).layer == "decoration":
        importer.generate_lods(25, 60, [])
    var result := importer.get_mesh()
    report[id] = {"lods": importer.get_surface_lod_count(0), "vertices": result.surface_get_array_len(0), "indices": result.surface_get_array_index_len(0), "footprint": [Catalog.entry(id).size.x, Catalog.entry(id).size.y], "boundary_preserved": Catalog.entry(id).layer == "surface"}
    if id == "rubble_cluster":
        # Tiny scattered stones use a baked lower LOD, not four full rocks each.
        var arrays := result.surface_get_arrays(0)
        var lod := maxi(0, importer.get_surface_lod_count(0) - 2)
        if importer.get_surface_lod_count(0) > 0:
            arrays[Mesh.ARRAY_INDEX] = importer.get_surface_lod_indices(0, lod)
        var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        for i in range(points.size()):
            points[i] /= 48.0
        arrays[Mesh.ARRAY_VERTEX] = points
        var detail := ArrayMesh.new()
        detail.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
        detail.surface_set_material(0, mat)
        ResourceSaver.save(detail, OUT + "detail_rubble.res")
        report["detail_rubble"] = {"triangles": detail.surface_get_array_index_len(0) / 3}
    ResourceSaver.save(result, OUT + id + ".res")
    var root := MeshInstance3D.new()
    root.name = id
    root.mesh = load(OUT + id + ".res")
    root.set_meta("component_id", id)
    root.set_meta("catalog_revision", Catalog.REVISION)
    var scene := PackedScene.new()
    scene.pack(root)
    ResourceSaver.save(scene, OUT + id + ".tscn")
    root.free()


func cliff_facade() -> ArrayMesh:
    var mesh := source_mesh("cliff")
    var aabb := mesh.get_aabb()
    var arrays := mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    for i in range(vertices.size()):
        var q := (vertices[i] - aabb.position) / aabb.size
        var lo := 0.0
        var hi := 64.0
        for iteration in range(18):
            var middle := (lo + hi) * 0.5
            if smoothstep(0.0, 64.0, middle) < q.y:
                lo = middle
            else:
                hi = middle
        # Bake the art relief onto the shared cliff section, fading at sockets.
        var relief := sin(q.x * PI) * sin(q.y * PI) * (3.0 + q.z * 15.0)
        vertices[i] = Vector3(q.x * 256.0, q.y * 128.0, (lo + hi) * 0.5 - relief)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    mesh = ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    var st := SurfaceTool.new()
    st.create_from(mesh, 0)
    st.generate_normals()
    st.generate_tangents()
    return st.commit()


func rubble_mesh() -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for i in range(4):
        var source := source_mesh(["rubble-a", "rubble-b", "rubble-c", "rubble-d"][i])
        var transform_value := Transform3D(Basis(Vector3.UP, i * 1.17), Vector3((i % 2) * 28, 0, int(i / 2) * 28))
        st.append_from(source, 0, transform_value)
    st.index()
    return st.commit()


func run() -> void:
    DirAccess.make_dir_recursive_absolute(OUT)
    var sand := material("sand")
    var rock := material("rock")
    var cliff := material("cliff")
    for id: String in Catalog.IDS:
        var item := Catalog.entry(id)
        if id == "cliff_straight":
            save_scene(id, cliff_facade(), rock)
            continue
        if item.layer == "decoration":
            var mesh := source_mesh("rock") if id.begins_with("rock_") else rubble_mesh()
            var aabb := mesh.get_aabb()
            var arrays := mesh.surface_get_arrays(0)
            var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
            var target: Vector2 = item.size
            var factor := minf(target.x / aabb.size.x, target.y / aabb.size.z)
            var center := Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
            for i in range(vertices.size()):
                vertices[i] = (vertices[i] - center) * factor
            arrays[Mesh.ARRAY_VERTEX] = vertices
            mesh = ArrayMesh.new()
            mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
            save_scene(id, mesh, rock)
            continue
        var st := SurfaceTool.new()
        st.begin(Mesh.PRIMITIVE_TRIANGLES)
        var size: Vector2 = item.size
        var step_x := int(size.x) if not id.begins_with("cliff") else 8
        var step_z := int(size.y) if id in ["sand_flat", "plateau_top", "ramp_run"] else 8
        for z in range(0, int(size.y), step_z):
            for x in range(0, int(size.x), step_x):
                for offset: Vector2 in [Vector2(0, 0), Vector2(step_x, 0), Vector2(step_x, step_z), Vector2(0, 0), Vector2(step_x, step_z), Vector2(0, step_z)]:
                    var p := Vector2(x, z) + offset
                    var dx := Catalog.height(id, p + Vector2(0.1, 0)) - Catalog.height(id, p - Vector2(0.1, 0))
                    var dz := Catalog.height(id, p + Vector2(0, 0.1)) - Catalog.height(id, p - Vector2(0, 0.1))
                    st.set_normal(Vector3(-dx, 0.2, -dz).normalized())
                    st.set_uv(p / 192.0)
                    st.add_vertex(Vector3(p.x, Catalog.height(id, p), p.y))
        st.generate_tangents()
        st.index()
        save_scene(id, st.commit(), cliff if id.begins_with("cliff") else sand)
    make_layout()
    var file := FileAccess.open(OUT + "build_report.json", FileAccess.WRITE)
    file.store_string(JSON.stringify({"catalog_revision": Catalog.REVISION, "components": report, "minimum_hardware_tested": false}, "  "))
    print("BUILD_TERRAIN_COMPONENTS failures=", failures)
    quit(0 if failures.is_empty() else 1)
