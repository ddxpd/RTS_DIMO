extends RefCounted
class_name CameraController

const EDGE_MARGIN := 32.0
const MOVE_SPEED := 420.0

var camera: Camera2D
var world_size: Vector2
var viewport_size_provider: Callable
var map_area_provider: Callable
var mouse_position_provider: Callable
var speed_multiplier := 1.0

func _init(target_camera: Camera2D, world: Vector2, viewport_provider: Callable, map_provider: Callable, mouse_provider: Callable) -> void:
    camera = target_camera
    world_size = world
    viewport_size_provider = viewport_provider
    map_area_provider = map_provider
    mouse_position_provider = mouse_provider

func update(delta: float) -> void:
    if camera == null or not camera.is_inside_tree():
        return
    var mouse_position: Vector2 = mouse_position_provider.call()
    var map_rect: Rect2 = map_area_provider.call()
    var window_size: Vector2 = viewport_size_provider.call()
    var direction := Vector2.ZERO
    # Left/right edges stay anchored to the map area; the side panel shields them.
    if mouse_position.x <= map_rect.position.x + EDGE_MARGIN:
        direction.x -= 1.0
    elif mouse_position.x >= map_rect.end.x - EDGE_MARGIN:
        direction.x += 1.0
    # Vertical edges trigger on the real window bounds so HUD bars never block them.
    if mouse_position.y <= EDGE_MARGIN:
        direction.y -= 1.0
    elif mouse_position.y >= window_size.y - EDGE_MARGIN:
        direction.y += 1.0
    if direction != Vector2.ZERO:
        camera.position += direction.normalized() * MOVE_SPEED * speed_multiplier * delta / camera.zoom.x
    _limit_camera()

func _limit_camera() -> void:
    var half: Vector2 = viewport_size_provider.call() / (2.0 * camera.zoom.x)
    var max_center: Vector2 = world_size - half
    camera.position = camera.position.clamp(half.min(world_size / 2.0), max_center.max(world_size / 2.0))
