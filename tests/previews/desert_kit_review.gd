extends Control
## Isolated, reproducible review. It never loads or rewrites a production map.

const Geometry = preload("res://tests/helpers/desert_kit_geometry.gd")
const Visual = preload("res://assets/art/entity_visual.gd")
const OUT := "res://assets/concept_art/desert_terrain_kit/"
const MODES := ["组件目录", "高差对照", "坡宽对照", "坡长对照", "拼接样板"]
var kit: RefCounted = Geometry.new()
var pane: HBoxContainer
var heading: Label
var description: Label
var footer: Label
var mode := 0
var cards: Array[Dictionary] = []
var capturing := false
var catalog_data: Array[Dictionary] = []
var saved: Array[String] = []


func _ready() -> void:
    get_viewport().msaa_3d = Viewport.MSAA_4X
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
    catalog_data = kit.catalog()
    kit.verify()
    _ui()
    _deliver_assets()
    review_all.call_deferred()


func _label(text_value: String, font_size: int, color: Color = Color("#e4e6e1")) -> Label:
    var label := Label.new()
    label.text = text_value
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    return label


func _ui() -> void:
    var background := ColorRect.new()
    background.color = Color("#172129")
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(background)
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 26)
    add_child(margin)
    var stack := VBoxContainer.new()
    stack.add_theme_constant_override("separation", 12)
    margin.add_child(stack)
    stack.add_child(_label("DESERT  /  荒漠自然地形组件  ·  短坡审阅 02", 22, Color("#d7ad68")))
    var nav := HBoxContainer.new()
    nav.add_theme_constant_override("separation", 12)
    stack.add_child(nav)
    for index in range(MODES.size()):
        var button := Button.new()
        button.text = "%d  %s" % [index + 1, MODES[index]]
        button.custom_minimum_size = Vector2(190, 42)
        button.pressed.connect(func():
            if not capturing:
                show_mode(index))
        nav.add_child(button)
    heading = _label("", 32)
    stack.add_child(heading)
    description = _label("", 18, Color("#b5c0c5"))
    stack.add_child(description)
    pane = HBoxContainer.new()
    pane.add_theme_constant_override("separation", 16)
    pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
    stack.add_child(pane)
    footer = _label("", 17, Color("#b5c0c5"))
    stack.add_child(footer)


func _card(title: String, detail: String, distance: float, focus: Vector3) -> Dictionary:
    var box := VBoxContainer.new()
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    pane.add_child(box)
    box.add_child(_label(title, 25, Color("#e5bc78")))
    box.add_child(_label(detail, 17))
    var container := SubViewportContainer.new()
    container.stretch = true
    container.size_flags_vertical = Control.SIZE_EXPAND_FILL
    box.add_child(container)
    var viewport := SubViewport.new()
    viewport.own_world_3d = true
    viewport.msaa_3d = Viewport.MSAA_4X
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    container.add_child(viewport)
    var world := Node3D.new()
    viewport.add_child(world)
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color("#e2d6c1")
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color("#e5dccc")
    environment.environment.ambient_light_energy = 0.35
    world.add_child(environment)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-55, -30, 0)
    sun.light_energy = 0.65
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 7000
    world.add_child(sun)
    var camera := Camera3D.new()
    world.add_child(camera)
    camera.fov = 38.0
    camera.near = 1.0
    camera.far = 12000.0
    camera.position = focus + Vector3(0, sin(deg_to_rad(42)), -cos(deg_to_rad(42))) * distance
    camera.look_at(focus)
    camera.current = true
    var data := {"world": world, "viewport": viewport, "camera": camera, "box": box}
    cards.append(data)
    return data


func _text3(parent: Node3D, text_value: String, point: Vector3, color: Color = Color("#292820"), font_size: int = 34) -> void:
    var label := Label3D.new()
    label.text = text_value
    label.font_size = font_size
    label.pixel_size = 1.0
    label.modulate = color
    label.outline_size = 4
    label.outline_modulate = Color("#f0e3c9")
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.no_depth_test = true
    label.position = point
    parent.add_child(label)


func _line(parent: Node3D, points: PackedVector3Array, color: Color) -> void:
    var mesh := ImmediateMesh.new()
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.albedo_color = color
    mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
    for index in range(points.size() - 1):
        mesh.surface_add_vertex(points[index])
        mesh.surface_add_vertex(points[index + 1])
    mesh.surface_end()
    var instance := MeshInstance3D.new()
    instance.mesh = mesh
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(instance)


func _reference(parent: Node3D, point: Vector3, kind: String) -> Node3D:
    var visual := Visual.new(kind, 1)
    parent.add_child(visual)
    visual.position = point
    visual.set_heading(Vector2(0, -1), true)
    visual.set_process(false)
    if kind == "mobile_infantry" and visual.mobile_motion != null:
        visual.animation_player.play("idle")
        visual.animation_player.seek(0.0, true)
        visual.animation_player.advance(0.0)
        visual.mobile_motion.skeleton.force_update_all_bone_transforms()
        preload("res://assets/art/units/mobile_infantry/mobile_infantry_weapon.gd").sync(visual.mobile_weapon)
    return visual


func _ground(world: Node3D, size: Vector2, point: Vector3) -> void:
    kit.place(world, kit.flat(size.x, size.y, Color("#d1bb94")), point)


func _platform_refs(world: Node3D, height: float) -> void:
    _reference(world, Vector3(85, height, 230), "barracks")
    _reference(world, Vector3(-110, height, 100), "mobile_infantry")
    _reference(world, Vector3(-195, 0, -225), "mobile_infantry")
    _text3(world, "兵营 128 × 96", Vector3(85, height + 145, 240), Color("#244255"), 28)


func _dimensions(world: Node3D, height: float, width: float, length: float) -> void:
    var gold := Color("#805b29")
    _line(world, PackedVector3Array([Vector3(310, 0, 16), Vector3(310, height, 16)]), gold)
    _text3(world, "H = %d" % height, Vector3(340, height / 2, 20), gold, 30)
    _line(world, PackedVector3Array([Vector3(-width / 2, 2, -length - 24), Vector3(width / 2, 2, -length - 24)]), gold)
    _text3(world, "净宽 %d" % width, Vector3(0, 8, -length - 70), gold, 28)
    _text3(world, "坡面：可通行 · 不可建造", Vector3(0, height * 0.5 + 20, -length * 0.5), Color("#835626"), 23)


func show_mode(next: int) -> void:
    mode = next
    cards.clear()
    for child in pane.get_children():
        pane.remove_child(child)
        child.queue_free()
    footer.text = "草模仅确认尺寸与拼接；颜色为区域提示，不代表最终材质。  |  32单位吸附基准  |  正式地图与玩法未修改"
    match mode:
        0:
            heading.text = "12 类基础组件  /  先确认结构，再制作风化细节"
            description.text = "原点与标准拼接边固定；岩石轮廓允许变化。坡道由坡脚、主体、坡顶三段组成。"
            var card := _card("自然地形组件目录", "尺寸单位与当前游戏一致；坡道标注为坡面高差，侧裙延伸至地面", 2050, Vector3(0, 35, 390))
            _ground(card.world, Vector2(1700, 1500), Vector3(-850, -4, -550))
            for index in range(catalog_data.size()):
                var item: Dictionary = catalog_data[index]
                var asset: Node3D = item.node.duplicate()
                var origin := Vector3(555 - (index % 4) * 370, 0, 790 - (index / 4) * 400)
                # Ramp catalog sources retain assembly coordinates; center each tile.
                var box := _bounds(asset)
                kit.place(card.world, asset, origin - Vector3(box.get_center().x, box.position.y, box.get_center().z))
                _text3(card.world, "%02d  %s" % [index + 1, item.title], origin + Vector3(0, 12, -145), Color("#292820"), 27)
                _text3(card.world, "%d × %d × %d" % [item.size.x, item.size.y, item.size.z], origin + Vector3(0, 10, -190), Color("#674b2c"), 21)
            _reference(card.world, Vector3(-780, 0, -100), "mobile_infantry")
            _reference(card.world, Vector3(780, 0, -100), "barracks")
        1, 2, 3:
            var values: Array = [[96, 128, 160], [192, 256, 320], [256, 320, 512]][mode - 1]
            heading.text = ["高差对照  /  A、B、C 三档", "坡道净宽对照  /  高差与长度固定", "坡道长度对照  /  高差与净宽固定"][mode - 1]
            description.text = ["固定高台 512 × 512、坡宽256、坡长256。人物高度68；三栏使用相同相机。", "固定高差128、坡长256。宽度按坡面净宽计，不包含两侧崖脚。", "固定高差128、净宽256。坡顶和坡脚各32，保持平滑接入。"][mode - 1]
            for index in range(3):
                var height: float = values[index] if mode == 1 else 128.0
                var width: float = values[index] if mode == 2 else 256.0
                var length: float = values[index] if mode == 3 else 256.0
                var title := "%s  %s %d" % [["A", "B", "C"][index], ["高差", "净宽", "长度"][mode - 1], values[index]]
                var detail := "高差 / 人高 = %.2f" % (height / 68.0) if mode == 1 else ("%d 格净宽" % int(width / 32) if mode == 2 else "平均坡度约 %.1f°" % rad_to_deg(atan(height / length)))
                var card := _card(title, detail, 1850, Vector3(0, 64, -20))
                _ground(card.world, Vector2(1200, 1500), Vector3(-600, -2, -850))
                kit.place(card.world, kit.platform(height, width, length), Vector3.ZERO)
                _platform_refs(card.world, height)
                _dimensions(card.world, height, width, length)
                if mode == 2:
                    for unit in range(5):
                        var x := (unit - 2) * 32.0
                        var z := -length * 0.75
                        _reference(card.world, Vector3(x, kit.ramp_height(0.25, height, length), z), "mobile_infantry")
        4:
            heading.text = "拼接样板  /  同一套崖壁与坡道，组合高台和凹地"
            description.text = "展示值：高差±128、坡宽256、坡长256。蓝绿色线为模块接缝；黄色线为坡道三段分界。"
            var card := _card("组合示例 · 短坡尺寸已确认", "只展示几何与预期用途，本轮没有接入碰撞、寻路或建造", 2400, Vector3(0, 0, 300))
            var high: Node3D = kit.platform(128, 256, 256)
            kit.place(card.world, high, Vector3(-650, 0, 0))
            # Continuous surroundings with an actual opening for the recessed floor.
            _ground(card.world, Vector2(2500, 800), Vector3(-1250, -2, -800))
            _ground(card.world, Vector2(2500, 332), Vector3(-1250, -2, 768))
            _ground(card.world, Vector2(1544, 768), Vector3(-1250, -2, 0))
            _ground(card.world, Vector2(444, 768), Vector3(806, -2, 0))
            var low: Node3D = kit.pit()
            kit.place(card.world, low, Vector3(550, 0, 0))
            _platform_refs(high, 128)
            _reference(low, Vector3(175, -128, 620), "mobile_infantry")
            _reference(low, Vector3(360, 0, 200), "barracks")
            _text3(high, "高台 +128", Vector3(0, 160, 510), Color("#244255"), 36)
            _text3(low, "凹地 -128", Vector3(0, -100, 680), Color("#244255"), 36)
            _text3(high, "平地 / 高台：预期可建造", Vector3(0, 140, 350), Color("#296257"), 26)
            _text3(low, "崖壁：不可通行", Vector3(230, 24, 430), Color("#7c382d"), 26)
            var seam := Color("#459183")
            _line(high, PackedVector3Array([Vector3(0, 129, 0), Vector3(0, 129, 512)]), seam)
            _line(high, PackedVector3Array([Vector3(-256, 129, 256), Vector3(256, 129, 256)]), seam)
            for z in [-224.0, -32.0]:
                var y: float = kit.ramp_height((z + 256) / 256, 128, 256) + 1
                _line(high, PackedVector3Array([Vector3(-128, y, z), Vector3(128, y, z)]), Color("#b68628"))
            for index in range(6):
                kit.place(high, kit.rock(Vector3(128, 96, 112), index + 10), Vector3(-350, 0, index * 100))
            kit.place(high, kit.rubble(), Vector3(300, 0, -40))
            kit.place(low, kit.rubble(), Vector3(300, 0, 510))


func _bounds(node: Node3D, transform: Transform3D = Transform3D.IDENTITY) -> AABB:
    var result := AABB()
    var first := true
    var current := transform * node.transform
    if node is MeshInstance3D:
        result = current * node.mesh.get_aabb()
        first = false
    for child in node.get_children():
        if child is Node3D:
            var box := _bounds(child, current)
            result = box if first else result.merge(box)
            first = false
    return result


func _deliver_assets() -> void:
    var list: Array[Dictionary] = []
    for item: Dictionary in catalog_data:
        kit.export_asset(item.node, item.id)
        var box := _bounds(item.node)
        list.append({"id": item.id, "名称": item.title, "标称尺寸XYZ": [item.size.x, item.size.y, item.size.z],
            "包围盒原点XYZ": [box.position.x, box.position.y, box.position.z],
            "实际包围盒尺寸XYZ": [box.size.x, box.size.y, box.size.z],
            "预期用途_未接入玩法": item.use, "草模三角面": kit.triangles(item.node), "正式LOD0三角面上限_初步": item.formal_lod0_triangle_budget})
    var high: Node3D = kit.platform(128)
    var low: Node3D = kit.pit(128)
    kit.export_asset(high, "assembled_highland_h128_w256_l256")
    kit.export_asset(low, "assembled_quarry_h128_w256_l256")
    high.free()
    low.free()
    var report := {"阶段": "256短坡尺寸已确认；基础目录仍为草模，写实局部另见v2-sample-manifest.json", "组件": list,
        "比较候选": {"高差": [96, 128, 160], "坡宽": [192, 256, 320], "坡长": [256, 320, 512]},
        "视角": {"pitch_degrees": 42, "fov_degrees": 38, "comparison_distance": 1850},
        "性能目标_未验收": {"cpu": "i5-8400", "gpu": "GTX1060 6GB", "内存暂定GB": 16, "分辨率": "1920x1080", "同屏单位": 200, "fps": 60},
        "初步贴图预算": {"共享套数": 3, "每套": "沙地/岩石/碎石各一套，BaseColor + Normal + ORM", "尺寸": "先按2048设计，碎石按1024评估", "GPU纹理上限MiB_含mip": 96, "说明": "正式贴图尚未制作，实际显存取决于导入格式；草模不计作正式性能验收"},
        "正式扩充建议": {"直线崖壁变体": 3, "内外角各": 2, "大岩块": 3, "中岩块": 3, "碎石簇": 3, "备注": "本轮只做每类一个；数量与最终尺寸需确认"},
        "geometry_checks": kit.checks, "failures": kit.failures}
    var file := FileAccess.open(OUT + "component_manifest.json", FileAccess.WRITE)
    file.store_string(JSON.stringify(report, "  "))


func review_all() -> void:
    capturing = true
    for index in range(5):
        show_mode(index)
        for frame in range(12):
            await get_tree().process_frame
        await RenderingServer.frame_post_draw
        var filename: String = ["01-components", "02-height-comparison", "03-width-comparison", "04-length-comparison", "05-assembly"][index] + ".png"
        var error := get_viewport().get_texture().get_image().save_png(OUT + filename)
        if error == OK:
            saved.append(filename)
        else:
            kit.failures.append("Capture " + filename)
    capturing = false
    show_mode(1)
    print("DESERT_KIT_REVIEW ", {"components": catalog_data.size(), "checks": kit.checks, "saved": saved, "failures": kit.failures})


func _unhandled_key_input(event: InputEvent) -> void:
    if capturing or not event is InputEventKey or not event.pressed:
        return
    if event.keycode >= KEY_1 and event.keycode <= KEY_5:
        show_mode(event.keycode - KEY_1)


func _exit_tree() -> void:
    for item in catalog_data:
        if is_instance_valid(item.node):
            item.node.free()
