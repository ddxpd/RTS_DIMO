extends Control
## Preview lines are screen-space; occupied outlines remain depth-tested on terrain.
const Simulation = preload("res://scripts/simulation.gd")
const VALID := Color("#73f3a0")
const INVALID := Color("#ff7770")
const OCCUPIED := Color("#83bdd3")
const ERROR_TEXT := {
    "Outside map": "超出地图范围",
    "Not enough credits": "资金不足",
    "Building footprint occupied": "建筑占地格已被占用",
    "Build within 360 px of a completed friendly building": "需要靠近已完成的己方建筑",
    "Blocked by terrain": "地形阻挡",
    "Blocked by ore": "矿点阻挡",
    "Blocked by a unit": "单位阻挡",
    "Blocked by a building or landing reservation": "建筑或降落预留区域阻挡",
    "Deploy in currently visible terrain": "需要在当前可见区域降落",
    "Build on a flat platform, away from slopes and cliffs": "需要平坦地面，避开坡道和悬崖",
    "Build inside the sample area": "需要放置在样板区范围内"
}

var host
var ground_root: Node3D
var occupied: Dictionary = {}
var footprint := Rect2()
var dimensions := Vector2i.ZERO
var cells: Array[Dictionary] = []
var reserved_rects: Array[Rect2] = []
var error := ""
var label_text := ""
var label_rect := Rect2()
var segments: Array[Dictionary] = []
var outline_material: StandardMaterial3D


func configure(owner, world: Node3D) -> void:
    host = owner
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    clip_contents = true
    ground_root = Node3D.new()
    ground_root.name = "OccupiedFootprints"
    world.add_child(ground_root)
    outline_material = StandardMaterial3D.new()
    outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    outline_material.albedo_color = OCCUPIED
    outline_material.cull_mode = BaseMaterial3D.CULL_DISABLED
    clear()


func clear() -> void:
    visible = false
    footprint = Rect2()
    dimensions = Vector2i.ZERO
    cells.clear()
    segments.clear()
    label_text = ""
    label_rect = Rect2()
    error = ""
    if is_instance_valid(ground_root):
        ground_root.visible = false
    queue_redraw()


func reset() -> void:
    clear()
    for entry: Dictionary in occupied.values():
        if is_instance_valid(entry.mesh):
            entry.mesh.queue_free()
    occupied.clear()


func show_site(rect: Rect2, reason: String, site_cells: Array = [], excluded_id: int = -1, regions: Array[Rect2] = []) -> void:
    var map_rect: Rect2 = host._get_map_screen_rect()
    position = map_rect.position
    size = map_rect.size
    visible = true
    ground_root.visible = true
    footprint = rect
    dimensions = Vector2i(roundi(rect.size.x / Simulation.CELL), roundi(rect.size.y / Simulation.CELL))
    error = reason
    cells.clear()
    cells.assign(site_cells)
    reserved_rects.assign(regions if not regions.is_empty() else [rect])
    label_text = "宽 %d 格 × 深 %d 格" % [dimensions.x, dimensions.y]
    _make_segments()
    _sync_occupied(excluded_id)
    queue_redraw()


func _make_segments() -> void:
    segments.clear()
    # Integer edge keys merge adjacent cell edges, with invalid taking precedence.
    var edges: Dictionary = {}
    for y in range(dimensions.y):
        for x in range(dimensions.x):
            var center := footprint.position + (Vector2(x, y) + Vector2.ONE * 0.5) * Simulation.CELL
            if not reserved_rects.any(func(rect: Rect2) -> bool: return rect.has_point(center)):
                continue
            var index := y * dimensions.x + x
            var blocked := not error.is_empty() if cells.is_empty() else not str(cells[index].error).is_empty()
            for key: Vector3i in [Vector3i(x, y, 0), Vector3i(x, y + 1, 0), Vector3i(x, y, 1), Vector3i(x + 1, y, 1)]:
                edges[key] = bool(edges.get(key, false)) or blocked
    for key: Vector3i in edges:
        var a := footprint.position + Vector2(key.x, key.y) * Simulation.CELL
        var b := a + (Vector2.RIGHT if key.z == 0 else Vector2.DOWN) * Simulation.CELL
        var border := key.y in [0, dimensions.y] if key.z == 0 else key.x in [0, dimensions.x]
        var blocked: bool = edges[key] or (border and not error.is_empty())
        segments.append({"a": a, "b": b, "border": border, "color": INVALID if blocked else VALID})


func _project(point: Vector2) -> Vector2:
    return host._world_to_screen(point) - position


func _draw() -> void:
    if dimensions == Vector2i.ZERO:
        return
    var factor := clampf(get_viewport_rect().size.y / 1080.0, 0.7, 1.5)
    for edge: Dictionary in segments:
        var a := _project(edge.a)
        var b := _project(edge.b)
        var width := (2.5 if edge.border else 1.5) * factor
        draw_line(a, b, Color(0.025, 0.065, 0.085, 0.8), width + 2.0 * factor, true)
        draw_line(a, b, edge.color, width, true)
    var bounds := Rect2(_project(footprint.position), Vector2.ZERO)
    for p: Vector2 in [footprint.position + Vector2(footprint.size.x, 0), footprint.end, footprint.position + Vector2(0, footprint.size.y)]:
        bounds = bounds.expand(_project(p))
    var font := get_theme_default_font()
    var font_size := roundi(17 * factor)
    var reason: String = ERROR_TEXT.get(error, error)
    var text_width := maxf(font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x,
        font.get_string_size(reason, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
    var box_size := Vector2(minf(text_width + 24 * factor, size.x), (58 if not error.is_empty() else 32) * factor)
    var origin := Vector2(bounds.get_center().x - box_size.x * 0.5, bounds.end.y + 10 * factor)
    if origin.y + box_size.y > size.y:
        origin.y = bounds.position.y - box_size.y - 10 * factor
    origin = origin.clamp(Vector2.ZERO, (size - box_size).max(Vector2.ZERO))
    label_rect = Rect2(origin, box_size)
    draw_style_box(_label_style(), label_rect)
    draw_string(font, origin + Vector2(12, 22) * factor, label_text, HORIZONTAL_ALIGNMENT_LEFT, box_size.x - 24 * factor, font_size, VALID if error.is_empty() else INVALID)
    if not error.is_empty():
        draw_string(font, origin + Vector2(12, 46) * factor, reason, HORIZONTAL_ALIGNMENT_LEFT, box_size.x - 24 * factor, font_size, Color.WHITE)


func _label_style() -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.025, 0.055, 0.075, 0.92)
    style.set_corner_radius_all(4)
    return style


func _sync_occupied(excluded_id: int) -> void:
    var keep: Dictionary = {}
    for id: int in host.sim.buildings:
        var building: Dictionary = host.sim.buildings[id]
        if id == excluded_id or building.hp <= 0 or not Simulation.BarracksFlight.blocks_ground(building) or Simulation.BarracksFlight.is_airborne(building):
            continue
        if building.owner != host.local_slot and not host.sim.can_see(host.local_slot, building.pos):
            continue
        var rect: Rect2 = host.sim.placement_bounds(building.type, building.pos)
        var bounds := Rect2(_project(rect.position), Vector2.ZERO)
        for p: Vector2 in [rect.end, rect.position + Vector2(rect.size.x, 0), rect.position + Vector2(0, rect.size.y)]:
            bounds = bounds.expand(_project(p))
        if not Rect2(Vector2.ZERO, size).intersects(bounds.grow(12)):
            continue
        keep[id] = true
        if not occupied.has(id):
            var mesh := MeshInstance3D.new()
            mesh.name = "Occupied%d" % id
            mesh.material_override = outline_material
            mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            ground_root.add_child(mesh)
            occupied[id] = {"mesh": mesh, "rect": Rect2()}
        var entry: Dictionary = occupied[id]
        if entry.rect != rect:
            entry.mesh.mesh = _occupied_mesh(rect, host.sim.placement_rects(building.type, building.pos))
            entry.rect = rect
    for id: int in occupied.keys():
        if not keep.has(id):
            occupied[id].mesh.queue_free()
            occupied.erase(id)


func _occupied_mesh(rect: Rect2, regions: Array[Rect2] = []) -> ArrayMesh:
    var vertices := PackedVector3Array()
    if regions.size() > 1:
        var edges := {}
        for region: Rect2 in regions:
            for y in range(roundi(region.size.y / Simulation.CELL)):
                for x in range(roundi(region.size.x / Simulation.CELL)):
                    var p := Vector2i((region.position + Vector2(x, y) * Simulation.CELL) / Simulation.CELL)
                    for key: Vector3i in [Vector3i(p.x, p.y, 0), Vector3i(p.x, p.y + 1, 0), Vector3i(p.x, p.y, 1), Vector3i(p.x + 1, p.y, 1)]:
                        edges[key] = int(edges.get(key, 0)) + 1
        for key: Vector3i in edges:
            if edges[key] != 1:
                continue
            var a := Vector2(key.x, key.y) * Simulation.CELL
            var b := a + (Vector2.RIGHT if key.z == 0 else Vector2.DOWN) * Simulation.CELL
            _ribbon(vertices, a, b)
        var shaped_arrays := []
        shaped_arrays.resize(Mesh.ARRAY_MAX)
        shaped_arrays[Mesh.ARRAY_VERTEX] = vertices
        var shaped_mesh := ArrayMesh.new()
        shaped_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, shaped_arrays)
        return shaped_mesh
    var counts := Vector2i(roundi(rect.size.x / Simulation.CELL), roundi(rect.size.y / Simulation.CELL))
    for axis in range(2):
        var along := Vector2.RIGHT if axis == 0 else Vector2.DOWN
        var across := Vector2.DOWN if axis == 0 else Vector2.RIGHT
        var count := counts.x if axis == 0 else counts.y
        var depth := rect.size.y if axis == 0 else rect.size.x
        for side in range(2):
            var normal := across * (-1 if side == 0 else 1)
            var start := rect.position + across * depth * side
            for index in range(count):
                var a := start + along * index * Simulation.CELL
                _ribbon(vertices, a, a + along * Simulation.CELL)
            for index in range(count + 1):
                var a := start + along * index * Simulation.CELL
                _ribbon(vertices, a, a + normal * 7.0)
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh


func _ribbon(vertices: PackedVector3Array, a: Vector2, b: Vector2) -> void:
    var delta := b - a
    var offset := Vector2(-delta.y, delta.x).normalized() * 0.8
    for p: Vector2 in [a - offset, a + offset, b + offset, a - offset, b + offset, b - offset]:
        vertices.append(Vector3(p.x, host.sim.terrain.height_at(p) + 0.85, p.y))
