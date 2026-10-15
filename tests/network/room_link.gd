extends Node
## Real UDP delay/loss proxy used by room tests; no production fault switches.
var socket := UDPServer.new()
var links := []
var packets := []
var rng := RandomNumberGenerator.new()
var drops := 0
var sent := 0

func _ready() -> void:
    rng.seed = 41016
    assert(socket.listen(24567, "127.0.0.1") == OK)

func enqueue(bytes: PackedByteArray, destination: PacketPeerUDP) -> void:
    if rng.randf() < 0.01:
        drops += 1
        return
    packets.append({"data": bytes, "peer": destination, "at": Time.get_ticks_msec() + rng.randi_range(40, 60)})

func _process(_delta: float) -> void:
    socket.poll()
    while socket.is_connection_available():
        var downstream := socket.take_connection()
        var upstream := PacketPeerUDP.new()
        upstream.connect_to_host("127.0.0.1", 24566)
        links.append([downstream, upstream])
    for link: Array in links:
        for direction in range(2):
            var source: PacketPeerUDP = link[direction]
            while source.get_available_packet_count() > 0:
                enqueue(source.get_packet(), link[1 - direction])
    var now := Time.get_ticks_msec()
    for i in range(packets.size() - 1, -1, -1):
        if packets[i].at <= now:
            packets[i].peer.put_packet(packets[i].data)
            sent += 1
            packets.remove_at(i)

func _exit_tree() -> void:
    socket.stop()
    for link: Array in links:
        link[0].close()
        link[1].close()
