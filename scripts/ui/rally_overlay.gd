extends Control
## Screen-space flags anchored to terrain. No collision or additional viewport.
var host
var entries: Array[Dictionary] = []


func configure(owner) -> void:
    host = owner
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    clip_contents = true
    z_index = -1


func _process(_delta: float) -> void:
    refresh()


func refresh() -> void:
    entries.clear()
    if host == null or not host.active or host.menu_visible or not host.selected_units.is_empty():
        queue_redraw()
        return
    var rect: Rect2 = host._get_map_screen_rect()
    position = rect.position
    size = rect.size
    var ids: Array[int] = host.selected_buildings.duplicate()
    if ids.is_empty() and host.selected_building >= 0:
        ids.append(host.selected_building)
    for id: int in ids:
        var building: Dictionary = host.sim.buildings.get(id, {})
        if building.is_empty() or building.owner != host.local_slot or building.hp <= 0 or building.rally_mode == "none":
            continue
        entries.append({"id": id, "from": host._world_to_screen(building.pos) - position,
            "to": host._world_to_screen(building.rally) - position,
            "active": id == host.active_building_id(), "ore": building.rally_mode == "ore"})
    queue_redraw()


func _draw() -> void:
    var factor: float = clampf(get_viewport_rect().size.y / 1080.0, 0.7, 1.5)
    for entry: Dictionary in entries:
        var color := Color("#6edbff") if entry.active else Color("#3c80b3")
        var target: Vector2 = entry.to
        draw_dashed_line(entry.from, target, Color(color, 0.7), 1.5 * factor, 9 * factor, true)
        draw_arc(target, 9 * factor, 0, TAU, 24, color, 2 * factor, true)
        var tip := target + Vector2(0, -34) * factor
        draw_line(target, tip, Color("#081b2a"), 5 * factor, true)
        draw_line(target, tip, color, 2 * factor, true)
        var flag := PackedVector2Array([tip, tip + Vector2(23, 3) * factor, tip + Vector2(17, 14) * factor, tip + Vector2(0, 12) * factor])
        draw_colored_polygon(flag, color)
        if entry.ore:
            draw_circle(tip + Vector2(9, 7) * factor, 3 * factor, Color("#123447"))
