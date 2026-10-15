extends SceneTree
## Read-only bridge. Never changes game resources or simulation constants.
const Sim = preload("res://scripts/simulation.gd")
const Flight = preload("res://scripts/barracks_flight.gd")
const Rules = preload("res://scripts/definitions/gameplay_rules.gd")


func typed(value: Variant) -> Dictionary:
    if value is Vector2:
        return {"type": "vector2", "value": [value.x, value.y]}
    if value is int:
        return {"type": "integer", "value": value}
    if value is float:
        return {"type": "number", "value": value}
    if value is bool:
        return {"type": "boolean", "value": value}
    return {"type": "unknown", "value": value}


func definitions(table: Dictionary) -> Dictionary:
    var result := {}
    for id: String in table:
        result[id] = {}
        for key: String in table[id]:
            result[id][key] = typed(table[id][key])
    return result


func _initialize() -> void:
    var source_paths: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tools/balance_designer/sources.json"))
    var sources := {}
    var active_units := {}
    for kind: String in Sim.ACTIVE_UNIT_TYPES:
        active_units[kind] = Sim.UNIT_TYPES[kind]
    for path: String in source_paths:
        sources[path] = {"sha256": FileAccess.get_sha256("res://" + path),
            "text": FileAccess.get_file_as_string("res://" + path)}
    var data := {"schema": 1, "protocol": Sim.VERSION, "tick": Sim.TICK, "gridCell": Sim.CELL,
        "exportedAt": Time.get_datetime_string_from_system(true) + "Z",
        "units": definitions(active_units), "buildings": definitions(Sim.BUILD_TYPES),
        "eyes": Sim.EYE_HEIGHTS, "targets": Sim.WEAPON_TARGETS,
        "dockPads": {"refinery": Sim.EntityCatalog.REFINERY_DOCK_RECTS.map(func(rect: Rect2) -> Array: return [rect.size.x, rect.size.y])},
        "internalDockPads": ["refinery"],
        "dockGeometry": {"refinery": {
            "berths": range(Sim.EntityCatalog.REFINERY_DOCK_RECTS.size()).map(func(slot: int) -> Vector2: return Sim.EntityCatalog.dock_point(slot, false)).map(func(point: Vector2) -> Array: return [point.x, point.y]),
            "entrances": range(Sim.EntityCatalog.REFINERY_DOCK_RECTS.size()).map(func(slot: int) -> Vector2: return Sim.EntityCatalog.dock_point(slot, true)).map(func(point: Vector2) -> Array: return [point.x, point.y]),
            "vehicleDiameterCells": Sim.UNIT_TYPES.harvester.radius * 2 / Sim.CELL,
            "clearance": Sim.EntityCatalog.BODY_GAP}},
        "flight": {"duration": Flight.DURATION, "speed": Flight.SPEED, "turn": rad_to_deg(Flight.TURN_SPEED)},
        "shared": {"capacity": typed(Rules.CAPACITY), "mining_interval": typed(Rules.MINING_INTERVAL), "mining_amount": typed(Rules.MINING_AMOUNT), "mining_reach": typed(Rules.MINING_REACH), "build_reach": typed(Rules.BUILD_REACH), "queue_limit": typed(Rules.QUEUE_LIMIT), "dock_retry": typed(Rules.DOCK_RETRY), "dock_offset": typed(Rules.DOCK_OFFSET), "dock_depth": typed(Rules.DOCK_DEPTH), "dock_entrance": typed(Rules.DOCK_ENTRANCE), "vision": typed(Rules.VISION)},
        "catalog": {"names": Sim.EntityCatalog.NAMES, "descriptions": Sim.EntityCatalog.DESCRIPTIONS, "producers": Sim.EntityCatalog.PRODUCERS},
        "sources": sources}
    for path: String in source_paths:
        if FileAccess.get_sha256("res://" + path) != sources[path].sha256:
            push_error("Game source changed during export: " + path)
            quit(1)
            return
    var folder := "res://.local/balance_designer"
    DirAccess.make_dir_recursive_absolute(folder)
    var file := FileAccess.open(folder + "/raw.pending.json", FileAccess.WRITE)
    if file == null:
        push_error("Cannot write balance export")
        quit(1)
        return
    file.store_string(JSON.stringify(data, "  ") + "\n")
    file.close()
    if DirAccess.rename_absolute(folder + "/raw.pending.json", folder + "/raw.json") != OK:
        push_error("Cannot install balance export")
        quit(1)
        return
    print("BALANCE_EXPORT PASS units=", data.units.size(), " buildings=", data.buildings.size())
    quit()
