extends RefCounted
## Authoritative relocation rules. Rendering never changes these fields.
const STATES := ["grounded", "taking_off", "airborne", "landing"]
const DURATION := 80
const SPEED := 60.0


static func initialize(b: Dictionary, height: float) -> void:
    b.flight = {"state": "grounded", "ticks": 0, "height": height,
        "ground": height, "cruise": height, "target": b.pos,
        "moving": false, "deploy": false, "error": ""}


static func state(b: Dictionary) -> String:
    return str(b.get("flight", {}).get("state", "grounded"))


static func blocks_ground(b: Dictionary) -> bool:
    return state(b) != "airborne"


static func is_airborne(b: Dictionary) -> bool:
    if not b.has("flight"):
        return b.get("target_layer", "ground") == "air"
    var f: Dictionary = b.flight
    return f.state == "airborne" or (f.state == "taking_off" and f.ticks > 16) or (f.state == "landing" and f.ticks < 64)


static func cruise_height(sim) -> float:
    var highest := 0.0
    for height in sim.terrain.heights:
        highest = maxf(highest, float(height))
    if sim.terrain.sample_surface != null:
        for height in sim.terrain.sample_surface.heights:
            highest = maxf(highest, float(height))
    return highest + 108.0 + 36.0


static func rect_error(sim, owner: int, rect: Rect2, ignore_id: int, visible: bool) -> String:
    if not Rect2(Vector2.ZERO, sim.WORLD).encloses(rect):
        return "Outside map"
    var ground_error: String = sim.terrain.build_error(rect)
    if not ground_error.is_empty():
        return ground_error
    if visible:
        for y in range(int(floor(rect.position.y / sim.CELL)), int(ceil(rect.end.y / sim.CELL))):
            for x in range(int(floor(rect.position.x / sim.CELL)), int(ceil(rect.end.x / sim.CELL))):
                if not sim.can_see(owner, Vector2(x * sim.CELL + 16, y * sim.CELL + 16)):
                    return "Deploy in currently visible terrain"
    for id: int in sim.buildings:
        var other: Dictionary = sim.buildings[id]
        if id != ignore_id and blocks_ground(other) and sim.footprint(other, 16).intersects(rect):
            return "Blocked by a building or landing reservation"
    for rock: Rect2 in sim.obstacles:
        if rock.grow(16).intersects(rect):
            return "Blocked by terrain"
    for ore: Dictionary in sim.ores.values():
        if rect.grow(32).has_point(ore.pos):
            return "Blocked by ore"
    for unit: Dictionary in sim.units.values():
        if not is_airborne(unit) and rect.grow(float(sim.UNIT_TYPES[unit.type].radius)).has_point(unit.pos):
            return "Blocked by a unit"
    return ""


static func placement(sim, owner: int, id: int, position: Vector2) -> Dictionary:
    var pos: Vector2 = sim.snap_build(position)
    var rect := Rect2(pos - Vector2(64, 48), Vector2(128, 96))
    var cells: Array[Dictionary] = []
    for y in range(3):
        for x in range(4):
            var cell := Rect2(rect.position + Vector2(x, y) * 32, Vector2(32, 32))
            var error := rect_error(sim, owner, cell, id, true)
            cells.append({"rect": cell, "error": error})
    var error := rect_error(sim, owner, rect.grow(16), id, true)
    return {"pos": pos, "rect": rect, "cells": cells, "error": error}


static func command(sim, owner: int, c: Dictionary) -> String:
    var id := int(c.get("building", -1))
    if not sim.buildings.has(id):
        return "Select a completed friendly barracks"
    var b: Dictionary = sim.buildings[id]
    if b.owner != owner or b.type != "barracks" or b.remaining > 0 or b.hp <= 0:
        return "Select a completed friendly barracks"
    var f: Dictionary = b.flight
    if c.action == "barracks_takeoff":
        if f.state != "grounded":
            return "Barracks is already lifting or airborne"
        if not b.queue.is_empty():
            return "Finish or cancel the training queue before takeoff"
        f.state = "taking_off"
        f.ticks = 0
        f.ground = sim.terrain.height_at(b.pos)
        f.cruise = cruise_height(sim)
        f.error = ""
        return ""
    if f.state != "airborne":
        return "Wait until takeoff or landing finishes"
    if c.action == "barracks_stop":
        f.moving = false
        f.deploy = false
        f.target = b.pos
        f.error = ""
        return ""
    if not c.get("pos") is Vector2 or not (c.pos as Vector2).is_finite():
        return "Invalid destination"
    var pos: Vector2 = c.pos
    if not Rect2(Vector2(64, 48), sim.WORLD - Vector2(128, 96)).has_point(pos):
        return "Outside map"
    if c.action == "barracks_deploy":
        var site := placement(sim, owner, id, pos)
        if not site.error.is_empty():
            return site.error
        pos = site.pos
    f.target = pos
    f.moving = true
    f.deploy = c.action == "barracks_deploy"
    f.error = ""
    return ""


static func advance(sim, id: int, b: Dictionary) -> void:
    var f: Dictionary = b.flight
    if f.state == "grounded":
        return
    if f.state == "airborne":
        if not f.moving:
            return
        b.pos = (b.pos as Vector2).move_toward(f.target, SPEED / sim.TICK)
        if not (b.pos as Vector2).is_equal_approx(f.target):
            return
        f.moving = false
        if f.deploy:
            var site := placement(sim, b.owner, id, b.pos)
            f.deploy = false
            if not site.error.is_empty():
                f.error = "Deployment canceled: " + site.error
                return
            f.state = "landing"
            f.ticks = 0
            f.ground = sim.terrain.height_at(b.pos)
            sim.rebuild_navigation()
        return
    f.ticks = mini(int(f.ticks) + 1, DURATION)
    var seconds: float = float(f.ticks) / sim.TICK
    var t: float = seconds if f.state == "taking_off" else 4.0 - seconds
    var rise := smoothstep(0.8, 3.2, t)
    f.height = lerpf(float(f.ground), float(f.cruise), rise)
    if f.state == "landing":
        # Reservation prevents normal entry; recheck to handle destruction/spawn/other forced changes.
        var error := rect_error(sim, b.owner, sim.footprint(b, 16), id, false)
        if not error.is_empty():
            f.state = "taking_off"
            f.ticks = DURATION - int(f.ticks)
            f.error = "Landing aborted: " + error
            return
    if f.ticks == DURATION:
        f.state = "airborne" if f.state == "taking_off" else "grounded"
        f.ticks = 0
        f.height = f.cruise if f.state == "airborne" else f.ground
        sim.rebuild_navigation()


static func valid(b: Dictionary, world: Vector2) -> bool:
    if b.type != "barracks":
        return not b.has("flight")
    if not b.get("flight") is Dictionary:
        return false
    var f: Dictionary = b.flight
    for key in ["state", "ticks", "height", "ground", "cruise", "target", "moving", "deploy", "error"]:
        if not f.has(key):
            return false
    if f.state not in STATES or typeof(f.ticks) != TYPE_INT or f.ticks < 0 or f.ticks >= DURATION:
        return false
    for key in ["height", "ground", "cruise"]:
        if not (f[key] is float or f[key] is int) or not is_finite(float(f[key])) or absf(float(f[key])) > 4096:
            return false
    if not f.target is Vector2 or not f.target.is_finite() or not Rect2(Vector2.ZERO, world).has_point(f.target):
        return false
    if not f.moving is bool or not f.deploy is bool or not f.error is String or f.error.length() > 256:
        return false
    if f.state != "grounded" and (b.remaining > 0 or not b.queue.is_empty()):
        return false
    if f.state != "airborne" and (f.moving or f.deploy):
        return false
    if f.state in ["grounded", "airborne"] and f.ticks != 0:
        return false
    if f.cruise < f.ground or f.height < f.ground - 0.01 or f.height > f.cruise + 0.01:
        return false
    var expected: float = f.ground
    if f.state == "airborne":
        expected = f.cruise
    elif f.state in ["taking_off", "landing"]:
        var seconds := float(f.ticks) / 20.0
        var t := seconds if f.state == "taking_off" else 4.0 - seconds
        expected = lerpf(f.ground, f.cruise, smoothstep(0.8, 3.2, t))
    if absf(float(f.height) - expected) > 0.01:
        return false
    return not f.deploy or f.moving
