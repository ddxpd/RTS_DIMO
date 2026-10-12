extends RefCounted
## Stateless presentation operations; WorldVisualSync owns node lifetime and caches.
const Simulation = preload("res://scripts/simulation.gd")
const EntityVisual = preload("res://assets/art/entity_visual.gd")
const DestinationMarker = preload("res://scripts/ui/destination_marker.gd")
const BuildFootprintOverlay = preload("res://scripts/ui/build_footprint_overlay.gd")


static func _sync_markers(context: WorldVisualSync) -> void:
    var seen := {}
    for click: Dictionary in context.host.clicks:
        var key := "click_%d" % int(click.id)
        var animated: bool = click.action in ["move", "attack", "attack_move"]
        if not context.marker_visuals.has(key):
            if animated:
                var marker := DestinationMarker.new()
                marker.configure(click.action, click.pos)
                marker.position.y += context.host.sim.terrain.height_at(click.pos)
                marker.rotation = context._surface_rotation(click.pos)
                context.add_child(marker)
                context.marker_visuals[key] = marker
            else:
                var sprite := Sprite3D.new()
                sprite.pixel_size = 3.0
                sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
                sprite.shaded = false
                sprite.texture = context._white_dot()
                sprite.position = Vector3((click.pos as Vector2).x, context.host.sim.terrain.height_at(click.pos) + 5, (click.pos as Vector2).y)
                context.add_child(sprite)
                context.marker_visuals[key] = sprite
        if animated:
            var marker: DestinationMarker = context.marker_visuals[key]
            marker.set_age(float(click.duration) - float(click.life))
        else:
            var sprite: Sprite3D = context.marker_visuals[key]
            sprite.modulate = Color("#ffc359", clampf(float(click.life) / float(click.duration), 0.0, 1.0))
        seen[key] = true
    for key: String in context.marker_visuals.keys():
        if not seen.has(key):
            context.marker_visuals[key].queue_free()
            context.marker_visuals.erase(key)


static func _sync_selection_rect(context: WorldVisualSync) -> void:
    if context.host.selection_dragging:
        var start_screen: Vector2 = context.host._world_to_screen(context.host.selection_start)
        var end_screen: Vector2 = context.host._world_to_screen(context.host.selection_current)
        var rect := Rect2(start_screen, end_screen - start_screen).abs()
        if context.selection_rect_overlay == null:
            context.selection_rect_overlay = Panel.new()
            var style := StyleBoxFlat.new()
            style.bg_color = Color(0.7, 1, 0.5, 0.15)
            style.border_color = Color("#c5e79d")
            style.set_border_width_all(1)
            context.selection_rect_overlay.add_theme_stylebox_override("panel", style)
            context.selection_rect_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
            context.host.hud.add_child(context.selection_rect_overlay)
        context.selection_rect_overlay.position = rect.position
        context.selection_rect_overlay.size = rect.size
        context.selection_rect_overlay.visible = true
    elif context.selection_rect_overlay != null:
        context.selection_rect_overlay.visible = false


static func _sync_build_preview(context: WorldVisualSync, position_override: Variant = null) -> void:
    if context.host.deploy_building >= 0 and (not context.host.sim.buildings.has(context.host.deploy_building) or Simulation.BarracksFlight.state(context.host.sim.buildings[context.host.deploy_building]) != "airborne" or context.host.sim.winner != 0):
        context.host.deploy_building = -1
    var active: bool = context.host.active and not context.host.menu_visible and context.host.sim.winner == 0
    if not active or (context.host.deploy_building < 0 and context.host.build_mode.is_empty()):
        _hide_build_preview(context)
        return
    if position_override == null and not context.host._get_map_screen_rect().has_point(context.get_viewport().get_mouse_position()):
        _hide_build_preview(context)
        return
    if context.host.deploy_building >= 0:
        _sync_deploy_preview(context, position_override)
        return
    var point: Vector2 = position_override if position_override is Vector2 else context.host._screen_to_world(context.get_viewport().get_mouse_position())
    var pos: Vector2 = context.host.sim.snap_building(context.host.build_mode, point)
    var error: String = context.host.sim.build_error(context.host.local_slot, context.host.build_mode, pos)
    _show_build_site(context, context.host.build_mode, pos, context.host.sim.placement_bounds(context.host.build_mode, pos), error)


static func _hide_build_preview(context: WorldVisualSync) -> void:
    if context.build_preview_model != null:
        context.build_preview_model.visible = false
    if context.footprint_overlay != null:
        context.footprint_overlay.clear()
    context.deployment_preview_error = ""


static func _show_build_site(context: WorldVisualSync, kind: String, pos: Vector2, rect: Rect2, error: String, cells: Array = [], excluded_id: int = -1) -> void:
    if context.footprint_overlay == null:
        context.footprint_overlay = BuildFootprintOverlay.new()
        context.footprint_overlay.name = "BuildFootprintOverlay"
        context.footprint_overlay.configure(context.host, context)
        context.host.hud.add_child(context.footprint_overlay)
    if context.build_preview_model != null and context.build_preview_model.kind != kind:
        context.build_preview_model.visible = false
        context.build_preview_model.queue_free()
        context.build_preview_model = null
    if context.build_preview_model == null:
        context.build_preview_model = EntityVisual.new(kind, context.host.local_slot)
        context.add_child(context.build_preview_model)
        _ghost_preview(context, context.build_preview_model)
    context.build_preview_model.visible = true
    context.build_preview_model.set_position_2d(pos, context.host.sim.terrain.height_at(pos))
    context.build_preview_model.set_animation("idle")
    context.footprint_overlay.show_site(rect, error, cells, excluded_id, context.host.sim.placement_rects(kind, pos))


static func _ghost_preview(context: WorldVisualSync, node: Node) -> void:
    if node is GeometryInstance3D:
        node.transparency = 0.6
        node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    if node is Light3D:
        node.light_energy = 0.0
    for child in node.get_children():
        _ghost_preview(context, child)


static func _sync_deploy_preview(context: WorldVisualSync, position_override: Variant = null) -> void:
    var position: Vector2 = position_override if position_override is Vector2 else context.host._screen_to_world(context.get_viewport().get_mouse_position())
    var site: Dictionary = context.host.sim.deployment_site(context.host.local_slot, context.host.deploy_building, position)
    context.deployment_preview_error = site.error
    _show_build_site(context, "barracks", site.pos, site.rect, site.error, site.cells, context.host.deploy_building)


static func _sync_fog(context: WorldVisualSync) -> void:
    var key := "%d:%d:%d" % [context.host.sim.match_id, context.host.local_slot, int(context.host.sim.frame / 4)]
    if key == context.last_fog_key:
        return
    context.last_fog_key = key
    if context.host.local_slot in [1, 2]:
        for y in range(Simulation.GRID.y):
            for x in range(Simulation.GRID.x):
                var index := y * Simulation.GRID.x + x
                if context.host.sim.visible[context.host.local_slot][index] == 0:
                    var alpha := 0.62 if context.host.sim.explored[context.host.local_slot][index] == 1 else 1.0
                    context.host.fog_image.set_pixel(x, y, Color(0.035, 0.055, 0.055, alpha))
                else:
                    context.host.fog_image.set_pixel(x, y, Color(0, 0, 0, 0))
        context.host.fog_texture.update(context.host.fog_image)
