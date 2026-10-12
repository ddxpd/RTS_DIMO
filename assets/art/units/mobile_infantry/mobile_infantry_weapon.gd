extends RefCounted
## Rigid weapon follows the baked weapon bone, including automatic death playback.

const WEAPON = preload("res://assets/models/units/mobile_infantry/mobile_infantry_machine_gun.glb")


static func attach(model: Node3D) -> Node3D:
    var skeletons := model.find_children("*", "Skeleton3D", true, false)
    if skeletons.is_empty():
        push_error("Mobile infantry skeleton is missing")
        return null
    var skeleton := skeletons[0] as Skeleton3D
    if skeleton.find_bone("weapon") < 0:
        push_error("Mobile infantry weapon bone is missing")
        return null
    var mount: Array = []
    var nodes: Array = [model]
    nodes.append_array(model.find_children("*", "Node3D", true, false))
    for node: Node in nodes:
        if node.has_meta("weapon_mount"):
            mount.assign(node.get_meta("weapon_mount"))
            break
        var extras: Dictionary = node.get_meta("extras", {})
        if extras.has("weapon_mount"):
            mount.assign(extras.weapon_mount)
            break
    if mount.size() != 12:
        push_error("Mobile infantry GLB has no weapon_mount transform")
        return null
    var socket := BoneAttachment3D.new()
    socket.name = "MachineGunAttachment"
    skeleton.add_child(socket)
    socket.bone_name = "weapon"
    var weapon := WEAPON.instantiate() as Node3D
    socket.add_child(weapon)
    weapon.transform = Transform3D(
        Vector3(mount[0], mount[1], mount[2]),
        Vector3(mount[3], mount[4], mount[5]),
        Vector3(mount[6], mount[7], mount[8]),
        Vector3(mount[9], mount[10], mount[11]))
    sync(weapon)
    return weapon


static func sync(weapon: Node3D) -> void:
    if weapon == null:
        return
    var socket := weapon.get_parent() as BoneAttachment3D
    var skeleton := socket.get_parent() as Skeleton3D
    # BoneAttachment handles automatic playback; manual sampling needs this now,
    # before Skeleton3D's deferred skeleton_updated notification is emitted.
    socket.transform = skeleton.get_bone_global_pose(socket.get_bone_idx())
