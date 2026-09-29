extends RefCounted
## Inspect the synchronized model directly: do not call set_heading in assertions.


static func faces(game, id: int, direction: Vector2, check: Callable, label: String) -> void:
    var visual = game.unit_visuals[id].visual
    var expected := Vector3(direction.x, 0, direction.y).normalized()
    check.call(visual.get_visual_forward().dot(expected) > 0.999, label)


static func basic(game, check: Callable) -> void:
    game.sim.reset(false, "prototype")
    game._sync_map_world()
    game.sim.units.clear()
    game._sync_units()
    var id: int = game.sim.add_unit(1, "soldier", Vector2(1200, 1200))
    var u: Dictionary = game.sim.units[id]
    u.order = "move"
    u.target = Vector2(1600, 1200)
    game._sync_units()
    var initial: Vector3 = game.unit_visuals[id].visual.get_visual_forward()
    game._sync_units()
    check.call(game.unit_visuals[id].visual.get_visual_forward().is_equal_approx(initial), "No path or displacement preserves spawn facing")
    u.path = [u.pos, Vector2(1200, 1300), u.target]
    game._sync_units()
    faces(game, id, Vector2.DOWN, check, "First path segment overrides final destination")
    u.pos += Vector2(-6, 0)
    game._sync_units()
    faces(game, id, Vector2.LEFT, check, "Actual sidestep overrides path and goal immediately")
    for i in range(3):
        game._sync_units()
        faces(game, id, Vector2.LEFT, check, "Between-tick render retains movement facing")
    u.order = "idle"
    u.path = []
    game._sync_units()
    faces(game, id, Vector2.LEFT, check, "Stopped soldier holds last direction")
    var enemy: int = game.sim.add_unit(2, "soldier", u.pos + Vector2(0, -50))
    u.order = "attack_move"
    u.attack_kind = "unit"
    u.attack_id = enemy
    game._sync_units()
    game.unit_visuals[id].visual._process(1.0)
    faces(game, id, Vector2.UP, check, "Engaged soldier retains enemy aim")
    game.sim.units.erase(enemy)
    u.pos += Vector2(6, 0)
    game._sync_units()
    faces(game, id, Vector2.RIGHT, check, "Removed target resumes actual movement facing")

    # Exercise the existing client velocity input, including a backwards
    # position correction and a stationary authoritative update.
    game.connected = true
    game.is_host = false
    var previous := {id: u.pos}
    u.pos += Vector2(0, -5)
    game._update_render_velocities(previous, 1, 2)
    game._sync_units()
    faces(game, id, Vector2.UP, check, "Client snapshot velocity drives facing")
    u.pos += Vector2(0, 2)
    game._sync_units()
    faces(game, id, Vector2.UP, check, "Client correction cannot reverse facing")
    game._update_render_velocities({id: u.pos}, 2, 3)
    game._sync_units()
    faces(game, id, Vector2.UP, check, "Zero snapshot velocity preserves facing")
    game.connected = false
    game.sim.units.erase(id)
    game._sync_units()
    check.call(not game.unit_visuals.has(id), "Despawn removes facing cache")
    game.sim.units[id] = u.duplicate(true)
    game.sim.units[id].order = "idle"
    game._sync_units()
    check.call(not game.unit_visuals[id].get("has_moved", false), "Reused ID starts without movement history")
    game.visual_sync.reset_world()
    check.call(game.unit_visuals.is_empty(), "World reset clears facing records")
    game.render_velocities.clear()


static func routes(game, check: Callable, capture: bool = false) -> void:
    for route: String in ["highland", "quarry"]:
        game.sim.units.clear()
        game._sync_units()
        var start := Vector2(2296, 1512) if route == "highland" else Vector2(2400, 1470)
        var target := Vector2(1876, 1900) if route == "highland" else Vector2(3016, 1782)
        var id: int = game.sim.add_unit(1, "soldier", start)
        check.call(game.sim.command(1, {"action": "move", "units": [id], "pos": target}).is_empty(), "Accept " + route + " movement")
        game._sync_units()
        var diverged := 0
        var captured := {"turn": false, "ramp": false}
        for tick in range(600):
            var previous: Vector2 = game.sim.units[id].pos
            game.sim.step()
            game._sync_units()
            var u: Dictionary = game.sim.units[id]
            var motion: Vector2 = u.pos - previous
            if motion.length_squared() > 0.0001 and u.order == "move":
                faces(game, id, motion, check, route + " faces actual path displacement")
                var goal_direction: Vector2 = (target - previous).normalized()
                var turning: bool = motion.normalized().dot(goal_direction) < 0.65
                if turning:
                    diverged += 1
                var on_ramp: bool = absf(game.sim.terrain.height_at(u.pos)) > 25 and game.sim.terrain.gradient_at(u.pos).length() > 0.02
                var shot := "turn" if turning and not captured.turn else "ramp" if on_ramp and not captured.ramp else ""
                if capture and not shot.is_empty():
                    captured[shot] = true
                    game.camera_controller.focus = u.pos
                    game.camera_zoom_level = 2.4
                    game._update_camera_transform()
                    game.hud.visible = false
                    game._sync_visuals()
                    for frame in range(4):
                        await game.get_tree().process_frame
                    await RenderingServer.frame_post_draw
                    var path := "res://assets/concept_art/soldier-heading-" + route + "-" + shot + "-v1.png"
                    check.call(game.get_viewport().get_texture().get_image().save_png(path) == OK, "Save " + route + " " + shot)
            if (u.pos as Vector2).distance_to(target) < 14:
                break
        check.call(diverged > 5, route + " includes real detour away from destination")
        check.call((game.sim.units[id].pos as Vector2).distance_to(target) < 20, route + " reaches destination")
        if capture:
            check.call(captured.turn and captured.ramp, route + " captured detour and slope")
    game.hud.visible = true
