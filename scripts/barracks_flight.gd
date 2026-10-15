extends RefCounted
## Authoritative relocation rules. Rendering never changes these fields.
const STATES := ["grounded", "taking_off", "airborne", "landing"]
const DURATION := 80
const FLYING_TYPES := ["base", "barracks"]
const SPEED := 60.0
const TURN_SPEED := PI / 2.0
const RELATIVE_HEIGHT := 144.0
const CLIMB_SPEED := 96.0
const DESCENT_SPEED := 64.0
const LOOKAHEAD_SECONDS := 1.0
const TERRAIN_CLEARANCE := 4.0
# Vector2 positions are float32; final diagonal steps can shift the bearing
# slightly even while following the same straight route.
const HEADING_EPSILON := 0.001
const AirVolumes = preload("res://scripts/building_air_volumes.gd")


static func duration(b: Dictionary) -> int:
    return 120 if b.type == "base" else DURATION


static func body_height(b: Dictionary) -> float:
    return AirVolumes.HEIGHTS.get(b.type, 104.0)


static func initialize(b: Dictionary, height: float) -> void:
    b.flight = {"state": "grounded", "ticks": 0, "height": height,
        "ground": height, "cruise": height, "target": b.pos,
        "moving": false, "deploy": false, "heading": 0.0, "error": ""}


static func state(b: Dictionary) -> String:
    return str(b.get("flight", {}).get("state", "grounded"))


static func blocks_ground(b: Dictionary) -> bool:
    return state(b) != "airborne"


static func is_airborne(b: Dictionary) -> bool:
    if not b.has("flight"):
        return b.get("target_layer", "ground") == "air"
    var f: Dictionary = b.flight
    var threshold := int(duration(b) * 0.2)
    return f.state == "airborne" or (f.state == "taking_off" and f.ticks > threshold) or (f.state == "landing" and f.ticks < duration(b) - threshold)


static func radius(b: Dictionary) -> float:
    return preload("res://scripts/definitions/entity_catalog.gd").BUILD_TYPES[b.type].size.length() * 0.5


static func cruise_height(sim, b: Dictionary, position: Vector2) -> float:
    return sim.terrain.flight_ground(position, position, radius(b)) + RELATIVE_HEIGHT


static func takeoff_height(sim, id: int, b: Dictionary, position: Vector2 = Vector2.INF) -> float:
    if position == Vector2.INF:
        position = b.pos
    # Ground footprints already exclude overlapping aligned launch/landing sites.
    # A neighboring tower no longer raises the entire platform's flight altitude;
    # turning clearance is checked against the actual rotated solids.
    return cruise_height(sim, b, position)


static func target_height(terrain, b: Dictionary) -> float:
    var finish: Vector2 = b.pos
    if b.flight.moving:
        finish = (b.pos as Vector2).move_toward(b.flight.target, SPEED * LOOKAHEAD_SECONDS)
    return terrain.flight_ground(b.pos, finish, radius(b)) + RELATIVE_HEIGHT


static func refresh_cruise(sim, b: Dictionary) -> void:
    b.flight.ground = sim.terrain.flight_ground(b.pos, b.pos, radius(b))
    b.flight.cruise = target_height(sim.terrain, b)


static func follow_height(sim, id: int, b: Dictionary) -> void:
    refresh_cruise(sim, b)
    var f: Dictionary = b.flight
    var safe_height: float = f.cruise
    if f.deploy and (b.pos as Vector2).distance_to(f.target) <= radius(b) + SPEED * LOOKAHEAD_SECONDS:
        # Reach the destination terrain's hover altitude before descent.
        # Building clearance is handled by the compound solids below.
        safe_height = maxf(safe_height, takeoff_height(sim, id, b, f.target))
    var speed := CLIMB_SPEED if f.height < safe_height else DESCENT_SPEED
    var next := move_toward(float(f.height), safe_height, speed / sim.TICK)
    if air_path_clear(sim, id, b.pos, b.pos, f.height, next):
        f.height = next
        if f.error in ["Vertical route occupied; holding altitude", "Rising for terrain clearance"]:
            f.error = ""
    else:
        f.error = "Vertical route occupied; holding altitude"


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
        if id != ignore_id and blocks_ground(other):
            for reserved: Rect2 in sim.placement_rects(other.type, other.pos):
                if reserved.intersects(rect):
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
    var kind: String = sim.buildings[id].type if sim.buildings.has(id) else "barracks"
    var pos: Vector2 = sim.snap_building(kind, position)
    var size: Vector2 = sim.BUILD_TYPES[kind].size
    var rect := Rect2(pos - size * 0.5, size)
    var cells: Array[Dictionary] = []
    for y in range(int(size.y / sim.CELL)):
        for x in range(int(size.x / sim.CELL)):
            var cell := Rect2(rect.position + Vector2(x, y) * sim.CELL, Vector2.ONE * sim.CELL)
            var error := rect_error(sim, owner, cell, id, true)
            cells.append({"rect": cell, "error": error})
    var error := rect_error(sim, owner, rect, id, true)
    return {"pos": pos, "rect": rect, "cells": cells, "error": error}


static func command(sim, owner: int, c: Dictionary) -> String:
    var id := int(c.get("building", -1))
    if not sim.buildings.has(id):
        return "Select a completed friendly flying building"
    var b: Dictionary = sim.buildings[id]
    if b.owner != owner or b.type not in FLYING_TYPES or b.remaining > 0 or b.hp <= 0:
        return "Select a completed friendly flying building"
    var f: Dictionary = b.flight
    if c.action in ["barracks_takeoff", "building_takeoff"]:
        if f.state != "grounded":
            return "Building is already lifting or airborne"
        if not b.queue.is_empty():
            return "Finish or cancel the training queue before takeoff"
        var ground: float = sim.terrain.height_at(b.pos)
        var cruise := takeoff_height(sim, id, b)
        # Validate the whole compound body's lift before changing state.
        # A rejected command stays grounded and usable.
        if not air_path_clear(sim, id, b.pos, b.pos, ground, cruise, true) or not air_clear(sim, id, b.pos, cruise):
            f.error = "升空通道被占用，请移开上方或附近的飞行建筑后重试"
            return f.error
        f.state = "taking_off"
        f.ticks = 0
        f.ground = ground
        f.cruise = cruise
        f.error = ""
        return ""
    if f.state != "airborne":
        return "Wait until takeoff or landing finishes"
    if c.action in ["barracks_stop", "building_stop"]:
        f.moving = false
        f.deploy = false
        f.target = b.pos
        f.error = ""
        refresh_cruise(sim, b)
        return ""
    if not c.get("pos") is Vector2 or not (c.pos as Vector2).is_finite():
        return "Invalid destination"
    var pos: Vector2 = c.pos
    var clearance: float = sim.BUILD_TYPES[b.type].size.length() * 0.5
    if not Rect2(Vector2.ONE * clearance, sim.WORLD - Vector2.ONE * clearance * 2).has_point(pos):
        return "Outside map"
    if c.action in ["barracks_deploy", "building_deploy"]:
        var site := placement(sim, owner, id, pos)
        if not site.error.is_empty():
            return site.error
        pos = site.pos
    var arrival_height := cruise_height(sim, b, pos)
    if c.action in ["barracks_deploy", "building_deploy"]:
        arrival_height = takeoff_height(sim, id, b, pos)
    if not air_clear(sim, id, pos, maxf(f.height, arrival_height)):
        return "Destination blocked by an airborne body"
    f.target = pos
    f.moving = true
    f.deploy = c.action in ["barracks_deploy", "building_deploy"]
    f.error = ""
    refresh_cruise(sim, b)
    return ""


static func travel_heading(b: Dictionary) -> float:
    var direction: Vector2 = b.flight.target - b.pos
    return heading_for_direction(b, direction)


static func heading_for_direction(b: Dictionary, direction: Vector2) -> float:
    # Gaia's long hull lies along X: always lead with its +X narrow end.
    # Barracks retain their -Z front door as the forward axis.
    if b.type == "base":
        return wrapf(atan2(-direction.y, direction.x), -PI, PI)
    return atan2(-direction.x, -direction.y)


static func is_thrusting(b: Dictionary) -> bool:
    var f: Dictionary = b.get("flight", {})
    if f.get("state") != "airborne" or not f.get("moving", false):
        return false
    if not b.has("pos") or (b.pos as Vector2).is_equal_approx(f.target):
        return false
    if not str(f.get("error", "")).is_empty():
        return false
    return absf(angle_difference(float(f.heading), travel_heading(b))) <= HEADING_EPSILON


static func turn_toward(f: Dictionary, target: float, tick_rate: float) -> bool:
    var difference := angle_difference(float(f.heading), target)
    if absf(difference) <= HEADING_EPSILON:
        f.heading = wrapf(target, -PI, PI)
        return true
    f.heading = wrapf(float(f.heading) + clampf(difference, -TURN_SPEED / tick_rate, TURN_SPEED / tick_rate), -PI, PI)
    # Never translate in a tick that also rotates the building.
    return false


static func turn_clear(sim, id: int, target: float) -> bool:
    var b: Dictionary = sim.buildings[id]
    var difference := angle_difference(float(b.flight.heading), target)
    var steps := maxi(1, ceili(absf(difference) / deg_to_rad(1.0)))
    for step in range(steps + 1):
        var heading := float(b.flight.heading) + difference * float(step) / steps
        if not air_clear(sim, id, b.pos, b.flight.height, false, false, heading):
            return false
    return true


static func advance(sim, id: int, b: Dictionary) -> void:
    var f: Dictionary = b.flight
    if f.state == "grounded":
        return
    if f.state == "airborne":
        var start_height: float = f.height
        follow_height(sim, id, b)
        if not f.moving:
            return
        if not (b.pos as Vector2).is_equal_approx(f.target):
            var direction: Vector2 = (f.target - b.pos).normalized()
            var next: Vector2 = b.pos
            var direct: Vector2 = (b.pos as Vector2).move_toward(f.target, SPEED / sim.TICK)
            if minf(start_height, f.height) < sim.terrain.flight_ground(b.pos, direct, radius(b)) + TERRAIN_CLEARANCE:
                f.error = "Rising for terrain clearance"
                return
            for angle: float in [0.0, PI / 6, -PI / 6, PI / 3, -PI / 3, PI / 2, -PI / 2]:
                var steering := direction.rotated(angle)
                var step: float = minf(SPEED / sim.TICK, (b.pos as Vector2).distance_to(f.target))
                var candidate: Vector2 = b.pos + steering * step
                var lookahead: Vector2 = b.pos + steering * minf(SPEED * 0.8, (b.pos as Vector2).distance_to(f.target))
                var heading := heading_for_direction(b, steering)
                if air_clear(sim, id, lookahead, f.height, false, false, heading) and turn_clear(sim, id, heading) and air_path_clear(sim, id, b.pos, candidate, start_height, f.height, false, heading):
                    next = candidate
                    break
            if next == b.pos:
                f.error = "Air route occupied; waiting for clearance"
                return
            var steering: Vector2 = next - b.pos
            if not turn_toward(f, heading_for_direction(b, steering), sim.TICK):
                return
            f.error = ""
            b.pos = next
            if (b.pos as Vector2).is_equal_approx(f.target) and not f.deploy:
                f.moving = false
            refresh_cruise(sim, b)
            return
        if f.deploy:
            if not turn_clear(sim, id, 0.0):
                f.error = "Deployment turn occupied; waiting for clearance"
                return
            if not turn_toward(f, 0.0, sim.TICK):
                return
            var site := placement(sim, b.owner, id, b.pos)
            f.moving = false
            f.deploy = false
            if not site.error.is_empty():
                f.error = "Deployment canceled: " + site.error
                return
            f.state = "landing"
            f.ticks = 0
            f.ground = sim.terrain.height_at(b.pos)
            # Freeze the actual start altitude, not a possibly unreached target.
            f.cruise = f.height
            sim.rebuild_navigation()
        else:
            f.moving = false
        return
    var previous_ticks: int = f.ticks
    var previous_height: float = f.height
    f.ticks = mini(int(f.ticks) + 1, duration(b))
    var phase: float = float(f.ticks) / duration(b) * 4.0
    var t: float = phase if f.state == "taking_off" else 4.0 - phase
    var rise := smoothstep(0.8, 3.2, t)
    f.height = lerpf(float(f.ground), float(f.cruise), rise)
    if not air_path_clear(sim, id, b.pos, b.pos, previous_height, f.height):
        f.ticks = previous_ticks
        f.height = previous_height
        f.error = "Lift column occupied; waiting for clearance"
        return
    if f.error == "Lift column occupied; waiting for clearance":
        f.error = ""
    if f.state == "landing":
        # Reservation prevents normal entry; recheck to handle destruction/spawn/other forced changes.
        var error := rect_error(sim, b.owner, sim.footprint(b), id, false)
        if not error.is_empty():
            f.state = "taking_off"
            f.ticks = duration(b) - int(f.ticks)
            f.error = "Landing aborted: " + error
            return
    if f.ticks == duration(b):
        f.state = "airborne" if f.state == "taking_off" else "grounded"
        f.ticks = 0
        f.height = f.cruise if f.state == "airborne" else f.ground
        if f.state == "airborne":
            refresh_cruise(sim, b)
        sim.rebuild_navigation()


static func valid(b: Dictionary, world: Vector2, terrain = null) -> bool:
    if b.type not in FLYING_TYPES:
        return not b.has("flight")
    if not b.get("flight") is Dictionary:
        return false
    var f: Dictionary = b.flight
    for key in ["state", "ticks", "height", "ground", "cruise", "target", "moving", "deploy", "heading", "error"]:
        if not f.has(key):
            return false
    if f.state not in STATES or typeof(f.ticks) != TYPE_INT or f.ticks < 0 or f.ticks >= duration(b):
        return false
    for key in ["height", "ground", "cruise"]:
        if not (f[key] is float or f[key] is int) or not is_finite(float(f[key])) or absf(float(f[key])) > 4096:
            return false
    if not (f.heading is float or f.heading is int) or not is_finite(float(f.heading)) or f.heading < -PI or f.heading >= PI:
        return false
    if f.state != "airborne" and absf(float(f.heading)) > HEADING_EPSILON:
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
    if f.state == "airborne":
        if f.cruise < f.ground + RELATIVE_HEIGHT - 0.01 or f.height < f.ground + TERRAIN_CLEARANCE - 0.01:
            return false
        if terrain != null:
            var ground: float = terrain.flight_ground(b.pos, b.pos, radius(b))
            if absf(f.ground - ground) > 0.01 or absf(f.cruise - target_height(terrain, b)) > 0.01:
                return false
        return not f.deploy or f.moving
    if f.cruise < f.ground or f.height < f.ground - 0.01 or f.height > f.cruise + 0.01:
        return false
    var expected: float = f.ground
    if f.state in ["taking_off", "landing"]:
        var phase := float(f.ticks) / duration(b) * 4.0
        var t := phase if f.state == "taking_off" else 4.0 - phase
        expected = lerpf(f.ground, f.cruise, smoothstep(0.8, 3.2, t))
    if absf(float(f.height) - expected) > 0.01:
        return false
    return not f.deploy or f.moving


static func air_path_clear(sim, id: int, from: Vector2, to: Vector2, from_height: float, to_height: float, lift_column: bool = false, heading: float = INF) -> bool:
    var b: Dictionary = sim.buildings[id]
    if state(b) == "airborne" and minf(from_height, to_height) < sim.terrain.flight_ground(from, to, radius(b)) + TERRAIN_CLEARANCE:
        return false
    var steps := maxi(1, ceili(maxf(from.distance_to(to) / 4.0, absf(to_height - from_height) / 4.0)))
    for step in range(steps + 1):
        var weight := float(step) / steps
        if not air_clear(sim, id, from.lerp(to, weight), lerpf(from_height, to_height, weight), true, lift_column, heading):
            return false
    return true


static func air_clear(sim, id: int, position: Vector2, height: float, check_terrain: bool = true, lift_column: bool = false, heading: float = INF) -> bool:
    var b: Dictionary = sim.buildings[id]
    var vertical := lift_column or (state(b) in ["taking_off", "landing"] and absf(angle_difference(float(b.flight.heading), 0.0)) <= HEADING_EPSILON)
    var rect := Rect2(position - sim.BUILD_TYPES[b.type].size * 0.5, sim.BUILD_TYPES[b.type].size)
    if heading == INF:
        heading = float(b.get("flight", {}).get("heading", 0.0))
    # Retain conservative terrain/map-edge clearance; building bodies use OBBs.
    var radius: float = sim.BUILD_TYPES[b.type].size.length() * 0.5
    var within_map: bool = Rect2(Vector2.ZERO, sim.WORLD).encloses(rect) if vertical else Rect2(Vector2.ONE * radius, sim.WORLD - Vector2.ONE * radius * 2).has_point(position)
    if not within_map:
        return false
    if check_terrain:
        var ground: float = sim.terrain.flight_ground_rect(rect) if vertical else sim.terrain.flight_ground(position, position, radius)
        if height < ground + (0.0 if vertical else TERRAIN_CLEARANCE) - 0.01:
            return false
    for other_id: int in sim.buildings:
        if other_id == id:
            continue
        var other: Dictionary = sim.buildings[other_id]
        # Extrude each part separately while another building takes off/lands.
        if AirVolumes.overlaps(b.type, position, height, heading, other, sim.terrain.height_at(other.pos)):
            return false
    return true
