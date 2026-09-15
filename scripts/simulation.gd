extends RefCounted
# The host is the only writer. Clients display snapshots; they never simulate damage.
const VERSION := "rts-economy-2"
const TICK := 20
const CELL := 32
const WORLD := Vector2(1600, 960)
const UNIT_TYPES := {
	"soldier": {"hp": 100, "speed": 100.0, "range": 125.0, "damage": 16, "cooldown": 12, "radius": 11.0, "cost": 100, "time": 50},
	"harvester": {"hp": 160, "speed": 75.0, "range": 0.0, "damage": 0, "cooldown": 20, "radius": 14.0, "cost": 200, "time": 70}
}
const BUILD_TYPES := {
	"base": {"hp": 800, "size": Vector2(96, 96), "cost": 500, "time": 140},
	"barracks": {"hp": 420, "size": Vector2(64, 64), "cost": 250, "time": 80}
}
var units: Dictionary = {}
var buildings: Dictionary = {}
var ores: Dictionary = {}
var money: Dictionary = {1: 600, 2: 600}
var frame := 0
var match_id := 0
var winner := 0
var next_id := 1
var ai_enabled := false
var effects: Array = []
var obstacles: Array[Rect2] = []
var visible: Dictionary = {}
var explored: Dictionary = {}
var nav := AStarGrid2D.new()

func reset(with_ai: bool = false) -> void:
	match_id += 1
	units.clear()
	buildings.clear()
	ores.clear()
	money = {1: 600, 2: 600}
	frame = 0
	winner = 0
	next_id = 1
	ai_enabled = with_ai
	effects.clear()
	for owner in [1, 2]:
		var cells := PackedByteArray()
		cells.resize(1500)
		cells.fill(0)
		visible[owner] = cells.duplicate()
		explored[owner] = cells.duplicate()
	obstacles = [Rect2(704, 64, 128, 192), Rect2(736, 672, 128, 224), Rect2(992, 416, 96, 96), Rect2(448, 448, 96, 96)]
	_add_building(1, "base", Vector2(192, 192), true)
	_add_building(2, "base", Vector2(1408, 768), true)
	add_unit(1, "soldier", Vector2(304, 160))
	add_unit(1, "soldier", Vector2(304, 208))
	add_unit(1, "harvester", Vector2(192, 304))
	add_unit(2, "soldier", Vector2(1296, 736))
	add_unit(2, "soldier", Vector2(1296, 784))
	add_unit(2, "harvester", Vector2(1408, 656))
	ores = {1: {"pos": Vector2(352, 352), "amount": 4000}, 2: {"pos": Vector2(1248, 576), "amount": 4000}, 3: {"pos": Vector2(800, 480), "amount": 6000}}
	rebuild_navigation()
	update_visibility()

func update_visibility() -> void:
	for owner in [1, 2]:
		var cells: PackedByteArray = visible[owner]
		cells.fill(0)
		for collection: Dictionary in [units, buildings]:
			for entity: Dictionary in collection.values():
				if entity.owner != owner or entity.hp <= 0:
					continue
				var center: Vector2 = entity.pos
				for x in range(maxi(0, int(center.x / CELL) - 11), mini(50, int(center.x / CELL) + 12)):
					for y in range(maxi(0, int(center.y / CELL) - 11), mini(30, int(center.y / CELL) + 12)):
						if center.distance_to(Vector2(x * CELL + 16, y * CELL + 16)) <= 340:
							cells[y * 50 + x] = 1
		visible[owner] = cells
		var known: PackedByteArray = explored[owner]
		for i in range(1500):
			if cells[i] == 1:
				known[i] = 1
		explored[owner] = known

func can_see(owner: int, pos: Vector2) -> bool:
	if owner == 0:
		return true
	var cell := Vector2i((pos / CELL).floor()).clamp(Vector2i.ZERO, Vector2i(49, 29))
	return visible.has(owner) and visible[owner][cell.y * 50 + cell.x] == 1

func allocate() -> int:
	var result := next_id
	next_id += 1
	return result

func add_unit(owner: int, kind: String, pos: Vector2) -> int:
	var id := allocate()
	var stats: Dictionary = UNIT_TYPES[kind]
	units[id] = {"owner": owner, "type": kind, "pos": pos, "hp": stats.hp, "order": "idle", "target": Vector2.ZERO,
		"attack_kind": "", "attack_id": -1, "ore": -1, "cargo": 0, "cooldown": 0, "work": 0, "path": [], "repath": 0, "flash": 0}
	return id

func _add_building(owner: int, kind: String, pos: Vector2, complete: bool) -> int:
	var id := allocate()
	var stats: Dictionary = BUILD_TYPES[kind]
	buildings[id] = {"owner": owner, "type": kind, "pos": pos, "hp": stats.hp,
		"remaining": 0 if complete else stats.time, "queue": [], "flash": 0}
	return id

func footprint(b: Dictionary, margin: float = 0.0) -> Rect2:
	var size: Vector2 = BUILD_TYPES[b.type].size
	return Rect2(b.pos - size / 2.0, size).grow(margin)

func snap_build(pos: Vector2) -> Vector2:
	return (pos / CELL).round() * CELL

func build_error(owner: int, kind: String, position: Vector2) -> String:
	if not BUILD_TYPES.has(kind) or owner not in [1, 2]:
		return "Invalid building"
	var pos := snap_build(position)
	var rect := Rect2(pos - BUILD_TYPES[kind].size / 2, BUILD_TYPES[kind].size).grow(16)
	if not Rect2(Vector2.ZERO, WORLD).encloses(rect):
		return "Outside map"
	if int(money[owner]) < int(BUILD_TYPES[kind].cost):
		return "Not enough credits"
	var nearby := false
	for b: Dictionary in buildings.values():
		if footprint(b, 16).intersects(rect):
			return "Buildings need more space"
		if b.owner == owner and b.remaining == 0 and pos.distance_to(b.pos) < 360:
			nearby = true
	if not nearby:
		return "Build within 360 px of a completed friendly building"
	for rock: Rect2 in obstacles:
		if rock.grow(16).intersects(rect):
			return "Blocked by terrain"
	for ore: Dictionary in ores.values():
		if rect.grow(32).has_point(ore.pos):
			return "Blocked by ore"
	for u: Dictionary in units.values():
		if rect.has_point(u.pos):
			return "Blocked by a unit"
	return ""

func command(owner: int, c: Dictionary) -> String:
	if winner != 0:
		return "Match has ended"
	if owner not in [1, 2]:
		return "Spectators cannot issue orders"
	var action: String = str(c.get("action", ""))
	if action == "build":
		if not c.get("pos") is Vector2:
			return "Invalid position"
		var kind: String = str(c.get("type", ""))
		var pos: Vector2 = c.pos
		if not pos.is_finite():
			return "Invalid position"
		var error := build_error(owner, kind, pos)
		if not error.is_empty():
			return error
		money[owner] -= BUILD_TYPES[kind].cost
		_add_building(owner, kind, snap_build(pos), false)
		rebuild_navigation()
		return ""
	if action in ["produce", "cancel_production"]:
		var id: int = int(c.get("building", -1))
		if not buildings.has(id) or buildings[id].owner != owner or buildings[id].remaining > 0:
			return "Select a completed friendly building"
		var b: Dictionary = buildings[id]
		if action == "cancel_production":
			if not b.queue.is_empty():
				var removed: Dictionary = b.queue.pop_back()
				money[owner] += UNIT_TYPES[removed.type].cost
			return ""
		var kind: String = str(c.get("type", ""))
		if not UNIT_TYPES.has(kind) or (kind == "soldier" and b.type != "barracks") or (kind == "harvester" and b.type != "base"):
			return "Wrong production building"
		if b.queue.size() >= 5:
			return "Queue full (5)"
		if money[owner] < UNIT_TYPES[kind].cost:
			return "Not enough credits"
		money[owner] -= UNIT_TYPES[kind].cost
		b.queue.append({"type": kind, "remaining": UNIT_TYPES[kind].time})
		return ""
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
		if not collection.has(target_id) or (collection[target_id].owner == owner and not bool(c.get("force", false))):
			return "Invalid enemy"
	if action == "gather" and not ores.has(int(c.get("target", -1))):
		return "Invalid ore field"
	var accepted := 0
	for value: Variant in requested:
		if not (value is int or value is float):
			continue
		var id := int(value)
		if not units.has(id) or units[id].owner != owner:
			continue
		var u: Dictionary = units[id]
		if action == "attack" and u.type != "soldier":
			continue
		if action == "gather" and u.type != "harvester":
			continue
		u.order = action if action != "stop" else "idle"
		u.path = []
		u.repath = 0
		u.attack_id = -1
		if action == "move":
			var index := accepted
			var offset := Vector2((index % 4) * 30, (index / 4) * 30) if requested.size() > 1 else Vector2.ZERO
			u.target = (c.pos + offset).clamp(Vector2(18, 18), WORLD - Vector2(18, 18))
		elif action == "attack":
			u.attack_kind = str(c.kind)
			u.attack_id = int(c.target)
		elif action == "attack_move":
			u.target = (c.pos as Vector2).clamp(Vector2(18, 18), WORLD - Vector2(18, 18))
		elif action == "gather":
			u.ore = int(c.target)
		accepted += 1
	return "" if accepted > 0 else "No compatible friendly units selected"

func rebuild_navigation() -> void:
	nav.region = Rect2i(0, 0, int(WORLD.x / CELL), int(WORLD.y / CELL))
	nav.cell_size = Vector2(CELL, CELL)
	nav.offset = Vector2(CELL / 2, CELL / 2)
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.update()
	for x in range(nav.region.size.x):
		for y in range(nav.region.size.y):
			var point := Vector2(x * CELL + 16, y * CELL + 16)
			nav.set_point_solid(Vector2i(x, y), not position_free(point, 15))
	for u: Dictionary in units.values():
		u.path = []
		u.repath = 0

func position_free(pos: Vector2, radius: float) -> bool:
	if not Rect2(Vector2(radius, radius), WORLD - Vector2.ONE * radius * 2).has_point(pos):
		return false
	for rock: Rect2 in obstacles:
		if rock.grow(radius).has_point(pos):
			return false
	for b: Dictionary in buildings.values():
		if footprint(b, radius).has_point(pos):
			return false
	return true

func nearest_cell(pos: Vector2) -> Vector2i:
	var base := Vector2i((pos / CELL).floor())
	base = base.clamp(Vector2i.ZERO, nav.region.size - Vector2i.ONE)
	if not nav.is_point_solid(base):
		return base
	for radius in range(1, 12):
		for x in range(-radius, radius + 1):
			for y in range(-radius, radius + 1):
				var p := base + Vector2i(x, y)
				if nav.is_in_boundsv(p) and not nav.is_point_solid(p):
					return p
	return base

func move_towards(u: Dictionary, destination: Vector2, stop_distance: float = 4.0) -> void:
	if (u.pos as Vector2).distance_to(destination) <= stop_distance:
		return
	u.repath = int(u.repath) - 1
	if u.path.is_empty() or u.repath <= 0:
		var start := nearest_cell(u.pos)
		var goal := nearest_cell(destination)
		u.path = Array(nav.get_point_path(start, goal))
		if not u.path.is_empty():
			u.path.pop_front()
		if position_free(destination, UNIT_TYPES[u.type].radius):
			u.path.append(destination)
		u.repath = 20
	if u.path.is_empty():
		return
	var waypoint: Vector2 = u.path[0]
	var next: Vector2 = (u.pos as Vector2).move_toward(waypoint, UNIT_TYPES[u.type].speed / TICK)
	if position_free(next, UNIT_TYPES[u.type].radius):
		u.pos = next
	else:
		u.path = []
	if next.distance_to(waypoint) < 1.0 and not u.path.is_empty():
		u.path.pop_front()

func _closest_enemy(u: Dictionary) -> Array:
	var result: Array = []
	var distance := 190.0
	for kind: String in ["unit", "building"]:
		var collection: Dictionary = units if kind == "unit" else buildings
		for id: int in collection:
			var e: Dictionary = collection[id]
			var d: float = (u.pos as Vector2).distance_to(e.pos)
			if e.owner != u.owner and d < distance and e.hp > 0:
				distance = d
				result = [kind, id]
	return result

func _fight(u: Dictionary) -> void:
	var collection: Dictionary = units if u.attack_kind == "unit" else buildings
	if not collection.has(int(u.attack_id)):
		u.attack_id = -1
		u.order = "idle"
		return
	var enemy: Dictionary = collection[int(u.attack_id)]
	var edge: Vector2 = enemy.pos
	if u.attack_kind == "building":
		edge = (u.pos as Vector2).clamp(footprint(enemy).position, footprint(enemy).end)
	var distance: float = (u.pos as Vector2).distance_to(edge)
	if distance > UNIT_TYPES[u.type].range:
		move_towards(u, edge, 70)
	elif u.cooldown <= 0:
		u.cooldown = UNIT_TYPES[u.type].cooldown
		enemy.hp -= UNIT_TYPES[u.type].damage
		enemy.flash = 3
		effects.append({"from": u.pos, "to": edge, "life": 5, "kind": "shot", "owner": u.owner, "frame": frame})

func _gather(u: Dictionary) -> void:
	if u.cargo >= 60 or (u.cargo > 0 and (not ores.has(int(u.ore)) or ores[int(u.ore)].amount <= 0)):
		var closest: Dictionary = {}
		var best := INF
		for b: Dictionary in buildings.values():
			if b.owner == u.owner and b.type == "base" and b.remaining == 0:
				var d: float = (u.pos as Vector2).distance_to(b.pos)
				if d < best:
					best = d
					closest = b
		if closest.is_empty():
			return
		var edge: Vector2 = (u.pos as Vector2).clamp(footprint(closest).position, footprint(closest).end)
		if (u.pos as Vector2).distance_to(edge) < 44:
			money[u.owner] += int(u.cargo)
			u.cargo = 0
			u.path = []
		else:
			# Approach the outside of the base, rather than a solid footprint cell.
			var approach: Vector2 = edge + ((u.pos as Vector2) - edge).normalized() * 24
			move_towards(u, approach, 4)
		return
	if not ores.has(int(u.ore)) or ores[int(u.ore)].amount <= 0:
		u.order = "idle"
		return
	var ore: Dictionary = ores[int(u.ore)]
	if (u.pos as Vector2).distance_to(ore.pos) > 46:
		move_towards(u, ore.pos, 38)
	else:
		u.work += 1
		if u.work >= 4:
			var amount := mini(10, int(ore.amount))
			ore.amount -= amount
			u.cargo += amount
			u.work = 0

func step() -> void:
	if winner != 0:
		return
	frame += 1
	for e: Dictionary in effects:
		e.life -= 1
	effects = effects.filter(func(e: Dictionary) -> bool: return e.life > 0)
	if ai_enabled and frame % 30 == 0:
		_ai_step()
	for id: int in buildings.keys():
		var b: Dictionary = buildings[id]
		b.flash = maxi(0, int(b.flash) - 1)
		if b.remaining > 0:
			b.remaining -= 1
		elif not b.queue.is_empty():
			var job: Dictionary = b.queue[0]
			job.remaining = maxi(0, int(job.remaining) - 1)
			if job.remaining == 0:
				var spawn := _spawn_position(b)
				if spawn != Vector2.ZERO:
					add_unit(int(b.owner), str(job.type), spawn)
					b.queue.pop_front()
	for id: int in units.keys():
		if not units.has(id):
			continue
		var u: Dictionary = units[id]
		if u.hp <= 0:
			continue
		u.flash = maxi(0, int(u.flash) - 1)
		u.cooldown = maxi(0, int(u.cooldown) - 1)
		if u.order == "move":
			move_towards(u, u.target)
			if (u.pos as Vector2).distance_to(u.target) < 5:
				u.order = "idle"
		elif u.order == "attack_move":
			var nearby := _closest_enemy(u)
			if not nearby.is_empty():
				u.attack_kind = nearby[0]
				u.attack_id = nearby[1]
				u.order = "attack"
			else:
				move_towards(u, u.target)
				if (u.pos as Vector2).distance_to(u.target) < 5:
					u.order = "idle"
		elif u.order == "gather":
			_gather(u)
		elif u.order == "attack":
			_fight(u)
		elif u.type == "soldier":
			var target := _closest_enemy(u)
			if not target.is_empty():
				u.attack_kind = target[0]
				u.attack_id = target[1]
				u.order = "attack"
	_separate_units()
	var removed_building := false
	for kind: String in ["unit", "building"]:
		var collection: Dictionary = units if kind == "unit" else buildings
		for id: int in collection.keys():
			if collection[id].hp <= 0:
				var dead: Dictionary = collection[id]
				effects.append({"from": dead.pos, "to": dead.pos, "life": 10, "kind": "death", "owner": dead.owner, "frame": frame})
				if kind == "building":
					removed_building = true
					for job: Dictionary in dead.queue:
						money[dead.owner] += UNIT_TYPES[job.type].cost
				collection.erase(id)
	if removed_building:
		rebuild_navigation()
	if frame % 4 == 0:
		update_visibility()
	var has_base := {1: false, 2: false}
	for b: Dictionary in buildings.values():
		if b.type == "base":
			has_base[b.owner] = true
	if not has_base[1] and not has_base[2]:
		winner = 3
	elif not has_base[1]:
		winner = 2
	elif not has_base[2]:
		winner = 1

func _spawn_position(b: Dictionary) -> Vector2:
	for ring in range(3, 8):
		for i in range(16):
			var p: Vector2 = b.pos + Vector2.from_angle(float(i) / 16 * TAU) * ring * 24
			var clear := position_free(p, 16)
			for u: Dictionary in units.values():
				if (u.pos as Vector2).distance_to(p) < 34:
					clear = false
			if clear:
				return p
	return Vector2.ZERO

func _separate_units() -> void:
	var ids: Array = units.keys()
	ids.sort()
	for iteration in range(8):
		for i in range(ids.size()):
			for j in range(i + 1, ids.size()):
				var a: Dictionary = units[ids[i]]
				var b: Dictionary = units[ids[j]]
				var delta: Vector2 = b.pos - a.pos
				var minimum: float = UNIT_TYPES[a.type].radius + UNIT_TYPES[b.type].radius + 1
				var distance := delta.length()
				if distance >= minimum:
					continue
				var normal := Vector2.RIGHT if distance < 0.001 else delta / distance
				var amount := (minimum - distance) / 2.0
				var pa: Vector2 = a.pos - normal * amount
				var pb: Vector2 = b.pos + normal * amount
				if position_free(pa, UNIT_TYPES[a.type].radius):
					a.pos = pa
				if position_free(pb, UNIT_TYPES[b.type].radius):
					b.pos = pb

func _ai_step() -> void:
	var barracks := -1
	var base := -1
	for id: int in buildings:
		if buildings[id].owner == 2:
			if buildings[id].type == "barracks":
				barracks = id
			elif buildings[id].type == "base":
				base = id
	if barracks < 0 and base >= 0:
		for offset: Vector2 in [Vector2(-192, 0), Vector2(0, -192), Vector2(-192, -160)]:
			if command(2, {"action": "build", "type": "barracks", "pos": buildings[base].pos + offset}).is_empty():
				break
	if barracks >= 0 and buildings[barracks].queue.size() < 2:
		command(2, {"action": "produce", "building": barracks, "type": "soldier"})
	for id: int in units:
		var u: Dictionary = units[id]
		if u.owner != 2 or u.order != "idle":
			continue
		if u.type == "harvester":
			command(2, {"action": "gather", "units": [id], "target": 2})
		elif frame > 1200:
			for bid: int in buildings:
				if buildings[bid].owner == 1 and buildings[bid].type == "base":
					command(2, {"action": "attack", "units": [id], "kind": "building", "target": bid})
					break

func snapshot() -> Dictionary:
	return {"version": VERSION, "match": match_id, "frame": frame, "units": units.duplicate(true), "buildings": buildings.duplicate(true),
		"ores": ores.duplicate(true), "money": money.duplicate(true), "winner": winner, "effects": effects.duplicate(true),
		"visible": visible.duplicate(true), "explored": explored.duplicate(true)}

func apply_snapshot(state: Dictionary) -> void:
	match_id = state.match
	frame = state.frame
	units = state.units
	buildings = state.buildings
	ores = state.ores
	money = state.money
	winner = state.winner
	effects = state.effects
	visible = state.visible
	explored = state.explored
