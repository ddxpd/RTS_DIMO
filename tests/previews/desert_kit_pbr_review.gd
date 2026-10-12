extends "res://tests/previews/desert_kit_review.gd"

const PBR = preload("res://tests/helpers/desert_kit_pbr.gd")
var realistic: RefCounted
var report: Dictionary = {}


func _ready() -> void:
    get_viewport().msaa_3d = Viewport.MSAA_4X
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
    catalog_data = kit.catalog()
    kit.verify()
    _ui()
    _deliver_assets()
    run_review.call_deferred()


func clear_cards() -> void:
    cards.clear()
    for child in pane.get_children():
        pane.remove_child(child)
        child.queue_free()


func capture(name_value: String) -> void:
    for frame in range(12):
        await get_tree().process_frame
    await RenderingServer.frame_post_draw
    var error := get_viewport().get_texture().get_image().save_png(OUT + name_value + ".png")
    if error != OK:
        kit.failures.append("Capture " + name_value)
    print("DESERT_PBR_CAPTURE ", name_value)


func sample_card(title: String, material_on: bool, distance: float, focus: Vector3) -> Dictionary:
    realistic.textured = material_on
    var card := _card(title, "高差128 · 净宽256 · 坡长256 · 仅审阅模型", distance, focus)
    card.camera.position = focus + Vector3(0.33, 0.72, -0.94).normalized() * distance
    card.camera.look_at(focus)
    var sample_node: Node3D = realistic.sample()
    card.world.add_child(sample_node)
    _reference(card.world, Vector3(215, 128, 160), "barracks")
    _reference(card.world, Vector3(-55, 128, 35), "mobile_infantry")
    _reference(card.world, Vector3(40, 0, -305), "mobile_infantry")
    return card


func run_review() -> void:
    capturing = true
    # Refresh the 12-part catalogue and the highland/quarry assembly views.
    for index in range(5):
        show_mode(index)
        await capture(["01-components", "02-height-comparison", "03-width-comparison", "04-length-comparison", "05-assembly"][index])
    clear_cards()
    heading.text = "短坡比例对照 / 相同宽度、高差与相机"
    description.text = "坡长512 → 256，占地减少50%；坡脚32 + 主体192 + 坡顶32。"
    for length_value in [512.0, 256.0]:
        var card := _card("原长坡512" if length_value == 512 else "新短坡256", "高差128 / 净宽256", 1750, Vector3(0, 64, 0))
        _ground(card.world, Vector2(1200, 1500), Vector3(-600, -2, -850))
        kit.place(card.world, kit.platform(128, 256, length_value), Vector3.ZERO)
        _platform_refs(card.world, 128)
    await capture("v2-01-short-ramp-comparison")
    realistic = PBR.new()
    realistic.initialize()
    heading.text = "正在制作共享沙地、岩石与碎石贴图"
    await get_tree().process_frame
    realistic.prepare_textures()
    realistic.textured = true
    var sample_node: Node3D = realistic.sample()
    realistic.export_asset(sample_node, "v2-realistic-short-ramp-sample")
    var export_parts := {"v2-cliff-straight": realistic.cliff(), "v2-ramp-toe": realistic.ramp_piece(256, 256, 128, 0, 0.125, "Toe"), "v2-ramp-run": realistic.ramp_piece(256, 256, 128, 0.125, 0.875, "Run"), "v2-ramp-crest": realistic.ramp_piece(256, 256, 128, 0.875, 1, "Crest"), "v2-sand-flat": realistic.flat(256, 256), "v2-plateau-top": realistic.plateau_tile(), "v2-rubble-stone": realistic.stone(Vector3(40, 20, 32), 550)}
    var parts: Array[Dictionary] = []
    for name_value: String in export_parts:
        var item: Node3D = export_parts[name_value]
        realistic.export_asset(item, name_value)
        parts.append({"file": name_value + ".glb", "triangles": realistic.triangles(item)})
        item.free()
    var total_triangles: int = realistic.triangles(sample_node)
    sample_node.free()
    # Sockets and cross-piece shading sample a common analytic surface.
    var joint_checks := verify_mesh_joints()
    for t in [0.0, 0.125, 0.875, 1.0]:
        for x in [0.0, 64.0, 128.0, 192.0, 256.0]:
            var point: Vector3 = realistic.slope_point(x, t, 256, 256, 128)
            joint_checks += 1
            if not point.is_finite() or absf(point.z - t * 256) > 0.001:
                realistic.failures.append("Invalid slope socket")
    for x in [0.0, 256.0]:
        for band in range(8):
            var point: Vector3 = realistic.cliff_point(x, band, 256, 128)
            var section: Vector2 = realistic.profile(128)[band]
            joint_checks += 1
            if point.distance_to(Vector3(x, section.x, -section.y)) > 0.001:
                realistic.failures.append("Cliff socket moved")
    for i in range(33):
        var cliff_edge: Vector3 = realistic.cliff_point(i * 8, 7, 256, 128) + Vector3(-384, 0, 0)
        var top_edge: Vector3 = realistic.plateau_point(i * 8 - 384, 0)
        joint_checks += 1
        if cliff_edge.distance_to(top_edge) > 0.001:
            realistic.failures.append("Natural cliff/top seam mismatch")
    clear_cards()
    heading.text = "同光照对照 / 自然轮廓与 PBR 表面"
    description.text = "左：同一网格纯色；右：沙地与岩石2K、碎石1K，颜色 + 法线 + ORM。"
    footer.text = "局部写实样板 · 真实网格实机渲染 · 坡道不可建造 · 尚未接入导航或生产地图"
    sample_card("同网格 / 纯色", false, 1530, Vector3(0, 60, -5))
    sample_card("同网格 / 完整材质", true, 1530, Vector3(0, 60, -5))
    await capture("v2-02-material-comparison")
    clear_cards()
    heading.text = "荒漠短坡 / 游戏俯视距离"
    description.text = "可通行坡面与岩质坡肩分离，坡脚碎石保持在主要通行区域之外。"
    sample_card("短坡局部样板", true, 1360, Vector3(0, 60, -10))
    await capture("v2-03-game-view")
    clear_cards()
    heading.text = "岩层、坡肩与地表细节"
    description.text = "大尺度轮廓由网格塑造；细小凹坑与岩层由法线贴图表现。"
    sample_card("近景检查", true, 900, Vector3(-95, 60, -80))
    await capture("v2-04-closeup")
    for z in [-224.0, -32.0]:
        var y: float = realistic.ramp_height((z + 256) / 256, 128, 256) + 1
        _line(cards[0].world, PackedVector3Array([Vector3(-128, y, z), Vector3(128, y, z)]), Color("#58bcb3"))
    heading.text = "三段接缝检查 / 辅助线仅用于审阅"
    await capture("v2-05-seam-check")
    report = {"stage": "局部材质与几何样板，非完整地图", "ramp": {"length": 256, "width": 256, "height": 128, "toe": 32, "run": 192, "crest": 32, "buildable": false}, "triangles_sample": total_triangles, "material_count": 3, "textures": realistic.texture_report, "parts": parts, "checks": kit.checks + realistic.checks + joint_checks, "failures": kit.failures + realistic.failures, "minimum_hardware_tested": false, "limits": ["无碰撞/寻路", "未制作LOD", "未扩展整套转角写实材质", "共享贴图GLB内嵌；单独导出文件会重复保存图像", "未压缩RGB含mip约108MiB；实际GPU格式待生产导入配置"]}
    var file := FileAccess.open(OUT + "v2-sample-manifest.json", FileAccess.WRITE)
    file.store_string(JSON.stringify(report, "  "))
    print("DESERT_PBR_REVIEW ", report)
    capturing = false


func verify_mesh_joints() -> int:
    var checks := 0
    var previous: Dictionary = {}
    for interval in [[0.0, 0.125], [0.125, 0.875], [0.875, 1.0]]:
        var mesh_root: Node3D = realistic.ramp_piece(256, 256, 128, interval[0], interval[1], "Verify")
        var arrays: Array = mesh_root.get_child(0).mesh.surface_get_arrays(0)
        var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
        var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
        for i in range(vertices.size()):
            if absf(vertices[i].z - interval[0] * 256) < 0.001 and not previous.is_empty():
                var prior: Array = previous.get(roundi(vertices[i].x), [])
                checks += 1
                if prior.is_empty() or vertices[i].distance_to(prior[0]) > 0.001 or normals[i].distance_to(prior[1]) > 0.001 or uvs[i].distance_to(prior[2]) > 0.001:
                    realistic.failures.append("Mesh position/normal/UV seam mismatch")
        previous.clear()
        for i in range(vertices.size()):
            if absf(vertices[i].z - interval[1] * 256) < 0.001:
                previous[roundi(vertices[i].x)] = [vertices[i], normals[i], uvs[i]]
        checks += 1
        if previous.size() != 33:
            realistic.failures.append("Missing ramp socket vertices")
        mesh_root.free()
    return checks
