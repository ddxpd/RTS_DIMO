extends RefCounted
## Stateless presentation operations; WorldVisualSync owns node lifetime and caches.
const Simulation = preload("res://scripts/simulation.gd")
const EntityVisual = preload("res://assets/art/entity_visual.gd")


static func _sync_ores(context: WorldVisualSync) -> void:
    var seen := {}
    for id: int in context.host.sim.ores:
        var ore: Dictionary = context.host.sim.ores[id]
        if not context.ore_visuals.has(id):
            var visual := EntityVisual.new("ore", 1)
            visual.name = "Ore%d" % id
            visual.set_position_2d(ore.pos, context.host.sim.terrain.height_at(ore.pos))
            context.add_child(visual)
            var label := Label3D.new()
            label.text = str(ore.amount)
            label.font_size = 32
            label.pixel_size = 0.02
            label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
            label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            label.position = Vector3(0, visual.get_model_height() + 8, 0)
            visual.add_child(label)
            context.ore_visuals[id] = {"visual": visual, "label": label}
        var vis: Dictionary = context.ore_visuals[id]
        var visual: EntityVisual = vis.visual

        # Fog of war: only render ores the local player can currently see.
        context._set_visual_visible(visual, ore.amount > 0 and context.host.sim.can_see(context.host.local_slot, ore.pos))
        visual.set_position_2d(ore.pos, context.host.sim.terrain.height_at(ore.pos))
        var label: Label3D = vis.label
        if int(vis.get("last_amount", -1)) != ore.amount:
            label.text = str(ore.amount)
            vis["last_amount"] = ore.amount
        seen[id] = true
    for id: int in context.ore_visuals.keys():
        if not seen.has(id):
            context.ore_visuals[id].visual.queue_free()
            context.ore_visuals.erase(id)


static func _sync_buildings(context: WorldVisualSync, delta: float = 0.0) -> void:
    var seen := {}
    for id: int in context.host.sim.buildings:
        var b: Dictionary = context.host.sim.buildings[id]
        if not context.building_visuals.has(id):
            var visual := EntityVisual.new(b.type, b.owner)
            visual.name = "Building%d" % id
            visual.set_position_2d(b.pos, context.host.sim.terrain.height_at(b.pos))
            if b.has("flight"):
                visual.rotation.y = float(b.flight.heading)
            context.add_child(visual)
            context.building_visuals[id] = {"visual": visual}
        var vis: Dictionary = context.building_visuals[id]
        var visual: EntityVisual = vis.visual

        # Fog: enemy buildings only render when currently visible.
        context._set_visual_visible(visual, b.owner == context.host.local_slot or context.host.sim.can_see(context.host.local_slot, b.pos))
        var ground: float = context.host.sim.terrain.height_at(b.pos)
        var height: float = b.get("flight", {}).get("height", ground)
        var target := Vector3(b.pos.x, height, b.pos.y)
        if b.has("flight") and delta > 0 and visual.position.distance_to(target) < 300:
            visual.position = visual.position.lerp(target, 1.0 - exp(-18.0 * delta))
            visual.rotation.y = lerp_angle(visual.rotation.y, float(b.flight.heading), 1.0 - exp(-18.0 * delta))
        else:
            visual.position = target
            if b.has("flight"):
                visual.rotation.y = float(b.flight.heading)
        if b.type == "refinery":
            visual.model.update_docks(b, context.host.sim.units, id)
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
            if int(vis.get("flight_frame", -1)) != context.host.sim.frame:
                vis.flight_frame = context.host.sim.frame
                vis.flight_elapsed = 0.0
            else:
                vis.flight_elapsed = minf(float(vis.get("flight_elapsed", 0.0)) + delta, 0.2)
            visual.barracks_motion.apply(b.flight, float(vis.get("flight_elapsed", 0.0)) * Simulation.TICK)
        if visual.barracks_presentation != null:
            visual.barracks_presentation.update(b, delta, visual.get_viewport().get_camera_3d())

        var building_selected: bool = context.host.selected_buildings.has(id) or context.host.selected_building == id
        var building_size: Vector2 = Simulation.BUILD_TYPES[b.type].size
        var building_radius := context._selection_ring_radius(b.type, maxf(building_size.x, building_size.y) * 0.5, building_size)
        visual.set_selected(building_selected and visual.visible, building_radius)
        if visual.selection_ring != null:
            if b.type == "barracks" and b.has("flight"):
                # Follow the interpolated building, including takeoff and landing.
                visual.selection_ring.position.y = 0.6
            else:
                visual.selection_ring.position.y = ground - visual.position.y + 0.6

        context.health_grid_overlay.upsert_entity(
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
                var build_bar := context._make_status_bar(Simulation.BUILD_TYPES[b.type].size.x * 0.8, 5, Color("#eac75b"))
                build_bar.position = Vector3(0, visual.get_model_height() + 20, 0)
                visual.add_child(build_bar)
                vis["build_bar"] = build_bar
            context._update_status_bar(vis.build_bar, 1.0 - float(b.remaining) / Simulation.BUILD_TYPES[b.type].time)
        if vis.has("build_bar"):
            vis.build_bar.visible = b.remaining > 0
        seen[id] = true
    for id: int in context.building_visuals.keys():
        if not seen.has(id):
            context.health_grid_overlay.remove_entity("building_%d" % id)
            context.building_visuals[id].visual.queue_free()
            context.building_visuals.erase(id)
