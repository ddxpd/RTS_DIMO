extends RefCounted

static func definition() -> Dictionary:
    var spawns := [Vector2(640, 640), Vector2(4160, 2560), Vector2(640, 2560), Vector2(4160, 640)]
    var ores := []
    var roads := []
    for spawn: Vector2 in spawns:
        roads.append({"points": [spawn, Vector2(2400, 1600)], "width": 96.0})
        var inward := Vector2(1 if spawn.x < 2400 else -1, 1 if spawn.y < 1600 else -1)
        for offset: Vector2 in [Vector2(320, 288), Vector2(544, 288), Vector2(320, 512)]:
            ores.append({"pos": spawn + (offset + Vector2(16, 16)) * inward, "amount": 18000})
    return {"id": "frontier_four", "version": 1, "seed": 41016, "name": "边境四方", "title": "边境四方",
        "description": "四方对称矿区 · 2–4 人混战 / 2v2", "size": Vector2(4800, 3200),
        "spawns": spawns, "ores": ores, "modules": [], "obstacles": [], "roads": roads,
        "preview": "res://assets/maps/desert_quarry_preview.png", "test_only": false}
