class_name HudController
extends Node
const Simulation = preload("res://scripts/simulation.gd")
const MechanicalHud = preload("res://scripts/ui/mechanical_hud.gd")
var host
var view: Control


func configure(owner) -> void:
    host = owner


func _refresh_command_cards() -> void:
    var commands := {}
    var unavailable: Array[int] = []
    if not host.selected_units.is_empty():
        commands = {0: "stop", 1: "move"}
        for id: int in host.selected_units:
            if Simulation.is_combat_unit(host.sim.units[id].type):
                commands[2] = "attack"
            elif host.sim.units[id].type == "harvester":
                commands[3] = "gather"
    elif host.sim.buildings.has(host.selected_building):
        var building: Dictionary = host.sim.buildings[host.active_building_id()]
        match str(building.type):
            "base":
                match Simulation.BarracksFlight.state(building):
                    "grounded":
                        commands = {0: "takeoff", 2: "barracks", 3: "refinery", 5: "bunker", 6: "base"}
                        if building.remaining > 0:
                            unavailable.append_array([0, 2, 3, 5, 6])
                    "airborne":
                        commands = {0: "stop", 1: "move", 3: "deploy"}
            "refinery":
                commands = {4: "cancel"}
            "barracks":
                match Simulation.BarracksFlight.state(building):
                    "grounded":
                        commands = {2: "takeoff", 4: "cancel"}
                        if building.remaining > 0:
                            unavailable.append(1)
                        if building.remaining > 0 or not building.queue.is_empty():
                            unavailable.append(2)
                    "airborne":
                        commands = {0: "stop", 1: "move", 3: "deploy"}
        var products := Simulation.EntityCatalog.produced_by(str(building.type))
        if not products.is_empty() and Simulation.BarracksFlight.state(building) == "grounded":
            commands[1] = products[0]
        if not products.is_empty():
            commands[6] = "rally"
            if building.rally_mode != "none" or host._rally_targets().any(func(id): return host.sim.buildings[id].rally_mode != "none"):
                commands[7] = "clear_rally"
            if host._rally_targets().is_empty():
                unavailable.append(6)
                unavailable.append(7)
    for i in range(host.action_buttons.size()):
        var command: String = commands.get(i, "")
        var selected: bool = (command == "attack" and host.attack_mode) or command == host.pending_command
        if not host.active or host.local_slot == 0:
            unavailable.append(i)
        host.action_buttons[i].present(command, commands.has(i) and i not in unavailable,
            host.key_bindings.label(command) if not command.is_empty() else "", selected)


func refresh() -> void:
    if host.pending_command == "rally" and (host.menu_visible or host._rally_targets().is_empty()):
        host.pending_command = ""
    view.refresh()
    _refresh_command_cards()
    view.arrange_commands()
    host.resume_button.disabled = not host.active
    host.result_label.text = ""
    if host.sim.winner > 0:
        host.result_label.text = "平局" if host.sim.result.status == "draw" else ("胜利" if host.sim.result.team == host.sim.teams.get(host.local_slot) else "失败")
        host.result_label.text += "  · Esc 返回菜单"


func playfield_rect() -> Rect2:
    return view.playfield_rect() if view != null else Rect2()


func minimap_dragging() -> bool:
    return view != null and view.minimap.dragging


func invoke(command: String) -> void:
    if command != "rally" and host.pending_command == "rally":
        host.pending_command = ""
    match command:
        "stop":
            host._stop()
        "move", "gather", "rally":
            host._begin_pending(command)
        "clear_rally":
            host._clear_rally()
        "attack":
            host.attack_mode = not host.attack_mode
            host.pending_command = ""
            host._notify("选择攻击目标或地面" if host.attack_mode else "已取消攻击指令")
        "mobile_infantry", "harvester":
            host._produce(command)
        "takeoff":
            host._takeoff_barracks()
        "deploy":
            host._begin_deploy()
        "cancel":
            host._cancel_job()
        "base", "barracks", "refinery", "bunker":
            host._begin_build(command)


func _button(parent: Node, caption: String, callback: Callable) -> Button:
    var button := Button.new()
    button.text = caption
    button.custom_minimum_size.y = 32
    button.pressed.connect(callback)
    parent.add_child(button)
    return button


func build() -> void:
    host.hud = CanvasLayer.new()
    host.add_child(host.hud)
    var root := Control.new()
    host.hud.add_child(root)
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    host.cjk_font = SystemFont.new()
    host.cjk_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "sans-serif"])
    var theme := Theme.new()
    theme.default_font = host.cjk_font
    theme.default_font_size = 18
    var panel_style := StyleBoxFlat.new()
    panel_style.bg_color = Color("#15212d")
    panel_style.border_color = Color("#51718e")
    panel_style.set_border_width_all(1)
    panel_style.set_content_margin_all(14)
    theme.set_stylebox("panel", "PanelContainer", panel_style)
    root.theme = theme
    # Retain the old status API for existing controllers without a second visible panel.
    host.info_panel = PanelContainer.new()
    host.info_panel.visible = false
    root.add_child(host.info_panel)
    host.info_label = Label.new()
    host.queue_label = Label.new()
    host.info_panel.add_child(host.info_label)
    host.info_panel.add_child(host.queue_label)
    view = MechanicalHud.new()
    root.add_child(view)
    view.configure(host)
    host.result_label = Label.new()
    host.result_label.position = Vector2(100, 80)
    host.result_label.add_theme_font_size_override("font_size", 30)
    host.result_label.add_theme_color_override("font_color", Color("#ffe292"))
    host.result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(host.result_label)
    host.menu = PanelContainer.new()
    host.menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    host.menu.offset_left   = -235
    host.menu.offset_right  = 235
    var menu_half_height := minf(440.0, host.get_viewport().get_visible_rect().size.y * 0.45)
    host.menu.offset_top    = -menu_half_height
    host.menu.offset_bottom = menu_half_height
    root.add_child(host.menu)
    host.menu_buttons = VBoxContainer.new()
    host.menu_buttons.add_theme_constant_override("separation", 12)
    var menu_scroll := ScrollContainer.new()
    menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    host.menu.add_child(menu_scroll)
    host.menu_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    menu_scroll.add_child(host.menu_buttons)
    var heading := Label.new()
    heading.text = "GAIA FRONTIER\nRTS SKIRMISH"
    heading.add_theme_font_size_override("font_size", 28)
    host.menu_buttons.add_child(heading)
    var subtitle := Label.new()
    subtitle.text = "Mine. Build. Deploy. Capture the field."
    host.menu_buttons.add_child(subtitle)
    host.map_selector = OptionButton.new()
    for id in host.MapCatalog.IDS:
        host.map_selector.add_item("训练场" if id == "desert_sample" else host.MapCatalog.definition(id).title)
    host.map_selector.item_selected.connect(host._map_selected)
    host.menu_buttons.add_child(host.map_selector)
    host.map_preview = TextureRect.new()
    host.map_preview.custom_minimum_size = Vector2(400, 132)
    host.map_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    host.map_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    host.menu_buttons.add_child(host.map_preview)
    host.map_description = Label.new()
    host.map_description.add_theme_font_size_override("font_size", 14)
    host.menu_buttons.add_child(host.map_description)
    host._update_map_description()
    host.resume_button = _button(host.menu_buttons, "Resume", host._close_menu)
    host.solo_button = _button(host.menu_buttons, "New solo match (vs AI)", host.play_solo)
    host.sample_host_button = _button(host.menu_buttons, "Create LAN Host", host.create_host)
    host._update_map_description()
    host.address = LineEdit.new()
    host.address.text = host.host_ip
    host.address.placeholder_text = "Host IPv4 host.address"
    host.address.text_changed.connect(func(value: String) -> void: host.host_ip = value)
    host.menu_buttons.add_child(host.address)
    _button(host.menu_buttons, "Join Host", host.join_host)
    _button(host.menu_buttons, "Restart match (solo / host)", host.restart_match)
    _button(host.menu_buttons, "Return to title / disconnect", host.return_to_title)
    host.settings_panel = preload("res://scripts/ui/settings_panel.gd").new()
    root.add_child(host.settings_panel)
    host.settings_panel.configure(host)
    host.settings_button = _button(host.menu_buttons, "设置", host.settings_panel.open)
    _button(host.menu_buttons, "Quit", host.get_tree().quit)
