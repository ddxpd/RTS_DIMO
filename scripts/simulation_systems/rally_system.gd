extends RefCounted
## Host-authoritative production destinations; existing units are never retasked.

static func producer(building: Dictionary) -> bool:
    return building.get("type", "") in ["barracks", "refinery"] and building.get("hp", 0) > 0


static func command(sim, owner: int, order: Dictionary) -> String:
    if typeof(order.get("building")) != TYPE_INT:
        return "Invalid building"
    var building: Dictionary = sim.buildings.get(order.building, {})
    if not producer(building) or building.owner != owner:
        return "Select a friendly production building"
    if sim.BarracksFlight.state(building) != "grounded":
        return "Land before setting a rally point"
    var mode: Variant = order.get("mode", "ground")
    if typeof(mode) != TYPE_STRING or mode not in ["none", "ground", "ore"]:
        return "Invalid rally mode"
    var point := Vector2.ZERO
    var ore_id := -1
    if mode != "none":
        if not order.get("pos") is Vector2 or not order.pos.is_finite() or not Rect2(Vector2.ZERO, sim.WORLD).has_point(order.pos):
            return "Invalid rally point"
        point = sim.snap_build(order.pos).clamp(Vector2.ZERO, sim.WORLD - Vector2.ONE)
    if mode == "ore":
        if building.type != "refinery" or typeof(order.get("ore")) != TYPE_INT:
            return "Invalid mining rally"
        ore_id = order.ore
        var ore: Dictionary = sim.ores.get(ore_id, {})
        if ore.is_empty() or ore.amount <= 0 or not sim.can_see(owner, ore.pos):
            return "Select a visible crystal deposit"
        point = ore.pos
    building.rally = point
    building.rally_mode = mode
    building.rally_ore = ore_id
    return ""


static func valid(building: Dictionary, world: Vector2) -> bool:
    if not building.get("rally") is Vector2 or not building.rally.is_finite():
        return false
    if typeof(building.get("rally_mode")) != TYPE_STRING or building.rally_mode not in ["none", "ground", "ore"]:
        return false
    if typeof(building.get("rally_ore")) != TYPE_INT:
        return false
    if building.rally_mode == "none":
        return building.rally == Vector2.ZERO and building.rally_ore == -1
    if building.type not in ["barracks", "refinery"] or not Rect2(Vector2.ZERO, world).has_point(building.rally):
        return false
    # A depleted/deleted ore target is legal: production falls back to auto-mine.
    return (building.type == "refinery" and building.rally_ore >= 0) if building.rally_mode == "ore" else building.rally_ore == -1


static func dispatch(sim, building: Dictionary, unit_id: int) -> void:
    var unit: Dictionary = sim.units[unit_id]
    if building.rally_mode == "ground":
        sim.command(int(building.owner), {"action": "move", "units": [unit_id], "pos": building.rally})
    elif unit.type == "harvester":
        var ore: Dictionary = sim.ores.get(building.rally_ore, {})
        if building.rally_mode == "ore" and not ore.is_empty() and ore.amount > 0 and sim.can_see(int(building.owner), ore.pos):
            sim.command(int(building.owner), {"action": "gather", "units": [unit_id], "target": building.rally_ore})
        else:
            sim._auto_mine(unit)
