extends Node3D
## Local, fixed-position order intent. No RPC, targeting, or pathfinding state.
const DURATION := 0.70
const MOVE_COLOR := Color("#6bdbff")
const ATTACK_COLOR := Color("#ff5038")

static var _meshes: Dictionary = {}
var action := "move"
var age := 0.0
var opacity := 1.0
var diameter := 64.0
var symbol: MeshInstance3D
var material: StandardMaterial3D


func configure(next_action: String, point: Vector2) -> void:
    action = next_action
    position = Vector3(point.x, 1.5, point.y)
    var profile := "attack" if action in ["attack", "attack_move"] else "move"
    if not _meshes.has(profile):
        _meshes[profile] = _create_mesh(profile)
    material = StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.vertex_color_use_as_albedo = true
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    symbol = MeshInstance3D.new()
    symbol.mesh = _meshes[profile]
    symbol.material_override = material
    symbol.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(symbol)
    set_age(0.0)


func set_age(seconds: float) -> void:
    age = clampf(seconds, 0.0, DURATION)
    # Click -> converge (0.18s) -> confirm (0.35s) -> fade (0.70s).
    var phase := clampf(age / 0.35, 0.0, 1.0)
    var shrink := lerpf(1.0, 0.5, 1.0 - pow(1.0 - phase, 2.0))
    opacity = 1.0 - smoothstep(0.35, DURATION, age)
    diameter = 64.0 * shrink
    symbol.scale = Vector3(shrink, 1.0, shrink)
    material.albedo_color = Color(1.0, 1.0, 1.0, opacity)
    visible = age < DURATION


static func _polygon(surface: SurfaceTool, points: PackedVector2Array, color: Color) -> void:
    var indices := Geometry2D.triangulate_polygon(points)
    for index: int in indices:
        surface.set_color(color)
        surface.set_normal(Vector3.UP)
        var elevation := 0.02 if color == MOVE_COLOR or color == ATTACK_COLOR else 0.0
        surface.add_vertex(Vector3(points[index].x, elevation, points[index].y))


static func _rotated(points: PackedVector2Array, angle: float) -> PackedVector2Array:
    var result := PackedVector2Array()
    for point: Vector2 in points:
        result.append(point.rotated(angle))
    return result


static func _create_mesh(profile: String) -> ArrayMesh:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    var color := ATTACK_COLOR if profile == "attack" else MOVE_COLOR
    var edge := Color("#18232c")
    for direction in range(4):
        var angle := direction * PI / 2.0
        if profile == "move":
            # Four separated curved sectors; leave cardinal gaps for inward arrows.
            for segment in range(12):
                var a := angle + deg_to_rad(16.0 + segment * 58.0 / 12.0)
                var b := angle + deg_to_rad(16.0 + (segment + 1) * 58.0 / 12.0)
                _polygon(surface, PackedVector2Array([Vector2.from_angle(a) * 27.0, Vector2.from_angle(b) * 27.0, Vector2.from_angle(b) * 22.0, Vector2.from_angle(a) * 22.0]), edge)
                _polygon(surface, PackedVector2Array([Vector2.from_angle(a) * 26.0, Vector2.from_angle(b) * 26.0, Vector2.from_angle(b) * 23.0, Vector2.from_angle(a) * 23.0]), color)
            _polygon(surface, _rotated(PackedVector2Array([Vector2(-6, -32), Vector2(6, -32), Vector2(0, -21)]), angle), edge)
            _polygon(surface, _rotated(PackedVector2Array([Vector2(-4, -30), Vector2(4, -30), Vector2(0, -23)]), angle), color)
        else:
            # Armored diamond corners, visually different from the circular move mark.
            _polygon(surface, _rotated(PackedVector2Array([Vector2(-13, -20), Vector2(0, -32), Vector2(13, -20), Vector2(9, -16), Vector2(0, -24), Vector2(-9, -16)]), angle), edge)
            _polygon(surface, _rotated(PackedVector2Array([Vector2(-10, -20), Vector2(0, -29), Vector2(10, -20), Vector2(8, -18), Vector2(0, -25), Vector2(-8, -18)]), angle), color)
            _polygon(surface, _rotated(PackedVector2Array([Vector2(-1.8, -12), Vector2(1.8, -12), Vector2(1.8, -5), Vector2(-1.8, -5)]), angle), edge)
            _polygon(surface, _rotated(PackedVector2Array([Vector2(-0.8, -11), Vector2(0.8, -11), Vector2(0.8, -6), Vector2(-0.8, -6)]), angle), color)
    return surface.commit()
