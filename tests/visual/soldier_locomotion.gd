extends SceneTree

const Visual = preload("res://assets/art/entity_visual.gd")
var failures: Array[String] = []
var worst_slide := 0.0
var worst_ground := 0.0
var worst_weapon_step := 0.0

class FlatGround:
    func height_at(_point: Vector2) -> float:
        return 0.0


func check_curved_gait(fps: int, guest: bool) -> void:
    var ground := FlatGround.new()
    for radius: float in [25.0, 50.0, 100.0]:
        var visual := Visual.new("soldier", 1)
        root.add_child(visual)
        var motion = visual.soldier_motion
        var lowest := INF
        var largest_drop := 0.0
        var largest_ik_drop := 0.0
        var previous_ik_offset := 0.0
        var last_height := 1.24
        var last_feet := [Vector3.ZERO, Vector3.ZERO]
        var last_planted := [false, false]
        var dt := 1.0 / fps
        for step in range(fps * 6):
            var time := step * dt
            var tick := int(floor(time * 20.0 + .000001))
            var angle := (time if guest else tick * .05) * 100.0 / radius
            var heading := Vector2.RIGHT.rotated(angle)
            var position := Vector2(sin(angle), 1.0 - cos(angle)) * radius
            visual.set_heading(heading, true)
            motion.sample(position, dt, tick, maxf(time * 20.0 - tick, 0), ground, guest, heading * 100, Vector2.ZERO)
            var pelvis: float = motion.skeleton.get_bone_global_pose(motion.bones.Pelvis).origin.y
            # Separate the deliberately larger running rebound from unwanted
            # leg-reach corrections; keep the original correction-jump limit.
            var gait: Vector4 = motion._gait_key(motion.phase + motion.cycle_offset)
            var authored_height: float = 1.24 - .07 * motion.blend + gait.y * pow(motion.stride_length / motion.STRIDE, 2.0) * motion.blend
            var ik_offset := pelvis - authored_height
            for i in 2:
                var sole := actual_sole(motion, i)
                if motion.planted[i]:
                    check(absf(sole.y) < .5, "Curved travel keeps planted feet on the ground")
                    if last_planted[i]:
                        check(Vector2(sole.x, sole.z).distance_to(Vector2(last_feet[i].x, last_feet[i].z)) < 1.0,
                            "Curved travel keeps planted feet locked")
                last_feet[i] = sole
                last_planted[i] = motion.planted[i]
            if time > .4:
                if pelvis < .9 and lowest >= .9:
                    print("CURVE_CONTACT step=", step, " phase=", motion.phase + motion.cycle_offset, " feet=", visual.to_local(motion.feet[0]), " / ", visual.to_local(motion.feet[1]), " planted=", motion.planted)
                lowest = minf(lowest, pelvis)
                largest_drop = maxf(largest_drop, last_height - pelvis)
                largest_ik_drop = maxf(largest_ik_drop, previous_ik_offset - ik_offset)
            last_height = pelvis
            previous_ik_offset = ik_offset
        print("CURVED_GAIT fps=", fps, " guest=", guest, " radius=", radius, " min_pelvis=", lowest,
            " max_drop=", largest_drop, " max_ik_drop=", largest_ik_drop)
        check(lowest > 1.0 and largest_ik_drop < .04 and largest_ik_drop / dt < 3.0,
            "Curved travel cannot add pelvis collapse beyond the authored running rebound")
        check(largest_drop / dt < 5.0, "Running rebound has bounded vertical speed")
        visual.free()


func _initialize() -> void:
    run.call_deferred()


func check(value: bool, message: String) -> void:
    if not value and not failures.has(message):
        failures.append(message)
        push_error(message)


func actual_sole(motion, index: int) -> Vector3:
    var side := "L" if index == 0 else "R"
    var bone: int = motion.bones["Foot_" + side]
    var deformation: Transform3D = motion.skeleton.get_bone_global_pose(bone) * motion.rests[bone].affine_inverse()
    return motion.skeleton.global_transform * (deformation * Vector3(-.22 if index == 0 else .22, 0, 0))


func traverse(terrain, fps: int, start: Vector2, heading: Vector2, speed: float, seconds: float) -> float:
    var visual := Visual.new("soldier", 1)
    root.add_child(visual)
    visual.set_heading(heading, true)
    visual.set_animation("move")
    var motion = visual.soldier_motion
    var dt := 1.0 / fps
    motion.sample(start, dt, 0, 0, terrain, false, Vector2.ZERO, Vector2.ZERO)
    var last_feet := [actual_sole(motion, 0), actual_sole(motion, 1)]
    var last_planted: Array = motion.planted.duplicate()
    for step in range(1, int(seconds * fps) + 1):
        var time := step * dt
        var tick := int(floor(time * 20.0 + .000001))
        var raw := start + heading * (tick * .05 * speed)
        motion.sample(raw, dt, tick, maxf(time * 20.0 - tick, 0.0), terrain, false, Vector2.ZERO, Vector2.ZERO)
        for i in 2:
            var sole := actual_sole(motion, i)
            if motion.planted[i]:
                var height_error := absf(sole.y - terrain.height_at(Vector2(sole.x, sole.z)))
                worst_ground = maxf(worst_ground, height_error)
                check(height_error < .5, "Planted sole stays within 0.5 world units of terrain")
                if last_planted[i] and step > 1:
                    var slide := Vector2(sole.x, sole.z).distance_to(Vector2(last_feet[i].x, last_feet[i].z))
                    worst_slide = maxf(worst_slide, slide)
                    check(slide < 1.0, "Planted sole slides less than 1 world unit per frame")
            last_feet[i] = sole
            last_planted[i] = motion.planted[i]
        for side: String in ["L", "R"]:
            var thigh: int = motion.bones["Thigh_" + side]
            var shin: int = motion.bones["Shin_" + side]
            var ankle: int = motion.bones["Foot_" + side]
            var a: Vector3 = motion.skeleton.get_bone_global_pose(thigh).origin
            var b: Vector3 = motion.skeleton.get_bone_global_pose(shin).origin
            var c: Vector3 = motion.skeleton.get_bone_global_pose(ankle).origin
            check(absf(a.distance_to(b) - motion.rests[thigh].origin.distance_to(motion.rests[shin].origin)) < .001, "Thigh never stretches")
            check(absf(b.distance_to(c) - motion.rests[shin].origin.distance_to(motion.rests[ankle].origin)) < .001, "Shin never stretches")
    var travelled: float = motion.distance
    var stopped: Vector2 = motion.current
    # Still ordered to move but blocked: no displacement must stop the gait.
    for step in range(fps):
        motion.sample(stopped, dt, 10000 + step, 1.0, terrain, false, Vector2.ZERO, Vector2.ZERO)
    var stopped_phase: float = motion.phase
    for step in range(fps):
        motion.sample(stopped, dt, 20000 + step, 1.0, terrain, false, Vector2.ZERO, Vector2.ZERO)
    check(is_equal_approx(motion.phase, stopped_phase) and motion.blend == 0, "Blocked soldier stops gait without resetting phase")
    check(motion.planted[0] and motion.planted[1], "Stop settles both feet")
    # Client correction does not add its correction distance to stride phase.
    var old_distance: float = motion.distance
    motion.sample(stopped + Vector2(0, -2), dt, 30000, 0, terrain, true, Vector2(100, 0), Vector2.ZERO)
    check(absf(motion.distance - old_distance - 100 * dt) < .001, "Guest correction is excluded from step distance")
    old_distance = motion.distance
    motion.sample(stopped, dt, 30001, 0, terrain, true, Vector2.ZERO, Vector2.ZERO)
    check(is_equal_approx(motion.distance, old_distance), "Zero guest velocity cannot advance gait")
    motion.sample(start + Vector2(1000, 0), dt, 0, 0, terrain, false, Vector2.ZERO, Vector2.ZERO)
    check(motion.distance == 0 and motion.phase == 0, "Teleport or frame reset clears locomotion history")
    visual.free()
    return travelled


func run() -> void:
    for fps in [30, 60, 144]:
        check_curved_gait(fps, true)
        check_curved_gait(fps, false)
    var sim = preload("res://scripts/simulation.gd").new()
    sim.reset(false, "desert_sample")
    var distances: Array[float] = []
    for fps in [30, 60, 144]:
        distances.append(traverse(sim.terrain, fps, Vector2(2200, 1300), Vector2.RIGHT, 100, 2.0))
    check(absf(distances.max() - distances.min()) < .01, "30/60/144 FPS cover equal rendered distance")
    for speed in [50.0, 150.0]:
        var d := traverse(sim.terrain, 60, Vector2(2200, 1300), Vector2.RIGHT, speed, 2.0)
        check(absf(d - distances[1] * speed / 100.0) < .01, "Stride distance follows actual speed")
    for x in [1876.0, 2876.0]:
        traverse(sim.terrain, 60, Vector2(x, 1160), Vector2.DOWN, 100, 5.0)
        traverse(sim.terrain, 60, Vector2(x, 1660), Vector2.UP, 100, 5.0)
    var visual := Visual.new("soldier", 1)
    root.add_child(visual)
    var motion = visual.soldier_motion
    var position := Vector2(2200, 1350)
    var last_weapon := Vector3.ZERO
    var last_attack_blend := 0.0
    var last_move_blend := 0.0
    for step in range(360):
        # Return across the flat test lane instead of crossing its cliff edge.
        var heading := Vector2.RIGHT if step < 60 or step >= 240 else Vector2.DOWN if step < 120 else Vector2.LEFT
        var moving := (step < 150 or step >= 190) and not (step >= 250 and step < 253)
        moving = moving and not (step >= 270 and step < 275) and not (step >= 300 and step < 312)
        if moving:
            position += heading * (100.0 / 60.0)
            visual.set_heading(heading, true)
        visual.set_animation("move" if moving else "attack")
        var aim := Vector2.UP if step >= 120 else Vector2.ZERO
        motion.sample(position, 1.0 / 60.0, step, 1.0, sim.terrain, true, heading * 100 if moving else Vector2.ZERO, aim)
        for i in 2:
            var sole := actual_sole(motion, i)
            if sole.y < sim.terrain.height_at(Vector2(sole.x, sole.z)) - .5:
                print("SOLE_PENETRATION step=", step, " foot=", i, " error=", sole.y - sim.terrain.height_at(Vector2(sole.x, sole.z)))
            check(sole.is_finite() and sole.y >= sim.terrain.height_at(Vector2(sole.x, sole.z)) - .5, "Turn/start/stop cannot penetrate ground")
        var weapon: Vector3 = motion.muzzle.position
        # Instant heading/aim changes are intentional RTS response. Check pose
        # continuity separately from the two commanded aim direction changes.
        if step > 0 and step not in [120, 240]:
            worst_weapon_step = maxf(worst_weapon_step, weapon.distance_to(last_weapon))
            # The muzzle sweeps an 80-degree arc when raising from vertical
            # carry, plus a 50-degree idle/run arc. Bound those transitions
            # separately; steady-gait continuity retains its original limit.
            var limit: float = minf(.85, .15 + 2.2 * absf(motion.attack_blend - last_attack_blend)
                + 1.4 * absf(motion.blend - last_move_blend))
            if weapon.distance_to(last_weapon) >= limit:
                print("POSE_JUMP step=", step, " delta=", weapon - last_weapon, " blend=", motion.blend, " phase=", motion.phase)
            check(weapon.distance_to(last_weapon) < limit, "Weapon respects steady-gait and fast carry-transition bounds")
        last_weapon = weapon
        last_attack_blend = motion.attack_blend
        last_move_blend = motion.blend
        if step == 180:
            check(motion.blend == 0 and motion.attack_blend > .99, "Attack blends in after stopping")
    visual.free()
    print("SOLDIER_LOCOMOTION ", JSON.stringify({"distances": distances, "max_planted_slide": worst_slide, "max_ground_error": worst_ground, "max_weapon_step": worst_weapon_step, "failures": failures}))
    quit(0 if failures.is_empty() else 1)
