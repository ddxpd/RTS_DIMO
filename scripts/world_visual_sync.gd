class_name WorldVisualSync
extends Node3D
const UnitVisualSync = preload("res://scripts/presentation/unit_visual_sync.gd")
const BuildingVisualSync = preload("res://scripts/presentation/building_visual_sync.gd")
const EffectVisualSync = preload("res://scripts/presentation/effect_visual_sync.gd")
const WorldOverlaySync = preload("res://scripts/presentation/world_overlay_sync.gd")

const EntityVisual = preload("res://assets/art/entity_visual.gd")
const HealthGridOverlay = preload("res://scripts/ui/health_grid_overlay.gd")
const BuildFootprintOverlay = preload("res://scripts/ui/build_footprint_overlay.gd")

const SELECTION_RING_PROFILES := {
    "mobile_infantry": {"radius_multiplier": 1.25, "radius_override": -1.0, "margin": 0.0},
    "soldier": {"radius_multiplier": 1.25, "radius_override": -1.0, "margin": 0.0},
    "harvester": {"radius_multiplier": 1.25, "radius_override": -1.0, "margin": 0.0},
    "base": {"radius_multiplier": 1.0, "radius_override": -1.0, "margin": 4.0},
    "barracks": {"radius_multiplier": 1.0, "radius_override": -1.0, "margin": 4.0},
    "refinery": {"radius_multiplier": 1.0, "radius_override": -1.0, "margin": 4.0},
    "bunker": {"radius_multiplier": 1.0, "radius_override": -1.0, "margin": 4.0}
}

var host
var _dot_texture: ImageTexture
var last_fog_key := ""

var unit_visuals: Dictionary = {}
var building_visuals: Dictionary = {}
var ore_visuals: Dictionary = {}
var effect_visuals: Dictionary = {}
var mobile_deaths: Array[Dictionary] = []
var marker_visuals: Dictionary = {}
var health_grid_overlay: HealthGridOverlay
var selection_rect_overlay: Panel
var build_preview_model: EntityVisual
var footprint_overlay: BuildFootprintOverlay
var deployment_preview_error := ""


func _selection_ring_radius(kind: String, base_radius: float, footprint_size: Vector2 = Vector2.ZERO) -> float:
    var profile: Dictionary = SELECTION_RING_PROFILES.get(kind, {})
    var radius_override := float(profile.get("radius_override", -1.0))
    if radius_override >= 0.0:
        return maxf(radius_override, 1.0)

    var margin := float(profile.get("margin", 0.0))
    if footprint_size.length_squared() > 0.0:
        var half_diagonal := sqrt(pow(footprint_size.x * 0.5, 2.0) + pow(footprint_size.y * 0.5, 2.0))
        return maxf(half_diagonal + margin, 1.0)

    var multiplier := float(profile.get("radius_multiplier", 1.0))
    return maxf(base_radius * multiplier + margin, 1.0)

func configure(owner) -> void:
    host = owner


func _ensure_health_grid_overlay() -> void:
    if health_grid_overlay != null:
        return
    health_grid_overlay = HealthGridOverlay.new()
    health_grid_overlay.name = "HealthGridOverlay"
    health_grid_overlay.configure(host)
    host.hud.add_child(health_grid_overlay)

func sync(delta: float = 0.0) -> void:
    _ensure_health_grid_overlay()
    _sync_ores()
    _sync_buildings(delta)
    _sync_units(delta)
    _sync_mobile_deaths(delta)
    _sync_effects(delta)
    _sync_markers()
    _sync_selection_rect()
    _sync_build_preview()
    _sync_fog()

func _set_visual_visible(visual: EntityVisual, next_visible: bool) -> void:
    visual.visible = next_visible
    if visual.animation_player != null:
        visual.animation_player.active = next_visible and visual.kind != "soldier"

func _sync_ores() -> void:
    BuildingVisualSync._sync_ores(self)

func _sync_buildings(delta: float = 0.0) -> void:
    BuildingVisualSync._sync_buildings(self, delta)

func _sync_units(delta: float = 0.0) -> void:
    UnitVisualSync._sync_units(self, delta)

func _sync_mobile_deaths(delta: float) -> void:
    UnitVisualSync._sync_mobile_deaths(self, delta)

func _unit_animation_state(u: Dictionary) -> String:
    return UnitVisualSync._unit_animation_state(self, u)

func _unit_destination(u: Dictionary) -> Vector2:
    return UnitVisualSync._unit_destination(self, u)

func _harvester_returning(u: Dictionary) -> bool:
    return UnitVisualSync._harvester_returning(self, u)

func _harvester_refinery(u: Dictionary) -> Dictionary:
    return UnitVisualSync._harvester_refinery(self, u)

func _nearest_refinery_position(u: Dictionary) -> Vector2:
    return UnitVisualSync._nearest_refinery_position(self, u)

func _unit_in_attack_range(u: Dictionary) -> bool:
    return UnitVisualSync._unit_in_attack_range(self, u)

func _unit_heading(u: Dictionary, id: int) -> Vector2:
    return UnitVisualSync._unit_heading(self, u, id)

func _has_combat_target(u: Dictionary) -> bool:
    return UnitVisualSync._has_combat_target(self, u)

func _soldier_heading(u: Dictionary, id: int, vis: Dictionary) -> Vector2:
    return UnitVisualSync._soldier_heading(self, u, id, vis)

func _white_dot() -> ImageTexture:
    if _dot_texture == null:
        var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
        img.fill(Color.WHITE)
        _dot_texture = ImageTexture.create_from_image(img)
    return _dot_texture


# Create a status bar (bg + fill) as billboarded Sprite3D pair above a unit.
func _make_status_bar(width: float, height: float, fill_color: Color) -> Node3D:
    var holder := Node3D.new()
    var bg := Sprite3D.new()
    bg.texture = _white_dot()
    bg.pixel_size = 1.0
    bg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    bg.shaded = false
    bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    bg.modulate = Color("#182219")
    bg.scale = Vector3(width / 8.0, height / 8.0, 1)
    holder.add_child(bg)
    var fill := Sprite3D.new()
    fill.texture = _white_dot()
    fill.pixel_size = 1.0
    fill.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    fill.shaded = false
    fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    fill.modulate = fill_color
    fill.scale = Vector3(width / 8.0, height / 8.0, 1)
    fill.position.z = -0.5
    holder.add_child(fill)
    holder.set_meta("fill", fill)
    holder.set_meta("width", width)
    return holder

func _update_status_bar(holder: Node3D, fraction: float, color: Color = Color.TRANSPARENT) -> void:
    var fill: Sprite3D = holder.get_meta("fill")
    var width: float = holder.get_meta("width")
    fill.scale.x = maxf(0.01, width / 8.0 * clampf(fraction, 0.0, 1.0))
    if color != Color.TRANSPARENT:
        fill.modulate = color

func _sync_effects(delta: float = 0.0) -> void:
    EffectVisualSync._sync_effects(self, delta)

func _sync_markers() -> void:
    WorldOverlaySync._sync_markers(self)

func _sync_selection_rect() -> void:
    WorldOverlaySync._sync_selection_rect(self)

func _sync_build_preview(position_override: Variant = null) -> void:
    WorldOverlaySync._sync_build_preview(self, position_override)

func _hide_build_preview() -> void:
    WorldOverlaySync._hide_build_preview(self)

func _show_build_site(kind: String, pos: Vector2, rect: Rect2, error: String, cells: Array = [], excluded_id: int = -1) -> void:
    WorldOverlaySync._show_build_site(self, kind, pos, rect, error, cells, excluded_id)

func _ghost_preview(node: Node) -> void:
    WorldOverlaySync._ghost_preview(self, node)

func _sync_deploy_preview(position_override: Variant = null) -> void:
    WorldOverlaySync._sync_deploy_preview(self, position_override)

func _sync_fog() -> void:
    WorldOverlaySync._sync_fog(self)

func _surface_rotation(point: Vector2) -> Vector3:
    var gradient: Vector2 = host.sim.terrain.gradient_at(point)
    return Vector3(-atan(gradient.y), 0.0, atan(gradient.x))

func reset_world() -> void:
    last_fog_key = ""
    if footprint_overlay != null:
        footprint_overlay.reset()
        footprint_overlay.queue_free()
        footprint_overlay = null
    for child in get_children():
        child.free()
    unit_visuals.clear()
    building_visuals.clear()
    ore_visuals.clear()
    effect_visuals.clear()
    mobile_deaths.clear()
    marker_visuals.clear()
    build_preview_model = null
    deployment_preview_error = ""
    host.deploy_building = -1
    if health_grid_overlay != null:
        health_grid_overlay.entries.clear()
        health_grid_overlay.queue_redraw()


func _harvester_heading(u: Dictionary, id: int) -> Vector2:
    return UnitVisualSync._harvester_heading(self, u, id)
