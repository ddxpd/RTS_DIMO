extends RefCounted
## Stateless presentation operations; WorldVisualSync owns node lifetime and caches.
const Simulation = preload("res://scripts/simulation.gd")
const EntityVisual = preload("res://assets/art/entity_visual.gd")


static func _sync_units(context: WorldVisualSync, delta: float = 0.0) -> void:
    var seen := {}
    for id: int in context.host.sim.units:
        var u: Dictionary = context.host.sim.units[id]
        if not context.unit_visuals.has(id):
            var visual := EntityVisual.new(u.type, u.owner)
            visual.name = "Unit%d" % id
            visual.set_position_2d(u.pos, context.host.sim.terrain.height_at(u.pos))
            context.add_child(visual)
            context.unit_visuals[id] = {"visual": visual}
        var vis: Dictionary = context.unit_visuals[id]
        var visual: EntityVisual = vis.visual

        # Fog: enemy units only render when currently visible.
        context._set_visual_visible(visual, u.owner == context.host.local_slot or context.host.sim.can_see(context.host.local_slot, u.pos))
        if u.type not in ["soldier", "mobile_infantry"]:
            visual.set_position_2d(u.pos, context.host.sim.terrain.height_at(u.pos))
        visual.set_flash(u.flash > 0)
        if u.type != "mobile_infantry":
            visual.set_heading(_unit_heading(context, u, id), u.type == "soldier")
        visual.set_animation(_unit_animation_state(context, u))
        if u.type == "harvester":
            visual.harvester_motion.sample(u, delta, context.host.sim.terrain)
        if u.type == "mobile_infantry":
            var aim := _unit_destination(context, u) - (u.pos as Vector2) if _has_combat_target(context, u) and _unit_in_attack_range(context, u) else Vector2.ZERO
            visual.mobile_motion.sample(u, delta, context.host.sim.frame, context.host.sim.terrain, aim)
        if u.type == "soldier":
            visual.soldier_motion.configure_view(context.host.camera, delta)
            visual.soldier_motion.observe_combat(context.host.sim.frame, int(u.cooldown))
        if u.type == "soldier" and (delta > 0.0 or not visual.soldier_motion.initialized
                or u.pos != visual.soldier_motion.current):
            var guest: bool = context.host.connected and not context.host.is_host
            var velocity: Vector2 = context.host.render_velocities.get(id, Vector2.ZERO)
            if u.order == "idle" or visual.animation_state == "attack":
                velocity = Vector2.ZERO
            var aim := _unit_destination(context, u) - (u.pos as Vector2) if _has_combat_target(context, u) else Vector2.ZERO
            visual.soldier_motion.sample(u.pos, delta, context.host.sim.frame, context.host.accumulator * Simulation.TICK,
                context.host.sim.terrain, guest, velocity, aim)
            visual.set_soldier_shadow_distance(context.host.camera.global_position)
        var unit_selected: bool = context.host.selected_units.has(id)
        var unit_radius := context._selection_ring_radius(u.type, float(Simulation.UNIT_TYPES[u.type].radius))
        visual.set_selected(unit_selected and visual.visible, unit_radius)
        if visual.selection_ring != null:
            visual.selection_ring.global_rotation = context._surface_rotation(Vector2(visual.position.x, visual.position.z))
        context.health_grid_overlay.upsert_entity(
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
                    var cargo_bar := context._make_status_bar(30, 4, Color("#eac75b"))
                    cargo_bar.position = Vector3(0, visual.get_model_height() + 20, 0)
                    visual.add_child(cargo_bar)
                    vis["cargo_bar"] = cargo_bar
                context._update_status_bar(vis.cargo_bar, float(u.cargo) / 60.0)
                vis.cargo_bar.visible = true
            elif vis.has("cargo_bar"):
                vis.cargo_bar.visible = false
        seen[id] = true
    for id: int in context.unit_visuals.keys():
        if not seen.has(id):
            context.health_grid_overlay.remove_entity("unit_%d" % id)
            var removed: EntityVisual = context.unit_visuals[id].visual
            var death_confirmed := false
            if removed.kind == "mobile_infantry" and removed.visible:
                for event: Dictionary in context.host.sim.effects:
                    if event.kind == "death" and int(event.get("entity_id", -1)) == id and event.get("unit_type") == "mobile_infantry":
                        death_confirmed = true
                        break
            if death_confirmed and removed.animation_player != null and removed.animation_player.has_animation("death"):
                removed.set_selected(false)
                removed.set_flash(false)
                removed.mobile_motion.skeleton.clear_bones_global_pose_override()
                removed.animation_player.active = true
                removed.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
                removed.animation_player.play("death", 0.12)
                context.mobile_deaths.append({"visual": removed, "age": 0.0})
            else:
                removed.queue_free()
            context.unit_visuals.erase(id)


static func _sync_mobile_deaths(context: WorldVisualSync, delta: float) -> void:
    for index in range(context.mobile_deaths.size() - 1, -1, -1):
        var corpse: Dictionary = context.mobile_deaths[index]
        corpse.age += maxf(delta, 0.0)
        var visual: EntityVisual = corpse.visual
        var point := Vector2(visual.position.x, visual.position.z)
        visual.visible = visual.owner_id == context.host.local_slot or context.host.sim.can_see(context.host.local_slot, point)
        if corpse.age >= 1.8:
            visual.queue_free()
            context.mobile_deaths.remove_at(index)


static func _unit_animation_state(context: WorldVisualSync, u: Dictionary) -> String:
    if u.order in ["attack", "attack_move"] and int(u.attack_id) >= 0:
        return "attack" if _unit_in_attack_range(context, u) else "move"
    if u.order in ["move", "attack_move"]:
        return "move"
    if u.type == "harvester" and u.order == "gather":
        if u.has("dock"):
            return "move" if (u.pos as Vector2).distance_to(u.dock.target) > 4.0 else "idle"
        if _harvester_returning(context, u):
            return "idle"
        if not context.host.sim.ores.has(int(u.ore)) or int(context.host.sim.ores[int(u.ore)].amount) <= 0:
            return "idle"
        if u.has("mining"):
            if u.mining.phase == "work":
                return "mine"
            return "move" if (u.pos as Vector2).distance_to(u.mining.target) > 4.0 else "idle"
        return "idle"
    return "idle"


static func _unit_destination(context: WorldVisualSync, u: Dictionary) -> Vector2:
    if u.order in ["attack", "attack_move"] and int(u.attack_id) >= 0:
        if u.attack_kind == "unit" and context.host.sim.units.has(int(u.attack_id)):
            return context.host.sim.units[int(u.attack_id)].pos
        if u.attack_kind == "building" and context.host.sim.buildings.has(int(u.attack_id)):
            return context.host.sim.buildings[int(u.attack_id)].pos
    if u.order == "gather" and u.type == "harvester":
        if u.has("dock"):
            return u.dock.target
        if _harvester_returning(context, u):
            return _nearest_refinery_position(context, u)
        if context.host.sim.ores.has(int(u.ore)):
            return context.host.sim.ores[int(u.ore)].pos
    return u.target


static func _harvester_returning(context: WorldVisualSync, u: Dictionary) -> bool:
    return Simulation.DepotDocking.returning(context.host.sim, u)


static func _harvester_refinery(context: WorldVisualSync, u: Dictionary) -> Dictionary:
    var nearest: Dictionary = {}
    var best_distance := INF
    for building: Dictionary in context.host.sim.buildings.values():
        var refinery: bool = building.type == "refinery" and building.owner == u.owner and building.remaining == 0
        var distance: float = (u.pos as Vector2).distance_to(building.pos) if refinery else INF
        if distance < best_distance:
            best_distance = distance
            nearest = building
    return nearest


static func _nearest_refinery_position(context: WorldVisualSync, u: Dictionary) -> Vector2:
    var refinery := _harvester_refinery(context, u)
    if refinery.is_empty():
        return u.pos
    var rect: Rect2 = context.host.sim.footprint(refinery)
    return (u.pos as Vector2).clamp(rect.position, rect.end)


static func _unit_in_attack_range(context: WorldVisualSync, u: Dictionary) -> bool:
    var target_position: Vector2 = u.pos
    if u.attack_kind == "unit" and context.host.sim.units.has(int(u.attack_id)):
        target_position = context.host.sim.units[int(u.attack_id)].pos
    elif u.attack_kind == "building" and context.host.sim.buildings.has(int(u.attack_id)):
        var footprint: Rect2 = context.host.sim.footprint(context.host.sim.buildings[int(u.attack_id)])
        target_position = (u.pos as Vector2).clamp(footprint.position, footprint.end)
    else:
        return false
    return (u.pos as Vector2).distance_to(target_position) <= float(Simulation.UNIT_TYPES[u.type].range)


static func _unit_heading(context: WorldVisualSync, u: Dictionary, id: int) -> Vector2:
    if u.type == "soldier":
        return _soldier_heading(context, u, id, context.unit_visuals[id])
    if u.type == "harvester":
        return _harvester_heading(context, u, id)
    var destination := _unit_destination(context, u)
    var heading := destination - (u.pos as Vector2)
    if heading.length_squared() > 1.0:
        return heading
    if context.host.render_velocities.has(id):
        return context.host.render_velocities[id]
    return Vector2.UP


static func _has_combat_target(context: WorldVisualSync, u: Dictionary) -> bool:
    if u.order not in ["attack", "attack_move"]:
        return false
    if u.attack_kind == "unit":
        return context.host.sim.units.has(int(u.attack_id))
    if u.attack_kind == "building":
        return context.host.sim.buildings.has(int(u.attack_id))
    return false


static func _soldier_heading(context: WorldVisualSync, u: Dictionary, id: int, vis: Dictionary) -> Vector2:
    var position: Vector2 = u.pos
    var motion := position - (vis.get("last_position", position) as Vector2)
    vis.last_position = position
    var forward: Vector3 = vis.visual.get_visual_forward()
    var heading: Vector2 = vis.get("last_heading", Vector2(forward.x, forward.z))
    if _has_combat_target(context, u) and _unit_in_attack_range(context, u):
        var aim := _unit_destination(context, u) - position
        if aim.length_squared() > 1.0:
            heading = aim.normalized()
    elif u.order in ["move", "attack_move", "attack"]:
        # Snapshot corrections can move the rendered position backwards. On
        # guests, use the existing snapshot-derived velocity instead.
        if context.host.connected and not context.host.is_host:
            motion = context.host.render_velocities.get(id, Vector2.ZERO)
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



static func _harvester_heading(context: WorldVisualSync, u: Dictionary, id: int) -> Vector2:
    # Match actual travel, not the final objective on the far side of an obstacle.
    var vis: Dictionary = context.unit_visuals.get(id, {})
    var position: Vector2 = u.pos
    var key := [context.host.sim.frame, position, u.order, int(u.cargo), int(u.ore)]
    if vis.get("heading_key", []) == key:
        return vis.get("last_heading", Vector2.UP)
    vis.heading_key = key
    var state := _unit_animation_state(context, u)
    var motion := position - (vis.get("last_position", position) as Vector2)
    vis.last_position = position
    var heading: Vector2 = vis.get("last_heading", Vector2.UP)
    if state == "mine":
        heading = _unit_destination(context, u) - position
    elif state == "move":
        if context.host.connected and not context.host.is_host:
            motion = context.host.render_velocities.get(id, Vector2.ZERO)
        if motion.length_squared() > 0.01:
            heading = motion.normalized()
        elif not vis.has("last_heading"):
            for waypoint: Vector2 in u.path:
                if waypoint.distance_squared_to(position) > 1.0:
                    heading = (waypoint - position).normalized()
                    break
    if heading.length_squared() > 0.01:
        vis.last_heading = heading.normalized()
    return vis.get("last_heading", Vector2.UP)
