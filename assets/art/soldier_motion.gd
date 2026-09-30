extends RefCounted
## Render-only locomotion. No simulation position, orders or snapshot writes.

const STRIDE := 56.0
const SCALE := 24.0
const STANCE := 0.52

var visual: Node3D
var skeleton: Skeleton3D
var bones := {}
var rests: Array[Transform3D] = []
var parents: Array[int] = []
var poses: Array[Transform3D] = []
var phase := 0.0
var stride_length := STRIDE
var turn_rate := 0.0
var distance := 0.0
var blend := 0.0
var clock := 0.0
var attack_blend := 0.0
var aim_yaw := 0.0
var pose_delta := 0.0
var initialized := false
var sample_frame := -1
var previous := Vector2.ZERO
var current := Vector2.ZERO
var last_display := Vector2.ZERO
var last_forward := Vector3.ZERO
var feet: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var planted: Array[bool] = [true, true]
var swing_start: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var swing_end: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var swing_phase: Array[float] = [STANCE, STANCE]
var foot_pitch: Array[float] = [0.0, 0.0]
var cycle_offset := STANCE * 0.5
var was_moving := false
var settling := 0.0
var terrain
var muzzle: Node3D


func _init(owner: Node3D) -> void:
    visual = owner
    skeleton = owner.model.find_children("*", "Skeleton3D", true, false)[0]
    muzzle = owner.model.get_node("soldier/Muzzle")
    for i in skeleton.get_bone_count():
        bones[skeleton.get_bone_name(i)] = i
        rests.append(skeleton.get_bone_global_rest(i))
        poses.append(rests[i])
        parents.append(skeleton.get_bone_parent(i))


func sample(raw: Vector2, dt: float, frame: int, alpha: float, ground,
        guest: bool, velocity: Vector2, aim: Vector2) -> void:
    terrain = ground
    pose_delta = dt
    var reset := not initialized or raw.distance_to(current) > 40.0 or frame < sample_frame
    if reset:
        previous = raw
        current = raw
        last_display = raw
        phase = 0.0
        stride_length = STRIDE
        turn_rate = 0.0
        blend = 0.0
        aim_yaw = 0.0
        distance = 0.0
        cycle_offset = STANCE * 0.5
        was_moving = false
        settling = 0.0
        last_forward = Vector3.ZERO
        initialized = true
    elif frame != sample_frame:
        previous = current
        current = raw
    sample_frame = frame
    var display := raw if guest or dt <= 0.0 else previous.lerp(current, clampf(alpha, 0.0, 1.0))
    var motion := display - last_display
    # Guest corrections relocate the foot anchors but do not advance the gait.
    if guest and not reset and dt > 0.0:
        var expected := velocity * dt
        var correction := motion - expected
        if correction.length() > 0.5:
            var offset := Vector3(correction.x, 0, correction.y)
            for i in 2:
                feet[i] += offset
                swing_start[i] += offset
                swing_end[i] += offset
        motion = expected
    visual.set_position_2d(display, terrain.height_at(display))
    last_display = display
    if reset:
        for i in 2:
            feet[i] = _neutral_foot(i)
            swing_start[i] = feet[i]
            swing_end[i] = feet[i]
            planted[i] = true
            swing_phase[i] = STANCE
            foot_pitch[i] = 0.0
    if dt <= 0.0:
        if reset:
            _pose(aim)
        return
    clock += dt
    var travel := 0.0 if reset else motion.length()
    var speed := travel / dt
    var moving := speed > 0.5
    var forward_now: Vector3 = visual.get_visual_forward()
    var turn := acos(clampf(forward_now.dot(last_forward), -1.0, 1.0)) if last_forward.length_squared() > .1 else 0.0
    # Host headings arrive at 20Hz; filtering avoids alternating between a
    # very tight bend and a straight stride on successive rendered frames.
    turn_rate = lerpf(turn_rate, turn / dt, 1.0 - exp(-dt / .12))
    # The outside foot covers more ground around a bend. Use shorter, quicker
    # steps there instead of holding it until a straight-line stride ends.
    var target_stride := clampf(STRIDE / (1.0 + turn_rate * 20.0 / maxf(speed, .5)), 32.0, STRIDE)
    stride_length = move_toward(stride_length, target_stride, dt * 160.0)
    if last_forward.length_squared() > .1 and forward_now.dot(last_forward) < .7:
        # A sharp path corner needs new contacts, not legs twisted around old
        # world-space anchors. Phase is retained across this replant.
        for i in 2:
            feet[i] = _neutral_foot(i)
            swing_start[i] = feet[i]
            swing_end[i] = feet[i]
            planted[i] = true
        cycle_offset = STANCE * .5 - phase
        for i in 2:
            swing_phase[i] = maxf(STANCE, fposmod(phase + cycle_offset + i * .5, 1.0))
    last_forward = forward_now
    distance += travel
    phase = fposmod(phase + travel / stride_length, 1.0)
    if moving and not was_moving:
        # Re-time contacts from the settling pose, including very short stops.
        # Accumulated distance and the distance-driven phase remain intact.
        var lead := 0
        var lead_offset := (feet[0] - _neutral_foot(0)).dot(forward_now)
        var other_offset := (feet[1] - _neutral_foot(1)).dot(forward_now)
        if other_offset > lead_offset:
            lead = 1
            lead_offset = other_offset
        var contact_phase := clampf(STANCE * .5 - lead_offset / stride_length, .04, .48)
        cycle_offset = contact_phase - phase - lead * .5
        for i in 2:
            planted[i] = true
            swing_phase[i] = maxf(STANCE, fposmod(phase + cycle_offset + i * .5, 1.0))
    was_moving = moving
    blend = move_toward(blend, 1.0 if moving else 0.0, dt / (0.15 if moving else 0.2))
    attack_blend = move_toward(attack_blend, 1.0 if visual.animation_state == "attack" else 0.0, dt / 0.15)
    if moving:
        settling = 0.0
    else:
        if settling == 0.0:
            for i in 2:
                swing_start[i] = feet[i]
                swing_end[i] = _neutral_foot(i)
        settling += dt
    for i in 2:
        var p := fposmod(phase + cycle_offset + i * 0.5, 1.0)
        var neutral := _neutral_foot(i)
        foot_pitch[i] = 0.0
        if not moving:
            # Two small staggered settling steps rather than dragging both
            # soles along the ground when stopping between gait contacts.
            var t := clampf((settling - i * 0.06) / 0.14, 0.0, 1.0)
            var eased := t * t * (3.0 - 2.0 * t)
            feet[i] = swing_start[i].lerp(swing_end[i], eased)
            feet[i].y += sin(t * PI) * 2.0
            planted[i] = t >= 1.0
        elif p < STANCE:
            if not planted[i]:
                feet[i] = swing_end[i]
                planted[i] = true
                swing_phase[i] = STANCE
        else:
            if planted[i]:
                planted[i] = false
                swing_start[i] = feet[i]
                # Keep phase overshoot since lift-off instead of delaying the
                # foot by a whole rendered frame (especially visible at 30Hz).
            # Refresh the landing prediction during the swing. A fixed target
            # drifts out to the side when the path bends after lift-off.
            swing_end[i] = neutral + forward_now * (stride_length * (1.0 - p + STANCE * 0.5))
            swing_end[i].y = _height(swing_end[i])
            var t := clampf((p - swing_phase[i]) / maxf(1.0 - swing_phase[i], .001), 0.0, 1.0)
            var eased := t * t * (3.0 - 2.0 * t)
            feet[i] = swing_start[i].lerp(swing_end[i], eased)
            feet[i].y = maxf(feet[i].y, _height(feet[i])) + sin(t * PI) * 4.5 * blend
            # Toe trails the shin after lift-off, then rises before touchdown.
            foot_pitch[i] = sin(t * TAU) * .32 * blend
        if planted[i]:
            feet[i].y = _height(feet[i])
    _pose(aim)


func _height(point: Vector3) -> float:
    return terrain.height_at(Vector2(point.x, point.z))


func _neutral_foot(index: int) -> Vector3:
    var result: Vector3 = visual.global_transform * Vector3((-0.22 if index == 0 else 0.22) * SCALE, 0, 0)
    result.y = _height(result)
    return result


func _put(name: String, rotation: Basis, origin: Vector3) -> void:
    var index: int = bones[name]
    poses[index] = Transform3D(rotation * rests[index].basis, origin)


func _segment(name: String, next_name: String, start: Vector3, end: Vector3) -> void:
    var rest_direction: Vector3 = rests[bones[next_name]].origin - rests[bones[name]].origin
    var rotation := Basis(Quaternion(rest_direction.normalized(), (end - start).normalized()))
    _put(name, rotation, start)


func _pose(aim: Vector2) -> void:
    var inverse := skeleton.global_transform.affine_inverse()
    # The skeleton's bind frame is Y-up and scaled only by the visual model.
    var cycle := phase + cycle_offset
    var bob := -0.015 * blend + cos(cycle * TAU * 2.0) * 0.012 * blend
    var pelvis := Vector3(sin(cycle * TAU) * .015 * blend, 1.24 - 0.12 * blend + bob, 0)
    # Lower the pelvis before solving, so slopes and long planted strides
    # remain reachable without stretching the leg or lifting a planted foot.
    for i in 2:
        var ankle: Vector3 = inverse * (feet[i] + Vector3.UP * .16 * SCALE)
        var hip_x := -.22 if i == 0 else .22
        var lateral := Vector2(ankle.x - hip_x, ankle.z).length_squared()
        pelvis.y = minf(pelvis.y, ankle.y + sqrt(maxf(1.10 * 1.10 - lateral, .01)) - .015)
    var yaw := 0.0
    if aim.length_squared() > 0.01:
        var local_aim := visual.global_transform.basis.inverse() * Vector3(aim.x, 0, aim.y)
        yaw = clampf(atan2(local_aim.x, local_aim.z), -0.55, 0.55)
    aim_yaw = lerpf(aim_yaw, yaw, 1.0 - exp(-pose_delta / .25)) if pose_delta > 0.0 else yaw
    var upper := Basis(Vector3.UP, aim_yaw + sin(phase * TAU) * 0.035 * blend)
    upper = upper * Basis(Vector3.RIGHT, 0.065 * blend)
    var breath := sin(clock * 2.4) * 0.006 * (1.0 - blend)
    var recoil := sin(clampf(fposmod(clock, 0.6) / 0.12, 0.0, 1.0) * PI) * 0.06 * attack_blend
    var torso_offset := pelvis - Vector3(0, 1.27, 0) + Vector3(0, breath, -recoil)
    _put("Pelvis", Basis(Vector3.UP, -sin(phase * TAU) * .025 * blend), pelvis)
    for name: String in ["Spine", "Head", "Weapon", "UpperArm_L", "Forearm_L", "Hand_L", "UpperArm_R", "Forearm_R", "Hand_R"]:
        var p: Vector3 = rests[bones[name]].origin
        _put(name, upper, Vector3(0, 1.57, 0) + upper * (p - Vector3(0, 1.57, 0)) + torso_offset)
    # Keep the head steadier than the chest while the rifle stays in both hands.
    _put("Head", Basis(Vector3.UP, aim_yaw + sin(phase * TAU) * .015 * blend)
        * Basis(Vector3.RIGHT, .025 * blend), poses[bones.Head].origin)
    for i in 2:
        var side := "L" if i == 0 else "R"
        var hip := pelvis + Vector3(-0.22 if i == 0 else 0.22, 0, 0)
        var ankle: Vector3 = inverse * (feet[i] + Vector3.UP * .16 * SCALE)
        var upper_length := rests[bones["Thigh_" + side]].origin.distance_to(rests[bones["Shin_" + side]].origin)
        var lower_length := rests[bones["Shin_" + side]].origin.distance_to(rests[bones["Foot_" + side]].origin)
        var vector := ankle - hip
        var reach := clampf(vector.length(), .1, upper_length + lower_length - .002)
        var axis := vector.normalized()
        var bend := (Vector3.FORWARD * -1.0).slide(axis).normalized()
        var along := (upper_length * upper_length - lower_length * lower_length + reach * reach) / (2.0 * reach)
        var knee := hip + axis * along + bend * sqrt(maxf(upper_length * upper_length - along * along, 0.0))
        ankle = hip + axis * reach
        _segment("Thigh_" + side, "Shin_" + side, hip, knee)
        _segment("Shin_" + side, "Foot_" + side, knee, ankle)
        var world_forward: Vector3 = visual.get_visual_forward()
        var sample_front := feet[i] + world_forward * 3.0
        var sample_back := feet[i] - world_forward * 3.0
        var slope := clampf((_height(sample_front) - _height(sample_back)) / 6.0, -.5, .5)
        _put("Foot_" + side, Basis(Vector3.RIGHT, -atan(slope) + foot_pitch[i]), ankle)
    for index in poses.size():
        var parent := parents[index]
        var local := poses[index] if parent < 0 else poses[parent].affine_inverse() * poses[index]
        skeleton.set_bone_pose(index, local)
    var weapon: Transform3D = poses[bones.Weapon] * rests[bones.Weapon].affine_inverse()
    muzzle.position = weapon * Vector3(.17, 1.84, 1.36)


func foot_world(index: int) -> Vector3:
    var side := "L" if index == 0 else "R"
    var pose: Transform3D = poses[bones["Foot_" + side]]
    var deform := pose * rests[bones["Foot_" + side]].affine_inverse()
    return skeleton.global_transform * (deform * Vector3(-.22 if index == 0 else .22, 0, 0))
