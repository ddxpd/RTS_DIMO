class_name AudioController
extends Node
## Client-side sound only; observes existing snapshots without changing simulation.

const Simulation = preload("res://scripts/simulation.gd")
const SOUND_FILES := {
    "click": "01_ui_click.wav", "select": "02_unit_select.wav",
    "shot": "03_machine_gun_burst.wav", "hit": "04_metal_impact.wav",
    "mining": "05_mining_loop.wav", "hover": "06_hover_engine_loop.wav",
    "deploy": "07_barracks_deploy.wav", "complete": "08_production_complete.wav",
}
const BUS := "GameSFX"
const MAX_WORLD := 12
const MAX_LOOPS := 4
const HEARING_RANGE := 1100.0

var simulation
var host: Node
var local_slot := 1
var streams: Dictionary = {}
var world_players: Array[AudioStreamPlayer3D] = []
var ui_players: Array[AudioStreamPlayer] = []
var loops: Dictionary = {}
var played_counts: Dictionary = {}
var seen_effects: Dictionary = {}
var known_units: Dictionary = {}
var building_states: Dictionary = {}
var observed_match := -1
var observed_frame := -1
var primed := false
var selection_key: Array = []
var ui_last_ms: Dictionary = {}
var loop_elapsed := 0.0
var enabled := false
var voice_generation := 0


func configure(value, slot: int) -> void:
    simulation = value
    local_slot = slot


func _exit_tree() -> void:
    voice_generation += 1
    for player in world_players:
        player.stop()
        player.stream = null
    for player in ui_players:
        player.stop()
        player.stream = null
    for player: AudioStreamPlayer3D in loops.values():
        player.stop()
        player.stream = null
    streams.clear()
    host = null
    simulation = null


func initialize(game: Node = null) -> void:
    if not streams.is_empty():
        return
    host = game
    if AudioServer.get_bus_index(BUS) < 0:
        AudioServer.add_bus()
        var index := AudioServer.bus_count - 1
        AudioServer.set_bus_name(index, BUS)
        AudioServer.set_bus_volume_db(index, -3.0)
        AudioServer.add_bus_effect(index, AudioEffectLimiter.new())
    for key: String in SOUND_FILES:
        var stream := load("res://assets/audio/sfx/" + SOUND_FILES[key]) as AudioStreamWAV
        assert(stream != null, "Missing sound: " + key)
        if key in ["mining", "hover"]:
            stream = stream.duplicate() as AudioStreamWAV
            stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
            stream.loop_begin = 0
            stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
        streams[key] = stream
    for i in range(MAX_WORLD):
        world_players.append(_new_world_player())
    for i in range(4):
        var player := AudioStreamPlayer.new()
        player.bus = BUS
        player.volume_db = -5.0
        add_child(player)
        ui_players.append(player)
    if host != null:
        _bind_buttons(host)
    reset_state()


func _new_world_player() -> AudioStreamPlayer3D:
    var player := AudioStreamPlayer3D.new()
    player.bus = BUS
    player.unit_size = 400.0
    player.max_distance = 2200.0
    player.volume_db = -10.0
    add_child(player)
    return player


func _bind_buttons(node: Node) -> void:
    if node is BaseButton:
        node.pressed.connect(_button_sound.bind(node))
    for child in node.get_children():
        _bind_buttons(child)


func _button_sound(button: BaseButton) -> void:
    if "action_id" in button and button.action_id == "move":
        return
    if host != null and button in host.group_cards and host.selected_units.is_empty():
        return
    play_ui("click")


func set_local_slot(slot: int) -> void:
    if local_slot != slot:
        local_slot = slot
        reset_state()


func reset_state() -> void:
    voice_generation += 1
    for player in world_players:
        player.stop()
        player.set_meta("pending", false)
    for player in ui_players:
        player.stop()
        player.set_meta("pending", false)
    for player: AudioStreamPlayer3D in loops.values():
        player.stop()
        player.queue_free()
    loops.clear()
    seen_effects.clear()
    known_units.clear()
    building_states.clear()
    ui_last_ms.clear()
    selection_key.clear()
    observed_match = -1
    observed_frame = -1
    primed = false
    loop_elapsed = 0.0


func _queue_voice(player: Node) -> void:
    # Coalesce frame-local play/reset operations before the audio thread sees
    # them. Stale queued voices must not restart after a match reset or deletion.
    player.set_meta("pending", true)
    _start_voice.call_deferred(player.get_instance_id(), voice_generation)


func _start_voice(instance_id: int, generation: int) -> void:
    var player := instance_from_id(instance_id)
    if generation != voice_generation or not is_instance_valid(player) or player.is_queued_for_deletion():
        return
    player.set_meta("pending", false)
    player.play()


func _busy(player: Node) -> bool:
    return player.playing or bool(player.get_meta("pending", false))


func play_ui(kind: String = "click") -> void:
    if not streams.has(kind):
        return
    var now := Time.get_ticks_msec()
    if now - int(ui_last_ms.get(kind, -1000)) < 90:
        return
    for player in ui_players:
        if not _busy(player):
            player.stream = streams[kind]
            _queue_voice(player)
            ui_last_ms[kind] = now
            played_counts[kind] = int(played_counts.get(kind, 0)) + 1
            return


func _focus() -> Vector2:
    return host.camera_controller.focus if host != null else Vector2.ZERO


func _audible(pos: Vector2) -> bool:
    return simulation.can_see(local_slot, pos) and _focus().distance_to(pos) < HEARING_RANGE


func _world_position(pos: Vector2) -> Vector3:
    return Vector3(pos.x, simulation.terrain.height_at(pos) + 25.0, pos.y)


func play_world(kind: String, pos: Vector2) -> void:
    if not enabled or not _audible(pos):
        return
    var count := 0
    for player in world_players:
        if _busy(player) and player.get_meta("kind", "") == kind:
            count += 1
    if count >= 4:
        return
    for player in world_players:
        if not _busy(player):
            player.stream = streams[kind]
            player.set_meta("kind", kind)
            player.set_meta("position", pos)
            player.position = _world_position(pos)
            _queue_voice(player)
            played_counts[kind] = int(played_counts.get(kind, 0)) + 1
            return


func consume_effects() -> void:
    if simulation == null or not enabled:
        return
    if observed_match != simulation.match_id or simulation.frame < observed_frame:
        reset_state()
        observed_match = simulation.match_id
    observed_frame = simulation.frame
    # Life changes between snapshots. Stable fields plus an occurrence ordinal
    # retain simultaneous identical shots and suppress replayed snapshots.
    var current: Dictionary = {}
    var occurrences: Dictionary = {}
    for effect: Dictionary in simulation.effects:
        var key := str([effect.frame, effect.kind, effect.owner, effect.from, effect.to, effect.get("impact", {})])
        var ordinal := int(occurrences.get(key, 0))
        occurrences[key] = ordinal + 1
        key += ":" + str(ordinal)
        current[key] = true
        if seen_effects.has(key):
            continue
        if effect.kind == "shot":
            play_world("shot", effect.from)
            play_world("hit", effect.to)
    seen_effects = current
    var next_units: Dictionary = {}
    for id: int in simulation.units:
        var unit: Dictionary = simulation.units[id]
        next_units[id] = true
        if primed and not known_units.has(id) and unit.owner == local_slot and unit.hp > 0:
            play_ui("complete")
    known_units = next_units
    var next_buildings: Dictionary = {}
    for id: int in simulation.buildings:
        var building: Dictionary = simulation.buildings[id]
        var state := Simulation.BarracksFlight.state(building)
        next_buildings[id] = state
        if primed and building_states.has(id) and state == "landing" and building_states[id] != "landing":
            play_world("deploy", building.pos)
    building_states = next_buildings
    primed = true


func update_loops() -> void:
    var candidates: Array[Dictionary] = []
    for id: int in simulation.units:
        var unit: Dictionary = simulation.units[id]
        if unit.type != "harvester" or unit.hp <= 0 or not _audible(unit.pos):
            continue
        candidates.append({"key": "hover_u%d" % id, "kind": "hover", "pos": unit.pos})
        var ore: Dictionary = simulation.ores.get(int(unit.get("ore", -1)), {})
        if unit.order == "gather" and unit.get("mining", {}).get("phase", "") == "work" and not unit.has("dock") and not Simulation.DepotDocking.returning(simulation, unit) and not ore.is_empty() and ore.amount > 0:
            var reach: float = Simulation.UNIT_TYPES.harvester.radius + 26.0
            if (unit.pos as Vector2).distance_to(ore.pos) <= reach:
                candidates.append({"key": "mining_u%d" % id, "kind": "mining", "pos": unit.pos})
    for id: int in simulation.buildings:
        var building: Dictionary = simulation.buildings[id]
        if building.type == "barracks" and building.hp > 0 and Simulation.BarracksFlight.state(building) != "grounded" and _audible(building.pos):
            candidates.append({"key": "hover_b%d" % id, "kind": "hover", "pos": building.pos})
    var focus := _focus()
    candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return (a.pos as Vector2).distance_squared_to(focus) < (b.pos as Vector2).distance_squared_to(focus))
    var wanted: Dictionary = {}
    for candidate in candidates.slice(0, MAX_LOOPS):
        wanted[candidate.key] = candidate
    for key: String in loops.keys():
        if not wanted.has(key):
            loops[key].stop()
            loops[key].queue_free()
            loops.erase(key)
    for key: String in wanted:
        var candidate: Dictionary = wanted[key]
        if not loops.has(key):
            var player := _new_world_player()
            player.volume_db = -19.0
            player.stream = streams[candidate.kind]
            loops[key] = player
            player.position = _world_position(candidate.pos)
            _queue_voice(player)
            played_counts[candidate.kind] = int(played_counts.get(candidate.kind, 0)) + 1
        loops[key].position = _world_position(candidate.pos)


func _process(delta: float) -> void:
    if host == null:
        return
    set_local_slot(host.local_slot)
    var should_enable: bool = host.active and simulation.winner == 0
    if should_enable != enabled:
        reset_state()
        enabled = should_enable
    if not enabled:
        return
    if simulation.frame != observed_frame or simulation.match_id != observed_match:
        consume_effects()
    var selected: Array = [host.selected_units.duplicate(), host.selected_buildings.duplicate(), host.selected_building]
    if selected != selection_key:
        selection_key = selected
        if not host.selected_units.is_empty():
            play_ui("select")
    loop_elapsed += delta
    if loop_elapsed >= 0.1:
        loop_elapsed = 0.0
        update_loops()
        for player in world_players:
            if player.playing and not _audible(player.get_meta("position", Vector2.ZERO)):
                player.stop()
