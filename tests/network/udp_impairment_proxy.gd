extends SceneTree
## Packet-level UDP impairment: each client gets a separate upstream socket.
var server := UDPServer.new()
var links: Array = []
var queue: Array = []
var rng := RandomNumberGenerator.new()
var port := 24561
var target_port := 24560
var delay_ms := 0.0
var jitter_ms := 0.0
var loss := 0.0
var upload := 0.0
var download := 0.0
var next_send := [0.0, 0.0]
var profile := "baseline"
var started := 0
var output := ""
var stop_file := ""
var outage_at := -1.0
var lifetime := 360.0
var counts := {"received_packets": [0, 0], "received_bytes": [0, 0], "sent_packets": [0, 0], "sent_bytes": [0, 0], "random_drops": [0, 0], "queue_drops": [0, 0], "outage_drops": [0, 0], "max_queue_ms": 0.0, "max_queued_packets": 0}

func _initialize() -> void:
    Engine.max_fps = 500
    for arg in OS.get_cmdline_user_args():
        var pair := arg.split("=", true, 1)
        if pair.size() != 2:
            continue
        match pair[0]:
            "--port": port = int(pair[1])
            "--target-port": target_port = int(pair[1])
            "--profile": profile = pair[1]
            "--seed": rng.seed = int(pair[1])
            "--output": output = pair[1]
            "--stop-file": stop_file = pair[1]
            "--lifetime": lifetime = float(pair[1])
    match profile:
        "rtt50": delay_ms = 25
        "rtt100": delay_ms = 50
        "rtt200": delay_ms = 100
        "normal", "limited", "outage":
            delay_ms = 50
            jitter_ms = 10
            loss = 0.01
        "poor":
            delay_ms = 100
            jitter_ms = 20
            loss = 0.03
    if profile == "limited":
        upload = 256000.0 / 8
        download = 1000000.0 / 8
    if profile == "outage":
        outage_at = 100.0
    assert(server.listen(port, "127.0.0.1") == OK)
    started = Time.get_ticks_msec()
    counts["started_unix_ms"] = Time.get_unix_time_from_system() * 1000
    counts["outage_end_unix_ms"] = counts.started_unix_ms + (outage_at + 3) * 1000 if outage_at >= 0 else -1
    print("UDP_PROXY_READY port=", port, " profile=", profile, " seed=", rng.seed)

func enqueue(packet: PackedByteArray, destination: PacketPeerUDP, direction: int, now: float) -> void:
    counts.received_packets[direction] += 1
    counts.received_bytes[direction] += packet.size()
    var elapsed := (now - started) / 1000
    if outage_at >= 0 and elapsed >= outage_at and elapsed < outage_at + 3:
        counts.outage_drops[direction] += 1
        return
    if rng.randf() < loss:
        counts.random_drops[direction] += 1
        return
    var due := now + delay_ms + rng.randf_range(-jitter_ms, jitter_ms)
    var rate := upload if direction == 0 else download
    if rate > 0:
        due = maxf(due, next_send[direction]) + packet.size() * 1000 / rate
        if due - now > 500:
            counts.queue_drops[direction] += 1
            return
        next_send[direction] = due
    if queue.size() >= 16384:
        counts.queue_drops[direction] += 1
        return
    counts.max_queue_ms = maxf(counts.max_queue_ms, due - now)
    queue.append({"due": due, "packet": packet, "destination": destination, "direction": direction})
    counts.max_queued_packets = maxi(counts.max_queued_packets, queue.size())

func _process(_delta: float) -> bool:
    var now := float(Time.get_ticks_msec())
    server.poll()
    while server.is_connection_available():
        var incoming := server.take_connection()
        var upstream := PacketPeerUDP.new()
        assert(upstream.bind(0, "127.0.0.1", 2097152) == OK)
        assert(upstream.connect_to_host("127.0.0.1", target_port) == OK)
        links.append([incoming, upstream])
    for link: Array in links:
        for direction in range(2):
            var source: PacketPeerUDP = link[direction]
            var destination: PacketPeerUDP = link[1 - direction]
            while source.get_available_packet_count() > 0:
                enqueue(source.get_packet(), destination, direction, now)
    # Sort by delivery time, so jitter really can reorder datagrams.
    queue.sort_custom(func(a, b): return a.due < b.due)
    var delivered := 0
    for item: Dictionary in queue:
        if item.due > now:
            break
        var elapsed := (now - started) / 1000
        if outage_at >= 0 and elapsed >= outage_at and elapsed < outage_at + 3:
            counts.outage_drops[item.direction] += 1
        elif item.destination.put_packet(item.packet) == OK:
            counts.sent_packets[item.direction] += 1
            counts.sent_bytes[item.direction] += item.packet.size()
        delivered += 1
    if delivered > 0:
        queue = queue.slice(delivered)
    if (not stop_file.is_empty() and FileAccess.file_exists(stop_file)) or now - started > lifetime * 1000:
        counts["profile"] = profile
        counts["duration_ms"] = now - started
        counts["links"] = links.size()
        var file := FileAccess.open(output, FileAccess.WRITE)
        if file != null:
            file.store_string(JSON.stringify(counts, "  "))
        server.stop()
        for link: Array in links:
            link[0].close()
            link[1].close()
        quit()
    return false
