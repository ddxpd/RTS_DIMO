extends Node3D

const Simulation = preload("res://scripts/simulation.gd")
const EntityVisual = preload("res://assets/art/entity_visual.gd")
const BULLET_SCENE = preload("res://assets/models/bullet.glb")
const HealthGridOverlay = preload("res://scripts/ui/health_grid_overlay.gd")
const DestinationMarker = preload("res://scripts/ui/destination_marker.gd")

const SELECTION_RING_PROFILES := {
    "soldier": {"radius_multiplier": 1.25, "radius_override": -1.0, "margin": 0.0},
    "harvester": {"radius_multiplier": 1.25, "radius_override": -1.0, "margin": 0.0},
    "base": {"radius_multiplier": 1.0, "radius_override": -1.0, "margin": 4.0},
    "barracks": {"radius_multiplier": 1.0, "radius_override": -1.0, "margin": 4.0},
    "refinery": {"radius_multiplier": 1.0, "radius_override": -1.0, "margin": 4.0},
    "bunker": {"radius_multiplier": 1.0, "radius_override": -1.0, "margin": 4.0}
}

var host
var last_fog_key := ""

var unit_visuals: Dictionary = {}
var building_visuals: Dictionary = {}
var ore_visuals: Dictionary = {}
var rock_visuals: Array[EntityVisual] = []
var effect_visuals: Dictionary = {}
var marker_visuals: Dictionary = {}
var health_grid_overlay: HealthGridOverlay
var selection_rect_overlay: Panel
var build_preview_visual: MeshInstance3D
var build_preview_model: EntityVisual
var deploy_cells: Array[MeshInstance3D] = []
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
    _sync_rocks()
    _sync_ores()
    _sync_buildings(delta)
    _sync_units(delta)
    _sync_effects()
    _sync_markers()
    _sync_selection_rect()
    _sync_build_preview()
    _sync_fog()

func _set_visual_visible(visual: EntityVisual, next_visible: bool) -> void:
    visual.visible = next_visible
    if visual.animation_player != null:
        visual.animation_player.active = next_visible and visual.kind != "soldier"

func _sync_rocks() -> void:
    if host.sim.map_id != "prototype":
        return
    if rock_visuals.is_empty():
        # Tile rock clusters across each obstacle footprint.
        var rock_index := 0
        for rock: Rect2 in host.sim.obstacles:
            var spacing := 72.0
            var cols := maxi(1, int(rock.size.x / spacing))
            var rows := maxi(1, int(rock.size.y / spacing))
            for cx in range(cols):
                for cy in range(rows):
                    var pos := Vector2(
                        rock.position.x + (cx + 0.5) * rock.size.x / cols,
                        rock.position.y + (cy + 0.5) * rock.size.y / rows
                    )
                    var variation_key := "%d_%d_%d" % [rock_index, cx, cy]
                    var jitter := _deterministic_rock_jitter(variation_key)
                    var scale_factor := _deterministic_rock_scale(variation_key)
                    var visual := EntityVisual.new("rock", 1)
                    visual.set_position_2d(pos + jitter)
                    visual.scale = Vector3.ONE * scale_factor
                    add_child(visual)
                    rock_visuals.append(visual)
            rock_index += 1

    # Fog: rocks only show in explored terrain (permanent reveal, like terrain).
    for visual: EntityVisual in rock_visuals:
        var cell := Vector2i((Vector2(visual.position.x, visual.position.z) / Simulation.CELL).floor()).clamp(Vector2i.ZERO, Vector2i(Simulation.GRID.x - 1, Simulation.GRID.y - 1))
        var index := cell.y * Simulation.GRID.x + cell.x
        var explored: PackedByteArray = host.sim.explored.get(host.local_slot, PackedByteArray())
        visual.visible = index >= 0 and index < explored.size() and explored[index] == 1


func _deterministic_rock_jitter(variation_key: String) -> Vector2:
    var x := float(absi(hash(variation_key + "_x")) % 29) - 14.0
    var y := float(absi(hash(variation_key + "_y")) % 29) - 14.0
    return Vector2(x, y)


func _deterministic_rock_scale(variation_key: String) -> float:
    return 0.72 + float(absi(hash(variation_key + "_scale")) % 39) / 100.0


func _sync_ores() -> void:
    var seen := {}
    for id: int in host.sim.ores:
        var ore: Dictionary = host.sim.ores[id]
        if not ore_visuals.has(id):
            var visual := EntityVisual.new("ore", 1)
            visual.name = "Ore%d" % id
            visual.set_position_2d(ore.pos, host.sim.terrain.height_at(ore.pos))
            add_child(visual)
            if host.sim.map_id in ["desert_quarry", "desert_sample"]:
                for entry in visual._materials:
                    entry.material.emission_enabled = false
                    entry.material.metallic = 0.0
                    entry.material.roughness = 0.9
                    entry.material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
                    entry.material.albedo_color = Color("#b69a63")
                    entry.base_color = entry.material.albedo_color
            var label := Label3D.new()
            label.text = str(ore.amount)
            label.font_size = 32
            label.pixel_size = 0.02
            label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
            label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            label.position = Vector3(0, visual.get_model_height() + 8, 0)
            visual.add_child(label)
            ore_visuals[id] = {"visual": visual, "label": label}
        var vis: Dictionary = ore_visuals[id]
        var visual: EntityVisual = vis.visual

        # Fog of war: only render ores the local player can currently see.
        _set_visual_visible(visual, ore.amount > 0 and host.sim.can_see(host.local_slot, ore.pos))
        visual.set_position_2d(ore.pos, host.sim.terrain.height_at(ore.pos))
        var label: Label3D = vis.label
        if int(vis.get("last_amount", -1)) != ore.amount:
            label.text = str(ore.amount)
            vis["last_amount"] = ore.amount
        seen[id] = true
    for id: int in ore_visuals.keys():
        if not seen.has(id):
            ore_visuals[id].visual.queue_free()
            ore_visuals.erase(id)


func _sync_buildings(delta: float = 0.0) -> void:
    var seen := {}
    for id: int in host.sim.buildings:
        var b: Dictionary = host.sim.buildings[id]
        if not building_visuals.has(id):
            var visual := EntityVisual.new(b.type, b.owner)
            visual.name = "Building%d" % id
            visual.set_position_2d(b.pos, host.sim.terrain.height_at(b.pos))
            add_child(visual)
            building_visuals[id] = {"visual": visual}
        var vis: Dictionary = building_visuals[id]
        var visual: EntityVisual = vis.visual

        # Fog: enemy buildings only render when currently visible.
        _set_visual_visible(visual, b.owner == host.local_slot or host.sim.can_see(host.local_slot, b.pos))
        var ground: float = host.sim.terrain.height_at(b.pos)
        var height: float = b.get("flight", {}).get("height", ground)
        var target := Vector3(b.pos.x, height, b.pos.y)
        if b.has("flight") and delta > 0 and visual.position.distance_to(target) < 300:
            visual.position = visual.position.lerp(target, 1.0 - exp(-18.0 * delta))
        else:
            visual.position = target
        visual.set_flash(b.flash > 0)
        visual.set_construction_tint(b.remaining > 0)
        if b.remaining > 0:
            visual.set_animation("construction")
            var build_time: int = Simulation.BUILD_TYPES[b.type].time
            visual.set_construction_progress(
                1.0 - float(b.remaining) / float(build_time),
                float(build_time) / float(Simulation.TICK)
            )
        elif b.type == "bunker" and int(b.cooldown) > 4:
            visual.set_animation("fire")
        elif not b.queue.is_empty() and b.type in ["barracks", "refinery"]:
            visual.set_animation("active")
        else:
            visual.set_animation("idle")
        if b.has("flight") and visual.barracks_motion != null:
            if int(vis.get("flight_frame", -1)) != host.sim.frame:
                vis.flight_frame = host.sim.frame
                vis.flight_elapsed = 0.0
            else:
                vis.flight_elapsed = minf(float(vis.get("flight_elapsed", 0.0)) + delta, 0.2)
            visual.barracks_motion.apply(b.flight, float(vis.get("flight_elapsed", 0.0)) * Simulation.TICK)

        var building_selected: bool = host.selected_buildings.has(id) or host.selected_building == id
        var building_size: Vector2 = Simulation.BUILD_TYPES[b.type].size
        var building_radius := _selection_ring_radius(b.type, maxf(building_size.x, building_size.y) * 0.5, building_size)
        visual.set_selected(building_selected and visual.visible, building_radius)
        if visual.selection_ring != null:
            visual.selection_ring.position.y = ground - visual.position.y + 0.6

        health_grid_overlay.upsert_entity(
            "building_%d" % id,
            visual.global_position + Vector3(0, visual.get_model_height() + 12, 0),
            int(b.hp),
            int(Simulation.BUILD_TYPES[b.type].hp),
            int(b.owner),
            "building",
            visual.visible
        )
        if b.remaining > 0:
            if not vis.has("build_bar"):
                var build_bar := _make_status_bar(Simulation.BUILD_TYPES[b.type].size.x * 0.8, 5, Color("#eac75b"))
                build_bar.position = Vector3(0, visual.get_model_height() + 20, 0)
                visual.add_child(build_bar)
                vis["build_bar"] = build_bar
            _update_status_bar(vis.build_bar, 1.0 - float(b.remaining) / Simulation.BUILD_TYPES[b.type].time)
        seen[id] = true
    for id: int in building_visuals.keys():
        if not seen.has(id):
            health_grid_overlay.remove_entity("building_%d" % id)
            building_visuals[id].visual.queue_free()
            building_visuals.erase(id)


func _sync_units(delta: float = 0.0) -> void:
    var seen := {}
    for id: int in host.sim.units:
        var u: Dictionary = host.sim.units[id]
        if not unit_visuals.has(id):
            var visual := EntityVisual.new(u.type, u.owner)
            visual.name = "Unit%d" % id
            visual.set_position_2d(u.pos, host.sim.terrain.height_at(u.pos))
            add_child(visual)
            unit_visuals[id] = {"visual": visual}
        var vis: Dictionary = unit_visuals[id]
        var visual: EntityVisual = vis.visual

        # Fog: enemy units only render when currently visible.
        _set_visual_visible(visual, u.owner == host.local_slot or host.sim.can_see(host.local_slot, u.pos))
        if u.type != "soldier":
            visual.set_position_2d(u.pos, host.sim.terrain.height_at(u.pos))
        visual.set_flash(u.flash > 0)
        visual.set_heading(_unit_heading(u, id), u.type == "soldier" and not _has_combat_target(u))
        visual.set_animation(_unit_animation_state(u))
        if u.type == "soldier" and (delta > 0.0 or not visual.soldier_motion.initialized
                or u.pos != visual.soldier_motion.current):
            var guest: bool = host.connected and not host.is_host
            var velocity: Vector2 = host.render_velocities.get(id, Vector2.ZERO)
            if u.order == "idle" or visual.animation_state == "attack":
                velocity = Vector2.ZERO
            var aim := _unit_destination(u) - (u.pos as Vector2) if _has_combat_target(u) else Vector2.ZERO
            visual.soldier_motion.sample(u.pos, delta, host.sim.frame, host.accumulator * Simulation.TICK,
                host.sim.terrain, guest, velocity, aim)
            visual.set_soldier_shadow_distance(host.camera.global_position)
        var unit_selected: bool = host.selected_units.has(id)
        var unit_radius := _selection_ring_radius(u.type, float(Simulation.UNIT_TYPES[u.type].radius))
        visual.set_selected(unit_selected and visual.visible, unit_radius)
        if visual.selection_ring != null:
            visual.selection_ring.global_rotation = _surface_rotation(Vector2(visual.position.x, visual.position.z))
        health_grid_overlay.upsert_entity(
            "unit_%d" % id,
            visual.global_position + Vector3(0, visual.get_model_height() + 12, 0),
            int(u.hp),
            int(Simulation.UNIT_TYPES[u.type].hp),
            int(u.owner),
            "unit",
            visual.visible
        )

        # Cargo bar for harvesters (reset when cargo drops to 0).
        if u.type == "harvester":
            if u.cargo > 0:
                if not vis.has("cargo_bar"):
                    var cargo_bar := _make_status_bar(30, 4, Color("#eac75b"))
                    cargo_bar.position = Vector3(0, visual.get_model_height() + 20, 0)
                    visual.add_child(cargo_bar)
                    vis["cargo_bar"] = cargo_bar
                _update_status_bar(vis.cargo_bar, float(u.cargo) / 60.0)
                vis.cargo_bar.visible = true
            elif vis.has("cargo_bar"):
                vis.cargo_bar.visible = false
        seen[id] = true
    for id: int in unit_visuals.keys():
        if not seen.has(id):
            health_grid_overlay.remove_entity("unit_%d" % id)
            unit_visuals[id].visual.queue_free()
            unit_visuals.erase(id)


func _unit_animation_state(u: Dictionary) -> String:
    if u.order in ["attack", "attack_move"] and int(u.attack_id) >= 0:
        return "attack" if _unit_in_attack_range(u) else "move"
    if u.order in ["move", "attack_move"]:
        return "move"
    if u.type == "harvester" and u.order == "gather":
        var destination := _unit_destination(u)
        var near_target := (u.pos as Vector2).distance_to(destination) <= (46.0 if int(u.cargo) < 60 else 44.0)
        if near_target:
            return "unload" if int(u.cargo) > 0 else "mine"
        return "move"
    return "idle"


func _unit_destination(u: Dictionary) -> Vector2:
    if u.order in ["attack", "attack_move"] and int(u.attack_id) >= 0:
        if u.attack_kind == "unit" and host.sim.units.has(int(u.attack_id)):
            return host.sim.units[int(u.attack_id)].pos
        if u.attack_kind == "building" and host.sim.buildings.has(int(u.attack_id)):
            return host.sim.buildings[int(u.attack_id)].pos
    if u.order == "gather" and u.type == "harvester":
        if int(u.cargo) >= 60:
            return _nearest_refinery_position(u)
        if host.sim.ores.has(int(u.ore)):
            return host.sim.ores[int(u.ore)].pos
    return u.target


func _nearest_refinery_position(u: Dictionary) -> Vector2:
    var best_position: Vector2 = u.pos
    var best_distance := INF
    for building: Dictionary in host.sim.buildings.values():
        var refinery: bool = building.type == "refinery" and building.owner == u.owner and building.remaining == 0
        var distance: float = (u.pos as Vector2).distance_to(building.pos) if refinery else INF
        if distance < best_distance:
            best_distance = distance
            best_position = building.pos
    return best_position


func _unit_in_attack_range(u: Dictionary) -> bool:
    var target_position: Vector2 = u.pos
    if u.attack_kind == "unit" and host.sim.units.has(int(u.attack_id)):
        target_position = host.sim.units[int(u.attack_id)].pos
    elif u.attack_kind == "building" and host.sim.buildings.has(int(u.attack_id)):
        var footprint: Rect2 = host.sim.footprint(host.sim.buildings[int(u.attack_id)])
        target_position = (u.pos as Vector2).clamp(footprint.position, footprint.end)
    else:
        return false
    return (u.pos as Vector2).distance_to(target_position) <= float(Simulation.UNIT_TYPES[u.type].range)


func _unit_heading(u: Dictionary, id: int) -> Vector2:
    if u.type == "soldier":
        return _soldier_heading(u, id, unit_visuals[id])
    var destination := _unit_destination(u)
    var heading := destination - (u.pos as Vector2)
    if heading.length_squared() > 1.0:
        return heading
    if host.render_velocities.has(id):
        return host.render_velocities[id]
    return Vector2.UP


func _has_combat_target(u: Dictionary) -> bool:
    if u.order not in ["attack", "attack_move"]:
        return false
    if u.attack_kind == "unit":
        return host.sim.units.has(int(u.attack_id))
    if u.attack_kind == "building":
        return host.sim.buildings.has(int(u.attack_id))
    return false


func _soldier_heading(u: Dictionary, id: int, vis: Dictionary) -> Vector2:
    var position: Vector2 = u.pos
    var motion := position - (vis.get("last_position", position) as Vector2)
    vis.last_position = position
    var forward: Vector3 = vis.visual.get_visual_forward()
    var heading: Vector2 = vis.get("last_heading", Vector2(forward.x, forward.z))
    if _has_combat_target(u) and _unit_in_attack_range(u):
        var aim := _unit_destination(u) - position
        if aim.length_squared() > 1.0:
            heading = aim.normalized()
    elif u.order in ["move", "attack_move", "attack"]:
        # Snapshot corrections can move the rendered position backwards. On
        # guests, use the existing snapshot-derived velocity instead.
        if host.connected and not host.is_host:
            motion = host.render_velocities.get(id, Vector2.ZERO)
        if motion.length_squared() > 0.0001:
            heading = motion.normalized()
            vis.has_moved = true
        elif not vis.get("has_moved", false):
            # Before the first movement tick, follow the next path segment.
            # Never substitute the final goal when a path is unavailable.
            for waypoint: Vector2 in u.path:
                var direction := waypoint - position
                if direction.length_squared() > 1.0:
                    heading = direction.normalized()
                    break
    vis.last_heading = heading
    return heading



var _dot_texture: ImageTexture

# Simple white dot for non-projectile effects and click markers (tinted by modulate).
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

func _sync_effects() -> void:
    var seen := {}
    for i: int in host.sim.effects.size():
        var e: Dictionary = host.sim.effects[i]
        # Fog: effects only render in visible areas.
        if not host.sim.can_see(host.local_slot, e.to):
            continue
        var key := "%d_%d" % [int(e.frame), i]
        if effect_visuals.has(key):
            var existing_visual = effect_visuals[key]
            var kind_mismatch: bool = (e.kind == "shot") == (existing_visual is Sprite3D)
            if not is_instance_valid(existing_visual) or kind_mismatch:
                if is_instance_valid(existing_visual):
                    existing_visual.queue_free()
                effect_visuals.erase(key)
        if not effect_visuals.has(key):
            if e.kind == "shot":
                var bullet := BULLET_SCENE.instantiate() as Node3D
                bullet.scale = Vector3.ONE * 6.0
                add_child(bullet)
                effect_visuals[key] = bullet
            else:
                var sprite := Sprite3D.new()
                sprite.pixel_size = 2.0
                sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
                sprite.shaded = false
                sprite.texture = _white_dot()
                add_child(sprite)
                effect_visuals[key] = sprite
        var visual: Node3D = effect_visuals[key]
        var progress := 1.0 - float(e.life) / 10.0
        if e.kind == "shot":
            var from_point := Vector3((e.from as Vector2).x, host.sim.terrain.height_at(e.from) + 40, (e.from as Vector2).y)
            var to_point := Vector3((e.to as Vector2).x, host.sim.terrain.height_at(e.to) + 24, (e.to as Vector2).y)
            visual.position = from_point.lerp(to_point, progress)
            var direction := to_point - from_point
            if direction.length_squared() > 0.001:
                var up := Vector3.FORWARD if absf(direction.normalized().dot(Vector3.UP)) > 0.98 else Vector3.UP
                visual.look_at(visual.position + direction.normalized(), up, true)
        else:
            var pos3 := Vector3((e.to as Vector2).x, host.sim.terrain.height_at(e.to) + 5 + (10 - e.life) * 2, (e.to as Vector2).y)
            visual.position = pos3
            (visual as Sprite3D).modulate = Color(1, 0.6, 0.2, float(e.life) / 10)
        seen[key] = true
    for key: String in effect_visuals.keys():
        if not seen.has(key):
            effect_visuals[key].queue_free()
            effect_visuals.erase(key)

func _sync_markers() -> void:
    var seen := {}
    for click: Dictionary in host.clicks:
        var key := "click_%d" % int(click.id)
        var animated: bool = click.action in ["move", "attack", "attack_move"]
        if not marker_visuals.has(key):
            if animated:
                var marker := DestinationMarker.new()
                marker.configure(click.action, click.pos)
                marker.position.y += host.sim.terrain.height_at(click.pos)
                marker.rotation = _surface_rotation(click.pos)
                add_child(marker)
                marker_visuals[key] = marker
            else:
                var sprite := Sprite3D.new()
                sprite.pixel_size = 3.0
                sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
                sprite.shaded = false
                sprite.texture = _white_dot()
                sprite.position = Vector3((click.pos as Vector2).x, host.sim.terrain.height_at(click.pos) + 5, (click.pos as Vector2).y)
                add_child(sprite)
                marker_visuals[key] = sprite
        if animated:
            var marker: DestinationMarker = marker_visuals[key]
            marker.set_age(float(click.duration) - float(click.life))
        else:
            var sprite: Sprite3D = marker_visuals[key]
            sprite.modulate = Color("#ffc359", clampf(float(click.life) / float(click.duration), 0.0, 1.0))
        seen[key] = true
    for key: String in marker_visuals.keys():
        if not seen.has(key):
            marker_visuals[key].queue_free()
            marker_visuals.erase(key)

func _sync_selection_rect() -> void:
    if host.selection_dragging:
        var start_screen: Vector2 = host._world_to_screen(host.selection_start)
        var end_screen: Vector2 = host._world_to_screen(host.selection_current)
        var rect := Rect2(start_screen, end_screen - start_screen).abs()
        if selection_rect_overlay == null:
            selection_rect_overlay = Panel.new()
            var style := StyleBoxFlat.new()
            style.bg_color = Color(0.7, 1, 0.5, 0.15)
            style.border_color = Color("#c5e79d")
            style.set_border_width_all(1)
            selection_rect_overlay.add_theme_stylebox_override("panel", style)
            selection_rect_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
            host.hud.add_child(selection_rect_overlay)
        selection_rect_overlay.position = rect.position
        selection_rect_overlay.size = rect.size
        selection_rect_overlay.visible = true
    elif selection_rect_overlay != null:
        selection_rect_overlay.visible = false

func _sync_build_preview() -> void:
    if host.deploy_building >= 0 and (not host.sim.buildings.has(host.deploy_building) or Simulation.BarracksFlight.state(host.sim.buildings[host.deploy_building]) != "airborne" or host.sim.winner != 0):
        host.deploy_building = -1
    for cell in deploy_cells:
        cell.visible = false
    if host.deploy_building >= 0 and not host.menu_visible:
        _sync_deploy_preview()
        return
    if not host.build_mode.is_empty() and not host.menu_visible:
        var pos: Vector2 = host.sim.snap_build(host._screen_to_world(get_viewport().get_mouse_position()))
        var size: Vector2 = Simulation.BUILD_TYPES[host.build_mode].size
        var valid: bool = host.sim.build_error(host.local_slot, host.build_mode, pos).is_empty()
        if build_preview_model != null and build_preview_model.kind != host.build_mode:
            build_preview_model.queue_free()
            build_preview_model = null
        if build_preview_model == null:
            build_preview_model = EntityVisual.new(host.build_mode, host.local_slot)
            add_child(build_preview_model)
        if build_preview_visual == null:
            var mesh := PlaneMesh.new()
            mesh.size = Vector2(100, 100)
            var surface := StandardMaterial3D.new()
            surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
            surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            build_preview_visual = MeshInstance3D.new()
            build_preview_visual.mesh = mesh
            build_preview_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            build_preview_visual.material_override = surface
            add_child(build_preview_visual)
        build_preview_model.visible = true
        build_preview_model.set_position_2d(pos, host.sim.terrain.height_at(pos))
        build_preview_model.set_animation("idle")
        build_preview_visual.visible = true
        build_preview_visual.position = Vector3(pos.x, host.sim.terrain.height_at(pos) + 0.5, pos.y)
        build_preview_visual.scale = Vector3(size.x / 100.0, 1, size.y / 100.0)
        build_preview_visual.get_active_material(0).albedo_color = Color(0.45, 1, 0.45, 0.3) if valid else Color(1, 0.3, 0.3, 0.3)
    else:
        if build_preview_model != null:
            build_preview_model.visible = false
        if build_preview_visual != null:
          build_preview_visual.visible = false

func _site_plane(size: Vector2) -> MeshInstance3D:
    var plane := PlaneMesh.new()
    plane.size = size
    var surface := StandardMaterial3D.new()
    surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    surface.no_depth_test = true
    var mesh := MeshInstance3D.new()
    mesh.mesh = plane
    mesh.material_override = surface
    mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(mesh)
    return mesh


func _sync_deploy_preview(position_override: Variant = null) -> void:
    var position: Vector2 = position_override if position_override is Vector2 else host._screen_to_world(get_viewport().get_mouse_position())
    var site: Dictionary = host.sim.deployment_site(host.local_slot, host.deploy_building, position)
    deployment_preview_error = site.error
    if build_preview_model != null and build_preview_model.kind != "barracks":
        build_preview_model.queue_free()
        build_preview_model = null
    if build_preview_model == null:
        build_preview_model = EntityVisual.new("barracks", host.local_slot)
        add_child(build_preview_model)
    build_preview_model.visible = true
    build_preview_model.set_position_2d(site.pos, host.sim.terrain.height_at(site.pos))
    build_preview_model.set_animation("idle")
    if build_preview_visual == null:
        build_preview_visual = _site_plane(Vector2(100, 100))
    build_preview_visual.visible = true
    build_preview_visual.position = Vector3(site.pos.x, host.sim.terrain.height_at(site.pos) + 0.6, site.pos.y)
    build_preview_visual.scale = Vector3(1.34, 1, 1.02)
    build_preview_visual.material_override.albedo_color = Color(0.2, 1, 0.3, 0.25) if site.error.is_empty() else Color(1, 0.1, 0.1, 0.4)
    while deploy_cells.size() < 12:
        deploy_cells.append(_site_plane(Vector2(29, 29)))
    for index in range(12):
        var entry: Dictionary = site.cells[index]
        var center: Vector2 = entry.rect.get_center()
        var cell := deploy_cells[index]
        cell.visible = true
        cell.position = Vector3(center.x, host.sim.terrain.height_at(center) + 0.8, center.y)
        cell.material_override.albedo_color = Color(0.1, 1, 0.2, 0.5) if entry.error.is_empty() else Color(1, 0.08, 0.08, 0.7)


func _sync_fog() -> void:
    var key := "%d:%d:%d" % [host.sim.match_id, host.local_slot, int(host.sim.frame / 4)]
    if key == last_fog_key:
        return
    last_fog_key = key
    if host.local_slot in [1, 2]:
        for y in range(Simulation.GRID.y):
            for x in range(Simulation.GRID.x):
                var index := y * Simulation.GRID.x + x
                if host.sim.visible[host.local_slot][index] == 0:
                    var alpha := 0.62 if host.sim.explored[host.local_slot][index] == 1 else 1.0
                    host.fog_image.set_pixel(x, y, Color(0.035, 0.055, 0.055, alpha))
                else:
                    host.fog_image.set_pixel(x, y, Color(0, 0, 0, 0))
        host.fog_texture.update(host.fog_image)
func _surface_rotation(point: Vector2) -> Vector3:
    var gradient: Vector2 = host.sim.terrain.gradient_at(point)
    return Vector3(-atan(gradient.y), 0.0, atan(gradient.x))

func reset_world() -> void:
    last_fog_key = ""
    for child in get_children():
        child.free()
    unit_visuals.clear()
    building_visuals.clear()
    ore_visuals.clear()
    rock_visuals.clear()
    effect_visuals.clear()
    marker_visuals.clear()
    build_preview_model = null
    build_preview_visual = null
    deploy_cells.clear()
    host.deploy_building = -1
    if health_grid_overlay != null:
        health_grid_overlay.entries.clear()
        health_grid_overlay.queue_redraw()
