extends Node3D

const Terrain = preload("res://scripts/maps/map_terrain.gd")
const SURFACE = preload("res://assets/maps/desert_surface.gdshader")
var terrain: Terrain
var ground_material: ShaderMaterial
var rock_material: ShaderMaterial
var ground_meshes: Array[MeshInstance3D] = []

func build(data: Terrain, fog: Texture2D) -> void:
    terrain = data
    ground_material = ShaderMaterial.new()
    ground_material.shader = SURFACE
    ground_material.set_shader_parameter("fog_map", fog)
    rock_material = ground_material.duplicate()
    rock_material.set_shader_parameter("rock_surface", true)
    # Independent chunks bound culling and keep surface count modest.
    for chunk_z in range(0, Terrain.DEPTH, 25):
        for chunk_x in range(0, Terrain.WIDTH, 25):
            var ground := SurfaceTool.new()
            var walls := SurfaceTool.new()
            ground.begin(Mesh.PRIMITIVE_TRIANGLES)
            walls.begin(Mesh.PRIMITIVE_TRIANGLES)
            var has_walls := false
            for z in range(chunk_z, mini(chunk_z + 25, Terrain.DEPTH)):
                for x in range(chunk_x, mini(chunk_x + 25, Terrain.WIDTH)):
                    var index := z * Terrain.WIDTH + x
                    var origin := Vector2(x * 32, z * 32)
                    var points: Array[Vector2] = [origin, origin + Vector2(32, 0), origin + Vector2(32, 32), origin + Vector2(0, 32)]
                    var vertices: Array[Vector3] = []
                    var colors: Array[Color] = []
                    for point in points:
                        vertices.append(terrain.vertex_in_cell(index, point))
                        var tint := Color("#b18a56")
                        if terrain.materials[index] == 1:
                            tint = Color("#987348")
                        elif terrain.materials[index] == 3:
                            tint = Color("#a87648")
                        tint.a = terrain.road_weight(point) if terrain.passable[index] != 0 else 0.0
                        colors.append(tint)
                    _quad(ground, vertices, colors)
                    for side in range(4):
                        var neighbor: int = index + [ -Terrain.WIDTH, 1, Terrain.WIDTH, -1 ][side]
                        if neighbor < 0 or neighbor >= Terrain.COUNT or absi(neighbor % Terrain.WIDTH - x) > 1:
                            continue
                        var a := vertices[side]
                        var b := vertices[(side + 1) % 4]
                        var low_a: Vector3 = terrain.vertex_in_cell(neighbor, points[side])
                        var low_b: Vector3 = terrain.vertex_in_cell(neighbor, points[(side + 1) % 4])
                        if a.y <= low_a.y + 0.1 and b.y <= low_b.y + 0.1:
                            continue
                        has_walls = true
                        var core_tint := Color("#a06b3e")
                        core_tint.a = 0.0
                        _quad(walls, [a, b, low_b, low_a], [core_tint, core_tint, core_tint, core_tint])
                        for band in range(4):
                            var t0 := band / 4.0
                            var t1 := (band + 1) / 4.0
                            var tint := Color("#a06b3e").lightened(0.04 if band % 2 == 0 else 0.0)
                            tint.a = 0.0
                            var outward := Vector3.UP.cross(b - a).normalized()
                            _quad(walls, [_cliff_point(a, low_a, t0, outward), _cliff_point(b, low_b, t0, outward), _cliff_point(b, low_b, t1, outward), _cliff_point(a, low_a, t1, outward)], [tint, tint, tint, tint])
            var mesh := _finish(ground, ground_material)
            ground_meshes.append(mesh)
            if has_walls:
                _finish(walls, rock_material)
    _scatter()
    _scrub()

func set_reveal_all(value: bool) -> void:
    ground_material.set_shader_parameter("reveal_all", value)
    rock_material.set_shader_parameter("reveal_all", value)

func _quad(surface: SurfaceTool, points: Array, colors: Array) -> void:
    var normal: Vector3 = (points[2] - points[0]).cross(points[1] - points[0]).normalized()
    for index in [0, 1, 2, 0, 2, 3]:
        surface.set_normal(normal)
        surface.set_color(colors[index])
        surface.set_uv(Vector2(colors[index].a, 0.0))
        surface.add_vertex(points[index])

func _finish(surface: SurfaceTool, material: Material) -> MeshInstance3D:
    surface.index()
    var instance := MeshInstance3D.new()
    instance.mesh = surface.commit()
    instance.material_override = material
    add_child(instance)
    return instance

func _rock_mesh() -> ArrayMesh:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    var tint := Color("#ae8352")
    tint.a = 0.0
    for side in range(7):
        var a := side * TAU / 7.0
        var b := (side + 1) * TAU / 7.0
        var bottom_a := Vector3(cos(a), 0, sin(a))
        var bottom_b := Vector3(cos(b), 0, sin(b))
        var upper_a := Vector3(cos(a) * 0.72, 0.65 + sin(a * 3) * 0.14, sin(a) * 0.72)
        var upper_b := Vector3(cos(b) * 0.72, 0.65 + sin(b * 3) * 0.14, sin(b) * 0.72)
        _quad(surface, [bottom_a, bottom_b, upper_b, upper_a], [tint, tint, tint, tint])
        _quad(surface, [upper_a, upper_b, Vector3(0.12, 0.86, 0.04), Vector3(0.12, 0.86, 0.04)], [tint, tint, tint, tint])
    surface.index()
    return surface.commit()

func _scatter() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = int(terrain.definition.seed)
    var rock_mesh := _rock_mesh()
    # Chunked MultiMeshes: small stones never masquerade as impassable boulders.
    for cz in range(4):
        for cx in range(6):
            var transforms: Array[Transform3D] = []
            for index in range(200):
                var point := Vector2(cx * 800 + rng.randf_range(12, 788), cz * 800 + rng.randf_range(12, 788))
                if terrain.road_weight(point) > 0.2:
                    continue
                var cell: int = terrain.cell_index(point)
                var scale_factor := rng.randf_range(2.0, 7.0)
                if terrain.passable[cell] == 0:
                    scale_factor = rng.randf_range(18.0, 38.0)
                var basis := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3(scale_factor, scale_factor * rng.randf_range(0.4, 0.85), scale_factor))
                transforms.append(Transform3D(basis, Vector3(point.x, terrain.height_at(point) - 0.4, point.y)))
            var multi := MultiMesh.new()
            multi.transform_format = MultiMesh.TRANSFORM_3D
            multi.mesh = rock_mesh
            multi.instance_count = transforms.size()
            for index in range(transforms.size()):
                multi.set_instance_transform(index, transforms[index])
            var instance := MultiMeshInstance3D.new()
            instance.multimesh = multi
            instance.material_override = rock_material
            add_child(instance)
func _scrub() -> void:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    var tint := Color("#695532")
    tint.a = 0.0
    for side in range(5):
        var angle := side * TAU / 5.0
        var right := Vector3(cos(angle), 0, sin(angle)) * 0.16
        var tip := Vector3(cos(angle) * 0.55, 1.0, sin(angle) * 0.55)
        _quad(surface, [-right, right, tip + right * 0.2, tip - right * 0.2], [tint, tint, tint, tint])
    surface.index()
    var mesh := surface.commit()
    var rng := RandomNumberGenerator.new()
    rng.seed = int(terrain.definition.seed) + 93
    var transforms: Array[Transform3D] = []
    for index in range(650):
        var point := Vector2(rng.randf_range(64, 4736), rng.randf_range(64, 3136))
        if terrain.road_weight(point) > 0.05 or not terrain.position_clear(point, 16):
            continue
        if point.distance_to(Vector2(2400, 1600)) < 500:
            continue
        var scale_factor := rng.randf_range(7, 16)
        var basis := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * scale_factor)
        transforms.append(Transform3D(basis, Vector3(point.x, terrain.height_at(point), point.y)))
    var multi := MultiMesh.new()
    multi.transform_format = MultiMesh.TRANSFORM_3D
    multi.mesh = mesh
    multi.instance_count = transforms.size()
    for index in range(transforms.size()):
        multi.set_instance_transform(index, transforms[index])
    var instance := MultiMeshInstance3D.new()
    instance.multimesh = multi
    instance.material_override = rock_material
    add_child(instance)
func _cliff_point(top: Vector3, bottom: Vector3, fraction: float, outward: Vector3) -> Vector3:
    var point := top.lerp(bottom, fraction)
    if fraction > 0.0 and fraction < 1.0:
        var wave := sin(point.x * 0.09 + point.z * 0.07 + fraction * 13.0)
        point += outward * (2.0 + wave * 3.0)
        point.y += wave * 3.0
    return point
