extends Node
## Application lifecycle. The battlefield is instantiated only after configuration.
const Config = preload("res://scripts/runtime/match_config.gd")
const Service = preload("res://scripts/runtime/room_service.gd")
const Game = preload("res://scenes/main.tscn")
const MenuMusic = preload("res://scripts/audio/menu_music.gd")
const MENU_CURSOR = preload("res://assets/ui/frontier/menu_cursor.svg")
const MENU_CURSOR_HOTSPOT := Vector2(5, 4)
var menu_cursor_applied := false
var menu_music: Node
var service: Node
var game: Node
var root: Control
var menu: Control
var page: VBoxContainer
var notice: Label
var background: TextureRect
var cards: HBoxContainer
var mode_panel: PanelContainer
var home_modes: VBoxContainer
var home_shade: TextureRect
var commander_name: Label
var home_actions: HBoxContainer
var settings_panel: PanelContainer
var menu_visible := true
var cursor_controller: Node
var hud_controller = null
var camera_speed_multiplier := 1.8
var camera_speed_slider: HSlider
var camera_speed_value_label: Label
var key_bindings := preload("res://scripts/controllers/key_bindings.gd").new()
var config := Config.defaults(true)
var lobby := {}
var mode := "home"
var address := "127.0.0.1"
var server_port := Service.PORT
var room_input := ""
var local_pid := -1
var keep_service := true
var connecting_local := false
var local_retry := 0
var shown_result := false
var online := false
var pending_world: Dictionary = {}

func _ready() -> void:
    service = Service.new()
    service.name = "Service"
    add_child(service)
    var args := OS.get_cmdline_user_args()
    if "--dedicated" in args:
        var bind_address := "127.0.0.1"
        var port := Service.PORT
        for argument in args:
            if argument.begins_with("--bind="):
                bind_address = argument.trim_prefix("--bind=")
            if argument.begins_with("--port="):
                port = int(argument.trim_prefix("--port="))
        var status: Error = service.listen(bind_address, port)
        print("GAIA service %s:%d: %s" % [bind_address, port, error_string(status)])
        if status != OK:
            get_tree().quit(1)
        return
    menu_music = MenuMusic.new()
    menu_music.name = "MenuMusic"
    add_child(menu_music)
    cursor_controller = self
    key_bindings.load_settings()
    var saved := ConfigFile.new()
    if saved.load("user://settings.cfg") == OK:
        camera_speed_multiplier = float(saved.get_value("camera", "speed_multiplier", 1.8))
        address = str(saved.get_value("online", "address", "127.0.0.1"))
        server_port = clampi(int(saved.get_value("online", "port", Service.PORT)), 1024, 65535)
        service.nickname = str(saved.get_value("online", "nickname", "指挥官"))
    service.message.connect(_notice)
    service.connection_ready.connect(func():
        connecting_local = false
        _notice("已连接服务器，可以创建房间或输入房间码。"))
    service.connection_lost.connect(_connection_lost)
    service.lobby_changed.connect(_lobby_changed)
    service.match_started.connect(_online_start)
    service.world_received.connect(_world)
    _build_shell()
    get_window().focus_entered.connect(func(): apply_menu_cursor(true))
    _home()
    _sync_menu_music()
    get_tree().auto_accept_quit = false

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        _quit()

func _exit_tree() -> void:
    if menu_cursor_applied and DisplayServer.get_name() != "headless":
        Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)

func uses_menu_cursor() -> bool:
    return root != null and (root.visible or (game != null and game.menu_visible))

func apply_menu_cursor(force: bool = false) -> void:
    if not uses_menu_cursor() or (menu_cursor_applied and not force):
        return
    if DisplayServer.get_name() != "headless":
        Input.set_custom_mouse_cursor(MENU_CURSOR, Input.CURSOR_ARROW, MENU_CURSOR_HOTSPOT)
    menu_cursor_applied = true

func release_menu_cursor() -> void:
    if not menu_cursor_applied:
        return
    menu_cursor_applied = false
    # The battlefield may have cached the same state before the menu opened.
    if game != null and game.cursor_controller != null:
        game.cursor_controller.current_state = &""

func _build_shell() -> void:
    var canvas := CanvasLayer.new()
    canvas.layer = 50
    add_child(canvas)
    root = Control.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    canvas.add_child(root)
    root.theme = Theme.new()
    root.theme.default_font_size = 24
    background = TextureRect.new()
    background.texture = load("res://assets/ui/frontier/command_background.png")
    background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(background)
    var shade := ColorRect.new()
    shade.color = Color(0.005, 0.025, 0.055, 0.38)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(shade)
    home_shade = TextureRect.new()
    var ramp := Gradient.new()
    ramp.colors = PackedColorArray([Color(0.005, 0.025, 0.045, 0), Color(0.005, 0.025, 0.045, 0.91)])
    var fade := GradientTexture2D.new()
    fade.gradient = ramp
    fade.fill_from = Vector2.ZERO
    fade.fill_to = Vector2.RIGHT
    home_shade.texture = fade
    home_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    home_shade.anchor_left = 0.64
    home_shade.anchor_right = 1.0
    home_shade.anchor_bottom = 1.0
    home_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(home_shade)
    menu = Control.new()
    menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_child(menu)
    cards = HBoxContainer.new()
    cards.anchor_left = 0.035
    cards.anchor_right = 0.635
    cards.anchor_top = 0.79
    cards.anchor_bottom = 0.93
    cards.add_theme_constant_override("separation", 16)
    menu.add_child(cards)
    _card("简报  /  BRIEFING", "开拓边疆\n基础建设与资源采集", "res://assets/maps/desert_quarry_preview.png", func(): _article("基础作战", "开局只有主基地。选中基地建造矿石冶炼场，生产悬浮作业机采矿；建造兵营训练机动兵。\n\n右键下达移动或交互指令。Esc 打开菜单，快捷键可在设置中修改。"))
    _card("资料  /  DATABASE", "单位与建筑\n查看当前作战数值", "res://assets/maps/sample/preview.png", _encyclopedia)
    _card("更新  /  DEVLOG", "新的指挥中心\n四方对战与独立房间", "res://assets/ui/frontier/command_background.png", func(): _article("本地更新", "GAIA FRONTIER\n\n• 指挥中心与训练场配置\n• 四阵营混战与 2v2\n• 房间码、准备和独立服务端\n\n内容随游戏版本更新，无需联网。"))
    var title := Label.new()
    title.text = "GAIA FRONTIER"
    title.position = Vector2(64, 64)
    title.add_theme_font_size_override("font_size", 68)
    title.add_theme_color_override("font_color", Color("#cfedff"))
    menu.add_child(title)
    var subtitle := Label.new()
    subtitle.text = "A NEW FRONTIER  /  人类的新边疆"
    subtitle.position = Vector2(70, 154)
    subtitle.add_theme_font_size_override("font_size", 22)
    menu.add_child(subtitle)
    var panel := PanelContainer.new()
    mode_panel = panel
    panel.anchor_left = 0.66
    panel.anchor_top = 0.05
    panel.anchor_right = 0.97
    panel.anchor_bottom = 0.93
    panel.add_theme_stylebox_override("panel", _style(Color(0.015, 0.055, 0.095, 0.93)))
    menu.add_child(panel)
    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    panel.add_child(scroll)
    page = VBoxContainer.new()
    page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    page.add_theme_constant_override("separation", 16)
    scroll.add_child(page)
    notice = Label.new()
    notice.anchor_top = 0.94
    notice.anchor_bottom = 0.99
    notice.anchor_left = 0.035
    notice.anchor_right = 0.965
    notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    root.add_child(notice)
    settings_panel = preload("res://scripts/ui/settings_panel.gd").new()
    root.add_child(settings_panel)
    settings_panel.configure(self)
    home_actions = HBoxContainer.new()
    home_actions.name = "HomeActions"
    home_actions.anchor_left = 0.66
    home_actions.anchor_right = 0.97
    home_actions.anchor_top = 0.79
    home_actions.anchor_bottom = 0.93
    home_actions.alignment = BoxContainer.ALIGNMENT_END
    home_actions.add_theme_constant_override("separation", 24)
    menu.add_child(home_actions)
    _home_action("Settings", "设置", "settings", settings_panel.open)
    _home_action("Exit", "退出", "exit", _quit)
    _build_home_modes()
    get_viewport().size_changed.connect(_resize)
    _resize()

func _style(color: Color) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.border_color = Color("#398eb7")
    style.set_border_width_all(1)
    style.set_corner_radius_all(6)
    style.content_margin_left = 22
    style.content_margin_right = 22
    style.content_margin_top = 16
    style.content_margin_bottom = 16
    return style

func _resize() -> void:
    if root == null:
        return
    var scale_factor := clampf(get_viewport().get_visible_rect().size.x / maxf(get_window().size.x, 1), 1, 1.6)
    root.theme.default_font_size = roundi(24 * scale_factor)

func _clear(title: String) -> void:
    home_modes.visible = mode == "home"
    home_shade.visible = mode == "home"
    mode_panel.visible = mode != "home"
    cards.visible = mode == "home"
    home_actions.visible = mode == "home"
    mode_panel.anchor_bottom = 0.75 if mode == "home" else 0.93
    for child in page.get_children():
        page.remove_child(child)
        child.queue_free()
    var heading := Label.new()
    heading.text = title
    heading.add_theme_font_size_override("font_size", 34)
    page.add_child(heading)
    notice.text = ""

func _build_home_modes() -> void:
    home_modes = VBoxContainer.new()
    home_modes.name = "HomeModes"
    home_modes.anchor_left = 0.755
    home_modes.anchor_right = 0.98
    home_modes.anchor_top = 0.045
    home_modes.anchor_bottom = 0.69
    home_modes.add_theme_constant_override("separation", 18)
    menu.add_child(home_modes)
    var identity := PanelContainer.new()
    identity.custom_minimum_size.y = 132
    var frame := StyleBoxTexture.new()
    frame.texture = preload("res://assets/ui/frontier/action_frame.svg")
    for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
        frame.set_texture_margin(side, 14)
        frame.set_content_margin(side, 22)
    identity.add_theme_stylebox_override("panel", frame)
    home_modes.add_child(identity)
    var row := HBoxContainer.new()
    identity.add_child(row)
    var names := VBoxContainer.new()
    names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    names.alignment = BoxContainer.ALIGNMENT_CENTER
    row.add_child(names)
    var role := Label.new()
    role.text = "COMMANDER"
    role.add_theme_font_size_override("font_size", 18)
    role.add_theme_color_override("font_color", Color("#7fafcc"))
    names.add_child(role)
    commander_name = Label.new()
    commander_name.add_theme_font_size_override("font_size", 28)
    commander_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    names.add_child(commander_name)
    var insignia := TextureRect.new()
    insignia.texture = preload("res://assets/ui/frontier/commander_mark.svg")
    insignia.custom_minimum_size = Vector2(70, 70)
    insignia.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    insignia.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    insignia.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(insignia)
    var spacer := Control.new()
    spacer.custom_minimum_size.y = 14
    spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    home_modes.add_child(spacer)
    var versus := preload("res://scripts/ui/frontier_mode_button.gd").new()
    versus.name = "Multiplayer"
    versus.configure("多人对战", preload("res://assets/ui/frontier/multiplayer_banner.png"), _multiplayer)
    home_modes.add_child(versus)
    var training := preload("res://scripts/ui/frontier_mode_button.gd").new()
    training.name = "Training"
    training.configure("训练场", preload("res://assets/ui/frontier/training_banner.png"), func():
        config = Config.defaults(true)
        _training())
    home_modes.add_child(training)

func _home_action(node_name: String, caption: String, icon_name: String, callback: Callable) -> void:
    var button := Button.new()
    button.name = node_name
    button.tooltip_text = caption
    button.custom_minimum_size = Vector2(112, 120)
    button.size_flags_vertical = Control.SIZE_SHRINK_END
    for state: String in ["normal", "hover", "pressed", "focus"]:
        var style := StyleBoxTexture.new()
        style.texture = preload("res://assets/ui/frontier/action_frame.svg")
        style.texture_margin_left = 14
        style.texture_margin_right = 14
        style.texture_margin_top = 14
        style.texture_margin_bottom = 14
        style.modulate_color = Color(0.55, 0.72, 0.82) if state == "normal" else Color(1.25, 1.4, 1.5)
        if state == "pressed":
            style.modulate_color = Color(0.7, 1.1, 1.3)
        button.add_theme_stylebox_override(state, style)
    button.pressed.connect(callback)
    home_actions.add_child(button)
    var body := VBoxContainer.new()
    body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    body.alignment = BoxContainer.ALIGNMENT_CENTER
    body.add_theme_constant_override("separation", 10)
    body.mouse_filter = Control.MOUSE_FILTER_IGNORE
    button.add_child(body)
    var icon := TextureRect.new()
    icon.texture = load("res://assets/ui/frontier/%s.svg" % icon_name)
    icon.custom_minimum_size = Vector2(44, 44)
    icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    body.add_child(icon)
    var label := Label.new()
    label.text = caption
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.add_theme_font_size_override("font_size", 22)
    label.add_theme_color_override("font_color", Color("#cfedff"))
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    body.add_child(label)

func _card(title: String, text: String, texture_path: String, callback: Callable) -> void:
    var card := Button.new()
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    card.add_theme_stylebox_override("normal", _style(Color(0.01, 0.04, 0.075, 0.94)))
    card.add_theme_stylebox_override("hover", _style(Color(0.025, 0.15, 0.23, 1)))
    card.pressed.connect(callback)
    cards.add_child(card)
    var body := VBoxContainer.new()
    body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    body.offset_left = 12
    body.offset_right = -12
    body.offset_top = 8
    body.offset_bottom = -8
    body.mouse_filter = Control.MOUSE_FILTER_IGNORE
    card.add_child(body)
    var heading := Label.new()
    heading.text = title
    heading.add_theme_font_size_override("font_size", 20)
    heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
    body.add_child(heading)
    var art := TextureRect.new()
    art.texture = load(texture_path)
    art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    art.size_flags_vertical = Control.SIZE_EXPAND_FILL
    art.mouse_filter = Control.MOUSE_FILTER_IGNORE
    body.add_child(art)
    var caption := Label.new()
    caption.text = text
    caption.add_theme_font_size_override("font_size", 18)
    caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
    body.add_child(caption)

func _label(text: String) -> Label:
    var label := Label.new()
    label.text = text
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    page.add_child(label)
    return label

func _button(text: String, callback: Callable) -> Button:
    var button := Button.new()
    button.text = text
    button.custom_minimum_size.y = 64
    button.add_theme_stylebox_override("normal", _style(Color(0.025, 0.13, 0.22, 0.9)))
    button.add_theme_stylebox_override("hover", _style(Color(0.04, 0.25, 0.39, 1)))
    button.pressed.connect(callback)
    page.add_child(button)
    return button

func _home() -> void:
    key_bindings.load_settings()
    mode = "home"
    root.show()
    menu.show()
    _clear("指挥中心")
    commander_name.text = service.nickname
    update_mouse_mode()

func _article(title: String, text: String) -> void:
    mode = "article"
    _clear(title)
    _label(text)
    _button("返回主界面", _home)

func _encyclopedia() -> void:
    mode = "article"
    _clear("单位百科")
    var catalog = preload("res://scripts/definitions/entity_catalog.gd")
    for kind: String in catalog.ACTIVE_UNIT_TYPES:
        var entry: Dictionary = catalog.UNIT_TYPES[kind]
        _label("%s\n生命 %s · 费用 %s\n伤害 %s · 射程 %.2f 格\n移动速度 %.2f 格/秒 · 训练 %.1f 秒\n%s" % [catalog.NAMES[kind], entry.hp, entry.cost, entry.damage, entry.range / 32, entry.speed / 32, entry.time / 20.0, catalog.DESCRIPTIONS[kind]])
    for kind: String in catalog.BUILD_TYPES:
        var entry: Dictionary = catalog.BUILD_TYPES[kind]
        var cells: Vector2i = catalog.BUILD_CELLS[kind]
        _label("%s\n生命 %s · 费用 %s · 建造 %.1f 秒\n占地 %d × %d 格（%d × %d 世界单位）\n%s" % [catalog.NAMES[kind], entry.hp, entry.cost, entry.time / 20.0, cells.x, cells.y, int(entry.size.x), int(entry.size.y), catalog.DESCRIPTIONS[kind]])
    _button("返回主界面", _home)

func _options(values: Array, selected: int, changed: Callable) -> OptionButton:
    var option := OptionButton.new()
    for value: String in values:
        option.add_item(value)
    option.select(selected)
    option.item_selected.connect(changed)
    page.add_child(option)
    return option

func _configuration(editable: bool) -> void:
    _label("地图")
    var maps := ["frontier_four", "desert_quarry", "desert_sample"] if config.training else ["frontier_four", "desert_quarry"]
    _options(["边境四方 · 4 人", "荒漠矿区 · 2 人", "地形训练场 · 2 人"] if config.training else ["边境四方 · 4 人", "荒漠矿区 · 2 人"], maxi(0, maps.find(config.map)), func(index):
        config.map = maps[index]
        _changed()).disabled = not editable
    _label("对战方式")
    _options(["各自为战", "2v2"], int(config.mode == "2v2"), func(index):
        config.mode = "ffa" if index == 0 else "2v2"
        _changed()).disabled = not editable
    _label("所有玩家初始资金")
    _options(["3,000", "6,000", "10,000", "自定义"], [3000, 6000, 10000].find(config.funds) if config.funds in [3000, 6000, 10000] else 3, func(index):
        if index < 3:
            config.funds = [3000, 6000, 10000][index]
            _changed()).disabled = not editable
    var funds := SpinBox.new()
    funds.min_value = 1
    funds.max_value = 1000000
    funds.value = config.funds
    funds.editable = editable
    funds.value_changed.connect(func(value):
        config.funds = int(value)
        if not config.training:
            service.send("configure", config))
    page.add_child(funds)
    for i in range(4):
        var player_name: String = lobby.get("names", {}).get(i + 1, "玩家 %d" % (i + 1)) if not config.training else "玩家 %d" % (i + 1)
        _label(player_name + ("  ✓ 已准备" if lobby.get("ready", {}).get(i + 1, false) else ""))
        var values := ["human", "ai", "open", "closed"]
        var option := _options(["真人", "AI", "开放", "关闭"], values.find(config.seats[i]), func(index):
            if values[index] == "human":
                _notice("真人通过加入房间占用席位。")
                return
            config.seats[i] = values[index]
            _changed())
        option.disabled = not editable or config.seats[i] == "human"
        if config.training:
            option.set_item_disabled(0, true)
            option.set_item_disabled(2, true)
        if config.mode == "2v2":
            _options(["队伍 A", "队伍 B"], config.teams[i] - 1, func(index):
                config.teams[i] = index + 1
                _changed()).disabled = not editable

func _changed() -> void:
    if config.training:
        _training()
    else:
        service.send("configure", config)

func _training() -> void:
    mode = "training"
    lobby = {}
    _clear("训练场配置")
    _label("全图可见 · 自由练习 · 可选 AI")
    _configuration(true)
    _button("开始训练", func():
        var reason := Config.error(config, true)
        if not reason.is_empty():
            _notice(reason)
            return
        _start_game({}, 1, false))
    _button("返回主界面", _home)

func _multiplayer() -> void:
    mode = "multiplayer"
    _clear("多人对战")
    _label("服务器地址（本机为 127.0.0.1）")
    var host := LineEdit.new()
    host.text = address
    host.text_changed.connect(func(value): address = value.strip_edges())
    page.add_child(host)
    _label("UDP 端口")
    var port_entry := SpinBox.new()
    port_entry.min_value = 1024
    port_entry.max_value = 65535
    port_entry.value = server_port
    port_entry.value_changed.connect(func(value): server_port = int(value))
    page.add_child(port_entry)
    var name_entry := LineEdit.new()
    name_entry.text = service.nickname
    name_entry.placeholder_text = "指挥官昵称"
    name_entry.max_length = 24
    name_entry.text_changed.connect(func(value): service.nickname = value)
    page.add_child(name_entry)
    _button("启动本机服务并连接", _local_server)
    _button("连接服务器", _connect)
    _button("创建房间", func(): service.send("create"))
    var code := LineEdit.new()
    code.placeholder_text = "输入房间码"
    code.max_length = 8
    code.text_changed.connect(func(value): room_input = value.strip_edges())
    page.add_child(code)
    _button("加入房间", func(): service.send("join", {"code": room_input}))
    if not service.token.is_empty():
        _button("重连上一局", func(): service.send("reconnect", {"code": service.room_code, "token": service.token}))
    if local_pid > 0:
        var keep := CheckBox.new()
        keep.text = "退出游戏后保留本机服务"
        keep.button_pressed = keep_service
        keep.toggled.connect(func(value): keep_service = value)
        page.add_child(keep)
    _button("返回主界面", _home)

func _connect() -> void:
    _save_settings()
    var status: Error = service.connect_to(address, server_port)
    _notice("正在连接…" if status == OK else error_string(status))

func _local_server() -> void:
    address = "127.0.0.1"
    server_port = Service.PORT
    if local_pid <= 0 or not OS.is_process_running(local_pid):
        var args := PackedStringArray(["--headless"])
        if OS.has_feature("editor"):
            args.append_array(["--path", ProjectSettings.globalize_path("res://")])
        args.append_array(["--", "--dedicated", "--bind=127.0.0.1"])
        local_pid = OS.create_process(OS.get_executable_path(), args, false)
        if local_pid <= 0:
            _notice("本机服务启动失败。")
            return
    connecting_local = true
    local_retry = 0
    _multiplayer()
    _notice("正在启动本机服务…")
    await get_tree().create_timer(1.0).timeout
    _connect()

func _connection_lost() -> void:
    if connecting_local and local_retry < 4:
        local_retry += 1
        await get_tree().create_timer(1.0).timeout
        _connect()
        return
    connecting_local = false
    if game != null:
        _dispose_game()
    _multiplayer()
    _notice("连接中断。对局席位保留 60 秒：连接服务器后点击重连。" if not service.token.is_empty() else "无法连接服务器，请检查地址、端口以及服务是否启动。")

func _lobby_changed(data: Dictionary) -> void:
    lobby = data
    if game != null:
        return
    config = data.config.duplicate(true)
    mode = "lobby"
    _clear("房间  " + data.code)
    _label("你的席位：%d  · 房主：%d" % [data.seat, data.host])
    _configuration(data.seat == data.host)
    _button("准备 / 取消准备", func(): service.send("ready"))
    if data.seat == data.host:
        _button("开始对战", func(): service.send("start"))
    _button("离开房间", func():
        service.send("leave")
        _home())

func _online_start(state: Dictionary, seat: int) -> void:
    _start_game(state, seat, true)

func _start_game(state: Dictionary, seat: int, networked: bool) -> void:
    mode = "loading"
    _sync_menu_music()
    pending_world.clear()
    _notice("正在加载战场…")
    await get_tree().process_frame
    if game != null:
        _dispose_game()
    online = networked
    mode = "playing"
    shown_result = false
    game = Game.instantiate()
    game.front_end = self
    game.external_transport = service if networked else null
    game.startup_config = state.config if networked else config.duplicate(true)
    game.selected_map_id = state.map_id if networked else config.map
    game.local_slot = seat
    add_child(game)
    if not game.initialization_error.is_empty():
        var reason: String = game.initialization_error
        if networked:
            service.send("leave")
        _dispose_game()
        _home()
        _notice(reason)
        return
    if networked and not game.sim.apply_snapshot(state):
        service.send("leave")
        _dispose_game()
        _home()
        _notice("无法加载对局状态。")
        return
    if networked and not pending_world.is_empty() and pending_world.get("match") == game.sim.match_id:
        game.sim.apply_snapshot(pending_world)
    pending_world.clear()
    game.connected = networked
    game.active = true
    game._reset_view()
    game.cursor_controller.update_mouse_mode()
    for child in game.menu_buttons.get_children():
        child.hide()
    game.resume_button.show()
    game.resume_button.text = "继续游戏"
    game.settings_button.show()
    game.settings_button.text = "设置"
    var back := Button.new()
    back.text = "退出对局并返回主界面"
    back.pressed.connect(return_home)
    game.menu_buttons.add_child(back)
    root.hide()

func _world(state: Dictionary) -> void:
    if mode == "loading":
        pending_world = state
        return
    if game == null or not online:
        return
    game.network_session.receive_world(state)
    if not game.active:
        service.send("leave")
        _dispose_game()
        _home()
        _notice("世界状态校验失败，请检查双方版本与地图资源。")

func _process(_delta: float) -> void:
    _sync_menu_music()
    if uses_menu_cursor():
        apply_menu_cursor()
    else:
        release_menu_cursor()
    if background != null and root.visible:
        var t := Time.get_ticks_msec() * 0.00012
        background.scale = Vector2.ONE * (1.012 + sin(t) * 0.004)
    if game != null and not shown_result and (game.sim.winner != 0 or game.local_slot in game.sim.eliminated):
        shown_result = true
        game._close_menu()
        game.menu_visible = true
        game.set_process_input(false)
        game.set_process_unhandled_input(false)
        game.cursor_controller.update_mouse_mode()
        root.show()
        menu.show()
        mode = "result"
        _clear("对局结果")
        var text := "失败"
        if game.sim.result.status == "draw":
            text = "平局"
        elif game.sim.result.status == "won" and game.sim.result.team == game.sim.teams.get(game.local_slot):
            text = "胜利"
        _label(text)
        _label("对局时长：%d 秒" % (game.sim.frame / 20))
        _button("返回主界面", return_home)
        apply_menu_cursor()

func _dispose_game() -> void:
    if game != null:
        remove_child(game)
        game.queue_free()
        game = null
        # Removing the scene synchronously restores the OS arrow in its cursor controller.
        menu_cursor_applied = false
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func return_home() -> void:
    if online:
        service.send("leave")
    _dispose_game()
    online = false
    _home()
    _sync_menu_music()

func _sync_menu_music() -> void:
    if menu_music != null:
        menu_music.set_menu_active(game == null and mode != "loading")

func _notice(text: String) -> void:
    if notice != null:
        notice.text = text
    if game != null:
        game._notify(text)

func update_mouse_mode() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    apply_menu_cursor()

func _input(event: InputEvent) -> void:
    if root == null or not root.visible or not event is InputEventKey or not event.pressed or event.echo:
        return
    if settings_panel.visible and not settings_panel.recording.is_empty():
        settings_panel.accept_key(event)
        get_viewport().set_input_as_handled()
    elif event.keycode == KEY_ESCAPE:
        if settings_panel.visible:
            settings_panel.close()
        elif mode not in ["lobby", "result"]:
            _home()
        get_viewport().set_input_as_handled()

func _camera_speed_changed(value: float) -> void:
    camera_speed_multiplier = value
    camera_speed_value_label.text = "%.1fx" % value
    _save_settings()

func _save_settings() -> void:
    var saved := ConfigFile.new()
    saved.load("user://settings.cfg")
    saved.set_value("camera", "speed_multiplier", camera_speed_multiplier)
    saved.set_value("online", "address", address)
    saved.set_value("online", "port", server_port)
    saved.set_value("online", "nickname", service.nickname)
    saved.save("user://settings.cfg")

func _quit() -> void:
    if online or not service.room_code.is_empty():
        service.send("leave")
    if local_pid > 0 and not keep_service and OS.is_process_running(local_pid):
        OS.kill(local_pid)
    get_tree().quit()
