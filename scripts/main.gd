extends Node3D
const Simulation = preload("res://scripts/simulation.gd")
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
var front_end: Node
var external_transport: Node
var startup_config: Dictionary = {}
var initialization_error := ""
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
var connection_port := PORT
var bind_ip := "*"
var slots: Dictionary = {}
var handshakes: Dictionary = {}
var rates: Dictionary = {}
var accumulator := 0.0
var render_velocities: Dictionary = {}
var selected_units: Array[int] = []
var selected_ore := -1
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
var speech_unit := -1
var speech_text := ""
var speech_time := 0.0
var attack_mode := false
var key_bindings := preload("res://scripts/controllers/key_bindings.gd").new()
var settings_panel: PanelContainer
var settings_button: Button
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

var unit_visuals: Dictionary:
    get:
        return visual_sync.unit_visuals if visual_sync != null else {}

var building_visuals: Dictionary:
    get:
        return visual_sync.building_visuals if visual_sync != null else {}

var ore_visuals: Dictionary:
    get:
        return visual_sync.ore_visuals if visual_sync != null else {}


var effect_visuals: Dictionary:
    get:
        return visual_sync.effect_visuals if visual_sync != null else {}

var marker_visuals: Dictionary:
    get:
        return visual_sync.marker_visuals if visual_sync != null else {}

var selection_rect_overlay: Panel:
    get:
        return visual_sync.selection_rect_overlay if visual_sync != null else null

var build_preview_model:
    get:
        return visual_sync.build_preview_model if visual_sync != null else null

var health_grid_overlay:
    get:
        return visual_sync.health_grid_overlay if visual_sync != null else null

# Terrain and fog share the authored height surface.
func _create_terrain() -> void:
    if terrain_view != null:
        terrain_view.free()
    rendered_map_id = sim.map_id
    terrain_view = SampleView.new() if sim.terrain.sample_surface != null else TerrainView.new()
    add_child(terrain_view)
    terrain_view.build(sim.terrain, fog_texture)

# Clear battlefield lighting makes the mechanical models readable from above.
func _create_lighting() -> void:
    var sun := DirectionalLight3D.new()
    sun.name = "BattlefieldSun"
    sun.rotation_degrees = Vector3(-55, -32, 0)
    sun.light_color = Color("#fff5e8")
    sun.light_energy = 0.85
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 1600.0
    add_child(sun)

    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color("#493c2c")
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
    environment.ambient_light_color = Color("#c3b7a5")
    environment.ambient_light_energy = 0.45
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

# Pick the visible terrain surface, including slopes and recessed ground.
func _screen_to_world(screen: Vector2) -> Vector2:
    var from := camera.project_ray_origin(screen)
    var dir := camera.project_ray_normal(screen)
    var hit := sim.terrain.ray_hit(from, dir)
    return Vector2(hit.x, hit.z) if hit.is_finite() else Vector2(-1, -1)

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
    if not sim.reset(false, selected_map_id, startup_config):
        initialization_error = sim.last_snapshot_error
        set_process(false)
        return
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
    if front_end == null:
        multiplayer.peer_connected.connect(_peer_joined)
        multiplayer.peer_disconnected.connect(_peer_left)
        multiplayer.connected_to_server.connect(_connected_to_server)
        multiplayer.connection_failed.connect(_connection_failed)
        multiplayer.server_disconnected.connect(_server_left)
    _refresh_ui()
func _load_settings() -> void:
    key_bindings.load_settings()
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
func _create_ui() -> void:
    hud_controller.build()

func _create_audio() -> void:
    if audio_controller != null:
        audio_controller.initialize(self)


func _play_ui_sound(kind: String) -> void:
    if audio_controller != null:
        audio_controller.play_ui(kind)

func _respond(unit_id: int, words: String, audible: bool = true) -> void:
    if not sim.units.has(unit_id) or sim.units[unit_id].owner != local_slot:
        return
    speech_unit = unit_id
    speech_text = words
    speech_time = 1.6
    _notify("Unit %d: %s" % [unit_id, words])
    if audible:
        _play_ui_sound("select")

func _clear_selection() -> void:
    selected_ore = -1
    if pending_command == "rally":
        pending_command = ""
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
    if audio_controller != null:
        audio_controller.reset_state()
    _sync_map_world()
    _clear_selection()
    build_mode = ""
    clicks.clear()
    camera_zoom_level = 2.0
    camera_controller.focus = sim.terrain.definition.spawns[clampi(local_slot - 1, 0, sim.terrain.definition.spawns.size() - 1)]
    if sim.is_test_map():
        camera_controller.focus = sim.terrain.definition.camera_focus
        camera_zoom_level = sim.terrain.definition.camera_zoom
    _update_camera_transform()
    menu_visible    = false
    menu.visible    = false
    if settings_panel != null:
        settings_panel.hide()
        settings_panel.recording = ""

func _disconnect() -> void:
    if external_transport != null:
        return
    if network_session != null:
        network_session.disconnect_session()

func _apply_snapshot_checked(state: Dictionary, context: String) -> bool:
    if state.get("map_id", "") == "desert_sample":
        _disconnect.call_deferred()
        active = false
        connected = false
        _notify("训练场不支持联机。")
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
    cursor_controller.update_mouse_mode()
    if sim.is_test_map():
        _notify("训练场：仅初始主基地，全图可见。选中基地建造设施，再生产单位测试地形。")
    else:
        _notify("Select your base to build an ore depot and produce harvesters. Build a barracks to train mobile infantry.")

func create_host() -> void:
    if MapCatalog.definition(selected_map_id).get("test_only", false):
        _notify("训练场仅供单机练习，请选择正式地图创建联机。")
        return
    _disconnect()
    peer = ENetMultiplayerPeer.new()
    peer.set_bind_ip(bind_ip)
    var error := peer.create_server(connection_port, MAX_CLIENTS)
    if error != OK:
        _notify("Host failed: " + error_string(error))
        return
    peer.host.compress(ENetConnection.COMPRESS_FASTLZ)
    multiplayer.multiplayer_peer = peer
    cursor_controller.update_mouse_mode()
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
    var error := peer.create_client(host_ip.strip_edges(), connection_port)
    if error != OK:
        _notify("Join failed: " + error_string(error))
        return
    peer.host.compress(ENetConnection.COMPRESS_FASTLZ)
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
    network_session.receive_hello(version, multiplayer.get_remote_sender_id(), self)

@rpc("authority", "reliable")

func _accepted(version: String, slot: int, state: Dictionary) -> void:
    network_session.receive_accepted(version, slot, state)

@rpc("authority", "reliable")

func _rejected(reason: String) -> void:
    network_session.receive_rejected(reason)

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
    network_session.receive_world(state)

@rpc("authority", "reliable")

func _final_state(state: Dictionary) -> void:
    network_session.receive_final_state(state)

@rpc("authority", "reliable")

func _new_match(state: Dictionary) -> void:
    network_session.receive_new_match(state)

func issue(order: Dictionary) -> void:
    if command_bus != null:
        command_bus.submit(order)
    else:
        _execute_order(order)

# Execute a validated order locally or send it to the authoritative host.
func _execute_order(order: Dictionary) -> void:
    if external_transport != null:
        external_transport.send("order", order)
    else:
        network_session.submit_order(order)

@rpc("any_peer", "reliable")

func _order(order: Dictionary) -> void:
    network_session.receive_order(order, multiplayer.get_remote_sender_id(), self)

@rpc("authority", "reliable")

func _order_error(message: String) -> void:
    network_session.receive_order_error(message)

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
        network_session.broadcast_new_match(sim.snapshot())
    _notify("New match.")

func return_to_title() -> void:
    if front_end != null:
        front_end.return_home()
        return
    if audio_controller != null:
        audio_controller.reset_state()
        audio_controller.enabled = false
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
    if active and not menu_visible and (DisplayServer.get_name() == "headless" or get_window().has_focus()):
        var typing := get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit
        var direction := Vector2.ZERO if typing else key_bindings.camera_direction()
        camera_controller.pan(direction, delta)
        if not hud_controller.minimap_dragging() and not middle_dragging:
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
    return hud_controller.playfield_rect() if hud_controller != null else get_viewport().get_visible_rect()

func _limit_camera() -> void:
    if camera_controller != null:
        camera_controller._limit_camera()
        _update_camera_transform()

func _screen_is_map(pos: Vector2) -> bool:
    return _get_map_screen_rect().has_point(pos)

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
            issue({"action": "building_move", "building": active_id, "pos": pos})
            return
        _set_rally(pos)
        return
    var air_target := airborne_building_at(_world_to_screen(pos))
    if air_target >= 0 and not sim.allied(sim.buildings[air_target].owner, local_slot):
        _notify("Selected weapons cannot attack airborne targets.")
        return
    var order := {"action": "move", "units": selected_units.duplicate(), "pos": pos}
    for kind: String in ["unit", "building"]:
        var collection: Dictionary = sim.units if kind == "unit" else sim.buildings
        for id: int in collection:
            var target: Dictionary = collection[id]
            var hit: bool = (target.pos as Vector2).distance_to(pos) < 24 if kind == "unit" else sim.footprint(target).has_point(pos)
            if not sim.allied(target.owner, local_slot) and hit:
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
        _respond(selected_units[0], reply, order.action != "move")
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
                if unit.owner == local_slot and unit.hp > 0 and (required.is_empty() or unit.type == required or (required == "soldier" and Simulation.is_combat_unit(unit.type))):
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
        issue({"action": "building_takeoff", "building": active_building_id()})


func _begin_deploy() -> void:
    var id := active_building_id()
    if not active or menu_visible or local_slot == 0 or not selected_units.is_empty() or not sim.buildings.has(id):
        return
    var building: Dictionary = sim.buildings[id]
    if building.owner != local_slot or building.type not in Simulation.BarracksFlight.FLYING_TYPES or Simulation.BarracksFlight.state(building) != "airborne":
        _notify("Select an airborne friendly base or barracks.")
        return
    deploy_building = id
    build_mode = ""
    pending_command = ""
    attack_mode = false
    selection_dragging = false
    var cells: Vector2i = Simulation.EntityCatalog.BUILD_CELLS[building.type]
    _notify("部署：%d×%d 格必须全部可用。左键确认，右键 / Esc 取消。" % [cells.x, cells.y])


func _deploy_click(pos: Vector2) -> void:
    var site := sim.deployment_site(local_slot, deploy_building, pos)
    if not site.error.is_empty():
        _notify(site.error)
        return
    issue({"action": "building_deploy", "building": deploy_building, "pos": site.pos})
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
    _play_ui_sound("click")

# Bottom action bar: dispatch a clicked button to the matching unit or building command.
func _action_clicked(index: int) -> void:
    if index < 0 or index >= action_buttons.size() or action_buttons[index].disabled:
        return
    hud_controller.invoke(action_buttons[index].action_id)

# Queue a command that waits for the next battlefield left-click.
func _begin_pending(kind: String) -> void:
    if not active or menu_visible or local_slot == 0:
        return
    var flying_move := false
    if kind == "move" and selected_units.is_empty() and sim.buildings.has(active_building_id()):
        var building: Dictionary = sim.buildings[active_building_id()]
        flying_move = building.owner == local_slot and Simulation.BarracksFlight.state(building) == "airborne"
    if (kind == "rally" and _rally_targets().is_empty()) or (kind != "rally" and selected_units.is_empty() and not flying_move):
        return
    pending_command = kind
    attack_mode = false
    build_mode = ""
    deploy_building = -1
    if kind == "rally":
        _notify("左键设置集结点；冶炼场可指定晶矿。Esc / 右键取消。")
        return
    _notify("Left-click a destination." if kind == "move" else "Left-click an ore patch to gather.")

func _pending_click(pos: Vector2) -> void:
    if pending_command == "move" and selected_units.is_empty():
        issue({"action": "building_move", "building": active_building_id(), "pos": pos})
        pending_command = ""
        return
    if pending_command == "rally":
        _set_rally(pos)
        pending_command = ""
        return
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
        _respond(selected_units[0], "Moving out!" if pending_command == "move" else "Mining operation!", pending_command != "move")
    _show_order_feedback(order, pos)
    pending_command = ""

func _rally_targets() -> Array[int]:
    var result: Array[int] = []
    if not selected_units.is_empty():
        return result
    var candidates: Array[int] = selected_buildings.duplicate()
    if candidates.is_empty() and selected_building >= 0:
        candidates.append(selected_building)
    for id: int in candidates:
        var building: Dictionary = sim.buildings.get(id, {})
        if Simulation.RallySystem.producer(building) and building.owner == local_slot and Simulation.BarracksFlight.state(building) == "grounded":
            result.append(id)
    return result


func _set_rally(pos: Vector2, clear: bool = false) -> void:
    if not clear and (not pos.is_finite() or not Rect2(Vector2.ZERO, Simulation.WORLD).has_point(pos)):
        return
    for id: int in _rally_targets():
        var order := {"action": "set_rally", "building": id, "pos": pos, "mode": "none" if clear else "ground"}
        if not clear and sim.buildings[id].type == "refinery":
            for ore_id: int in sim.ores:
                var ore: Dictionary = sim.ores[ore_id]
                if ore.amount > 0 and sim.can_see(local_slot, ore.pos) and ore.pos.distance_to(pos) < 38:
                    order.mode = "ore"
                    order.ore = ore_id
                    break
        issue(order)


func _clear_rally() -> void:
    pending_command = ""
    _set_rally(Vector2.ZERO, true)

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
    var producer := "barracks" if Simulation.is_combat_unit(kind) else "refinery"
    for id: int in selected_buildings:
        var b: Dictionary = sim.buildings.get(id, {})
        if b.is_empty() or int(b.remaining) > 0 or Simulation.BarracksFlight.state(b) != "grounded":
            continue
        if b.type != producer or int(b.owner) != local_slot:
            continue
        if b.queue.size() < best_queue:
            best_queue = b.queue.size()
            best = id
    issue({"action": "produce", "building": best, "type": kind})
    _play_ui_sound("click")

func _cancel_job() -> void:
    var target := selected_building
    if selected_buildings.size() > 1:
        target = selected_buildings[building_tab_index % selected_buildings.size()]
    issue({"action": "cancel_production", "building": target})

func _stop() -> void:
    if selected_units.is_empty() and sim.buildings.has(active_building_id()) and sim.buildings[active_building_id()].type in Simulation.BarracksFlight.FLYING_TYPES:
        issue({"action": "building_stop", "building": active_building_id()})
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
        network_session.broadcast_final_state(sim.snapshot())
    if is_host and not slots.is_empty():
        network_session.broadcast_world(sim.snapshot())

func _toggle_menu() -> void:
    if settings_panel != null and settings_panel.visible:
        settings_panel.close()
        return
    if pending_command == "rally":
        pending_command = ""
    menu_visible       = not menu_visible
    menu.visible       = menu_visible
    selection_dragging = false
    middle_dragging    = false
    cursor_controller.update_mouse_mode()

func _close_menu() -> void:
    if settings_panel != null:
        settings_panel.hide()
        settings_panel.recording = ""
    if active:
        menu_visible = false
        menu.visible = false
        cursor_controller.update_mouse_mode()

func _notify(message: String) -> void:
    feedback = message
    feedback_time = 8.0

# Keep all HUD text and command-card state in one place.
func _refresh_ui() -> void:
    hud_controller.refresh()

func _sync_visuals(delta: float = 0.0) -> void:
    if visual_sync != null:
        visual_sync.sync(delta)

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
    if terrain_view != null:
        terrain_view.set_reveal_all(local_slot == 0 or sim.is_test_map())
    var environment_node := get_node_or_null("BattlefieldEnvironment") as WorldEnvironment
    if environment_node != null:
        environment_node.environment.ambient_light_energy = 0.45
        var sunlight := get_node_or_null("BattlefieldSun") as DirectionalLight3D
        if sunlight != null:
            sunlight.light_energy = 0.85
            sunlight.light_color = Color("#fff5e8")
        environment_node.environment.ambient_light_color = Color("#c3b7a5")
        environment_node.environment.background_color = Color("#493c2c")
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
        sample_host_button.tooltip_text = "训练场仅供单机练习" if sample else ""
    if solo_button != null:
        solo_button.text = "进入训练场" if sample else "New solo match (vs AI)"
    var preview_path := "res://assets/maps/desert_quarry_preview.png" if selected_map_id == "desert_quarry" else ""
    preview_path = data.get("preview", preview_path)
    if not preview_path.is_empty() and ResourceLoader.exists(preview_path):
        map_preview.texture = load(preview_path)
    else:
        map_preview.texture = null
