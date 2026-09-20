extends RefCounted
class_name CameraController

const EDGE_MARGIN := 32.0
const MOVE_SPEED := 420.0

var camera: Camera2D
var world_size: Vector2
var viewport_size_provider: Callable
var mouse_position_provider: Callable
var speed_multiplier := 1.0

func _init(target_camera: Camera2D, world: Vector2, viewport_provider: Callable, mouse_provider: Callable) -> void:
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
        direction.x -= 1.0
    elif mouse_position.x >= window_size.x - EDGE_MARGIN:
        direction.x += 1.0
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
