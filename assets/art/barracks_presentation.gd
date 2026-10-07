extends RefCounted
const Simulation = preload("res://scripts/simulation.gd")

# Mesh resources are shared. Only the original rig is ever put in the scene tree.
const LOD_SCENES := [preload("res://assets/models/barracks_lod1.glb"), preload("res://assets/models/barracks_lod2.glb")]
static var shared_lods: Array[Dictionary] = []

var visual: Node3D
var meshes: Array[MeshInstance3D] = []
var levels: Array[Dictionary] = []
var materials: Dictionary = {}
var far_materials: Dictionary = {}
var lod := 0
var status := "ready"
var phase := 0.0
var view_elapsed := 1.0
var on_screen := true
var projected_pixels := 256.0
var flag_elapsed := 0.0
var critical_elapsed := 0.0
var lamp: StandardMaterial3D
var engine: StandardMaterial3D
var smoke: CPUParticles3D
var sparks: CPUParticles3D
var soot: MeshInstance3D
var effect_root: Node3D
var rear_jets: Array[MeshInstance3D] = []


func _init(owner_visual: Node3D) -> void:
    visual = owner_visual
    if shared_lods.is_empty():
        for scene: PackedScene in LOD_SCENES:
            var temporary := scene.instantiate()
            var resources := {}
            for mesh: MeshInstance3D in temporary.find_children("*", "MeshInstance3D", true, false):
                resources[str(mesh.name)] = mesh.mesh
            shared_lods.append(resources)
            temporary.free()
    var near := {}
    for mesh: MeshInstance3D in visual.model.find_children("*", "MeshInstance3D", true, false):
        meshes.append(mesh)
        near[str(mesh.name)] = mesh.mesh
    levels = [near, shared_lods[0], shared_lods[1]]
    for entry: Dictionary in visual._materials:
        var material: StandardMaterial3D = entry.material
        materials[material.resource_name] = material
        if "Thrust" in material.resource_name:
            engine = material
        if "Amber" in material.resource_name:
            lamp = material
    for resource: Mesh in levels[2].values():
        for surface in range(resource.get_surface_count()):
            var source := resource.surface_get_material(surface) as StandardMaterial3D
            if source != null and source.resource_name in ["RTS_Body", "V2_FactionPaint"] and not far_materials.has(source.resource_name):
                far_materials[source.resource_name] = source.duplicate()
                far_materials[source.resource_name].vertex_color_use_as_albedo = true
    _create_effects()


static func choose_lod(pixels: float, previous: int, transitioning: bool) -> int:
    var next := previous
    if pixels >= (176.0 if previous > 0 else 144.0):
        next = 0
    elif pixels < (72.0 if previous < 2 else 88.0):
        next = 2
    else:
        next = 1
    return mini(next, 1) if transitioning else next


func set_lod(next: int) -> void:
    if next == lod:
        return
    lod = next
    if lod == 2:
        _sync_far_materials()
    for mesh: MeshInstance3D in meshes:
        var node_name := str(mesh.name)
        # Hydraulic rods are subpixel at this size; the control nodes remain.
        var hidden := lod == 2 and (node_name.begins_with("Gear") or node_name.begins_with("RampRod") or node_name.begins_with("RampCylinder") or node_name == "BarracksFlag")
        mesh.visible = not hidden
        var replacement: Mesh = levels[lod].get(node_name, levels[0][node_name])
        for surface in range(mesh.mesh.get_surface_count()):
            mesh.set_surface_override_material(surface, null)
        mesh.mesh = replacement
        for surface in range(replacement.get_surface_count()):
            var source := replacement.surface_get_material(surface)
            if source != null and lod == 2 and far_materials.has(source.resource_name):
                mesh.set_surface_override_material(surface, far_materials[source.resource_name])
            elif source != null and materials.has(source.resource_name):
                mesh.set_surface_override_material(surface, materials[source.resource_name])


func _measure_view(camera: Camera3D) -> void:
    if camera == null:
        on_screen = visual.is_visible_in_tree()
        return
    var minimum := Vector2(INF, INF)
    var maximum := Vector2(-INF, -INF)
    var any_front := false
    on_screen = false
    # Fixed envelope avoids LOD oscillation as the flag/gear animate.
    for x: float in [-64.0, 64.0]:
        for y: float in [0.0, 104.0]:
            for z: float in [-48.0, 48.0]:
                var point: Vector3 = visual.to_global(Vector3(x, y, z))
                if camera.is_position_behind(point):
                    continue
                any_front = true
                var screen := camera.unproject_position(point)
                minimum = minimum.min(screen)
                maximum = maximum.max(screen)
    var viewport_size := camera.get_viewport().get_visible_rect().size
    if any_front:
        on_screen = Rect2(minimum, maximum - minimum).intersects(Rect2(Vector2.ZERO, viewport_size))
        projected_pixels = maxf(maximum.x - minimum.x, maximum.y - minimum.y) * 1080.0 / maxf(1.0, viewport_size.y)
    on_screen = on_screen and visual.is_visible_in_tree()


func _sync_far_materials() -> void:
    for material_name: String in far_materials:
        var far: StandardMaterial3D = far_materials[material_name]
        var near: StandardMaterial3D = materials[material_name]
        far.albedo_color = near.albedo_color
        far.emission_enabled = near.emission_enabled
        far.emission = near.emission
        far.emission_energy_multiplier = near.emission_energy_multiplier


func update(building: Dictionary, delta: float, camera: Camera3D) -> void:
    phase = fposmod(phase + delta, 60.0)
    if lod == 2:
        _sync_far_materials()
    var flight: Dictionary = building.get("flight", {})
    var flight_state: String = flight.get("state", "grounded")
    var transitioning := flight_state in ["taking_off", "landing"]
    view_elapsed += delta
    if view_elapsed >= 0.1:
        view_elapsed = 0.0
        _measure_view(camera)
        set_lod(choose_lod(projected_pixels, lod, transitioning))
    elif transitioning and lod == 2:
        set_lod(1)
    var shown: bool = on_screen and visual.is_visible_in_tree()
    effect_root.visible = shown and not visual.construction_tint
    var thrusting: bool = Simulation.BarracksFlight.is_thrusting(building)
    for jet: MeshInstance3D in rear_jets:
        jet.visible = shown and not visual.construction_tint and thrusting
        if jet.visible:
            jet.scale.y = 1.0 + 0.06 * sin(phase * 35.0)
    var wind: AnimationPlayer = visual.barracks_motion.wind
    wind.active = shown and lod < 2
    # Medium distance flags update at 10 Hz; near flags use normal interpolation.
    wind.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if lod > 0 else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
    if shown and lod == 1:
        flag_elapsed += delta
        if flag_elapsed >= 0.1:
            wind.advance(flag_elapsed)
            flag_elapsed = 0.0
    else:
        flag_elapsed = 0.0
    var queue: Array = building.get("queue", [])
    status = "ready" if queue.is_empty() else ("blocked" if int(queue[0].get("remaining", 1)) == 0 else "training")
    if int(building.get("remaining", 0)) > 0 or flight_state != "grounded":
        status = "inactive"
    var color := Color("62c9ed")
    var power := 0.3
    if status == "training":
        power = 0.6 + 0.5 * sin(phase * TAU * 0.75)
    elif status == "blocked":
        color = Color("ffad32")
        power = 1.7 if fposmod(phase, 0.32) < 0.16 else 0.08
    elif status == "inactive":
        power = 0.0
    lamp.albedo_color = color * maxf(0.1, power)
    lamp.emission = color
    lamp.emission_energy_multiplier = power
    if engine != null:
        engine.emission_enabled = true
        engine.emission_energy_multiplier = 2.0 if flight_state != "grounded" else 0.0
    var ratio := float(building.get("hp", 1)) / float(Simulation.BUILD_TYPES.barracks.hp)
    var damaged: bool = shown and not visual.construction_tint
    smoke.emitting = damaged and ratio < 0.5
    if damaged and ratio < 0.25:
        critical_elapsed = fposmod(critical_elapsed + delta, 2.4)
    else:
        critical_elapsed = 0.0
    sparks.emitting = damaged and ratio < 0.25 and lod < 2 and critical_elapsed < 0.45
    soot.visible = ratio < 0.25
    # Hiding the emitter also discards its visual contribution immediately.
    smoke.visible = smoke.emitting
    sparks.visible = sparks.emitting


func _create_effects() -> void:
    effect_root = Node3D.new()
    effect_root.name = "BarracksStatus"
    visual.add_child(effect_root)
    _create_rear_jets()
    if lamp == null:
        lamp = StandardMaterial3D.new()
    lamp.emission_enabled = true
    var lens := MeshInstance3D.new()
    var lens_mesh := BoxMesh.new()
    lens_mesh.size = Vector3(22, 1.8, 0.9)
    lens.mesh = lens_mesh
    lens.material_override = lamp
    lens.position = Vector3(12.36, 53.76, -31.5)
    lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    effect_root.add_child(lens)
    smoke = _particles(8, false)
    sparks = _particles(4, true)
    soot = MeshInstance3D.new()
    var patch := BoxMesh.new()
    patch.size = Vector3(12, 0.3, 10)
    soot.mesh = patch
    soot.position = Vector3(7, 66.7, -4)
    var charred := StandardMaterial3D.new()
    charred.albedo_color = Color("282722")
    charred.roughness = 1.0
    soot.material_override = charred
    soot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    soot.visible = false
    effect_root.add_child(soot)


func _create_rear_jets() -> void:
    var flame := StandardMaterial3D.new()
    flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    flame.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    flame.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
    flame.albedo_color = Color(0.15, 0.55, 1.0, 0.7)
    flame.emission_enabled = true
    flame.emission = Color(0.1, 0.5, 1.0)
    flame.emission_energy_multiplier = 1.5
    var mesh := CylinderMesh.new()
    mesh.top_radius = 0.15
    mesh.bottom_radius = 4.8
    mesh.height = 18.0
    mesh.radial_segments = 10
    mesh.rings = 1
    mesh.material = flame
    for side: float in [-1.0, 1.0]:
        var jet := MeshInstance3D.new()
        jet.name = "RearJetLeft" if side < 0 else "RearJetRight"
        jet.mesh = mesh
        # Nozzle exit at Blender (side * 2.7, -3.93, 2.65), scale 12.
        jet.position = Vector3(side * 32.4, 31.8, 47.16 + 9.0)
        jet.rotation.x = PI / 2.0
        jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        jet.visible = false
        effect_root.add_child(jet)
        rear_jets.append(jet)


func _particles(count: int, spark: bool) -> CPUParticles3D:
    var particles := CPUParticles3D.new()
    particles.amount = count
    particles.lifetime = 0.5 if spark else 2.5
    particles.emitting = false
    particles.position = Vector3(7, 68, -4)
    particles.direction = Vector3.UP
    particles.spread = 55.0 if spark else 18.0
    particles.gravity = Vector3(0, -15, 0) if spark else Vector3(1, 2, 0)
    particles.initial_velocity_min = 10.0 if spark else 6.0
    particles.initial_velocity_max = 18.0 if spark else 12.0
    particles.scale_amount_min = 0.4 if spark else 6.0
    particles.scale_amount_max = 0.8 if spark else 10.0
    var quad := QuadMesh.new()
    quad.size = Vector2.ONE if spark else Vector2(2, 2)
    var material := StandardMaterial3D.new()
    material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
    material.billboard_keep_scale = true
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.vertex_color_use_as_albedo = true
    var falloff := Gradient.new()
    falloff.set_color(0, Color.WHITE)
    falloff.set_color(1, Color(1, 1, 1, 0))
    var texture := GradientTexture2D.new()
    texture.gradient = falloff
    texture.width = 32
    texture.height = 32
    texture.fill = GradientTexture2D.FILL_RADIAL
    texture.fill_from = Vector2(0.5, 0.5)
    texture.fill_to = Vector2(1, 0.5)
    material.albedo_texture = texture
    material.albedo_color = Color("ffc55f") if spark else Color(0.12, 0.13, 0.15, 0.7)
    quad.material = material
    particles.mesh = quad
    var gradient := Gradient.new()
    gradient.set_color(0, Color(1, 1, 1, 0.8))
    gradient.set_color(1, Color(1, 1, 1, 0))
    particles.color_ramp = gradient
    particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    effect_root.add_child(particles)
    return particles
