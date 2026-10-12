extends "res://tests/previews/desert_kit_review.gd"
## Independent art acceptance scene, using the exact exported game meshes.

const V3 := OUT + "v3/"
var models: Dictionary = {}
var sand: StandardMaterial3D
var rock_material: StandardMaterial3D
var checks := 0
var failures: Array[String] = []
var review_stats: Dictionary = {}


func _ready() -> void:
    get_viewport().msaa_3d = Viewport.MSAA_4X
    _ui()
    # This scene has its own three review subjects, not the v2 catalogue tabs.
    var stack: VBoxContainer = heading.get_parent()
    stack.get_child(0).text = "DESERT / 岩层与风化样板 v3"
    stack.get_child(1).hide()
    footer.text = "Blender高低模烘焙 → GLB → Godot实机 | 独立美术样板，未接入正式地图"
    prepare.call_deferred()


func texture_file(path: String) -> ImageTexture:
    var image := Image.load_from_file(path)
    if image == null:
        failures.append("Missing image " + path)
        return null
    image.generate_mipmaps()
    return ImageTexture.create_from_image(image)


func read_model(path: String) -> Node3D:
    var document := GLTFDocument.new()
    var state := GLTFState.new()
    var error := document.append_from_file(path, state)
    checks += 1
    if error != OK:
        failures.append("Cannot import " + path)
        return Node3D.new()
    return document.generate_scene(state)


func assign_material(node: Node, material: Material) -> void:
    if node is MeshInstance3D:
        node.material_override = material
    for child in node.get_children():
        assign_material(child, material)


func prepare() -> void:
    capturing = true
    sand = StandardMaterial3D.new()
    sand.resource_name = "V3_Sand_Shared"
    sand.albedo_texture = texture_file(OUT + "v2_sand_basecolor.png")
    sand.normal_texture = texture_file(OUT + "v2_sand_normal.png")
    sand.normal_enabled = true
    sand.normal_scale = 0.18
    sand.roughness = 0.93
    sand.vertex_color_use_as_albedo = true
    sand.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    rock_material = StandardMaterial3D.new()
    rock_material.resource_name = "V3_Baked_Sandstone_Shared"
    rock_material.albedo_texture = texture_file(V3 + "v3_rock_basecolor.png")
    rock_material.normal_texture = texture_file(V3 + "v3_rock_normal.png")
    rock_material.normal_enabled = true
    rock_material.normal_scale = 0.38
    rock_material.roughness_texture = texture_file(V3 + "v3_rock_orm.png")
    rock_material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
    rock_material.ao_texture = rock_material.roughness_texture
    rock_material.ao_enabled = true
    rock_material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
    rock_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    for key: String in ["cliff", "rock", "rubble-a", "rubble-b", "rubble-c", "rubble-d"]:
        var node := read_model(V3 + "v3-" + key + ".glb")
        assign_material(node, rock_material)
        models[key] = node
        audit_mesh(node)
    var transition := composition()
    review_stats.triangles = kit.triangles(transition)
    export_review(transition, "v3-rock-sand-transition")
    transition.free()
    show_subject(0)
    await capture_v3("v3-01-cliff-comparison")
    show_subject(1)
    await capture_v3("v3-02-rock-closeup")
    show_subject(2)
    await capture_v3("v3-03-transition-closeup")
    show_subject(3)
    await capture_v3("v3-04-game-view")
    show_subject(4)
    await capture_v3("v3-05-normal-comparison")
    show_subject(3)
    review_stats.merge({"checks": checks, "failures": failures, "scope": "three art subjects only; no gameplay integration",
        "shared_materials": 2, "rock_atlas_resolution": 2048, "normal_source": "Blender selected-to-active high to low",
        "texture_rgb_mip_mib": 80, "minimum_hardware_tested": false,
        "limits": ["no LOD/compression/minimum-hardware test", "sand reuses v2 color+normal", "not a socket-compatible production cliff"]})
    var file := FileAccess.open(V3 + "v3-review-report.json", FileAccess.WRITE)
    file.store_string(JSON.stringify(review_stats, "  "))
    print("DESERT_V3_REVIEW ", review_stats)
    capturing = false


func clear_views() -> void:
    cards.clear()
    for child in pane.get_children():
        pane.remove_child(child)
        child.queue_free()


func view_card(title: String, distance: float, focus: Vector3, angle: Vector3 = Vector3(0.55, 0.6, 1)) -> Dictionary:
    var card := _card(title, "相同日光与天空补光 · 无离线渲染替代", distance, focus)
    card.camera.position = focus + angle.normalized() * distance
    card.camera.look_at(focus)
    for child in card.world.get_children():
        if child is WorldEnvironment:
            child.environment.background_color = Color("#e7e2d8")
            child.environment.ambient_light_color = Color("#e2e8f0")
            child.environment.ambient_light_energy = 0.42
        if child is DirectionalLight3D:
            child.rotation_degrees = Vector3(-52, -35, 0)
            child.light_color = Color("#fff1dc")
            child.light_energy = 0.8
            child.directional_shadow_max_distance = 2200
            child.shadow_bias = 0.025
    return card


func piece(key: String, point: Vector3 = Vector3.ZERO, size_scale: float = 32.0) -> Node3D:
    var root := Node3D.new()
    var node: Node3D = models[key].duplicate()
    root.add_child(node)
    node.scale = Vector3.ONE * size_scale
    root.position = point
    return root


func ground_height(x: float, z: float) -> float:
    var skirt_center := 40.0 + 8.0 * sin(x * 0.036) + 4.0 * cos(x * 0.094)
    var skirt := exp(-pow((z - skirt_center) / 27.0, 2)) * 11.0
    skirt *= smoothstep(173.0, 125.0, absf(x))
    return skirt + sin(x * 0.014 + z * 0.029) * 0.6 + cos(x * 0.032 - z * 0.011) * 0.45


func ground_patch() -> MeshInstance3D:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    surface.set_material(sand)
    for iz in range(42):
        for ix in range(58):
            for corner: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
                var x: float = (ix + corner.x) * 8.0 - 232.0
                var z: float = (iz + corner.y) * 8.0 - 105.0
                var y := ground_height(x, z)
                var normal := Vector3(ground_height(x - 0.2, z) - ground_height(x + 0.2, z), 0.4, ground_height(x, z - 0.2) - ground_height(x, z + 0.2)).normalized()
                surface.set_normal(normal)
                surface.set_uv(Vector2(x, z) / 130.0)
                var dirt := exp(-pow((z - 50) / 35.0, 2)) * smoothstep(170.0, 120.0, absf(x))
                surface.set_color(Color.WHITE.lerp(Color(0.79, 0.74, 0.64), dirt * 0.38))
                surface.add_vertex(Vector3(x, y, z))
    surface.generate_tangents()
    surface.index()
    var instance := MeshInstance3D.new()
    instance.name = "SandAccumulation"
    instance.mesh = surface.commit()
    return instance


func composition() -> Node3D:
    var root := Node3D.new()
    root.name = "RockSandTransition"
    root.add_child(ground_patch())
    root.add_child(piece("cliff"))
    var boulder := piece("rock", Vector3(162, -3, 64), 26)
    boulder.rotation.y = -0.8
    root.add_child(boulder)
    var random := RandomNumberGenerator.new()
    random.seed = 91026
    var clusters := [Vector2(-110, 57), Vector2(-32, 64), Vector2(66, 53), Vector2(125, 94)]
    for i in range(104):
        var center: Vector2 = clusters[i % clusters.size()]
        var x := clampf(random.randfn(center.x, 22), -200, 203)
        var z := clampf(random.randfn(center.y, 15), 36, 140)
        var scale_value := random.randf_range(6, 18) if i > 19 else random.randf_range(18, 32)
        var debris := piece(["rubble-a", "rubble-b", "rubble-c", "rubble-d"][i % 4], Vector3(x, ground_height(x, z) - scale_value * 0.08, z), scale_value)
        debris.rotation = Vector3(random.randf_range(-0.2, 0.2), random.randf_range(-PI, PI), random.randf_range(-0.2, 0.2))
        root.add_child(debris)
    # Shared atlas allows the static rock cluster to render as one surface.
    var batch := SurfaceTool.new()
    batch.begin(Mesh.PRIMITIVE_TRIANGLES)
    batch.set_material(rock_material)
    for child in root.get_children():
        if child is MeshInstance3D:
            continue
        append_rock_mesh(batch, child, Transform3D.IDENTITY)
        root.remove_child(child)
        child.free()
    batch.index()
    var rocks := MeshInstance3D.new()
    rocks.name = "BatchedCliffAndDebris"
    rocks.mesh = batch.commit()
    root.add_child(rocks)
    return root


func append_rock_mesh(batch: SurfaceTool, node: Node3D, parent_transform: Transform3D) -> void:
    var transform_value := parent_transform * node.transform
    if node is MeshInstance3D:
        for surface in range(node.mesh.get_surface_count()):
            batch.append_from(node.mesh, surface, transform_value)
    for child in node.get_children():
        if child is Node3D:
            append_rock_mesh(batch, child, transform_value)


func show_subject(index: int) -> void:
    clear_views()
    match index:
        0:
            heading.text = "崖壁对照 / 从连续墙面到分层断裂"
            description.text = "两者均约256宽、128高；统一镜头与光照。v3为美术造型样板，拼接端口待后续适配。"
            var old_card := view_card("v2 · 程序起伏崖壁", 580, Vector3(0, 58, 0))
            var old := read_model(OUT + "v2-cliff-straight.glb")
            old.rotation.y = PI
            old.position.x = 128
            old_card.world.add_child(old)
            var card := view_card("v3 · 高低模烘焙岩层", 580, Vector3(0, 58, 0))
            card.world.add_child(piece("cliff"))
        1:
            heading.text = "独立岩石 / 破损棱角与层状风化"
            description.text = "连续岩体与局部侵蚀沟槽；和崖壁、四种碎石共享同一张2K岩石图集。"
            var card := view_card("近景 · 实际低模", 285, Vector3(0, 34, 0), Vector3(0.65, 0.58, 1))
            card.world.add_child(piece("rock"))
        2:
            heading.text = "岩沙交界 / 崩落碎石与积沙"
            description.text = "岩脚积沙抬升、碎石成簇且部分埋入；沙地与砂砾逐渐过渡。"
            var card := view_card("组合近景", 665, Vector3(0, 40, 38))
            card.world.add_child(composition())
        3:
            heading.text = "游戏俯视 / 岩层、轮廓与单位尺度"
            description.text = "沿用现有单位作尺度参照；画面为独立样板，不代表正式地图已替换。"
            var card := view_card("RTS距离审阅", 1030, Vector3(0, 33, 40), Vector3(.25, 1.0, 1.0))
            card.world.add_child(composition())
            _reference(card.world, Vector3(-100, 1, 174), "mobile_infantry")
            _reference(card.world, Vector3(10, 1, 173), "mobile_infantry")
        4:
            heading.text = "法线作用对照 / 相同网格、底色与光照"
            description.text = "左侧关闭法线；右侧开启高模烘焙法线。大轮廓始终由低模承担。"
            for enabled: bool in [false, true]:
                var card := view_card("开启烘焙法线" if enabled else "关闭法线", 265, Vector3(0, 36, 0))
                var node := piece("rock")
                var material := rock_material.duplicate() as StandardMaterial3D
                material.normal_enabled = enabled
                assign_material(node, material)
                card.world.add_child(node)


func capture_v3(name_value: String) -> void:
    for frame in range(14):
        await get_tree().process_frame
    await RenderingServer.frame_post_draw
    var error := get_viewport().get_texture().get_image().save_png(V3 + name_value + ".png")
    checks += 1
    if error != OK:
        failures.append("Capture " + name_value)
    print("DESERT_V3_CAPTURE ", name_value)


func audit_mesh(node: Node) -> void:
    if node is MeshInstance3D:
        for surface in range(node.mesh.get_surface_count()):
            var arrays: Array = node.mesh.surface_get_arrays(surface)
            var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
            checks += 3
            if arrays[Mesh.ARRAY_TEX_UV].size() != vertices.size():
                failures.append("Missing UV")
            if arrays[Mesh.ARRAY_NORMAL].size() != vertices.size():
                failures.append("Missing normal")
            if arrays[Mesh.ARRAY_TANGENT].size() != vertices.size() * 4:
                failures.append("Missing tangent")
            for vertex in vertices:
                checks += 1
                if not vertex.is_finite():
                    failures.append("Non-finite vertex")
    for child in node.get_children():
        audit_mesh(child)


func export_review(root: Node3D, filename: String) -> void:
    kit.mark_owners(root, root)
    var document := GLTFDocument.new()
    var state := GLTFState.new()
    var error := document.append_from_scene(root, state)
    checks += 1
    if error == OK:
        error = document.write_to_filesystem(state, V3 + filename + ".glb")
    if error != OK:
        failures.append("Export transition")
        return
    var readback := read_model(V3 + filename + ".glb")
    checks += 1
    if kit.triangles(readback) != kit.triangles(root):
        failures.append("Triangle count changed on round trip")
    readback.free()


func _exit_tree() -> void:
    for node: Node3D in models.values():
        node.free()
