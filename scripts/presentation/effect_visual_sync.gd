extends RefCounted
## Stateless presentation operations; WorldVisualSync owns node lifetime and caches.
const Simulation = preload("res://scripts/simulation.gd")
const BULLET_SCENE = preload("res://assets/models/effects/bullet.glb")
const MobileHitEffect = preload("res://assets/art/effects/mobile_hit_effect.gd")


static func _sync_effects(context: WorldVisualSync, delta: float = 0.0) -> void:
    var seen := {}
    for i: int in context.host.sim.effects.size():
        var e: Dictionary = context.host.sim.effects[i]
        if e.kind == "death" and e.get("unit_type") == "mobile_infantry":
            continue
        if e.has("impact"):
            var impact: Dictionary = e.impact
            var collection: Dictionary = context.host.sim.units if impact.target_kind == "unit" else context.host.sim.buildings
            var point: Vector2 = collection[impact.target_id].pos if collection.has(impact.target_id) else impact.target_pos
            if not context.host.sim.can_see(context.host.local_slot, point):
                continue
            # Stable across removal of older effects and repeated snapshots.
            var impact_key := "impact_%d_%d_%d" % [context.host.sim.match_id, int(e.frame), int(impact.source_id)]
            if not context.effect_visuals.has(impact_key):
                var hit := MobileHitEffect.new()
                context.add_child(hit)
                context.effect_visuals[impact_key] = hit
            var visuals: Dictionary = context.unit_visuals if impact.target_kind == "unit" else context.building_visuals
            var target: Node3D = visuals.get(impact.target_id, {}).get("visual")
            var shooter: Node3D = context.unit_visuals.get(impact.source_id, {}).get("visual")
            var age: float = (context.host.sim.frame - int(e.frame)) / float(Simulation.TICK) + maxf(0.0, context.host.accumulator)
            context.effect_visuals[impact_key].sample(e, target, shooter, context.host.sim.terrain, age, delta)
            seen[impact_key] = true
            continue
        # Fog: effects only render in visible areas.
        if not context.host.sim.can_see(context.host.local_slot, e.to):
            continue
        var key := "%d_%d" % [int(e.frame), i]
        if context.effect_visuals.has(key):
            var existing_visual: Node3D = context.effect_visuals[key]
            var kind_mismatch: bool = (e.kind == "shot") == (existing_visual is Sprite3D)
            if not is_instance_valid(existing_visual) or kind_mismatch:
                if is_instance_valid(existing_visual):
                    existing_visual.queue_free()
                context.effect_visuals.erase(key)
        if not context.effect_visuals.has(key):
            if e.kind == "shot":
                var bullet := BULLET_SCENE.instantiate() as Node3D
                bullet.scale = Vector3.ONE * 6.0
                context.add_child(bullet)
                context.effect_visuals[key] = bullet
            else:
                var sprite := Sprite3D.new()
                sprite.pixel_size = 2.0
                sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
                sprite.shaded = false
                sprite.texture = context._white_dot()
                context.add_child(sprite)
                context.effect_visuals[key] = sprite
        var visual: Node3D = context.effect_visuals[key]
        var progress := 1.0 - float(e.life) / 10.0
        if e.kind == "shot":
            var from_point := Vector3((e.from as Vector2).x, context.host.sim.terrain.height_at(e.from) + 40, (e.from as Vector2).y)
            var to_point := Vector3((e.to as Vector2).x, context.host.sim.terrain.height_at(e.to) + 24, (e.to as Vector2).y)
            visual.position = from_point.lerp(to_point, progress)
            var direction := to_point - from_point
            if direction.length_squared() > 0.001:
                var up := Vector3.FORWARD if absf(direction.normalized().dot(Vector3.UP)) > 0.98 else Vector3.UP
                visual.look_at(visual.position + direction.normalized(), up, true)
        else:
            var pos3 := Vector3((e.to as Vector2).x, context.host.sim.terrain.height_at(e.to) + 5 + (10 - e.life) * 2, (e.to as Vector2).y)
            visual.position = pos3
            (visual as Sprite3D).modulate = Color(1, 0.6, 0.2, float(e.life) / 10)
        seen[key] = true
    for key: String in context.effect_visuals.keys():
        if not seen.has(key):
            context.effect_visuals[key].queue_free()
            context.effect_visuals.erase(key)
