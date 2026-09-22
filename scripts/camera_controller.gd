extends RefCounted
class_name CameraController

const EDGE_MARGIN := 32.0
const MOVE_SPEED := 600.0

var camera: Camera3D
var world_size: Vector2
var viewport_size_provider: Callable
var mouse_position_provider: Callable
var speed_multiplier := 1.0
var focus := Vector2.ZERO

func _init(target_camera: Camera3D, world: Vector2, viewport_provider: Callable, mouse_provider: Callable) -> void:
    camera = target_camera
    world_size = world
    viewport_size_provider = viewport_provider
    mouse_position_provider = mouse_provider

func update(delta: float) -> void:
    if camera == null or not camera.is_inside_tree():
        return
    var mouse_position: Vector2 = mouse_position_provider.call()
    var window_size: Vector2 = viewport_size_provider.call()
    var direction := Vector2.ZERO
    # All four edges trigger on the real window bounds; HUD panels sit in the
    # dead zone between the playfield edge and the 32px window trigger strip.
    if mouse_position.x <= EDGE_MARGIN:
        direction.x += 1.0
    elif mouse_position.x >= window_size.x - EDGE_MARGIN:
        direction.x -= 1.0
    if mouse_position.y <= EDGE_MARGIN:
        direction.y += 1.0
    elif mouse_position.y >= window_size.y - EDGE_MARGIN:
        direction.y -= 1.0
    if direction != Vector2.ZERO:
        focus += direction.normalized() * MOVE_SPEED * speed_multiplier * delta / _zoom_scale()
    _limit_camera()

# Higher cameras need larger focus steps to feel like constant screen-space speed.
func _zoom_scale() -> float:
    return maxf(0.4, camera.position.y / 600.0)

# Ground rectangle covered by the camera frustum (rays cast onto the y=0 plane).
func _visible_ground_rect() -> Rect2:
    var vp := camera.get_viewport().get_visible_rect()
    var points: Array = []
    for corner: Vector2 in [Vector2(0, 0), Vector2(vp.size.x, 0), Vector2(vp.size.x, vp.size.y), Vector2(0, vp.size.y)]:
        var ray_from: Vector3 = camera.project_ray_origin(corner)
        var ray_dir: Vector3 = camera.project_ray_normal(corner)
        if absf(ray_dir.y) < 0.001:
            continue
        var t: float = -ray_from.y / ray_dir.y
        if t < 0.0:
            continue
        var hit: Vector3 = ray_from + ray_dir * t
        points.append(Vector2(hit.x, hit.z))
    if points.size() < 3:
        return Rect2(Vector2.ZERO, world_size)
    var min_p: Vector2 = points[0]
    var max_p: Vector2 = points[0]
    for p: Vector2 in points:
        min_p = min_p.min(p)
        max_p = max_p.max(p)
    return Rect2(min_p, max_p - min_p)

func _limit_camera() -> void:
    # Clamp the focus point within the world bounds. Corner-ray rects are
    # too large under perspective for sub-world clamping; the focal center
    # staying on the map is the meaningful constraint for RTS gameplay.
    focus = focus.clamp(Vector2(200, 200), world_size - Vector2(200, 200))
