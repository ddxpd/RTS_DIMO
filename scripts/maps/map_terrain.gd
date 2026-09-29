extends RefCounted

const Catalog = preload("res://scripts/maps/map_catalog.gd")
const Modules = preload("res://scripts/maps/terrain_modules.gd")
const CELL := 32.0
const WIDTH := 150
const DEPTH := 100
const WORLD := Vector2(4800, 3200)
const COUNT := WIDTH * DEPTH

var id := ""
var definition: Dictionary = {}
var checksum := ""
var error := ""
var heights := PackedFloat32Array()
var gradients := PackedVector2Array()
var buildable := PackedByteArray()
var passable := PackedByteArray()
var materials := PackedByteArray()
var flat_clear := PackedByteArray()
var navigation_clear := PackedByteArray()
var visibility_cache: Dictionary = {}

func load_map(map_id: String) -> bool:
    return assemble(Catalog.definition(map_id))

func assemble(data: Dictionary) -> bool:
    error = ""
    if data.is_empty() or data.get("size") != WORLD:
        error = "Unknown map or unsupported dimensions."
        return false
    definition = data.duplicate(true)
    id = str(data.id)
    var digest := HashingContext.new()
    digest.start(HashingContext.HASH_SHA256)
    digest.update(var_to_bytes([Modules.REVISION, definition]))
    checksum = digest.finish().hex_encode()
    heights.resize(COUNT)
    heights.fill(0.0)
    gradients.resize(COUNT)
    gradients.fill(Vector2.ZERO)
    buildable.resize(COUNT)
    buildable.fill(1)
    passable.resize(COUNT)
    passable.fill(1)
    materials.resize(COUNT)
    materials.fill(0)
    visibility_cache.clear()
    flat_clear.clear()
    if id == "prototype":
        navigation_clear.resize(COUNT)
        navigation_clear.fill(1)
        return true
    var occupied: Array[Rect2] = []
    for module: Dictionary in data.modules:
        if not Modules.KINDS.has(module.get("kind")) or not module.get("position") is Vector2 or not module.get("size") is Vector2:
            error = "Invalid terrain module."
            return false
        var elevation := float(module.get("height", 0.0))
        if not is_finite(elevation) or elevation < -96.0 or elevation > 192.0:
            error = "Module height must be finite and between -96 and 192."
            return false
        var rect := Rect2(module.position, module.size)
        if not Rect2(Vector2.ZERO, WORLD).encloses(rect) or rect.size.x <= 0 or rect.size.y <= 0 or int(module.get("rotation", 0)) not in [0, 1, 2, 3]:
            error = "Module outside map, invalid size or rotation: %s" % module
            return false
        for value: float in [rect.position.x, rect.position.y, rect.size.x, rect.size.y]:
            if not is_equal_approx(fposmod(value, CELL), 0.0):
                error = "Module is not aligned to the 32-unit grid."
                return false
        for previous: Rect2 in occupied:
            if previous.intersects(rect):
                error = "Overlapping terrain modules at %s." % rect.position
                return false
        occupied.append(rect)
        for z in range(int(rect.position.y / CELL), int(rect.end.y / CELL)):
            for x in range(int(rect.position.x / CELL), int(rect.end.x / CELL)):
                var index := z * WIDTH + x
                var sample := Modules.sample(module, center(index))
                heights[index] = sample.height
                gradients[index] = sample.gradient
                buildable[index] = int(sample.buildable)
                passable[index] = int(sample.passable)
                materials[index] = sample.material
    # Validate both ends of every authored ramp. Lateral edges intentionally form cliffs.
    for index in range(COUNT):
        if gradients[index] == Vector2.ZERO:
            continue
        var direction := gradients[index].normalized()
        for side in [-1.0, 1.0]:
            var edge: Vector2 = center(index) + direction * 16.0 * side
            if absf(height_at(edge - direction * 0.1) - height_at(edge + direction * 0.1)) > 1.0:
                error = "Ramp seam height mismatch at %s." % edge
                return false
    navigation_clear.resize(COUNT)
    for index in range(COUNT):
        navigation_clear[index] = int(position_clear(center(index), 24.0))
    flat_clear.resize(COUNT)
    for index in range(COUNT):
        var cx := index % WIDTH
        var cz := index / WIDTH
        var flat := gradients[index] == Vector2.ZERO and passable[index] != 0
        for dz in range(-1, 2):
            for dx in range(-1, 2):
                var next := clampi(cz + dz, 0, DEPTH - 1) * WIDTH + clampi(cx + dx, 0, WIDTH - 1)
                if gradients[next] != Vector2.ZERO or heights[next] != heights[index] or passable[next] == 0:
                    flat = false
        flat_clear[index] = int(flat)
    if not _validate_connectivity():
        return false
    return true

func cell_index(point: Vector2) -> int:
    return clampi(int(floor(point.y / CELL)), 0, DEPTH - 1) * WIDTH + clampi(int(floor(point.x / CELL)), 0, WIDTH - 1)

func center(index: int) -> Vector2:
    return Vector2((index % WIDTH) * CELL + 16.0, (index / WIDTH) * CELL + 16.0)

func height_at(point: Vector2) -> float:
    if heights.is_empty():
        return 0.0
    var index := cell_index(point)
    if gradients[index] == Vector2.ZERO:
        return heights[index]
    return heights[index] + gradients[index].dot(point - center(index))

func vertex_in_cell(index: int, point: Vector2) -> Vector3:
    return Vector3(point.x, heights[index] + gradients[index].dot(point - center(index)), point.y)

func position_clear(point: Vector2, radius: float) -> bool:
    if not Rect2(Vector2.ONE * radius, WORLD - Vector2.ONE * radius * 2).has_point(point):
        return false
    var index := cell_index(point)
    if not flat_clear.is_empty() and radius <= 16.0 and flat_clear[index] != 0:
        return true
    if passable[index] == 0:
        return false
    var h := height_at(point)
    for offset: Vector2 in [Vector2(radius, 0), Vector2(-radius, 0), Vector2(0, radius), Vector2(0, -radius), Vector2(radius, radius), Vector2(-radius, radius), Vector2(radius, -radius), Vector2(-radius, -radius)]:
        var p := point + offset
        if passable[cell_index(p)] == 0 or absf(height_at(p) - h) > radius * 0.4 + 1.0:
            return false
    return true

func segment_clear(from: Vector2, to: Vector2, radius: float) -> bool:
    if id == "prototype":
        return true
    var steps := maxi(1, ceili(from.distance_to(to) / 8.0))
    for step in range(1, steps + 1):
        if not position_clear(from.lerp(to, float(step) / steps), radius):
            return false
    return true

func build_error(rect: Rect2) -> String:
    var h := height_at(rect.get_center())
    for z in range(int(floor(rect.position.y / CELL)), int(ceil(rect.end.y / CELL)) + 1):
        for x in range(int(floor(rect.position.x / CELL)), int(ceil(rect.end.x / CELL)) + 1):
            var p := Vector2(x * CELL, z * CELL).clamp(rect.position, rect.end - Vector2.ONE * 0.01)
            var index := cell_index(p)
            if buildable[index] == 0 or passable[index] == 0 or not position_clear(p, 16.0) or absf(height_at(p) - h) > 0.1:
                return "Build on a flat platform, away from slopes and cliffs"
    return ""

func line_of_sight(from: Vector2, to: Vector2, from_offset: float = 40.0, to_offset: float = 24.0) -> bool:
    if id == "prototype":
        return true
    var start := height_at(from) + from_offset
    var finish := height_at(to) + to_offset
    var steps := maxi(1, ceili(from.distance_to(to) / 12.0))
    for step in range(1, steps):
        var t := float(step) / steps
        if height_at(from.lerp(to, t)) > lerpf(start, finish, t) - 0.5:
            return false
    return true

func visible_cells(origin: Vector2, eye_height: float) -> PackedInt32Array:
    var origin_index := cell_index(origin)
    var key := origin_index * 128 + int(eye_height)
    if visibility_cache.has(key):
        return visibility_cache[key]
    var result := PackedInt32Array()
    var cx := origin_index % WIDTH
    var cz := origin_index / WIDTH
    var marked := {}
    marked[origin_index] = true
    var eye := heights[origin_index] + eye_height
    # Cast grid rays to the perimeter once. Each ray tracks its terrain horizon;
    # this is O(radius²), rather than tracing a separate ray to every cell.
    for side in range(4):
        for along in range(-11, 12):
            var end := Vector2i(along, -11)
            if side == 1:
                end = Vector2i(11, along)
            elif side == 2:
                end = Vector2i(along, 11)
            elif side == 3:
                end = Vector2i(-11, along)
            var dx := absi(end.x)
            var dz := absi(end.y)
            var sx := signi(end.x)
            var sz := signi(end.y)
            var line_error := dx - dz
            var x := 0
            var z := 0
            var horizon := -INF
            while x != end.x or z != end.y:
                var twice := line_error * 2
                if twice > -dz:
                    line_error -= dz
                    x += sx
                if twice < dx:
                    line_error += dx
                    z += sz
                if cx + x < 0 or cx + x >= WIDTH or cz + z < 0 or cz + z >= DEPTH:
                    break
                var distance := sqrt(float(x * x + z * z)) * CELL
                if distance > 340.0:
                    break
                var index := (cz + z) * WIDTH + cx + x
                var rise := heights[index] - eye
                if (rise + 12.0) / distance >= horizon:
                    marked[index] = true
                horizon = maxf(horizon, rise / distance)
    for index: int in marked:
        result.append(index)
    visibility_cache[key] = result
    return result

func ray_hit(origin: Vector3, direction: Vector3) -> Vector3:
    # Deterministic surface ray marching includes cliff faces, then refines the first hit.
    var first := 0.0
    var last := 12000.0
    for axis in [0, 2]:
        var limit := WORLD.x if axis == 0 else WORLD.y
        if absf(direction[axis]) < 0.00001:
            if origin[axis] < 0 or origin[axis] > limit:
                return Vector3(INF, INF, INF)
        else:
            var a: float = -origin[axis] / direction[axis]
            var b: float = (limit - origin[axis]) / direction[axis]
            first = maxf(first, minf(a, b))
            last = minf(last, maxf(a, b))
    if first > last:
        return Vector3(INF, INF, INF)
    if direction.y < -0.001:
        first = maxf(first, (origin.y - 256.0) / -direction.y)
        last = minf(last, (origin.y + 128.0) / -direction.y)
    var distance := maxf(first, 0.0)
    while distance <= last:
        var p := origin + direction * distance
        if p.y <= height_at(Vector2(p.x, p.z)):
            var low := maxf(first, distance - 8.0)
            var high := distance
            for iteration in range(12):
                var mid := (low + high) * 0.5
                var probe := origin + direction * mid
                if probe.y <= height_at(Vector2(probe.x, probe.z)):
                    high = mid
                else:
                    low = mid
            return origin + direction * high
        distance += 8.0
    return Vector3(INF, INF, INF)

func road_weight(point: Vector2) -> float:
    var weight := 0.0
    for road: Dictionary in definition.roads:
        var points: Array = road.points
        for i in range(points.size() - 1):
            var a: Vector2 = points[i]
            var b: Vector2 = points[i + 1]
            var nearest := Geometry2D.get_closest_point_to_segment(point, a, b)
            weight = maxf(weight, 1.0 - smoothstep(float(road.width) * 0.32, float(road.width) * 0.65, point.distance_to(nearest)))
    return weight

func _validate_connectivity() -> bool:
    var targets: Array = definition.spawns.duplicate()
    for ore: Dictionary in definition.ores:
        targets.append(ore.pos)
    if targets.size() < 2:
        error = "A map needs two spawn points."
        return false
    for spawn: Vector2 in definition.spawns:
        if not build_error(Rect2(spawn - Vector2(112, 112), Vector2(224, 224))).is_empty():
            error = "Spawn area is not flat and clear: %s." % spawn
            return false
    var visited := PackedByteArray()
    visited.resize(COUNT)
    var queue := PackedInt32Array([cell_index(targets[0])])
    visited[queue[0]] = 1
    var cursor := 0
    while cursor < queue.size():
        var index := queue[cursor]
        cursor += 1
        for next in [index - 1, index + 1, index - WIDTH, index + WIDTH]:
            if next < 0 or next >= COUNT or visited[next] != 0 or navigation_clear[next] == 0:
                continue
            if absi(next % WIDTH - index % WIDTH) > 1:
                continue
            visited[next] = 1
            queue.append(next)
    for point: Vector2 in targets:
        if not Rect2(Vector2.ZERO, WORLD).has_point(point) or visited[cell_index(point)] == 0:
            error = "Unreachable spawn or resource at %s." % point
            return false
    return true
