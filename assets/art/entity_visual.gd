class_name EntityVisual
extends Node3D

const MODEL_SCENES := {
    "soldier": preload("res://assets/models/soldier.glb"),
    "harvester": preload("res://assets/models/harvester.glb"),
    "base": preload("res://assets/models/base.glb"),
    "barracks": preload("res://assets/models/barracks.glb"),
    "refinery": preload("res://assets/models/refinery.glb"),
    "bunker": preload("res://assets/models/bunker.glb"),
    "ore": preload("res://assets/models/ore.glb"),
    "rock": preload("res://assets/models/rock.glb")
}

const MODEL_SETTINGS := {
    "soldier": {"scale": 24.0, "height": 68.0},
    "harvester": {"scale": 19.0, "height": 44.0},
    "base": {"scale": 21.0, "height": 88.0},
    "barracks": {"scale": 19.0, "height": 48.0},
    "refinery": {"scale": 18.0, "height": 70.0},
    "bunker": {"scale": 23.0, "height": 62.0},
    "ore": {"scale": 45.0, "height": 40.0},
    "rock": {"scale": 26.0, "height": 28.0}
}

const TEAM_COLORS := {
    1: Color("#5fa5e0"),
    2: Color("#d66551")
}

var kind := ""
var owner_id := 1
var model: Node3D
var animation_player: AnimationPlayer
var animation_state := ""
var flash_enabled := false
var construction_tint := false
var _target_heading := 0.0
var _model_scale := 1.0
var _materials: Array[Dictionary] = []
var _faction_applied := false

static var _shared_animation_libraries: Dictionary = {}


func _init(model_kind: String, model_owner: int = 1) -> void:
    kind = model_kind
    owner_id = model_owner


func _ready() -> void:
    var settings: Dictionary = MODEL_SETTINGS.get(kind, {"scale": 20.0, "height": 40.0})
    _model_scale = float(settings.scale)
    model = MODEL_SCENES[kind].instantiate()
    add_child(model)
    model.scale = Vector3.ONE * _model_scale
    _instance_materials()
    _apply_lod_and_shadow_policy()
    _create_animation_player()
    set_faction(owner_id)
    set_animation("idle")


func _process(delta: float) -> void:
    if absf(angle_difference(rotation.y, _target_heading)) < 0.001:
        return
    rotation.y = lerp_angle(rotation.y, _target_heading, minf(delta * 10.0, 1.0))


func set_position_2d(position_2d: Vector2) -> void:
    position = Vector3(position_2d.x, 0, position_2d.y)


func set_heading(heading: Vector2) -> void:
    if heading.length_squared() < 0.01:
        return
    var forward_z := _forward_z()
    _target_heading = atan2(heading.x * forward_z, heading.y * forward_z)


func get_visual_forward() -> Vector3:
    return (global_transform.basis.z * _forward_z()).normalized()


func _forward_z() -> float:
    # The soldier body is authored facing local +Z. The harvester drill is
    # authored facing local -Z, so facing must be resolved per model kind.
    return 1.0 if kind == "soldier" else -1.0


func set_animation(next_state: String) -> void:
    if animation_state == next_state:
        return
    # Construction scales the model inner root. Reset it when leaving that
    # state so a stopped loop cannot leave a completed building double-scaled.
    if animation_state == "construction":
        var animated_root := model.get_node_or_null(NodePath(kind))
        if animated_root != null:
            animated_root.scale = Vector3.ONE
    animation_state = next_state
    if animation_player == null or not animation_player.has_animation(next_state):
        return
    animation_player.speed_scale = 1.0
    animation_player.play(next_state)


func set_flash(enabled: bool) -> void:
    if flash_enabled == enabled:
        return
    flash_enabled = enabled
    _refresh_material_tint()


func set_construction_tint(enabled: bool) -> void:
    if construction_tint == enabled:
        return
    construction_tint = enabled
    _refresh_material_tint()


func set_construction_progress(progress: float, duration: float) -> void:
    if animation_player == null or not animation_player.has_animation("construction"):
        return
    var next_progress := clampf(progress, 0.0, 1.0)
    var next_duration := maxf(duration, 0.001)
    var animation := animation_player.get_animation("construction")
    # The construction clip is normalized to one second. Slowing it by the
    # actual build duration makes one pass match the complete construction time.
    animation_player.speed_scale = 1.0 / next_duration
    if animation_player.assigned_animation != &"construction":
        animation_player.play("construction")
    animation_player.seek(animation.length * next_progress, true)


func set_faction(next_owner: int) -> void:
    if _faction_applied and owner_id == next_owner:
        return
    owner_id = next_owner
    _faction_applied = true
    var team: Color = TEAM_COLORS.get(owner_id, Color("#8d8d8d"))
    for entry: Dictionary in _materials:
        if not bool(entry.faction):
            continue
        var material: StandardMaterial3D = entry.material
        material.albedo_color = team if "Paint" in material.resource_name else team.lightened(0.35)
        material.emission_enabled = true
        material.emission = team.lightened(0.25)
        material.emission_energy_multiplier = 1.25 if "Glow" in material.resource_name else 0.12
        entry.base_color = material.albedo_color
    _refresh_material_tint()


func get_model_height() -> float:
    return float(MODEL_SETTINGS.get(kind, {"height": 40.0}).height)


func get_animation_names() -> Array[StringName]:
    var names: Array[StringName] = []
    if animation_player != null:
        names.append_array(animation_player.get_animation_list())
    return names


func _instance_materials() -> void:
    var meshes := model.find_children("*", "MeshInstance3D", true, false)
    for mesh_instance: MeshInstance3D in meshes:
        if mesh_instance.mesh == null:
            continue
        for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
            var source: Material = mesh_instance.mesh.surface_get_material(surface_index)
            if source == null or not source is StandardMaterial3D:
                continue
            var material := (source as StandardMaterial3D).duplicate()
            mesh_instance.set_surface_override_material(surface_index, material)
            _materials.append({
                "material": material,
                "base_color": material.albedo_color,
                "faction": "Faction" in material.resource_name
            })


func _apply_lod_and_shadow_policy() -> void:
    # Units contribute far more instances than buildings, so omit their shadow
    # passes and fade small mechanical details at strategic zoom distances.
    var unit_core: Dictionary = {}
    if kind == "soldier":
        unit_core = {"Body": true, "soldier_Static_Armor_FactionPaint": true, "Weapon": true}
    elif kind == "harvester":
        unit_core = {"Hull": true, "harvester_Static_Armor": true, "harvester_Static_Steel": true}

    var is_unit := kind == "soldier" or kind == "harvester"
    for mesh_instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
        if is_unit:
            mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            if not unit_core.has(mesh_instance.name):
                mesh_instance.visibility_range_end = 1400.0
        elif mesh_instance.name in ["FactionGlow", "FactionSensor", "FactionBeacon", "FactionLight"]:
            mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _refresh_material_tint() -> void:
    var tint := 1.0
    if construction_tint:
        tint = 0.62
    if flash_enabled:
        tint = maxf(tint, 1.9)
    for entry: Dictionary in _materials:
        var material: StandardMaterial3D = entry.material
        material.albedo_color = (entry.base_color as Color) * tint


func _create_animation_player() -> void:
    animation_player = AnimationPlayer.new()
    animation_player.name = "StateAnimationPlayer"
    add_child(animation_player)
    animation_player.root_node = animation_player.get_path_to(model)
    if not _shared_animation_libraries.has(kind):
        _shared_animation_libraries[kind] = _build_animation_library()
    animation_player.add_animation_library("", _shared_animation_libraries[kind])
    animation_player.active = kind != "rock"


func _build_animation_library() -> AnimationLibrary:
    var library := AnimationLibrary.new()
    match kind:
        "soldier":
            library.add_animation("idle", _soldier_idle())
            library.add_animation("move", _soldier_move())
            library.add_animation("attack", _soldier_attack())
        "harvester":
            library.add_animation("idle", _harvester_idle())
            library.add_animation("move", _harvester_move())
            library.add_animation("mine", _harvester_mine())
            library.add_animation("unload", _harvester_unload())
        "base":
            library.add_animation("idle", _base_idle())
            library.add_animation("construction", _construction_animation())
        "barracks":
            library.add_animation("idle", _barracks_idle())
            library.add_animation("active", _barracks_active())
            library.add_animation("construction", _construction_animation())
        "refinery":
            library.add_animation("idle", _refinery_idle())
            library.add_animation("active", _refinery_active())
            library.add_animation("construction", _construction_animation())
        "bunker":
            library.add_animation("idle", _bunker_idle())
            library.add_animation("fire", _bunker_fire())
            library.add_animation("construction", _construction_animation())
        "ore":
            library.add_animation("idle", _ore_idle())
    return library

func _make_animation(length: float, looping: bool = true) -> Animation:
    var animation := Animation.new()
    animation.length = length
    animation.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
    return animation


func _add_value_track(animation: Animation, node_name: String, property: String, values: Array) -> void:
    var node := model.get_node_or_null(NodePath(node_name))
    if node == null or values.size() < 2:
        return
    var track := animation.add_track(Animation.TYPE_VALUE)
    animation.track_set_path(track, "%s:%s" % [node_name, property])
    animation.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS)
    for index: int in range(values.size()):
        var time := animation.length * index / float(values.size() - 1)
        animation.track_insert_key(track, time, values[index])


func _soldier_idle() -> Animation:
    var animation := _make_animation(2.4)
    _add_value_track(animation, "soldier/Body", "position", [Vector3(0, 1.63, 0), Vector3(0, 1.648, 0), Vector3(0, 1.63, 0)])
    _add_value_track(animation, "soldier/Head", "rotation", [Vector3.ZERO, Vector3(0, 0.12, 0), Vector3.ZERO])
    return animation


func _soldier_move() -> Animation:
    var animation := _make_animation(0.8)
    _add_value_track(animation, "soldier/Leg_L", "rotation", [Vector3(0.42, 0, 0), Vector3(-0.42, 0, 0), Vector3(0.42, 0, 0)])
    _add_value_track(animation, "soldier/Leg_R", "rotation", [Vector3(-0.42, 0, 0), Vector3(0.42, 0, 0), Vector3(-0.42, 0, 0)])
    _add_value_track(animation, "soldier/Arm_L", "rotation", [Vector3(-0.30, 0, 0), Vector3(0.30, 0, 0), Vector3(-0.30, 0, 0)])
    _add_value_track(animation, "soldier/Arm_R", "rotation", [Vector3(0.30, 0, 0), Vector3(-0.30, 0, 0), Vector3(0.30, 0, 0)])
    _add_value_track(animation, "soldier/Hips", "position", [Vector3(0, 1.10, 0), Vector3(0, 1.15, 0), Vector3(0, 1.10, 0)])
    return animation


func _soldier_attack() -> Animation:
    var animation := _make_animation(0.45)
    # The visible soldier front and corrected weapon both use local +Z.
    _add_value_track(animation, "soldier/Weapon", "position", [Vector3(0.70, 1.51, 0.52), Vector3(0.70, 1.51, 0.35), Vector3(0.70, 1.51, 0.52)])
    _add_value_track(animation, "soldier/Muzzle", "position", [Vector3(0.70, 1.51, 0.98), Vector3(0.70, 1.51, 0.86), Vector3(0.70, 1.51, 0.98)])
    _add_value_track(animation, "soldier/Arm_R", "rotation", [Vector3(-0.16, 0, 0), Vector3(0.10, 0, 0), Vector3(-0.16, 0, 0)])
    return animation


func _harvester_idle() -> Animation:
    var animation := _make_animation(2.0)
    _add_value_track(animation, "harvester/Drill", "rotation", [Vector3(1.507, 0, 0), Vector3(1.507, 0, 0.3), Vector3(1.507, 0, 0)])
    _add_value_track(animation, "harvester/FactionBeacon", "scale", [Vector3.ONE, Vector3(1.16, 1.16, 1.16), Vector3.ONE])
    return animation


func _harvester_move() -> Animation:
    var animation := _make_animation(0.45)
    for wheel_name: String in ["LeftWheel_0", "LeftWheel_1", "LeftWheel_2", "LeftWheel_3", "LeftWheel_4", "RightWheel_0", "RightWheel_1", "RightWheel_2", "RightWheel_3", "RightWheel_4"]:
        _add_value_track(animation, "harvester/" + wheel_name, "rotation", [Vector3(0, 1.5708, 0), Vector3(0, 1.5708, TAU), Vector3(0, 1.5708, TAU * 2.0)])
    _add_value_track(animation, "harvester/Hull", "position", [Vector3(0, 0.83, 0.04), Vector3(0, 0.85, 0.04), Vector3(0, 0.83, 0.04)])
    return animation


func _harvester_mine() -> Animation:
    var animation := _make_animation(0.22)
    _add_value_track(animation, "harvester/Drill", "rotation", [Vector3(1.507, 0, 0), Vector3(1.507, 0, TAU), Vector3(1.507, 0, TAU * 2.0)])
    _add_value_track(animation, "harvester/DrillShaft", "rotation", [Vector3(1.5708, 0, 0), Vector3(1.5708, 0, TAU), Vector3(1.5708, 0, TAU * 2.0)])
    _add_value_track(animation, "harvester/Chassis", "position", [Vector3(0, 0.54, 0), Vector3(0, 0.555, 0), Vector3(0, 0.54, 0)])
    return animation


func _harvester_unload() -> Animation:
    var animation := _make_animation(0.75)
    _add_value_track(animation, "harvester/CargoGate", "position", [Vector3(0, 0.96, -0.82), Vector3(0, 0.82, -0.82), Vector3(0, 0.96, -0.82)])
    _add_value_track(animation, "harvester/CargoHopper", "rotation", [Vector3.ZERO, Vector3(0.08, 0, 0), Vector3.ZERO])
    _add_value_track(animation, "harvester/FactionBeacon", "scale", [Vector3.ONE, Vector3(1.35, 1.35, 1.35), Vector3.ONE])
    return animation


func _base_idle() -> Animation:
    var animation := _make_animation(4.0)
    _add_value_track(animation, "base/RadarDish", "rotation", [Vector3(0, 0, 0.15), Vector3(0, TAU * 0.5, 0.15), Vector3(0, TAU, 0.15)])
    _add_value_track(animation, "base/Hologram", "scale", [Vector3.ONE, Vector3(1.08, 1.18, 1.08), Vector3.ONE])
    return animation


func _barracks_idle() -> Animation:
    var animation := _make_animation(3.0)
    _add_value_track(animation, "barracks/RoofFan", "rotation", [Vector3.ZERO, Vector3(0, TAU, 0), Vector3(0, TAU * 2.0, 0)])
    return animation


func _barracks_active() -> Animation:
    var animation := _make_animation(1.2)
    _add_value_track(animation, "barracks/RoofFan", "rotation", [Vector3.ZERO, Vector3(0, TAU * 2.0, 0), Vector3(0, TAU * 4.0, 0)])
    _add_value_track(animation, "barracks/AssemblyDoor", "position", [Vector3(1.46, 0.72, 0), Vector3(1.18, 0.72, 0), Vector3(1.46, 0.72, 0)])
    _add_value_track(animation, "barracks/FactionLight", "scale", [Vector3.ONE, Vector3(1.4, 1.4, 1.4), Vector3.ONE])
    return animation


func _refinery_idle() -> Animation:
    var animation := _make_animation(2.5)
    _add_value_track(animation, "refinery/Pump", "position", [Vector3(0.85, 0.58, 0.85), Vector3(0.85, 0.66, 0.85), Vector3(0.85, 0.58, 0.85)])
    _add_value_track(animation, "refinery/Flare", "scale", [Vector3.ONE, Vector3(1.15, 0.9, 1.15), Vector3.ONE])
    return animation


func _refinery_active() -> Animation:
    var animation := _make_animation(0.5)
    _add_value_track(animation, "refinery/Pump", "position", [Vector3(0.85, 0.58, 0.85), Vector3(0.85, 0.74, 0.85), Vector3(0.85, 0.58, 0.85)])
    _add_value_track(animation, "refinery/Motor", "rotation", [Vector3.ZERO, Vector3(0, TAU, 0), Vector3(0, TAU * 2.0, 0)])
    _add_value_track(animation, "refinery/Flare", "scale", [Vector3.ONE, Vector3(1.35, 1.1, 1.35), Vector3.ONE])
    return animation


func _bunker_idle() -> Animation:
    var animation := _make_animation(3.6)
    _add_value_track(animation, "bunker/Turret", "rotation", [Vector3(0, PI - 0.10, 0), Vector3(0, PI + 0.10, 0), Vector3(0, PI - 0.10, 0)])
    _add_value_track(animation, "bunker/SensorMast", "rotation", [Vector3(0, -0.04, 0), Vector3(0, 0.04, 0), Vector3(0, -0.04, 0)])
    _add_value_track(animation, "bunker/FactionSensor", "scale", [Vector3.ONE, Vector3(1.18, 1.30, 1.18), Vector3.ONE])
    return animation


func _bunker_fire() -> Animation:
    var animation := _make_animation(0.5)
    _add_value_track(animation, "bunker/Turret/Barrel_L", "position", [Vector3(-0.22, 0.25, 0.60), Vector3(-0.22, 0.25, 0.48), Vector3(-0.22, 0.25, 0.60)])
    _add_value_track(animation, "bunker/Turret/Barrel_R", "position", [Vector3(0.22, 0.25, 0.60), Vector3(0.22, 0.25, 0.48), Vector3(0.22, 0.25, 0.60)])
    _add_value_track(animation, "bunker/Turret", "rotation", [Vector3(0, PI + 0.06, 0), Vector3(0, PI - 0.10, 0), Vector3(0, PI + 0.06, 0)])
    _add_value_track(animation, "bunker/Turret/MuzzleFlash", "scale", [Vector3(0.04, 0.04, 0.04), Vector3(1.40, 0.75, 1.40), Vector3(0.04, 0.04, 0.04)])
    _add_value_track(animation, "bunker/FactionSensor", "scale", [Vector3.ONE, Vector3(1.55, 1.55, 1.55), Vector3.ONE])
    return animation


func _ore_idle() -> Animation:
    var animation := _make_animation(1.6)
    _add_value_track(animation, "ore/OreCrystal_0", "scale", [Vector3.ONE, Vector3(1.08, 0.94, 1.08), Vector3.ONE])
    _add_value_track(animation, "ore/OreCrystal_1", "scale", [Vector3.ONE, Vector3(0.95, 1.08, 0.95), Vector3.ONE])
    return animation


func _construction_animation() -> Animation:
    # Keep this clip normalized. `set_construction_progress()` maps it to the
    # building's actual build time and seeks to the current construction ratio.
    var animation := _make_animation(1.0, false)
    var low := Vector3(1, 0.2, 1)
    _add_value_track(animation, kind, "scale", [low, Vector3.ONE])
    if kind == "bunker":
        _add_value_track(animation, "bunker/BlastShutter_L", "scale", [Vector3(0.15, 0.15, 0.15), Vector3.ONE])
        _add_value_track(animation, "bunker/BlastShutter_R", "scale", [Vector3(0.15, 0.15, 0.15), Vector3.ONE])
        _add_value_track(animation, "bunker/Stabilizer_L", "scale", [Vector3(0.10, 0.10, 0.10), Vector3.ONE])
        _add_value_track(animation, "bunker/Stabilizer_R", "scale", [Vector3(0.10, 0.10, 0.10), Vector3.ONE])
        _add_value_track(animation, "bunker/SensorMast", "scale", [Vector3(0.12, 0.12, 0.12), Vector3.ONE])
        _add_value_track(animation, "bunker/FactionSensor", "scale", [Vector3(0.05, 0.05, 0.05), Vector3.ONE])
    return animation
