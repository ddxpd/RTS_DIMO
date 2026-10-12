extends Control
## Resolution-independent armor frame. Decorations never consume input.
var accent := Color("#377ca9")
var inset := false


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    resized.connect(queue_redraw)


static func outline(rect: Rect2, cut: float) -> PackedVector2Array:
    var a := rect.position
    var b := rect.end
    var c := minf(cut, minf(rect.size.x, rect.size.y) * 0.2)
    return PackedVector2Array([a + Vector2(c, 0), Vector2(b.x - c, a.y), Vector2(b.x, a.y + c),
        b - Vector2(0, c), b - Vector2(c, 0), Vector2(a.x + c, b.y), Vector2(a.x, b.y - c), a + Vector2(0, c)])


static func plate(canvas: CanvasItem, rect: Rect2, edge: Color, recessed: bool = false) -> void:
    var outer := outline(rect, 14)
    canvas.draw_colored_polygon(outer, Color("#0a1017"))
    var bevel := outline(rect.grow(-2), 13)
    canvas.draw_colored_polygon(bevel, Color("#45505b"))
    canvas.draw_colored_polygon(outline(rect.grow(-5), 11), Color("#232d38"))
    canvas.draw_colored_polygon(outline(rect.grow(-10), 9), Color("#101b27") if recessed else Color("#131b23"))
    var inner := outline(rect.grow(-11), 8)
    inner.append(inner[0])
    canvas.draw_polyline(inner, edge, 1.2, true)
    canvas.draw_line(rect.position + Vector2(21, 6), Vector2(rect.end.x - 21, rect.position.y + 6), Color("#697581"), 1.0)
    for x: float in [rect.position.x + 8, rect.end.x - 8]:
        for y: float in [rect.position.y + 9, rect.end.y - 9]:
            canvas.draw_circle(Vector2(x, y), 3.3, Color("#0a0e13"))
            canvas.draw_arc(Vector2(x, y), 3.2, 0.3, 3.5, 10, Color("#7b8490"), 0.8, true)
            canvas.draw_line(Vector2(x - 1.3, y + 1.2), Vector2(x + 1.3, y - 1.2), Color("#56636f"), 1)
    canvas.draw_line(rect.position + Vector2(17, 9), rect.position + Vector2(30, 9), Color("#e9a445"), 2)
    canvas.draw_line(rect.end - Vector2(30, 9), rect.end - Vector2(17, 9), Color("#e9a445"), 2)


func _draw() -> void:
    plate(self, Rect2(Vector2.ZERO, size), accent, inset)
