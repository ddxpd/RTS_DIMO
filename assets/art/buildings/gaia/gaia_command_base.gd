class_name GaiaCommandBase
extends Node3D
## Standalone visual asset. No simulation fields, commands, or construction animation.

const MODEL_SCALE := Vector3(320.0 / 18.0, 16.0, 192.0 / 10.0)
const CLEARANCE := 12.0
const LIFT := 96.0
const TRANSITION_TIME := 6.0
const MODELS := [
    preload("res://assets/models/buildings/gaia/gaia_command_base.glb"),
    preload("res://assets/models/buildings/gaia/gaia_command_base_lod1.glb"),
    preload("res://assets/models/buildings/gaia/gaia_command_base_lod2.glb")
]

@export var automatic_animation := true
@export var radar_enabled := true
@export var team_color := Color("#63b4d8")
@export_range(-1, 2) var forced_lod := -1

var state := "deployed"
var state_time := 0.0
var clock := 0.0
var cruising := false
var current_lod := 0
var presentation: Node3D
var models: Array[Node3D] = []
var radar_yaws: Array[Node3D] = []
var radar_pitches: Array[Node3D] = []
var engine_material: StandardMaterial3D
var lights: Array[OmniLight3D] = []
var _thrust := 0.35
var materials: Dictionary = {}
var construction_tint := false
var flash_enabled := false


func _ready() -> void:
    presentation = Node3D.new()
    presentation.name = "PresentationRoot"
    add_child(presentation)
    var shared_materials: Dictionary = materials
    for index in range(MODELS.size()):
        var model: Node3D = MODELS[index].instantiate()
        model.name = "LOD%d" % index
        model.scale = MODEL_SCALE
        presentation.add_child(model)
        models.append(model)
        radar_yaws.append(model.find_children("RadarYaw*", "Node3D", true, false)[0])
        radar_pitches.append(model.find_children("RadarPitch*", "Node3D", true, false)[0])
        for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
            for surface in range(mesh.mesh.get_surface_count()):
                var source: StandardMaterial3D = mesh.mesh.surface_get_material(surface)
                if source == null:
                    continue
                if not shared_materials.has(source.resource_name):
                    var material: StandardMaterial3D = source.duplicate()
                    shared_materials[source.resource_name] = material
                    if source.resource_name == "GAIA_Team":
                        material.albedo_color = team_color.darkened(0.6)
                        material.emission = team_color
                        material.emission_energy_multiplier = 0.45
                    elif source.resource_name == "GAIA_Emission":
                        engine_material = material
                        material.emission_enabled = true
                        material.emission = Color("#409bd1")
                mesh.set_surface_override_material(surface, shared_materials[source.resource_name])
    for x in [-80.0, 80.0]:
        var lamp := OmniLight3D.new()
        lamp.name = "LiftBounceLight"
        lamp.position = Vector3(x * MODEL_SCALE.x / 16.0, 6, 0)
        lamp.light_color = Color("#5ba3da")
        lamp.omni_range = 65.0
        lamp.omni_attenuation = 2.0
        lamp.shadow_enabled = false
        presentation.add_child(lamp)
        lights.append(lamp)
    apply_pose()


func set_team_color(color: Color) -> void:
    team_color = color
    refresh_tint()


func set_visual_tint(constructing: bool, flashing: bool) -> void:
    construction_tint = constructing
    flash_enabled = flashing
    refresh_tint()


func refresh_tint() -> void:
    var tint := 1.9 if flash_enabled else (0.62 if construction_tint else 1.0)
    for key: String in materials:
        var material: StandardMaterial3D = materials[key]
        if not material.has_meta("original_color"):
            material.set_meta("original_color", material.albedo_color)
        var color: Color = material.get_meta("original_color")
        if key == "GAIA_Team":
            color = team_color.darkened(0.6)
            material.emission = team_color
            material.emission_energy_multiplier = 0.45 * (0.62 if construction_tint else 1.0)
        material.albedo_color = color * tint


func take_off() -> void:
    if state == "deployed":
        state = "taking_off"
        state_time = 0.0


func land() -> void:
    if state == "airborne":
        state = "landing"
        state_time = 0.0
        cruising = false


func set_cruising(enabled: bool) -> void:
    cruising = enabled and state == "airborne"


func seek_pose(next_state: String, seconds: float, cruise: bool = false) -> void:
    assert(next_state in ["deployed", "taking_off", "airborne", "landing"])
    state = next_state
    state_time = maxf(seconds, 0.0)
    clock = state_time
    cruising = cruise and state == "airborne"
    apply_pose()


func _process(delta: float) -> void:
    if not is_visible_in_tree():
        return
    if automatic_animation:
        advance(delta)
    else:
        update_lod()


func advance(delta: float) -> void:
    clock += maxf(delta, 0.0)
    state_time += maxf(delta, 0.0)
    if state in ["taking_off", "landing"] and state_time >= TRANSITION_TIME:
        state = "airborne" if state == "taking_off" else "deployed"
        state_time = 0.0
    apply_pose(delta)


func apply_pose(delta: float = 0.0) -> void:
    if presentation == null:
        return
    var progress := clampf(state_time / TRANSITION_TIME, 0.0, 1.0)
    var blend := smoothstep(0.0, 1.0, progress)
    var altitude := 0.0
    var thrust := 0.35
    match state:
        "taking_off":
            altitude = LIFT * blend
            thrust = 0.35 + 0.20 * blend + 0.35 * sin(progress * PI)
        "airborne":
            altitude = LIFT
            thrust = 0.8 if cruising else 0.55
        "landing":
            altitude = LIFT * (1.0 - blend)
            thrust = 0.55 - 0.20 * blend + 0.20 * sin(progress * PI)
    presentation.position.y = CLEARANCE + altitude + 0.5 * sin(clock * TAU / 6.0)
    # Blend the cruise attitude so stopping cannot snap a broad rigid platform.
    var target_pitch := deg_to_rad(-2.0) if cruising else 0.0
    var response := 1.0 if delta <= 0.0 else 1.0 - exp(-delta * 5.0)
    presentation.rotation.x = lerpf(presentation.rotation.x, target_pitch, response)
    _thrust = lerpf(_thrust, thrust, response)
    for index in range(models.size()):
        if radar_enabled:
            radar_yaws[index].rotation.y = fposmod(clock * TAU / 24.0, TAU)
            radar_pitches[index].rotation.x = deg_to_rad(-8.0 + 4.0 * sin(clock * TAU / 12.0))
    if engine_material != null:
        engine_material.emission_energy_multiplier = lerpf(1.1, 3.0, _thrust)
    for lamp in lights:
        lamp.light_energy = _thrust * 0.45
    update_lod()


func update_lod() -> void:
    var level := forced_lod
    if level < 0:
        var camera := get_viewport().get_camera_3d()
        var distance := camera.global_position.distance_to(presentation.global_position) if camera else 0.0
        # Hysteresis avoids flickering between levels while the camera is stationary.
        level = current_lod
        if level == 0 and distance > 950:
            level = 1
        elif level == 1 and distance < 850:
            level = 0
        elif level == 1 and distance > 1850:
            level = 2
        elif level == 2 and distance < 1750:
            level = 1
    current_lod = clampi(level, 0, 2)
    for index in range(models.size()):
        models[index].visible = index == current_lod
    for lamp in lights:
        lamp.visible = current_lod == 0
