@tool
extends "res://addons/godot_ai/testing/test_suite.gd"

const MODEL_PATH := "res://assets/models/units/mobile_infantry/mobile_infantry.glb"


func suite_name() -> String:
    return "mobile_infantry"


func test_independent_weapon() -> void:
    var scene = load("res://assets/models/units/mobile_infantry/mobile_infantry_machine_gun.glb")
    var gun: Node3D = scene.instantiate()
    track(gun)
    var meshes := gun.find_children("*", "MeshInstance3D", true, false)
    var node_names: Array[String] = []
    for node in gun.find_children("*", "Node3D", true, false):
        node_names.append(node.name)
    assert_eq(meshes.size(), 1, "Independent rigid weapon has one mesh")
    var mesh: Mesh = meshes[0].mesh
    assert_eq(mesh.get_surface_count(), 1, "Weapon uses one material")
    assert_true(mesh.surface_get_array_index_len(0) / 3 <= 2000, "Weapon triangle budget")
    var material := mesh.surface_get_material(0) as StandardMaterial3D
    assert_eq(material.albedo_texture.get_width(), 1024, "Weapon owns a 1024 atlas")
    assert_true(material.normal_enabled and material.normal_texture != null, "Weapon relief uses normal map")
    assert_true(material.ao_enabled and material.roughness_texture != null, "Weapon PBR parameters imported")
    for anchor in ["GripRight", "GripLeft", "MuzzleSocket"]:
        assert_true(gun.find_child(anchor, true, false) != null, "Stable weapon anchor: " + anchor + " in " + str(node_names))
    var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/source/mobile_infantry_machine_gun_report.json"))
    assert_eq(int(report.uv_triangle_intersection_pairs), 0, "Weapon UVs do not overlap")
    assert_eq(int(report.source_ngons), 0, "Weapon source has no ngons")
    assert_eq(int(report.external_dependencies), 0, "Weapon is self-contained")


func test_rigged_asset_import() -> void:
    var scene := ResourceLoader.load(MODEL_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
    assert_true(scene != null, "GLB imports as a PackedScene")
    if scene == null:
        return
    var model := scene.instantiate()
    track(model)
    var meshes := model.find_children("*", "MeshInstance3D", true, false)
    assert_eq(meshes.size(), 1, "Runtime mesh is consolidated")
    var triangles := 0
    var faction_count := 0
    var materials := {}
    for instance: MeshInstance3D in meshes:
        for surface in range(instance.mesh.get_surface_count()):
            triangles += instance.mesh.surface_get_array_index_len(surface) / 3
            var material := instance.mesh.surface_get_material(surface) as StandardMaterial3D
            assert_true(material != null, "PBR material imported")
            if material == null:
                continue
            materials[material.resource_name] = true
            if "Faction" in material.resource_name:
                faction_count += 1
                var red := material.duplicate() as StandardMaterial3D
                red.albedo_color = Color(0.58, 0.035, 0.022)
                assert_true(red.albedo_color != material.albedo_color, "Team colors can change independently")
                assert_true(material.albedo_texture == null, "Faction color is not baked blue")
            else:
                assert_true(material.albedo_texture != null, "Base color embedded")
                if material.albedo_texture != null:
                    assert_eq(material.albedo_texture.get_width(), 2048, "2048 atlas")
            assert_true(material.normal_enabled and material.normal_texture != null, "Normal map imported")
            assert_true(material.roughness_texture != null and material.metallic_texture != null, "Packed material parameters imported")
            assert_true(material.ao_enabled and material.ao_texture != null, "Baked AO imported")
    assert_true(triangles > 0 and triangles <= 6000, "Game geometry stays inside budget")
    assert_true(materials.size() <= 3, "At most three runtime materials")
    var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/source/mobile_infantry_report.json"))
    assert_eq(triangles, int(report.export_triangles), "Imported mesh matches the audited deliverable: actual=%d expected=%d" % [triangles, int(report.export_triangles)])
    assert_eq(faction_count, 1, "One independently colorable team surface")
    var skeletons := model.find_children("*", "Skeleton3D", true, false)
    assert_eq(skeletons.size(), 1, "One independent skeleton")
    if not skeletons.is_empty():
        assert_eq(skeletons[0].get_bone_count(), 23, "Only deform bones exported")
    var players := model.find_children("*", "AnimationPlayer", true, false)
    assert_eq(players.size(), 1, "Baked action player imported")
    if not players.is_empty():
        assert_eq(players[0].get_animation_list().size(), 6, "No stale actions from other Blender sessions")
        for clip in ["RESET", "idle", "walk", "jog", "fire", "death"]:
            assert_true(players[0].has_animation(clip), "Required animation: " + clip)


func test_source_report() -> void:
    var file := FileAccess.open("res://assets/models/source/mobile_infantry_report.json", FileAccess.READ)
    assert_true(file != null, "Authoring report exists")
    if file == null:
        return
    var report: Dictionary = JSON.parse_string(file.get_as_text())
    assert_eq(int(report.source_ngons), 0, "No source ngons")
    assert_eq(int(report.source_triangles), 0, "All source faces are quads")
    assert_eq(int(report.uv_overlap_pairs), 0, "UV island allocation validation")
    assert_eq(int(report.uv_triangle_intersection_pairs), 0, "Actual UV triangles have no positive-area intersections")
    assert_true(int(report.uv_min_gutter_pixels) >= 8, "Atlas has required mip padding")
    assert_eq(int(report.external_dependencies), 0, "Portable embedded GLB")
    assert_eq(int(report.version), 6, "Independent weapon revision")
    assert_true(report.separate_weapon, "Body atlas and mesh exclude the old rifle")
    for role in ["ContinuousBody", "ContinuousSleeveL", "ContinuousSleeveR", "HelmetShell"]:
        assert_eq(int(report.continuous_component_counts[role]), 1, "Continuous source topology: " + role)
    assert_eq(int(report.skin_unweighted_vertices), 0, "Every source vertex is skinned")
    assert_true(float(report.skin_max_weight_error) < 0.00001, "Normalized source skin weights")
    assert_true(int(report.skin_samples) >= 36 and float(report.skin_max_edge_ratio) < 3.0, "Evaluated motion has no extreme elbow stretch")
    assert_true(report.normal_baked and report.ao_baked, "High detail was baked")
    assert_eq(report.faction_parts, ["ShoulderArmorL", "ShoulderArmorR"], "Only whole shoulder shells carry faction paint")
    assert_true(report.normal_bake_exclusions.is_empty(), "Helmet is no longer excluded from surface normals")
    assert_true(float(report.helmet_normal_detail_max) > 0.025, "Helmet has baked relief")


func test_faction_geometry_is_confined_to_shoulders() -> void:
    var scene := ResourceLoader.load(MODEL_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
    assert_true(scene != null, "Model imports for independent faction geometry check")
    if scene == null:
        return
    var model := scene.instantiate()
    track(model)
    var instance := model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
    var mesh_to_model := Transform3D.IDENTITY
    var ancestor: Node = instance
    while ancestor is Node3D:
        mesh_to_model = (ancestor as Node3D).transform * mesh_to_model
        ancestor = ancestor.get_parent()
    for surface in range(instance.mesh.get_surface_count()):
        var material := instance.mesh.surface_get_material(surface) as StandardMaterial3D
        if material == null or not "Faction" in material.resource_name:
            continue
        var vertices: PackedVector3Array = instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
        var inside_shoulders := true
        var left := false
        var right := false
        var minimum := Vector3(INF, INF, INF)
        var maximum := Vector3(-INF, -INF, -INF)
        for local_vertex in vertices:
            var vertex := mesh_to_model * local_vertex
            minimum = minimum.min(vertex)
            maximum = maximum.max(vertex)
            inside_shoulders = inside_shoulders and vertex.y > 1.25 and vertex.y < 1.55 and absf(vertex.x) > 0.15
            left = left or vertex.x < 0
            right = right or vertex.x > 0
        assert_true(inside_shoulders, "Exported team vertices exclude head, torso, forearms and knees: min=%s max=%s" % [minimum, maximum])
        assert_true(left and right, "Both shoulder shells are colorable")
