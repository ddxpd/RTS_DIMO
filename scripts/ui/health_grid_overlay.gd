class_name HealthGridOverlay
extends Control

const HEALTH_PER_CELL := 10
const UNIT_TARGET_WIDTH := 72.0
const BUILDING_TARGET_WIDTH := 120.0
const CELL_GAP := 1.0
const UNIT_CELL_HEIGHT := 5.0
const BUILDING_CELL_HEIGHT := 6.0
const MIN_CELL_WIDTH := 1.5
const MAX_CELL_WIDTH := 7.0
const TEAM_COLORS := {
    1: Color("#5fa5e0"),
    2: Color("#d66551")
}

var host
var entries: Dictionary = {}


func configure(owner) -> void:
    host = owner
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    z_index = -1


func upsert_entity(
    key: String,
    world_position: Vector3,
    current_hp: int,
    max_hp: int,
    owner_id: int,
    category: String,
    visible: bool
) -> void:
    var safe_max_hp := maxi(1, max_hp)
    var cell_count := maxi(1, ceili(float(safe_max_hp) / float(HEALTH_PER_CELL)))
    var entry: Dictionary = entries.get(key, {})
    # Render interpolation changes the label position every frame, while HP
    # usually stays unchanged. Rebuild the cell fills only when HP changes.
    if entry.get("current_hp", -1) != current_hp or entry.get("max_hp", -1) != safe_max_hp:
        var cell_fractions: Array[float] = []
        for cell_index in range(cell_count):
            var cell_hp := clampf(float(current_hp - cell_index * HEALTH_PER_CELL) / float(HEALTH_PER_CELL), 0.0, 1.0)
            cell_fractions.append(cell_hp)
        entry.cell_fractions = cell_fractions
    entry.world_position = world_position
    entry.screen_position = host.camera.unproject_position(world_position)
    entry.current_hp = current_hp
    entry.max_hp = safe_max_hp
    entry.cell_count = cell_count
    entry.owner = owner_id
    entry.category = category
    entry.visible = visible and current_hp > 0
    entries[key] = entry
    queue_redraw()


func remove_entity(key: String) -> void:
    if entries.erase(key):
        queue_redraw()


func _draw() -> void:
    if host == null or host.camera == null:
        return
    var map_rect: Rect2 = host._get_map_screen_rect()
    for entry: Dictionary in entries.values():
        if not bool(entry.visible):
            continue
        var world_position: Vector3 = entry.world_position
        if host.camera.is_position_behind(world_position):
            continue
        var screen_position: Vector2 = entry.screen_position
        if not map_rect.has_point(screen_position):
            continue
        _draw_entry(screen_position, entry)


func _draw_entry(screen_position: Vector2, entry: Dictionary) -> void:
    var cell_count: int = entry.cell_count
    var target_width := BUILDING_TARGET_WIDTH if entry.category == "building" else UNIT_TARGET_WIDTH
    var cell_width := clampf(
        (target_width - CELL_GAP * float(cell_count - 1)) / float(cell_count),
        MIN_CELL_WIDTH,
        MAX_CELL_WIDTH
    )
    var cell_height := BUILDING_CELL_HEIGHT if entry.category == "building" else UNIT_CELL_HEIGHT
    var total_width := cell_width * float(cell_count) + CELL_GAP * float(cell_count - 1)
    var origin := screen_position - Vector2(total_width * 0.5, cell_height + 2.0)
    var border_rect := Rect2(origin - Vector2.ONE, Vector2(total_width + 2.0, cell_height + 2.0))
    draw_rect(border_rect, Color("#101815"))

    var fill_color: Color = TEAM_COLORS.get(int(entry.owner), Color("#9da7a1"))
    var fractions: Array[float] = entry.cell_fractions
    for cell_index in range(cell_count):
        var cell_position := origin + Vector2(float(cell_index) * (cell_width + CELL_GAP), 0)
        var cell_rect := Rect2(cell_position, Vector2(cell_width, cell_height))
        draw_rect(cell_rect, Color("#29352f"))
        var fill_fraction := fractions[cell_index]
        if fill_fraction > 0.0:
            draw_rect(
                Rect2(cell_position, Vector2(cell_width * fill_fraction, cell_height)),
                fill_color
            )
