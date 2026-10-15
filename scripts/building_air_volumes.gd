extends RefCounted
## Authoritative local-space solids (X/Y/Z), independent of rendering and LOD.
## Gaia: 320/18, 16, 192/10 model scale, 12-unit presentation clearance.
## Envelopes include radar sweep and hover bob. Cosmetic cruise pitch may
## extend a wing tip by under two units; it does not enlarge grid lift columns.
const BASE := [
    AABB(Vector3(-160, 0, -96), Vector3(320, 90, 192)),
    AABB(Vector3(-36, 74, -28), Vector3(72, 30, 70)),
    AABB(Vector3(-32, 100, -23), Vector3(64, 38, 60)),
    AABB(Vector3(-23, 128, -20), Vector3(46, 32, 50)),
]
const HEIGHTS := {"base": 160.0, "barracks": 104.0, "refinery": 72.0, "bunker": 62.0}
const Catalog = preload("res://scripts/definitions/entity_catalog.gd")
const GAP := 4.0


static func parts(kind: String) -> Array:
    if kind == "base":
        return BASE
    var size: Vector2 = Catalog.BUILD_TYPES[kind].size
    return [AABB(Vector3(-size.x * 0.5, 0, -size.y * 0.5), Vector3(size.x, HEIGHTS.get(kind, 104.0), size.y))]


static func axis(heading: float) -> Vector2:
    return Vector2(cos(heading), -sin(heading))


static func horizontal_overlap(a: AABB, pos_a: Vector2, yaw_a: float, b: AABB, pos_b: Vector2, yaw_b: float) -> bool:
    var ax := axis(yaw_a)
    var az := Vector2(-ax.y, ax.x)
    var bx := axis(yaw_b)
    var bz := Vector2(-bx.y, bx.x)
    var ca := a.get_center()
    var cb := b.get_center()
    var delta := pos_b + bx * cb.x + bz * cb.z - pos_a - ax * ca.x - az * ca.z
    for direction: Vector2 in [ax, az, bx, bz]:
        var ra := (absf(direction.dot(ax)) * a.size.x + absf(direction.dot(az)) * a.size.z) * 0.5
        var rb := (absf(direction.dot(bx)) * b.size.x + absf(direction.dot(bz)) * b.size.z) * 0.5
        # Grid-aligned neighboring lift columns may share an edge.
        if absf(delta.dot(direction)) >= ra + rb - 0.001:
            return false
    return true


static func overlaps(kind: String, position: Vector2, height: float, heading: float, other: Dictionary, ground: float) -> bool:
    var reach: float = (Catalog.BUILD_TYPES[kind].size.length() + Catalog.BUILD_TYPES[other.type].size.length()) * 0.5
    if position.distance_squared_to(other.pos) >= reach * reach:
        return false
    var flight: Dictionary = other.get("flight", {})
    var bottom: float = flight.get("height", ground)
    var top := bottom
    if flight.get("state", "grounded") in ["taking_off", "landing"]:
        bottom = minf(flight.ground, flight.cruise)
        top = maxf(flight.ground, flight.cruise)
    if height >= top + float(HEIGHTS.get(other.type, 104.0)) + GAP or height + float(HEIGHTS.get(kind, 104.0)) + GAP <= bottom:
        return false
    var yaw: float = flight.get("heading", 0.0)
    for a: AABB in parts(kind):
        for b: AABB in parts(other.type):
            if height + a.position.y >= top + b.end.y + GAP or height + a.end.y + GAP <= bottom + b.position.y:
                continue
            if horizontal_overlap(a, position, heading, b, other.pos, yaw):
                return true
    return false
