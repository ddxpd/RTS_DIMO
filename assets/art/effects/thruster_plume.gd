extends Node3D
## Cosmetic jet. Local -Y is exhaust direction; all dimensions are world units.
const PLUME_SHADER = preload("res://assets/art/effects/thruster_plume.gdshader")
static var shell_mesh: ArrayMesh
static var shell_material: ShaderMaterial
static var core_material: ShaderMaterial
static var soft_texture: GradientTexture2D

var radius := 5.0
var max_length := 35.0
var lift := false
var phase := 0.0
var strength := 0.0
var target_strength := 0.0
var outer: MeshInstance3D
var inner: MeshInstance3D
var tail: GPUParticles3D
var dust: GPUParticles3D
var dust_power := 0.0
var was_shown := false


func _init(width: float = 5.0, length: float = 35.0, is_lift: bool = false, offset: float = 0.0) -> void:
    radius = width
    max_length = length
    lift = is_lift
    phase = offset


func _ready() -> void:
    if shell_mesh == null:
        # Two crossing flow sheets keep a soft silhouette from any RTS azimuth.
        # The shader tapers alpha instead of exposing the boundary of a cone.
        shell_mesh = ArrayMesh.new()
        var arrays := []
        arrays.resize(Mesh.ARRAY_MAX)
        arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
            Vector3(-1, 0.5, 0), Vector3(1, 0.5, 0), Vector3(-1, -0.5, 0), Vector3(1, -0.5, 0),
            Vector3(0, 0.5, -1), Vector3(0, 0.5, 1), Vector3(0, -0.5, -1), Vector3(0, -0.5, 1)])
        arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK,
            Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT])
        arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1),
            Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)])
        arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 1, 3, 2, 4, 5, 6, 5, 7, 6])
        shell_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
        shell_material = ShaderMaterial.new()
        shell_material.shader = PLUME_SHADER
        core_material = ShaderMaterial.new()
        core_material.shader = PLUME_SHADER
        core_material.set_shader_parameter("core", true)
        var gradient := Gradient.new()
        gradient.set_color(0, Color.WHITE)
        gradient.add_point(0.35, Color(1, 1, 1, 0.6))
        gradient.set_color(gradient.get_point_count() - 1, Color(1, 1, 1, 0))
        soft_texture = GradientTexture2D.new()
        soft_texture.gradient = gradient
        soft_texture.width = 32
        soft_texture.height = 32
        soft_texture.fill = GradientTexture2D.FILL_RADIAL
        soft_texture.fill_from = Vector2(0.5, 0.5)
        soft_texture.fill_to = Vector2(1, 0.5)
    outer = _layer("OuterFlow", shell_material)
    inner = _layer("WhiteCore", core_material)
    tail = _particles(false)
    if lift:
        dust = _particles(true)
    visible = false


func _layer(label: String, material: ShaderMaterial) -> MeshInstance3D:
    var mesh := MeshInstance3D.new()
    mesh.name = label
    mesh.mesh = shell_mesh
    mesh.material_override = material
    mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    mesh.set_instance_shader_parameter("phase", phase)
    add_child(mesh)
    return mesh


func _particles(is_dust: bool) -> GPUParticles3D:
    var particles := GPUParticles3D.new()
    particles.name = "GroundWash" if is_dust else "TailWisps"
    particles.amount = 12 if is_dust else 6
    particles.lifetime = 1.25 if is_dust else 0.32
    particles.emitting = false
    particles.local_coords = not is_dust
    particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    particles.visibility_aabb = AABB(Vector3.ONE * -max_length * 2.0, Vector3.ONE * max_length * 4.0)
    var process := ParticleProcessMaterial.new()
    process.direction = Vector3.UP if is_dust else Vector3.DOWN
    process.spread = 85.0 if is_dust else 9.0
    process.gravity = Vector3(0, 1, 0) if is_dust else Vector3.ZERO
    process.initial_velocity_min = radius * (2.0 if is_dust else 3.0)
    process.initial_velocity_max = radius * (4.0 if is_dust else 6.0)
    process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX if is_dust else ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    process.emission_box_extents = Vector3(radius * 1.3, 0.1, radius * 1.3)
    process.emission_sphere_radius = radius * (1.3 if is_dust else 0.2)
    process.scale_min = radius * (2.0 if is_dust else 0.2)
    process.scale_max = radius * (3.5 if is_dust else 0.45)
    var fade := Gradient.new()
    fade.set_color(0, Color(1, 1, 1, 0))
    fade.add_point(0.15, Color.WHITE)
    fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
    var ramp := GradientTexture1D.new()
    ramp.gradient = fade
    process.color_ramp = ramp
    particles.process_material = process
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX if is_dust else BaseMaterial3D.BLEND_MODE_ADD
    material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
    material.billboard_keep_scale = true
    material.vertex_color_use_as_albedo = true
    material.albedo_texture = soft_texture
    material.albedo_color = Color(0.48, 0.43, 0.34, 0.16) if is_dust else Color(0.06, 0.55, 1, 0.3)
    var quad := QuadMesh.new()
    quad.material = material
    particles.draw_pass_1 = quad
    add_child(particles)
    return particles


static func lift_power(state: String, progress: float, cruising: bool = false) -> float:
    var p := clampf(progress, 0.0, 1.0)
    match state:
        "taking_off":
            return lerpf(0.12, 0.58, smoothstep(0.0, 0.25, p)) + 0.32 * sin(p * PI)
        "airborne":
            return 0.78 if cruising else 0.56
        "landing":
            return (0.56 + 0.2 * sin(p * PI)) * (1.0 - smoothstep(0.82, 1.0, p))
    return 0.0


func advance(delta: float, power: float, lod: int, shown: bool, ground_sampler: Callable = Callable()) -> void:
    target_strength = clampf(power, 0.0, 1.0)
    # Never retain invisible particles across fog-of-war or construction changes.
    if not shown:
        was_shown = false
        strength = 0.0
        visible = false
        tail.emitting = false
        if dust != null:
            dust.emitting = false
            dust_power = 0.0
        return
    if not was_shown:
        tail.restart()
        if dust != null:
            dust.restart()
    was_shown = true
    strength = lerpf(strength, target_strength, 1.0 if delta <= 0 else 1.0 - exp(-delta * 12.0))
    if target_strength == 0.0 and strength < 0.005:
        strength = 0.0
    visible = strength > 0.0
    var length := max_length * lerpf(0.25, 1.0, strength)
    outer.scale = Vector3(radius, length, radius)
    outer.position.y = -length * 0.5
    inner.scale = Vector3(radius * 0.44, length * 0.48, radius * 0.44)
    inner.position.y = -length * 0.24
    outer.visible = lod < 2
    for mesh: MeshInstance3D in [outer, inner]:
        mesh.set_instance_shader_parameter("power", strength)
    tail.position.y = -length * 0.62
    tail.emitting = visible and target_strength > 0.05 and lod == 0
    tail.visible = visible and lod == 0
    if dust != null:
        var ground := float(ground_sampler.call(Vector2(global_position.x, global_position.z))) if ground_sampler.is_valid() else 0.0
        outer.set_instance_shader_parameter("ground_height", ground)
        inner.set_instance_shader_parameter("ground_height", ground)
        var clearance := global_position.y - ground
        dust_power = strength * (1.0 - smoothstep(radius * 2.0, max_length * 1.8, clearance))
        if clearance < 0.0:
            dust_power = 0.0
        dust.global_transform = Transform3D(Basis.IDENTITY, Vector3(global_position.x, ground + 0.6, global_position.z))
        dust.emitting = visible and target_strength > 0.05 and dust_power > 0.04 and lod == 0
        dust.visible = visible and lod == 0 and clearance >= 0.0
        (dust.draw_pass_1.material as StandardMaterial3D).albedo_color.a = 0.24 * dust_power
