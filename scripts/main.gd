extends Node3D
const Simulation = preload("res://scripts/simulation.gd")
const Art = preload("res://assets/art/pixel_art.gd")
const CameraController = preload("res://scripts/camera_controller.gd")
const WorldVisualSync = preload("res://scripts/world_visual_sync.gd")
const GameSession = preload("res://scripts/runtime/game_session.gd")
const CommandBus = preload("res://scripts/runtime/command_bus.gd")
const AudioController = preload("res://scripts/audio/audio_controller.gd")
const InputController = preload("res://scripts/controllers/input_controller.gd")
const NetworkSession = preload("res://scripts/runtime/network_session.gd")
const HudController = preload("res://scripts/ui/hud_controller.gd")
const CursorController = preload("res://scripts/ui/cursor_controller.gd")
const MapCatalog = preload("res://scripts/maps/map_catalog.gd")
const TerrainView = preload("res://scripts/maps/terrain_view.gd")
const SampleView = preload("res://scripts/maps/sample_view.gd")
const PORT := 24560
const MAX_CLIENTS := 4
var sim := Simulation.new()
var deploy_building := -1
var session: GameSession
var command_bus: CommandBus
var audio_controller: AudioController
var input_controller: InputController
var network_session: NetworkSession
var hud_controller: HudController
var cursor_controller: CursorController
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
var selected_map_id := "desert_quarry"
var terrain_view: TerrainView
var rendered_map_id := ""
var rendered_match_id := -1
var sample_host_button: Button
var solo_button: Button
var map_selector: OptionButton
var map_description: Label
var map_preview: TextureRect
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
var next_click_id := 0
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
var visual_sync: WorldVisualSync

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
    if terrain_view != null:
        terrain_view.free()
        terrain_view = null
    for chunk in terrain_chunks:
        if is_instance_valid(chunk):
            chunk.free()
    terrain_chunks.clear()
    rendered_map_id = sim.map_id
    if sim.map_id in ["desert_quarry", "desert_sample"]:
        terrain_view = SampleView.new() if sim.is_test_map() else TerrainView.new()
        add_child(terrain_view)
        terrain_view.build(sim.terrain, fog_texture)
        return
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
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    var sky := Sky.new()
    var sky_material := ProceduralSkyMaterial.new()
    sky_material.sky_top_color = Color("#708da5")
    sky_material.sky_horizon_color = Color("#c3b7a5")
    sky_material.ground_bottom_color = Color("#514a3e")
    sky_material.ground_horizon_color = Color("#a99b7b")
    sky.sky_material = sky_material
    environment.sky = sky
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
        if sim.is_test_map():
            var area: Rect2 = sim.terrain.definition.sample_bounds
            camera_controller.focus = camera_controller.focus.clamp(area.position + Vector2(128, 128), area.end - Vector2(128, 128))
    var focus3 := Vector3(camera_controller.focus.x, sim.terrain.height_at(camera_controller.focus), camera_controller.focus.y)
    var pitch := deg_to_rad(42.0)
    var dist := 1200.0 / camera_zoom_level
    camera.position = focus3 + Vector3(0, dist * sin(pitch), -dist * cos(pitch))
    camera.look_at(focus3)

# Project a ground point back to screen space (for input event construction).
func _world_to_screen(world: Vector2) -> Vector2:
    return camera.unproject_position(Vector3(world.x, sim.terrain.height_at(world), world.y))

# Project a screen point onto the y=0 ground plane.
func _screen_to_world(screen: Vector2) -> Vector2:
    var from := camera.project_ray_origin(screen)
    var dir := camera.project_ray_normal(screen)
    if sim.map_id != "prototype":
        var terrain_hit := sim.terrain.ray_hit(from, dir)
        if terrain_hit.is_finite():
            return Vector2(terrain_hit.x, terrain_hit.z)
        return Vector2(-1, -1)
    if absf(dir.y) < 0.001:
        return camera_controller.focus
    var t := -from.y / dir.y
    if t < 0.0:
        return camera_controller.focus
    var hit := from + dir * t
    return Vector2(hit.x, hit.z)

func _ready() -> void:
    _load_settings()
    session = GameSession.new()
    session.configure(sim)
    session.simulation_tick.connect(_on_session_tick)
    add_child(session)
    command_bus = CommandBus.new()
    command_bus.configure(_execute_order)
    command_bus.command_rejected.connect(_notify)
    input_controller = InputController.new()
    input_controller.name = "InputController"
    input_controller.configure(self)
    add_child(input_controller)
    # Main owns the engine callbacks and delegates once through the compatibility
    # wrappers below. Disable the child callbacks to avoid processing each event twice.
    input_controller.set_process_input(false)
    input_controller.set_process_unhandled_input(false)
    network_session = NetworkSession.new()
    network_session.name = "NetworkSession"
    network_session.configure(self)
    add_child(network_session)
    sim.reset(false, selected_map_id)
    _create_fog()
    _create_terrain()
    _create_lighting()
    camera = Camera3D.new()
    camera.fov = 38.0
    camera.near = 1.0
    camera.far = 12000.0
    add_child(camera)
    camera.make_current()
    camera_controller = CameraController.new(camera, Simulation.WORLD,
        func() -> Vector2: return get_viewport().get_visible_rect().size,
        func() -> Vector2: return get_viewport().get_mouse_position())
    camera_controller.surface_picker = _screen_to_world
    camera_controller.speed_multiplier = camera_speed_multiplier
    camera_controller.focus = Vector2(900, 700)
    _update_camera_transform()
    hud_controller = HudController.new()
    hud_controller.name = "HudController"
    hud_controller.configure(self)
    add_child(hud_controller)
    _create_ui()
    audio_controller = AudioController.new()
    audio_controller.configure(sim, local_slot)
    add_child(audio_controller)
    _create_audio()
    visual_sync = WorldVisualSync.new()
    visual_sync.name = "WorldVisualSync"
    visual_sync.configure(self)
    add_child(visual_sync)
    cursor_controller = CursorController.new()
    cursor_controller.name = "CursorController"
    cursor_controller.configure(self)
    add_child(cursor_controller)
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
    if camera_controller != null:
        camera_controller.surface_picker = Callable()
        camera_controller.viewport_size_provider = Callable()
        camera_controller.mouse_position_provider = Callable()
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# Build the HUD in code so the exported scene stays lightweight.
func _create_ui_legacy() -> void:
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

func _create_ui() -> void:
    if hud_controller != null:
        hud_controller.build()
    else:
        _create_ui_legacy()


func _create_audio() -> void:
    if audio_controller == null:
        return
    audio_controller.initialize()
    audio_player = audio_controller.audio_player
    audio_playback = audio_controller.audio_playback

func _play_tone(frequency: float, duration: float, volume: float = 0.16, slide: float = 0.0) -> void:
    if audio_controller != null:
        audio_controller.play_tone(frequency, duration, volume, slide)

func _play_attack_sound() -> void:
    if audio_controller != null:
        audio_controller.play_attack_sound()

func _play_hit_sound() -> void:
    if audio_controller != null:
        audio_controller.play_hit_sound()

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
    _sync_map_world()
    _clear_selection()
    build_mode = ""
    clicks.clear()
    camera_zoom_level = 2.0
    camera_controller.focus = Vector2(900, 700) if local_slot != 2 else Vector2(3900, 2500)
    if sim.is_test_map():
        camera_controller.focus = sim.terrain.definition.camera_focus
        camera_zoom_level = sim.terrain.definition.camera_zoom
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

func _apply_snapshot_checked(state: Dictionary, context: String) -> bool:
    if state.get("map_id", "") == "desert_sample":
        _disconnect.call_deferred()
        active = false
        connected = false
        _notify("样板区不支持联机。")
        return false
    if sim.apply_snapshot(state):
        return true
    var detail: String = sim.last_snapshot_error
    _disconnect.call_deferred()
    active = false
    connected = false
    _notify("Invalid %s snapshot%s" % [context, ": " + detail if not detail.is_empty() else ""])
    return false

func play_solo() -> void:
    _disconnect()
    if not sim.reset(true, selected_map_id):
        _notify(sim.last_snapshot_error)
        return
    active      = true
    local_slot  = 1
    accumulator = 0.0
    if session != null:
        session.reset_clock()
    _reset_view()
    Input.mouse_mode = Input.MOUSE_MODE_CONFINED
    if sim.is_test_map():
        _notify("样板测试场：全图可见，无敌人和胜负。右键指挥单位上下坡；可测试建造与采矿。")
    else:
        _notify("Select the harvester, then right-click yellow ore. Build a barracks to train soldiers.")

func create_host() -> void:
    if MapCatalog.definition(selected_map_id).get("test_only", false):
        _notify("样板区仅供单机测试，请选择正式地图创建联机。")
        return
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
    if session != null:
        session.reset_clock()
    if not sim.reset(false, selected_map_id):
        _disconnect()
        active = false
        _notify(sim.last_snapshot_error)
        return
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
    if network_session != null:
        network_session.peer_joined(id)

func _connected_to_server() -> void:
    if network_session != null:
        network_session.connected_to_server()

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
    if not _apply_snapshot_checked(state, "accepted"):
        return
    sim.rebuild_navigation()
    _reset_view()
    _notify("Red army assigned." if slot == 2 else "Spectator mode: no orders allowed.")

@rpc("authority", "reliable")

func _rejected(reason: String) -> void:
    _disconnect.call_deferred()
    active = false
    _notify(reason)

func _peer_left(id: int) -> void:
    if network_session != null:
        network_session.peer_left(id)

func _connection_failed() -> void:
    if network_session != null:
        network_session.connection_failed()

func _server_left() -> void:
    if network_session != null:
        network_session.server_left()

@rpc("authority", "call_remote", "reliable", 1)

func _world(state: Dictionary) -> void:
    if state.get("version") != Simulation.VERSION or state.get("match") != sim.match_id:
        return
    if typeof(state.get("frame")) != TYPE_INT:
        _apply_snapshot_checked(state, "world")
        return
    if int(state.frame) < sim.frame:
        return
    var previous_positions: Dictionary = {}
    for id: int in sim.units:
        previous_positions[id] = sim.units[id].pos
    var previous_frame: int = sim.frame
    if not _apply_snapshot_checked(state, "world"):
        return
    _update_render_velocities(previous_positions, previous_frame, int(state.frame))
    _audio_for_effects()

@rpc("authority", "reliable")

func _final_state(state: Dictionary) -> void:
    if state.get("match") == sim.match_id:
        _apply_snapshot_checked(state, "final")

@rpc("authority", "reliable")

func _new_match(state: Dictionary) -> void:
    if not _apply_snapshot_checked(state, "new match"):
        return
    sim.rebuild_navigation()
    _reset_view()

# Submit a player order through the command boundary.
func issue(order: Dictionary) -> void:
    if command_bus != null:
        command_bus.submit(order)
    else:
        _execute_order(order)

# Execute a validated order locally or send it to the authoritative host.
func _execute_order(order: Dictionary) -> void:
    if network_session != null:
        network_session.submit_order(order)
        return
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
    sim.reset(not connected, sim.map_id)
    _reset_view()
    if is_host:
        if network_session != null:
            network_session.broadcast_new_match(sim.snapshot())
        else:
            _new_match.rpc(sim.snapshot())
    _notify("New match.")

func return_to_title() -> void:
    _disconnect()
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    active = false
    local_slot = 1
    sim.reset(false, selected_map_id)
    _sync_map_world()
    _clear_selection()
    build_mode   = ""
    menu_visible = true
    menu.visible = true
    _notify("Match closed.")

# Main loop: advance host simulation, refresh HUD, and redraw the battlefield.
func _process(delta: float) -> void:
    _sync_map_world()
    if map_selector != null:
        map_selector.disabled = active or connected
    for click: Dictionary in clicks:
        click.life -= delta
    clicks        = clicks.filter(func(c: Dictionary) -> bool: return c.life > 0)
    feedback_time = maxf(0.0, feedback_time - delta)
    speech_time   = maxf(0.0, speech_time - delta)
    if speech_time <= 0.0:
        speech_unit = -1
    if session != null:
        session.advance(delta, active, is_host, connected)
        accumulator = session.accumulator
    if active and connected and not is_host:
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
    _sync_visuals(delta)

    if cursor_controller != null:
        cursor_controller.update_cursor()


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

# Compatibility wrappers delegate input handling to InputController.
func _unhandled_input(event: InputEvent) -> void:
    if input_controller != null:
        input_controller._unhandled_input(event)

func _input(event: InputEvent) -> void:
    if input_controller != null:
        input_controller._input(event)

func _finish_drag_select(pos: Vector2) -> void:
    if input_controller != null:
        input_controller._finish_drag_select(pos)

func _left_click(pos: Vector2) -> void:
    if input_controller != null:
        input_controller._left_click(pos)

func _select_same_type_buildings_on_screen(kind: String) -> void:
    if input_controller != null:
        input_controller._select_same_type_buildings_on_screen(kind)

func _select_same_type_on_screen(kind: String) -> void:
    if input_controller != null:
        input_controller._select_same_type_on_screen(kind)

func _attack_click(pos: Vector2) -> void:
    if input_controller != null:
        input_controller._attack_click(pos)

func _select_rect(rect: Rect2) -> void:
    if input_controller != null:
        input_controller._select_rect(rect)

func _control_group_key(group: int, ctrl: bool, shift: bool) -> void:
    if input_controller != null:
        input_controller._control_group_key(group, ctrl, shift)

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
        var active_id := active_building_id()
        if sim.buildings.has(active_id) and Simulation.BarracksFlight.state(sim.buildings[active_id]) != "grounded":
            issue({"action": "barracks_move", "building": active_id, "pos": pos})
            return
        var rally_targets: Array[int] = selected_buildings.duplicate()
        if rally_targets.is_empty() and selected_building >= 0:
            rally_targets.append(selected_building)
        if not rally_targets.is_empty():
            for id: int in rally_targets:
                issue({"action": "set_rally", "building": id, "pos": pos})
            _notify("Rally points set.")
            _show_order_feedback({"action": "rally"}, pos)
        return
    var air_target := airborne_building_at(_world_to_screen(pos))
    if air_target >= 0 and sim.buildings[air_target].owner != local_slot:
        _notify("Selected weapons cannot attack airborne targets.")
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
    _show_order_feedback(order, pos)


func _show_order_feedback(order: Dictionary, pos: Vector2) -> void:
    # An intent marker, not authoritative acceptance or a reachability guarantee.
    if not active or menu_visible or local_slot == 0 or sim.winner != 0:
        return
    if not pos.is_finite() or not Rect2(Vector2.ZERO, Simulation.WORLD).has_point(pos):
        return
    var action := str(order.get("action", ""))
    if action not in ["move", "attack_move", "attack", "gather", "rally"]:
        return
    var compatible := false
    if action == "rally":
        compatible = cursor_controller.has_buildings()
    else:
        var required := "soldier" if action == "attack" else ("harvester" if action == "gather" else "")
        for id: int in order.get("units", []):
            if sim.units.has(id):
                var unit: Dictionary = sim.units[id]
                if unit.owner == local_slot and unit.hp > 0 and (required.is_empty() or unit.type == required):
                    compatible = true
                    break
    if not compatible:
        return
    var duration := 0.70 if action in ["move", "attack_move", "attack"] else 0.55
    next_click_id += 1
    clicks.append({"id": next_click_id, "pos": pos, "life": duration, "duration": duration, "action": action})
    while clicks.size() > 16:
        clicks.pop_front()

func active_building_id() -> int:
    if not selected_buildings.is_empty():
        return selected_buildings[building_tab_index % selected_buildings.size()]
    return selected_building


func _takeoff_barracks() -> void:
    if active and not menu_visible and selected_units.is_empty():
        issue({"action": "barracks_takeoff", "building": active_building_id()})


func _begin_deploy() -> void:
    var id := active_building_id()
    if not active or menu_visible or local_slot == 0 or not selected_units.is_empty() or not sim.buildings.has(id):
        return
    var building: Dictionary = sim.buildings[id]
    if building.owner != local_slot or building.type != "barracks" or Simulation.BarracksFlight.state(building) != "airborne":
        _notify("Select an airborne friendly barracks.")
        return
    deploy_building = id
    build_mode = ""
    pending_command = ""
    attack_mode = false
    selection_dragging = false
    _notify("Deploy: all 12 cells must be green. Left-click confirms; RMB / Esc cancels.")


func _deploy_click(pos: Vector2) -> void:
    var site := sim.deployment_site(local_slot, deploy_building, pos)
    if not site.error.is_empty():
        _notify(site.error)
        return
    issue({"action": "barracks_deploy", "building": deploy_building, "pos": site.pos})
    deploy_building = -1


func building_screen_position(id: int) -> Vector2:
    var b: Dictionary = sim.buildings[id]
    var height: float = b.get("flight", {}).get("height", sim.terrain.height_at(b.pos))
    return camera.unproject_position(Vector3(b.pos.x, height + (40.0 if b.has("flight") else 0.0), b.pos.y))


func airborne_building_at(screen: Vector2, friendly_only: bool = false) -> int:
    if visual_sync == null:
        return -1
    var closest := -1
    var depth := INF
    var origin := camera.project_ray_origin(screen)
    var end := origin + camera.project_ray_normal(screen) * 10000.0
    for id: int in sim.buildings:
        var b: Dictionary = sim.buildings[id]
        if not Simulation.BarracksFlight.is_airborne(b) or (friendly_only and b.owner != local_slot):
            continue
        if not visual_sync.building_visuals.has(id):
            continue
        var visual: Node3D = visual_sync.building_visuals[id].visual
        if not visual.visible:
            continue
        var local_origin: Vector3 = visual.to_local(origin)
        var local_end: Vector3 = visual.to_local(end)
        var box := AABB(Vector3(-64, 0, -48), Vector3(128, 104, 96))
        var hit: Variant = box.intersects_segment(local_origin, local_end)
        if hit is Vector3:
            var distance: float = local_origin.distance_to(hit)
            if distance < depth:
                depth = distance
                closest = id
    return closest


func _begin_build(kind: String) -> void:
    if not active or local_slot == 0 or sim.winner != 0:
        return
    build_mode = kind
    deploy_building = -1
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
        var building: Dictionary = sim.buildings[active_building_id()]
        if building.type == "barracks" and index in [0, 2, 3]:
            if index == 0:
                _stop()
            elif index == 2:
                _takeoff_barracks()
            else:
                _begin_deploy()
            return
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
    if not selected_units.is_empty():
        _respond(selected_units[0], "Moving out!" if pending_command == "move" else "Mining operation!")
    _show_order_feedback(order, pos)
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
        if b.is_empty() or int(b.remaining) > 0 or Simulation.BarracksFlight.state(b) != "grounded":
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
    if selected_units.is_empty() and sim.buildings.has(active_building_id()) and sim.buildings[active_building_id()].type == "barracks":
        issue({"action": "barracks_stop", "building": active_building_id()})
        return
    issue({"action": "stop", "units": selected_units.duplicate()})
    if not selected_units.is_empty():
        _respond(selected_units[0], "Standing by.")

func _audio_for_effects() -> void:
    if audio_controller != null:
        audio_controller.set_local_slot(local_slot)
        audio_controller.consume_effects()

func _on_session_tick(previous_winner: int, _current_winner: int) -> void:
    _audio_for_effects()
    if is_host and previous_winner == 0 and sim.winner > 0:
        if network_session != null:
            network_session.broadcast_final_state(sim.snapshot())
        else:
            _final_state.rpc(sim.snapshot())
    if is_host and not slots.is_empty():
        if network_session != null:
            network_session.broadcast_world(sim.snapshot())
        else:
            _world.rpc(sim.snapshot())

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
    if hud_controller != null:
        hud_controller.refresh()
        return
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

# World presentation is owned by WorldVisualSync. These properties and methods
# preserve the existing test/debug surface while the runtime is split incrementally.
var unit_visuals: Dictionary:
    get:
        return visual_sync.unit_visuals if visual_sync != null else {}

var building_visuals: Dictionary:
    get:
        return visual_sync.building_visuals if visual_sync != null else {}

var ore_visuals: Dictionary:
    get:
        return visual_sync.ore_visuals if visual_sync != null else {}

var rock_visuals:
    get:
        return visual_sync.rock_visuals if visual_sync != null else []

var effect_visuals: Dictionary:
    get:
        return visual_sync.effect_visuals if visual_sync != null else {}

var marker_visuals: Dictionary:
    get:
        return visual_sync.marker_visuals if visual_sync != null else {}

var selection_rect_overlay: Panel:
    get:
        return visual_sync.selection_rect_overlay if visual_sync != null else null

var build_preview_visual: MeshInstance3D:
    get:
        return visual_sync.build_preview_visual if visual_sync != null else null

var build_preview_model:
    get:
        return visual_sync.build_preview_model if visual_sync != null else null

var health_grid_overlay:
    get:
        return visual_sync.health_grid_overlay if visual_sync != null else null

func _sync_visuals(delta: float = 0.0) -> void:
    if visual_sync != null:
        visual_sync.sync(delta)

func _sync_rocks() -> void:
    if visual_sync != null:
        visual_sync._sync_rocks()

func _sync_ores() -> void:
    if visual_sync != null:
        visual_sync._sync_ores()

func _sync_buildings() -> void:
    if visual_sync != null:
        visual_sync._sync_buildings()

func _sync_units() -> void:
    if visual_sync != null:
        visual_sync._sync_units()

func _sync_effects() -> void:
    if visual_sync != null:
        visual_sync._sync_effects()

func _sync_markers() -> void:
    if visual_sync != null:
        visual_sync._sync_markers()

func _sync_selection_rect() -> void:
    if visual_sync != null:
        visual_sync._sync_selection_rect()

func _sync_build_preview() -> void:
    if visual_sync != null:
        visual_sync._sync_build_preview()

func _sync_fog() -> void:
    if visual_sync != null:
        visual_sync._sync_fog()
# Rebuild only at map/match boundaries; snapshots never recreate static terrain.
func _sync_map_world() -> void:
    if rendered_map_id != sim.map_id:
        _create_terrain()
    if rendered_match_id != sim.match_id:
        rendered_match_id = sim.match_id
        render_velocities.clear()
        if visual_sync != null:
            visual_sync.reset_world()
    fog_plane.visible = sim.map_id == "prototype"
    if terrain_view != null:
        terrain_view.set_reveal_all(local_slot == 0 or sim.is_test_map())
    var environment_node := get_node_or_null("BattlefieldEnvironment") as WorldEnvironment
    if environment_node != null:
        var desert := sim.map_id in ["desert_quarry", "desert_sample"]
        environment_node.environment.ambient_light_energy = 0.45 if desert else 0.72
        var sunlight := get_node_or_null("BattlefieldSun") as DirectionalLight3D
        if sunlight != null:
            sunlight.light_energy = 0.85 if desert else 1.12
            sunlight.light_color = Color("#fff5e8") if desert else Color("#fff1d6")
        environment_node.environment.ambient_light_color = Color("#c3b7a5") if desert else Color("#9fb6a6")
        environment_node.environment.background_color = Color("#493c2c") if desert else Color("#203028")
    if map_selector != null:
        map_selector.select(MapCatalog.IDS.find(sim.map_id) if active else MapCatalog.IDS.find(selected_map_id))

func _map_selected(index: int) -> void:
    if active or connected:
        return
    selected_map_id = MapCatalog.IDS[index]
    _update_map_description()

func _update_map_description() -> void:
    if map_description == null:
        return
    var data := MapCatalog.definition(selected_map_id)
    var sample: bool = data.get("test_only", false)
    map_description.text = data.description + ("\n临时选项 · 可自由移动、采矿和建造" if sample else "\n联机加入时使用主机地图")
    if sample_host_button != null:
        sample_host_button.disabled = sample
        sample_host_button.tooltip_text = "样板区仅供单机测试" if sample else ""
    if solo_button != null:
        solo_button.text = "进入样板测试场" if sample else "New solo match (vs AI)"
    var preview_path := "res://assets/concept_art/desert-quarry-overview.png" if selected_map_id == "desert_quarry" else "res://build/verification/gameplay.png"
    preview_path = data.get("preview", preview_path)
    if ResourceLoader.exists(preview_path):
        map_preview.texture = load(preview_path)
    else:
        map_preview.texture = null
