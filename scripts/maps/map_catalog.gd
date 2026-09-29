extends RefCounted

const DESERT = preload("res://assets/maps/desert_quarry.tres")
const IDS := ["desert_quarry", "prototype"]

static func definition(id: String) -> Dictionary:
    if id == "desert_quarry":
        return DESERT.data.duplicate(true)
    if id != "prototype":
        return {}
    return {
        "id": "prototype", "version": 1, "seed": 0,
        "title": "原型地图 / Prototype", "description": "经典平面测试地图", "size": Vector2(4800, 3200),
        "spawns": [Vector2(384, 384), Vector2(4416, 2816)], "modules": [], "roads": [],
        "obstacles": [Rect2(2112, 192, 384, 576), Rect2(2208, 2016, 384, 672), Rect2(2976, 1248, 288, 288), Rect2(1344, 1344, 288, 288)],
        "ores": [
            {"pos": Vector2(704, 704), "amount": 4000}, {"pos": Vector2(4096, 2496), "amount": 4000},
            {"pos": Vector2(2400, 1600), "amount": 6000},
            {"pos": Vector2(704, 1600), "amount": 5000}, {"pos": Vector2(4096, 1600), "amount": 5000},
            {"pos": Vector2(1600, 500), "amount": 6000}, {"pos": Vector2(3200, 2700), "amount": 6000},
            {"pos": Vector2(3800, 700), "amount": 7000}, {"pos": Vector2(1000, 2500), "amount": 7000}
        ]
    }
