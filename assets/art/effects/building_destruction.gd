extends Node3D
## Presentation-only debris. Absolute event age supports snapshots and late joins.
const EntityVisual = preload("res://assets/art/entity_visual.gd")
const DURATION := 6.0
var elapsed := 0.0
var finished := false
var kind := ""
var hull: Node3D
var hull_meshes: Array[MeshInstance3D] = []
var hull_parts: Array[Dictionary] = []
var scorch_materials: Array[Dictionary] = []
var debris: Array[Dictionary] = []
var clouds: Array[Dictionary] = []
var bursts: Array[Dictionary] = []
var fall_height := 0.0
var extent := Vector2.ZERO


func configure(event: Dictionary, ground: float) -> void:
    var data: Dictionary = event.destruction
    kind = data.type
    position = Vector3(event.to.x, ground, event.to.y)
    rotation.y = float(data.heading)
    fall_height = maxf(0.0, float(data.height) - ground)
    extent = {"base": Vector2(320, 192), "barracks": Vector2(128, 96), "refinery": Vector2(128, 128)}[kind]
    var source := EntityVisual.new(kind, int(event.owner))
    add_child(source)
    # Keep only the currently visible geometry, without controllers, lights or UI.
    hull = Node3D.new()
    add_child(hull)
    for mesh: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
        if not mesh.is_visible_in_tree():
            continue
        var copy := MeshInstance3D.new()
        copy.mesh = mesh.mesh
        copy.transform = source.global_transform.affine_inverse() * mesh.global_transform
        copy.material_override = mesh.material_override
        for surface in range(mesh.mesh.get_surface_count()):
            var original := mesh.get_active_material(surface) as StandardMaterial3D
            if original != null:
                var material := original.duplicate() as StandardMaterial3D
                copy.set_surface_override_material(surface, material)
                scorch_materials.append({"material": material, "color": material.albedo_color, "energy": material.emission_energy_multiplier})
                if "Glass" in original.resource_name:
                    copy.set_meta("glass", true)
        hull.add_child(copy)
        hull_meshes.append(copy)
    source.free()
    var rng := RandomNumberGenerator.new()
    rng.seed = int(data.id) * 7919 + int(event.frame)
    for mesh in hull_meshes:
        hull_parts.append({"mesh": mesh, "origin": mesh.position, "rotation": mesh.rotation,
            "drift": Vector3(rng.randf_range(-0.06, 0.06) * extent.x, rng.randf_range(-9, 0), rng.randf_range(-0.06, 0.06) * extent.y),
            "tilt": Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08))})
    var energy := Color(0.1, 0.65, 1.0) if kind == "refinery" else Color(1.0, 0.28, 0.025)
    for i in range(18 if kind == "base" else 12):
        var chunk := _mesh(BoxMesh.new(), energy if kind == "refinery" and i % 3 == 0 else Color(0.16, 0.18, 0.2), kind == "refinery" and i % 3 == 0)
        chunk.scale = Vector3(rng.randf_range(3, 9), rng.randf_range(2, 6), rng.randf_range(3, 9))
        var origin := Vector3(rng.randf_range(-0.35, 0.35) * extent.x, fall_height + 24, rng.randf_range(-0.35, 0.35) * extent.y)
        debris.append({"node": chunk, "origin": origin, "velocity": Vector3(rng.randf_range(-70, 70), rng.randf_range(60, 125), rng.randf_range(-70, 70)), "spin": Vector3(rng.randf(), rng.randf(), rng.randf()) * 4.0})
    for i in range(9):
        var puff := _cloud(Color(0.17, 0.18, 0.2), false)
        clouds.append({"node": puff, "origin": Vector3(rng.randf_range(-0.35, 0.35) * extent.x, fall_height + 25, rng.randf_range(-0.35, 0.35) * extent.y), "delay": float(i) * 0.12})
    for i in range(5 if kind == "base" else 3):
        var burst := _cloud(energy, true)
        bursts.append({"node": burst, "origin": Vector3(rng.randf_range(-0.3, 0.3) * extent.x, fall_height + 30, rng.randf_range(-0.3, 0.3) * extent.y), "delay": float(i) * 0.22})
    advance(0.0, 0.0)


func _cloud(color: Color, glowing: bool) -> MeshInstance3D:
    var quad := QuadMesh.new()
    quad.size = Vector2.ONE * 2.0
    var mesh := _mesh(quad, color, glowing)
    var texture := GradientTexture2D.new()
    texture.width = 64
    texture.height = 64
    texture.fill = GradientTexture2D.FILL_RADIAL
    texture.fill_from = Vector2(0.5, 0.5)
    texture.fill_to = Vector2(1, 0.5)
    texture.gradient = Gradient.new()
    texture.gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
    texture.gradient.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.25), Color(1, 1, 1, 0)])
    var material := mesh.material_override as StandardMaterial3D
    material.albedo_texture = texture
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    material.billboard_keep_scale = true
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    return mesh


func _mesh(shape: Mesh, color: Color, glowing: bool) -> MeshInstance3D:
    var mesh := MeshInstance3D.new()
    if shape is SphereMesh:
        shape.radial_segments = 12
        shape.rings = 6
    mesh.mesh = shape
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.95
    if glowing:
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        material.emission_enabled = true
        material.emission = color
        material.emission_energy_multiplier = 3.0
    mesh.material_override = material
    mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(mesh)
    return mesh


func advance(age: float, delta: float) -> void:
    elapsed = maxf(age, elapsed + maxf(delta, 0.0))
    finished = elapsed >= DURATION
    if finished:
        visible = false
        return
    var collapse := smoothstep(0.25, 2.2, elapsed)
    hull.position.y = fall_height * (1.0 - collapse) - collapse * (30.0 if kind == "base" else 14.0)
    hull.rotation = Vector3(collapse * (0.22 if kind == "base" else 0.08), 0, collapse * (0.12 if kind == "base" else -0.16))
    hull.scale.y = 1.0 - collapse * (0.65 if kind == "barracks" else 0.35)
    var fade := smoothstep(3.2, DURATION, elapsed)
    for part: Dictionary in hull_parts:
        part.mesh.position = part.origin + part.drift * collapse
        part.mesh.rotation = part.rotation + part.tilt * collapse
        if part.mesh.has_meta("glass"):
            part.mesh.visible = elapsed < 0.25
    for entry: Dictionary in scorch_materials:
        entry.material.albedo_color = (entry.color as Color).lerp(Color(0.075, 0.07, 0.065, entry.color.a), smoothstep(0.1, 1.8, elapsed) * 0.95)
        entry.material.emission_energy_multiplier = entry.energy * (1.0 - smoothstep(0.0, 0.8, elapsed))
    for mesh in hull_meshes:
        mesh.transparency = fade
    for piece: Dictionary in debris:
        var t := minf(elapsed, 2.4)
        var p: Vector3 = piece.origin + piece.velocity * t + Vector3.DOWN * 95.0 * t * t
        p.y = maxf(3.0, p.y)
        piece.node.position = p
        piece.node.rotation = piece.spin * t
        piece.node.transparency = fade
    for cloud: Dictionary in clouds:
        var t := maxf(0.0, elapsed - float(cloud.delay))
        cloud.node.visible = elapsed >= float(cloud.delay)
        cloud.node.position = cloud.origin + Vector3(t * 5.0, t * 18.0, 0)
        cloud.node.scale = Vector3.ONE * (12.0 + t * 17.0)
        cloud.node.transparency = clampf(0.2 + t / 7.0, 0.0, 1.0)
    for burst: Dictionary in bursts:
        var t := elapsed - float(burst.delay)
        burst.node.visible = t >= 0.0 and t < 0.7
        burst.node.position = burst.origin
        burst.node.scale = Vector3.ONE * (8.0 + maxf(0.0, t) * (100.0 if kind == "base" else 65.0))
        burst.node.transparency = clampf(t / 0.7, 0.0, 1.0)
