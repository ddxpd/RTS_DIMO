extends RefCounted
## Stable editor/runtime contract. XZ ground plane, Y up, game units baked in.

const REVISION := 2
const WorldGrid = preload("res://scripts/world_grid.gd")
const ROOT := "res://assets/maps/components/"
const GRID := float(WorldGrid.CELL)
const STEP := 8.0
const IDS := ["sand_flat", "plateau_top", "cliff_straight", "cliff_outer", "cliff_inner", "cliff_end", "ramp_toe", "ramp_run", "ramp_crest", "rock_large", "rock_medium", "rubble_cluster"]


static func entry(id: String) -> Dictionary:
    if id not in IDS:
        return {}
    var size := Vector2(256, 256)
    if id == "cliff_straight":
        size.y = 64
    elif id in ["cliff_outer", "cliff_inner"]:
        size = Vector2(64, 64)
    elif id == "cliff_end":
        size = Vector2(128, 64)
    elif id in ["ramp_toe", "ramp_crest"]:
        size.y = 32
    elif id == "ramp_run":
        size.y = 192
    elif id == "rock_large":
        size = Vector2(128, 128)
    elif id == "rock_medium":
        size = Vector2(64, 64)
    elif id == "rubble_cluster":
        size = Vector2(96, 96)
    var decor := id in ["rock_large", "rock_medium", "rubble_cluster"]
    return {
        "id": id, "scene": ROOT + id + ".tscn", "thumbnail": ROOT + "thumbnails/" + id + ".png",
        "size": size, "origin": "base_center" if decor else "minimum_xz",
        "layer": "decoration" if decor else "surface", "walkable": not id.begins_with("cliff"),
        "buildable": id in ["sand_flat", "plateau_top"], "blocking": id.begins_with("rock_"),
        "sockets": [] if decor else ["west", "east", "north", "south"],
        "lod": "imported" if decor else "fixed_boundary", "revision": REVISION
    }


static func ramp_height(distance: float) -> float:
    # 32/192/32 pieces, continuous height and tangent, total rise 128.
    var t := clampf(distance / 256.0, 0.0, 1.0)
    if t < 0.125:
        var u := t / 0.125
        return 16.0 * u * u * (2.0 - u)
    if t > 0.875:
        var u := (t - 0.875) / 0.125
        return 112.0 + 16.0 * (u + u * u - u * u * u)
    return t * 128.0


static func height(id: String, p: Vector2) -> float:
    if id == "ramp_toe":
        return ramp_height(p.y)
    if id == "ramp_run":
        return ramp_height(p.y + 32.0) - 16.0
    if id == "ramp_crest":
        return ramp_height(p.y + 224.0) - 112.0
    if id in ["cliff_straight", "cliff_end"]:
        return 128.0 * smoothstep(0.0, 64.0, p.y)
    if id == "cliff_outer":
        return 128.0 * smoothstep(64.0, 0.0, p.distance_to(Vector2(64, 64)))
    if id == "cliff_inner":
        return 128.0 * smoothstep(0.0, 64.0, p.length())
    return 0.0


static func transform(instance: Dictionary) -> Transform3D:
    var p: Array = instance.position
    var angle := float(instance.get("rotation", 0.0))
    var basis := Basis(Vector3.UP, angle)
    if absf(angle / (PI / 2) - roundf(angle / (PI / 2))) < 0.00001:
        # Exact quarter turns prevent tiny cracks/asymmetric height samples at
        # mirrored seams, especially where a ramp meets a flat zero-height pad.
        basis = Basis(basis.x.round(), basis.y.round(), basis.z.round())
    return Transform3D(basis.scaled(Vector3.ONE * float(instance.get("scale", 1.0))), Vector3(p[0], p[1], p[2]))


static func rect(instance: Dictionary) -> Rect2:
    var item := entry(instance.component)
    var size: Vector2 = item.size
    var offset := -size * 0.5 if item.layer == "decoration" else Vector2.ZERO
    var t := transform(instance)
    var result := Rect2()
    for i in range(4):
        var p: Vector2 = offset + [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)][i]
        var world := t * Vector3(p.x, 0, p.y)
        if i == 0:
            result = Rect2(Vector2(world.x, world.z), Vector2.ZERO)
        else:
            result = result.expand(Vector2(world.x, world.z))
    return result


static func local_point(instance: Dictionary, point: Vector2) -> Vector2:
    var p := transform(instance).affine_inverse() * Vector3(point.x, 0, point.y)
    return Vector2(p.x, p.z)


static func world_height(instance: Dictionary, point: Vector2) -> float:
    return float(instance.position[1]) + height(instance.component, local_point(instance, point))
