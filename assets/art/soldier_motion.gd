extends RefCounted
## Render-only locomotion. No simulation position, orders or snapshot writes.

const STRIDE := 56.0
const SCALE := 24.0
const STANCE := 0.34
const RUN_CARRY_PITCH := deg_to_rad(80.0)
# Authored contact / compression / passing / lift poses. x: lateral shift,
# y: vertical compression, z: chest roll, w: chest pitch (model units/radians).
const JOG_KEYS := [Vector4(-.012, .005, -.025, .23), Vector4(-.024, -.030, -.040, .26),
    Vector4(-.018, .010, -.030, .25), Vector4(-.006, .075, -.008, .23), Vector4(.005, .100, .014, .21),
    Vector4(.012, .005, .025, .23), Vector4(.024, -.030, .040, .26),
    Vector4(.018, .010, .030, .25), Vector4(.006, .075, .008, .23), Vector4(-.005, .100, -.014, .21)]

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
var lod: RefCounted
var solve_elapsed := 0.0
var solve_count := 0
var force_pose := true
var replant := false
var pose_state := ""
var combat_frame := -1
var combat_cooldown := 0
var shot_age := 1.0
var shot_count := 0


func _init(owner: Node3D) -> void:
    visual = owner
    skeleton = owner.model.find_children("*", "Skeleton3D", true, false)[0]
    muzzle = owner.model.get_node("soldier/Muzzle")
    lod = preload("res://assets/art/soldier_lod.gd").new(owner.model)
    for i in skeleton.get_bone_count():
        bones[skeleton.get_bone_name(i)] = i
        rests.append(skeleton.get_bone_global_rest(i))
        poses.append(rests[i])
        parents.append(skeleton.get_bone_parent(i))


func configure_view(camera: Camera3D, _dt: float) -> void:
    var previous_level: int = lod.level
    var visible_before: bool = lod.on_screen
    lod.update(camera, visual)
    if lod.level != previous_level or (lod.on_screen and not visible_before):
        force_pose = true
    if lod.on_screen and not visible_before:
        replant = true
        shot_age = 1.0


func observe_combat(frame: int, cooldown: int) -> void:
    # A reset of the existing simulation cooldown is the shot event. Initial
    # snapshots establish a baseline; repeated renders never replay a shot.
    if combat_frame < 0 or frame < combat_frame:
        combat_frame = frame
        combat_cooldown = cooldown
        shot_age = 1.0
        return
    if frame == combat_frame:
        return
    if cooldown > combat_cooldown:
        shot_age = 0.0
        shot_count += 1
        # A real shot can interrupt the cosmetic raise; never fire downwards
        # while waiting for the carry-to-aim blend to finish.
        attack_blend = 1.0
        force_pose = true
    combat_frame = frame
    combat_cooldown = cooldown


func sample(raw: Vector2, dt: float, frame: int, alpha: float, ground,
        guest: bool, velocity: Vector2, aim: Vector2) -> void:
    terrain = ground
    solve_elapsed += dt
    shot_age += dt
    force_pose = force_pose or visual.animation_state != pose_state
    force_pose = force_pose or shot_age < .12 or (attack_blend > 0.0 and attack_blend < 1.0)
    pose_state = visual.animation_state
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
    if reset or replant:
        for i in 2:
            feet[i] = _neutral_foot(i)
            swing_start[i] = feet[i]
            swing_end[i] = feet[i]
            planted[i] = true
            swing_phase[i] = STANCE
            foot_pitch[i] = 0.0
        replant = false
        force_pose = true
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
        var contact_phase := clampf(STANCE * .5 - lead_offset / stride_length, .04, STANCE - .04)
        cycle_offset = contact_phase - phase - lead * .5
        for i in 2:
            planted[i] = true
            swing_phase[i] = maxf(STANCE, fposmod(phase + cycle_offset + i * .5, 1.0))
    was_moving = moving
    blend = move_toward(blend, 1.0 if moving else 0.0, dt / .06)
    # Killing the target may clear the attack order in this same tick. Finish
    # the actual shot's short recoil before lowering, even in that case.
    var should_aim: bool = visual.animation_state == "attack" or shot_age < .12
    attack_blend = move_toward(attack_blend, 1.0 if should_aim else 0.0, dt / .05)
    # Track distance and state offscreen, but do not solve invisible limbs.
    if not lod.on_screen:
        replant = true
        return
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
            var eased := smoothstep(.24, .95, t)
            feet[i] = swing_start[i].lerp(swing_end[i], eased)
            # Lift the trailing heel early, then carry the folded leg forward.
            # Stance below half a cycle creates two short true flight phases.
            feet[i].y = maxf(feet[i].y, _height(feet[i])) + sin(pow(t, .60) * PI) * 14.0 * blend
            foot_pitch[i] = sin(t * TAU) * .70 * blend
        if planted[i]:
            feet[i].y = _height(feet[i])
    var interval: float = [0.0, 1.0 / 30.0, 1.0 / 15.0][lod.level]
    if force_pose or solve_elapsed + .00001 >= interval:
        solve_elapsed = 0.0
        force_pose = false
        _pose(aim)


func _gait_key(cycle: float) -> Vector4:
    var sample_position := fposmod(cycle, 1.0) * JOG_KEYS.size()
    var index := int(sample_position)
    var t := smoothstep(0.0, 1.0, fposmod(sample_position, 1.0))
    return JOG_KEYS[index].lerp(JOG_KEYS[(index + 1) % JOG_KEYS.size()], t)


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
    solve_count += 1
    var inverse := skeleton.global_transform.affine_inverse()
    # The skeleton's bind frame is Y-up and scaled only by the visual model.
    var cycle := phase + cycle_offset
    var gait := _gait_key(cycle)
    # Tight turns already shorten the stride. Reduce the rebound with it so
    # a foot planted around the bend cannot pull the pelvis down abruptly.
    var rebound_gain := pow(stride_length / STRIDE, 2.0)
    var pelvis := Vector3(gait.x * blend, 1.24 - .07 * blend + gait.y * rebound_gain * blend, 0)
    var carry_clearance_lift := 0.0
    # Lower the pelvis before solving, so slopes and long planted strides
    # remain reachable without stretching the leg or lifting a planted foot.
    for i in 2:
        var ankle: Vector3 = inverse * (feet[i] + Vector3.UP * .16 * SCALE)
        var hip_x := -.22 if i == 0 else .22
        var lateral := Vector2(ankle.x - hip_x, ankle.z).length_squared()
        pelvis.y = minf(pelvis.y, ankle.y + sqrt(maxf(1.10 * 1.10 - lateral, .01)) - .015)
        # Bring the rifle up slightly on rising ground, so the leading knee
        # can pass below the handguard without moving the muzzle away from the torso.
        carry_clearance_lift = maxf(carry_clearance_lift,
            clampf((_height(feet[i]) - visual.global_position.y) / SCALE * 2.0, 0.0, .22))
    var yaw := 0.0
    if aim.length_squared() > 0.01:
        var local_aim := visual.global_transform.basis.inverse() * Vector3(aim.x, 0, aim.y)
        yaw = clampf(atan2(local_aim.x, local_aim.z), -0.55, 0.55)
    aim_yaw = yaw
    var upper := Basis(Vector3.UP, aim_yaw - gait.x * blend)
    upper = upper * Basis(Vector3.BACK, gait.z * blend) * Basis(Vector3.RIGHT, gait.w * blend)
    var breath := sin(clock * 2.4) * 0.006 * (1.0 - blend)
    var recoil := sin(clampf(shot_age / .12, 0.0, 1.0) * PI) * .055
    var torso_offset := pelvis - Vector3(0, 1.27, 0) + Vector3(0, breath, -recoil * .25)
    _put("Pelvis", Basis(Vector3.UP, gait.x * 1.4 * blend), pelvis)
    for name: String in ["Spine", "Head", "Clavicle_L", "Clavicle_R"]:
        var p: Vector3 = rests[bones[name]].origin
        _put(name, upper, Vector3(0, 1.57, 0) + upper * (p - Vector3(0, 1.57, 0)) + torso_offset)
    # Keep the head steadier than the chest while the rifle stays in both hands.
    _put("Head", Basis(Vector3.UP, aim_yaw) * Basis(Vector3.RIGHT, .025 * blend), poses[bones.Head].origin)
    # Running carry follows the torso's long axis, muzzle down, with both
    # hands attached. Idle keeps its low-ready pose; shots still raise instantly.
    var weapon_basis := upper * Basis(Vector3.UP, -.12 * (1.0 - attack_blend))
    var carry_pitch := lerpf(.52, RUN_CARRY_PITCH, blend)
    weapon_basis *= Basis(Vector3.RIGHT, lerpf(carry_pitch, -.025, attack_blend))
    # Turn the magazine outwards, leaving room for belt pouches and raised knees.
    weapon_basis *= Basis(Vector3.BACK, PI * .5 * blend * (1.0 - attack_blend))
    var stock_rest := Vector3(.17, 1.86, .13)
    var carry_stock := Vector3(.10, 1.95, .34).lerp(Vector3(.02, 2.36 + carry_clearance_lift, .65), blend)
    var stock_target := carry_stock.lerp(Vector3(.36, 2.18, .12), attack_blend)
    stock_target = Vector3(0, 1.57, 0) + upper * (stock_target - Vector3(0, 1.57, 0)) + torso_offset
    stock_target.z -= recoil
    var weapon_transform := Transform3D(weapon_basis, stock_target - weapon_basis * stock_rest)
    poses[bones.Weapon] = weapon_transform * rests[bones.Weapon]
    for side: String in ["L", "R"]:
        var shoulder_rest: Vector3 = rests[bones["UpperArm_" + side]].origin
        var shoulder := Vector3(0, 1.57, 0) + upper * (shoulder_rest - Vector3(0, 1.57, 0)) + torso_offset
        shoulder += upper * Vector3(.04 if side == "L" else 0.0, .01,
            lerpf(.08, .10, attack_blend) if side == "L" else lerpf(.03, .025, attack_blend))
        var clavicle: Vector3 = poses[bones["Clavicle_" + side]].origin
        _segment("Clavicle_" + side, "UpperArm_" + side, clavicle, shoulder)
        var hand := weapon_transform * rests[bones["Hand_" + side]].origin
        _arm(side, shoulder, hand, weapon_basis)
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
        var foot: Transform3D = poses[bones["Foot_" + side]] * rests[bones["Foot_" + side]].affine_inverse()
        var toe_rest: Vector3 = rests[bones["Toe_" + side]].origin
        _put("Toe_" + side, foot.basis * Basis(Vector3.RIGHT, -maxf(foot_pitch[i], 0.0) * .65), foot * toe_rest)
    for index in poses.size():
        var parent := parents[index]
        var local := poses[index] if parent < 0 else poses[parent].affine_inverse() * poses[index]
        skeleton.set_bone_pose(index, local)
    var weapon: Transform3D = poses[bones.Weapon] * rests[bones.Weapon].affine_inverse()
    muzzle.position = weapon * Vector3(.17, 1.84, 1.36)


func _arm(side: String, shoulder: Vector3, hand: Vector3, hand_basis: Basis) -> void:
    var upper_length := rests[bones["UpperArm_" + side]].origin.distance_to(rests[bones["Forearm_" + side]].origin)
    var lower_length := rests[bones["Forearm_" + side]].origin.distance_to(rests[bones["Hand_" + side]].origin)
    var vector := hand - shoulder
    var reach := clampf(vector.length(), absf(upper_length - lower_length) + .001, upper_length + lower_length - .001)
    var axis := vector.normalized()
    # Elbows hang below and slightly outside the torso, not through the chest.
    var pole := Vector3(-.5 if side == "L" else .65, -1, -.15)
    var bend := pole.slide(axis).normalized()
    var along := (upper_length * upper_length - lower_length * lower_length + reach * reach) / (2.0 * reach)
    var elbow := shoulder + axis * along + bend * sqrt(maxf(upper_length * upper_length - along * along, 0.0))
    _segment("UpperArm_" + side, "Forearm_" + side, shoulder, elbow)
    _segment("Forearm_" + side, "Hand_" + side, elbow, hand)
    _put("Hand_" + side, hand_basis, hand)


func foot_world(index: int) -> Vector3:
    var side := "L" if index == 0 else "R"
    var pose: Transform3D = poses[bones["Foot_" + side]]
    var deform := pose * rests[bones["Foot_" + side]].affine_inverse()
    return skeleton.global_transform * (deform * Vector3(-.22 if index == 0 else .22, 0, 0))
