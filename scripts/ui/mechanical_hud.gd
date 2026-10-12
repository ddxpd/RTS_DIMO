extends Control
const Frame = preload("res://scripts/ui/mechanical_frame.gd")
const Minimap = preload("res://scripts/ui/tactical_minimap.gd")
const Sim = preload("res://scripts/simulation.gd")
const Card = preload("res://scripts/ui/command_card.gd")
const NAMES = Sim.EntityCatalog.NAMES
const PORTRAITS := {
    "soldier": preload("res://assets/ui/portraits/soldier.png"),
    "mobile_infantry": preload("res://assets/ui/portraits/mobile_infantry.png"),
    "harvester": preload("res://assets/ui/portraits/harvester.png"),
    "base": preload("res://assets/ui/portraits/base.png"),
    "barracks": preload("res://assets/ui/portraits/barracks.png"),
    "refinery": preload("res://assets/ui/portraits/refinery.png"),
    "bunker": preload("res://assets/ui/portraits/bunker.png")}
const ORDERS := {"idle": "待命", "move": "移动中", "attack": "攻击中", "attack_move": "攻击前进", "gather": "采矿作业"}
const FLIGHT := {"grounded": "已部署", "taking_off": "升空中", "airborne": "飞行中", "landing": "降落中"}
var host
var header: Control
var bottom: Control
var portrait: TextureRect
var portrait_frame: Control
var status_frame: Control
var command_frame: Control
var minimap: Control
var groups: HBoxContainer
var title: Label
var health: ProgressBar
var health_text: Label
var clock_label: Label
var faction: Label
var detail: Label
var queue_tiles: Array[TextureRect] = []
var queue_captions: Array[Label] = []
var roster_tiles: Dictionary = {}
var roster_labels: Dictionary = {}
var last_viewport := Vector2.ZERO
var current_kind := ""
var rally_overlay: Control
var command_signature := ""
var last_selection := ""


func label(parent: Node, text_value: String, font_size: int = 20, tint: Color = Color("#d9e5f5")) -> Label:
    var node := Label.new()
    node.text = text_value
    node.add_theme_font_size_override("font_size", font_size)
    node.add_theme_color_override("font_color", tint)
    node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    parent.add_child(node)
    return node


func box(node: Control, x: float, y: float, width: float, height: float) -> void:
    node.position = Vector2(x, y)
    node.size = Vector2(maxf(0, width), maxf(0, height))


func panel(parent: Node, blue: bool = false) -> Control:
    var panel_root := Control.new()
    panel_root.mouse_filter = Control.MOUSE_FILTER_STOP
    parent.add_child(panel_root)
    var frame := Frame.new()
    frame.accent = Color("#277fc3") if blue else Color("#495a68")
    frame.inset = blue
    panel_root.add_child(frame)
    frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    return panel_root


func bar(parent: Node) -> ProgressBar:
    var result := ProgressBar.new()
    result.show_percentage = false
    result.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var back := StyleBoxFlat.new()
    back.bg_color = Color("#263544")
    back.border_color = Color("#5b7189")
    back.set_border_width_all(1)
    var fill := StyleBoxFlat.new()
    fill.bg_color = Color("#258cef")
    result.add_theme_stylebox_override("background", back)
    result.add_theme_stylebox_override("fill", fill)
    parent.add_child(result)
    return result


func configure(owner) -> void:
    host = owner
    rally_overlay = preload("res://scripts/ui/rally_overlay.gd").new()
    host.hud.add_child(rally_overlay)
    rally_overlay.configure(host)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    header = panel(self)
    host.top_label = label(header, "IRON FRONT  //", 26)
    faction = label(header, "蓝方指挥终端", 18, Color("#94b0cf"))
    host.resource_label = label(header, "◆  矿石  0", 23, Color("#91ceff"))
    clock_label = label(header, "00:00", 23)
    var menu_button := Button.new()
    menu_button.text = "菜单  Esc"
    menu_button.pressed.connect(host._toggle_menu)
    header.add_child(menu_button)
    menu_button.name = "MenuButton"
    bottom = Control.new()
    bottom.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(bottom)
    var backing := ColorRect.new()
    backing.color = Color("#10171e")
    backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
    bottom.add_child(backing)
    backing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var map_frame := panel(bottom)
    map_frame.name = "MapFrame"
    map_frame.custom_minimum_size = Vector2(282, 224)
    box(map_frame, 8, 10, 282, 224)
    minimap = Minimap.new()
    map_frame.add_child(minimap)
    minimap.configure(host)
    box(minimap, 14, 14, 254, 196)
    host.bottom_zones.map = map_frame
    portrait_frame = panel(bottom, true)
    box(portrait_frame, 298, 26, 210, 208)
    portrait = TextureRect.new()
    portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
    portrait_frame.add_child(portrait)
    box(portrait, 14, 14, 182, 180)
    status_frame = panel(bottom)
    host.bottom_zones.status = status_frame
    title = label(status_frame, "未选择对象", 30)
    box(title, 24, 16, 590, 42)
    health = bar(status_frame)
    box(health, 114, 68, 270, 16)
    var hp_caption := label(status_frame, "生命值", 19, Color("#9fbbd7"))
    box(hp_caption, 24, 59, 90, 30)
    health_text = label(status_frame, "—", 19)
    box(health_text, 400, 59, 220, 30)
    host.selection_label = label(status_frame, "选择单位或建筑", 20)
    box(host.selection_label, 24, 96, 650, 30)
    detail = label(status_frame, "", 16, Color("#e8b767"))
    box(detail, 24, 128, 760, 24)
    host.roster_row = HBoxContainer.new()
    status_frame.add_child(host.roster_row)
    host.roster_row.add_theme_constant_override("separation", 10)
    box(host.roster_row, 24, 154, 320, 38)
    for kind: String in Sim.ACTIVE_UNIT_TYPES:
        var tile := HBoxContainer.new()
        var icon := TextureRect.new()
        icon.texture = PORTRAITS[kind]
        icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        icon.custom_minimum_size = Vector2(36, 36)
        icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
        tile.add_child(icon)
        roster_labels[kind] = label(tile, "", 18)
        roster_tiles[kind] = tile
    host.production_queue_label = label(status_frame, "", 16, Color("#9fbbd7"))
    box(host.production_queue_label, 24, 150, 120, 40)
    host.production_queue_row = HBoxContainer.new()
    status_frame.add_child(host.production_queue_row)
    host.production_queue_row.add_theme_constant_override("separation", 6)
    box(host.production_queue_row, 146, 151, 240, 40)
    for index in range(5):
        var tile := TextureRect.new()
        tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        tile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        tile.custom_minimum_size = Vector2(38, 38)
        tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
        host.production_queue_row.add_child(tile)
        queue_tiles.append(tile)
        var caption := label(tile, "", 12, Color("#8cb3d7"))
        caption.position = Vector2(14, 9)
        queue_captions.append(caption)
    host.production_bar = bar(status_frame)
    box(host.production_bar, 390, 166, 150, 12)
    groups = HBoxContainer.new()
    groups.add_theme_constant_override("separation", 6)
    bottom.add_child(groups)
    box(groups, 528, 0, 450, 26)
    for i in range(9):
        var button := Button.new()
        button.text = str(i + 1)
        button.custom_minimum_size = Vector2(42, 24)
        button.add_theme_font_size_override("font_size", 15)
        button.pressed.connect(host._control_group_key.bind(i + 1, false, false))
        groups.add_child(button)
        host.group_cards.append(button)
    command_frame = panel(bottom)
    host.bottom_zones.command = command_frame
    host.action_grid = GridContainer.new()
    host.action_grid.columns = 3
    host.action_grid.add_theme_constant_override("h_separation", 9)
    host.action_grid.add_theme_constant_override("v_separation", 8)
    command_frame.add_child(host.action_grid)
    for index in range(8):
        var button := Card.new()
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.size_flags_vertical = Control.SIZE_EXPAND_FILL
        button.pressed.connect(host._action_clicked.bind(index))
        host.action_grid.add_child(button)
        host.action_buttons.append(button)
    host.message_label = label(bottom, "", 15, Color("#95aabf"))
    box(host.message_label, 306, 235, 1500, 25)
    var brand := label(bottom, "IRON FRONT  /  战术态势", 13, Color("#71889e"))
    box(brand, 26, 237, 264, 20)
    layout()


func layout() -> void:
    var viewport := get_viewport().get_visible_rect().size
    var factor := minf(viewport.x / 1920.0, viewport.y / 1080.0)
    scale = Vector2.ONE * maxf(0.25, factor)
    size = viewport / scale
    last_viewport = viewport
    box(header, 0, 0, size.x, 52)
    box(host.top_label, 24, 8, 290, 35)
    box(faction, 330, 10, 250, 30)
    box(host.resource_label, size.x - 550, 9, 245, 34)
    box(clock_label, size.x - 282, 9, 112, 34)
    box(header.get_node("MenuButton"), size.x - 152, 10, 126, 32)
    box(bottom, 0, size.y - 260, size.x, 260)
    box(status_frame, 516, 26, size.x - 1032, 208)
    box(command_frame, size.x - 508, 26, 500, 208)
    box(host.action_grid, 16, 16, 468, 176)
    host.message_label.size.x = size.x - 325
    title.size.x = status_frame.size.x - 48
    host.selection_label.size.x = status_frame.size.x - 48
    detail.size.x = status_frame.size.x - 48


func playfield_rect() -> Rect2:
    return Rect2(Vector2(0, 52 * scale.y), Vector2(last_viewport.x, maxf(0, last_viewport.y - 312 * scale.y)))


func arrange_commands() -> void:
    var buttons: Array = []
    for button: Button in host.action_buttons:
        button.visible = not button.action_id.is_empty()
        if button.visible:
            buttons.append(button)
    var order := ["move", "attack", "stop", "gather", "mobile_infantry", "takeoff", "deploy", "harvester", "rally", "cancel", "clear_rally", "barracks", "refinery", "bunker", "base"]
    buttons.sort_custom(func(a, b): return order.find(a.action_id) < order.find(b.action_id))
    var signature := ""
    for button: Button in buttons:
        signature += button.action_id + "/"
    if signature == command_signature:
        return
    command_signature = signature
    for index in range(buttons.size()):
        host.action_grid.move_child(buttons[index], index)
        buttons[index].custom_minimum_size = Vector2(150, 176 if buttons.size() <= 3 else 84)
    host.action_grid.columns = maxi(1, mini(3, buttons.size()))
    # Containers grow automatically, but do not shrink after a previous tall row.
    host.action_grid.set_deferred("size", Vector2(468, 176))


func refresh() -> void:
    if last_viewport != get_viewport().get_visible_rect().size:
        layout()
    visible = host.active
    if not host.active:
        return
    faction.text = "蓝方指挥终端" if host.local_slot == 1 else ("红方指挥终端" if host.local_slot == 2 else "观战终端")
    host.resource_label.text = "◆  矿石  %d" % int(host.sim.money.get(host.local_slot, 0))
    clock_label.text = "%02d:%02d" % [host.sim.frame / (Sim.TICK * 60), (host.sim.frame / Sim.TICK) % 60]
    var entity: Dictionary = {}
    var counts := {}
    var building := false
    for id: int in host.selected_units:
        if host.sim.units.has(id):
            var unit: Dictionary = host.sim.units[id]
            if unit.hp <= 0:
                continue
            if entity.is_empty():
                entity = unit
            counts[unit.type] = int(counts.get(unit.type, 0)) + 1
    if entity.is_empty() and host.sim.buildings.has(host.selected_building) and host.sim.buildings[host.selected_building].hp > 0:
        entity = host.sim.buildings[host.active_building_id()]
        building = true
    current_kind = str(entity.get("type", ""))
    portrait.texture = PORTRAITS.get(current_kind)
    title.text = NAMES.get(current_kind, "未选择对象")
    detail.text = ""
    host.selection_label.text = "选择单位或建筑以查看状态"
    health.value = 0
    health_text.text = "—"
    host.production_queue_row.visible = building
    host.production_queue_label.visible = building
    host.production_bar.visible = false
    host.production_queue_label.text = ""
    host.roster_row.visible = not building and counts.size() > 0
    for kind: String in roster_tiles:
        var tile: Control = roster_tiles[kind]
        if counts.has(kind):
            if tile.get_parent() == null:
                host.roster_row.add_child(tile)
            roster_labels[kind].text = "×%d" % counts[kind]
        elif tile.get_parent() != null:
            host.roster_row.remove_child(tile)
    for i in range(5):
        queue_tiles[i].texture = null
        queue_tiles[i].tooltip_text = ""
        queue_captions[i].text = str(i + 1)
    if not entity.is_empty():
        var stats: Dictionary = Sim.BUILD_TYPES[current_kind] if building else Sim.UNIT_TYPES[current_kind]
        health.max_value = stats.hp
        health.value = entity.hp
        health_text.text = "%d / %d" % [entity.hp, stats.hp]
        if building:
            host.selection_label.text = "施工中 · %.1f 秒" % (float(entity.remaining) / Sim.TICK) if entity.remaining > 0 else "已部署"
            if current_kind == "barracks" and entity.remaining <= 0:
                host.selection_label.text = FLIGHT.get(Sim.BarracksFlight.state(entity), "状态更新中")
                detail.text = str(entity.flight.error)
            if current_kind in ["barracks", "refinery"] and detail.text.is_empty():
                detail.text = "右键地面设置集结点" if Sim.BarracksFlight.state(entity) == "grounded" else "右键飞行 · D 选择降落位置"
            if host.selected_buildings.size() > 1:
                title.text += "  [%d/%d]" % [host.building_tab_index + 1, host.selected_buildings.size()]
                detail.text += "  · Tab 切换建筑"
            host.production_queue_row.visible = current_kind in ["barracks", "refinery"]
            host.production_queue_label.text = "队列 %d / 5" % entity.queue.size() if not entity.queue.is_empty() else "队列空闲"
            host.production_queue_label.visible = host.production_queue_row.visible
            for i in range(mini(5, entity.queue.size())):
                var job: Dictionary = entity.queue[i]
                queue_tiles[i].texture = PORTRAITS.get(job.type)
                queue_tiles[i].tooltip_text = "%s · %.1f 秒" % [NAMES.get(job.type, job.type), float(job.remaining) / Sim.TICK]
                queue_captions[i].text = ""
            if not entity.queue.is_empty():
                var job: Dictionary = entity.queue[0]
                host.production_bar.max_value = Sim.UNIT_TYPES[job.type].time
                host.production_bar.value = Sim.UNIT_TYPES[job.type].time - int(job.remaining)
                host.production_bar.visible = true
                if job.remaining == 0:
                    detail.text = "出口堵塞 · 请移开附近单位"
            if host.deploy_building >= 0:
                var reason: String = host.visual_sync.deployment_preview_error
                detail.text = "选择降落位置" if reason.is_empty() else reason
            if current_kind in ["barracks", "refinery"]:
                var rally_text: String = {"none": "未设置", "ground": "地面集结", "ore": "晶矿采集"}.get(entity.rally_mode, "未设置")
                detail.text += "  · 集结点：" + rally_text
        else:
            host.selection_label.text = ORDERS.get(str(entity.order), str(entity.order))
            if counts.values().reduce(func(a, b): return a + b, 0) > 1:
                title.text = "作战编队  · %d 单位" % host.selected_units.size()
                detail.text = "生命值与状态显示当前首个单位"
            if current_kind == "harvester":
                detail.text = "矿仓 %d / 60" % entity.cargo
                if entity.has("mining"):
                    host.selection_label.text = {"wait": "等待采矿名额", "approach": "前往采集位置", "work": "采集中", "exit": "离开作业区"}.get(entity.mining.phase, "采矿作业")
                    var mining_counts: Vector2i = Sim.MiningSystem.counts(host.sim, int(entity.ore))
                    detail.text += "  · 作业/预约 %d/5 · 等待 %d" % [mining_counts.x, mining_counts.y]
                if entity.has("dock"):
                    detail.text += "  · " + str({"wait": "等待泊位", "approach": "前往入口", "enter": "进入卸矿", "exit": "退出泊位", "leave": "离站"}.get(entity.dock.phase, "卸矿作业"))
    if entity.is_empty() and host.sim.ores.has(host.selected_ore):
        var ore: Dictionary = host.sim.ores[host.selected_ore]
        if ore.amount > 0 and host.sim.can_see(host.local_slot, ore.pos):
            var tally: Vector2i = Sim.MiningSystem.counts(host.sim, host.selected_ore)
            title.text = "晶矿"
            host.selection_label.text = "作业/预约：%d/5 · 等待：%d" % [tally.x, tally.y]
            detail.text = "剩余矿石 %d · 满额时仅在30格内自动换矿" % ore.amount
        else:
            host.selected_ore = -1
    for i in range(host.group_cards.size()):
        var button: Button = host.group_cards[i]
        var group: Dictionary = host.control_groups.get(i + 1, {})
        var count: int = group.get("units", []).size() + group.get("buildings", []).size()
        button.text = "%d%s" % [i + 1, " ·" if count else ""]
        button.modulate = Color.WHITE if count else Color("#74889e")
        var kind := ""
        if not group.get("units", []).is_empty():
            kind = str(host.sim.units.get(group.units[0], {}).get("type", ""))
        elif not group.get("buildings", []).is_empty():
            kind = str(host.sim.buildings.get(group.buildings[0], {}).get("type", ""))
        button.tooltip_text = "编队 %d · %s · %d 对象\nCtrl+数字 设置 / Shift+数字 添加" % [i + 1, NAMES.get(kind, "空"), count]
    host.message_label.text = host.feedback if host.feedback_time > 0 else "左键选择  /  右键下令  /  Ctrl+数字编队  /  Esc 取消或菜单"
    host.info_label.text = title.text + "\n" + host.selection_label.text + "\n" + detail.text
    host.queue_label.text = host.production_queue_label.text


func _exit_tree() -> void:
    for tile: Control in roster_tiles.values():
        if tile.get_parent() == null:
            tile.free()
