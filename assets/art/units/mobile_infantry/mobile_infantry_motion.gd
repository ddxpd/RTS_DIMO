extends RefCounted
## Independent presentation controller. Simulation remains the movement authority.

var walk_stride := 0.0
var jog_stride := 0.0

var visual: Node3D
var player: AnimationPlayer
var skeleton: Skeleton3D
var phase := 0.0
var speed := 0.0
var clock := 0.0
var last_cooldown := 0
var last_frame := -1
var fire_time := 1.0
var clip := "idle"
var pose_rotations: Array[Quaternion] = []
var pose_positions: Array[Vector3] = []


func _init(owner_visual: Node3D) -> void:
    visual = owner_visual
    # Strides follow the instantiated model, including its weapon/rig scale.
    walk_stride = 0.80 * visual.model.scale.x
    jog_stride = 1.50 * visual.model.scale.x
    player = visual.animation_player
    var found: Array = visual.model.find_children("*", "Skeleton3D", true, false)
    if not found.is_empty():
        skeleton = found[0]
    if player != null:
        player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
        player.active = true


func sample(unit: Dictionary, delta: float, frame: int, terrain, aim: Vector2) -> void:
    if player == null or skeleton == null:
        return
    var dt := clampf(delta, 0.0, 0.1)
    var old := Vector2(visual.position.x, visual.position.z)
    var target: Vector2 = unit.pos
    var point := old.lerp(target, 1.0 - exp(-18.0 * dt)) if dt > 0.0 else target
    var teleported := old.distance_to(target) > 128.0
    if teleported:
        point = target
        phase = 0.0
    var displacement := point - old
    var distance := 0.0 if teleported else displacement.length()
    visual.position = Vector3(point.x, terrain.height_at(point), point.y)
    if frame != last_frame:
        if int(unit.cooldown) > last_cooldown:
            fire_time = 0.0
        last_cooldown = int(unit.cooldown)
        last_frame = frame
    fire_time += dt
    clock += dt
    var measured := distance / dt if dt > 0.00001 else 0.0
    speed = lerpf(speed, measured, 1.0 - exp(-12.0 * dt))
    var moving := distance > 0.005 and speed > 1.0
    var heading := aim if aim.length_squared() > 1.0 and not moving else displacement
    visual.set_heading(heading)
    var next_clip := "idle"
    if moving:
        next_clip = "jog" if speed > 55.0 else "walk"
        phase = fposmod(phase + distance / (jog_stride if next_clip == "jog" else walk_stride), 1.0)
    elif fire_time < 0.3 or visual.animation_state == "attack":
        next_clip = "fire"
    clip = next_clip
    if not player.has_animation(clip):
        return
    skeleton.clear_bones_global_pose_override()
    player.play(clip)
    var length := player.get_animation(clip).length
    var position := phase * length if moving else (minf(fire_time, length) if clip == "fire" else fposmod(clock, length))
    player.seek(position, true)
    player.advance(0.0)
    # Smooth animation changes without restarting the gait phase each frame.
    var count := skeleton.get_bone_count()
    var blend := 1.0 - exp(-20.0 * dt)
    if pose_rotations.size() != count or teleported:
        pose_rotations.resize(count)
        pose_positions.resize(count)
        blend = 1.0
    for index in range(count):
        var rotation := skeleton.get_bone_pose_rotation(index)
        var translation := skeleton.get_bone_pose_position(index)
        if blend < 1.0:
            rotation = pose_rotations[index].slerp(rotation, blend)
            translation = pose_positions[index].lerp(translation, blend)
        skeleton.set_bone_pose_rotation(index, rotation)
        skeleton.set_bone_pose_position(index, translation)
        pose_rotations[index] = rotation
        pose_positions[index] = translation
    skeleton.force_update_all_bone_transforms()
    if visual.visible:
        _ground_leg("L", terrain)
        _ground_leg("R", terrain)
    preload("res://assets/art/units/mobile_infantry/mobile_infantry_weapon.gd").sync(visual.mobile_weapon)


func _ground_leg(side: String, terrain) -> void:
    var thigh := skeleton.find_bone("thigh." + side)
    var shin := skeleton.find_bone("shin." + side)
    var foot := skeleton.find_bone("foot." + side)
    if thigh < 0 or shin < 0 or foot < 0:
        return
    var upper := skeleton.get_bone_global_pose(thigh)
    var lower := skeleton.get_bone_global_pose(shin)
    var end := skeleton.get_bone_global_pose(foot)
    var world := skeleton.global_transform * end.origin
    var point := Vector2(world.x, world.z)
    var ground: float = terrain.height_at(point)
    var center_ground: float = visual.position.y
    var correction := clampf(ground - center_ground, -7.0, 7.0)
    if absf(correction) < 0.02:
        return
    var goal := skeleton.global_transform.affine_inverse() * (world + Vector3.UP * correction)
    var a := upper.origin.distance_to(lower.origin)
    var b := lower.origin.distance_to(end.origin)
    var axis := goal - upper.origin
    var distance := clampf(axis.length(), absf(a - b) + 0.001, a + b - 0.001)
    axis = axis.normalized()
    goal = upper.origin + axis * distance
    var pole := lower.origin - upper.origin
    pole = (pole - axis * pole.dot(axis)).normalized()
    if pole.length_squared() < 0.1:
        return
    var along := (a * a - b * b + distance * distance) / (2.0 * distance)
    var knee := upper.origin + axis * along + pole * sqrt(maxf(0.0, a * a - along * along))
    upper.basis = Basis(Quaternion((lower.origin - upper.origin).normalized(), (knee - upper.origin).normalized())) * upper.basis
    lower.basis = Basis(Quaternion((end.origin - lower.origin).normalized(), (goal - knee).normalized())) * lower.basis
    lower.origin = knee
    end.origin = goal
    skeleton.set_bone_global_pose_override(thigh, upper, 1.0, true)
    skeleton.set_bone_global_pose_override(shin, lower, 1.0, true)
    skeleton.set_bone_global_pose_override(foot, end, 1.0, true)
