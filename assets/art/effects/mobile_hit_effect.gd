extends Node3D
## Local presentation only. A fixed surface anchor follows the rendered target.
const DURATION := 0.20
const Visual = preload("res://assets/art/entity_visual.gd")
static var glow_texture: Texture2D
static var spark_mesh: BoxMesh
var anchor := Vector3.ZERO
var attached := false
var initialized := false
var elapsed := 0.0
var flash: Sprite3D
var smoke: Sprite3D
var muzzle: Sprite3D
var muzzle_socket: Node3D
var sparks: MultiMeshInstance3D


static func texture() -> Texture2D:
    if glow_texture == null:
        var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
        for y in range(32):
            for x in range(32):
                var radius := Vector2(x - 15.5, y - 15.5).length() / 15.5
                image.set_pixel(x, y, Color(1, 1, 1, pow(maxf(0.0, 1.0 - radius), 2.0)))
        glow_texture = ImageTexture.create_from_image(image)
    return glow_texture


func sprite(size: float) -> Sprite3D:
    var result := Sprite3D.new()
    result.texture = texture()
    result.pixel_size = size / 32.0
    result.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    result.shaded = false
    result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(result)
    return result


func _ready() -> void:
    flash = sprite(16.0)
    smoke = sprite(18.0)
    muzzle = sprite(12.0 * Visual.MOBILE_INFANTRY_SIZE_FACTOR)
    muzzle.top_level = true
    if spark_mesh == null:
        spark_mesh = BoxMesh.new()
        spark_mesh.size = Vector3(0.7, 0.7, 3.0)
        var material := StandardMaterial3D.new()
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        material.vertex_color_use_as_albedo = true
        spark_mesh.material = material
    sparks = MultiMeshInstance3D.new()
    sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.use_colors = true
    multimesh.mesh = spark_mesh
    multimesh.instance_count = 6
    sparks.multimesh = multimesh
    add_child(sparks)


func sample(event: Dictionary, target: Node3D, shooter: Node3D, terrain, age: float, delta: float = 0.0) -> void:
    # Continue fading after the winning tick and during delayed snapshots.
    elapsed = maxf(age, elapsed + maxf(delta, 0.0))
    age = elapsed
    var info: Dictionary = event.impact
    var toward: Vector2 = ((event.from as Vector2) - (info.target_pos as Vector2)).normalized()
    if toward.length_squared() < 0.1:
        toward = Vector2.DOWN
    var seed_value: int = int(event.frame) + int(info.source_id) * 17
    var jitter := float(seed_value % 7 - 3)
    if not initialized:
        var point: Vector2 = info.target_pos
        var offset: Vector2
        var height: float = Visual.MODEL_SETTINGS[info.target_type].height
        if info.target_kind == "building":
            var half: Vector2 = Simulation.BUILD_TYPES[info.target_type].size * 0.44
            var distance := minf(half.x / maxf(absf(toward.x), 0.001), half.y / maxf(absf(toward.y), 0.001))
            offset = toward * distance + toward.orthogonal() * jitter * 3.0
            height *= 0.28 if info.target_type == "base" else 0.5
        else:
            var body_depth := 12.0 if info.target_type == "soldier" else (10.0 if info.target_type == "mobile_infantry" else 29.0)
            if info.target_type == "mobile_infantry":
                body_depth *= Visual.MOBILE_INFANTRY_SIZE_FACTOR
            offset = toward * body_depth
            offset += toward.orthogonal() * jitter * 0.6
            height *= 0.62
        point += offset
        global_position = Vector3(point.x, terrain.height_at(info.target_pos) + height + jitter * 0.7, point.y)
        if is_instance_valid(target):
            # Include visual interpolation and elevation, then retain local offset.
            global_position += target.global_position - Vector3(info.target_pos.x, terrain.height_at(info.target_pos), info.target_pos.y)
            anchor = target.to_local(global_position)
            attached = true
        initialized = true
        if is_instance_valid(shooter):
            muzzle_socket = shooter.find_child("MuzzleSocket", true, false) as Node3D
    if attached and is_instance_valid(target):
        global_position = target.to_global(anchor)
    else:
        attached = false
    visible = age < DURATION
    var fraction := clampf(age / DURATION, 0.0, 1.0)
    flash.modulate = Color(3.0, 1.8, 0.65, pow(1.0 - fraction, 3.0))
    flash.scale = Vector3.ONE * (1.0 + fraction * 0.6)
    smoke.position = Vector3(0, fraction * 5.0, 0)
    smoke.scale = Vector3.ONE * (0.4 + fraction)
    smoke.modulate = Color(0.45, 0.42, 0.38, sin(fraction * PI) * 0.22)
    for index in range(6):
        var angle := index * TAU / 6.0 + float(seed_value % 11) * 0.2
        var direction := Vector3(toward.x, 0.6, toward.y) + Vector3(cos(angle), sin(angle) * 0.7, sin(angle)) * 0.65
        direction = direction.normalized()
        var basis := Basis.looking_at(direction, Vector3.UP)
        sparks.multimesh.set_instance_transform(index, Transform3D(basis, direction * fraction * (7.0 + index)))
        sparks.multimesh.set_instance_color(index, Color(1.0, 0.65, 0.15, 1.0 - fraction))
    muzzle.visible = visible and age < 0.075 and is_instance_valid(shooter) and shooter.visible
    if muzzle.visible:
        muzzle.visible = is_instance_valid(muzzle_socket)
        if is_instance_valid(muzzle_socket):
            muzzle.global_position = muzzle_socket.global_position
            muzzle.modulate = Color(3.0, 1.8, 0.6, 1.0 - age / 0.075)
