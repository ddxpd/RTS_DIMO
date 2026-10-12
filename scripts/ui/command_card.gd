extends Button
## Persistent command tile; child controls never consume pointer events.
const Simulation = preload("res://scripts/simulation.gd")
const ICONS := {
    "rally": preload("res://assets/ui/commands/rally.svg"),
    "clear_rally": preload("res://assets/ui/commands/clear_rally.svg"),
    "mobile_infantry": preload("res://assets/ui/commands/mobile_infantry.svg"),
    "stop": preload("res://assets/ui/commands/stop.svg"),
    "move": preload("res://assets/ui/commands/move.svg"),
    "attack": preload("res://assets/ui/commands/attack.svg"),
    "gather": preload("res://assets/ui/commands/gather.svg"),
    "soldier": preload("res://assets/ui/commands/soldier.svg"),
    "harvester": preload("res://assets/ui/commands/harvester.svg"),
    "cancel": preload("res://assets/ui/commands/cancel.svg"),
    "barracks": preload("res://assets/ui/commands/barracks.svg"),
    "refinery": preload("res://assets/ui/commands/refinery.svg"),
    "bunker": preload("res://assets/ui/commands/bunker.svg"),
    "base": preload("res://assets/ui/commands/base.svg"),
    "takeoff": preload("res://assets/ui/commands/takeoff.svg"),
    "deploy": preload("res://assets/ui/commands/deploy.svg"),
}
const Frame = preload("res://scripts/ui/mechanical_frame.gd")
const TITLES := {
    "rally": "设置集结点", "clear_rally": "清除集结点",
    "mobile_infantry": "训练机动兵", "stop": "停止", "move": "移动", "attack": "攻击", "gather": "采矿",
    "soldier": "训练士兵", "harvester": "生产矿车", "cancel": "取消生产", "barracks": "建造兵营",
    "refinery": "卸载站", "bunker": "建造地堡", "base": "指挥基地", "takeoff": "升空", "deploy": "降落部署"
}
const HELP := {
    "rally": "左键指定位置，也可直接右键地面；卸载站可指向晶矿。",
    "clear_rally": "恢复默认生产行为，不改变已出生单位的命令。",
    "mobile_infantry": "将机动兵加入生产队列。", "stop": "停止选中的单位或飞行兵营。",
    "move": "点击后左键选择目的地；也可直接右键地面。", "attack": "进入攻击模式，再左键选择敌人或地面。",
    "gather": "点击后左键选择矿点；也可直接右键矿点。", "soldier": "将士兵加入生产队列。",
    "harvester": "将采集作业机加入卸载站生产队列。", "cancel": "取消最后一个生产任务并返还费用。",
    "barracks": "选择位置部署兵营。", "refinery": "选择位置部署矿石卸载站。", "bunker": "选择位置部署地堡。",
    "base": "选择位置部署指挥基地。", "takeoff": "兵营需施工完成且生产队列为空。", "deploy": "选择无阻挡的兵营降落位置。"
}

var action_id := ""
var active := false
var glyph: TextureRect
var hotkey: Label
var normal_style: StyleBoxFlat
var active_style: StyleBoxFlat
var caption: Label


func _init() -> void:
    custom_minimum_size = Vector2(150, 84)
    mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    disabled = true
    normal_style = _style(Color.TRANSPARENT, Color.TRANSPARENT)
    active_style = normal_style
    for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
        add_theme_stylebox_override(state, normal_style)
    glyph = TextureRect.new()
    glyph.name = "Glyph"
    glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(glyph)
    caption = Label.new()
    caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
    caption.add_theme_font_size_override("font_size", 19)
    add_child(caption)
    hotkey = Label.new()
    hotkey.name = "Hotkey"
    hotkey.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hotkey.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hotkey.add_theme_font_size_override("font_size", 14)
    add_child(hotkey)
    resized.connect(_layout)
    mouse_entered.connect(queue_redraw)
    mouse_exited.connect(queue_redraw)
    button_down.connect(queue_redraw)
    button_up.connect(queue_redraw)


func _layout() -> void:
    var large := size.y > 110
    var extent := 64.0 if large else 28.0
    glyph.position = Vector2((size.x - extent) * 0.5, 22 if large else 12)
    glyph.size = Vector2.ONE * extent
    caption.position = Vector2(9, 98 if large else 36)
    caption.size = Vector2(size.x - 18, 28 if large else 23)
    caption.add_theme_font_size_override("font_size", 22 if large else 17)
    hotkey.position = Vector2(9, size.y - (29 if large else 23))
    hotkey.size = Vector2(size.x - 18, 21 if large else 17)
    hotkey.add_theme_font_size_override("font_size", 14 if large else 12)
    queue_redraw()


func _draw() -> void:
    var color := Color("#2d80d1")
    if disabled:
        color = Color("#3b4b5d")
    elif active or is_pressed():
        color = Color("#efb451")
    elif is_hovered():
        color = Color("#87d8ff")
    Frame.plate(self, Rect2(Vector2.ZERO, size), color, true)


func _style(fill: Color, border: Color) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = fill
    box.border_color = border
    box.set_border_width_all(1)
    box.set_corner_radius_all(3)
    box.set_content_margin_all(3)
    return box


func present(command: String, enabled: bool, key: String = "", selected: bool = false) -> void:
    var next_active := selected and enabled
    var next_key := key if not command.is_empty() else ""
    # Keep hover tooltips and mouse-down state stable during per-frame HUD refresh.
    if action_id == command and disabled == not enabled and active == next_active and hotkey.text == next_key:
        return
    action_id = command
    active = next_active
    # Assigning an unchanged disabled value preserves an in-progress mouse press.
    disabled = not enabled
    glyph.texture = ICONS.get(command)
    caption.text = TITLES.get(command, "")
    caption.modulate = Color.WHITE if enabled else Color("#6a7c90")
    queue_redraw()
    glyph.modulate = Color.WHITE if enabled else Color(1, 1, 1, 0.3)
    hotkey.text = next_key
    hotkey.modulate = Color("#eed89b") if enabled else Color("#66716f")
    add_theme_stylebox_override("normal", active_style if active else normal_style)
    tooltip_text = ""
    if command.is_empty():
        return
    tooltip_text = str(TITLES[command])
    if Simulation.UNIT_TYPES.has(command):
        tooltip_text += "（矿石 $%d）" % int(Simulation.UNIT_TYPES[command].cost)
    elif Simulation.BUILD_TYPES.has(command):
        tooltip_text += "（矿石 $%d）" % int(Simulation.BUILD_TYPES[command].cost)
    if not key.is_empty():
        tooltip_text += " [%s]" % key
    if active:
        tooltip_text += " · 已激活"
    tooltip_text += "\n" + str(HELP[command])
    if not enabled:
        tooltip_text += "\n当前不可用。"
