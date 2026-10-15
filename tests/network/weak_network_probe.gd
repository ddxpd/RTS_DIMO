extends Node
## Uses production commands/snapshots. Test-only RPCs observe, never repair state.
var game
var role := "host"
var round_number := 1
var output := ""
var duration := 180.0
var started := 0
var deadline := 0
var failures: Array[String] = []
var intervals: Array[float] = []
var acknowledgements: Array[float] = []
var pings: Array[float] = []
var host_steps: Array[float] = []
var last_snapshot := 0
var last_frame := -1
var last_tick := 0
var sequence := 0
var pending := {}
var stage := -1
var last_order := -1
var last_host_move := -1
var requested_stop := false
var frozen_frame := -1
var snapshot_sizes: Array[float] = []
var loads: Array = []
var finishing := false
var final_state: Dictionary = {}
var compared := false
var snapshot_times: Array[float] = []
var frame_lag: Array = []
var comparison_passed := false
var ack_samples: Array = []
var comparison_file := ""

func check(value: bool, message: String) -> void:
    if not value and message not in failures:
        failures.append(message)
        push_error("WEAK_NETWORK " + message)

func start() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--output="):
            output = arg.trim_prefix("--output=")
        elif arg.begins_with("--duration="):
            duration = float(arg.trim_prefix("--duration="))
    deadline = Time.get_ticks_msec() + int((duration + 120) * 1000)
    if role == "host":
        game.create_host()
        game.sim.ai_enabled = false
        game.session.simulation_tick.connect(_host_tick)
        print("WEAK_HOST_READY")
    else:
        game.network_session.snapshot_applied.connect(_snapshot)
        game.join_host()
        while not game.connected and Time.get_ticks_msec() < deadline:
            await get_tree().process_frame
        check(game.connected and game.local_slot == 2, "Guest receives player slot")
        if not failures.is_empty():
            finish()
            return
        started = Time.get_ticks_msec()
        deadline = started + int((duration + 30) * 1000)
        _begin.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable", 2)
func _begin() -> void:
    if game.is_host and game.slots.get(multiplayer.get_remote_sender_id(), 0) == 2:
        started = Time.get_ticks_msec()
        deadline = started + int((duration + 40) * 1000)

func _host_tick(_previous: int, _winner: int) -> void:
    var now := Time.get_ticks_msec()
    if last_tick > 0:
        host_steps.append(float(now - last_tick))
    last_tick = now

func _snapshot(frame: int) -> void:
    var now := Time.get_ticks_msec()
    check(frame >= last_frame, "Snapshot frames remain monotonic")
    last_frame = frame
    if last_snapshot > 0:
        intervals.append(float(now - last_snapshot))
    last_snapshot = now
    snapshot_times.append(Time.get_unix_time_from_system() * 1000)
    if sequence % 10 == 0:
        snapshot_sizes.append(float(var_to_bytes(game.sim.snapshot()).size()))
    if frozen_frame >= 0 and frame == frozen_frame and not compared:
        compared = true
        _compare_actual.rpc_id(1, game.sim.snapshot())

func _process(_delta: float) -> void:
    var now := Time.get_ticks_msec()
    if deadline > 0 and now > deadline:
        check(false, "Watchdog expired: " + str(game.feedback))
        finish()
        return
    if started == 0:
        return
    var elapsed := (now - started) / 1000.0
    if role == "host":
        var next_stage := mini(2, int(elapsed / (duration / 3)))
        if next_stage != stage:
            stage = next_stage
            seed_load([50, 100, 200][stage])
        var move_number := int(elapsed / 8)
        if move_number != last_host_move and not requested_stop:
            last_host_move = move_number
            for id: int in game.sim.units:
                var unit: Dictionary = game.sim.units[id]
                if unit.owner == 1:
                    game.sim.command(1, {"action": "move", "units": [id], "pos": Vector2(2080 + (id % 10) * 32 + (move_number % 2) * 160, 1250 + ((id / 10) % 10) * 32)})
        return
    if not game.connected:
        check(false, "Unexpected disconnect: " + str(game.feedback))
        finish()
        return
    var order_number := int(elapsed)
    if order_number != last_order and not requested_stop:
        last_order = order_number
        var selected: Array[int] = []
        var candidates: Array[int] = []
        for id: int in game.sim.units:
            if game.sim.units[id].owner == 2:
                candidates.append(id)
        for index in range(mini(12, candidates.size())):
            selected.append(candidates[(order_number * 12 + index) % candidates.size()])
        if not selected.is_empty():
            var target := Vector2(2080 + (order_number % 4) * 128, 1800 + ((order_number / 4) % 3) * 96)
            sequence += 1
            pending[sequence] = now
            game.issue({"action": "move", "units": selected, "pos": target})
            _ack_request.rpc_id(1, sequence, selected, target)
        _ping.rpc_id(1, now)
    if elapsed >= duration and not requested_stop:
        requested_stop = true
        _freeze.rpc_id(1)

func seed_load(count: int) -> void:
    game.sim.units.clear()
    for index in range(count):
        var owner := 1 if index < count / 2 else 2
        var local_index := index % (count / 2)
        var position := Vector2(2080 + (local_index % 10) * 32, (1250 if owner == 1 else 1800) + (local_index / 10) * 32)
        game.sim.add_unit(owner, "mobile_infantry", position)
    loads.append(count)
    print("WEAK_LOAD units=", count, " frame=", game.sim.frame)

@rpc("any_peer", "reliable")
func _ack_request(number: int, ids: Array, target: Vector2) -> void:
    if not game.is_host:
        return
    var applied := false
    var surviving := 0
    for id in ids:
        if game.sim.units.has(id) and game.sim.units[id].owner == 2:
            surviving += 1
            applied = applied or game.sim.units[id].get("arrival", {}).get("anchor") == target
    check(surviving == 0 or applied, "Ordered destination applied before acknowledgement")
    _ack.rpc_id(multiplayer.get_remote_sender_id(), number, applied)

@rpc("authority", "call_remote", "reliable", 2)
func _ack(number: int, applied: bool) -> void:
    if pending.has(number):
        var measured := float(Time.get_ticks_msec() - pending[number])
        acknowledgements.append(measured)
        ack_samples.append({"elapsed_ms": Time.get_ticks_msec() - started, "ms": measured})
        pending.erase(number)
    # A load transition may replace the units while commands are in transit.
    if applied:
        set_meta("observed_command", true)

@rpc("any_peer", "call_remote", "unreliable", 3)
func _ping(sent: int) -> void:
    if game.is_host:
        _pong.rpc_id(multiplayer.get_remote_sender_id(), sent, game.sim.frame)

@rpc("authority", "call_remote", "unreliable", 3)
func _pong(sent: int, host_frame: int) -> void:
    pings.append(float(Time.get_ticks_msec() - sent))
    frame_lag.append({"elapsed_ms": Time.get_ticks_msec() - started, "frames": maxi(0, host_frame - last_frame)})

@rpc("any_peer", "call_remote", "reliable", 0)
func _freeze() -> void:
    if not game.is_host:
        return
    requested_stop = true
    game.set_process(false)
    # Orders and this barrier share channel 0. Advance once after all preceding
    # orders, so an older snapshot with the same frame cannot satisfy the test.
    game.sim.step()
    var state: Dictionary = game.sim.snapshot()
    final_state = state.duplicate(true)
    _barrier.rpc_id(multiplayer.get_remote_sender_id(), int(state.frame))

@rpc("authority", "call_remote", "reliable", 2)
func _barrier(frame: int) -> void:
    frozen_frame = frame
    # Request one production snapshot after the observer is ready. This avoids
    # channel-order races without adding a burst of duplicate final snapshots.
    _request_final_world.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable", 2)
func _request_final_world() -> void:
    if game.is_host and not final_state.is_empty():
        game.network_session.broadcast_world(final_state)

@rpc("any_peer", "call_remote", "reliable", 2)
func _compare_actual(state: Dictionary) -> void:
    if not game.is_host:
        return
    var fields: Array = []
    for key in final_state:
        if final_state[key] != state.get(key):
            fields.append(key)
    var run_directory := output.get_base_dir()
    var audit_directory := "res://.local/simulation_audits/weak_network/" + run_directory.get_base_dir().get_file() + "/" + run_directory.get_file()
    DirAccess.make_dir_recursive_absolute(audit_directory)
    comparison_file = audit_directory + "/states.bin"
    var file := FileAccess.open(comparison_file, FileAccess.WRITE)
    file.store_var([final_state, state])
    file.close()
    _comparison.rpc_id(multiplayer.get_remote_sender_id(), fields)

@rpc("authority", "call_remote", "reliable", 2)
func _comparison(fields: Array) -> void:
    comparison_passed = fields.is_empty()
    check(fields.is_empty(), "Final production state identical: " + str(fields))
    _finished.rpc_id(1)
    await get_tree().create_timer(0.3).timeout
    finish()

@rpc("any_peer", "call_remote", "reliable", 2)
func _finished() -> void:
    if game.is_host:
        await get_tree().create_timer(1).timeout
        finish()

func stats(values: Array[float]) -> Dictionary:
    if values.is_empty():
        return {"count": 0}
    var sorted := values.duplicate()
    sorted.sort()
    return {"count": sorted.size(), "p50": sorted[int(sorted.size() * 0.5)], "p95": sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))], "max": sorted[-1]}

func finish() -> void:
    if finishing:
        return
    finishing = true
    set_process(false)
    if role != "host":
        check(bool(get_meta("observed_command", false)), "Production command execution observed")
        check(frozen_frame >= 0, "Final convergence barrier reached")
        check(comparison_passed, "Final state comparison completed")
    var result := {"role": role, "failures": failures, "duration_ms": Time.get_ticks_msec() - started, "loads": loads, "ack_ms": stats(acknowledgements), "rtt_ms": stats(pings), "snapshot_interval_ms": stats(intervals), "snapshot_serialized_bytes": stats(snapshot_sizes), "host_tick_interval_ms": stats(host_steps), "pending_commands": pending.size(), "final_frame": frozen_frame}
    result["snapshot_unix_ms"] = snapshot_times
    result["snapshot_frame_lag"] = frame_lag
    result["ack_samples"] = ack_samples
    result["comparison_file"] = comparison_file
    var file := FileAccess.open(output, FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(result, "  "))
        file.close()
    print("WEAK_NETWORK_RESULT ", JSON.stringify(result))
    game.queue_free()
    await get_tree().process_frame
    get_tree().quit(0 if failures.is_empty() else 1)
