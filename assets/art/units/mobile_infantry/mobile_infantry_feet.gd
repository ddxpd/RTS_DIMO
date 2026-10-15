extends RefCounted
## World-space support contacts. Changes only the displayed skeleton.
var visual: Node3D
var skeleton: Skeleton3D
var feet: Array[Dictionary] = []
var pelvis := -1
var pelvis_offset := 0.0
var ready := false


func _init(owner: Node3D, rig: Skeleton3D) -> void:
    visual = owner
    skeleton = rig
    pelvis = rig.find_bone("pelvis")
    for side in ["L", "R"]:
        feet.append({"bones": [rig.find_bone("thigh." + side), rig.find_bone("shin." + side), rig.find_bone("foot." + side)],
            "locked": false, "anchor": Vector3.ZERO, "last": Vector3.ZERO,
            "stepping": false, "step": 0.0, "from": Vector3.ZERO})


static func solve(rig: Skeleton3D, bones: Array, goal: Vector3, end_basis: Basis) -> void:
    var upper := rig.get_bone_global_pose(bones[0])
    var lower := rig.get_bone_global_pose(bones[1])
    var end := rig.get_bone_global_pose(bones[2])
    var a := upper.origin.distance_to(lower.origin)
    var b := lower.origin.distance_to(end.origin)
    var axis := goal - upper.origin
    var distance := clampf(axis.length(), absf(a - b) + 0.001, a + b - 0.001)
    axis = axis.normalized()
    goal = upper.origin + axis * distance
    var pole := lower.origin - upper.origin
    pole = pole - axis * pole.dot(axis)
    if pole.length_squared() < 0.000001:
        pole = Vector3.FORWARD - axis * axis.dot(Vector3.FORWARD)
    pole = pole.normalized()
    var along := (a * a - b * b + distance * distance) / (2.0 * distance)
    var knee := upper.origin + axis * along + pole * sqrt(maxf(0.0, a * a - along * along))
    upper.basis = Basis(Quaternion((lower.origin - upper.origin).normalized(), (knee - upper.origin).normalized())) * upper.basis
    lower.basis = Basis(Quaternion((end.origin - lower.origin).normalized(), (goal - knee).normalized())) * lower.basis
    lower.origin = knee
    end.origin = goal
    end.basis = end_basis
    rig.set_bone_global_pose_override(bones[0], upper, 1.0, true)
    rig.set_bone_global_pose_override(bones[1], lower, 1.0, true)
    rig.set_bone_global_pose_override(bones[2], end, 1.0, true)


func update(delta: float, phase: float, stance: float, moving: bool, terrain, reset: bool) -> void:
    if reset:
        pelvis_offset = 0.0
    var transform := skeleton.global_transform
    var inverse := transform.affine_inverse()
    var wants: Array[Vector3] = []
    var bases: Array[Basis] = []
    var correction := 0.0
    for foot: Dictionary in feet:
        var pose := skeleton.get_bone_global_pose(foot.bones[2])
        var point := transform * pose.origin
        var ground: float = terrain.height_at(Vector2(point.x, point.z))
        correction = minf(correction, ground - visual.position.y)
        point.y += ground - visual.position.y
        wants.append(point)
        bases.append(pose.basis)
    pelvis_offset = lerpf(pelvis_offset, clampf(correction, -5.0, 2.0), 1.0 - exp(-12.0 * delta))
    if pelvis >= 0:
        var pose := skeleton.get_bone_global_pose(pelvis)
        pose.origin += inverse.basis * Vector3(0, pelvis_offset, 0)
        skeleton.set_bone_global_pose_override(pelvis, pose, 1.0, true)
        skeleton.force_update_all_bone_transforms()
    for index in range(2):
        var foot: Dictionary = feet[index]
        var desired := wants[index]
        if reset or not ready:
            foot.anchor = desired
            foot.last = desired
            foot.locked = false
            foot.stepping = false
        var goal := desired
        if moving:
            var contact := fposmod(phase + index * 0.5, 1.0) < stance
            if contact and not foot.stepping:
                if not foot.locked:
                    foot.anchor = desired
                foot.locked = true
                goal.x = foot.anchor.x
                goal.z = foot.anchor.z
                goal.y += terrain.height_at(Vector2(goal.x, goal.z)) - terrain.height_at(Vector2(desired.x, desired.z))
            else:
                foot.locked = false
        else:
            # Finish a swing and alternate feet during turns, rather than dragging
            # both feet around with the root transform.
            if not foot.locked and not foot.stepping:
                foot.anchor = foot.last
                foot.locked = true
            var error: Vector3 = desired - foot.anchor
            if not foot.stepping and not feet[1 - index].stepping and (Vector2(error.x, error.z).length() > 1.25 or absf(error.y) > 1.2):
                foot.stepping = true
                foot.step = 0.0
                foot.from = foot.last
            if not foot.stepping:
                goal = foot.anchor
        # A speed change on a slope can put the old support beyond leg reach.
        # Lift and replant it instead of stretching the shin or sliding the sole.
        var hip := skeleton.get_bone_global_pose(foot.bones[0]).origin
        var knee := skeleton.get_bone_global_pose(foot.bones[1]).origin
        var ankle := skeleton.get_bone_global_pose(foot.bones[2]).origin
        var reach := hip.distance_to(knee) + knee.distance_to(ankle) - 0.004
        if foot.locked and not foot.stepping and hip.distance_to(inverse * goal) > reach:
            foot.stepping = true
            foot.step = 0.0
            foot.from = foot.last
        if foot.stepping:
            foot.locked = false
            foot.step = minf(1.0, foot.step + delta / 0.20)
            goal = (foot.from as Vector3).lerp(desired, smoothstep(0.0, 1.0, float(foot.step)))
            goal.y += sin(float(foot.step) * PI) * 2.0
            if foot.step >= 1.0:
                foot.stepping = false
                foot.locked = true
                foot.anchor = desired
        var p := Vector2(goal.x, goal.z)
        var dx: float = (terrain.height_at(p + Vector2(2, 0)) - terrain.height_at(p - Vector2(2, 0))) / 4.0
        var dz: float = (terrain.height_at(p + Vector2(0, 2)) - terrain.height_at(p - Vector2(0, 2))) / 4.0
        var slope := Basis(Quaternion(Vector3.UP, Vector3(-dx, 1, -dz).normalized()))
        var basis := inverse.basis * slope * transform.basis * bases[index]
        solve(skeleton, foot.bones, inverse * goal, basis)
        foot.last = goal
    ready = true
