extends RefCounted
## One cached triangulated surface drives drawing, picking, clearance and grounding.
## The original maps do not use this sampler.

const STEP := 8.0
const REVISION := 1
var definition: Dictionary
var bounds: Rect2
var cache_bounds: Rect2
var columns: int
var rows: int
var heights := PackedFloat32Array()
var roads: Array[Dictionary] = []


func configure(data: Dictionary) -> void:
    definition = data
    bounds = data.sample_bounds
    cache_bounds = bounds.grow(128.0)
    columns = int(cache_bounds.size.x / STEP) + 1
    rows = int(cache_bounds.size.y / STEP) + 1
    heights.resize(columns * rows)
    for road: Dictionary in data.roads:
        var curve := Curve2D.new()
        var points: Array = road.points
        for i in range(points.size()):
            var previous: Vector2 = points[maxi(0, i - 1)]
            var next: Vector2 = points[mini(points.size() - 1, i + 1)]
            var tangent := (next - previous) * 0.18
            curve.add_point(points[i], -tangent if i > 0 else Vector2.ZERO, tangent if i < points.size() - 1 else Vector2.ZERO)
        curve.bake_interval = 24.0
        var road_bounds := Rect2(points[0], Vector2.ZERO)
        for point: Vector2 in points:
            road_bounds = road_bounds.expand(point)
        roads.append({"points": curve.get_baked_points(), "width": road.width, "bounds": road_bounds.grow(float(road.width))})
    for z in range(rows):
        for x in range(columns):
            var p := cache_bounds.position + Vector2(x, z) * STEP
            heights[z * columns + x] = _authored_height(p)


func edge_distance(p: Vector2, center: Vector2, radius: Vector2) -> float:
    var q := (p - center) / radius
    var angle := atan2(q.y, q.x)
    var variation := sin(angle * 5.0 + 0.7) * 10.0 + sin(angle * 9.0 - 0.4) * 5.0 + sin(angle * 17.0) * 2.0
    return (1.0 - q.length()) * minf(radius.x, radius.y) + variation


func _level(distance: float, width: float) -> float:
    # A broad toe and small lip bevel surround the steep, unwalkable rock face.
    return smoothstep(-width * 0.8, width * 0.5, distance)


func _authored_height(p: Vector2) -> float:
    var plateau: Dictionary = definition.plateau
    var quarry: Dictionary = definition.quarry
    var top_edge := edge_distance(p, plateau.center, plateau.radius)
    var outer_edge := edge_distance(p, quarry.center, quarry.radius)
    var inner_edge := edge_distance(p, quarry.center, quarry.inner_radius)
    var h := float(plateau.height) * _level(top_edge, plateau.edge_width)
    h += float(quarry.height) * 0.5 * (_level(outer_edge, quarry.edge_width) + _level(inner_edge, quarry.edge_width))
    # Rock strata affect the face geometry only, never flat building pads.
    for edge: float in [top_edge, outer_edge, inner_edge]:
        var face := 1.0 - smoothstep(4.0, 26.0, absf(edge))
        h += sin(p.x * 0.11 + p.y * 0.017) * sin(edge * 0.35) * face * 1.8
    for ramp: Dictionary in definition.ramps:
        var start: Vector2 = ramp.start
        var end: Vector2 = ramp.end
        var delta := end - start
        var t := (p - start).dot(delta) / delta.length_squared()
        if t < 0.0 or t > 1.0:
            continue
        var sideways := absf((p - start).cross(delta.normalized()))
        var blend := 1.0 - smoothstep(float(ramp.width) * 0.5, float(ramp.width) * 0.5 + 48.0, sideways)
        h = lerpf(h, float(ramp.height) * smoothstep(0.0, 1.0, t), blend)
    return h


func vertex(x: int, z: int) -> Vector3:
    var p := cache_bounds.position + Vector2(x, z) * STEP
    return Vector3(p.x, heights[z * columns + x], p.y)


func height_at(p: Vector2) -> float:
    if not cache_bounds.has_point(p):
        return 0.0
    var local := (p - cache_bounds.position) / STEP
    var x := clampi(int(local.x), 0, columns - 2)
    var z := clampi(int(local.y), 0, rows - 2)
    var u := local.x - x
    var v := local.y - z
    var a := heights[z * columns + x]
    var b := heights[z * columns + x + 1]
    var c := heights[(z + 1) * columns + x + 1]
    var d := heights[(z + 1) * columns + x]
    # Same a-c diagonal as the renderer, not bilinear interpolation.
    return a + (b - a) * u + (c - b) * v if u >= v else a + (c - d) * u + (d - a) * v


func gradient_at(p: Vector2) -> Vector2:
    return Vector2(height_at(p + Vector2(1, 0)) - height_at(p - Vector2(1, 0)), height_at(p + Vector2(0, 1)) - height_at(p - Vector2(0, 1))) * 0.5


func normal_at(p: Vector2) -> Vector3:
    var g := gradient_at(p)
    return Vector3(-g.x, 1.0, -g.y).normalized()


func road_sample(p: Vector2) -> Vector3:
    var best := Vector3(0, 0, 0)
    var closest := INF
    for road: Dictionary in roads:
        if not (road.bounds as Rect2).has_point(p):
            continue
        var points: PackedVector2Array = road.points
        var along := 0.0
        for i in range(points.size() - 1):
            var a := points[i]
            var b := points[i + 1]
            var near := Geometry2D.get_closest_point_to_segment(p, a, b)
            var distance := p.distance_to(near)
            if distance < closest:
                closest = distance
                var weight := 1.0 - smoothstep(float(road.width) * 0.34, float(road.width) * 0.68, distance)
                best = Vector3(weight, (p - near).dot(Vector2(-(b-a).y, (b-a).x).normalized()), along + a.distance_to(near))
            along += a.distance_to(b)
    return best


func cliff_distance(p: Vector2) -> float:
    var plateau: Dictionary = definition.plateau
    var quarry: Dictionary = definition.quarry
    return minf(absf(edge_distance(p, plateau.center, plateau.radius)), minf(absf(edge_distance(p, quarry.center, quarry.radius)), absf(edge_distance(p, quarry.center, quarry.inner_radius))))


func position_clear(p: Vector2, radius: float) -> bool:
    if not bounds.grow(-radius).has_point(p):
        return false
    var height := height_at(p)
    if gradient_at(p).length() > 0.4:
        return false
    for direction: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(0.707, 0.707), Vector2(-0.707, 0.707), Vector2(0.707, -0.707), Vector2(-0.707, -0.707)]:
        var probe := p + direction * radius
        if absf(height_at(probe) - height) > radius * 0.4 + 0.25 or gradient_at(probe).length() > 0.42:
            return false
    return true


func build_error(rect: Rect2) -> String:
    var expected := height_at(rect.get_center())
    if not bounds.encloses(rect.grow(16)):
        return "Build inside the sample area"
    for z in range(int(rect.position.y) - 16, int(rect.end.y) + 17, 8):
        for x in range(int(rect.position.x) - 16, int(rect.end.x) + 17, 8):
            var p := Vector2(x, z)
            if absf(height_at(p) - expected) > 0.1 or gradient_at(p).length() > 0.005:
                return "Build on a flat platform, away from slopes and cliffs"
    return ""
