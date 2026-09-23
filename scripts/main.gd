extends Node3D
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
var building_tab_index := 0
var group_cards: Array[Button] = []
var bottom_zones: Dictionary = {}
var roster_row: HBoxContainer
var production_queue_row: HBoxContainer
var cjk_font: SystemFont

# Placeholder thumbnails; swap the character for a texture once art exists.
const UNIT_THUMBNAILS := {"soldier": "兵", "harvester": "矿"}
var selection_start := Vector2.ZERO
var selection_current := Vector2.ZERO
var middle_dragging := false
var build_mode := ""
var menu_visible := true
var camera: Camera3D
var camera_zoom_level := 1.0
var camera_controller: CameraController
var terrain_chunks: Array[MeshInstance3D] = []
var fog_plane: MeshInstance3D
var fog_texture: ImageTexture
var fog_image: Image
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
var camera_speed_multiplier := 1.8
var camera_speed_slider: HSlider
var camera_speed_value_label: Label

# Scene bootstrap: create the simulation, world tiles, camera, HUD, and audio.
# Remove and free all children immediately so refreshes can rebuild inline.
func _clear_container(container: Control) -> void:
    for child: Node in container.get_children():
        container.remove_child(child)
        child.free()

# Build one unit thumbnail tile (placeholder glyph today, art later) with an
# optional caption such as "x6" or "37%".
func _make_unit_thumbnail(kind: String, caption: String, size: int) -> VBoxContainer:
    var tile := VBoxContainer.new()
    tile.add_theme_constant_override("separation", 0)
    var icon := Button.new()
    icon.custom_minimum_size = Vector2(size, size)
    icon.text = str(UNIT_THUMBNAILS.get(kind, "?"))
    icon.tooltip_text = kind
    icon.add_theme_font_size_override("font_size", int(size * 0.5))
    if cjk_font != null:
        icon.add_theme_font_override("font", cjk_font)
    tile.add_child(icon)
    if not caption.is_empty():
        var count_label := Label.new()
        count_label.text = caption
        count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        count_label.add_theme_font_size_override("font_size", 12)
        tile.add_child(count_label)
    return tile

# Register one named command-bar zone; returns its content container so
# callers can populate it. Future zones plug in without layout surgery.
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
    bottom_zones[key] = zone
    return zone

# Bake the procedural tile pattern into four ground planes (Don't Starve stage).
func _create_terrain() -> void:
    # Single continuous ground plane: no seams, no floating patches.
    var tex := ImageTexture.create_from_image(Art.terrain_image())
    var mesh := PlaneMesh.new()
    mesh.size = Simulation.WORLD
    var surface := StandardMaterial3D.new()
    surface.albedo_texture = tex
    surface.albedo_color = Color("#425238")
    surface.roughness = 0.88
    surface.metallic = 0.0
    surface.cull_mode = BaseMaterial3D.CULL_DISABLED
    # Repeat the 48x16 tileset across the whole 4800x3200 world.
    surface.texture_repeat = true
    surface.uv1_scale = Vector3(Simulation.WORLD.x / 144.0, Simulation.WORLD.y / 16.0, 1.0)
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    mi.material_override = surface
    mi.position = Vector3(Simulation.WORLD.x / 2.0, 0, Simulation.WORLD.y / 2.0)
    add_child(mi)
    terrain_chunks.append(mi)

# Clear battlefield lighting makes the mechanical models readable from above.
func _create_lighting() -> void:
    var sun := DirectionalLight3D.new()
    sun.name = "BattlefieldSun"
    sun.rotation_degrees = Vector3(-55, -32, 0)
    sun.light_color = Color("#fff1d6")
    sun.light_energy = 1.12
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 1600.0
    add_child(sun)

    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color("#203028")
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("#9fb6a6")
    environment.ambient_light_energy = 0.72
    environment.glow_enabled = true
    environment.glow_intensity = 0.35
    var world_environment := WorldEnvironment.new()
    world_environment.name = "BattlefieldEnvironment"
    world_environment.environment = environment
    add_child(world_environment)


# One low-res alpha texture covers the whole map fog (nearest-filtered).
func _create_fog() -> void:
    fog_image = Image.create(Simulation.GRID.x, Simulation.GRID.y, false, Image.FORMAT_RGBA8)
    fog_texture = ImageTexture.create_from_image(fog_image)

    var mesh := PlaneMesh.new()
    mesh.size = Simulation.WORLD
    var surface := StandardMaterial3D.new()
    surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    surface.albedo_texture = fog_texture
    surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    fog_plane = MeshInstance3D.new()
    fog_plane.mesh = mesh
    fog_plane.material_override = surface
    fog_plane.position = Vector3(Simulation.WORLD.x / 2.0, 1.0, Simulation.WORLD.y / 2.0)
    add_child(fog_plane)

# Fixed-pitch perspective camera looking at the focus point on the ground.
func _update_camera_transform() -> void:
    if camera_controller != null:
        camera_controller.focus = camera_controller.focus.clamp(Vector2.ZERO, Simulation.WORLD)
    var focus3 := Vector3(camera_controller.focus.x, 0, camera_controller.focus.y)
    var pitch := deg_to_rad(42.0)
    var dist := 1200.0 / camera_zoom_level
    camera.position = focus3 + Vector3(0, dist * sin(pitch), -dist * cos(pitch))
    camera.look_at(focus3)

# Project a ground point back to screen space (for input event construction).
func _world_to_screen(world: Vector2) -> Vector2:
    return camera.unproject_position(Vector3(world.x, 0, world.y))

# Project a screen point onto the y=0 ground plane.
func _screen_to_world(screen: Vector2) -> Vector2:
    var from := camera.project_ray_origin(screen)
    var dir := camera.project_ray_normal(screen)
    if absf(dir.y) < 0.001:
        return camera_controller.focus
    var t := -from.y / dir.y
    if t < 0.0:
        return camera_controller.focus
    var hit := from + dir * t
    return Vector2(hit.x, hit.z)

# Make a billboard sprite standing on the ground.
func _make_billboard(tex: Texture2D, size: Vector2, pos2d: Vector2) -> Sprite3D:
    var sprite := Sprite3D.new()
    sprite.texture = tex
    sprite.pixel_size = size.y / maxf(tex.get_height(), 1.0)
    sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    sprite.shaded = false

    sprite.position = Vector3(pos2d.x, size.y / 2.0, pos2d.y)
    return sprite

func _ready() -> void:
    _load_settings()
    sim.reset(false)
    _create_terrain()
    _create_lighting()
    _create_fog()
    camera = Camera3D.new()
    camera.fov = 38.0
    camera.near = 1.0
    camera.far = 5000.0
    add_child(camera)
    camera.make_current()
    camera_controller = CameraController.new(camera, Simulation.WORLD,
        func() -> Vector2: return get_viewport().get_visible_rect().size,
        func() -> Vector2: return get_viewport().get_mouse_position())
    camera_controller.speed_multiplier = camera_speed_multiplier
    camera_controller.focus = Vector2(900, 700)
    _update_camera_transform()
    _create_ui()
    _create_audio()
    multiplayer.peer_connected.connect(_peer_joined)
    multiplayer.peer_disconnected.connect(_peer_left)
    multiplayer.connected_to_server.connect(_connected_to_server)
    multiplayer.connection_failed.connect(_connection_failed)
    multiplayer.server_disconnected.connect(_server_left)
    _refresh_ui()
func _load_settings() -> void:
    var config := ConfigFile.new()
    if config.load("user://settings.cfg") == OK:
        camera_speed_multiplier = clampf(float(config.get_value("camera", "speed_multiplier", 1.8)), 0.5, 3.0)

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
    # The command bar is composed of named zones; future zones (minimap,
    # extras) plug in through _add_bottom_zone without touching the layout.
    _add_bottom_zone(bottom_row, "map", Vector2(220, 96), "", false)
    var status_zone: VBoxContainer = _add_bottom_zone(bottom_row, "status", Vector2(0, 96), "STATUS", true)
    var status_content := HBoxContainer.new()
    status_content.add_theme_constant_override("separation", 12)
    status_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    status_zone.add_child(status_content)
    cjk_font = SystemFont.new()
    cjk_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "sans-serif"])
    roster_row = HBoxContainer.new()
    roster_row.add_theme_constant_override("separation", 6)
    # Fixed width keeps the queue anchor stable no matter the roster size.
    roster_row.custom_minimum_size = Vector2(260, 0)
    status_content.add_child(roster_row)
    var production_panel := VBoxContainer.new()
    production_panel.add_theme_constant_override("separation", 4)
    status_content.add_child(production_panel)
    production_queue_label = Label.new()
    production_queue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    production_queue_label.add_theme_font_size_override("font_size", 13)
    production_queue_label.text = ""
    production_panel.add_child(production_queue_label)
    production_queue_row = HBoxContainer.new()
    production_queue_row.add_theme_constant_override("separation", 4)
    # Fixed five-slot strip: job i always renders at the same x position.
    production_queue_row.custom_minimum_size = Vector2(240, 0)
    production_panel.add_child(production_queue_row)
    production_bar = ProgressBar.new()
    production_bar.custom_minimum_size = Vector2(180, 16)
    production_bar.show_percentage = true
    production_bar.visible = false
    production_panel.add_child(production_bar)
    selection_label = Label.new()
    selection_label.custom_minimum_size = Vector2(0, 76)
    selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    selection_label.add_theme_font_size_override("font_size", 16)
    selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    selection_label.text = "UNIT STATUS\nNo unit selected — left-click a unit on the battlefield."
    status_content.add_child(selection_label)
    var command_zone: VBoxContainer = _add_bottom_zone(bottom_row, "command", Vector2(420, 96), "COMMAND", false)
    action_grid = GridContainer.new()
    action_grid.columns = 4
    action_grid.custom_minimum_size = Vector2(420, 96)
    command_zone.add_child(action_grid)
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
    # 0.45 caps at ~2670 dist (~1780 height, ~1x world width visible).
    return 0.45

func _reset_view() -> void:
    _clear_selection()
    build_mode = ""
    clicks.clear()
    camera_zoom_level = 2.0
    camera_controller.focus = Vector2(900, 700) if local_slot != 2 else Vector2(3900, 2500)
    _update_camera_transform()
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
        camera_controller.focus -= direction * delta * 500 * camera_speed_multiplier / camera_zoom_level
        camera_controller.update(delta)
    _limit_camera()
    _clean_selection()
    # Safety net: if the release event was lost entirely, finish the drag on
    # the first frame where our tracked button state says it was released.
    if selection_dragging and not left_button_held:
        _finish_drag_select(selection_current)
    _refresh_ui()
    _sync_visuals()

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
        if selected_building >= 0 and sim.buildings.has(selected_building) and sim.buildings[selected_building].owner == local_slot:
            selected_buildings.append(selected_building)
        else:
            selected_building = -1
    elif not selected_buildings.has(selected_building):
        selected_building = selected_buildings[0]
    if not sim.buildings.has(selected_building) or sim.buildings[selected_building].owner != local_slot:
        selected_building = -1

func _get_camera_viewport_size() -> Vector2:
    return get_viewport().get_visible_rect().size

func _get_map_screen_rect() -> Rect2:
        var size := get_viewport().get_visible_rect().size
        return Rect2(Vector2(0, 52), Vector2(size.x - 260, size.y - 184))

func _limit_camera() -> void:
    if camera_controller != null:
        camera_controller._limit_camera()
        _update_camera_transform()

func _screen_is_map(pos: Vector2) -> bool:
    var size := get_viewport().get_visible_rect().size
    return pos.x < size.x - 260 and pos.y > 52 and pos.y < size.y - 132

# Translate keyboard and mouse input into selection and simulation orders.
func _unhandled_input(event: InputEvent) -> void:
    # _input and _unhandled_input can receive different subsets of injected or
    # platform events, so keep the anti-duplicate timestamp accurate in both.
    if event is InputEventMouseMotion:
        last_mouse_event_msec = Time.get_ticks_msec()
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
            if selected_buildings.size() > 1:
                building_tab_index = (building_tab_index + 1) % selected_buildings.size()
                _notify("Building %d / %d" % [building_tab_index + 1, selected_buildings.size()])
    if not active or menu_visible:
        return
    if event is InputEventMouseButton:
        var pos: Vector2 = _screen_to_world(event.position)
        var button := event as InputEventMouseButton
        if button.button_index == MOUSE_BUTTON_LEFT:
            var was_held := left_button_held
            if button.pressed and not button.canceled:
                left_button_held = true
            if button.pressed and _screen_is_map(event.position):
                # Preserve the original box when Windows emits a duplicate press
                # while the tracked button is still held. Stale drags fall
                # through so their lost release can be recovered below.
                if selection_dragging and was_held:
                    var press_msec := Time.get_ticks_msec()
                    if press_msec - last_mouse_event_msec < 1500:
                        return
                if not build_mode.is_empty():
                    _place_building(pos)
                else:
                    selection_dragging = true
                    selection_start    = pos
                    selection_current  = pos
            elif not button.pressed and selection_dragging:
                if not button.canceled:
                    _finish_drag_select(pos)
            if not button.pressed and not button.canceled:
                left_button_held = false
        elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed and _screen_is_map(event.position):
            if not build_mode.is_empty():
                build_mode = ""
            else:
                _right_click(pos)
        elif event.button_index == MOUSE_BUTTON_MIDDLE:
            middle_dragging = event.pressed
        elif event.pressed and _screen_is_map(event.position) and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
            var before := _screen_to_world(event.position)
            var factor := 1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
            camera_zoom_level = clampf(camera_zoom_level * factor, _min_zoom(), 6.0)
            # Iterative anchor: perspective projection needs multiple passes
            # to converge the world point under the cursor exactly.
            for i in range(3):
                _update_camera_transform()
                var after := _screen_to_world(event.position)
                camera_controller.focus += before - after
            _update_camera_transform()
    elif event is InputEventMouseMotion:
        if middle_dragging:
            camera_controller.focus += Vector2(event.relative.x, event.relative.y) / camera_zoom_level
        if selection_dragging:
            selection_current = _screen_to_world(event.position)

func _input(event: InputEvent) -> void:
    # _input runs before the HUD consumes events, so an active drag keeps
    # tracking (and can complete) even while the cursor is over HUD panels.
    if event is InputEventMouseMotion:
        last_mouse_event_msec = Time.get_ticks_msec()
        if selection_dragging:
            selection_current = _screen_to_world(event.position)
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
            _finish_drag_select(_screen_to_world(event.position))

# Complete a box drag: treat tiny drags as clicks, larger ones as selections.
func _finish_drag_select(pos: Vector2) -> void:
    selection_dragging = false
    if (pos - selection_start).length() * camera_zoom_level < 8:
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

# Double-click: grab every on-screen building of the same kind as the clicked one.
func _select_same_type_buildings_on_screen(kind: String) -> void:
    selected_units.clear()
    selected_buildings.clear()
    var half := camera_controller._visible_ground_rect().size / 2.0
    var view := Rect2(camera_controller.focus - half, half * 2.0)
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
    var half := camera_controller._visible_ground_rect().size / 2.0
    var view := Rect2(camera_controller.focus - half, half * 2.0)
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
        match index:
            0:
                _stop()
            1:
                _begin_pending("move")
            2:
                attack_mode = not attack_mode
                _notify("Attack mode %s. Left-click a target or ground." % ("ON" if attack_mode else "OFF"))
            3:
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
    var target := selected_building
    if selected_buildings.size() > 1:
        target = selected_buildings[building_tab_index % selected_buildings.size()]
    issue({"action": "cancel_production", "building": target})

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
        active_actions = 4
        var selected: Dictionary = sim.units[selected_units[0]]
        # Roster: one thumbnail tile per unit kind with its count.
        _clear_container(roster_row)
        var roster_counts := {}
        for id: int in selected_units:
            var roster_kind := str(sim.units[id].type)
            roster_counts[roster_kind] = int(roster_counts.get(roster_kind, 0)) + 1
        for roster_kind: String in roster_counts:
            roster_row.add_child(_make_unit_thumbnail(roster_kind, "x%d" % int(roster_counts[roster_kind]), 52))
        if selected_units.size() == 1:
            var stats: Dictionary = Simulation.UNIT_TYPES[selected.type]
            selection_label.text = "UNIT STATUS   |   HP %d / %d   |   ORDER: %s" % [selected.hp, stats.hp, str(selected.order).to_upper()]
        else:
            selection_label.text = "GROUP"
        # SC2-style command card: universal commands stay in fixed slots and
        # type-specific commands each get their own slot, all visible at once.
        var has_soldier := false
        var has_harvester := false
        for id: int in selected_units:
            if sim.units[id].type == "soldier":
                has_soldier = true
            elif sim.units[id].type == "harvester":
                has_harvester = true
        action_buttons[0].text     = "STOP (S)"
        action_buttons[0].disabled = false
        action_buttons[1].text     = "MOVE (RMB)"
        action_buttons[1].disabled = false
        action_buttons[2].text     = ("ATTACK (A) ON" if attack_mode else "ATTACK (A)") if has_soldier else "—"
        action_buttons[2].disabled = not has_soldier
        action_buttons[3].text     = "GATHER (RMB)" if has_harvester else "—"
        action_buttons[3].disabled = not has_harvester
    elif sim.buildings.has(selected_building):
        var b: Dictionary = sim.buildings[selected_building]
        var tab_prefix := ""
        if selected_buildings.size() > 1:
            building_tab_index = building_tab_index % selected_buildings.size()
            b = sim.buildings[selected_buildings[building_tab_index]]
            tab_prefix = "%d x %s  [%d/%d]   " % [selected_buildings.size(), str(b.type).to_upper(), building_tab_index + 1, selected_buildings.size()]
        var rally_hint := "   |   Right-click: rally point" if b.type in ["barracks", "refinery"] else ""
        selection_label.text = "BUILDING   %s%s   |   HP %d / %d%s" % [tab_prefix, str(b.type).to_upper(), b.hp, Simulation.BUILD_TYPES[b.type].hp, rally_hint]
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
        _clear_container(production_queue_row)
        if not b.queue.is_empty():
            var job: Dictionary = b.queue[0]
            var job_time: int = Simulation.UNIT_TYPES[job.type].time
            var progress := 100.0 * (1.0 - float(job.remaining) / job_time)
            production_bar.visible = true
            production_bar.max_value = job_time
            production_bar.value = job_time - int(job.remaining)
            production_queue_label.text = "QUEUE %d / 5" % b.queue.size()
            # The queue is a row of thumbnails; the first shows its progress.
            for i: int in b.queue.size():
                var entry: Dictionary = b.queue[i]
                var caption := "%.0f%%" % progress if i == 0 else ""
                production_queue_row.add_child(_make_unit_thumbnail(str(entry.type), caption, 40))
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
# Per-frame visual sync: manage 3D nodes from simulation state.
var unit_visuals: Dictionary = {}
var building_visuals: Dictionary = {}
var ore_visuals: Dictionary = {}
var rock_visuals: Array[EntityVisual] = []
var effect_visuals: Dictionary = {}
var marker_visuals: Dictionary = {}
var selection_rect_overlay: Panel
var build_preview_visual: MeshInstance3D
var build_preview_model: EntityVisual


func _sync_visuals() -> void:
    _sync_rocks()
    _sync_ores()
    _sync_buildings()
    _sync_units()
    _sync_effects()
    _sync_markers()
    _sync_selection_rect()
    _sync_build_preview()
    _sync_fog()


func _set_visual_visible(visual: EntityVisual, next_visible: bool) -> void:
    visual.visible = next_visible
    if visual.animation_player != null:
        visual.animation_player.active = next_visible

func _sync_rocks() -> void:
    if rock_visuals.is_empty():
        # Tile rock clusters across each obstacle footprint.
        var rock_index := 0
        for rock: Rect2 in sim.obstacles:
            var spacing := 72.0
            var cols := maxi(1, int(rock.size.x / spacing))
            var rows := maxi(1, int(rock.size.y / spacing))
            for cx in range(cols):
                for cy in range(rows):
                    var pos := Vector2(
                        rock.position.x + (cx + 0.5) * rock.size.x / cols,
                        rock.position.y + (cy + 0.5) * rock.size.y / rows
                    )
                    var variation_key := "%d_%d_%d" % [rock_index, cx, cy]
                    var jitter := _deterministic_rock_jitter(variation_key)
                    var scale_factor := _deterministic_rock_scale(variation_key)
                    var visual := EntityVisual.new("rock", 1)
                    visual.set_position_2d(pos + jitter)
                    visual.scale = Vector3.ONE * scale_factor
                    add_child(visual)
                    rock_visuals.append(visual)
            rock_index += 1

    # Fog: rocks only show in explored terrain (permanent reveal, like terrain).
    for visual: EntityVisual in rock_visuals:
        var cell := Vector2i((Vector2(visual.position.x, visual.position.z) / Simulation.CELL).floor()).clamp(Vector2i.ZERO, Vector2i(Simulation.GRID.x - 1, Simulation.GRID.y - 1))
        var index := cell.y * Simulation.GRID.x + cell.x
        var explored: PackedByteArray = sim.explored.get(local_slot, PackedByteArray())
        visual.visible = index >= 0 and index < explored.size() and explored[index] == 1


func _deterministic_rock_jitter(variation_key: String) -> Vector2:
    var x := float(absi(hash(variation_key + "_x")) % 29) - 14.0
    var y := float(absi(hash(variation_key + "_y")) % 29) - 14.0
    return Vector2(x, y)


func _deterministic_rock_scale(variation_key: String) -> float:
    return 0.72 + float(absi(hash(variation_key + "_scale")) % 39) / 100.0


func _sync_ores() -> void:
    var seen := {}
    for id: int in sim.ores:
        var ore: Dictionary = sim.ores[id]
        if not ore_visuals.has(id):
            var visual := EntityVisual.new("ore", 1)
            visual.name = "Ore%d" % id
            visual.set_position_2d(ore.pos)
            add_child(visual)
            var label := Label3D.new()
            label.text = str(ore.amount)
            label.font_size = 32
            label.pixel_size = 0.02
            label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
            label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            label.position = Vector3(0, visual.get_model_height() + 8, 0)
            visual.add_child(label)
            ore_visuals[id] = {"visual": visual, "label": label}
        var vis: Dictionary = ore_visuals[id]
        var visual: EntityVisual = vis.visual

        # Fog of war: only render ores the local player can currently see.
        _set_visual_visible(visual, ore.amount > 0 and sim.can_see(local_slot, ore.pos))
        visual.set_position_2d(ore.pos)
        var label: Label3D = vis.label
        if int(vis.get("last_amount", -1)) != ore.amount:
            label.text = str(ore.amount)
            vis["last_amount"] = ore.amount
        seen[id] = true
    for id: int in ore_visuals.keys():
        if not seen.has(id):
            ore_visuals[id].visual.queue_free()
            ore_visuals.erase(id)


func _sync_buildings() -> void:
    var seen := {}
    for id: int in sim.buildings:
        var b: Dictionary = sim.buildings[id]
        if not building_visuals.has(id):
            var visual := EntityVisual.new(b.type, b.owner)
            visual.name = "Building%d" % id
            visual.set_position_2d(b.pos)
            add_child(visual)
            var hp_bar := _make_status_bar(Simulation.BUILD_TYPES[b.type].size.x * 0.8, 5, Color("#75c46e"))
            hp_bar.position = Vector3(0, visual.get_model_height() + 12, 0)
            visual.add_child(hp_bar)
            building_visuals[id] = {"visual": visual, "hp_bar": hp_bar}
        var vis: Dictionary = building_visuals[id]
        var visual: EntityVisual = vis.visual

        # Fog: enemy buildings only render when currently visible.
        _set_visual_visible(visual, b.owner == local_slot or sim.can_see(local_slot, b.pos))
        visual.set_position_2d(b.pos)
        visual.set_flash(b.flash > 0)
        visual.set_construction_tint(b.remaining > 0)
        if b.remaining > 0:
            visual.set_animation("construction")
        elif b.type == "bunker" and int(b.cooldown) > 4:
            visual.set_animation("fire")
        elif not b.queue.is_empty() and b.type in ["barracks", "refinery"]:
            visual.set_animation("active")
        else:
            visual.set_animation("idle")

        _update_status_bar(vis.hp_bar, float(b.hp) / Simulation.BUILD_TYPES[b.type].hp)
        if b.remaining > 0:
            if not vis.has("build_bar"):
                var build_bar := _make_status_bar(Simulation.BUILD_TYPES[b.type].size.x * 0.8, 5, Color("#eac75b"))
                build_bar.position = Vector3(0, visual.get_model_height() + 20, 0)
                visual.add_child(build_bar)
                vis["build_bar"] = build_bar
            _update_status_bar(vis.build_bar, 1.0 - float(b.remaining) / Simulation.BUILD_TYPES[b.type].time)
        seen[id] = true
    for id: int in building_visuals.keys():
        if not seen.has(id):
            building_visuals[id].visual.queue_free()
            building_visuals.erase(id)


func _sync_units() -> void:
    var seen := {}
    for id: int in sim.units:
        var u: Dictionary = sim.units[id]
        if not unit_visuals.has(id):
            var visual := EntityVisual.new(u.type, u.owner)
            visual.name = "Unit%d" % id
            visual.set_position_2d(u.pos)
            add_child(visual)
            var hp_bar := _make_status_bar(30, 4, Color("#75c46e"))
            hp_bar.position = Vector3(0, visual.get_model_height() + 12, 0)
            visual.add_child(hp_bar)
            unit_visuals[id] = {"visual": visual, "hp_bar": hp_bar}
        var vis: Dictionary = unit_visuals[id]
        var visual: EntityVisual = vis.visual

        # Fog: enemy units only render when currently visible.
        _set_visual_visible(visual, u.owner == local_slot or sim.can_see(local_slot, u.pos))
        visual.set_position_2d(u.pos)
        visual.set_flash(u.flash > 0)
        visual.set_heading(_unit_heading(u, id))
        visual.set_animation(_unit_animation_state(u))
        _update_status_bar(vis.hp_bar, float(u.hp) / Simulation.UNIT_TYPES[u.type].hp)

        # Cargo bar for harvesters (reset when cargo drops to 0).
        if u.type == "harvester":
            if u.cargo > 0:
                if not vis.has("cargo_bar"):
                    var cargo_bar := _make_status_bar(30, 4, Color("#eac75b"))
                    cargo_bar.position = Vector3(0, visual.get_model_height() + 20, 0)
                    visual.add_child(cargo_bar)
                    vis["cargo_bar"] = cargo_bar
                _update_status_bar(vis.cargo_bar, float(u.cargo) / 60.0)
                vis.cargo_bar.visible = true
            elif vis.has("cargo_bar"):
                vis.cargo_bar.visible = false
        seen[id] = true
    for id: int in unit_visuals.keys():
        if not seen.has(id):
            unit_visuals[id].visual.queue_free()
            unit_visuals.erase(id)


func _unit_animation_state(u: Dictionary) -> String:
    if u.order == "attack":
        return "attack" if _unit_in_attack_range(u) else "move"
    if u.order in ["move", "attack_move"]:
        return "move"
    if u.type == "harvester" and u.order == "gather":
        var destination := _unit_destination(u)
        var near_target := (u.pos as Vector2).distance_to(destination) <= (46.0 if int(u.cargo) < 60 else 44.0)
        if near_target:
            return "unload" if int(u.cargo) > 0 else "mine"
        return "move"
    return "idle"


func _unit_destination(u: Dictionary) -> Vector2:
    if u.order == "attack":
        if u.attack_kind == "unit" and sim.units.has(int(u.attack_id)):
            return sim.units[int(u.attack_id)].pos
        if u.attack_kind == "building" and sim.buildings.has(int(u.attack_id)):
            return sim.buildings[int(u.attack_id)].pos
    if u.order == "gather" and u.type == "harvester":
        if int(u.cargo) >= 60:
            return _nearest_refinery_position(u)
        if sim.ores.has(int(u.ore)):
            return sim.ores[int(u.ore)].pos
    return u.target


func _nearest_refinery_position(u: Dictionary) -> Vector2:
    var best_position: Vector2 = u.pos
    var best_distance := INF
    for building: Dictionary in sim.buildings.values():
        var refinery: bool = building.type == "refinery" and building.owner == u.owner and building.remaining == 0
        var distance: float = (u.pos as Vector2).distance_to(building.pos) if refinery else INF
        if distance < best_distance:
            best_distance = distance
            best_position = building.pos
    return best_position


func _unit_in_attack_range(u: Dictionary) -> bool:
    var target_position: Vector2 = u.pos
    if u.attack_kind == "unit" and sim.units.has(int(u.attack_id)):
        target_position = sim.units[int(u.attack_id)].pos
    elif u.attack_kind == "building" and sim.buildings.has(int(u.attack_id)):
        var footprint := sim.footprint(sim.buildings[int(u.attack_id)])
        target_position = (u.pos as Vector2).clamp(footprint.position, footprint.end)
    else:
        return false
    return (u.pos as Vector2).distance_to(target_position) <= float(Simulation.UNIT_TYPES[u.type].range)


func _unit_heading(u: Dictionary, id: int) -> Vector2:
    var destination := _unit_destination(u)
    var heading := destination - (u.pos as Vector2)
    if heading.length_squared() > 1.0:
        return heading
    if render_velocities.has(id):
        return render_velocities[id]
    return Vector2.UP



var _dot_texture: ImageTexture

# Simple white dot for effects and click markers (tinted by modulate).
func _white_dot() -> ImageTexture:
    if _dot_texture == null:
        var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
        img.fill(Color.WHITE)
        _dot_texture = ImageTexture.create_from_image(img)
    return _dot_texture


# Create a status bar (bg + fill) as billboarded Sprite3D pair above a unit.
func _make_status_bar(width: float, height: float, fill_color: Color) -> Node3D:
    var holder := Node3D.new()
    var bg := Sprite3D.new()
    bg.texture = _white_dot()
    bg.pixel_size = 1.0
    bg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    bg.shaded = false
    bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    bg.modulate = Color("#182219")
    bg.scale = Vector3(width / 8.0, height / 8.0, 1)
    holder.add_child(bg)
    var fill := Sprite3D.new()
    fill.texture = _white_dot()
    fill.pixel_size = 1.0
    fill.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    fill.shaded = false
    fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    fill.modulate = fill_color
    fill.scale = Vector3(width / 8.0, height / 8.0, 1)
    fill.position.z = -0.5
    holder.add_child(fill)
    holder.set_meta("fill", fill)
    holder.set_meta("width", width)
    return holder

func _update_status_bar(holder: Node3D, fraction: float, color: Color = Color.TRANSPARENT) -> void:
    var fill: Sprite3D = holder.get_meta("fill")
    var width: float = holder.get_meta("width")
    fill.scale.x = maxf(0.01, width / 8.0 * clampf(fraction, 0.0, 1.0))
    if color != Color.TRANSPARENT:
        fill.modulate = color

func _sync_effects() -> void:
    var seen := {}
    for i: int in sim.effects.size():
        var e: Dictionary = sim.effects[i]
        # Fog: effects only render in visible areas.
        if not sim.can_see(local_slot, e.to):
            continue
        var key := "%d_%d" % [int(e.frame), i]
        if not effect_visuals.has(key):
            var sprite := Sprite3D.new()
            sprite.pixel_size = 2.0
            sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
            sprite.shaded = false
            sprite.texture = _white_dot()
            add_child(sprite)
            effect_visuals[key] = sprite
        var sprite: Sprite3D = effect_visuals[key]
        var progress := 1.0 - float(e.life) / 10.0
        if e.kind == "shot":
            var point := Vector3((e.from as Vector2).lerp(e.to, progress).x, 12, (e.from as Vector2).lerp(e.to, progress).y)
            point.y = 12
            sprite.position = point
            sprite.modulate = Color("#ffe9a2")
        else:
            var pos3 := Vector3((e.to as Vector2).x, 5 + (10 - e.life) * 2, (e.to as Vector2).y)
            sprite.position = pos3
            sprite.modulate = Color(1, 0.6, 0.2, float(e.life) / 10)
        seen[key] = true
    for key: String in effect_visuals.keys():
        if not seen.has(key):
            effect_visuals[key].queue_free()
            effect_visuals.erase(key)

func _sync_markers() -> void:
    var seen := {}
    for i: int in clicks.size():
        var click: Dictionary = clicks[i]
        var key := "click_%d" % i
        if not marker_visuals.has(key):
            var sprite := Sprite3D.new()
            sprite.pixel_size = 3.0
            sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
            sprite.shaded = false
            sprite.texture = _white_dot()
            add_child(sprite)
            marker_visuals[key] = sprite
        var sprite: Sprite3D = marker_visuals[key]
        var pos3 := Vector3((click.pos as Vector2).x, 5, (click.pos as Vector2).y)
        sprite.position = pos3
        var p: float = 1.0 - click.life / 0.55
        sprite.modulate = Color("#ffc359", 1.0 - p)
        seen[key] = true
    for key: String in marker_visuals.keys():
        if not seen.has(key):
            marker_visuals[key].queue_free()
            marker_visuals.erase(key)

func _sync_selection_rect() -> void:
    if selection_dragging:
        var start_screen := _world_to_screen(selection_start)
        var end_screen := _world_to_screen(selection_current)
        var rect := Rect2(start_screen, end_screen - start_screen).abs()
        if selection_rect_overlay == null:
            selection_rect_overlay = Panel.new()
            var style := StyleBoxFlat.new()
            style.bg_color = Color(0.7, 1, 0.5, 0.15)
            style.border_color = Color("#c5e79d")
            style.set_border_width_all(1)
            selection_rect_overlay.add_theme_stylebox_override("panel", style)
            selection_rect_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
            hud.add_child(selection_rect_overlay)
        selection_rect_overlay.position = rect.position
        selection_rect_overlay.size = rect.size
        selection_rect_overlay.visible = true
    elif selection_rect_overlay != null:
        selection_rect_overlay.visible = false

func _sync_build_preview() -> void:
    if not build_mode.is_empty() and not menu_visible:
        var pos: Vector2 = sim.snap_build(_screen_to_world(get_viewport().get_mouse_position()))
        var size: Vector2 = Simulation.BUILD_TYPES[build_mode].size
        var valid := sim.build_error(local_slot, build_mode, pos).is_empty()
        if build_preview_model != null and build_preview_model.kind != build_mode:
            build_preview_model.queue_free()
            build_preview_model = null
        if build_preview_model == null:
            build_preview_model = EntityVisual.new(build_mode, local_slot)
            add_child(build_preview_model)
        if build_preview_visual == null:
            var mesh := PlaneMesh.new()
            mesh.size = Vector2(100, 100)
            var surface := StandardMaterial3D.new()
            surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
            surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            build_preview_visual = MeshInstance3D.new()
            build_preview_visual.mesh = mesh
            build_preview_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            build_preview_visual.material_override = surface
            add_child(build_preview_visual)
        build_preview_model.visible = true
        build_preview_model.set_position_2d(pos)
        build_preview_model.set_animation("idle")
        build_preview_visual.visible = true
        build_preview_visual.position = Vector3(pos.x, 0.5, pos.y)
        build_preview_visual.scale = Vector3(size.x / 100.0, 1, size.y / 100.0)
        build_preview_visual.get_active_material(0).albedo_color = Color(0.45, 1, 0.45, 0.3) if valid else Color(1, 0.3, 0.3, 0.3)
    else:
        if build_preview_model != null:
            build_preview_model.visible = false
        if build_preview_visual != null:
            build_preview_visual.visible = false

func _sync_fog() -> void:
    if local_slot in [1, 2]:
        for y in range(Simulation.GRID.y):
            for x in range(Simulation.GRID.x):
                var index := y * Simulation.GRID.x + x
                if sim.visible[local_slot][index] == 0:
                    var alpha := 0.62 if sim.explored[local_slot][index] == 1 else 1.0
                    fog_image.set_pixel(x, y, Color(0.035, 0.055, 0.055, alpha))
                else:
                    fog_image.set_pixel(x, y, Color(0, 0, 0, 0))
        fog_texture.update(fog_image)
