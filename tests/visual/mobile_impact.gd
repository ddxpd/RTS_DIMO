extends SceneTree
const MAIN = preload("res://scenes/main.tscn")
const Hit = preload("res://assets/art/effects/mobile_hit_effect.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
    run.call_deferred()


func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)


func run() -> void:
    var sim := Simulation.new()
    sim.reset()
    sim.units.clear()
    sim.frame = 50
    var source := sim.add_unit(1, "mobile_infantry", Vector2(1640, 1900))
    var target := sim.add_unit(2, "soldier", Vector2(1720, 1900))
    sim.visible[1].fill(1)
    var unit: Dictionary = sim.units[source]
    unit.order = "attack"
    unit.attack_kind = "unit"
    unit.attack_id = target
    sim._fight(unit)
    check(sim.units[target].hp == 84 and unit.cooldown == 12, "Damage and cooldown unchanged")
    check(sim.effects.size() == 1 and sim.effects[0].has("impact"), "Mobile infantry creates an immediate hit")
    if sim.effects.is_empty():
        quit(1)
        return
    var event: Dictionary = sim.effects[0].duplicate(true)
    check(event.impact.source_id == source and event.impact.target_id == target, "Shot identities are authoritative")
    var mirror := Simulation.new()
    mirror.reset()
    check(mirror.apply_snapshot(sim.snapshot()) and mirror.snapshot() == sim.snapshot(), "Impact snapshot roundtrip")
    for patch: Dictionary in [{"source_id": -1}, {"source_id": 1.5}, {"target_id": "3"}, {"target_kind": "ore"}, {"target_type": "base"}, {"source_type": "soldier"}, {"target_pos": Vector2(INF, 0)}]:
        var bad := sim.snapshot()
        bad.effects[0].impact.merge(patch, true)
        check(not mirror.apply_snapshot(bad), "Reject malformed impact: " + str(patch))
    var old := sim.snapshot()
    old.version = "rts-desert-only-9"
    check(not mirror.apply_snapshot(old), "Old protocol rejected")
    unit.type = "soldier"
    unit.cooldown = 0
    sim._fight(unit)
    check(not sim.effects.back().has("impact"), "Ordinary soldier retains projectile effect")
    unit.type = "mobile_infantry"
    sim.units.erase(target)
    check(mirror.apply_snapshot(sim.snapshot()), "Lethal hit remains valid after target removal")

    root.size = Vector2i(1440, 900)
    var game := MAIN.instantiate()
    root.add_child(game)
    game.play_solo()
    game.set_process(false)
    game.sim.ai_enabled = false
    game.sim.units.clear()
    game.sim.buildings.clear()
    game.sim.effects.clear()
    game.sim.frame = 50
    game.accumulator = 0.04
    game.sim.visible[1].fill(1)
    var kinds := ["soldier", "mobile_infantry", "harvester", "base", "barracks", "refinery", "bunker"]
    for index in range(kinds.size()):
        var kind: String = kinds[index]
        var position := Vector2(1100 + (index % 4) * 280, 1750 + (index / 4) * 320)
        var sid: int = game.sim.add_unit(1, "mobile_infantry", position + Vector2(0, -110))
        var tid: int = game.sim.add_unit(2, kind, position) if index < 3 else game.sim._add_building(2, kind, position, true)
        game.sim.units[sid].order = "attack"
        game.sim.units[sid].attack_kind = "unit" if index < 3 else "building"
        game.sim.units[sid].attack_id = tid
        game.sim.units[sid].cooldown = 12
        var shot := event.duplicate(true)
        shot.from = position + Vector2(0, -110)
        shot.to = position
        shot.impact = {"source_type": "mobile_infantry", "source_id": sid, "target_kind": "unit" if index < 3 else "building", "target_id": tid, "target_type": kind, "target_pos": position}
        game.sim.effects.append(shot)
    game._sync_visuals()
    var sync: Node3D = game.visual_sync
    check(sync.effect_visuals.size() == 7, "One impact per shot across all seven target types")
    var ids: Array = []
    for index in range(sync.effect_visuals.size()):
        var effect: Node3D = sync.effect_visuals.values()[index]
        check(effect is Hit and effect.visible, "Mobile shots instantiate only hit effects")
        var info: Dictionary = game.sim.effects[index].impact
        var height: float = effect.global_position.y - game.sim.terrain.height_at(info.target_pos)
        check(height > 0 and height < EntityVisual.MODEL_SETTINGS[info.target_type].height, "Hit is within the current target height above terrain")
        if info.target_type == "harvester":
            var horizontal := Vector2(effect.global_position.x, effect.global_position.z)
            check(horizontal.distance_to(info.target_pos) <= Simulation.UNIT_TYPES.harvester.radius, "Compact harvester impact stays on the body")
        check(effect.muzzle.visible, "Muzzle flash uses actual weapon socket")
        ids.append(effect.get_instance_id())
    sync._sync_effects()
    var repeated: Array = []
    for effect: Node3D in sync.effect_visuals.values():
        repeated.append(effect.get_instance_id())
    check(ids == repeated, "Repeated snapshots reuse effects")
    var first_event: Dictionary = game.sim.effects[0]
    var first_hit: Node3D = sync.effect_visuals.values()[0]
    var target_visual: Node3D = sync.unit_visuals[first_event.impact.target_id].visual
    var before: Vector3 = first_hit.global_position
    target_visual.position.x += 10.0
    sync._sync_effects()
    check(first_hit.global_position.is_equal_approx(before + Vector3(10, 0, 0)), "Anchor follows interpolated target movement")
    target_visual.rotation.y += 0.5
    sync._sync_effects()
    check(first_hit.global_position.is_equal_approx(target_visual.to_global(first_hit.anchor)), "Anchor follows target rotation")
    game.camera_controller.focus = Vector2(1500, 1920)
    game.camera_zoom_level = 0.6
    game._update_camera_transform()
    if DisplayServer.get_name() != "headless":
        await process_frame
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png("res://.godot/mobile-impact-preview.png")
        game.camera_controller.focus = Vector2(1280, 1790)
        game.camera_zoom_level = 1.8
        game._update_camera_transform()
        await process_frame
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png("res://.godot/mobile-impact-close.png")
        game.accumulator = 0.12
        sync._sync_effects()
        await process_frame
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png("res://.godot/mobile-impact-decay.png")
        game.accumulator = 0.04
        sync._sync_effects()
    game.sim.effects.remove_at(0)
    sync._sync_effects()
    check(sync.effect_visuals.size() == 6 and sync.effect_visuals.values()[0].get_instance_id() == ids[1], "Removing earlier shot does not recreate later effects")
    var remaining: Dictionary = game.sim.effects[0]
    var remaining_hit: Node3D = sync.effect_visuals.values()[0]
    var last_position: Vector3 = remaining_hit.global_position
    sync.unit_visuals[remaining.impact.target_id].visual.free()
    sync.unit_visuals.erase(remaining.impact.target_id)
    game.sim.units.erase(remaining.impact.target_id)
    sync._sync_effects()
    check(remaining_hit.global_position.is_equal_approx(last_position), "Target death preserves last hit position")
    game.sim.visible[1].fill(0)
    sync._sync_effects()
    check(sync.effect_visuals.is_empty(), "Hidden targets do not leak impact visuals")
    game.sim.visible[1].fill(1)
    game.accumulator = 0.21
    sync._sync_effects()
    for effect: Node3D in sync.effect_visuals.values():
        check(not effect.visible, "Late snapshots do not replay expired flashes")
    game.sim.effects.clear()
    sync._sync_effects()
    check(sync.effect_visuals.is_empty(), "Expired effects are reclaimed")
    var crowd: Array[Node3D] = []
    for index in range(100):
        var hit := Hit.new()
        sync.add_child(hit)
        hit.sample(event, null, null, game.sim.terrain, 0.08)
        crowd.append(hit)
    var start := Time.get_ticks_usec()
    for frame in range(20):
        for hit in crowd:
            hit.sample(event, null, null, game.sim.terrain, 0.08)
    var update_ms := (Time.get_ticks_usec() - start) / 20000.0
    check(crowd[0].sparks.multimesh.mesh == crowd[99].sparks.multimesh.mesh, "Simultaneous hits share mesh and material")
    check(update_ms < 4.0, "100 active impact updates stay below 4ms CPU")
    crowd[0].sample(event, null, null, game.sim.terrain, 0.0, 0.21)
    check(not crowd[0].visible, "Winning tick or stalled snapshots cannot freeze the flash")
    print("MOBILE_IMPACT_CPU 100_hits_ms=", update_ms)
    for hit in crowd:
        hit.free()
    game.queue_free()
    await process_frame
    print("MOBILE_IMPACT checks=", checks, " failures=", failures)
    quit(0 if failures.is_empty() else 1)
