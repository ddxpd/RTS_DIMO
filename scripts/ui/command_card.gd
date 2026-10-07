extends Button
## Persistent command tile; child controls never consume pointer events.
const Simulation = preload("res://scripts/simulation.gd")
const ICONS := {
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
const TITLES := {
    "stop": "Stop", "move": "Move", "attack": "Attack", "gather": "Gather",
    "soldier": "Train soldier", "harvester": "Build miner", "cancel": "Cancel production",
    "barracks": "Build barracks", "refinery": "Build refinery", "bunker": "Build bunker",
    "base": "Build base", "takeoff": "Lift off", "deploy": "Deploy"
}
const HELP := {
    "stop": "Stop the selected units or flying barracks.",
    "move": "Click this button, then left-click a destination. Right-click ground to move directly.",
    "attack": "Toggle attack targeting, then left-click an enemy or ground.",
    "gather": "Click this button, then left-click ore. Right-click ore to gather directly.",
    "soldier": "Add a soldier to this barracks' production queue.",
    "harvester": "Add a miner to this refinery's production queue.",
    "cancel": "Cancel the last queued unit and refund its cost.",
    "barracks": "Choose a location for a barracks.",
    "refinery": "Choose a location for a refinery.",
    "bunker": "Choose a location for a bunker.",
    "base": "Choose a location for a base.",
    "takeoff": "Lift this barracks into the air. Requires completed construction and an empty queue.",
    "deploy": "Choose a clear landing site for this flying barracks."
}

var action_id := ""
var active := false
var glyph: TextureRect
var hotkey: Label
var normal_style: StyleBoxFlat
var active_style: StyleBoxFlat


func _init() -> void:
    custom_minimum_size = Vector2(100, 42)
    mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    disabled = true
    normal_style = _style(Color("#24363d"), Color("#59766f"))
    active_style = _style(Color("#314e4b"), Color("#e5ce81"))
    add_theme_stylebox_override("normal", normal_style)
    add_theme_stylebox_override("hover", _style(Color("#36514f"), Color("#b9d7cc")))
    add_theme_stylebox_override("pressed", _style(Color("#152d31"), Color("#e5ce81")))
    add_theme_stylebox_override("disabled", _style(Color("#19282e"), Color("#35474b")))
    glyph = TextureRect.new()
    glyph.name = "Glyph"
    glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(glyph)
    glyph.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    glyph.offset_left = -16
    glyph.offset_top = -16
    glyph.offset_right = 16
    glyph.offset_bottom = 16
    hotkey = Label.new()
    hotkey.name = "Hotkey"
    hotkey.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hotkey.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    hotkey.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
    hotkey.add_theme_font_size_override("font_size", 11)
    add_child(hotkey)
    hotkey.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    hotkey.offset_left = 4
    hotkey.offset_right = -5
    hotkey.offset_bottom = -2


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
    glyph.modulate = Color.WHITE if enabled else Color(1, 1, 1, 0.3)
    hotkey.text = next_key
    hotkey.modulate = Color("#eed89b") if enabled else Color("#66716f")
    add_theme_stylebox_override("normal", active_style if active else normal_style)
    tooltip_text = ""
    if command.is_empty():
        return
    tooltip_text = str(TITLES[command])
    if Simulation.UNIT_TYPES.has(command):
        tooltip_text += " ($%d)" % int(Simulation.UNIT_TYPES[command].cost)
    elif Simulation.BUILD_TYPES.has(command):
        tooltip_text += " ($%d)" % int(Simulation.BUILD_TYPES[command].cost)
    if not key.is_empty():
        tooltip_text += " [%s]" % key
    if active:
        tooltip_text += " - ON"
    tooltip_text += "\n" + str(HELP[command])
    if not enabled:
        tooltip_text += "\nCurrently unavailable."
