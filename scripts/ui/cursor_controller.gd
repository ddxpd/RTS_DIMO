extends Node
## Local presentation only: never sends orders or mutates simulation state.
const STATES := [&"default", &"select", &"move", &"attack", &"blocked"]
const HOTSPOTS := {
    &"default": Vector2(9, 6), &"select": Vector2(9, 8),
    &"move": Vector2(11, 10), &"attack": Vector2(20, 20),
    &"blocked": Vector2(13, 9)
}

var host
var textures: Dictionary = {}
var current_state: StringName = &""
var hardware_updates := 0


func configure(owner) -> void:
    host = owner
    for state: StringName in STATES:
        textures[state] = load("res://assets/ui/cursors/%s.png" % state)


func _ready() -> void:
    get_window().focus_exited.connect(_focus_exited)
    get_window().focus_entered.connect(_focus_entered)
    apply_state(&"default")


func _exit_tree() -> void:
    restore_system_cursor()


func restore_system_cursor() -> void:
    if DisplayServer.get_name() != "headless":
        Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
    current_state = &""


func _focus_exited() -> void:
    apply_state(&"default")


func _focus_entered() -> void:
    current_state = &""
    update_cursor()


func apply_state(state: StringName) -> void:
    if current_state == state:
        return
    current_state = state
    if DisplayServer.get_name() != "headless":
        Input.set_custom_mouse_cursor(textures[state], Input.CURSOR_ARROW, HOTSPOTS[state])
        hardware_updates += 1


func update_cursor() -> void:
    if DisplayServer.get_name() != "headless" and not get_window().has_focus():
        apply_state(&"default")
        return
    var screen: Vector2 = host.get_viewport().get_mouse_position()
    var hovered: Control = host.get_viewport().gui_get_hovered_control()
    var over_ui := hovered != null and hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE
    apply_state(state_at(screen, over_ui))


func has_units(kind: String = "") -> bool:
    for id: int in host.selected_units:
        if not host.sim.units.has(id):
            continue
        var unit: Dictionary = host.sim.units[id]
        if unit.owner == host.local_slot and unit.hp > 0 and (kind.is_empty() or unit.type == kind):
            return true
    return false


func has_buildings() -> bool:
    var ids: Array = host.selected_buildings.duplicate()
    if host.selected_building >= 0 and not ids.has(host.selected_building):
        ids.append(host.selected_building)
    for id: int in ids:
        if host.sim.buildings.has(id):
            var building: Dictionary = host.sim.buildings[id]
            if building.owner == host.local_slot and building.hp > 0:
                return true
    return false


func target_at(pos: Vector2, friendly_only: bool = false, enemies_only: bool = false) -> Dictionary:
    # Match existing input priority: units before buildings, insertion order.
    for kind: String in ["unit", "building"]:
        var collection: Dictionary = host.sim.units if kind == "unit" else host.sim.buildings
        for id: int in collection:
            var entity: Dictionary = collection[id]
            var friendly: bool = entity.owner == host.local_slot
            if entity.hp <= 0 or (friendly_only and not friendly) or (enemies_only and friendly):
                continue
            if not friendly and not host.sim.can_see(host.local_slot, entity.pos):
                continue
            var hit: bool
            if kind == "unit":
                var distance: float = (entity.pos as Vector2).distance_to(pos)
                hit = distance <= 20.0 if friendly_only else (distance < 24.0 if enemies_only else distance <= 24.0)
            else:
                hit = host.sim.footprint(entity).has_point(pos)
            if hit:
                return {"kind": kind, "id": id}
    return {}


func ore_at(pos: Vector2) -> bool:
    for ore: Dictionary in host.sim.ores.values():
        if ore.amount > 0 and (ore.pos as Vector2).distance_to(pos) < 38.0:
            return true
    return false


func state_at(screen: Vector2, over_ui: bool = false) -> StringName:
    if over_ui or not host.active or host.menu_visible or host.local_slot == 0 or host.sim.winner != 0:
        return &"default"
    if not host.get_viewport().get_visible_rect().has_point(screen) or not host._screen_is_map(screen):
        return &"default"
    var pos: Vector2 = host._screen_to_world(screen)
    return world_state(pos)


func world_state(pos: Vector2) -> StringName:
    if not pos.is_finite() or not Rect2(Vector2.ZERO, host.sim.WORLD).has_point(pos):
        return &"blocked" if has_units() or has_buildings() or not host.build_mode.is_empty() else &"default"
    if not host.build_mode.is_empty():
        return &"default" if host.sim.build_error(host.local_slot, host.build_mode, pos).is_empty() else &"blocked"
    if not host.pending_command.is_empty():
        if host.pending_command == "gather":
            return &"move" if has_units("harvester") and ore_at(pos) else &"blocked"
        return &"move" if has_units() else &"blocked"
    if host.attack_mode:
        if not has_units():
            return &"blocked"
        # Force-attack on friendlies remains valid; invisible enemies are not inspected.
        return &"blocked" if not target_at(pos).is_empty() and not has_units("soldier") else &"attack"
    if host.selection_dragging:
        return &"default"
    if not target_at(pos, true).is_empty():
        return &"select"
    if has_units():
        # Existing right-click gives a mine precedence over an overlapping enemy.
        if ore_at(pos):
            return &"move" if has_units("harvester") else &"blocked"
        if not target_at(pos, false, true).is_empty():
            return &"attack" if has_units("soldier") else &"blocked"
        return &"move"
    return &"move" if has_buildings() else &"default"
