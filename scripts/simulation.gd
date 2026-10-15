class_name Simulation
extends RefCounted
const EntityCatalog = preload("res://scripts/definitions/entity_catalog.gd")
const SnapshotValidator = preload("res://scripts/snapshot_validator.gd")
const DepotDocking = preload("res://scripts/simulation_systems/depot_docking.gd")
const EconomySystem = preload("res://scripts/simulation_systems/economy_system.gd")
const CombatSystem = preload("res://scripts/simulation_systems/combat_system.gd")
const MovementSystem = preload("res://scripts/simulation_systems/movement_system.gd")
const AiSystem = preload("res://scripts/simulation_systems/ai_system.gd")
const VisibilitySystem = preload("res://scripts/simulation_systems/visibility_system.gd")
# The host is the only writer. Clients display snapshots; they never simulate damage.
const VERSION := "gaia-frontier-19"
const WorldGrid = preload("res://scripts/world_grid.gd")
const MiningSystem = preload("res://scripts/simulation_systems/mining_system.gd")
const SweptPaths = preload("res://scripts/maps/swept_paths.gd")
const RallySystem = preload("res://scripts/simulation_systems/rally_system.gd")
const BarracksFlight = preload("res://scripts/barracks_flight.gd")
const WEAPON_TARGETS = EntityCatalog.WEAPON_TARGETS
const ArrivalPlanner = preload("res://scripts/arrival_planner.gd")
const MapTerrain = preload("res://scripts/maps/map_terrain.gd")
const EYE_HEIGHTS = EntityCatalog.EYE_HEIGHTS
const TICK := 20
const CELL := WorldGrid.CELL
const WORLD := Vector2(4800, 3200)
const GRID := Vector2i(150, 100)
const GRID_CELLS := GRID.x * GRID.y
const MAX_SNAPSHOT_UNITS := 4096
const MAX_SNAPSHOT_BUILDINGS := 1024
const MAX_SNAPSHOT_ORES := 256
const MAX_SNAPSHOT_EFFECTS := 4096
const MAX_SNAPSHOT_ORE_AMOUNT := 100000
# Soldier definitions remain for archived model/animation previews; only this
# roster is available to live match initialization, production and catalogues.
const ACTIVE_UNIT_TYPES = EntityCatalog.ACTIVE_UNIT_TYPES
const UNIT_TYPES = EntityCatalog.UNIT_TYPES
const BUILD_CELLS = EntityCatalog.BUILD_CELLS
const BUILD_TYPES = EntityCatalog.BUILD_TYPES
var units: Dictionary = {}
var buildings: Dictionary = {}
var ores: Dictionary = {}
var money: Dictionary = {1: 600, 2: 600}
var frame := 0
var match_id := 0
var winner := 0
var match_config: Dictionary = {}
var players: Array = [1, 2]
var teams: Dictionary = {1: 1, 2: 2}
var ai_players: Array = []
var training := false
var eliminated: Array = []
var result := {"status": "playing", "team": 0}
var next_id := 1
var ai_enabled := false
var effects: Array = []
var obstacles: Array[Rect2] = []
var visible: Dictionary = {}
var explored: Dictionary = {}
var nav := AStarGrid2D.new()
var navigation_by_radius: Dictionary = {}
var connectivity_by_radius: Dictionary = {}
var blocked_sight: Dictionary = {}
var swept_graphs: Dictionary = {}
var avoidance := preload("res://scripts/movement_avoidance.gd").new()
var arrival_nav_regions := PackedInt32Array()
var last_snapshot_error := ""
var terrain := MapTerrain.new()
var map_id := "desert_quarry"

func reset(with_ai: bool = false, selected_map: String = "desert_quarry", config: Dictionary = {}) -> bool:
    if not config.is_empty() and not preload("res://scripts/runtime/match_config.gd").error(config, true).is_empty():
        last_snapshot_error = preload("res://scripts/runtime/match_config.gd").error(config, true)
        return false
    var next_terrain := MapTerrain.new()
    if not next_terrain.load_map(selected_map):
        last_snapshot_error = next_terrain.error
        return false
    terrain = next_terrain
    map_id = selected_map
    match_id += 1
    units.clear()
    avoidance = preload("res://scripts/movement_avoidance.gd").new()
    buildings.clear()
    ores.clear()
    match_config = config.duplicate(true)
    training = bool(config.get("training", is_test_map()))
    players = [1] if is_test_map() else [1, 2]
    teams = {1: 1} if is_test_map() else {1: 1, 2: 2}
    ai_players = [2] if with_ai and not training else []
    if not config.is_empty():
        players = []
        teams = {}
        ai_players = []
        for i in range(4):
            if config.seats[i] in ["human", "ai"]:
                players.append(i + 1)
                teams[i + 1] = config.teams[i] if config.mode == "2v2" else i + 1
                if config.seats[i] == "ai":
                    ai_players.append(i + 1)
    eliminated.clear()
    result = {"status": "playing", "team": 0}
    money = {1: 0, 2: 0, 3: 0, 4: 0}
    for owner: int in players:
        money[owner] = int(config.get("funds", 10000 if training else 6000))
    frame      = 0
    winner     = 0
    next_id    = 1
    ai_enabled = not ai_players.is_empty()
    effects.clear()
    for owner in [1, 2, 3, 4]:
        var cells := PackedByteArray()
        cells.resize(GRID_CELLS)
        cells.fill(0)
        visible[owner] = cells.duplicate()
        explored[owner] = cells.duplicate()
    obstacles.assign(terrain.definition.get("obstacles", []))
    for owner in players:
        var spawn: Vector2 = terrain.definition.spawns[mini(owner - 1, terrain.definition.spawns.size() - 1)]
        if not config.is_empty():
            spawn = _configured_spawn(spawn)
            if not spawn.is_finite():
                last_snapshot_error = "No clear, aligned base site for player %d." % owner
                return false
        _add_building(owner, "base", spawn, true)
    for index in range(terrain.definition.ores.size()):
        ores[index + 1] = terrain.definition.ores[index].duplicate(true)
    rebuild_navigation()
    update_visibility()
    return true

func _configured_spawn(origin: Vector2) -> Vector2:
    var size: Vector2 = BUILD_TYPES.base.size
    for radius in range(20):
        for z in range(-radius, radius + 1):
            for x in range(-radius, radius + 1):
                if radius > 0 and absi(x) != radius and absi(z) != radius:
                    continue
                var position := snap_building("base", origin + Vector2(x, z) * CELL)
                var area := Rect2(position - size / 2, size)
                if not terrain.build_error(area).is_empty():
                    continue
                var overlaps := false
                for building: Dictionary in buildings.values():
                    if footprint(building).grow(CELL * 2).intersects(area):
                        overlaps = true
                if not overlaps:
                    return position
    return Vector2(INF, INF)

func is_test_map() -> bool:
    return bool(terrain.definition.get("test_only", false))


func update_visibility() -> void:
    VisibilitySystem.update_visibility(self)


func can_see(owner: int, pos: Vector2) -> bool:
    return VisibilitySystem.can_see(self, owner, pos)


func allocate() -> int:
    var result := next_id
    next_id += 1
    return result

func add_unit(owner: int, kind: String, pos: Vector2) -> int:
    # Low-level factory also serves archived asset fixtures. Live creation is
    # restricted by reset() and EconomySystem's active-roster checks.
    var id := allocate()
    var stats: Dictionary = UNIT_TYPES[kind]
    units[id] = {"owner": owner, "type": kind, "pos": pos, "hp": stats.hp, "order": "idle", "target": Vector2.ZERO,
        "attack_kind": "", "attack_id": -1, "ore": -1, "cargo": 0, "cooldown": 0, "work": 0, "path": [], "repath": 0, "flash": 0, "auto": true, "stuck": 0}
    if kind == "harvester":
        units[id].heading = -PI * 0.5
    return id

func _add_building(owner: int, kind: String, pos: Vector2, complete: bool) -> int:
    pos = snap_building(kind, pos)
    var id := allocate()
    var stats: Dictionary = BUILD_TYPES[kind]
    var initial_hp := int(stats.hp) if complete else EconomySystem.construction_health(int(stats.hp), int(stats.time), int(stats.time))
    buildings[id] = {"owner": owner, "type": kind, "pos": pos, "hp": initial_hp,
        "remaining": 0 if complete else stats.time, "queue": [], "flash": 0, "rally": Vector2.ZERO, "rally_mode": "none", "rally_ore": -1, "cooldown": 0}
    if kind == "refinery":
        buildings[id].dock_flash = []
        buildings[id].dock_flash.resize(EntityCatalog.REFINERY_DOCK_RECTS.size())
        buildings[id].dock_flash.fill(0)
    if kind in BarracksFlight.FLYING_TYPES:
        BarracksFlight.initialize(buildings[id], terrain.height_at(pos))
    return id


func can_target(attacker: Dictionary, target: Dictionary) -> bool:
    return CombatSystem.can_target(self, attacker, target)


func weapon_can_target(layers: Array, target: Dictionary) -> bool:
    return CombatSystem.weapon_can_target(self, layers, target)


func deployment_site(owner: int, id: int, pos: Vector2) -> Dictionary:
    return BarracksFlight.placement(self, owner, id, pos)

func footprint(b: Dictionary, margin: float = 0.0) -> Rect2:
    var size: Vector2 = BUILD_TYPES[b.type].size
    return Rect2(b.pos - size / 2.0, size).grow(margin)


func placement_rects(kind: String, pos: Vector2) -> Array[Rect2]:
    var size: Vector2 = BUILD_TYPES[kind].size
    return [Rect2(pos - size / 2.0, size)]


func placement_bounds(kind: String, pos: Vector2) -> Rect2:
    var rects := placement_rects(kind, pos)
    var bounds := rects[0]
    for rect: Rect2 in rects:
        bounds = bounds.merge(rect)
    return bounds

# Production jobs now cover unit kinds only; bunkers are placed directly.
func _job_stats(kind: String) -> Dictionary:
    return EconomySystem._job_stats(self, kind)


static func is_combat_unit(kind: String) -> bool:
    return UNIT_TYPES.has(kind) and WEAPON_TARGETS.has(kind)

# Nearest visible enemy unit inside bunker range.
func _bunker_target(b: Dictionary) -> Dictionary:
    return CombatSystem._bunker_target(self, b)


# Send an automated miner to the nearest visible ore patch.
func _auto_mine(u: Dictionary) -> void:
    EconomySystem._auto_mine(self, u)


func snap_build(pos: Vector2) -> Vector2:
    return EconomySystem.snap_build(self, pos)


func snap_building(kind: String, pos: Vector2) -> Vector2:
    # Align footprint edges, including half-cell centers for odd dimensions.
    return WorldGrid.snap_center(pos, BUILD_TYPES[kind].size)


func build_error(owner: int, kind: String, position: Vector2) -> String:
    return EconomySystem.build_error(self, owner, kind, position)


func command(owner: int, c: Dictionary) -> String:
    if winner != 0:
        return "Match has ended"
    if owner not in (players if not match_config.is_empty() else [1, 2, 3, 4]) or owner in eliminated:
        return "Spectators cannot issue orders"
    var action: String = str(c.get("action", ""))
    if action in ["barracks_takeoff", "barracks_move", "barracks_stop", "barracks_deploy", "building_takeoff", "building_move", "building_stop", "building_deploy"]:
        return BarracksFlight.command(self, owner, c)
    if action in ["build", "produce", "cancel_production", "set_rally"]:
        return EconomySystem.command(self, owner, c)
    if action not in ["move", "attack", "attack_move", "gather", "stop"]:
        return "Unknown order"
    var requested: Variant = c.get("units", [])
    if not requested is Array or requested.size() > 200:
        return "Invalid unit list"
    if action in ["move", "attack_move"] and (not c.get("pos") is Vector2 or not (c.pos as Vector2).is_finite()):
        return "Invalid destination"
    if action == "attack":
        var collection: Dictionary = units if c.get("kind") == "unit" else buildings
        var target_id: int = int(c.get("target", -1))
        if not collection.has(target_id) or (allied(int(collection[target_id].owner), owner) and (int(collection[target_id].owner) != owner or not bool(c.get("force", false)))):
            return "Invalid enemy"
    if action == "gather" and not ores.has(int(c.get("target", -1))):
        return "Invalid ore field"
    var allocation := {}
    if action in ["move", "attack_move"]:
        var ids: Array = []
        for value: Variant in requested:
            if (value is int or value is float) and units.has(int(value)) and units[int(value)].owner == owner and not ids.has(int(value)):
                ids.append(int(value))
        if ids.is_empty():
            return "No compatible friendly units selected"
        ids.sort()
        allocation = MovementSystem.plan_arrivals(self, ids, (c.pos as Vector2).clamp(Vector2(18, 18), WORLD - Vector2(18, 18)))
        if allocation.has("error"):
            return allocation.error
    var accepted := 0
    for value: Variant in requested:
        if not (value is int or value is float):
            continue
        var id := int(value)
        if not units.has(id) or units[id].owner != owner:
            continue
        var u: Dictionary = units[id]
        if action == "attack" and not is_combat_unit(u.type):
            continue
        if action == "attack":
            var targets: Dictionary = units if c.get("kind") == "unit" else buildings
            if not can_target(u, targets[int(c.target)]):
                continue
        if action == "gather" and u.type != "harvester":
            continue
        MiningSystem.cancel(self, u)
        u.order       = action if action != "stop" else "idle"
        u.path        = []
        u.repath      = 0
        u.attack_kind = ""
        u.attack_id   = -1
        u.stuck       = 0
        u.erase("arrival")
        u.erase("dock")
        # Miners auto-seek the nearest visible ore unless explicitly stopped.
        u.auto = action != "stop"
        if action in ["move", "attack_move"]:
            u.target = allocation.orders[id].target
            u.arrival = allocation.orders[id].arrival
        elif action == "attack":
            u.attack_kind = str(c.kind)
            u.attack_id = int(c.target)
        elif action == "gather":
            u.ore = int(c.target)
            MiningSystem.request(self, u, int(u.ore))
        accepted += 1
    return "" if accepted > 0 else "No compatible friendly units selected"

func rebuild_navigation() -> void:
    MovementSystem.rebuild_navigation(self)


func navigation_for(radius: float) -> AStarGrid2D:
    return MovementSystem.navigation_for(self, radius)


func movement_free(from: Vector2, to: Vector2, radius: float) -> bool:
    return MovementSystem.movement_free(self, from, to, radius)


func route_visible(from: Vector2, to: Vector2, radius: float) -> bool:
    return MovementSystem.route_visible(self, from, to, radius)


func position_free(pos: Vector2, radius: float) -> bool:
    return MovementSystem.position_free(self, pos, radius)


func nearest_cell(pos: Vector2, radius: float = 16.0) -> Vector2i:
    return MovementSystem.nearest_cell(self, pos, radius)


func move_towards(u: Dictionary, destination: Vector2, stop_distance: float = 4.0) -> void:
    MovementSystem.move_towards(self, u, destination, stop_distance)


func _closest_enemy(u: Dictionary) -> Array:
    return CombatSystem._closest_enemy(self, u)


func _fight(u: Dictionary, fallback_order: String = "idle") -> bool:
    return CombatSystem._fight(self, u, fallback_order)


func _firing_position(u: Dictionary, target: Vector2) -> Vector2:
    return CombatSystem._firing_position(self, u, target)


func _gather(u: Dictionary) -> void:
    EconomySystem._gather(self, u)


func step() -> void:
    # Systems run synchronously against this state. Preserve entity iteration order:
    # a unit's movement/attack is completed before the next unit is processed.
    if winner != 0:
        return
    frame += 1
    MovementSystem.refresh_arrivals(self)
    for e: Dictionary in effects:
        e.life -= 1
    effects = effects.filter(func(e: Dictionary) -> bool: return e.life > 0)
    if ai_enabled and frame % 30 == 0:
        _ai_step()
    for id: int in buildings.keys():
        var b: Dictionary = buildings[id]
        if b.hp <= 0:
            continue
        b.flash = maxi(0, int(b.flash) - 1)
        if b.type in BarracksFlight.FLYING_TYPES:
            BarracksFlight.advance(self, id, b)
            if BarracksFlight.state(b) != "grounded":
                continue
        if b.remaining > 0:
            EconomySystem.advance_construction(self, b)
        elif b.type == "bunker":
            CombatSystem.advance_bunker(self, b)
        elif not b.queue.is_empty():
            EconomySystem.advance_production(self, b)
    MiningSystem.prepare(self)
    DepotDocking.prepare(self)
    MovementSystem.begin_tick(self)
    for id: int in units.keys():
        if not units.has(id):
            continue
        var u: Dictionary = units[id]
        if u.hp <= 0:
            continue
        u.flash = maxi(0, int(u.flash) - 1)
        u.cooldown = maxi(0, int(u.cooldown) - 1)
        var pos_before: Vector2 = u.pos
        if u.order == "move":
            MovementSystem.advance_move(self, u)
        elif u.order == "attack_move":
            CombatSystem.advance_attack_move(self, u)
        elif u.order == "gather":
            _gather(u)
        elif u.order == "attack":
            _fight(u)
        elif is_combat_unit(u.type):
            CombatSystem.advance_idle(self, u)
        elif u.type == "harvester" and bool(u.get("auto", true)) and frame % 10 == 0:
            # Idle automated miners keep seeking the nearest visible ore.
            _auto_mine(u)
        MovementSystem.track_stall(self, u, pos_before)
    _separate_units()
    var removed_building := false
    for kind: String in ["unit", "building"]:
        var collection: Dictionary = units if kind == "unit" else buildings
        for id: int in collection.keys():
            if collection[id].hp <= 0:
                var dead: Dictionary = collection[id]
                var death_event := {"from": dead.pos, "to": dead.pos, "life": 10, "kind": "death", "owner": dead.owner, "frame": frame}
                if kind == "unit" and dead.type == "mobile_infantry":
                    death_event["entity_id"] = id
                    death_event["unit_type"] = "mobile_infantry"
                    death_event.life = 36
                effects.append(death_event)
                if kind == "building":
                    if dead.type in ["base", "barracks", "refinery"]:
                        death_event["destruction"] = {"id": id, "type": dead.type,
                            "height": float(dead.get("flight", {}).get("height", terrain.height_at(dead.pos))),
                            "heading": float(dead.get("flight", {}).get("heading", 0.0))}
                    removed_building = true
                    EconomySystem.refund_destroyed_building(self, dead)
                collection.erase(id)
    if removed_building:
        for u: Dictionary in units.values():
            if u.has("dock") and not buildings.has(u.dock.station):
                u.erase("dock")
                u.path = []
        rebuild_navigation()
    if frame % 4 == 0:
        update_visibility()
    check_result()

func allied(a: int, b: int) -> bool:
    return a == b or (teams.has(a) and teams.has(b) and teams[a] == teams[b])

func surrender(owner: int) -> void:
    if owner not in players or owner in eliminated:
        return
    eliminated.append(owner)
    for collection: Dictionary in [units, buildings]:
        for id: int in collection.keys():
            if collection[id].owner == owner:
                collection.erase(id)
    rebuild_navigation()
    check_result()

func check_result() -> void:
    if training:
        return
    var living := {}
    for owner: int in players:
        var alive := false
        for building: Dictionary in buildings.values():
            if building.owner == owner and building.hp > 0:
                alive = true
                break
        if not alive and owner not in eliminated:
            eliminated.append(owner)
        if alive and owner not in eliminated:
            living[teams[owner]] = true
    if living.size() <= 1:
        var team: int = living.keys()[0] if living.size() == 1 else 0
        result = {"status": "won" if team > 0 else "draw", "team": team}
        winner = team if team > 0 else 5


func _spawn_position(b: Dictionary, kind: String = "mobile_infantry") -> Vector2:
    return EconomySystem._spawn_position(self, b, kind)


# Does the proposed position collide with another unit's body?
func _unit_blocks(u: Dictionary, next: Vector2) -> bool:
    return MovementSystem._unit_blocks(self, u, next)


# Retry a stalled route without moving the unit outside collision checks.
func _unstick(u: Dictionary) -> void:
    MovementSystem._unstick(self, u)


func _separate_units() -> void:
    MovementSystem._separate_units(self)


func _separate_pair(a: Dictionary, b: Dictionary) -> void:
    MovementSystem._separate_pair(self, a, b)


func _ai_step() -> void:
    if match_config.is_empty() and ai_players.is_empty():
        AiSystem._ai_step(self, 2)
        return
    for owner: int in ai_players:
        if owner not in eliminated:
            AiSystem._ai_step(self, owner)


# Nearest enemy unit inside AI territory (near any friendly building).
func _ai_threat() -> Dictionary:
    return AiSystem._ai_threat(self)


# Enemy building closest to the AI's own base.
func _ai_attack_target() -> int:
    return AiSystem._ai_attack_target(self)


func snapshot() -> Dictionary:
    return {"config": match_config.duplicate(true), "players": players.duplicate(), "teams": teams.duplicate(), "eliminated": eliminated.duplicate(), "result": result.duplicate(), "training": training, "version": VERSION, "map_id": map_id, "map_version": terrain.definition.version, "map_checksum": terrain.checksum, "match": match_id, "frame": frame, "units": units.duplicate(true), "buildings": buildings.duplicate(true),
        "ores": ores.duplicate(true), "money": money.duplicate(true), "winner": winner, "effects": effects.duplicate(true),
        "visible": visible.duplicate(true), "explored": explored.duplicate(true)}

func validate_snapshot(state: Dictionary) -> bool:
    return SnapshotValidator.new(self).validate(state)


func _validate_vector2(value: Variant, bounds: Vector2, label: String) -> bool:
    # Mining/docking validators share the same bounds check and error reporting.
    return SnapshotValidator.new(self)._validate_vector2(value, bounds, label)


func apply_snapshot(state: Dictionary) -> bool:
    if not validate_snapshot(state):
        return false
    var changed_map: bool = state.map_id != map_id
    if changed_map:
        var next_terrain := MapTerrain.new()
        if not next_terrain.load_map(state.map_id):
            return false
        terrain = next_terrain
        map_id = state.map_id
        obstacles.assign(terrain.definition.get("obstacles", []))
    match_config = state.config.duplicate(true)
    players = state.players.duplicate()
    teams = state.teams.duplicate()
    eliminated = state.eliminated.duplicate()
    result = state.result.duplicate()
    training = state.training
    match_id  = state.match
    frame     = state.frame
    units     = state.units.duplicate(true)
    buildings = state.buildings.duplicate(true)
    ores      = state.ores.duplicate(true)
    money     = state.money.duplicate(true)
    winner    = state.winner
    effects   = state.effects.duplicate(true)
    visible   = state.visible.duplicate(true)
    explored  = state.explored.duplicate(true)
    if changed_map:
        rebuild_navigation()
    return true


func _ai_build_offsets(anchor_kind: String, build_kind: String, directions: Array) -> Array[Vector2]:
    return AiSystem._ai_build_offsets(self, anchor_kind, build_kind, directions)
