extends RefCounted
const Rules = preload("res://scripts/definitions/gameplay_rules.gd")
## Validates without applying a snapshot; Simulation owns all authoritative state.
var sim


func _init(owner) -> void:
    sim = owner


func validate(state: Dictionary) -> bool:
    sim.last_snapshot_error = ""
    for field in ["version", "map_id", "map_version", "map_checksum", "match", "frame", "units", "buildings", "ores", "money", "winner", "effects", "visible", "explored"]:
        if not state.has(field):
            sim.last_snapshot_error = "Snapshot is missing %s." % field
            return false
    if typeof(state.version) != TYPE_STRING or state.version != sim.VERSION:
        sim.last_snapshot_error = "Snapshot version mismatch."
        return false
    if typeof(state.map_id) != TYPE_STRING or typeof(state.map_version) != TYPE_INT or typeof(state.map_checksum) != TYPE_STRING:
        sim.last_snapshot_error = "Invalid map identity."
        return false
    var candidate = sim.terrain
    if state.map_id != sim.map_id:
        candidate = sim.MapTerrain.new()
        if not candidate.load_map(state.map_id):
            sim.last_snapshot_error = "Unknown or invalid map."
            return false
    if candidate.definition.is_empty() or state.map_version != candidate.definition.version or state.map_checksum != candidate.checksum:
        sim.last_snapshot_error = "Map content mismatch. Both players need identical maps."
        return false
    if typeof(state.match) != TYPE_INT or int(state.match) < 0:
        sim.last_snapshot_error = "Snapshot match id is invalid."
        return false
    if typeof(state.frame) != TYPE_INT or int(state.frame) < 0:
        sim.last_snapshot_error = "Snapshot frame is invalid."
        return false
    if typeof(state.winner) != TYPE_INT or int(state.winner) not in [0, 1, 2, 3]:
        sim.last_snapshot_error = "Snapshot winner is invalid."
        return false
    if not _validate_snapshot_dictionary(state.units, sim.MAX_SNAPSHOT_UNITS, "units", true):
        return false
    if not _validate_snapshot_dictionary(state.buildings, sim.MAX_SNAPSHOT_BUILDINGS, "buildings", false):
        return false
    var occupied_docks := {}
    for u: Dictionary in state.units.values():
        if not u.has("dock"):
            continue
        var d: Dictionary = u.dock
        if not state.buildings.has(d.station):
            sim.last_snapshot_error = "Snapshot dock station is missing."
            return false
        var station: Dictionary = state.buildings[d.station]
        if station.type != "refinery" or station.owner != u.owner or station.remaining > 0 or d.requested > state.frame:
            sim.last_snapshot_error = "Snapshot dock station is invalid."
            return false
        if d.slot >= 0:
            var key := Vector2i(d.station, d.slot)
            if occupied_docks.has(key):
                sim.last_snapshot_error = "Snapshot has duplicate dock reservations."
                return false
            occupied_docks[key] = true
    if not _validate_snapshot_dictionary(state.ores, sim.MAX_SNAPSHOT_ORES, "ores", false):
        return false
    if not sim.MiningSystem.validate(sim, state):
        sim.last_snapshot_error = "Snapshot mining reservation is invalid."
        return false
    if not _validate_money(state.money):
        return false
    if not _validate_effects(state.effects, int(state.frame)):
        return false
    if not _validate_visibility(state.visible, "visible"):
        return false
    if not _validate_visibility(state.explored, "explored"):
        return false
    return true


func _validate_snapshot_dictionary(value: Variant, limit: int, label: String, units_table: bool) -> bool:
    if not (value is Dictionary):
        sim.last_snapshot_error = "Snapshot %s table is not a dictionary." % label
        return false
    var table: Dictionary = value
    if table.size() > limit:
        sim.last_snapshot_error = "Snapshot %s table is too large." % label
        return false
    for raw_id: Variant in table.keys():
        if typeof(raw_id) != TYPE_INT or int(raw_id) <= 0:
            sim.last_snapshot_error = "Snapshot %s id is invalid." % label
            return false
        var entry: Variant = table[raw_id]
        if units_table:
            if not _validate_unit_entry(entry):
                return false
        elif label == "buildings":
            if not _validate_building_entry(entry):
                return false
        else:
            if not _validate_ore_entry(entry):
                return false
    return true


func _validate_unit_entry(value: Variant) -> bool:
    if not (value is Dictionary):
        sim.last_snapshot_error = "Snapshot unit entry is not a dictionary."
        return false
    var unit: Dictionary = value
    for field in ["owner", "type", "pos", "hp", "order", "target", "attack_kind", "attack_id", "ore", "cargo", "cooldown", "work", "path", "repath", "flash", "auto", "stuck"]:
        if not unit.has(field):
            sim.last_snapshot_error = "Snapshot unit is missing %s." % field
            return false
    if typeof(unit.owner) != TYPE_INT or int(unit.owner) not in [1, 2] or typeof(unit.type) != TYPE_STRING or not sim.UNIT_TYPES.has(unit.type):
        sim.last_snapshot_error = "Snapshot unit owner or type is invalid."
        return false
    var kind: String = str(unit.type)
    if not _validate_vector2(unit.pos, sim.WORLD, "unit position") or not _validate_vector2(unit.target, sim.WORLD * 2.0, "unit target"):
        return false
    var max_hp: int = int(sim.UNIT_TYPES[kind].hp)
    if typeof(unit.hp) != TYPE_INT or int(unit.hp) < 0 or int(unit.hp) > max_hp:
        sim.last_snapshot_error = "Snapshot unit hp is invalid."
        return false
    if typeof(unit.order) != TYPE_STRING or unit.order not in ["idle", "move", "attack", "attack_move", "gather"]:
        sim.last_snapshot_error = "Snapshot unit order is invalid."
        return false
    if typeof(unit.attack_kind) != TYPE_STRING or unit.attack_kind not in ["", "unit", "building"]:
        sim.last_snapshot_error = "Snapshot unit attack kind is invalid."
        return false
    if typeof(unit.attack_id) != TYPE_INT or int(unit.attack_id) < -1 or int(unit.attack_id) > 1000000:
        sim.last_snapshot_error = "Snapshot unit attack id is invalid."
        return false
    if typeof(unit.ore) != TYPE_INT or int(unit.ore) < -1 or int(unit.ore) > sim.MAX_SNAPSHOT_ORES:
        sim.last_snapshot_error = "Snapshot unit ore id is invalid."
        return false
    if typeof(unit.cargo) != TYPE_INT or int(unit.cargo) < 0 or int(unit.cargo) > Rules.CAPACITY:
        sim.last_snapshot_error = "Snapshot unit cargo is invalid."
        return false
    if typeof(unit.cooldown) != TYPE_INT or int(unit.cooldown) < 0 or int(unit.cooldown) > int(sim.UNIT_TYPES[kind].cooldown):
        sim.last_snapshot_error = "Snapshot unit cooldown is invalid."
        return false
    if typeof(unit.work) != TYPE_INT or int(unit.work) < 0 or int(unit.work) > Rules.MINING_INTERVAL:
        sim.last_snapshot_error = "Snapshot unit work timer is invalid."
        return false
    if typeof(unit.path) != TYPE_ARRAY or unit.path.size() > 2048:
        sim.last_snapshot_error = "Snapshot unit path is invalid."
        return false
    for point: Variant in unit.path:
        if not _validate_vector2(point, sim.WORLD * 2.0, "unit path point"):
            return false
    if typeof(unit.repath) != TYPE_INT or int(unit.repath) < -100 or int(unit.repath) > 10000:
        sim.last_snapshot_error = "Snapshot unit repath timer is invalid."
        return false
    if typeof(unit.flash) != TYPE_INT or int(unit.flash) < 0 or int(unit.flash) > 10:
        sim.last_snapshot_error = "Snapshot unit flash timer is invalid."
        return false
    if typeof(unit.auto) != TYPE_BOOL:
        sim.last_snapshot_error = "Snapshot unit auto flag is invalid."
        return false
    if typeof(unit.stuck) != TYPE_INT or int(unit.stuck) < 0 or int(unit.stuck) > 10000:
        sim.last_snapshot_error = "Snapshot unit stuck timer is invalid."
        return false
    if not sim.DepotDocking.valid(sim, unit):
        sim.last_snapshot_error = "Snapshot dock intent is invalid."
        return false
    if unit.has("arrival"):
        var arrival: Variant = unit.arrival
        if not arrival is Dictionary or arrival.size() != 4:
            sim.last_snapshot_error = "Snapshot arrival intent is invalid."
            return false
        if not _validate_vector2(arrival.get("anchor"), sim.WORLD, "arrival anchor"):
            return false
        if typeof(arrival.get("region")) != TYPE_INT or arrival.region < 0 or arrival.region >= sim.GRID_CELLS:
            sim.last_snapshot_error = "Snapshot arrival region is invalid."
            return false
        if typeof(arrival.get("waiting")) != TYPE_BOOL or typeof(arrival.get("arrived")) != TYPE_BOOL or (arrival.waiting and arrival.arrived):
            sim.last_snapshot_error = "Snapshot arrival status is invalid."
            return false
    return true


func _validate_building_entry(value: Variant) -> bool:
    if not (value is Dictionary):
        sim.last_snapshot_error = "Snapshot building entry is not a dictionary."
        return false
    var building: Dictionary = value
    for field in ["owner", "type", "pos", "hp", "remaining", "queue", "flash", "rally", "cooldown"]:
        if not building.has(field):
            sim.last_snapshot_error = "Snapshot building is missing %s." % field
            return false
    if typeof(building.owner) != TYPE_INT or int(building.owner) not in [1, 2] or typeof(building.type) != TYPE_STRING or not sim.BUILD_TYPES.has(building.type):
        sim.last_snapshot_error = "Snapshot building owner or type is invalid."
        return false
    var kind: String = str(building.type)
    if not sim.RallySystem.valid(building, sim.WORLD):
        sim.last_snapshot_error = "Invalid building rally state."
        return false
    if not _validate_vector2(building.pos, sim.WORLD, "building position") or not _validate_vector2(building.rally, sim.WORLD * 2.0, "building rally"):
        return false
    if kind == "refinery":
        if not building.get("dock_flash") is Array or building.dock_flash.size() != 2:
            sim.last_snapshot_error = "Snapshot dock lights are invalid."
            return false
        for timer: Variant in building.dock_flash:
            if typeof(timer) != TYPE_INT or timer < 0 or timer > 10:
                sim.last_snapshot_error = "Snapshot dock light timer is invalid."
                return false
    var max_hp: int = int(sim.BUILD_TYPES[kind].hp)
    var max_remaining: int = int(sim.BUILD_TYPES[kind].time)
    if typeof(building.hp) != TYPE_INT or int(building.hp) < 0 or int(building.hp) > max_hp:
        sim.last_snapshot_error = "Snapshot building hp is invalid."
        return false
    if typeof(building.remaining) != TYPE_INT or int(building.remaining) < 0 or int(building.remaining) > max_remaining:
        sim.last_snapshot_error = "Snapshot construction timer is invalid."
        return false
    if typeof(building.queue) != TYPE_ARRAY or building.queue.size() > Rules.QUEUE_LIMIT:
        sim.last_snapshot_error = "Snapshot production queue is invalid."
        return false
    for job: Variant in building.queue:
        if not (job is Dictionary) or not job.has("type") or not job.has("remaining") or typeof(job.type) != TYPE_STRING or not sim.UNIT_TYPES.has(job.type) or typeof(job.remaining) != TYPE_INT:
            sim.last_snapshot_error = "Snapshot production job is invalid."
            return false
        if int(job.remaining) < 0 or int(job.remaining) > int(sim.UNIT_TYPES[job.type].time):
            sim.last_snapshot_error = "Snapshot production timer is invalid."
            return false
    if typeof(building.flash) != TYPE_INT or int(building.flash) < 0 or int(building.flash) > 10:
        sim.last_snapshot_error = "Snapshot building flash timer is invalid."
        return false
    if not sim.BarracksFlight.valid(building, sim.WORLD):
        sim.last_snapshot_error = "Invalid barracks flight state."
        return false
    if sim.BarracksFlight.state(building) == "grounded" and building.pos != sim.snap_building(kind, building.pos):
        sim.last_snapshot_error = "Grounded building footprint is not grid aligned."
        return false
    var max_cooldown := int(sim.BUILD_TYPES.bunker.cooldown)
    if typeof(building.cooldown) != TYPE_INT or int(building.cooldown) < 0 or int(building.cooldown) > max_cooldown:
        sim.last_snapshot_error = "Snapshot building cooldown is invalid."
        return false
    return true


func _validate_ore_entry(value: Variant) -> bool:
    if not (value is Dictionary):
        sim.last_snapshot_error = "Snapshot ore entry is not a dictionary."
        return false
    var ore: Dictionary = value
    if not ore.has("pos") or not ore.has("amount") or not _validate_vector2(ore.pos, sim.WORLD, "ore position") or typeof(ore.amount) != TYPE_INT or int(ore.amount) < 0 or int(ore.amount) > sim.MAX_SNAPSHOT_ORE_AMOUNT:
        sim.last_snapshot_error = "Snapshot ore entry is invalid."
        return false
    return true


func _validate_money(value: Variant) -> bool:
    if not (value is Dictionary) or value.size() != 2 or not value.has(1) or not value.has(2):
        sim.last_snapshot_error = "Snapshot money table is invalid."
        return false
    for owner: Variant in value.keys():
        if typeof(owner) != TYPE_INT or int(owner) not in [1, 2] or typeof(value[owner]) != TYPE_INT or int(value[owner]) < 0 or int(value[owner]) > 1000000000:
            sim.last_snapshot_error = "Snapshot money entry is invalid."
            return false
    return true


func _validate_effects(value: Variant, snapshot_frame: int) -> bool:
    if not (value is Array) or value.size() > sim.MAX_SNAPSHOT_EFFECTS:
        sim.last_snapshot_error = "Snapshot effects are invalid."
        return false
    for effect: Variant in value:
        if not (effect is Dictionary) or not effect.has("kind") or not effect.has("from") or not effect.has("to") or not effect.has("life") or not effect.has("owner") or not effect.has("frame"):
            sim.last_snapshot_error = "Snapshot effect entry is invalid."
            return false
        if typeof(effect.kind) != TYPE_STRING or effect.kind not in ["shot", "death"] or not _validate_vector2(effect.from, sim.WORLD * 2.0, "effect origin") or not _validate_vector2(effect.to, sim.WORLD * 2.0, "effect target"):
            return false
        if typeof(effect.life) != TYPE_INT or int(effect.life) < 0 or int(effect.life) > 60 or typeof(effect.owner) != TYPE_INT or int(effect.owner) not in [1, 2] or typeof(effect.frame) != TYPE_INT or int(effect.frame) < 0 or int(effect.frame) > snapshot_frame:
            sim.last_snapshot_error = "Snapshot effect metadata is invalid."
            return false
        if effect.has("entity_id") or effect.has("unit_type"):
            if effect.kind != "death" or typeof(effect.get("entity_id")) != TYPE_INT or int(effect.entity_id) < 0 or effect.get("unit_type") != "mobile_infantry":
                sim.last_snapshot_error = "Snapshot unit death identity is invalid."
                return false
        if effect.has("impact"):
            var impact: Variant = effect.impact
            if effect.kind != "shot" or not impact is Dictionary:
                sim.last_snapshot_error = "Snapshot impact is invalid."
                return false
            if impact.get("source_type") != "mobile_infantry" or typeof(impact.get("source_id")) != TYPE_INT or int(impact.source_id) < 0 or typeof(impact.get("target_id")) != TYPE_INT or int(impact.target_id) < 0:
                sim.last_snapshot_error = "Snapshot impact identity is invalid."
                return false
            if impact.get("target_kind") not in ["unit", "building"] or typeof(impact.get("target_type")) != TYPE_STRING:
                sim.last_snapshot_error = "Snapshot impact target is invalid."
                return false
            var types: Dictionary = sim.UNIT_TYPES if impact.target_kind == "unit" else sim.BUILD_TYPES
            if not types.has(impact.target_type) or not _validate_vector2(impact.get("target_pos"), sim.WORLD * 2.0, "impact position"):
                return false
    return true


func _validate_visibility(value: Variant, label: String) -> bool:
    if not (value is Dictionary) or value.size() != 2 or not value.has(1) or not value.has(2):
        sim.last_snapshot_error = "Snapshot %s table is invalid." % label
        return false
    for owner: Variant in value.keys():
        if typeof(owner) != TYPE_INT or int(owner) not in [1, 2] or not (value[owner] is PackedByteArray) or value[owner].size() != sim.GRID_CELLS:
            sim.last_snapshot_error = "Snapshot %s buffer is invalid." % label
            return false
    return true


func _validate_vector2(value: Variant, bounds: Vector2, label: String) -> bool:
    if not (value is Vector2):
        sim.last_snapshot_error = "Snapshot %s is not a Vector2." % label
        return false
    var point: Vector2 = value
    if not is_finite(point.x) or not is_finite(point.y) or absf(point.x) > bounds.x or absf(point.y) > bounds.y:
        sim.last_snapshot_error = "Snapshot %s is out of bounds." % label
        return false
    return true
