extends Control
## CPU-cached terrain/fog, local-player visibility, no extra 3D viewport.
const Sim = preload("res://scripts/simulation.gd")
var host
var dragging := false
var terrain_image: Image
var terrain_texture: ImageTexture
var fog_image: Image
var fog_texture: ImageTexture
var markers: Array[Dictionary] = []
var elapsed := 1.0
var map_identity := 0
var view_polygon := PackedVector2Array()


func configure(owner) -> void:
    host = owner
    mouse_filter = Control.MOUSE_FILTER_STOP
    mouse_default_cursor_shape = Control.CURSOR_CROSS
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    clip_contents = true


func map_rect() -> Rect2:
    var extent := size - Vector2(8, 8)
    var factor := minf(extent.x / Sim.WORLD.x, extent.y / Sim.WORLD.y)
    var dimensions := Sim.WORLD * maxf(0.0, factor)
    return Rect2((size - dimensions) * 0.5, dimensions)


func to_map(world: Vector2) -> Vector2:
    var rect := map_rect()
    # The fixed camera looks from -Z: +X is screen-left, +Z is screen-up.
    return rect.position + (Vector2.ONE - world / Sim.WORLD) * rect.size


func to_world(point: Vector2) -> Vector2:
    var rect := map_rect()
    if rect.size.x <= 0 or rect.size.y <= 0:
        return Vector2.ZERO
    return ((Vector2.ONE - (point - rect.position) / rect.size) * Sim.WORLD).clamp(Vector2.ZERO, Sim.WORLD)


func rebuild_terrain() -> void:
    terrain_image = Image.create(Sim.GRID.x, Sim.GRID.y, false, Image.FORMAT_RGBA8)
    for y in range(Sim.GRID.y):
        for x in range(Sim.GRID.x):
            var point := (Vector2(x, y) + Vector2.ONE * 0.5) * Sim.CELL
            var height: float = host.sim.terrain.height_at(point)
            var color := Color("#a18153").lerp(Color("#d3b17a"), clampf(height / 240.0, 0.0, 1.0))
            if x > 0:
                var previous: float = host.sim.terrain.height_at(point - Vector2(Sim.CELL, 0))
                if absf(height - previous) > 20:
                    color = Color("#69533e")
            for obstacle: Rect2 in host.sim.obstacles:
                if obstacle.has_point(point):
                    color = Color("#655947")
                    break
            terrain_image.set_pixel(x, y, color)
    terrain_texture = ImageTexture.create_from_image(terrain_image)
    fog_image = Image.create(Sim.GRID.x, Sim.GRID.y, false, Image.FORMAT_RGBA8)
    fog_texture = ImageTexture.create_from_image(fog_image)
    map_identity = host.sim.terrain.get_instance_id()


func refresh_intel() -> void:
    markers.clear()
    if terrain_texture == null or map_identity != host.sim.terrain.get_instance_id():
        rebuild_terrain()
    var owner: int = host.local_slot
    var known: PackedByteArray = host.sim.explored.get(owner, PackedByteArray())
    var visible_cells: PackedByteArray = host.sim.visible.get(owner, PackedByteArray())
    for y in range(Sim.GRID.y):
        for x in range(Sim.GRID.x):
            var index := y * Sim.GRID.x + x
            var alpha := 0.0
            if owner != 0:
                alpha = 1.0 if index >= known.size() or known[index] == 0 else (0.62 if index >= visible_cells.size() or visible_cells[index] == 0 else 0.0)
            fog_image.set_pixel(x, y, Color(0.025, 0.04, 0.06, alpha))
    fog_texture.update(fog_image)
    for collection: Dictionary in [host.sim.units, host.sim.buildings]:
        for item: Dictionary in collection.values():
            if item.hp <= 0 or (item.owner != owner and not host.sim.can_see(owner, item.pos)):
                continue
            markers.append({"pos": item.pos, "color": Color("#44aeff") if item.owner == 1 else Color("#ff735a"), "building": item.has("queue")})
    for ore: Dictionary in host.sim.ores.values():
        if ore.amount > 0 and host.sim.can_see(owner, ore.pos):
            markers.append({"pos": ore.pos, "color": Color("#68e7f4"), "building": false})


func _process(delta: float) -> void:
    if host == null or not host.active:
        dragging = false
        return
    if host.menu_visible:
        dragging = false
    elapsed += delta
    if elapsed >= 0.1:
        elapsed = 0.0
        refresh_intel()
    view_polygon.clear()
    var rect: Rect2 = host._get_map_screen_rect()
    for point: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
        view_polygon.append(to_map(host._screen_to_world(point).clamp(Vector2.ZERO, Sim.WORLD)))
    if not view_polygon.is_empty():
        view_polygon.append(view_polygon[0])
    queue_redraw()


func move_camera(point: Vector2) -> void:
    host.camera_controller.focus = to_world(point)
    host._limit_camera()


func _gui_input(event: InputEvent) -> void:
    if not host.active or host.menu_visible or host.selection_dragging:
        return
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        dragging = event.pressed and not event.canceled and map_rect().has_point(event.position)
        if dragging:
            host.middle_dragging = false
            move_camera(event.position)
        accept_event()


func _input(event: InputEvent) -> void:
    if not dragging:
        return
    if event is InputEventMouseMotion:
        move_camera(get_global_transform_with_canvas().affine_inverse() * event.position)
        get_viewport().set_input_as_handled()
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
        dragging = false
        host.left_button_held = false
        get_viewport().set_input_as_handled()


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color("#070f19"))
    var rect := map_rect()
    if terrain_texture != null:
        # Keep CPU images in world-cell order; rotate both raster layers to
        # match to_map(), then restore local space for markers and the frame.
        draw_set_transform(rect.position + rect.end, 0.0, -Vector2.ONE)
        draw_texture_rect(terrain_texture, rect, false)
        draw_texture_rect(fog_texture, rect, false)
        draw_set_transform(Vector2.ZERO)
        for marker: Dictionary in markers:
            var radius := 3.0 if marker.building else 2.0
            draw_rect(Rect2(to_map(marker.pos) - Vector2.ONE * radius, Vector2.ONE * radius * 2), marker.color)
        if view_polygon.size() > 2:
            draw_polyline(view_polygon, Color("#c8e9ff"), 1.1, true)
    draw_rect(rect, Color("#58758b"), false, 1)
