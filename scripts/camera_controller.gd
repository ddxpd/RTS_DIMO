extends RefCounted
class_name CameraController

const EDGE_MARGIN := 32.0
const MOVE_SPEED := 600.0

var camera: Camera3D
var world_size: Vector2
var viewport_size_provider: Callable
var mouse_position_provider: Callable
var speed_multiplier := 1.0
var surface_picker: Callable
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
    if not Rect2(Vector2.ZERO, window_size).has_point(mouse_position):
        _limit_camera()
        return
    var direction := Vector2.ZERO
    # All four edges trigger on the real window bounds; HUD panels sit in the
    # dead zone between the playfield edge and the 32px window trigger strip.
    if mouse_position.x <= EDGE_MARGIN:
        direction.x -= 1.0
    elif mouse_position.x >= window_size.x - EDGE_MARGIN:
        direction.x += 1.0
    if mouse_position.y <= EDGE_MARGIN:
        direction.y -= 1.0
    elif mouse_position.y >= window_size.y - EDGE_MARGIN:
        direction.y += 1.0
    if direction != Vector2.ZERO:
        pan(direction, delta)
    _limit_camera()

func plane_point(screen: Vector2) -> Vector3:
    # Use the focal plane, never absolute camera altitude or a terrain ray hit.
    var ray := camera.project_ray_normal(screen)
    var origin := camera.project_ray_origin(screen)
    var center_ray := camera.project_ray_normal(camera.get_viewport().get_visible_rect().size * 0.5)
    var horizontal := Vector2(center_ray.x, center_ray.z).length()
    var distance := Vector2(camera.position.x, camera.position.z).distance_to(focus) / maxf(horizontal, 0.0001)
    var height := camera.position.y + center_ray.y * distance
    if absf(ray.y) < 0.0001:
        return Vector3(focus.x, height, focus.y)
    return origin + ray * ((height - origin.y) / ray.y)


func pan(direction: Vector2, delta: float) -> void:
    if direction.is_zero_approx():
        return
    var size: Vector2 = camera.get_viewport().get_visible_rect().size
    var center := size * 0.5
    var p := plane_point(center)
    var dx := plane_point(center + Vector2.RIGHT) - p
    var dy := plane_point(center + Vector2.DOWN) - p
    var screen_step := direction.limit_length() * MOVE_SPEED * speed_multiplier * delta * size.y / 1080.0
    var world_step := dx * screen_step.x + dy * screen_step.y
    focus += Vector2(world_step.x, world_step.z)


func drag(previous: Vector2, current: Vector2) -> void:
    var offset := plane_point(previous) - plane_point(current)
    focus += Vector2(offset.x, offset.z)
    _limit_camera()

# Ground rectangle covered by the camera frustum (rays cast onto the y=0 plane).
func _visible_ground_rect() -> Rect2:
    var vp := camera.get_viewport().get_visible_rect()
    var points: Array = []
    for corner: Vector2 in [Vector2(0, 0), Vector2(vp.size.x, 0), Vector2(vp.size.x, vp.size.y), Vector2(0, vp.size.y)]:
        if surface_picker.is_valid():
            var point: Vector2 = surface_picker.call(corner)
            if point.x >= 0 and point.y >= 0:
                points.append(point)
                continue
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
