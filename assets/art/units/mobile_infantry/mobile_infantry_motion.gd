extends RefCounted
## Distance-driven poses with world-space contacts; simulation remains authoritative.
const Feet = preload("res://assets/art/units/mobile_infantry/mobile_infantry_feet.gd")
const Weapon = preload("res://assets/art/units/mobile_infantry/mobile_infantry_weapon.gd")
var walk_stride := 0.0
var jog_stride := 0.0
var visual: Node3D
var player: AnimationPlayer
var skeleton: Skeleton3D
var feet: RefCounted
var phase := 0.0
var speed := 0.0
var clock := 0.0
var last_cooldown := 0
var last_frame := -1
var fire_time := 1.0
var clip := "idle"
var gait_weight := 0.0
var jog_weight := 0.0
var fire_weight := 0.0
var lean := 0.0
var initialized := false
var pose_rotations: Array[Quaternion] = []
var pose_positions: Array[Vector3] = []
var hands: Array[Dictionary] = []
var spine := -1
var head := -1
var weapon_bone := -1


func _init(owner_visual: Node3D) -> void:
    visual = owner_visual
    walk_stride = 0.80 * visual.model.scale.x
    jog_stride = 1.50 * visual.model.scale.x
    player = visual.animation_player
    var found: Array = visual.model.find_children("*", "Skeleton3D", true, false)
    if found.is_empty() or player == null:
        return
    skeleton = found[0]
    player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
    player.active = true
    feet = Feet.new(visual, skeleton)
    spine = skeleton.find_bone("spine")
    head = skeleton.find_bone("head")
    weapon_bone = skeleton.find_bone("weapon")
    pose_rotations.resize(skeleton.get_bone_count())
    pose_positions.resize(skeleton.get_bone_count())
    player.play("RESET")
    player.advance(0)
    skeleton.force_update_all_bone_transforms()
    Weapon.sync(visual.mobile_weapon)
    for side in ["L", "R"]:
        var bones := [skeleton.find_bone("upper_arm." + side), skeleton.find_bone("forearm." + side), skeleton.find_bone("hand." + side)]
        var grip := visual.mobile_weapon.find_child("GripLeft" if side == "L" else "GripRight", true, false) as Node3D
        var world_basis := skeleton.global_basis * skeleton.get_bone_global_pose(bones[2]).basis
        hands.append({"bones": bones, "grip": grip, "basis": visual.mobile_weapon.global_basis.inverse() * world_basis})


func _mix_pose(name: String, time: float, weight: float, first: bool = false) -> void:
    if not first and weight <= 0.0001:
        return
    player.play(name)
    player.seek(time, true)
    player.advance(0)
    for index in range(pose_rotations.size()):
        var rotation := skeleton.get_bone_pose_rotation(index)
        var position := skeleton.get_bone_pose_position(index)
        pose_rotations[index] = rotation if first else pose_rotations[index].slerp(rotation, weight)
        pose_positions[index] = position if first else pose_positions[index].lerp(position, weight)


func sample(unit: Dictionary, delta: float, frame: int, terrain, aim: Vector2) -> void:
    if player == null or skeleton == null:
        return
    var dt := clampf(delta, 0, 0.1)
    var old := Vector2(visual.position.x, visual.position.z)
    var target: Vector2 = unit.pos
    var reset := not initialized or old.distance_to(target) > 128.0 or frame < last_frame
    var point := target if reset or dt == 0 else old.lerp(target, 1.0 - exp(-18.0 * dt))
    var distance := 0.0 if reset else point.distance_to(old)
    var displacement := point - old
    visual.position = Vector3(point.x, terrain.height_at(point), point.y)
    if frame != last_frame:
        if int(unit.cooldown) > last_cooldown:
            fire_time = 0.0
        last_cooldown = int(unit.cooldown)
        last_frame = frame
    fire_time += dt
    clock += dt
    var previous_speed := speed
    var measured := distance / dt if dt > 0.00001 else 0.0
    speed = lerpf(speed, measured, 1.0 - exp(-12.0 * dt))
    if reset:
        phase = 0
        speed = 0
        gait_weight = 0
        lean = 0
    var moving := distance > 0.005 and speed > 1.0
    jog_weight = smoothstep(40.0, 70.0, speed)
    if moving:
        phase = fposmod(phase + distance / lerpf(walk_stride, jog_stride, jog_weight), 1.0)
    gait_weight = move_toward(gait_weight, 1.0 if moving else 0.0, dt * (8.0 if moving else 5.0))
    var firing: bool = not moving and (fire_time < 0.3 or visual.animation_state == "attack")
    fire_weight = move_toward(fire_weight, 1.0 if firing else 0.0, dt * 8.0)
    clip = ("jog" if jog_weight >= 0.5 else "walk") if moving else "fire" if firing else "idle"
    visual.set_heading(displacement if moving else aim)
    var turn := angle_difference(visual.rotation.y, visual._target_heading)
    if reset:
        visual.rotation.y = visual._target_heading
    else:
        visual.rotation.y += clampf(turn * (1.0 - exp(-10.0 * dt)), -TAU * dt, TAU * dt)
    var acceleration := (speed - previous_speed) / maxf(dt, 0.001)
    lean = lerpf(lean, clampf(acceleration * 0.00035, -0.035, 0.05), 1.0 - exp(-8.0 * dt))
    skeleton.clear_bones_global_pose_override()
    var idle_time := fposmod(clock + float(unit.get("id", 0)) * 0.73, player.get_animation("idle").length)
    var firing_time := minf(fire_time, player.get_animation("fire").length)
    if fire_weight >= 1.0:
        _mix_pose("fire", firing_time, 1.0, true)
    elif gait_weight <= 0.0:
        _mix_pose("idle", idle_time, 1.0, true)
        _mix_pose("fire", firing_time, fire_weight)
    else:
        if jog_weight >= 1.0:
            _mix_pose("jog", phase * player.get_animation("jog").length, 1.0, true)
        else:
            _mix_pose("walk", phase * player.get_animation("walk").length, 1.0, true)
            _mix_pose("jog", phase * player.get_animation("jog").length, jog_weight)
        _mix_pose("idle", idle_time, 1.0 - gait_weight)
        _mix_pose("fire", firing_time, fire_weight)
    for index in range(pose_rotations.size()):
        skeleton.set_bone_pose_rotation(index, pose_rotations[index])
        skeleton.set_bone_pose_position(index, pose_positions[index])
    if spine >= 0:
        skeleton.set_bone_pose_rotation(spine, pose_rotations[spine] * Quaternion(Vector3.RIGHT, lean))
    if head >= 0:
        skeleton.set_bone_pose_rotation(head, pose_rotations[head] * Quaternion(Vector3.UP, clampf(turn * 0.3, -0.16, 0.16)))
    skeleton.force_update_all_bone_transforms()
    if visual.visible:
        feet.update(dt, phase, lerpf(0.60, 0.42, jog_weight), moving, terrain, reset)
        skeleton.force_update_all_bone_transforms()
    Weapon.sync(visual.mobile_weapon)
    # Re-solve both palms after blending. Freeze the gun's intended pose because
    # its authored bone is parented to the right hand.
    var gun_pose := skeleton.get_bone_global_pose(weapon_bone)
    var inverse := skeleton.global_transform.affine_inverse()
    var weapon_basis: Basis = visual.mobile_weapon.global_basis
    var goals: Array[Vector3] = []
    for hand: Dictionary in hands:
        goals.append(inverse * hand.grip.global_position)
    for index in range(hands.size()):
        var hand: Dictionary = hands[index]
        Feet.solve(skeleton, hand.bones, goals[index], inverse.basis * weapon_basis * hand.basis)
    skeleton.set_bone_global_pose_override(weapon_bone, gun_pose, 1.0, true)
    Weapon.sync(visual.mobile_weapon)
    initialized = true
