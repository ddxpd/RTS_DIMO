class_name HudController
extends Node

const Simulation = preload("res://scripts/simulation.gd")

var host


func configure(owner) -> void:
    host = owner


func _clear_container(container: Control) -> void:
    for child: Node in container.get_children():
        container.remove_child(child)
        child.free()


func _make_unit_thumbnail(kind: String, caption: String, size: int) -> VBoxContainer:
    var tile := VBoxContainer.new()
    tile.add_theme_constant_override("separation", 0)
    var icon := Button.new()
    icon.custom_minimum_size = Vector2(size, size)
    icon.text = str({"soldier": "S", "harvester": "H"}.get(kind, "?"))
    icon.tooltip_text = kind
    icon.add_theme_font_size_override("font_size", int(size * 0.5))
    if host.cjk_font != null:
        icon.add_theme_font_override("font", host.cjk_font)
    tile.add_child(icon)
    if not caption.is_empty():
        var count_label := Label.new()
        count_label.text = caption
        count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        count_label.add_theme_font_size_override("font_size", 12)
        tile.add_child(count_label)
    return tile


func refresh() -> void:
    var role := "BLUE" if host.local_slot == 1 else ("RED" if host.local_slot == 2 else "SPECTATOR")
    host.top_label.text = "IRON FRONT   /   %s     CREDITS: %d     %02d:%02d" % [role, int(host.sim.money.get(host.local_slot, 0)), host.sim.frame / 1200, (host.sim.frame / 20) % 60]
    host.resource_label.text = "MINERALS  %d" % int(host.sim.money.get(host.local_slot, 0))
    # Reset only the unused action slots: toggling an enabled Button every frame
    # would clear its internal press state and swallow the clicked signal.
    var active_actions := 0
    host.production_bar.visible = false
    host.production_queue_label.text = ""
    if not host.selected_units.is_empty():
        active_actions = 4
        var selected: Dictionary = host.sim.units[host.selected_units[0]]
        # Roster: one thumbnail tile per unit kind with its count.
        _clear_container(host.roster_row)
        var roster_counts := {}
        for id: int in host.selected_units:
            var roster_kind := str(host.sim.units[id].type)
            roster_counts[roster_kind] = int(roster_counts.get(roster_kind, 0)) + 1
        for roster_kind: String in roster_counts:
            host.roster_row.add_child(_make_unit_thumbnail(roster_kind, "x%d" % int(roster_counts[roster_kind]), 52))
        if host.selected_units.size() == 1:
            var stats: Dictionary = Simulation.UNIT_TYPES[selected.type]
            host.selection_label.text = "UNIT STATUS   |   HP %d / %d   |   ORDER: %s" % [selected.hp, stats.hp, str(selected.order).to_upper()]
        else:
            host.selection_label.text = "GROUP"
        # SC2-style command card: universal commands stay in fixed slots and
        # type-specific commands each get their own slot, all visible at once.
        var has_soldier := false
        var has_harvester := false
        for id: int in host.selected_units:
            if host.sim.units[id].type == "soldier":
                has_soldier = true
            elif host.sim.units[id].type == "harvester":
                has_harvester = true
        host.action_buttons[0].text     = "STOP (S)"
        host.action_buttons[0].disabled = false
        host.action_buttons[1].text     = "MOVE (RMB)"
        host.action_buttons[1].disabled = false
        host.action_buttons[2].text     = ("ATTACK (A) ON" if host.attack_mode else "ATTACK (A)") if has_soldier else "-"
        host.action_buttons[2].disabled = not has_soldier
        host.action_buttons[3].text     = "GATHER (RMB)" if has_harvester else "-"
        host.action_buttons[3].disabled = not has_harvester
    elif host.sim.buildings.has(host.selected_building):
        var b: Dictionary = host.sim.buildings[host.selected_building]
        var tab_prefix := ""
        if host.selected_buildings.size() > 1:
            host.building_tab_index = host.building_tab_index % host.selected_buildings.size()
            b = host.sim.buildings[host.selected_buildings[host.building_tab_index]]
            tab_prefix = "%d x %s  [%d/%d]   " % [host.selected_buildings.size(), str(b.type).to_upper(), host.building_tab_index + 1, host.selected_buildings.size()]
        var rally_hint := "   |   Right-click: rally point" if b.type in ["barracks", "refinery"] else ""
        host.selection_label.text = "BUILDING   %s%s   |   HP %d / %d%s" % [tab_prefix, str(b.type).to_upper(), b.hp, Simulation.BUILD_TYPES[b.type].hp, rally_hint]
        # Only the building's own actions: production on its producer,
        # construction orders on the base; nothing unrelated leaks in.
        var labels: Dictionary = {}
        if b.type == "barracks":
            active_actions = 5
            labels = {1: "SOLDIER ($100)", 4: "CANCEL (Refund)"}
        elif b.type == "refinery":
            active_actions = 5
            labels = {1: "MINER ($200)", 4: "CANCEL (Refund)"}
        elif b.type == "base":
            active_actions = 7
            labels = {2: "BARRACKS (B)", 3: "REFINERY ($400)", 5: "BUNKER ($300)", 6: "BASE ($500)"}
        for i in range(host.action_buttons.size()):
            if labels.has(i):
                host.action_buttons[i].text     = str(labels[i])
                host.action_buttons[i].disabled = false
            else:
                host.action_buttons[i].text = "-"
                host.action_buttons[i].disabled = true
        _clear_container(host.production_queue_row)
        if not b.queue.is_empty():
            var job: Dictionary = b.queue[0]
            var job_time: int = Simulation.UNIT_TYPES[job.type].time
            var progress := 100.0 * (1.0 - float(job.remaining) / job_time)
            host.production_bar.visible = true
            host.production_bar.max_value = job_time
            host.production_bar.value = job_time - int(job.remaining)
            host.production_queue_label.text = "QUEUE %d / 5" % b.queue.size()
            # The queue is a row of thumbnails; the first shows its progress.
            for i: int in b.queue.size():
                var entry: Dictionary = b.queue[i]
                var caption := "%.0f%%" % progress if i == 0 else ""
                host.production_queue_row.add_child(_make_unit_thumbnail(str(entry.type), caption, 40))
        else:
            host.production_bar.visible = false
            host.production_queue_label.text = "QUEUE EMPTY"
    else:
        host.selection_label.text = "UNIT STATUS\\nNo unit selected - left-click a unit on the battlefield."
    for i in range(host.action_buttons.size()):
        if i >= active_actions:
            host.action_buttons[i].text = "-"
            host.action_buttons[i].disabled = true
    host.resume_button.disabled = not host.active
    host.message_label.text = host.feedback if host.feedback_time > 0 else "Left: select / dbl-click: same type    Right: order / rally    A: attack    B: barracks    S: stop    Ctrl/Shift+N: groups    Esc: menu"
    host.result_label.text = ""
    if host.sim.winner > 0:
        host.result_label.text = "DRAW" if host.sim.winner == 3 else ("VICTORY" if host.sim.winner == host.local_slot else "DEFEAT")
        host.result_label.text += "  - Esc to restart / return"
    for n: int in range(host.group_cards.size()):
        var group_number := n + 1
        if host.control_groups.has(group_number):
            var group_state: Dictionary = host.control_groups[group_number]
            var units_in_group: Array = group_state.get("units", [])
            var buildings_in_group: Array = group_state.get("buildings", [])
            var first_name := "-"
            if not units_in_group.is_empty() and host.sim.units.has(int(units_in_group[0])):
                first_name = str(host.sim.units[int(units_in_group[0])].type).to_upper()
            elif not buildings_in_group.is_empty() and host.sim.buildings.has(int(buildings_in_group[0])):
                first_name = str(host.sim.buildings[int(buildings_in_group[0])].type).to_upper()
            host.group_cards[n].text = "%d: %s" % [group_number, first_name]
            host.group_cards[n].modulate = Color.WHITE
        else:
            host.group_cards[n].text = "%d -" % group_number
            host.group_cards[n].modulate = Color(1, 1, 1, 0.35)
    if host.sim.buildings.has(host.selected_building):
        var b: Dictionary = host.sim.buildings[host.selected_building]
        host.info_label.text = "%s\nHP %d / %d\n%s" % [str(b.type).to_upper(), b.hp, Simulation.BUILD_TYPES[b.type].hp, "Construction: %.1fs" % (float(b.remaining) / 20) if b.remaining > 0 else "Ready"]
        host.queue_label.text = "PRODUCTION (%d / 5)\n" % b.queue.size()
        for job: Dictionary in b.queue:
            host.queue_label.text += "%s  %.1fs\n" % [job.type, float(job.remaining) / 20]
        if not b.queue.is_empty() and int(b.queue[0].remaining) == 0:
            host.queue_label.text += "Exit blocked - clear nearby units"
    elif not host.selected_units.is_empty():
        host.info_label.text = "%d UNIT(S) SELECTED\n" % host.selected_units.size()
        var u: Dictionary = host.sim.units[host.selected_units[0]]
        host.info_label.text += "%s / HP %d\nOrder: %s" % [u.type, u.hp, u.order]
        if u.type == "harvester":
            host.info_label.text += " / Cargo %d / 60" % u.cargo
        host.queue_label.text = "Select a refinery for miners.\nSelect a barracks for soldiers."
    else:
        host.info_label.text = "No selection\nSelect units or a building.\nHarvesters return ore to a base."
        host.queue_label.text = "Buildings cost credits.\nPlace near your existing base."


func _button(parent: Node, caption: String, callback: Callable) -> Button:
    var button := Button.new()
    button.text = caption
    button.custom_minimum_size.y = 32
    button.pressed.connect(callback)
    parent.add_child(button)
    return button


func _add_bottom_zone(row: HBoxContainer, key: String, min_size: Vector2, caption: String, expand: bool) -> VBoxContainer:
    var zone := VBoxContainer.new()
    zone.add_theme_constant_override("separation", 2)
    zone.custom_minimum_size = min_size
    if expand:
        zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    if not caption.is_empty():
        var caption_label := Label.new()
        caption_label.text = caption
        caption_label.add_theme_font_size_override("font_size", 11)
        caption_label.modulate = Color(1, 1, 1, 0.5)
        zone.add_child(caption_label)
    row.add_child(zone)
    host.bottom_zones[key] = zone
    return zone
func build() -> void:
    host.hud = CanvasLayer.new()
    host.add_child(host.hud)
    var theme := Theme.new()
    theme.default_font_size = 15
    var style := StyleBoxFlat.new()
    style.bg_color = Color("#1c292e")
    style.border_color = Color("#557568")
    style.set_border_width_all(1)
    style.set_content_margin_all(12)
    theme.set_stylebox("panel", "PanelContainer", style)
    var root := Control.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.theme = theme
    host.hud.add_child(root)
    var header := PanelContainer.new()
    header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    header.offset_bottom = 52
    root.add_child(header)
    host.top_label = Label.new()
    host.top_label.add_theme_font_size_override("font_size", 18)
    header.add_child(host.top_label)
    host.resource_label          = Label.new()
    host.resource_label.text     = "MINERALS"
    host.resource_label.position = Vector2(440, 12)
    root.add_child(host.resource_label)
    host.info_panel = PanelContainer.new()
    host.info_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
    host.info_panel.offset_left = -260
    host.info_panel.offset_top = 52
    root.add_child(host.info_panel)
    host.info_panel.visible = false
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 6)
    column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    host.info_panel.add_child(scroll)
    scroll.add_child(column)
    var title := Label.new()
    title.text = "FIELD COMMAND"
    title.add_theme_color_override("font_color", Color("#d3be76"))
    column.add_child(title)
    host.info_label = Label.new()
    host.info_label.custom_minimum_size = Vector2(228, 92)
    host.info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    column.add_child(host.info_label)
    column.add_child(HSeparator.new())
    _button(column, "Build Barracks   $250  [B]", host._begin_build.bind("barracks"))
    _button(column, "Build Base         $500", host._begin_build.bind("base"))
    _button(column, "Cancel last job / refund", host._cancel_job)
    host.queue_label = Label.new()
    host.queue_label.custom_minimum_size = Vector2(228, 92)
    host.queue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    column.add_child(host.queue_label)
    _button(column, "Stop selected units [S]", host._stop)
    _button(column, "Menu [Esc]", host._toggle_menu)
    var spacer := Control.new()
    spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(spacer)
    var help := Label.new()
    help.text = "LEFT: select / drag box\nBlank: clear selection\nRIGHT: move / attack / mine\nA: attack mode, then LEFT target / ground\nWheel: zoom\nMiddle drag / arrows: camera\nEsc / right click: cancel build\nDestroy all enemy bases to win"
    help.add_theme_font_size_override("font_size", 12)
    column.add_child(help)
    var bottom := PanelContainer.new()
    bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    # Sit strictly above the 42px message bar; two button rows fit inside 132px.
    bottom.offset_top = -174
    bottom.offset_bottom = -42
    bottom.offset_right = 0
    root.add_child(bottom)
    # SC2-style control group cards floating above the command bar.
    var groups_row := HBoxContainer.new()
    groups_row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    groups_row.offset_top = -212
    groups_row.offset_bottom = -178
    groups_row.offset_left = 12
    groups_row.add_theme_constant_override("separation", 6)
    root.add_child(groups_row)
    for n in range(9):
        var card := Button.new()
        card.custom_minimum_size = Vector2(96, 34)
        card.text = "%d -" % (n + 1)
        card.pressed.connect(host._control_group_key.bind(n + 1, false, false))
        groups_row.add_child(card)
        host.group_cards.append(card)
    var bottom_row := HBoxContainer.new()
    bottom_row.add_theme_constant_override("separation", 12)
    bottom.add_child(bottom_row)
    # The command bar is composed of named zones; future zones (minimap,
    # extras) plug in through _add_bottom_zone without touching the layout.
    _add_bottom_zone(bottom_row, "map", Vector2(220, 96), "", false)
    var status_zone: VBoxContainer = _add_bottom_zone(bottom_row, "status", Vector2(0, 96), "STATUS", true)
    var status_content := HBoxContainer.new()
    status_content.add_theme_constant_override("separation", 12)
    status_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    status_zone.add_child(status_content)
    host.cjk_font = SystemFont.new()
    host.cjk_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "sans-serif"])
    host.roster_row = HBoxContainer.new()
    host.roster_row.add_theme_constant_override("separation", 6)
    # Fixed width keeps the queue anchor stable no matter the roster size.
    host.roster_row.custom_minimum_size = Vector2(260, 0)
    status_content.add_child(host.roster_row)
    var production_panel := VBoxContainer.new()
    production_panel.add_theme_constant_override("separation", 4)
    status_content.add_child(production_panel)
    host.production_queue_label = Label.new()
    host.production_queue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    host.production_queue_label.add_theme_font_size_override("font_size", 13)
    host.production_queue_label.text = ""
    production_panel.add_child(host.production_queue_label)
    host.production_queue_row = HBoxContainer.new()
    host.production_queue_row.add_theme_constant_override("separation", 4)
    # Fixed five-slot strip: job i always renders at the same x position.
    host.production_queue_row.custom_minimum_size = Vector2(240, 0)
    production_panel.add_child(host.production_queue_row)
    host.production_bar = ProgressBar.new()
    host.production_bar.custom_minimum_size = Vector2(180, 16)
    host.production_bar.show_percentage = true
    host.production_bar.visible = false
    production_panel.add_child(host.production_bar)
    host.selection_label = Label.new()
    host.selection_label.custom_minimum_size = Vector2(0, 76)
    host.selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    host.selection_label.add_theme_font_size_override("font_size", 16)
    host.selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    host.selection_label.text = "UNIT STATUS\\nNo unit selected - left-click a unit on the battlefield."
    status_content.add_child(host.selection_label)
    var command_zone: VBoxContainer = _add_bottom_zone(bottom_row, "command", Vector2(420, 96), "COMMAND", false)
    host.action_grid = GridContainer.new()
    host.action_grid.columns = 4
    host.action_grid.custom_minimum_size = Vector2(420, 96)
    command_zone.add_child(host.action_grid)
    for i in range(8):
        var action_button := Button.new()
        action_button.custom_minimum_size = Vector2(100, 42)
        action_button.text = "-"
        action_button.disabled = true
        action_button.pressed.connect(host._action_clicked.bind(i))
        host.action_grid.add_child(action_button)
        host.action_buttons.append(action_button)
    host.message_label = Label.new()
    host.message_label.add_theme_font_size_override("font_size", 13)
    var message_bar := PanelContainer.new()
    message_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    message_bar.offset_top = -42
    message_bar.offset_right = 0
    root.add_child(message_bar)
    message_bar.add_child(host.message_label)
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
    host.menu.offset_top    = -255
    host.menu.offset_bottom = 255
    root.add_child(host.menu)
    host.menu_buttons = VBoxContainer.new()
    host.menu_buttons.add_theme_constant_override("separation", 12)
    host.menu.add_child(host.menu_buttons)
    var heading := Label.new()
    heading.text = "IRON FRONT\nRTS SKIRMISH"
    heading.add_theme_font_size_override("font_size", 28)
    host.menu_buttons.add_child(heading)
    var subtitle := Label.new()
    subtitle.text = "Mine. Build. Deploy. Capture the field."
    host.menu_buttons.add_child(subtitle)
    host.resume_button = _button(host.menu_buttons, "Resume", host._close_menu)
    _button(host.menu_buttons, "New solo match (vs AI)", host.play_solo)
    _button(host.menu_buttons, "Create LAN Host", host.create_host)
    host.address = LineEdit.new()
    host.address.text = host.host_ip
    host.address.placeholder_text = "Host IPv4 host.address"
    host.address.text_changed.connect(func(value: String) -> void: host.host_ip = value)
    host.menu_buttons.add_child(host.address)
    _button(host.menu_buttons, "Join Host", host.join_host)
    _button(host.menu_buttons, "Restart match (solo / host)", host.restart_match)
    _button(host.menu_buttons, "Return to title / disconnect", host.return_to_title)
    host.attack_rebind_button = _button(host.menu_buttons, "Rebind attack key (current: A)", host._begin_rebind)
    var speed_row := HBoxContainer.new()
    speed_row.add_theme_constant_override("separation", 10)
    host.menu_buttons.add_child(speed_row)
    var speed_caption := Label.new()
    speed_caption.text = "Camera speed"
    speed_row.add_child(speed_caption)
    host.camera_speed_slider = HSlider.new()
    host.camera_speed_slider.min_value = 0.5
    host.camera_speed_slider.max_value = 3.0
    host.camera_speed_slider.step = 0.1
    host.camera_speed_slider.value = host.camera_speed_multiplier
    host.camera_speed_slider.custom_minimum_size = Vector2(180, 32)
    host.camera_speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    host.camera_speed_slider.value_changed.connect(host._camera_speed_changed)
    speed_row.add_child(host.camera_speed_slider)
    host.camera_speed_value_label = Label.new()
    host.camera_speed_value_label.text = "%.1fx" % host.camera_speed_multiplier
    host.camera_speed_value_label.custom_minimum_size = Vector2(48, 32)
    speed_row.add_child(host.camera_speed_value_label)
    _button(host.menu_buttons, "Quit", host.get_tree().quit)
