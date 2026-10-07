extends RefCounted
## One live skeleton and one mesh instance; LOD meshes/textures are shared.

const PATHS := ["res://assets/models/soldier.glb", "res://assets/models/soldier_lod1.glb", "res://assets/models/soldier_lod2.glb"]
static var meshes: Array[Mesh] = []
var instance: MeshInstance3D
var level := 0
var on_screen := true
var projected_height := 0.0


func _init(model: Node3D) -> void:
    instance = model.find_children("*", "MeshInstance3D", true, false)[0]
    if meshes.is_empty():
        for path: String in PATHS:
            var scene := load(path) as PackedScene
            var source := scene.instantiate()
            var mesh: Mesh = source.find_children("*", "MeshInstance3D", true, false)[0].mesh
            if not meshes.is_empty():
                for surface in mesh.get_surface_count():
                    mesh.surface_set_material(surface, meshes[0].surface_get_material(surface))
            meshes.append(mesh)
            source.free()


func select_height(pixels: float) -> void:
    projected_height = pixels
    # Hysteresis in 1080p-equivalent pixels avoids swaps around zoom boundaries.
    var next := level
    if level == 0 and pixels < 90.0:
        next = 1
    if level == 1 and pixels > 110.0:
        next = 0
    if next == 1 and pixels < 36.0:
        next = 2
    if level == 2 and pixels > 44.0:
        next = 0 if pixels > 110.0 else 1
    if next != level:
        level = next
        # Keep the original skin, skeleton path and per-instance team overrides.
        instance.mesh = meshes[level]


func update(camera: Camera3D, visual: Node3D) -> void:
    if camera == null:
        return
    var bottom := visual.global_position
    var top := bottom + Vector3.UP * 68.0
    var viewport_size := camera.get_viewport().get_visible_rect().size
    if camera.is_position_behind(bottom + Vector3.UP * 34.0):
        on_screen = false
        return
    var a := camera.unproject_position(bottom)
    var b := camera.unproject_position(top)
    var pixels := a.distance_to(b)
    on_screen = visual.is_visible_in_tree() and Rect2(Vector2.ZERO, viewport_size).grow(maxf(pixels, 16.0)).has_point((a + b) * .5)
    select_height(pixels * 1080.0 / maxf(viewport_size.y, 1.0))
