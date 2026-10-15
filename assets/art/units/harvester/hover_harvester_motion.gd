extends RefCounted
const Rules = preload("res://scripts/definitions/gameplay_rules.gd")
## Presentation only: simulation remains a ground unit with the existing capacity/rules.

var visual: Node3D
var body: Node3D
var arms: Array[Node3D] = []
var extensions: Array[Node3D] = []
var claws: Array[Node3D] = []
var fans: Array[Node3D] = []
var cargo_layers: Array[Node3D] = []
var clock := 0.0
var cargo_stage := -1
var extension := 0.16
static var mineral_material: ShaderMaterial
var _pose_key: Array = []
var _ground_key: Array = []
var _ground_pitch := 0.0
var _ground_roll := 0.0


func _init(owner_visual: Node3D) -> void:
    visual = owner_visual
    body = visual.model.find_child("HoverBody", true, false)
    for side: String in ["L", "R"]:
        arms.append(visual.model.find_child("Arm_" + side, true, false))
        extensions.append(visual.model.find_child("ArmExtension_" + side, true, false))
        fans.append(visual.model.find_child("Fan_" + side, true, false))
        for jaw: String in ["A", "B"]:
            claws.append(visual.model.find_child("Claw_" + side + "_" + jaw, true, false))
    for name: String in ["CargoLow", "CargoMid", "CargoHigh"]:
        cargo_layers.append(visual.model.find_child(name, true, false))
    for entry: Dictionary in visual._materials:
        var material: StandardMaterial3D = entry.material
        if material.resource_name == "HH_ThrusterBlue":
            material.emission_enabled = true
            material.emission = Color(0.015, 0.5, 1.0)
            material.emission_energy_multiplier = 2.6
    if mineral_material == null:
        mineral_material = ShaderMaterial.new()
        mineral_material.shader = preload("res://assets/art/units/harvester/harvester_cargo.gdshader")
        mineral_material.set_shader_parameter("mineral_color", preload("res://assets/models/environment/ore/ore_crystal_basecolor.png"))
        mineral_material.set_shader_parameter("mineral_detail", preload("res://assets/models/environment/ore/ore_crystal_detail.png"))
    for layer: Node3D in cargo_layers:
        for mesh: MeshInstance3D in layer.find_children("*", "MeshInstance3D", true, false):
            mesh.material_override = mineral_material
    set_cargo(0)
    sample({"cargo": 0, "work": 0}, 0.0, null)


static func stage_for(cargo: int, capacity: int = Rules.CAPACITY) -> int:
    if cargo <= 0:
        return 0
    if cargo < capacity / 3.0:
        return 1
    return 2 if cargo < capacity * 2.0 / 3.0 else 3


func set_cargo(amount: int) -> void:
    var next := stage_for(amount)
    if next == cargo_stage:
        return
    cargo_stage = next
    for i in range(cargo_layers.size()):
        cargo_layers[i].visible = i < cargo_stage


func sample(unit: Dictionary, delta: float, terrain) -> void:
    set_cargo(int(unit.get("cargo", 0)))
    if not visual.visible:
        return
    var terrain_key: String = terrain.checksum if terrain != null else ""
    var pose_key := [visual.global_transform, visual._target_heading, visual.animation_state, int(unit.get("work", 0)), terrain_key]
    # Repeated zero-time synchronization must not solve an unchanged pose again.
    if delta <= 0.0 and pose_key == _pose_key:
        return
    _pose_key = pose_key
    clock += clampf(delta, 0.0, 0.1)
    var moving: bool = visual.animation_state == "move"
    var mining: bool = visual.animation_state == "mine"
    var phase := float(unit.get("work", 0)) / Rules.MINING_INTERVAL * TAU
    var response := 1.0 if delta <= 0.0 else 1.0 - exp(-delta * 10.0)
    var target_extension := 0.53 + 0.08 * sin(phase) if mining else 0.16
    extension = lerpf(extension, target_extension, response)
    for i in range(2):
        extensions[i].position.z = -extension
        arms[i].rotation.x = 0.06 + 0.05 * sin(phase + i * 0.7) if mining else 0.12
        fans[i].rotation.y = fposmod(clock * (16.0 if moving else 8.0), TAU)
        var opening := (0.17 + 0.22 * (0.5 + 0.5 * cos(phase + i * 0.7))) if mining else 0.06
        claws[i * 2].rotation.y = opening
        claws[i * 2 + 1].rotation.y = -opening
    var pitch := -0.035 if moving else 0.0
    var roll: float = clampf(angle_difference(visual.rotation.y, visual._target_heading) * -0.10, -0.06, 0.06) if moving else 0.0
    if terrain != null:
        var ground_key := [visual.global_transform, terrain_key]
        if ground_key != _ground_key:
            _ground_key = ground_key
            var span: float = 1.7 * visual._model_scale
            var front: float = _height_at(terrain, 0, -span)
            var rear: float = _height_at(terrain, 0, span)
            var left: float = _height_at(terrain, -span, 0)
            var right: float = _height_at(terrain, span, 0)
            _ground_pitch = clampf(atan2(front - rear, span * 2.0), -0.24, 0.24)
            _ground_roll = clampf(atan2(right - left, span * 2.0), -0.24, 0.24)
        pitch += _ground_pitch
        roll += _ground_roll
    body.rotation.x = lerp_angle(body.rotation.x, pitch, response)
    body.rotation.z = lerp_angle(body.rotation.z, roll, response)
    var lift := 0.10
    if terrain != null:
        for probe: Vector3 in [Vector3(-1.15, 0.43, 0.03), Vector3(1.15, 0.43, 0.03), Vector3(0, 0.39, 1.1), Vector3(0, 0.45, -1.1)]:
            var rotated: Vector3 = body.basis * probe * visual._model_scale
            var ground := _height_at(terrain, rotated.x, rotated.z)
            var clearance: float = 0.17 * visual._model_scale
            lift = maxf(lift, (ground - visual.position.y + clearance - rotated.y) / visual._model_scale)
    body.position.y = lift + 0.018 * (1.0 + sin(clock * 2.3))


func _height_at(terrain, x: float, z: float) -> float:
    var world: Vector3 = visual.global_transform * Vector3(x, 0, z)
    return terrain.height_at(Vector2(world.x, world.z))
