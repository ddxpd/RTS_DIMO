class_name NetworkSession
extends Node

const Simulation = preload("res://scripts/simulation.gd")

var host


func configure(owner) -> void:
    host = owner


func _apply_snapshot_checked(state: Dictionary, context: String) -> bool:
    if host == null or host.sim.apply_snapshot(state):
        return host != null
    var detail: String = host.sim.last_snapshot_error
    disconnect_session.call_deferred()
    host.active = false
    host.connected = false
    host._notify("Invalid %s snapshot%s" % [context, ": " + detail if not detail.is_empty() else ""])
    return false


func disconnect_session() -> void:
    if host == null:
        return
    if host.multiplayer.multiplayer_peer != null:
        host.multiplayer.multiplayer_peer.close()
    host.multiplayer.multiplayer_peer = null
    host.peer = null
    host.is_host = false
    host.connected = false
    host.slots.clear()
    host.handshakes.clear()
    host.rates.clear()


func submit_order(order: Dictionary) -> void:
    if host == null:
        return
    if not host.active or host.local_slot == 0:
        host._notify("Spectators cannot issue orders.")
        return
    if host.is_host or not host.connected:
        var error: String = host.sim.command(host.local_slot, order)
        if not error.is_empty():
            host._notify(error)
    else:
        _order.rpc_id(1, order)


func broadcast_world(state: Dictionary) -> void:
    if host != null and host.is_host and not host.slots.is_empty():
        _world.rpc(state)


func broadcast_final_state(state: Dictionary) -> void:
    if host != null and host.is_host:
        _final_state.rpc(state)


func broadcast_new_match(state: Dictionary) -> void:
    if host != null and host.is_host:
        _new_match.rpc(state)


func peer_joined(id: int) -> void:
    if host != null and host.is_host:
        host.handshakes[id] = Time.get_ticks_msec()


func connected_to_server() -> void:
    if host == null:
        return
    Input.mouse_mode = Input.MOUSE_MODE_CONFINED
    _hello.rpc_id(1, Simulation.VERSION)


func peer_left(id: int) -> void:
    if host == null:
        return
    host.handshakes.erase(id)
    host.rates.erase(id)
    if host.is_host:
        var was_player: bool = host.slots.get(id, 0) == 2
        host.slots.erase(id)
        if was_player:
            for other: int in host.slots:
                if host.slots[other] == 0:
                    host.slots[other] = 2
                    _accepted.rpc_id(other, Simulation.VERSION, 2, host.sim.snapshot())
                    break
            host._notify("Red player disconnected; army retained for reconnect.")


func connection_failed() -> void:
    if host == null:
        return
    disconnect_session()
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    host.active       = false
    host.menu_visible = true
    host.menu.visible = true
    host._notify("Connection failed. Check host address and UDP 24560.")


func server_left() -> void:
    if host == null:
        return
    disconnect_session()
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    host.active       = false
    host.menu_visible = true
    host.menu.visible = true
    host._clear_selection()
    host._notify("Host disconnected. Match stopped; return to title or start a new match.")


@rpc("any_peer", "reliable")
func _hello(version: String) -> void:
    if host == null or not host.is_host:
        return
    var sender := multiplayer.get_remote_sender_id()
    if host.slots.has(sender):
        return
    if version != Simulation.VERSION:
        _rejected.rpc_id(sender, "Different game version. Both players need this release.")
        return
    host.handshakes.erase(sender)
    var slot := 2 if not host.slots.values().has(2) else 0
    host.slots[sender] = slot
    _accepted.rpc_id(sender, Simulation.VERSION, slot, host.sim.snapshot())


@rpc("authority", "reliable")
func _accepted(version: String, slot: int, state: Dictionary) -> void:
    if host == null:
        return
    if version != Simulation.VERSION:
        _rejected("Different game version")
        return
    host.connected  = true
    host.active     = true
    host.local_slot = slot
    if not _apply_snapshot_checked(state, "accepted"):
        return
    host.sim.rebuild_navigation()
    host._reset_view()
    host._notify("Red army assigned." if slot == 2 else "Spectator mode: no orders allowed.")


@rpc("authority", "reliable")
func _rejected(reason: String) -> void:
    if host == null:
        return
    disconnect_session.call_deferred()
    host.active = false
    host._notify(reason)


@rpc("authority", "call_remote", "reliable", 1)
func _world(state: Dictionary) -> void:
    if host == null:
        return
    if state.get("version") != Simulation.VERSION or state.get("match") != host.sim.match_id:
        return
    if typeof(state.get("frame")) != TYPE_INT:
        _apply_snapshot_checked(state, "world")
        return
    if int(state.frame) < host.sim.frame:
        return
    var previous_positions: Dictionary = {}
    for id: int in host.sim.units:
        previous_positions[id] = host.sim.units[id].pos
    var previous_frame: int = host.sim.frame
    if not _apply_snapshot_checked(state, "world"):
        return
    host._update_render_velocities(previous_positions, previous_frame, int(state.frame))
    host._audio_for_effects()


@rpc("authority", "reliable")
func _final_state(state: Dictionary) -> void:
    if host != null and state.get("match") == host.sim.match_id:
        _apply_snapshot_checked(state, "final")


@rpc("authority", "reliable")
func _new_match(state: Dictionary) -> void:
    if host == null:
        return
    if not _apply_snapshot_checked(state, "new match"):
        return
    host.sim.rebuild_navigation()
    host._reset_view()


@rpc("any_peer", "reliable")
func _order(order: Dictionary) -> void:
    if host == null or not host.is_host:
        return
    var sender := multiplayer.get_remote_sender_id()
    if not host.slots.has(sender):
        return
    var rate: Dictionary = host.rates.get(sender, {"frame": host.sim.frame, "count": 0})
    if host.sim.frame - int(rate.frame) >= 20:
        rate = {"frame": host.sim.frame, "count": 0}
    rate.count += 1
    host.rates[sender] = rate
    if rate.count > 64:
        return
    var error: String = host.sim.command(int(host.slots[sender]), order)
    if not error.is_empty():
        _order_error.rpc_id(sender, error)


@rpc("authority", "reliable")
func _order_error(message: String) -> void:
    if host != null:
        host._notify(message)
