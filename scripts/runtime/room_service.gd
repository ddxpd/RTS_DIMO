extends Node
## Stable RPC endpoint shared by the graphical client and headless service.
signal lobby_changed(room: Dictionary)
signal match_started(state: Dictionary, seat: int)
signal world_received(state: Dictionary)
signal message(text: String)
signal connection_ready
signal connection_lost

const Sim = preload("res://scripts/simulation.gd")
const Config = preload("res://scripts/runtime/match_config.gd")
const PORT := 24562
const CHUNK := 1100
const MAX_PACKET := 4194304
var serving := false
var rooms := {}
var members := {}
var authenticated := {}
var limits := {}
var max_rooms := 8
var peer: ENetMultiplayerPeer
var room_code := ""
var token := ""
var nickname := "指挥官"
var latest_frame := -1
var incoming := {}
var accumulator := 0.0
var next_match := 0
var current_match := -1

func _ready() -> void:
    multiplayer.connected_to_server.connect(_connected)
    multiplayer.peer_disconnected.connect(_departed)
    multiplayer.connection_failed.connect(_lost)
    multiplayer.server_disconnected.connect(_lost)

func listen(bind_address: String = "127.0.0.1", port: int = PORT) -> Error:
    peer = ENetMultiplayerPeer.new()
    peer.set_bind_ip(bind_address)
    var status := peer.create_server(port, 32, 3)
    if status == OK:
        serving = true
        multiplayer.multiplayer_peer = peer
    return status

func connect_to(address: String, port: int = PORT) -> Error:
    disconnect_service(false)
    peer = ENetMultiplayerPeer.new()
    var status := peer.create_client(address, port, 3)
    if status == OK:
        multiplayer.multiplayer_peer = peer
    return status

func disconnect_service(forget: bool = true) -> void:
    if peer != null:
        peer.close()
    multiplayer.multiplayer_peer = null
    peer = null
    incoming.clear()
    if forget:
        room_code = ""
        token = ""

func _connected() -> void:
    request.rpc_id(1, "hello", {"version": Sim.VERSION, "name": nickname.left(24)})

func _lost() -> void:
    disconnect_service(false)
    connection_lost.emit()

func send(action: String, data: Dictionary = {}) -> void:
    if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
        message.emit("尚未连接服务器。")
        return
    request.rpc_id(1, action, data)

func _process(delta: float) -> void:
    if not serving:
        return
    accumulator += minf(delta, 0.25)
    while accumulator >= 0.05:
        accumulator -= 0.05
        for code: String in rooms.keys():
            var room: Dictionary = rooms[code]
            if room.sim == null:
                continue
            for seat: int in room.absent.keys():
                if Time.get_ticks_msec() >= room.absent[seat]:
                    room.sim.surrender(seat)
                    room.absent.erase(seat)
                    room.tokens.erase(seat)
            if room.peers.is_empty() and room.absent.is_empty():
                rooms.erase(code)
                continue
            if room.sim.winner != 0:
                if not room.get("finished", false):
                    room.finished = true
                    var final_packet := pack(room.sim.snapshot())
                    for id: int in room.peers:
                        event.rpc_id(id, "final", {"data": final_packet})
                continue
            var previous: int = room.sim.winner
            room.sim.step()
            if room.sim.frame % 4 == 0 or room.sim.winner != previous:
                var packed := pack(room.sim.snapshot())
                for id: int in room.peers:
                    if room.sim.winner != previous:
                        event.rpc_id(id, "final", {"data": packed})
                    elif room.sim.winner == 0:
                        _send_world(id, room.sim.match_id, room.sim.frame, packed)
                if room.sim.winner != 0:
                    room.finished = true
            if room.peers.is_empty() and room.absent.is_empty():
                rooms.erase(code)

static func pack(state: Dictionary) -> PackedByteArray:
    var raw := var_to_bytes(state)
    var compressed := raw.compress(FileAccess.COMPRESSION_ZSTD)
    var packet := PackedByteArray()
    packet.resize(4)
    packet.encode_u32(0, raw.size())
    packet.append_array(compressed)
    return packet

static func unpack(packet: PackedByteArray) -> Dictionary:
    if packet.size() < 5 or packet.size() > MAX_PACKET:
        return {}
    var length := packet.decode_u32(0)
    if length > MAX_PACKET or length == 0:
        return {}
    var raw := packet.slice(4).decompress(length, FileAccess.COMPRESSION_ZSTD)
    if raw.size() != length:
        return {}
    var value: Variant = bytes_to_var(raw)
    return value if value is Dictionary else {}

func _send_world(id: int, match_id: int, frame: int, data: PackedByteArray) -> void:
    var count := ceili(float(data.size()) / CHUNK)
    for index in range(count):
        world_chunk.rpc_id(id, match_id, frame, index, count, data.slice(index * CHUNK, (index + 1) * CHUNK))

@rpc("authority", "call_remote", "unreliable", 1)
func world_chunk(match_id: int, frame: int, index: int, count: int, data: PackedByteArray) -> void:
    if serving or match_id != current_match or frame <= latest_frame or count < 1 or count > ceili(float(MAX_PACKET) / CHUNK) or index < 0 or index >= count or data.size() > CHUNK:
        return
    if frame < int(incoming.get("frame", -1)):
        return
    if frame != int(incoming.get("frame", -1)):
        incoming = {"frame": frame, "count": count, "chunks": {}}
    if incoming.count != count:
        return
    incoming.chunks[index] = data
    if incoming.chunks.size() == count:
        var packed := PackedByteArray()
        for i in range(count):
            packed.append_array(incoming.chunks[i])
        var state := unpack(packed)
        incoming.clear()
        if not state.is_empty() and state.get("match") == current_match:
            latest_frame = frame
            world_received.emit(state)

func _reject(id: int, reason: String) -> void:
    event.rpc_id(id, "error", {"text": reason})

func _public(room: Dictionary) -> Dictionary:
    return {"code": room.code, "config": room.config.duplicate(true), "names": room.names.duplicate(),
        "ready": room.ready.duplicate(), "host": room.host, "started": room.sim != null}

func _publish(room: Dictionary) -> void:
    for id: int in room.peers:
        var data := _public(room)
        data["seat"] = room.peers[id]
        event.rpc_id(id, "lobby", data)

func _admit(id: int, room: Dictionary, seat: int) -> void:
    room.peers[id] = seat
    members[id] = room.code
    room.names[seat] = authenticated[id]
    room.config.seats[seat - 1] = "human"
    room.ready[seat] = false
    var secret := Crypto.new().generate_random_bytes(24).hex_encode()
    room.tokens[seat] = secret
    event.rpc_id(id, "ticket", {"code": room.code, "token": secret})
    _publish(room)

@rpc("any_peer", "call_remote", "reliable", 0)
func request(action: String, data: Dictionary) -> void:
    if not serving:
        return
    var id := multiplayer.get_remote_sender_id()
    var now := Time.get_ticks_msec()
    var rate: Dictionary = limits.get(id, {"time": now, "count": 0})
    if now - rate.time >= 1000:
        rate = {"time": now, "count": 0}
    rate.count += 1
    limits[id] = rate
    if rate.count > 80 or var_to_bytes(data).size() > 65536:
        return
    if action == "hello":
        if data.get("version") != Sim.VERSION:
            _reject(id, "版本不一致，请使用同一版本。")
            return
        authenticated[id] = str(data.get("name", "指挥官")).strip_edges().left(24)
        event.rpc_id(id, "connected", {})
        return
    if not authenticated.has(id):
        return
    if action == "leave":
        _leave(id, false)
        event.rpc_id(id, "left", {})
        return
    if action == "create":
        if members.has(id) or rooms.size() >= max_rooms:
            _reject(id, "已在房间内，或服务器房间已满。")
            return
        var code := Crypto.new().generate_random_bytes(4).hex_encode().to_upper()
        while rooms.has(code):
            code = Crypto.new().generate_random_bytes(4).hex_encode().to_upper()
        var config := Config.defaults()
        config.seats = ["human", "open", "closed", "closed"]
        var room := {"code": code, "config": config, "host": 1, "peers": {}, "names": {}, "ready": {}, "tokens": {}, "absent": {}, "sim": null}
        rooms[code] = room
        _admit(id, room, 1)
        return
    if action in ["join", "reconnect"]:
        var code := str(data.get("code", "")).to_upper()
        if members.has(id) or not rooms.has(code):
            _reject(id, "房间不存在，或已在房间中。")
            return
        var room: Dictionary = rooms[code]
        if action == "reconnect":
            for seat: int in room.absent:
                if now < room.absent[seat] and data.get("token", "") == room.tokens.get(seat):
                    room.absent.erase(seat)
                    room.peers[id] = seat
                    members[id] = code
                    event.rpc_id(id, "start", {"seat": seat, "data": pack(room.sim.snapshot())})
                    return
            _reject(id, "重连凭据已失效。")
            return
        if room.sim != null:
            _reject(id, "对局已开始，不能中途加入。")
            return
        var seat: int = room.config.seats.find("open") + 1
        if seat == 0:
            _reject(id, "没有开放席位。")
            return
        _admit(id, room, seat)
        return
    if not members.has(id):
        return
    var room: Dictionary = rooms[members[id]]
    var seat: int = room.peers[id]
    if action == "order" and room.sim != null:
        var reason: String = room.sim.command(seat, data)
        if not reason.is_empty():
            _reject(id, reason)
    elif action == "configure" and room.sim == null and seat == room.host:
        var reason := Config.error(data)
        if data.get("training", false):
            reason = "训练场为离线模式。"
        if reason.is_empty():
            for i in range(4):
                if (i + 1 in room.peers.values()) != (data.seats[i] == "human"):
                    reason = "不能修改真人占用的席位。"
        if not reason.is_empty():
            _reject(id, reason)
            return
        room.config = data.duplicate(true)
        room.ready.clear()
        _publish(room)
    elif action == "ready" and room.sim == null:
        room.ready[seat] = not room.ready.get(seat, false)
        _publish(room)
    elif action == "start" and room.sim == null and seat == room.host:
        var reason := Config.error(room.config, true)
        for human: int in room.peers.values():
            if not room.ready.get(human, false):
                reason = "所有真人玩家准备后才能开始。"
        if not reason.is_empty():
            _reject(id, reason)
            return
        var simulation := Sim.new()
        if not simulation.reset(false, room.config.map, room.config):
            _reject(id, simulation.last_snapshot_error)
            return
        room.sim = simulation
        next_match += 1
        simulation.match_id = next_match
        var packed := pack(simulation.snapshot())
        for other: int in room.peers:
            event.rpc_id(other, "start", {"seat": room.peers[other], "data": packed})

func _departed(id: int) -> void:
    if serving:
        _leave(id, true)
        authenticated.erase(id)
        limits.erase(id)

func _leave(id: int, disconnected: bool) -> void:
    if not members.has(id):
        return
    var code: String = members[id]
    var room: Dictionary = rooms[code]
    var seat: int = room.peers[id]
    members.erase(id)
    room.peers.erase(id)
    if room.sim != null:
        if disconnected:
            room.absent[seat] = Time.get_ticks_msec() + 60000
        else:
            room.sim.surrender(seat)
            room.tokens.erase(seat)
            var packed := pack(room.sim.snapshot())
            for other: int in room.peers:
                event.rpc_id(other, "final", {"data": packed})
    else:
        room.config.seats[seat - 1] = "open"
        room.names.erase(seat)
        room.ready.clear()
    if room.peers.is_empty() and room.absent.is_empty():
        rooms.erase(code)
        return
    if seat == room.host and not room.peers.is_empty():
        room.host = room.peers.values()[0]
    _publish(room)

@rpc("authority", "call_remote", "reliable", 0)
func event(kind: String, data: Dictionary) -> void:
    if serving:
        return
    match kind:
        "connected": connection_ready.emit()
        "ticket":
            room_code = data.code
            token = data.token
        "lobby": lobby_changed.emit(data)
        "start":
            var state := unpack(data.data)
            if state.is_empty():
                message.emit("无法读取初始状态。")
                return
            latest_frame = state.frame
            current_match = state.match
            incoming.clear()
            match_started.emit(state, data.seat)
        "final":
            var state := unpack(data.data)
            if not state.is_empty() and state.get("match") == current_match and int(state.frame) >= latest_frame:
                latest_frame = state.frame
                world_received.emit(state)
        "left":
            room_code = ""
            token = ""
        "error": message.emit(str(data.text))
