extends Node2D
const Simulation = preload("res://scripts/simulation.gd")
const Art = preload("res://scripts/pixel_art.gd")
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
var selected_units: Array[int] = []
var selected_building := -1
var selection_dragging := false
var selection_start := Vector2.ZERO
var selection_current := Vector2.ZERO
var middle_dragging := false
var build_mode := ""
var menu_visible := true
var camera: Camera2D
var tiles: TileMapLayer
var hud: CanvasLayer
var top_label: Label
var resource_label: Label
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

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sim.reset(false)
	sprites = {1: Art.sprites(Color("#5fa5e0")), 2: Art.sprites(Color("#d66551"))}
	tiles = TileMapLayer.new()
	tiles.tile_set = Art.terrain()
	tiles.scale = Vector2(2, 2)
	tiles.z_index = -10
	add_child(tiles)
	for x in range(50):
		for y in range(30):
			tiles.set_cell(Vector2i(x, y), 0, Vector2i((x * 7 + y * 11) % 3, 0))
	camera = Camera2D.new()
	add_child(camera)
	camera.position = Vector2(500, 350)
	camera.zoom = Vector2.ONE
	_create_ui()
	_create_audio()
	multiplayer.peer_connected.connect(_peer_joined)
	multiplayer.peer_disconnected.connect(_peer_left)
	multiplayer.connected_to_server.connect(_connected_to_server)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_left)
	_refresh_ui()

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
	resource_label=Label.new()
	resource_label.text="MINERALS"
	resource_label.position=Vector2(440,12)
	root.add_child(resource_label)
	info_panel = PanelContainer.new()
	info_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	info_panel.offset_left = -260
	info_panel.offset_top = 52
	root.add_child(info_panel)
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
	_button(column, "Train Soldier     $100", _produce.bind("soldier"))
	_button(column, "Build Harvester  $200", _produce.bind("harvester"))
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
	bottom.offset_top = -132
	bottom.offset_right = -260
	root.add_child(bottom)
	message_label = Label.new()
	message_label.add_theme_font_size_override("font_size", 13)
	bottom.add_child(message_label)
	result_label = Label.new()
	result_label.position = Vector2(100, 80)
	result_label.add_theme_font_size_override("font_size", 30)
	result_label.add_theme_color_override("font_color", Color("#ffe292"))
	result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(result_label)
	menu = PanelContainer.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu.offset_left = -235
	menu.offset_right = 235
	menu.offset_top = -255
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
	_button(menu_buttons, "Quit", get_tree().quit)

func _create_audio() -> void:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 44100
	stream.buffer_length = 1.0
	audio_player = AudioStreamPlayer.new()
	audio_player.stream = stream
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
	selection_dragging = false

func _reset_view() -> void:
	_clear_selection()
	build_mode = ""
	clicks.clear()
	camera.zoom = Vector2.ONE
	camera.position = Vector2(500, 350) if local_slot != 2 else Vector2(1250, 650)
	menu_visible = false
	menu.visible = false

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
	active = true
	local_slot = 1
	accumulator = 0.0
	_reset_view()
	_notify("Select the harvester, then right-click yellow ore. Build a barracks to train soldiers.")

func create_host() -> void:
	_disconnect()
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_CLIENTS)
	if error != OK:
		_notify("Host failed: " + error_string(error))
		return
	multiplayer.multiplayer_peer = peer
	is_host = true
	connected = true
	active = true
	local_slot = 1
	sim.reset(false)
	_reset_view()
	_notify("LAN host ready on UDP 24560. Waiting for the red player.")

func join_host() -> void:
	_disconnect()
	active = false
	local_slot = 0
	peer = ENetMultiplayerPeer.new()
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
	connected = true
	active = true
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
	active = false
	menu_visible = true
	menu.visible = true
	_notify("Connection failed. Check host address and UDP 24560.")

func _server_left() -> void:
	_disconnect()
	active = false
	menu_visible = true
	menu.visible = true
	_clear_selection()
	_notify("Host disconnected. Match stopped; return to title or start a new match.")

@rpc("authority", "call_remote", "reliable", 1)
func _world(state: Dictionary) -> void:
	if state.get("version") == Simulation.VERSION and state.get("match") == sim.match_id and int(state.frame) >= sim.frame:
		sim.apply_snapshot(state)
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
	active = false
	local_slot = 1
	sim.reset(false)
	_clear_selection()
	build_mode = ""
	menu_visible = true
	menu.visible = true
	_notify("Match closed.")

func _process(delta: float) -> void:
	for click: Dictionary in clicks:
		click.life -= delta
	clicks = clicks.filter(func(c: Dictionary) -> bool: return c.life > 0)
	feedback_time = maxf(0.0, feedback_time - delta)
	speech_time = maxf(0.0, speech_time - delta)
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
			if is_host and sim.frame % 2 == 0 and not slots.is_empty():
				_world.rpc(sim.snapshot())
	if is_host:
		for id: int in handshakes.keys():
			if Time.get_ticks_msec() - int(handshakes[id]) > 5000:
				peer.disconnect_peer(id)
				handshakes.erase(id)
	if active and not menu_visible:
		var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		camera.position += direction * delta * 500 / camera.zoom.x
	_limit_camera()
	_clean_selection()
	_refresh_ui()
	queue_redraw()

func _clean_selection() -> void:
	var valid: Array[int] = []
	for id: int in selected_units:
		if sim.units.has(id) and sim.units[id].owner == local_slot:
			valid.append(id)
	selected_units = valid
	if not sim.buildings.has(selected_building) or sim.buildings[selected_building].owner != local_slot:
		selected_building = -1

func _limit_camera() -> void:
	var half := get_viewport_rect().size / (2.0 * camera.zoom.x)
	var max_center := Simulation.WORLD - half
	camera.position = camera.position.clamp(half.min(Simulation.WORLD / 2), max_center.max(Simulation.WORLD / 2))

func _screen_is_map(pos: Vector2) -> bool:
	var size := get_viewport_rect().size
	return pos.x < size.x - 260 and pos.y > 52 and pos.y < size.y - 132

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
			if not build_mode.is_empty():
				build_mode = ""
			else:
				_toggle_menu()
		elif active and not menu_visible and event.keycode == attack_keycode:
			attack_mode = not attack_mode
			_notify("Attack mode %s. Left-click a target or ground." % ("ON" if attack_mode else "OFF"))
		elif active and not menu_visible and event.keycode == KEY_B:
			_begin_build("barracks")
		elif active and not menu_visible and event.keycode == KEY_S:
			_stop()
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
					selection_start = pos
					selection_current = pos
			elif not event.pressed and selection_dragging:
				selection_dragging = false
				if (pos - selection_start).length() * camera.zoom.x < 8:
					_left_click(pos)
				else:
					_select_rect(Rect2(selection_start, pos - selection_start).abs())
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
			camera.zoom = Vector2.ONE * clampf(camera.zoom.x * factor, 0.65, 2.5)
			camera.force_update_scroll()
			camera.position += before - get_global_mouse_position()
	elif event is InputEventMouseMotion:
		if middle_dragging:
			camera.position -= event.relative / camera.zoom.x
		if selection_dragging:
			selection_current = get_global_transform_with_canvas().affine_inverse() * event.position

func _input(event: InputEvent) -> void:
	# A release over the sidebar must not leave a drag stuck on.
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			middle_dragging = false
		if event.button_index == MOUSE_BUTTON_LEFT and not _screen_is_map(event.position):
			selection_dragging = false

func _left_click(pos: Vector2) -> void:
	if attack_mode:
		_attack_click(pos)
		return
	_clear_selection()
	for id: int in sim.units:
		var u: Dictionary = sim.units[id]
		if u.owner == local_slot and (u.pos as Vector2).distance_to(pos) <= 20:
			selected_units.append(id)
			return
	for id: int in sim.buildings:
		if sim.buildings[id].owner == local_slot and sim.footprint(sim.buildings[id]).has_point(pos):
			selected_building = id
			return

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

func _right_click(pos: Vector2) -> void:
	if selected_units.is_empty() or not Rect2(Vector2.ZERO, Simulation.WORLD).has_point(pos):
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
	selection_dragging = false
	_notify("Left-click a green site to build; right-click cancels.")
	_play_tone(300.0, 0.08, 0.12)

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
	issue({"action": "produce", "building": selected_building, "type": kind})
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
	menu_visible = not menu_visible
	menu.visible = menu_visible
	selection_dragging = false
	middle_dragging = false

func _close_menu() -> void:
	if active:
		menu_visible = false
		menu.visible = false

func _notify(message: String) -> void:
	feedback = message
	feedback_time = 8.0

func _refresh_ui() -> void:
	var role := "BLUE" if local_slot == 1 else ("RED" if local_slot == 2 else "SPECTATOR")
	top_label.text = "IRON FRONT   /   %s     CREDITS: %d     %02d:%02d" % [role, int(sim.money.get(local_slot, 0)), sim.frame / 1200, (sim.frame / 20) % 60]
	resource_label.text = "MINERALS  %d" % int(sim.money.get(local_slot, 0))
	resume_button.disabled = not active
	message_label.text = feedback if feedback_time > 0 else "Left: select    Right: order    A: attack mode    B: barracks    S: stop    Esc: menu"
	result_label.text = ""
	if sim.winner > 0:
		result_label.text = "DRAW" if sim.winner == 3 else ("VICTORY" if sim.winner == local_slot else "DEFEAT")
		result_label.text += "  鈥? Esc to restart / return"
	if sim.buildings.has(selected_building):
		var b: Dictionary = sim.buildings[selected_building]
		info_label.text = "%s\nHP %d / %d\n%s" % [str(b.type).to_upper(), b.hp, Simulation.BUILD_TYPES[b.type].hp, "Construction: %.1fs" % (float(b.remaining) / 20) if b.remaining > 0 else "Ready"]
		queue_label.text = "PRODUCTION (%d / 5)\n" % b.queue.size()
		for job: Dictionary in b.queue:
			queue_label.text += "%s  %.1fs\n" % [job.type, float(job.remaining) / 20]
		if not b.queue.is_empty() and int(b.queue[0].remaining) == 0:
			queue_label.text += "Exit blocked 鈥?clear nearby units"
	elif not selected_units.is_empty():
		info_label.text = "%d UNIT(S) SELECTED\n" % selected_units.size()
		var u: Dictionary = sim.units[selected_units[0]]
		info_label.text += "%s / HP %d\nOrder: %s" % [u.type, u.hp, u.order]
		if u.type == "harvester":
			info_label.text += " / Cargo %d / 60" % u.cargo
		queue_label.text = "Select a base for harvesters.\nSelect a barracks for soldiers."
	else:
		info_label.text = "No selection\nSelect units or a building.\nHarvesters return ore to a base."
		queue_label.text = "Buildings cost credits.\nPlace near your existing base."

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
		for y in range(30):
			for x in range(50):
				var index := y * 50 + x
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




