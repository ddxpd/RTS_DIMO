extends PanelContainer
## Menu-owned settings; never sends gameplay commands.
var host
var recording := ""
var rows := {}
var status: Label
var tabs: TabContainer
var heading: Label


func configure(owner) -> void:
    host = owner
    name = "Settings"
    visible = false
    var body := VBoxContainer.new()
    body.add_theme_constant_override("separation", 12)
    theme = Theme.new()
    var margin := MarginContainer.new()
    for side in ["left", "top", "right", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 16)
    add_child(margin)
    margin.add_child(body)
    heading = Label.new()
    heading.text = "设置"
    body.add_child(heading)
    tabs = TabContainer.new()
    tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body.add_child(tabs)
    var general := page("游戏通用")
    var caption := Label.new()
    caption.text = "镜头移动速度（边缘滚屏 / 方向键）"
    general.add_child(caption)
    host.camera_speed_slider = HSlider.new()
    host.camera_speed_slider.min_value = 0.5
    host.camera_speed_slider.max_value = 3.0
    host.camera_speed_slider.step = 0.1
    host.camera_speed_slider.value = host.camera_speed_multiplier
    host.camera_speed_slider.custom_minimum_size = Vector2(180, 36)
    host.camera_speed_slider.value_changed.connect(host._camera_speed_changed)
    general.add_child(host.camera_speed_slider)
    host.camera_speed_value_label = Label.new()
    general.add_child(host.camera_speed_value_label)
    host.camera_speed_value_label.text = "%.1fx" % host.camera_speed_multiplier
    var hint := Label.new()
    hint.text = "远近缩放保持近似屏幕速度。中键拖动跟随鼠标，不受此倍率影响。"
    hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    general.add_child(hint)
    var keys := page("按键设置")
    var info := Label.new()
    info.text = "点击当前按键后输入新键；支持 Ctrl / Shift / Alt。Esc 取消录制，始终可用于返回。鼠标操作保持不变。"
    info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    keys.add_child(info)
    for action: String in host.key_bindings.defaults:
        var row := HBoxContainer.new()
        keys.add_child(row)
        var label := Label.new()
        label.text = host.key_bindings.titles[action]
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(label)
        var key := Button.new()
        key.custom_minimum_size.x = 140
        key.pressed.connect(func(): begin_recording(action))
        row.add_child(key)
        var default_label := Label.new()
        default_label.text = "默认 " + host.key_bindings.label(action, true)
        default_label.custom_minimum_size.x = 140
        row.add_child(default_label)
        var restore := Button.new()
        restore.text = "恢复默认"
        restore.pressed.connect(func():
            recording = ""
            status.text = host.key_bindings.rebind(action, host.key_bindings.defaults[action])
            refresh())
        row.add_child(restore)
        rows[action] = key
    var all_defaults := Button.new()
    all_defaults.text = "恢复全部默认按键"
    all_defaults.pressed.connect(func():
        recording = ""
        status.text = host.key_bindings.reset_all()
        refresh())
    keys.add_child(all_defaults)
    status = Label.new()
    status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    body.add_child(status)
    var back := Button.new()
    back.text = "返回菜单"
    back.pressed.connect(close)
    body.add_child(back)
    host.key_bindings.changed.connect(refresh)
    get_viewport().size_changed.connect(resize_panel)
    resize_panel()
    refresh()


func page(title: String) -> VBoxContainer:
    var scroll := ScrollContainer.new()
    scroll.name = title
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    tabs.add_child(scroll)
    var content := VBoxContainer.new()
    content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    content.add_theme_constant_override("separation", 10)
    scroll.add_child(content)
    return content


func resize_panel() -> void:
    var viewport_size := get_viewport_rect().size
    # Canvas stretch keeps logical 1920px coordinates even in a small window.
    var ui_scale := clampf(viewport_size.x / maxf(1, get_window().size.x), 1.0, 1.75)
    theme.default_font_size = roundi(18 * ui_scale)
    heading.add_theme_font_size_override("font_size", roundi(26 * ui_scale))
    size = Vector2(minf(880 * ui_scale, viewport_size.x - 32), minf(760 * ui_scale, viewport_size.y - 32))
    position = (viewport_size - size) * 0.5


func open() -> void:
    host.menu_visible = true
    host.menu.hide()
    show()
    host.cursor_controller.update_mouse_mode()
    status.text = host.key_bindings.load_error
    refresh()


func close() -> void:
    recording = ""
    hide()
    host.menu.show()
    get_viewport().gui_release_focus()


func begin_recording(action: String) -> void:
    recording = action
    status.text = "请为「%s」按下新键，Esc 取消。" % host.key_bindings.titles[action]
    refresh()


func accept_key(event: InputEventKey) -> void:
    if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
        recording = ""
        status.text = "已取消改键。"
    else:
        var error: String = host.key_bindings.rebind(recording, host.key_bindings.chord(event))
        status.text = error if not error.is_empty() else "已保存。"
        if error.is_empty():
            recording = ""
    refresh()


func refresh() -> void:
    for action: String in rows:
        rows[action].text = "请按键…" if action == recording else host.key_bindings.label(action)
        rows[action].tooltip_text = "默认：" + host.key_bindings.label(action, true)
    if host.hud_controller != null and host.hud_controller.view != null:
        host.hud_controller._refresh_command_cards()
