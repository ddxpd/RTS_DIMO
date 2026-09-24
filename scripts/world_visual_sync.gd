extends Node3D

const Simulation = preload("res://scripts/simulation.gd")
const EntityVisual = preload("res://assets/art/entity_visual.gd")

var host

var unit_visuals: Dictionary = {}
var building_visuals: Dictionary = {}
var ore_visuals: Dictionary = {}
var rock_visuals: Array[EntityVisual] = []
var effect_visuals: Dictionary = {}
var marker_visuals: Dictionary = {}
var selection_rect_overlay: Panel
var build_preview_visual: MeshInstance3D
var build_preview_model: EntityVisual

func configure(owner) -> void:
    host = owner

func sync() -> void:
    _sync_rocks()
    _sync_ores()
    _sync_buildings()
    _sync_units()
    _sync_effects()
    _sync_markers()
    _sync_selection_rect()
    _sync_build_preview()
    _sync_fog()

func _set_visual_visible(visual: EntityVisual, next_visible: bool) -> void:
    visual.visible = next_visible
    if visual.animation_player != null:
        visual.animation_player.active = next_visible

func _sync_rocks() -> void:
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
            visual.set_position_2d(ore.pos)
            add_child(visual)
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
        visual.set_position_2d(ore.pos)
        var label: Label3D = vis.label
        if int(vis.get("last_amount", -1)) != ore.amount:
            label.text = str(ore.amount)
            vis["last_amount"] = ore.amount
        seen[id] = true
    for id: int in ore_visuals.keys():
        if not seen.has(id):
            ore_visuals[id].visual.queue_free()
            ore_visuals.erase(id)


func _sync_buildings() -> void:
    var seen := {}
    for id: int in host.sim.buildings:
        var b: Dictionary = host.sim.buildings[id]
        if not building_visuals.has(id):
            var visual := EntityVisual.new(b.type, b.owner)
            visual.name = "Building%d" % id
            visual.set_position_2d(b.pos)
            add_child(visual)
            var hp_bar := _make_status_bar(Simulation.BUILD_TYPES[b.type].size.x * 0.8, 5, Color("#75c46e"))
            hp_bar.position = Vector3(0, visual.get_model_height() + 12, 0)
            visual.add_child(hp_bar)
            building_visuals[id] = {"visual": visual, "hp_bar": hp_bar}
        var vis: Dictionary = building_visuals[id]
        var visual: EntityVisual = vis.visual

        # Fog: enemy buildings only render when currently visible.
        _set_visual_visible(visual, b.owner == host.local_slot or host.sim.can_see(host.local_slot, b.pos))
        visual.set_position_2d(b.pos)
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

        _update_status_bar(vis.hp_bar, float(b.hp) / Simulation.BUILD_TYPES[b.type].hp)
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
            building_visuals[id].visual.queue_free()
            building_visuals.erase(id)


func _sync_units() -> void:
    var seen := {}
    for id: int in host.sim.units:
        var u: Dictionary = host.sim.units[id]
        if not unit_visuals.has(id):
            var visual := EntityVisual.new(u.type, u.owner)
            visual.name = "Unit%d" % id
            visual.set_position_2d(u.pos)
            add_child(visual)
            var hp_bar := _make_status_bar(30, 4, Color("#75c46e"))
            hp_bar.position = Vector3(0, visual.get_model_height() + 12, 0)
            visual.add_child(hp_bar)
            unit_visuals[id] = {"visual": visual, "hp_bar": hp_bar}
        var vis: Dictionary = unit_visuals[id]
        var visual: EntityVisual = vis.visual

        # Fog: enemy units only render when currently visible.
        _set_visual_visible(visual, u.owner == host.local_slot or host.sim.can_see(host.local_slot, u.pos))
        visual.set_position_2d(u.pos)
        visual.set_flash(u.flash > 0)
        visual.set_heading(_unit_heading(u, id))
        visual.set_animation(_unit_animation_state(u))
        _update_status_bar(vis.hp_bar, float(u.hp) / Simulation.UNIT_TYPES[u.type].hp)

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
            unit_visuals[id].visual.queue_free()
            unit_visuals.erase(id)


func _unit_animation_state(u: Dictionary) -> String:
    if u.order == "attack":
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
    if u.order == "attack":
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
    var destination := _unit_destination(u)
    var heading := destination - (u.pos as Vector2)
    if heading.length_squared() > 1.0:
        return heading
    if host.render_velocities.has(id):
        return host.render_velocities[id]
    return Vector2.UP



var _dot_texture: ImageTexture

# Simple white dot for effects and click markers (tinted by modulate).
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
        if not effect_visuals.has(key):
            var sprite := Sprite3D.new()
            sprite.pixel_size = 2.0
            sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
            sprite.shaded = false
            sprite.texture = _white_dot()
            add_child(sprite)
            effect_visuals[key] = sprite
        var sprite: Sprite3D = effect_visuals[key]
        var progress := 1.0 - float(e.life) / 10.0
        if e.kind == "shot":
            var point := Vector3((e.from as Vector2).lerp(e.to, progress).x, 12, (e.from as Vector2).lerp(e.to, progress).y)
            point.y = 12
            sprite.position = point
            sprite.modulate = Color("#ffe9a2")
        else:
            var pos3 := Vector3((e.to as Vector2).x, 5 + (10 - e.life) * 2, (e.to as Vector2).y)
            sprite.position = pos3
            sprite.modulate = Color(1, 0.6, 0.2, float(e.life) / 10)
        seen[key] = true
    for key: String in effect_visuals.keys():
        if not seen.has(key):
            effect_visuals[key].queue_free()
            effect_visuals.erase(key)

func _sync_markers() -> void:
    var seen := {}
    for i: int in host.clicks.size():
        var click: Dictionary = host.clicks[i]
        var key := "click_%d" % i
        if not marker_visuals.has(key):
            var sprite := Sprite3D.new()
            sprite.pixel_size = 3.0
            sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
            sprite.shaded = false
            sprite.texture = _white_dot()
            add_child(sprite)
            marker_visuals[key] = sprite
        var sprite: Sprite3D = marker_visuals[key]
        var pos3 := Vector3((click.pos as Vector2).x, 5, (click.pos as Vector2).y)
        sprite.position = pos3
        var p: float = 1.0 - click.life / 0.55
        sprite.modulate = Color("#ffc359", 1.0 - p)
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
        build_preview_model.set_position_2d(pos)
        build_preview_model.set_animation("idle")
        build_preview_visual.visible = true
        build_preview_visual.position = Vector3(pos.x, 0.5, pos.y)
        build_preview_visual.scale = Vector3(size.x / 100.0, 1, size.y / 100.0)
        build_preview_visual.get_active_material(0).albedo_color = Color(0.45, 1, 0.45, 0.3) if valid else Color(1, 0.3, 0.3, 0.3)
    else:
        if build_preview_model != null:
            build_preview_model.visible = false
        if build_preview_visual != null:
            build_preview_visual.visible = false

func _sync_fog() -> void:
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
