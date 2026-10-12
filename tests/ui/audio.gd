extends SceneTree

const MAIN = preload("res://scenes/main.tscn")
const Simulation = preload("res://scripts/simulation.gd")
const Controller = preload("res://scripts/audio/audio_controller.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
    run.call_deferred()


func check(value: bool, label: String) -> void:
    checks += 1
    if not value:
        failures.append(label)
        push_error(label)


func run() -> void:
    var game := MAIN.instantiate()
    root.add_child(game)
    game.play_solo()
    preload("res://tests/fixtures/army_setup.gd").seed(game.sim)
    game.sim.ai_enabled = false
    game.set_process(false)
    var sound: Node = game.audio_controller
    sound.set_process(false)
    sound._process(.1)
    check(sound.streams.size() == 8, "Eight production audio resources loaded")
    for key: String in sound.streams:
        var stream: AudioStreamWAV = sound.streams[key]
        check(stream.mix_rate == 48000 and stream.stereo and stream.get_length() > .1, key + " imports correctly")
    for key: String in ["mining", "hover"]:
        var stream: AudioStreamWAV = sound.streams[key]
        check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_end == 192000, key + " complete loop")
    check(sound.played_counts.get("complete", 0) == 0, "Initial units do not announce production")
    game.camera_controller.focus = game.sim.units[3].pos
    game._update_camera_transform()
    var pos: Vector2 = game.sim.units[3].pos
    var event := {"kind": "shot", "owner": 1, "from": pos, "to": pos + Vector2(10, 0), "life": 5, "frame": 1}
    game.sim.frame = 1
    game.sim.effects = [event.duplicate(true), event.duplicate(true)]
    sound.consume_effects()
    check(sound.played_counts.get("shot", 0) == 2, "Two identical same-frame shots both play")
    check(sound.played_counts.get("hit", 0) == 2, "Hits play on damage rather than death")
    game.sim.effects[0].life -= 1
    sound.consume_effects()
    check(sound.played_counts.shot == 2, "Snapshot lifetime change does not replay")
    for i in range(30):
        sound.play_world("shot", pos)
    check(sound.played_counts.shot == 4, "World voice limit caps dense fire")
    var before: int = sound.played_counts.get("hit", 0)
    sound.play_world("hit", Vector2(4700, 3000))
    check(sound.played_counts.hit == before, "Distant or hidden event stays silent")
    sound.reset_state()
    game.sim.effects.clear()
    sound.consume_effects()
    before = sound.played_counts.get("complete", 0)
    game.sim.add_unit(1, "soldier", pos)
    sound.consume_effects()
    check(sound.played_counts.get("complete", 0) == before + 1, "New friendly unit announces production")
    game.sim.add_unit(2, "soldier", pos)
    sound.consume_effects()
    check(sound.played_counts.complete == before + 1, "Enemy unit never announces production")
    var station: int = game.sim._add_building(1, "barracks", pos + Vector2(100, 0), true)
    sound.consume_effects()
    game.sim.buildings[station].flight.state = "landing"
    sound.consume_effects()
    check(sound.played_counts.get("deploy", 0) == 1, "Landing transition plays deployment once")
    sound.consume_effects()
    check(sound.played_counts.deploy == 1, "Repeated landing snapshot stays silent")
    var miner: int = game.sim.add_unit(1, "harvester", pos)
    game.sim.ores[999] = {"pos": pos + Vector2(30, 0), "amount": 1000}
    game.sim.units[miner].order = "gather"
    game.sim.units[miner].ore = 999
    Simulation.MiningSystem.request(game.sim, game.sim.units[miner], 999)
    game.sim.units[miner].mining.phase = "work"
    game.sim.units[miner].mining.ghost = true
    game.sim.buildings[station].flight.state = "grounded"
    sound.update_loops()
    check(sound.loops.has("mining_u%d" % miner), "Miner in reach starts mining loop")
    check(sound.loops.has("hover_u%d" % miner), "Harvester starts hover loop")
    var loop_player: AudioStreamPlayer3D = sound.loops["mining_u%d" % miner]
    sound.update_loops()
    check(sound.loops["mining_u%d" % miner] == loop_player, "Loop persists without restart each tick")
    game.sim.units[miner].mining.phase = "wait"
    sound.update_loops()
    check(not sound.loops.has("mining_u%d" % miner), "Waiting in reach does not play mining loop")
    game.sim.units[miner].mining.phase = "work"
    var visible: PackedByteArray = game.sim.visible[1].duplicate()
    game.sim.visible[1].fill(0)
    sound.update_loops()
    check(sound.loops.is_empty(), "Fog hides even nearby sound sources")
    game.sim.visible[1] = visible
    game.sim.units[miner].cargo = 60
    sound.update_loops()
    check(not sound.loops.has("mining_u%d" % miner), "Full miner stops drilling before return")
    game.sim.units[miner].cargo = 0
    game.sim.units[miner].order = "idle"
    sound.update_loops()
    check(not sound.loops.has("mining_u%d" % miner), "Stop command silences drill")
    game.sim.units[miner].hp = 0
    sound.update_loops()
    check(not sound.loops.has("hover_u%d" % miner), "Death stops engine")
    game.sim.units.erase(miner)
    for i in range(20):
        game.sim.add_unit(1, "harvester", pos + Vector2(i * 2, 0))
    sound.update_loops()
    check(sound.loops.size() <= Controller.MAX_LOOPS, "Large army has bounded loop voices")
    game.camera_controller.focus = Vector2(4700, 3000)
    sound.update_loops()
    check(sound.loops.is_empty(), "Camera leaving range silences loops")
    game.camera_controller.focus = pos
    sound.reset_state()
    sound.consume_effects()
    before = sound.played_counts.get("select", 0)
    game.selected_units.clear()
    game.selected_units.append(3)
    sound._process(.1)
    check(sound.played_counts.get("select", 0) == before + 1, "Selection plays confirmation")
    before = sound.played_counts.get("click", 0)
    game.attack_rebind_button.pressed.emit()
    check(sound.played_counts.get("click", 0) == before + 1, "Real HUD button plays click")
    game.rebinding_attack = false
    sound.reset_state()
    game._clear_selection()
    game.selected_building = station
    game.selected_buildings.assign([station])
    before = sound.played_counts.get("select", 0)
    sound._process(.1)
    check(sound.played_counts.get("select", 0) == before, "Building selection stays silent")
    game._control_group_key(2, true, false)
    var clicks_before: int = sound.played_counts.get("click", 0)
    game.group_cards[1].pressed.emit()
    sound._process(.1)
    check(sound.played_counts.get("click", 0) == clicks_before and sound.played_counts.get("select", 0) == before, "Building group selection stays silent")
    game._clear_selection()
    game.selected_units.assign([3])
    game._refresh_ui()
    sound._process(.1)
    sound.reset_state()
    before = sound.played_counts.get("select", 0)
    clicks_before = sound.played_counts.get("click", 0)
    game._right_click(pos + Vector2(100, 0))
    check(game.sim.units[3].order == "move" and sound.played_counts.get("select", 0) == before, "Right-click movement keeps order and silences confirmation")
    game.action_buttons[1].pressed.emit()
    game._pending_click(pos + Vector2(120, 0))
    check(sound.played_counts.get("click", 0) == clicks_before and sound.played_counts.get("select", 0) == before, "Move button and destination stay silent")
    # A joining client's first snapshot primes identity; later snapshots share
    # the same event reader and do not require any new wire fields.
    var guest_sim := Simulation.new()
    guest_sim.reset(false, game.sim.map_id)
    var accepted: bool = guest_sim.apply_snapshot(game.sim.snapshot())
    check(accepted, "Existing snapshot accepted: " + guest_sim.last_snapshot_error)
    var guest := Controller.new()
    root.add_child(guest)
    guest.configure(guest_sim, 1)
    guest.initialize()
    guest.enabled = true
    guest.consume_effects()
    check(guest.played_counts.get("complete", 0) == 0, "Joining guest does not announce existing army")
    game.sim.add_unit(1, "soldier", pos)
    check(guest_sim.apply_snapshot(game.sim.snapshot()), "Guest receives subsequent production snapshot")
    guest.consume_effects()
    check(guest.played_counts.get("complete", 0) == 1, "Guest production observation works")
    guest.queue_free()
    # Actual mixer capture, including the imported PCM and GameSFX bus.
    var capture := AudioEffectCapture.new()
    capture.buffer_length = 2.0
    var bus := AudioServer.get_bus_index(Controller.BUS)
    var effect_index := AudioServer.get_bus_effect_count(bus)
    AudioServer.add_bus_effect(bus, capture)
    sound.reset_state()
    sound.play_ui("complete")
    await create_timer(.95).timeout
    var mixed := capture.get_buffer(capture.get_frames_available())
    var peak := 0.0
    for sample: Vector2 in mixed:
        peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
    check(not mixed.is_empty() and peak > .001 and peak < 1.0, "Imported WAV reaches mixer without clipping")
    capture.clear_buffer()
    sound.enabled = true
    sound.play_world("shot", pos)
    await create_timer(.6).timeout
    mixed = capture.get_buffer(capture.get_frames_available())
    var world_peak := 0.0
    for sample: Vector2 in mixed:
        world_peak = maxf(world_peak, maxf(absf(sample.x), absf(sample.y)))
    check(world_peak > .0001 and world_peak < 1.0, "Spatial shot reaches camera listener")
    sound.reset_state()
    sound.update_loops()
    check(not sound.loops.is_empty(), "Engine loop available for playback check")
    var running_loop: AudioStreamPlayer3D = sound.loops.values()[0]
    await create_timer(4.2).timeout
    check(running_loop.playing and running_loop.get_playback_position() < 4.0, "Loop plays across four-second boundary")
    AudioServer.remove_bus_effect(bus, effect_index)
    game.return_to_title()
    check(sound.loops.is_empty() and not sound.enabled, "Return to title immediately stops world audio")
    game.play_solo()
    sound._process(.1)
    check(sound.observed_match == game.sim.match_id, "Restart resets event identity")
    game.queue_free()
    await process_frame
    await process_frame
    print("AUDIO_CHECKS ", checks, " failures=", failures, " mixer_peak=", peak, " world_peak=", world_peak)
    quit(0 if failures.is_empty() else 1)
