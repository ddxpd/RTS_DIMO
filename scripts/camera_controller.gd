extends RefCounted
class_name CameraController

const EDGE_MARGIN := 32.0
const MOVE_SPEED := 420.0

var camera: Camera2D
var world_size: Vector2
var viewport_size_provider: Callable
var map_area_provider: Callable

func _init(target_camera: Camera2D, world: Vector2, viewport_provider: Callable, map_provider: Callable) -> void:
    camera = target_camera
    world_size = world
    viewport_size_provider = viewport_provider
    map_area_provider = map_provider

func update(delta: float) -> void:
    if camera == null or not camera.is_inside_tree():
        return
    var mouse_position := camera.get_viewport().get_mouse_position()
    var map_rect: Rect2 = map_area_provider.call()
    if not map_rect.has_point(mouse_position):
        _limit_camera()
        return
    var direction := Vector2.ZERO
    if mouse_position.x <= map_rect.position.x + EDGE_MARGIN:
        direction.x -= 1.0
    elif mouse_position.x >= map_rect.end.x - EDGE_MARGIN:
        direction.x += 1.0
    if mouse_position.y <= map_rect.position.y + EDGE_MARGIN:
        direction.y -= 1.0
    elif mouse_position.y >= map_rect.end.y - EDGE_MARGIN:
        direction.y += 1.0
    if direction != Vector2.ZERO:
        camera.position += direction.normalized() * MOVE_SPEED * delta / camera.zoom.x
    _limit_camera()

func _limit_camera() -> void:
    var half := viewport_size_provider.call() / (2.0 * camera.zoom.x)
    var max_center := world_size - half
    camera.position = camera.position.clamp(half.min(world_size / 2.0), max_center.max(world_size / 2.0))
