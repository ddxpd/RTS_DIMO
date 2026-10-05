extends "res://scripts/maps/terrain_view.gd"

const SAMPLE_SHADER = preload("res://assets/maps/sample_surface.gdshader")
var vertex_count := 0
var triangle_count := 0
var sample_build_ms := 0


func build(data: Terrain, _fog: Texture2D) -> void:
    var started := Time.get_ticks_msec()
    terrain = data
    ground_material = ShaderMaterial.new()
    ground_material.shader = SAMPLE_SHADER
    for kind in ["sand", "soil", "gravel", "rock"]:
        for channel in ["color", "nr"]:
            ground_material.set_shader_parameter(kind + "_" + channel, load("res://assets/maps/sample/" + kind + "_" + channel + ".png"))
    for parameter: String in data.definition.materials:
        ground_material.set_shader_parameter(parameter, data.definition.materials[parameter])
    rock_material = ground_material.duplicate()
    rock_material.set_shader_parameter("decoration", true)
    var field = terrain.sample_surface
    var normals := PackedVector3Array()
    var colors := PackedColorArray()
    var road_uvs := PackedVector2Array()
    var ramp_uvs := PackedVector2Array()
    var count: int = field.columns * field.rows
    normals.resize(count)
    colors.resize(count)
    road_uvs.resize(count)
    ramp_uvs.resize(count)
    for z in range(field.rows):
        for x in range(field.columns):
            var index: int = z * field.columns + x
            var p: Vector2 = field.cache_bounds.position + Vector2(x, z) * field.STEP
            normals[index] = field.normal_at(p)
            var road: Vector3 = field.road_sample(p)
            var edge: float = field.cliff_distance(p)
            var cliff_apron := 1.0 - smoothstep(18.0, 94.0, edge)
            var basin := 1.0 - smoothstep(-70.0, -6.0, field.height_at(p))
            var gravel_zone := clampf(cliff_apron * 0.85 + basin * 0.38, 0.0, 1.0) * (1.0 - road.x * 0.75)
            var contact := (1.0 - smoothstep(5.0, 38.0, edge)) * (1.0 - road.x)
            var ramp: Vector4 = field.ramp_markings(p)
            colors[index] = Color(road.x, gravel_zone, contact, ramp.x)
            road_uvs[index] = Vector2(road.y, road.z)
            ramp_uvs[index] = Vector2(ramp.y - ramp.z, ramp.w)
    # Chunks share vertex samples and normals, eliminating shading seams.
    for cz in range(0, field.rows - 1, 32):
        for cx in range(0, field.columns - 1, 32):
            var surface := SurfaceTool.new()
            surface.begin(Mesh.PRIMITIVE_TRIANGLES)
            for z in range(cz, mini(cz + 32, field.rows - 1)):
                for x in range(cx, mini(cx + 32, field.columns - 1)):
                    for offset: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1)]:
                        var vx := x + offset.x
                        var vz := z + offset.y
                        var index: int = vz * field.columns + vx
                        surface.set_normal(normals[index])
                        surface.set_color(colors[index])
                        surface.set_uv(road_uvs[index])
                        surface.set_uv2(ramp_uvs[index])
                        surface.add_vertex(field.vertex(vx, vz))
                        vertex_count += 1
                    triangle_count += 2
            ground_meshes.append(_finish(surface, ground_material))
    _buffer_ground()
    _sample_rubble()
    sample_build_ms = Time.get_ticks_msec() - started
    print("SAMPLE_VIEW triangles=", triangle_count, " build_ms=", sample_build_ms)


func _buffer_ground() -> void:
    var rect: Rect2 = terrain.sample_surface.cache_bounds
    # Four flush planes extend to the normal world boundary without overlapping
    # the fine mesh; the sample occupies only the central working area.
    var regions := [Rect2(0, 0, 4800, rect.position.y), Rect2(0, rect.end.y, 4800, 3200 - rect.end.y), Rect2(0, rect.position.y, rect.position.x, rect.size.y), Rect2(rect.end.x, rect.position.y, 4800 - rect.end.x, rect.size.y)]
    for region: Rect2 in regions:
        var surface := SurfaceTool.new()
        surface.begin(Mesh.PRIMITIVE_TRIANGLES)
        var a := Vector3(region.position.x, 0, region.position.y)
        var b := Vector3(region.end.x, 0, region.position.y)
        var c := Vector3(region.end.x, 0, region.end.y)
        var d := Vector3(region.position.x, 0, region.end.y)
        _quad(surface, [a, b, c, d], [Color(0,0,0,0), Color(0,0,0,0), Color(0,0,0,0), Color(0,0,0,0)])
        _finish(surface, ground_material)


func _sample_rubble() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = int(terrain.definition.seed)
    var field = terrain.sample_surface
    var transforms: Array[Transform3D] = []
    var tints: Array[Color] = []
    var density: float = terrain.definition.decoration_density
    for i in range(int(5200 * density)):
        var p: Vector2 = field.bounds.position + Vector2(rng.randf() * field.bounds.size.x, rng.randf() * field.bounds.size.y)
        var edge: float = field.cliff_distance(p)
        if edge > 96.0 or field.road_sample(p).x > 0.08:
            continue
        var slope: float = field.gradient_at(p).length()
        var size := rng.randf_range(2.0, 6.0)
        if slope > 0.55:
            size = rng.randf_range(9.0, 23.0)
        elif rng.randf() > 0.6:
            continue
        if field.ramp_core_distance(p) < size * 1.5:
            continue
        var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size * rng.randf_range(0.7, 1.5), size * 0.65, size))
        transforms.append(Transform3D(basis, Vector3(p.x, field.height_at(p) - size * 0.2, p.y)))
        var tint := rng.randf_range(0.86, 1.08)
        tints.append(Color(tint, tint * 0.99, tint * 0.96, 1))
    # Small irregular shoulder stones also mark the ramp away from cliff rims.
    # Their entire footprint stays outside the authored walkable core.
    for ramp: Dictionary in terrain.definition.ramps:
        var delta: Vector2 = ramp.end - ramp.start
        var direction := delta.normalized()
        var sideways := Vector2(direction.y, -direction.x)
        var spacing := float(terrain.definition.ramp_style.rubble_spacing)
        for step in range(1, int(delta.length() / spacing)):
            for side in [-1.0, 1.0]:
                if rng.randf() > clampf(density * 0.72, 0.0, 1.0):
                    continue
                var size := rng.randf_range(2.5, 5.0)
                var distance := float(ramp.width) * 0.5 + rng.randf_range(12.0, 24.0)
                var p: Vector2 = ramp.start + direction * (step * spacing + rng.randf_range(-9.0, 9.0)) + sideways * distance * side
                var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size * 0.55, size * 1.2))
                transforms.append(Transform3D(basis, Vector3(p.x, field.height_at(p) - size * 0.2, p.y)))
                var tint := rng.randf_range(0.90, 1.08)
                tints.append(Color(tint, tint, tint * 0.98, 1))
    var multi := MultiMesh.new()
    multi.transform_format = MultiMesh.TRANSFORM_3D
    multi.use_colors = true
    multi.mesh = _sample_stone()
    multi.instance_count = transforms.size()
    for index in range(transforms.size()):
        multi.set_instance_transform(index, transforms[index])
        multi.set_instance_color(index, tints[index])
    var instance := MultiMeshInstance3D.new()
    instance.name = "CliffRubble"
    instance.multimesh = multi
    instance.material_override = rock_material
    add_child(instance)


func _sample_stone() -> ArrayMesh:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for side in range(7):
        var a := side * TAU / 7.0
        var b := (side + 1) * TAU / 7.0
        var lower_a := Vector3(cos(a), 0, sin(a))
        var lower_b := Vector3(cos(b), 0, sin(b))
        var top_a := Vector3(cos(a) * (0.68 + sin(a * 3) * 0.15), 0.65 + sin(a * 2) * 0.15, sin(a) * 0.65)
        var top_b := Vector3(cos(b) * (0.68 + sin(b * 3) * 0.15), 0.65 + sin(b * 2) * 0.15, sin(b) * 0.65)
        _quad(surface, [lower_a, lower_b, top_b, top_a], [Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
        _quad(surface, [top_a, top_b, Vector3(0.1,0.85,0), Vector3(0.1,0.85,0)], [Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
    surface.index()
    return surface.commit()
