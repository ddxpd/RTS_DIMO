extends RefCounted
## Terrain-only connected terraces. Buildings affect slots, not region identity.

var source: WeakRef
var terrain:
    get:
        return source.get_ref()
var labels := PackedInt32Array()
var slopes := PackedByteArray()
var candidate_cache := {}


func _init(owner) -> void:
    source = weakref(owner)
    labels.resize(terrain.COUNT)
    labels.fill(-1)
    slopes.resize(terrain.COUNT)
    for i in terrain.COUNT:
        slopes[i] = int(terrain.gradients[i].length() > .05)
    var region := 0
    for seed in terrain.COUNT:
        if labels[seed] >= 0 or terrain.navigation_clear[seed] == 0:
            continue
        labels[seed] = region
        var queue: Array[int] = [seed]
        var head := 0
        while head < queue.size():
            var index := queue[head]
            head += 1
            var cell := Vector2i(index % terrain.WIDTH, int(index / terrain.WIDTH))
            for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
                var next := cell + offset
                if next.x < 0 or next.y < 0 or next.x >= terrain.WIDTH or next.y >= terrain.DEPTH:
                    continue
                var n: int = next.y * terrain.WIDTH + next.x
                if labels[n] >= 0 or terrain.navigation_clear[n] == 0 or slopes[n] != slopes[index]:
                    continue
                var tolerance := 14.0 if slopes[n] else 1.0
                if absf(terrain.heights[n] - terrain.heights[index]) > tolerance:
                    continue
                labels[n] = region
                queue.append(n)
        region += 1


func at(point: Vector2) -> int:
    if not Rect2(Vector2.ZERO, terrain.WORLD).has_point(point):
        return -1
    var height: float = terrain.height_at(point)
    var slope := int(terrain.gradient_at(point).length() > .05)
    var cell := Vector2i((point / terrain.CELL).floor())
    var best := INF
    var result := -1
    # A cliff-edge click may share a coarse cell with the other elevation.
    # Match its actual surface, never blindly choose that cell's centre.
    for y in range(-2, 3):
        for x in range(-2, 3):
            var c := cell + Vector2i(x, y)
            if c.x < 0 or c.y < 0 or c.x >= terrain.WIDTH or c.y >= terrain.DEPTH:
                continue
            var index: int = c.y * terrain.WIDTH + c.x
            if labels[index] < 0 or slopes[index] != slope:
                continue
            if absf(terrain.heights[index] - height) > (14.0 if slope else 1.0):
                continue
            var d: float = terrain.center(index).distance_squared_to(point)
            if d < best:
                best = d
                result = labels[index]
    return result


func candidates(anchor: Vector2, region: int) -> Array[Vector2]:
    var key := Vector3(anchor.x, anchor.y, region)
    if candidate_cache.has(key):
        return candidate_cache[key]
    var result: Array[Vector2] = []
    for y in range(-10, 11):
        for x in range(-10, 11):
            var p := anchor + Vector2(x, y) * 12.0
            if p.distance_squared_to(anchor) <= 128.0 * 128.0 and at(p) == region:
                result.append(p)
    result.sort_custom(func(a: Vector2, b: Vector2):
        var da := a.distance_squared_to(anchor)
        var db := b.distance_squared_to(anchor)
        return da < db if not is_equal_approx(da, db) else (a.x < b.x if a.x != b.x else a.y < b.y))
    if candidate_cache.size() >= 128:
        candidate_cache.clear()
    candidate_cache[key] = result
    return result
