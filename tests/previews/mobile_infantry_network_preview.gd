extends Node
## Focused real ENet roundtrip using the game's actual RPC and snapshot handlers.
## This supplements, but does not replace, the complete multi-process regression.

var server_game: Node3D
var guest_game: Node3D
var failures: Array[String] = []


func check(value: bool, label: String) -> void:
    if not value:
        failures.append(label)


func wait_until(predicate: Callable, seconds: float = 6.0) -> bool:
    var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
    while Time.get_ticks_msec() < deadline:
        if predicate.call():
            return true
        await get_tree().process_frame
    return false


func make_game(branch_name: String) -> Node3D:
    var branch := Node.new()
    branch.name = branch_name
    add_child(branch)
    var api := SceneMultiplayer.new()
    api.root_path = branch.get_path()
    get_tree().set_multiplayer(api, branch.get_path())
    var game := load("res://scenes/main.tscn").instantiate() as Node3D
    game.name = "Game"
    branch.add_child(game)
    game.set_process_input(false)
    game.set_process_unhandled_input(false)
    for child in game.get_children():
        if child is CanvasLayer:
            child.hide()
    return game


func _ready() -> void:
    server_game = make_game("Server")
    guest_game = make_game("Guest")
    server_game.peer = ENetMultiplayerPeer.new()
    server_game.peer.set_bind_ip("127.0.0.1")
    var error: int = server_game.peer.create_server(24561, 4)
    check(error == OK, "Loopback server starts")
    if error != OK:
        finish()
        return
    server_game.multiplayer.multiplayer_peer = server_game.peer
    server_game.is_host = true
    server_game.connected = true
    server_game.active = true
    server_game.local_slot = 1
    server_game.sim.reset(false, "desert_quarry")
    server_game._reset_view()
    var barracks: int = server_game.sim._add_building(2, "barracks", Vector2(3600, 2600), true)
    server_game.sim.rebuild_navigation()
    guest_game.peer = ENetMultiplayerPeer.new()
    error = guest_game.peer.create_client("127.0.0.1", 24561)
    check(error == OK, "Loopback guest starts")
    guest_game.multiplayer.multiplayer_peer = guest_game.peer
    check(await wait_until(func() -> bool: return guest_game.connected), "Game protocol handshake")
    if not guest_game.connected:
        finish()
        return
    check(guest_game.local_slot == 2, "Guest receives red slot")
    guest_game.issue({"action": "produce", "building": barracks, "type": "mobile_infantry"})
    check(await wait_until(func() -> bool: return find_mobile(server_game) >= 0), "Guest production reaches authoritative host")
    var id := find_mobile(server_game)
    check(await wait_until(func() -> bool: return guest_game.sim.units.has(id)), "Produced infantry arrives in guest snapshot")
    if id >= 0 and guest_game.sim.units.has(id):
        var initial: Vector2 = server_game.sim.units[id].pos
        guest_game.issue({"action": "move", "units": [id], "pos": initial + Vector2(-150, 0)})
        check(await wait_until(func() -> bool: return server_game.sim.units[id].pos.distance_to(initial) > 20), "Guest can move new unit")
        check(await wait_until(func() -> bool: return guest_game.sim.units[id].pos.distance_to(initial) > 15), "Guest receives moving snapshots")
        server_game.sim.units[id].hp = 0
        check(await wait_until(func() -> bool: return not guest_game.sim.units.has(id)), "Death removal synchronized")
        var death_received := false
        for event: Dictionary in guest_game.sim.effects:
            death_received = death_received or (event.get("entity_id", -1) == id and event.get("unit_type") == "mobile_infantry")
        check(death_received, "Death identity synchronized")
    finish()


func find_mobile(game: Node3D) -> int:
    for id: int in game.sim.units:
        if game.sim.units[id].type == "mobile_infantry":
            return id
    return -1


func finish() -> void:
    if guest_game != null:
        guest_game._disconnect()
        guest_game.set_process(false)
    if server_game != null:
        server_game._disconnect()
        server_game.set_process(false)
    print("MOBILE_INFANTRY_ENET ", {"failures": failures, "scope": "same-process loopback, actual game RPC"})
