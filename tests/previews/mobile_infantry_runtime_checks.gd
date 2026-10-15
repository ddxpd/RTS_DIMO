extends Node3D
## Fresh-process coverage for controller, imported poses and gameplay dependencies.

const Sim = preload("res://scripts/simulation.gd")
const Visual = preload("res://assets/art/entity_visual.gd")
signal finished(success: bool)
var failures: Array[String] = []
var checks := 0


func check(value: bool, label: String) -> void:
    checks += 1
    if not value:
        failures.append(label)


func _ready() -> void:
    run.call_deferred()


func run() -> void:
    for path in ["res://tests/visual/test_mobile_infantry.gd", "res://tests/simulation/test_mobile_infantry_gameplay.gd"]:
        var suite = load(path).new()
        for method: Dictionary in suite.get_method_list():
            if not str(method.name).begins_with("test_"):
                continue
            suite._reset()
            suite.call(method.name)
            checks += suite._assertion_count
            if suite._failed:
                failures.append(str(method.name) + ": " + suite._message)
            suite._free_tracked()
    var sim := Sim.new()
    sim.reset(true, "desert_sample")
    sim.units.clear()
    var visual := Visual.new("mobile_infantry", 1)
    add_child(visual)
    visual.set_process(false)
    var motion = visual.mobile_motion
    var skeleton: Skeleton3D = motion.skeleton
    check(is_equal_approx(visual.get_model_height(), 45.333333), "New model height is two thirds of 68")
    check(is_equal_approx(visual.model.scale.x, (68.0 / 1.849) * 2.0 / 3.0), "Body uses the agreed uniform scale")
    check(is_equal_approx(motion.walk_stride, 0.80 * visual.model.scale.x) and is_equal_approx(motion.jog_stride, 1.50 * visual.model.scale.x), "Both gait strides follow actual model scale")
    check(visual.mobile_weapon != null and is_equal_approx(visual.mobile_weapon.global_basis.get_scale().x, visual.model.scale.x), "Independent gun inherits body scale exactly once")
    # A steady displacement must advance gait by distance/new stride, not old size.
    motion.sample({"pos": Vector2(800, 1200), "cooldown": 0}, 0, 0, sim.terrain, Vector2.ZERO)
    for speed_value: float in [30.0, 100.0]:
        visual.set_position_2d(Vector2(800, 1200))
        motion.speed = speed_value
        motion.phase = 0.0
        var old := visual.position
        motion.sample({"pos": Vector2(800, 1200 + speed_value / 60.0 / (1.0 - exp(-18.0 / 60.0))), "cooldown": 0}, 1.0 / 60.0, 0, sim.terrain, Vector2.ZERO)
        var travelled := Vector2(visual.position.x - old.x, visual.position.z - old.z).length()
        var stride: float = motion.jog_stride if speed_value > 55.0 else motion.walk_stride
        check(absf(motion.phase - travelled / stride) < 0.0001, "Gait phase follows displacement at speed " + str(speed_value))
    check(visual.mobile_weapon != null, "Independent machine gun attached")
    if visual.mobile_weapon != null:
        for action in ["RESET", "idle", "walk", "jog", "fire", "death"]:
            var clip_length: float = motion.player.get_animation(action).length
            var max_grip_error := 0.0
            for sample in range(9):
                motion.player.play(action)
                motion.player.seek(clip_length * sample / 8.0, true)
                motion.player.advance(0.0)
                skeleton.force_update_all_bone_transforms()
                preload("res://assets/art/units/mobile_infantry/mobile_infantry_weapon.gd").sync(visual.mobile_weapon)
                for side in ["L", "R"]:
                    var anchor := visual.mobile_weapon.find_child("GripLeft" if side == "L" else "GripRight", true, false) as Node3D
                    if anchor == null:
                        max_grip_error = INF
                        continue
                    var palm := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand." + side)).origin
                    max_grip_error = maxf(max_grip_error, palm.distance_to(anchor.global_position))
            check(max_grip_error < 0.8, "Both hands follow independent gun in %s: %.4f" % [action, max_grip_error])
        motion.player.play("RESET")
        motion.player.advance(0.0)
    for ramp: Dictionary in sim.terrain.definition.ramps:
        for reverse in [false, true]:
            var direction: Vector2 = (ramp.end - ramp.start).normalized()
            var start: Vector2 = ramp.start - direction * 40.0
            var target: Vector2 = ramp.end + direction * 40.0
            if reverse:
                var swap := start
                start = target
                target = swap
            sim.units.clear()
            var id := sim.add_unit(1, "mobile_infantry", start)
            visual.set_position_2d(start, sim.terrain.height_at(start))
            check(sim.command(1, {"action": "move", "units": [id], "pos": target}).is_empty(), "Slope command")
            var valid := true
            var max_height_step := 0.0
            for tick in range(240):
                sim.step()
                for frame in range(3):
                    var previous_y := visual.position.y
                    motion.sample(sim.units[id], 1.0 / 60.0, sim.frame, sim.terrain, Vector2.ZERO)
                    visual._process(1.0 / 60.0)
                    max_height_step = maxf(max_height_step, absf(visual.position.y - previous_y))
                    for bone in range(skeleton.get_bone_count()):
                        valid = valid and skeleton.get_bone_global_pose(bone).is_finite()
                if sim.units[id].pos.distance_to(target) < 14.0:
                    break
            check(sim.units[id].pos.distance_to(target) < 14.0, "Infantry traverses slope in both directions")
            check(valid, "Slope IK produces finite bone transforms")
            check(max_height_step < 3.0, "Slope movement has no height snap")
            sim.command(1, {"action": "stop", "units": [id]})
            for frame in range(90):
                motion.sample(sim.units[id], 1.0 / 60.0, sim.frame, sim.terrain, Vector2.ZERO)
            check(motion.clip == "idle", "Stop settles to idle")
            var phase: float = motion.phase
            for frame in range(20):
                motion.sample(sim.units[id], 1.0 / 60.0, sim.frame, sim.terrain, Vector2.ZERO)
            check(is_equal_approx(phase, motion.phase), "Stationary infantry does not keep stepping")
    # Check death really falls, and fire uses the current aimed action.
    var player: AnimationPlayer = motion.player
    player.play("fire")
    player.seek(0.25, true)
    player.advance(0.0)
    skeleton.clear_bones_global_pose_override()
    skeleton.force_update_all_bone_transforms()
    check(skeleton.get_bone_global_pose(skeleton.find_bone("weapon")).origin.y > 1.30, "Aimed firing action")
    player.play("death")
    player.seek(1.2, true)
    player.advance(0.0)
    skeleton.force_update_all_bone_transforms()
    check(skeleton.get_bone_global_pose(skeleton.find_bone("head")).origin.y < 0.4, "Death lowers head to floor")
    visual.free()
    var game := load("res://scenes/main.tscn").instantiate() as Node3D
    add_child(game)
    game.play_solo()
    game.set_process(false)
    game.set_process_input(false)
    game.set_process_unhandled_input(false)
    var refinery: int = game.sim._add_building(1, "refinery", Vector2(1000, 600), true)
    var barracks: int = game.sim._add_building(1, "barracks", Vector2(800, 600), true)
    game.selected_building = refinery
    game.selected_buildings.assign([refinery, barracks])
    game._produce("mobile_infantry")
    check(game.sim.buildings[refinery].queue.is_empty(), "Mixed building selection skips incompatible producer")
    check(game.sim.buildings[barracks].queue.size() == 1, "Actual UI production selects barracks")
    var id: int = game.sim.add_unit(1, "mobile_infantry", Vector2(1200, 600))
    game.visual_sync.sync(0.016)
    var live_visual = game.visual_sync.unit_visuals[id].visual
    check(is_equal_approx(game.visual_sync._selection_ring_radius("mobile_infantry", Sim.UNIT_TYPES.mobile_infantry.radius), 15.0), "Selection ring follows smaller radius")
    var health: Dictionary = game.visual_sync.health_grid_overlay.entries["unit_%d" % id]
    check(absf(health.world_position.y - live_visual.global_position.y - 57.333333) < 0.001, "Actual health anchor follows smaller height")
    game.sim.units.erase(id)
    game.visual_sync.sync(0.016)
    check(game.visual_sync.mobile_deaths.is_empty(), "Removal without death event does not create a corpse")
    id = game.sim.add_unit(1, "mobile_infantry", Vector2(1200, 600))
    game.visual_sync.sync(0.016)
    game.sim.units[id].hp = 0
    game.sim.step()
    game.visual_sync.sync(0.016)
    check(game.visual_sync.mobile_deaths.size() == 1, "Confirmed death transfers visual")
    game.visual_sync.reset_world()
    check(game.visual_sync.mobile_deaths.is_empty(), "Map reset clears corpse references")
    game.free()
    # CPU sampling measurement only: this is not a complete GPU/FPS benchmark.
    var crowd: Array[Node3D] = []
    for index in range(100):
        var actor := Visual.new("mobile_infantry", 1 + index % 2)
        add_child(actor)
        actor.set_process(false)
        actor.set_position_2d(Vector2(2200 + index * 35, 2300))
        crowd.append(actor)
    var started := Time.get_ticks_usec()
    for frame in range(60):
        for index in range(crowd.size()):
            var actor := crowd[index]
            var unit := {"pos": Vector2(2200 + index * 35, 2300 + frame * 1.667), "cooldown": 0}
            actor.mobile_motion.sample(unit, 1.0 / 60.0, frame, sim.terrain, Vector2.ZERO)
    var cpu_frame_ms := (Time.get_ticks_usec() - started) / 60000.0
    if crowd[0].mobile_weapon != null and crowd[1].mobile_weapon != null:
        var gun_a: MeshInstance3D = crowd[0].mobile_weapon.find_children("*", "MeshInstance3D", true, false)[0]
        var gun_b: MeshInstance3D = crowd[1].mobile_weapon.find_children("*", "MeshInstance3D", true, false)[0]
        check(gun_a.mesh == gun_b.mesh, "Units share weapon mesh")
        check(gun_a.get_active_material(0) == gun_b.get_active_material(0), "Units share weapon material")
    for actor in crowd:
        actor.free()
    print("MOBILE_INFANTRY_RUNTIME_CHECKS ", {"checks": checks, "failures": failures, "100_unit_animation_cpu_ms_per_frame": cpu_frame_ms})
    if not failures.is_empty():
        push_error("Mobile infantry checks failed: " + str(failures))
    finished.emit(failures.is_empty())
