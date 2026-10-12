extends RefCounted
## Shared horizontal logical grid. Visual surface tessellation is independent.
const CELL := 32

static func aligned(value: float) -> bool:
    return is_finite(value) and absf(value / CELL - roundf(value / CELL)) < 0.00001

static func rect_aligned(rect: Rect2) -> bool:
    return aligned(rect.position.x) and aligned(rect.position.y) and aligned(rect.size.x) and aligned(rect.size.y)

static func snap_center(point: Vector2, size: Vector2) -> Vector2:
    return ((point - size * 0.5) / CELL).round() * CELL + size * 0.5

static func cell_center(point: Vector2) -> Vector2:
    return (point / CELL).floor() * CELL + Vector2.ONE * (CELL * 0.5)

static func enclosing(rect: Rect2) -> Rect2:
    var start := (rect.position / CELL).floor() * CELL
    var end := (rect.end / CELL).ceil() * CELL
    return Rect2(start, end - start)
