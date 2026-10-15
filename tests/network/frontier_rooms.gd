extends SceneTree
const Service = preload("res://scripts/runtime/room_service.gd")
const Config = preload("res://scripts/runtime/match_config.gd")
var failures := []
var clients: Array = []
var server: Node
var states := {}
var lobbies := {}
var started := {}
var connections := {}
var weak := false
var link: Node

func check(value: bool, label: String) -> void:
    if not value:
        failures.append(label)
        push_error(label)

func _initialize() -> void:
    run.call_deferred()

func endpoint(label: String) -> Node:
    var branch := Node.new()
    branch.name = label
    root.add_child(branch)
    var api := SceneMultiplayer.new()
    set_multiplayer(api, branch.get_path())
    var node := Service.new()
    node.name = "Service"
    branch.add_child(node)
    return node

func pause(seconds: float = 0.6) -> void:
    await create_timer(seconds).timeout

func wait_until(condition: Callable, timeout_ms: int = 4000) -> bool:
    var deadline := Time.get_ticks_msec() + timeout_ms
    while not condition.call() and Time.get_ticks_msec() < deadline:
        await process_frame
    return condition.call()

func run() -> void:
    weak = weak or "--weak" in OS.get_cmdline_user_args()
    if weak:
        link = preload("res://tests/network/room_link.gd").new()
        root.add_child(link)
    server = endpoint("Server")
    check(server.listen("127.0.0.1", 24566) == OK, "server bind")
    for i in range(5):
        var client := endpoint("Client%d" % i)
        clients.append(client)
        client.connection_ready.connect(func(): connections[i] = int(connections.get(i, 0)) + 1)
        client.nickname = "Pilot%d" % i
        client.lobby_changed.connect(func(data): lobbies[i] = data)
        client.match_started.connect(func(data, seat):
            states[i] = data
            started[i] = seat)
        client.world_received.connect(func(data): states[i] = data)
        check(client.connect_to("127.0.0.1", 24567 if weak else 24566) == OK, "client connect")
    await pause(1.2)
    clients[0].send("create")
    clients[4].send("create")
    await pause()
    check(server.rooms.size() == 2, "room isolation")
    if not lobbies.has(0):
        finish()
        return
    var code: String = lobbies[0].code
    var config: Dictionary = lobbies[0].config.duplicate(true)
    config.seats = ["human", "open", "open", "open"]
    clients[0].send("configure", config)
    await pause()
    for i in range(1, 4):
        clients[i].send("join", {"code": code})
        await pause()
    check(server.rooms[code].peers.size() == 4, "four seats joined")
    clients[0].send("start")
    await pause()
    check(server.rooms[code].sim == null, "cannot start before readiness")
    var original_funds: int = server.rooms[code].config.funds
    var unauthorized: Dictionary = server.rooms[code].config.duplicate(true)
    unauthorized.funds = 12345
    clients[1].send("configure", unauthorized)
    await pause()
    check(server.rooms[code].config.funds == original_funds, "only manager configures room")
    for i in range(4):
        clients[i].send("ready")
    await pause()
    clients[0].send("start")
    await pause(1.0)
    check(started.size() == 4 and not started.has(4), "only room members start")
    check(states.has(3) and states[3].players.size() == 4, "four-owner snapshots")
    check(states.has(2) and states[2].frame > 0, "unreliable chunk stream")
    var accepted_frame: int = clients[0].latest_frame
    clients[0].world_chunk(-999, 999999, 0, 1, PackedByteArray([1, 2, 3]))
    check(clients[0].latest_frame == accepted_frame, "late previous-match chunks rejected")
    check(Service.unpack(PackedByteArray([255, 255, 255, 255, 0])).is_empty(), "decompression allocation is bounded")
    var room: Dictionary = server.rooms[code]
    for owner in range(1, 5):
        var ids := []
        var origin: Vector2 = room.sim.terrain.definition.spawns[owner - 1]
        for index in range(50):
            ids.append(room.sim.add_unit(owner, "mobile_infantry", origin + Vector2((index % 10) * 48, 160 + (index / 10) * 48)))
        clients[owner - 1].send("order", {"action": "move", "units": ids, "pos": origin + Vector2(600 if origin.x < 2400 else -600, 0)})
    await pause(8.0 if weak else 2.0)
    for i in range(4):
        check(states.has(i) and states[i].units.size() == 200, "200-unit state reaches client %d" % i)
        check(states.has(i) and room.sim.frame - int(states[i].frame) < 60, "bounded snapshot age client %d" % i)
    if weak:
        check(link.drops > 0, "real UDP loss exercised")
        print("ROOM_WEAK packets=", link.sent, " dropped=", link.drops, " server_frame=", room.sim.frame, " client_frames=", states.values().map(func(state): return state.frame))
    var seat: int = started.get(1, 2)
    var token: String = clients[1].token
    clients[1].disconnect_service(false)
    await pause()
    check(room.absent.has(seat), "reconnect grace period")
    var previous_connections: int = connections.get(1, 0)
    check(clients[1].connect_to("127.0.0.1", 24567 if weak else 24566) == OK, "reconnect transport starts")
    # Wait for the authenticated handshake; packet loss can trigger ENet retries.
    # Sleeping 600ms could send the command while the peer was still connecting.
    check(await wait_until(func(): return int(connections.get(1, 0)) > previous_connections), "reconnect handshake completes")
    clients[1].send("reconnect", {"code": code, "token": token})
    check(await wait_until(func(): return not room.absent.has(seat) and room.peers.size() == 4), "reconnect restores seat")
    clients[0].send("leave")
    await pause()
    check(room.host != 1 and room.sim.eliminated.has(1), "host departure transfers manager")
    check(server.rooms.size() == 2, "other room persists")
    var expiring_seat: int = started[2]
    clients[2].disconnect_service(false)
    await pause()
    check(room.absent.has(expiring_seat), "second disconnect reserves seat")
    room.absent[expiring_seat] = Time.get_ticks_msec() - 1
    await pause()
    check(room.sim.eliminated.has(expiring_seat) and not room.tokens.has(expiring_seat), "expired reconnect forfeits and revokes token")
    for client in clients:
        client.send("leave")
    await pause()
    check(server.rooms.is_empty(), "empty rooms reclaimed")
    finish()

func finish() -> void:
    for node in clients + [server]:
        node.disconnect_service()
        node.get_parent().queue_free()
    if link != null:
        link.queue_free()
    await process_frame
    print("FRONTIER_ROOMS ", JSON.stringify({"passed": failures.is_empty(), "failures": failures}))
    quit(0 if failures.is_empty() else 1)
