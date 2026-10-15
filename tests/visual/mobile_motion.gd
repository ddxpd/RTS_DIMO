extends SceneTree
const Visual = preload("res://assets/art/entity_visual.gd")
var checks := 0
var failures: Array[String] = []
var max_slip := 0.0
var max_grip := 0.0
var max_stretch := 0.0
var worst: Dictionary = {}
var contacts := 0

class Floor:
    var slope := 0.0
    func height_at(point: Vector2) -> float:
        return point.y * slope

func _initialize() -> void:
    run.call_deferred()

func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok and not failures.has(message):
        failures.append(message)
        push_error(message)

func route(fps: int, hz: int, curved: bool, slope: float) -> void:
    var actor := Visual.new("mobile_infantry", 1)
    root.add_child(actor)
    actor.set_process(false)
    var motion = actor.mobile_motion
    var rig: Skeleton3D = motion.skeleton
    var floor := Floor.new()
    floor.slope = slope
    var unit := {"pos": Vector2.ZERO, "cooldown": 0}
    motion.sample(unit, 0, 0, floor, Vector2.ZERO)
    var tick := -1
    var last_points: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
    var last_anchors: Array[Vector3] = [Vector3.INF, Vector3.INF]
    var rest_lengths: Array[float] = []
    for side in ["L", "R"]:
        var lower := rig.get_bone_global_rest(rig.find_bone("shin." + side)).origin
        var end := rig.get_bone_global_rest(rig.find_bone("foot." + side)).origin
        rest_lengths.append(lower.distance_to(end))
    for frame in range(fps * 5):
        var time := float(frame) / fps
        var next_tick := floori(time * hz)
        if tick != next_tick:
            tick = next_tick
            var t := float(tick) / hz
            var distance := minf(t, 3.0) * 70.0
            unit.pos = Vector2(45 * (1 - cos(distance / 45)), 45 * sin(distance / 45)) if curved else Vector2(0, distance)
        motion.sample(unit, 1.0 / fps, tick, floor, Vector2(-100, 0) if time > 3.6 else Vector2.ZERO)
        for index in range(2):
            var foot: Dictionary = motion.feet.feet[index]
            var local := rig.get_bone_global_pose(foot.bones[2]).origin
            var point := rig.global_transform * local
            var lower := rig.get_bone_global_pose(foot.bones[1]).origin
            max_stretch = maxf(max_stretch, absf(local.distance_to(lower) - rest_lengths[index]))
            if foot.locked and not foot.stepping and foot.anchor == last_anchors[index] and time > 0.5:
                contacts += 1
                var slip := Vector2(point.x - last_points[index].x, point.z - last_points[index].z).length()
                if slip > max_slip:
                    worst = {"fps": fps, "hz": hz, "curved": curved, "slope": slope, "time": time, "phase": motion.phase, "speed": motion.speed, "foot": index}
                    max_slip = slip
            last_points[index] = point
            last_anchors[index] = foot.anchor if foot.locked and not foot.stepping else Vector3.INF
            var hand: Dictionary = motion.hands[index]
            var palm := rig.global_transform * rig.get_bone_global_pose(hand.bones[2]).origin
            max_grip = maxf(max_grip, palm.distance_to(hand.grip.global_position))
        check(actor.transform.is_finite() and rig.get_bone_global_pose(rig.find_bone("head")).is_finite(), "All poses remain finite")
    check(motion.clip == "idle" and motion.gait_weight == 0, "Stop finishes gait and returns to ready stance")
    check(absf(angle_difference(actor.rotation.y, -PI / 2)) < 0.01, "Standing turn follows aim")
    check(not motion.feet.feet[0].stepping and not motion.feet.feet[1].stepping, "Turn settles instead of endlessly shuffling")
    var position := actor.position
    for frame in range(30):
        motion.sample(unit, 1.0 / fps, tick, floor, Vector2(-100, 0))
    check(actor.position.distance_to(position) < 0.01, "Pose settling does not displace the unit")
    unit.cooldown = 5
    actor.set_animation("attack")
    for frame in range(fps):
        motion.sample(unit, 1.0 / fps, tick, floor, Vector2(-100, 0))
        for hand: Dictionary in motion.hands:
            var palm := rig.global_transform * rig.get_bone_global_pose(hand.bones[2]).origin
            max_grip = maxf(max_grip, palm.distance_to(hand.grip.global_position))
    check(motion.fire_weight == 1.0, "Firing blend reaches the aimed pose after a turn")
    unit.pos += Vector2(500, 0)
    motion.sample(unit, 1.0 / fps, tick + 1, floor, Vector2.ZERO)
    check(actor.position.x == unit.pos.x and motion.phase == 0, "Teleport resets contacts and gait")
    actor.free()

func run() -> void:
    for fps in [30, 60, 144]:
        for hz in [5, 20]:
            route(fps, hz, false, 0.0)
            route(fps, hz, true, 0.0)
        route(fps, 20, false, 0.35)
        route(fps, 20, false, -0.35)
    check(max_slip < 0.35, "Support feet remain fixed in world space")
    check(max_grip < 0.8, "Both hands stay on weapon through blends and terrain correction")
    check(max_stretch < 0.005, "IK preserves shin length")
    check(contacts > 1000, "World-space contact checks cover actual planted feet")
    print("MOBILE_MOTION ", JSON.stringify({"checks": checks, "max_slip": max_slip, "max_grip": max_grip, "max_stretch": max_stretch, "worst": worst, "failures": failures}))
    quit(0 if failures.is_empty() else 1)
