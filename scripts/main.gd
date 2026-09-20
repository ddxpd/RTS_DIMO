extends Node2D
const Simulation = preload("res://scripts/simulation.gd")
const Art = preload("res://assets/art/pixel_art.gd")
const CameraController = preload("res://scripts/camera_controller.gd")
const PORT := 24560
const MAX_CLIENTS := 4
var sim := Simulation.new()
var peer: ENetMultiplayerPeer
var is_host := false
var connected := false
var active := false
var local_slot := 1
var host_ip := "127.0.0.1"
var slots: Dictionary = {}
var handshakes: Dictionary = {}
var rates: Dictionary = {}
var accumulator := 0.0
var render_velocities: Dictionary = {}
var selected_units: Array[int] = []
var selected_building := -1
var selection_dragging := false
var left_button_held := false
var last_mouse_event_msec := 0
var selected_buildings: Array[int] = []
var last_click_building := -1
var last_click_building_time := 0.0
var action_type_index := 0
var group_cards: Array[Button] = []
var selection_start := Vector2.ZERO
var selection_current := Vector2.ZERO
var middle_dragging := false
var build_mode := ""
var menu_visible := true
var camera: Camera2D
var camera_controller: CameraController
var tiles: TileMapLayer
var hud: CanvasLayer
var top_label: Label
var resource_label: Label
var selection_label: Label
var action_grid: GridContainer
var action_buttons: Array[Button] = []
var info_label: Label
var queue_label: Label
var message_label: Label
var result_label: Label
var menu: PanelContainer
var info_panel: PanelContainer
var menu_buttons: VBoxContainer
var resume_button: Button
var address: LineEdit
var build_buttons: Array[Button] = []
var sprites: Dictionary = {}
var clicks: Array = []
var feedback := ""
var feedback_time := 0.0
var audio_player: AudioStreamPlayer
var audio_playback: AudioStreamGeneratorPlayback
var audio_effect_frame := -1
var speech_unit := -1
var speech_text := ""
var speech_time := 0.0
var attack_mode := false
var rebinding_attack := false
var attack_keycode: Key = KEY_A
var attack_rebind_button: Button
var pending_command := ""
var control_groups: Dictionary = {}
var last_click_time := 0.0
var last_click_unit := -1
var production_bar: ProgressBar
var production_queue_label: Label
var camera_speed_multiplier := 1.4
var camera_speed_slider: HSlider
var camera_speed_value_label: Label

# Scene bootstrap: create the simulation, world tiles, camera, HUD, and audio.
func _ready() -> void:
    _load_settings()
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    sim.reset(false)
    sprites        = {1: Art.sprites(Color("#5fa5e0")), 2: Art.sprites(Color("#d66551"))}
    tiles          = TileMapLayer.new()
    tiles.tile_set = Art.terrain()
    tiles.scale    = Vector2(2, 2)
    tiles.z_index  = -10
    add_child(tiles)
    for x in range(Simulation.GRID.x):
        for y in range(Simulation.GRID.y):
            tiles.set_cell(Vector2i(x, y), 0, Vector2i((x * 7 + y * 11) % 3, 0))
    camera = Camera2D.new()
    add_child(camera)
    camera.position = Vector2(500, 350)
    camera.zoom = Vector2.ONE
    camera_controller = CameraController.new(camera, Simulation.WORLD,
        func() -> Vector2: return get_viewport_rect().size,
        func() -> Vector2: return camera.get_viewport().get_mouse_position())
    camera_controller.speed_multiplier = camera_speed_multiplier
    _create_ui()
    _create_audio()
    multiplayer.peer_connected.connect(_peer_joined)
    multiplayer.peer_disconnected.connect(_peer_left)
    multiplayer.connected_to_server.connect(_connected_to_server)
    multiplayer.connection_failed.connect(_connection_failed)
    multiplayer.server_disconnected.connect(_server_left)
    _refresh_ui()

# Persisted user preferences live in user://settings.cfg.
func _load_settings() -> void:
    var config := ConfigFile.new()
    if config.load("user://settings.cfg") == OK:
        camera_speed_multiplier = clampf(float(config.get_value("camera", "speed_multiplier", 1.4)), 0.5, 3.0)

func _save_settings() -> void:
    var config := ConfigFile.new()
    config.load("user://settings.cfg")
    config.set_value("camera", "speed_multiplier", camera_speed_multiplier)
    config.save("user://settings.cfg")

func _camera_speed_changed(value: float) -> void:
    camera_speed_multiplier = clampf(value, 0.5, 3.0)
    camera_speed_value_label.text = "%.1fx" % camera_speed_multiplier
    if camera_controller != null:
        camera_controller.speed_multiplier = camera_speed_multiplier
    _save_settings()

# Never leave the cursor confined when the game node leaves the tree.
func _exit_tree() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# Build the HUD in code so the exported scene stays lightweight.
func _create_ui() -> void:
    hud = CanvasLayer.new()
    add_child(hud)
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
    hud.add_child(root)
    var header := PanelContainer.new()
    header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    header.offset_bottom = 52
    root.add_child(header)
    top_label = Label.new()
    top_label.add_theme_font_size_override("font_size", 18)
    header.add_child(top_label)
    resource_label          = Label.new()
    resource_label.text     = "MINERALS"
    resource_label.position = Vector2(440, 12)
    root.add_child(resource_label)
    info_panel = PanelContainer.new()
    info_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
    info_panel.offset_left = -260
    info_panel.offset_top = 52
    root.add_child(info_panel)
    info_panel.visible = false
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 6)
    column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    info_panel.add_child(scroll)
    scroll.add_child(column)
    var title := Label.new()
    title.text = "FIELD COMMAND"
    title.add_theme_color_override("font_color", Color("#d3be76"))
    column.add_child(title)
    info_label = Label.new()
    info_label.custom_minimum_size = Vector2(228, 92)
    info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    column.add_child(info_label)
    column.add_child(HSeparator.new())
    _button(column, "Build Barracks   $250  [B]", _begin_build.bind("barracks"))
    _button(column, "Build Base         $500", _begin_build.bind("base"))
    _button(column, "Cancel last job / refund", _cancel_job)
    queue_label = Label.new()
    queue_label.custom_minimum_size = Vector2(228, 92)
    queue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    column.add_child(queue_label)
    _button(column, "Stop selected units [S]", _stop)
    _button(column, "Menu [Esc]", _toggle_menu)
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
        card.text = "%d —" % (n + 1)
        card.pressed.connect(_control_group_key.bind(n + 1, false, false))
        groups_row.add_child(card)
        group_cards.append(card)
    var bottom_row := HBoxContainer.new()
    bottom_row.add_theme_constant_override("separation", 12)
    bottom.add_child(bottom_row)
    selection_label = Label.new()
    selection_label.custom_minimum_size = Vector2(0, 76)
    selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    selection_label.add_theme_font_size_override("font_size", 16)
    selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    selection_label.text = "UNIT STATUS\nNo unit selected — left-click a unit on the battlefield."
    bottom_row.add_child(selection_label)
    var production_panel := VBoxContainer.new()
    production_panel.add_theme_constant_override("separation", 4)
    production_panel.custom_minimum_size = Vector2(190, 76)
    bottom_row.add_child(production_panel)
    production_queue_label = Label.new()
    production_queue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    production_queue_label.add_theme_font_size_override("font_size", 13)
    production_queue_label.text = ""
    production_panel.add_child(production_queue_label)
    production_bar = ProgressBar.new()
    production_bar.custom_minimum_size = Vector2(180, 16)
    production_bar.show_percentage = true
    production_bar.visible = false
    production_panel.add_child(production_bar)
    action_grid = GridContainer.new()
    action_grid.columns = 4
    action_grid.custom_minimum_size = Vector2(420, 96)
    bottom_row.add_child(action_grid)
    for i in range(8):
        var action_button := Button.new()
        action_button.custom_minimum_size = Vector2(100, 42)
        action_button.text = "—"
        action_button.disabled = true
        action_button.pressed.connect(_action_clicked.bind(i))
        action_grid.add_child(action_button)
        action_buttons.append(action_button)
    message_label = Label.new()
    message_label.add_theme_font_size_override("font_size", 13)
    var message_bar := PanelContainer.new()
    message_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    message_bar.offset_top = -42
    message_bar.offset_right = 0
    root.add_child(message_bar)
    message_bar.add_child(message_label)
    result_label = Label.new()
    result_label.position = Vector2(100, 80)
    result_label.add_theme_font_size_override("font_size", 30)
    result_label.add_theme_color_override("font_color", Color("#ffe292"))
    result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(result_label)
    menu = PanelContainer.new()
    menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    menu.offset_left   = -235
    menu.offset_right  = 235
    menu.offset_top    = -255
    menu.offset_bottom = 255
    root.add_child(menu)
    menu_buttons = VBoxContainer.new()
    menu_buttons.add_theme_constant_override("separation", 12)
    menu.add_child(menu_buttons)
    var heading := Label.new()
    heading.text = "IRON FRONT\nRTS SKIRMISH"
    heading.add_theme_font_size_override("font_size", 28)
    menu_buttons.add_child(heading)
    var subtitle := Label.new()
    subtitle.text = "Mine. Build. Deploy. Capture the field."
    menu_buttons.add_child(subtitle)
    resume_button = _button(menu_buttons, "Resume", _close_menu)
    _button(menu_buttons, "New solo match (vs AI)", play_solo)
    _button(menu_buttons, "Create LAN Host", create_host)
    address = LineEdit.new()
    address.text = host_ip
    address.placeholder_text = "Host IPv4 address"
    address.text_changed.connect(func(value: String) -> void: host_ip = value)
    menu_buttons.add_child(address)
    _button(menu_buttons, "Join Host", join_host)
    _button(menu_buttons, "Restart match (solo / host)", restart_match)
    _button(menu_buttons, "Return to title / disconnect", return_to_title)
    attack_rebind_button = _button(menu_buttons, "Rebind attack key (current: A)", _begin_rebind)
    var speed_row := HBoxContainer.new()
    speed_row.add_theme_constant_override("separation", 10)
    menu_buttons.add_child(speed_row)
    var speed_caption := Label.new()
    speed_caption.text = "Camera speed"
    speed_row.add_child(speed_caption)
    camera_speed_slider = HSlider.new()
    camera_speed_slider.min_value = 0.5
    camera_speed_slider.max_value = 3.0
    camera_speed_slider.step = 0.1
    camera_speed_slider.value = camera_speed_multiplier
    camera_speed_slider.custom_minimum_size = Vector2(180, 32)
    camera_speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    camera_speed_slider.value_changed.connect(_camera_speed_changed)
    speed_row.add_child(camera_speed_slider)
    camera_speed_value_label = Label.new()
    camera_speed_value_label.text = "%.1fx" % camera_speed_multiplier
    camera_speed_value_label.custom_minimum_size = Vector2(48, 32)
    speed_row.add_child(camera_speed_value_label)
    _button(menu_buttons, "Quit", get_tree().quit)

func _create_audio() -> void:
    var stream := AudioStreamGenerator.new()
    stream.mix_rate      = 44100
    stream.buffer_length = 1.0
    audio_player         = AudioStreamPlayer.new()
    audio_player.stream  = stream
    add_child(audio_player)
    audio_player.play()
    audio_playback = audio_player.get_stream_playback() as AudioStreamGeneratorPlayback

func _play_tone(frequency: float, duration: float, volume: float = 0.16, slide: float = 0.0) -> void:
    if audio_playback == null:
        return
    var frames := mini(int(duration * 44100.0), 16000)
    for i in range(frames):
        var t := float(i) / 44100.0
        var envelope := minf(1.0, float(i) / 220.0) * minf(1.0, float(frames - i) / 900.0)
        var phase := TAU * (frequency * t + slide * t * t * 0.5)
        var sample := sin(phase) * volume * envelope
        audio_playback.push_frame(Vector2(sample, sample))

func _play_attack_sound() -> void:
    _play_tone(180.0, 0.055, 0.16, 420.0)

func _play_hit_sound() -> void:
    _play_tone(78.0, 0.10, 0.20, -25.0)

func _respond(unit_id: int, words: String) -> void:
    if not sim.units.has(unit_id) or sim.units[unit_id].owner != local_slot:
        return
    speech_unit = unit_id
    speech_text = words
    speech_time = 1.6
    _notify("Unit %d: %s" % [unit_id, words])
    _play_tone(440.0, 0.045, 0.10)

func _button(parent: Node, caption: String, callback: Callable) -> Button:
    var button := Button.new()
    button.text = caption
    button.custom_minimum_size.y = 32
    button.pressed.connect(callback)
    parent.add_child(button)
    return button

func _clear_selection() -> void:
    selected_units.clear()
    selected_building = -1
    selected_buildings.clear()
    selection_dragging = false

# Keep the world strictly larger than the viewport on both axes so the
# camera always has room to move; otherwise it clamps dead at the center.
func _min_zoom() -> float:
    var size := get_viewport_rect().size
    return maxf(size.x / Simulation.WORLD.x, size.y / Simulation.WORLD.y) + 0.05

func _reset_view() -> void:
    _clear_selection()
    build_mode = ""
    clicks.clear()
    camera.zoom     = Vector2.ONE * maxf(1.0, _min_zoom())
    camera.position = Vector2(900, 700) if local_slot != 2 else Vector2(3900, 2500)
    menu_visible    = false
    menu.visible    = false

func _disconnect() -> void:
    if multiplayer.multiplayer_peer != null:
        multiplayer.multiplayer_peer.close()
    multiplayer.multiplayer_peer = null
    peer = null
    is_host = false
    connected = false
    slots.clear()
    handshakes.clear()
    rates.clear()

func play_solo() -> void:
    _disconnect()
    sim.reset(true)
    active      = true
    local_slot  = 1
    accumulator = 0.0
    _reset_view()
    Input.mouse_mode = Input.MOUSE_MODE_CONFINED
    _notify("Select the harvester, then right-click yellow ore. Build a barracks to train soldiers.")

func create_host() -> void:
    _disconnect()
    peer = ENetMultiplayerPeer.new()
    var error := peer.create_server(PORT, MAX_CLIENTS)
    if error != OK:
        _notify("Host failed: " + error_string(error))
        return
    multiplayer.multiplayer_peer = peer
    Input.mouse_mode = Input.MOUSE_MODE_CONFINED
    is_host = true
    connected = true
    active = true
    local_slot = 1
    sim.reset(false)
    _reset_view()
    _notify("LAN host ready on UDP 24560. Waiting for the red player.")

func join_host() -> void:
    _disconnect()
    active     = false
    local_slot = 0
    peer       = ENetMultiplayerPeer.new()
    var error := peer.create_client(host_ip.strip_edges(), PORT)
    if error != OK:
        _notify("Join failed: " + error_string(error))
        return
    multiplayer.multiplayer_peer = peer
    _notify("Connecting to " + host_ip + "...")

func _peer_joined(id: int) -> void:
    if is_host:
        handshakes[id] = Time.get_ticks_msec()

func _connected_to_server() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_CONFINED
    _hello.rpc_id(1, Simulation.VERSION)

@rpc("any_peer", "reliable")

func _hello(version: String) -> void:
    if not is_host:
        return
    var sender := multiplayer.get_remote_sender_id()
    if slots.has(sender):
        return
    if version != Simulation.VERSION:
        _rejected.rpc_id(sender, "Different game version. Both players need this release.")
        return
    handshakes.erase(sender)
    var slot := 2 if not slots.values().has(2) else 0
    slots[sender] = slot
    _accepted.rpc_id(sender, Simulation.VERSION, slot, sim.snapshot())

@rpc("authority", "reliable")

func _accepted(version: String, slot: int, state: Dictionary) -> void:
    if version != Simulation.VERSION:
        _rejected("Different game version")
        return
    connected  = true
    active     = true
    local_slot = slot
    sim.apply_snapshot(state)
    sim.rebuild_navigation()
    _reset_view()
    _notify("Red army assigned." if slot == 2 else "Spectator mode: no orders allowed.")

@rpc("authority", "reliable")

func _rejected(reason: String) -> void:
    _disconnect.call_deferred()
    active = false
    _notify(reason)

func _peer_left(id: int) -> void:
    handshakes.erase(id)
    rates.erase(id)
    if is_host:
        var was_player: bool = slots.get(id, 0) == 2
        slots.erase(id)
        if was_player:
            for other: int in slots:
                if slots[other] == 0:
                    slots[other] = 2
                    _accepted.rpc_id(other, Simulation.VERSION, 2, sim.snapshot())
                    break
            _notify("Red player disconnected; army retained for reconnect.")

func _connection_failed() -> void:
    _disconnect()
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    active       = false
    menu_visible = true
    menu.visible = true
    _notify("Connection failed. Check host address and UDP 24560.")

func _server_left() -> void:
    _disconnect()
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    active       = false
    menu_visible = true
    menu.visible = true
    _clear_selection()
    _notify("Host disconnected. Match stopped; return to title or start a new match.")

@rpc("authority", "call_remote", "reliable", 1)

func _world(state: Dictionary) -> void:
    if state.get("version") == Simulation.VERSION and state.get("match") == sim.match_id and int(state.frame) >= sim.frame:
        var previous_positions: Dictionary = {}
        for id: int in sim.units:
            previous_positions[id] = sim.units[id].pos
        var previous_frame: int = sim.frame
        sim.apply_snapshot(state)
        _update_render_velocities(previous_positions, previous_frame, int(state.frame))
        _audio_for_effects()

@rpc("authority", "reliable")

func _final_state(state: Dictionary) -> void:
    if state.get("match") == sim.match_id:
        sim.apply_snapshot(state)

@rpc("authority", "reliable")

func _new_match(state: Dictionary) -> void:
    sim.apply_snapshot(state)
    sim.rebuild_navigation()
    _reset_view()

# Send a player order locally or to the authoritative host.
func issue(order: Dictionary) -> void:
    if not active or local_slot == 0:
        _notify("Spectators cannot issue orders.")
        return
    if is_host or not connected:
        var error := sim.command(local_slot, order)
        if not error.is_empty():
            _notify(error)
    else:
        _order.rpc_id(1, order)

@rpc("any_peer", "reliable")

func _order(order: Dictionary) -> void:
    if not is_host:
        return
    var sender := multiplayer.get_remote_sender_id()
    if not slots.has(sender):
        return
    var rate: Dictionary = rates.get(sender, {"frame": sim.frame, "count": 0})
    if sim.frame - int(rate.frame) >= 20:
        rate = {"frame": sim.frame, "count": 0}
    rate.count += 1
    rates[sender] = rate
    if rate.count > 64:
        return
    var error := sim.command(int(slots[sender]), order)
    if not error.is_empty():
        _order_error.rpc_id(sender, error)

@rpc("authority", "reliable")

func _order_error(message: String) -> void:
    _notify(message)

func restart_match() -> void:
    if connected and not is_host:
        _notify("Only the host can restart.")
        return
    if not active:
        play_solo()
        return
    sim.reset(not connected)
    _reset_view()
    if is_host:
        _new_match.rpc(sim.snapshot())
    _notify("New match.")

func return_to_title() -> void:
    _disconnect()
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    active = false
    local_slot = 1
    sim.reset(false)
    _clear_selection()
    build_mode   = ""
    menu_visible = true
    menu.visible = true
    _notify("Match closed.")

# Main loop: advance host simulation, refresh HUD, and redraw the battlefield.
func _process(delta: float) -> void:
    for click: Dictionary in clicks:
        click.life -= delta
    clicks        = clicks.filter(func(c: Dictionary) -> bool: return c.life > 0)
    feedback_time = maxf(0.0, feedback_time - delta)
    speech_time   = maxf(0.0, speech_time - delta)
    if speech_time <= 0.0:
        speech_unit = -1
    if active and (is_host or not connected):
        accumulator += minf(delta, 0.25)
        while accumulator >= 0.05:
            accumulator -= 0.05
            var previous_winner: int = sim.winner
            sim.step()
            _audio_for_effects()
            if is_host and previous_winner == 0 and sim.winner > 0:
                _final_state.rpc(sim.snapshot())
            if is_host and not slots.is_empty():
                # One snapshot per logic tick (20 Hz) keeps guest motion fluid.
                _world.rpc(sim.snapshot())
    elif active and connected and not is_host:
        _smooth_guest_motion(delta)
    if is_host:
        for id: int in handshakes.keys():
            if Time.get_ticks_msec() - int(handshakes[id]) > 5000:
                peer.disconnect_peer(id)
                handshakes.erase(id)
    if active and not menu_visible:
        var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
        camera.position += direction * delta * 500 * camera_speed_multiplier / camera.zoom.x
        camera_controller.update(delta)
    _limit_camera()
    _clean_selection()
    # Safety net: if the release event was lost entirely, finish the drag on
    # the first frame where our tracked button state says it was released.
    if selection_dragging and not left_button_held:
        _finish_drag_select(selection_current)
    _refresh_ui()
    queue_redraw()

func _clean_selection() -> void:
    var valid: Array[int] = []
    for id: int in selected_units:
        if sim.units.has(id) and sim.units[id].owner == local_slot:
            valid.append(id)
    selected_units = valid
    var valid_buildings: Array[int] = []
    for id: int in selected_buildings:
        if sim.buildings.has(id) and sim.buildings[id].owner == local_slot:
            valid_buildings.append(id)
    selected_buildings = valid_buildings
    if selected_buildings.is_empty():
        selected_building = -1
    elif not selected_buildings.has(selected_building):
        selected_building = selected_buildings[0]
    if not sim.buildings.has(selected_building) or sim.buildings[selected_building].owner != local_slot:
        selected_building = -1

func _get_camera_viewport_size() -> Vector2:
    return get_viewport_rect().size

func _get_map_screen_rect() -> Rect2:
        var size := get_viewport_rect().size
        return Rect2(Vector2(0, 52), Vector2(size.x - 260, size.y - 184))

func _limit_camera() -> void:
    var half := get_viewport_rect().size / (2.0 * camera.zoom.x)
    var max_center := Simulation.WORLD - half
    camera.position = camera.position.clamp(half.min(Simulation.WORLD / 2), max_center.max(Simulation.WORLD / 2))

func _screen_is_map(pos: Vector2) -> bool:
    var size := get_viewport_rect().size
    return pos.x < size.x - 260 and pos.y > 52 and pos.y < size.y - 132

# Translate keyboard and mouse input into selection and simulation orders.
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if rebinding_attack:
            if event.keycode != KEY_ESCAPE:
                attack_keycode = event.keycode
                rebinding_attack = false
                attack_rebind_button.text = "Rebind attack key (current: %s)" % OS.get_keycode_string(attack_keycode)
                _notify("Attack key set to %s." % OS.get_keycode_string(attack_keycode))
            get_viewport().set_input_as_handled()
            return
        if event.keycode == KEY_ESCAPE:
            if not build_mode.is_empty() or not pending_command.is_empty():
                build_mode = ""
                pending_command = ""
            else:
                _toggle_menu()
        elif active and not menu_visible and event.keycode == attack_keycode:
            attack_mode = not attack_mode
            _notify("Attack mode %s. Left-click a target or ground." % ("ON" if attack_mode else "OFF"))
        elif active and not menu_visible and event.keycode == KEY_B:
            _begin_build("barracks")
        elif active and not menu_visible and event.keycode == KEY_S:
            _stop()
        elif active and not menu_visible and event.keycode >= KEY_1 and event.keycode <= KEY_9:
            _control_group_key(int(event.keycode) - int(KEY_1) + 1, event.ctrl_pressed, event.shift_pressed)
        elif active and not menu_visible and event.keycode == KEY_TAB:
            var types: Array = _selected_unit_types()
            if types.size() > 1:
                action_type_index = (action_type_index + 1) % types.size()
                _notify("Actions: %s" % str(types[action_type_index]).to_upper())
    if not active or menu_visible:
        return
    if event is InputEventMouseButton:
        var pos: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed and _screen_is_map(event.position):
                if not build_mode.is_empty():
                    _place_building(pos)
                else:
                    selection_dragging = true
                    selection_start    = pos
                    selection_current  = pos
            elif not event.pressed and selection_dragging:
                var button := event as InputEventMouseButton
                if not button.canceled and not left_button_held:
                    _finish_drag_select(pos)
        elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and _screen_is_map(event.position):
            if not build_mode.is_empty():
                build_mode = ""
            else:
                _right_click(pos)
        elif event.button_index == MOUSE_BUTTON_MIDDLE:
            middle_dragging = event.pressed
        elif event.pressed and _screen_is_map(event.position) and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
            var before := get_global_mouse_position()
            var factor := 1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
            camera.zoom = Vector2.ONE * clampf(camera.zoom.x * factor, _min_zoom(), 2.5)
            camera.force_update_scroll()
            camera.position += before - get_global_mouse_position()
    elif event is InputEventMouseMotion:
        if middle_dragging:
            camera.position -= event.relative / camera.zoom.x
        if selection_dragging:
            selection_current = get_global_transform_with_canvas().affine_inverse() * event.position

func _input(event: InputEvent) -> void:
    # _input runs before the HUD consumes events, so an active drag keeps
    # tracking (and can complete) even while the cursor is over HUD panels.
    if event is InputEventMouseMotion:
        last_mouse_event_msec = Time.get_ticks_msec()
        if selection_dragging:
            selection_current = get_global_transform_with_canvas().affine_inverse() * event.position
    if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
        middle_dragging = false
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        var button := event as InputEventMouseButton
        var now := Time.get_ticks_msec()
        # A second press while the button is already held mid-drag is a
        # spurious duplicate from the input stack (seen with confined cursor
        # on Windows): swallow it so the original box start is preserved.
        # Stale drags (release event lost entirely) restart from this press.
        if button.pressed and selection_dragging and left_button_held and not button.canceled:
            if now - last_mouse_event_msec < 1500:
                get_viewport().set_input_as_handled()
                return
            _finish_drag_select(selection_current)
        last_mouse_event_msec = now
        # Track the button ourselves: Godot's Input state is also corrupted by
        # canceled events, so only non-canceled presses/releases update it.
        if not button.canceled:
            left_button_held = button.pressed
        if not button.pressed and selection_dragging:
            # Canceled releases (focus quirks, confined-cursor edge pressure)
            # must not end a drag while the button is still physically held.
            if button.canceled or left_button_held:
                return
            _finish_drag_select(get_global_transform_with_canvas().affine_inverse() * event.position)

# Complete a box drag: treat tiny drags as clicks, larger ones as selections.
func _finish_drag_select(pos: Vector2) -> void:
    selection_dragging = false
    if (pos - selection_start).length() * camera.zoom.x < 8:
        _left_click(pos)
    else:
        _select_rect(Rect2(selection_start, pos - selection_start).abs())

func _left_click(pos: Vector2) -> void:
    if not pending_command.is_empty():
        _pending_click(pos)
        return
    if attack_mode:
        _attack_click(pos)
        return
    _clear_selection()
    for id: int in sim.units:
        var u: Dictionary = sim.units[id]
        if u.owner == local_slot and (u.pos as Vector2).distance_to(pos) <= 20:
            var now := Time.get_ticks_msec() / 1000.0
            if id == last_click_unit and now - last_click_time <= 0.4:
                _select_same_type_on_screen(str(u.type))
                last_click_unit = -1
            else:
                selected_units.append(id)
                last_click_unit = id
            last_click_time = now
            return
    for id: int in sim.buildings:
        if sim.buildings[id].owner == local_slot and sim.footprint(sim.buildings[id]).has_point(pos):
            var now := Time.get_ticks_msec() / 1000.0
            if id == last_click_building and now - last_click_building_time <= 0.4:
                _select_same_type_buildings_on_screen(str(sim.buildings[id].type))
                last_click_building = -1
            else:
                selected_building = id
                selected_buildings.clear()
                selected_buildings.append(id)
                last_click_building = id
            last_click_building_time = now
            return

# Distinct unit kinds in the current selection, in stable order.
func _selected_unit_types() -> Array:
    var types: Array = []
    for id: int in selected_units:
        if sim.units.has(id) and not types.has(sim.units[id].type):
            types.append(sim.units[id].type)
    return types

# Compact roster text such as "6 SOLDIER + 2 HARVESTER".
func _selection_roster() -> String:
    var counts := {}
    for id: int in selected_units:
        if sim.units.has(id):
            var kind := str(sim.units[id].type).to_upper()
            counts[kind] = int(counts.get(kind, 0)) + 1
    var parts: Array = []
    for kind: String in counts:
        parts.append("%d %s" % [int(counts[kind]), kind])
    return " + ".join(parts)

# Double-click: grab every on-screen building of the same kind as the clicked one.
func _select_same_type_buildings_on_screen(kind: String) -> void:
    selected_units.clear()
    selected_buildings.clear()
    var half := get_viewport().get_visible_rect().size / (2.0 * camera.zoom)
    var view := Rect2(camera.position - half, half * 2.0)
    for id: int in sim.buildings:
        var b: Dictionary = sim.buildings[id]
        if b.owner == local_slot and b.type == kind and view.has_point(b.pos):
            selected_buildings.append(id)
    if not selected_buildings.is_empty():
        selected_building = selected_buildings[0]
        _notify("All %ss on screen!" % kind)

# Double-click: grab every on-screen unit of the same kind as the clicked one.
func _select_same_type_on_screen(kind: String) -> void:
    selected_units.clear()
    selected_building = -1
    var half := get_viewport().get_visible_rect().size / (2.0 * camera.zoom)
    var view := Rect2(camera.position - half, half * 2.0)
    for id: int in sim.units:
        var u: Dictionary = sim.units[id]
        if u.owner == local_slot and u.type == kind and view.has_point(u.pos):
            selected_units.append(id)
    if not selected_units.is_empty():
        _respond(selected_units[0], "All %ss on screen!" % kind)

func _attack_click(pos: Vector2) -> void:
    var kind := ""
    var target_id := -1
    for id: int in sim.units:
        if (sim.units[id].pos as Vector2).distance_to(pos) <= 24:
            kind = "unit"
            target_id = id
            break
    if target_id < 0:
        for id: int in sim.buildings:
            if sim.footprint(sim.buildings[id]).has_point(pos):
                kind = "building"
                target_id = id
                break
    if target_id >= 0:
        issue({"action": "attack", "units": selected_units.duplicate(), "kind": kind, "target": target_id, "force": true})
        clicks.append({"pos": pos, "life": 0.55, "action": "attack"})
    else:
        issue({"action": "attack_move", "units": selected_units.duplicate(), "pos": pos})
        clicks.append({"pos": pos, "life": 0.55, "action": "attack_move"})
    if not selected_units.is_empty():
        _respond(selected_units[0], "Attack order!")
    attack_mode = false

func _select_rect(rect: Rect2) -> void:
    _clear_selection()
    for id: int in sim.units:
        if sim.units[id].owner == local_slot and rect.has_point(sim.units[id].pos):
            selected_units.append(id)

# Ctrl+N assigns the selection to group N, Shift+N adds to it, N alone recalls it.
# A group can hold units and/or one building; recalling prefers units for orders.
func _control_group_key(group: int, ctrl: bool, shift: bool) -> void:
    if ctrl:
        if selected_units.is_empty() and selected_building < 0:
            control_groups.erase(group)
            _notify("Group %d cleared." % group)
            return
        var members: Array[int] = []
        for id: int in selected_units:
            members.append(id)
        var building_list: Array[int] = selected_buildings.duplicate()
        if building_list.is_empty() and selected_building >= 0:
            building_list.append(selected_building)
        control_groups[group] = {"units": members, "building": selected_building, "buildings": building_list}
        var label := "%d unit(s)" % members.size() if not members.is_empty() else "%d building(s)" % selected_buildings.size()
        _notify("Group %d assigned: %s." % [group, label])
        return
    if shift:
        if selected_units.is_empty() and selected_building < 0:
            return
        var merged: Dictionary = {"units": [], "building": -1}
        if control_groups.has(group):
            merged = (control_groups[group] as Dictionary).duplicate()
        var current: Array[int] = []
        for value: Variant in merged.get("units", []):
            current.append(int(value))
        for id: int in selected_units:
            if not current.has(id):
                current.append(id)
        merged.units = current
        if selected_building >= 0:
            merged.building = selected_building
        control_groups[group] = merged
        _notify("Group %d now has %d unit(s)." % [group, current.size()])
        return
    if not control_groups.has(group):
        return
    var state: Dictionary = control_groups[group]
    var group_units: Array[int] = []
    for value: Variant in state.get("units", []):
        var id := int(value)
        if sim.units.has(id) and sim.units[id].owner == local_slot and not group_units.has(id):
            group_units.append(id)
    var group_building := int(state.get("building", -1))
    if group_building >= 0 and (not sim.buildings.has(group_building) or sim.buildings[group_building].owner != local_slot):
        group_building = -1
    if group_units.is_empty() and group_building < 0:
        control_groups.erase(group)
        return
    if not group_units.is_empty():
        selected_units = group_units
        selected_building = -1
        selected_buildings.clear()
        _respond(group_units[0], "Group %d reporting." % group)
    else:
        var group_buildings: Array[int] = []
        for value: Variant in state.get("buildings", []):
            var bid := int(value)
            if sim.buildings.has(bid) and sim.buildings[bid].owner == local_slot and not group_buildings.has(bid):
                group_buildings.append(bid)
        selected_units.clear()
        selected_buildings = group_buildings
        selected_building = group_buildings[0] if not group_buildings.is_empty() else -1
        _notify("Group %d building ready." % group)

# Guest-side smoothing: derive per-unit velocity from consecutive snapshots.
func _update_render_velocities(previous: Dictionary, previous_frame: int, current_frame: int) -> void:
    render_velocities.clear()
    var ticks := current_frame - previous_frame
    if ticks < 1 or ticks > 10:
        return
    for id: int in sim.units:
        if not previous.has(id):
            continue
        var velocity: Vector2 = ((sim.units[id].pos as Vector2) - (previous[id] as Vector2)) / (ticks * 0.05)
        if velocity.length() > 400.0:
            velocity = velocity.normalized() * 400.0
        render_velocities[id] = velocity

# Extrapolate one render frame between snapshots so motion stays fluid on guests.
func _smooth_guest_motion(delta: float) -> void:
    for id: int in render_velocities:
        if sim.units.has(id):
            var u: Dictionary = sim.units[id]
            u.pos = (u.pos as Vector2) + (render_velocities[id] as Vector2) * delta
    for e: Dictionary in sim.effects:
        e.life = maxf(0.0, float(e.life) - delta * 20.0)

func _right_click(pos: Vector2) -> void:
    pending_command = ""
    if not Rect2(Vector2.ZERO, Simulation.WORLD).has_point(pos):
        return
    if selected_units.is_empty():
        var rally_targets: Array[int] = selected_buildings.duplicate()
        if rally_targets.is_empty() and selected_building >= 0:
            rally_targets.append(selected_building)
        if not rally_targets.is_empty():
            for id: int in rally_targets:
                issue({"action": "set_rally", "building": id, "pos": pos})
            _notify("Rally points set.")
            clicks.append({"pos": pos, "life": 0.55, "action": "rally"})
        return
    var order := {"action": "move", "units": selected_units.duplicate(), "pos": pos}
    for kind: String in ["unit", "building"]:
        var collection: Dictionary = sim.units if kind == "unit" else sim.buildings
        for id: int in collection:
            var target: Dictionary = collection[id]
            var hit: bool = (target.pos as Vector2).distance_to(pos) < 24 if kind == "unit" else sim.footprint(target).has_point(pos)
            if target.owner != local_slot and hit:
                if sim.can_see(local_slot, target.pos):
                    order = {"action": "attack", "units": selected_units.duplicate(), "kind": kind, "target": id}
    for id: int in sim.ores:
        if (sim.ores[id].pos as Vector2).distance_to(pos) < 38 and sim.ores[id].amount > 0:
            order = {"action": "gather", "units": selected_units.duplicate(), "target": id}
    issue(order)
    if not selected_units.is_empty():
        var reply := "Moving out!"
        if order.action == "attack":
            reply = "Engaging target!"
        elif order.action == "gather":
            reply = "Mining operation!"
        _respond(selected_units[0], reply)
    clicks.append({"pos": pos, "life": 0.55, "action": order.action})

func _begin_build(kind: String) -> void:
    if not active or local_slot == 0 or sim.winner != 0:
        return
    build_mode = kind
    pending_command = ""
    attack_mode = false
    selection_dragging = false
    _notify("Left-click a green site to build; right-click cancels.")
    _play_tone(300.0, 0.08, 0.12)

# Bottom action bar: dispatch a clicked button to the matching unit or building command.
func _action_clicked(index: int) -> void:
    if not selected_units.is_empty():
        var kind: String = sim.units[selected_units[0]].type
        match index:
            0:
                _stop()
            1:
                _begin_pending("move")
            2:
                if kind == "soldier":
                    attack_mode = not attack_mode
                    _notify("Attack mode %s. Left-click a target or ground." % ("ON" if attack_mode else "OFF"))
                else:
                    _begin_pending("gather")
    elif sim.buildings.has(selected_building):
        var building: Dictionary = sim.buildings[selected_building]
        match index:
            1:
                if building.type == "barracks":
                    _produce("soldier")
                elif building.type == "refinery":
                    _produce("harvester")
            2:
                _begin_build("barracks")
            3:
                _begin_build("refinery")
            4:
                _cancel_job()
            5:
                _begin_build("bunker")
            6:
                _begin_build("base")

# Queue a command that waits for the next battlefield left-click.
func _begin_pending(kind: String) -> void:
    if not active or menu_visible or selected_units.is_empty():
        return
    pending_command = kind
    attack_mode = false
    build_mode = ""
    _notify("Left-click a destination." if kind == "move" else "Left-click an ore patch to gather.")

func _pending_click(pos: Vector2) -> void:
    var order := {"action": pending_command, "units": selected_units.duplicate(), "pos": pos}
    if pending_command == "gather":
        var ore_id := -1
        for id: int in sim.ores:
            if sim.ores[id].amount > 0 and (sim.ores[id].pos as Vector2).distance_to(pos) < 38:
                ore_id = id
        if ore_id < 0:
            _notify("Left-click an ore patch to gather.")
            return
        order = {"action": "gather", "units": selected_units.duplicate(), "target": ore_id}
    issue(order)
    _respond(selected_units[0], "Moving out!" if pending_command == "move" else "Mining operation!")
    clicks.append({"pos": pos, "life": 0.55, "action": pending_command})
    pending_command = ""

func _begin_rebind() -> void:
    rebinding_attack = true
    _notify("Press a key to assign the attack command. Esc cancels.")

func _place_building(pos: Vector2) -> void:
    var error := sim.build_error(local_slot, build_mode, pos)
    if not error.is_empty():
        _notify(error)
        return
    issue({"action": "build", "type": build_mode, "pos": pos})
    build_mode = ""

func _produce(kind: String) -> void:
    # With several compatible producers selected, spread jobs across them by
    # always choosing the completed building with the shortest queue.
    var best := selected_building
    var best_queue := 99
    for id: int in selected_buildings:
        var b: Dictionary = sim.buildings.get(id, {})
        if b.is_empty() or int(b.remaining) > 0:
            continue
        if b.queue.size() < best_queue:
            best_queue = b.queue.size()
            best = id
    issue({"action": "produce", "building": best, "type": kind})
    _play_tone(520.0, 0.08, 0.12, 100.0)

func _cancel_job() -> void:
    issue({"action": "cancel_production", "building": selected_building})

func _stop() -> void:
    issue({"action": "stop", "units": selected_units.duplicate()})
    if not selected_units.is_empty():
        _respond(selected_units[0], "Standing by.")

func _audio_for_effects() -> void:
    for effect: Dictionary in sim.effects:
        var effect_frame := int(effect.get("frame", -1))
        if effect_frame <= audio_effect_frame or not sim.can_see(local_slot, effect.to):
            continue
        audio_effect_frame = maxi(audio_effect_frame, effect_frame)
        if effect.kind == "shot":
            _play_attack_sound()
        elif effect.kind == "death":
            _play_hit_sound()

func _toggle_menu() -> void:
    menu_visible       = not menu_visible
    menu.visible       = menu_visible
    selection_dragging = false
    middle_dragging    = false

func _close_menu() -> void:
    if active:
        menu_visible = false
        menu.visible = false

func _notify(message: String) -> void:
    feedback = message
    feedback_time = 8.0

# Keep all HUD text and command-card state in one place.
func _refresh_ui() -> void:
    var role := "BLUE" if local_slot == 1 else ("RED" if local_slot == 2 else "SPECTATOR")
    top_label.text = "IRON FRONT   /   %s     CREDITS: %d     %02d:%02d" % [role, int(sim.money.get(local_slot, 0)), sim.frame / 1200, (sim.frame / 20) % 60]
    resource_label.text = "MINERALS  %d" % int(sim.money.get(local_slot, 0))
    # Reset only the unused action slots: toggling an enabled Button every frame
    # would clear its internal press state and swallow the clicked signal.
    var active_actions := 0
    production_bar.visible = false
    production_queue_label.text = ""
    if not selected_units.is_empty():
        active_actions = 3
        var types: Array = _selected_unit_types()
        if action_type_index >= types.size():
            action_type_index = 0
        var current_type: String = types[action_type_index]
        var selected: Dictionary = sim.units[selected_units[0]]
        var stats: Dictionary = Simulation.UNIT_TYPES[current_type]
        if selected_units.size() == 1:
            selection_label.text = "UNIT STATUS   %s   |   HP %d / %d   |   ORDER: %s" % [current_type.to_upper(), selected.hp, stats.hp, str(selected.order).to_upper()]
        else:
            selection_label.text = "GROUP   %s" % _selection_roster()
        if types.size() > 1:
            selection_label.text += "   |   TAB: %s (%d/%d)" % [current_type.to_upper(), action_type_index + 1, types.size()]
        action_buttons[0].text = "STOP (S)"
        action_buttons[0].disabled = false
        action_buttons[1].text = "MOVE (RMB)"
        action_buttons[1].disabled = false
        if current_type == "soldier":
            action_buttons[2].text = "ATTACK (A) ON" if attack_mode else "ATTACK (A)"
        else:
            action_buttons[2].text = "GATHER (RMB)"
        action_buttons[2].disabled = false
    elif selected_buildings.size() > 1:
        var first: Dictionary = sim.buildings.get(selected_building, {})
        if first.is_empty() and not selected_buildings.is_empty():
            first = sim.buildings[selected_buildings[0]]
        selection_label.text = "BUILDINGS   %d x %s   |   Right-click: rally point" % [selected_buildings.size(), str(first.get("type", "")).to_upper()]
        var multi_labels: Dictionary = {}
        if first.type == "barracks":
            active_actions = 5
            multi_labels = {1: "SOLDIER ($100)", 4: "CANCEL (Refund)"}
        elif first.type == "refinery":
            active_actions = 5
            multi_labels = {1: "MINER ($200)", 4: "CANCEL (Refund)"}
        for i in range(action_buttons.size()):
            if multi_labels.has(i):
                action_buttons[i].text     = str(multi_labels[i])
                action_buttons[i].disabled = false
            else:
                action_buttons[i].text     = "—"
                action_buttons[i].disabled = true
        var total_jobs := 0
        for id: int in selected_buildings:
            total_jobs += sim.buildings.get(id, {}).get("queue", []).size()
        production_queue_label.text = "TOTAL QUEUE: %d" % total_jobs
    elif sim.buildings.has(selected_building):
        var b: Dictionary = sim.buildings[selected_building]
        var rally_hint := "   |   Right-click: rally point" if b.type in ["barracks", "refinery"] else ""
        selection_label.text = "BUILDING   %s   |   HP %d / %d%s" % [str(b.type).to_upper(), b.hp, Simulation.BUILD_TYPES[b.type].hp, rally_hint]
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
        for i in range(action_buttons.size()):
            if labels.has(i):
                action_buttons[i].text     = str(labels[i])
                action_buttons[i].disabled = false
            else:
                action_buttons[i].text     = "—"
                action_buttons[i].disabled = true
        if not b.queue.is_empty():
            var job: Dictionary = b.queue[0]
            var job_time: int = Simulation.UNIT_TYPES[job.type].time
            var progress := 100.0 * (1.0 - float(job.remaining) / job_time)
            production_bar.visible = true
            production_bar.max_value = job_time
            production_bar.value = job_time - int(job.remaining)
            production_queue_label.text = "QUEUE (%d / 5)\n" % b.queue.size()
            production_queue_label.text += "Now: %s %.0f%%\n" % [str(job.type).to_upper(), progress]
            if b.queue.size() > 1:
                var next_names: Array = []
                for i: int in range(1, mini(4, b.queue.size())):
                    next_names.append(str(b.queue[i].type).to_upper())
                production_queue_label.text += "Next: %s" % "+".join(next_names)
                if b.queue.size() > 4:
                    production_queue_label.text += " +%d more" % (b.queue.size() - 4)
        else:
            production_bar.visible = false
            production_queue_label.text = "QUEUE EMPTY"
    else:
        selection_label.text = "UNIT STATUS\nNo unit selected — left-click a unit on the battlefield."
    for i in range(action_buttons.size()):
        if i >= active_actions:
            action_buttons[i].text = "—"
            action_buttons[i].disabled = true
    resume_button.disabled = not active
    message_label.text = feedback if feedback_time > 0 else "Left: select / dbl-click: same type    Right: order / rally    A: attack    B: barracks    S: stop    Ctrl/Shift+N: groups    Esc: menu"
    result_label.text = ""
    if sim.winner > 0:
        result_label.text = "DRAW" if sim.winner == 3 else ("VICTORY" if sim.winner == local_slot else "DEFEAT")
        result_label.text += "  — Esc to restart / return"
    for n: int in range(group_cards.size()):
        var group_number := n + 1
        if control_groups.has(group_number):
            var group_state: Dictionary = control_groups[group_number]
            var units_in_group: Array = group_state.get("units", [])
            var buildings_in_group: Array = group_state.get("buildings", [])
            var first_name := "—"
            if not units_in_group.is_empty() and sim.units.has(int(units_in_group[0])):
                first_name = str(sim.units[int(units_in_group[0])].type).to_upper()
            elif not buildings_in_group.is_empty() and sim.buildings.has(int(buildings_in_group[0])):
                first_name = str(sim.buildings[int(buildings_in_group[0])].type).to_upper()
            group_cards[n].text = "%d: %s" % [group_number, first_name]
            group_cards[n].modulate = Color.WHITE
        else:
            group_cards[n].text = "%d —" % group_number
            group_cards[n].modulate = Color(1, 1, 1, 0.35)
    if sim.buildings.has(selected_building):
        var b: Dictionary = sim.buildings[selected_building]
        info_label.text = "%s\nHP %d / %d\n%s" % [str(b.type).to_upper(), b.hp, Simulation.BUILD_TYPES[b.type].hp, "Construction: %.1fs" % (float(b.remaining) / 20) if b.remaining > 0 else "Ready"]
        queue_label.text = "PRODUCTION (%d / 5)\n" % b.queue.size()
        for job: Dictionary in b.queue:
            queue_label.text += "%s  %.1fs\n" % [job.type, float(job.remaining) / 20]
        if not b.queue.is_empty() and int(b.queue[0].remaining) == 0:
            queue_label.text += "Exit blocked — clear nearby units"
    elif not selected_units.is_empty():
        info_label.text = "%d UNIT(S) SELECTED\n" % selected_units.size()
        var u: Dictionary = sim.units[selected_units[0]]
        info_label.text += "%s / HP %d\nOrder: %s" % [u.type, u.hp, u.order]
        if u.type == "harvester":
            info_label.text += " / Cargo %d / 60" % u.cargo
        queue_label.text = "Select a refinery for miners.\nSelect a barracks for soldiers."
    else:
        info_label.text = "No selection\nSelect units or a building.\nHarvesters return ore to a base."
        queue_label.text = "Buildings cost credits.\nPlace near your existing base."

# Render world geometry and entities; UI is rendered by CanvasLayer controls.
func _draw() -> void:
    for rock: Rect2 in sim.obstacles:
        draw_rect(rock, Color("#29352e"))
        for x in range(int(rock.position.x), int(rock.end.x), 32):
            for y in range(int(rock.position.y), int(rock.end.y), 32):
                draw_texture_rect(sprites[1].rock, Rect2(Vector2(x, y), Vector2(36, 36)), false)
    for ore: Dictionary in sim.ores.values():
        if ore.amount > 0:
            draw_texture_rect(sprites[1].ore, Rect2(ore.pos - Vector2(32, 24), Vector2(64, 48)), false)
            draw_string(ThemeDB.fallback_font, ore.pos + Vector2(-22, 36), str(ore.amount), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#f5d677"))
    for id: int in sim.buildings:
        var b: Dictionary = sim.buildings[id]
        if b.owner != local_slot and not sim.can_see(local_slot, b.pos):
            continue
        var rect: Rect2 = sim.footprint(b)
        draw_rect(Rect2(rect.position + Vector2(6, 10), rect.size), Color(0, 0, 0, 0.3))
        var tint := Color(0.65, 0.65, 0.65) if b.remaining > 0 else Color.WHITE
        if b.flash > 0:
            tint = Color(2, 2, 2)
        draw_texture_rect(sprites[b.owner][b.type], rect, false, tint)
        _bar(rect.position - Vector2(0, 8), rect.size.x, float(b.hp) / Simulation.BUILD_TYPES[b.type].hp, Color("#75c46e"))
        if b.remaining > 0:
            _bar(rect.position + Vector2(0, rect.size.y + 4), rect.size.x, 1.0 - float(b.remaining) / Simulation.BUILD_TYPES[b.type].time, Color("#eac75b"))
        if selected_building == id:
            draw_rect(rect.grow(3), Color("#dfe995"), false, 2)
            if b.type == "bunker":
                draw_arc(b.pos, Simulation.BUILD_TYPES.bunker.range, 0, TAU, 48, Color(0.55, 0.85, 1.0, 0.35), 1)
            if b.has("rally") and (b.rally as Vector2) != Vector2.ZERO:
                draw_line(b.pos, b.rally, Color(0.55, 0.85, 1.0, 0.5), 1)
                draw_circle(b.rally, 9, Color(0.55, 0.85, 1.0, 0.35))
                draw_circle(b.rally, 4, Color("#c8ecff"))
                draw_string(ThemeDB.fallback_font, b.rally + Vector2(10, -8), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#c8ecff"))
    for id: int in sim.units:
        var u: Dictionary = sim.units[id]
        if u.owner != local_slot and not sim.can_see(local_slot, u.pos):
            continue
        var pos: Vector2 = u.pos
        if selected_units.has(id):
            draw_arc(pos, 19, 0, TAU, 24, Color("#cbef84"), 2)
            if u.order == "attack":
                var targets: Dictionary = sim.units if u.attack_kind == "unit" else sim.buildings
                if targets.has(int(u.attack_id)):
                    draw_line(pos, targets[int(u.attack_id)].pos, Color(0.9, 0.25, 0.15, 0.45), 1)
        draw_rect(Rect2(pos + Vector2(-11, 8), Vector2(24, 8)), Color(0, 0, 0, 0.3))
        var size := Vector2(30, 30) if u.type == "soldier" else Vector2(36, 36)
        draw_texture_rect(sprites[u.owner][u.type], Rect2(pos - size / 2, size), false, Color(2, 2, 2) if u.flash > 0 else Color.WHITE)
        _bar(pos + Vector2(-15, -24), 30, float(u.hp) / Simulation.UNIT_TYPES[u.type].hp, Color("#75c46e"))
        if u.type == "harvester" and u.cargo > 0:
            _bar(pos + Vector2(-15, 23), 30, float(u.cargo) / 60, Color("#eac75b"))
        if id == speech_unit and speech_time > 0.0:
            var bubble := Rect2(pos + Vector2(18, -48), Vector2(126, 25))
            draw_rect(bubble, Color("#eef2d8"), true)
            draw_rect(bubble, Color("#27352f"), false, 1)
            draw_string(ThemeDB.fallback_font, bubble.position + Vector2(5, 17), speech_text, HORIZONTAL_ALIGNMENT_LEFT, 116, 11, Color("#18231f"))
    for e: Dictionary in sim.effects:
        if not sim.can_see(local_slot, e.to):
            continue
        if e.kind == "shot":
            var progress := 1.0 - float(e.life) / 5.0
            var point: Vector2 = (e.from as Vector2).lerp(e.to, progress)
            draw_line(e.from, point, Color("#dfb66a"), 1)
            draw_circle(point, 3, Color("#ffe9a2"))
            draw_circle(e.to, 5 * (1.0 - progress), Color("#ff8c50"))
        else:
            draw_circle(e.to, 5 + (10 - e.life) * 2, Color(1, 0.6, 0.2, float(e.life) / 10))
    if local_slot in [1, 2]:
        for y in range(Simulation.GRID.y):
            for x in range(Simulation.GRID.x):
                var index := y * Simulation.GRID.x + x
                if sim.visible[local_slot][index] == 0:
                    var alpha := 0.62 if sim.explored[local_slot][index] == 1 else 1.0
                    draw_rect(Rect2(x * 32, y * 32, 32, 32), Color(0.035, 0.055, 0.055, alpha))
    for click: Dictionary in clicks:
        var p: float = 1.0 - click.life / 0.55
        var color := Color("#ffc359") if click.action != "attack" else Color("#ff725e")
        color.a = 1 - p
        draw_arc(click.pos, lerpf(8, 32, p), 0, TAU, 24, color, 2)
        draw_line(click.pos - Vector2(7, 0), click.pos + Vector2(7, 0), color, 2)
        draw_line(click.pos - Vector2(0, 7), click.pos + Vector2(0, 7), color, 2)
    if selection_dragging:
        var rect := Rect2(selection_start, selection_current - selection_start).abs()
        draw_rect(rect, Color(0.7, 1, 0.5, 0.15))
        draw_rect(rect, Color("#c5e79d"), false, 1)
    if not build_mode.is_empty() and not menu_visible:
        var pos: Vector2 = sim.snap_build(get_global_mouse_position())
        var size: Vector2 = Simulation.BUILD_TYPES[build_mode].size
        var color := Color(0.45, 1, 0.45, 0.6) if sim.build_error(local_slot, build_mode, pos).is_empty() else Color(1, 0.3, 0.3, 0.6)
        draw_texture_rect(sprites[local_slot][build_mode], Rect2(pos - size / 2, size), false, color)
        draw_rect(Rect2(pos - size / 2, size).grow(16), color, false, 2)

func _bar(pos: Vector2, width: float, fraction: float, color: Color) -> void:
    draw_rect(Rect2(pos, Vector2(width, 4)), Color("#182219"))
    draw_rect(Rect2(pos, Vector2(width * clampf(fraction, 0, 1), 4)), color)
