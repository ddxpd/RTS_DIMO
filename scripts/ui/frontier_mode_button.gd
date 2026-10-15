extends Button
## Native button input with a separate decorative layer; shaders never intercept input.
const BACKPLATE = preload("res://assets/ui/frontier/mode_button.gdshader")
var surface: ColorRect
var arrow: Label
var transition: Tween
var highlight := 0.0:
    set(value):
        highlight = value
        if surface != null:
            surface.material.set_shader_parameter("highlight", value)
        if arrow != null:
            arrow.offset_left = -66 + value * 5
            arrow.offset_right = -26 + value * 5
var depression := 0.0:
    set(value):
        depression = value
        if surface != null:
            surface.material.set_shader_parameter("depression", value)

func configure(caption: String, artwork: Texture2D, callback: Callable) -> void:
    custom_minimum_size = Vector2(0, 166)
    mouse_default_cursor_shape = Control.CURSOR_ARROW
    tooltip_text = caption
    for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
        add_theme_stylebox_override(state, StyleBoxEmpty.new())
    surface = ColorRect.new()
    surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
    surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var material := ShaderMaterial.new()
    material.shader = BACKPLATE
    material.set_shader_parameter("artwork", artwork)
    surface.material = material
    add_child(surface)
    var title := Label.new()
    title.text = caption
    title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    title.offset_left = 34
    title.offset_right = -72
    title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 32)
    title.add_theme_color_override("font_color", Color("#def6ff"))
    title.add_theme_color_override("font_shadow_color", Color(0, 0.025, 0.05, 0.9))
    title.add_theme_constant_override("shadow_offset_y", 2)
    title.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(title)
    arrow = Label.new()
    arrow.text = "›"
    arrow.anchor_left = 1.0
    arrow.anchor_right = 1.0
    arrow.anchor_bottom = 1.0
    arrow.offset_left = -66
    arrow.offset_right = -26
    arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    arrow.add_theme_font_size_override("font_size", 58)
    arrow.add_theme_color_override("font_color", Color("#a2e8ff"))
    arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(arrow)
    resized.connect(func(): material.set_shader_parameter("panel_size", size))
    mouse_entered.connect(_animate)
    mouse_exited.connect(_animate)
    focus_entered.connect(_animate)
    focus_exited.connect(_animate)
    button_down.connect(func(): depression = 1.0)
    button_up.connect(func(): depression = 0.0)
    visibility_changed.connect(_reset_visual)
    pressed.connect(callback)

func _animate() -> void:
    if not is_inside_tree():
        return
    if transition != null:
        transition.kill()
    transition = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    transition.tween_property(self, "highlight", 1.0 if is_hovered() or has_focus() else 0.0, 0.15)

func _reset_visual() -> void:
    if not is_visible_in_tree():
        if transition != null:
            transition.kill()
        highlight = 0.0
        depression = 0.0

func _has_point(point: Vector2) -> bool:
    var half_size := size * 0.5 - Vector2(10, 10)
    var q := (point - size * 0.5).abs()
    return q.x <= half_size.x and q.y <= half_size.y and q.x + q.y <= half_size.x + half_size.y - 11.0
