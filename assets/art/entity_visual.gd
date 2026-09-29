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
    "base": {"scale": 32.0, "height": 108.0},
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
const SELECTION_GREEN := Color("#65ff78")

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
var _soldier_animation_defaults: Dictionary = {}
var _bunker_construction_defaults: Dictionary = {}
var _base_construction_defaults: Dictionary = {}
var _base_light_materials: Array[Dictionary] = []
# Animation tracks target these properties on this instance, not shared resources.
var base_scan_phase := 0.0:
    set(value):
        base_scan_phase = value
        _refresh_base_lights()
var base_windows_power := 1.0:
    set(value):
        base_windows_power = value
        _refresh_base_lights()
var selection_ring: MeshInstance3D
var _selection_ring_material: StandardMaterial3D
var _selection_ring_enabled := false
var _selection_ring_radius := 1.0

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
    _capture_soldier_animation_defaults()
    _capture_bunker_construction_defaults()
    _capture_base_construction_defaults()
    _instance_materials()
    _apply_lod_and_shadow_policy()
    _create_animation_player()
    set_faction(owner_id)
    set_animation("idle")
    _apply_selection_ring_state()


func _process(delta: float) -> void:
    if absf(angle_difference(rotation.y, _target_heading)) >= 0.001:
        rotation.y = lerp_angle(rotation.y, _target_heading, minf(delta * 10.0, 1.0))


func set_position_2d(position_2d: Vector2, ground_height: float = 0.0) -> void:
    position = Vector3(position_2d.x, ground_height, position_2d.y)


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
    if kind == "soldier" and not animation_state.is_empty():
        _reset_soldier_animation_state()
    # Construction scales the model inner root. Reset it when leaving that
    # state so a stopped loop cannot leave a completed building double-scaled.
    if animation_state == "construction":
        var animated_root := model.get_node_or_null(NodePath(kind))
        if animated_root != null:
            animated_root.scale = Vector3.ONE
        if kind == "bunker":
            _reset_bunker_construction_state()
        elif kind == "base":
            for node_path: String in _base_construction_defaults:
                model.get_node(node_path).position = _base_construction_defaults[node_path]
            base_windows_power = 1.0
            base_scan_phase = 0.0
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


func set_selected(enabled: bool, radius: float = 1.0) -> void:
    _selection_ring_enabled = enabled
    _selection_ring_radius = maxf(radius, 1.0)
    if enabled and selection_ring == null:
        _create_selection_ring()
    _apply_selection_ring_state()


func _apply_selection_ring_state() -> void:
    if selection_ring == null:
        return
    selection_ring.visible = _selection_ring_enabled
    selection_ring.scale = Vector3.ONE * _selection_ring_radius


func _create_selection_ring() -> void:
    selection_ring = MeshInstance3D.new()
    selection_ring.name = "SelectionRing"
    var torus := TorusMesh.new()
    torus.inner_radius = 0.88
    torus.outer_radius = 1.0
    torus.rings = 32
    torus.ring_segments = 8
    selection_ring.mesh = torus
    selection_ring.position.y = 0.42
    selection_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _selection_ring_material = StandardMaterial3D.new()
    _selection_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _selection_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    _selection_ring_material.albedo_color = Color(SELECTION_GREEN, 0.9)
    _selection_ring_material.emission_enabled = true
    _selection_ring_material.emission = SELECTION_GREEN
    _selection_ring_material.emission_energy_multiplier = 1.8
    selection_ring.material_override = _selection_ring_material
    selection_ring.visible = false
    add_child(selection_ring)


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
        if kind == "base":
            # Saturated emission stays visibly blue/red under Compatibility rendering.
            material.albedo_color = team
            material.emission = team * team * team
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
            var entry := {
                "material": material,
                "base_color": material.albedo_color,
                "faction": "Faction" in material.resource_name
            }
            _materials.append(entry)
            if kind == "base" and "Base_Faction" in material.resource_name:
                entry["tower_index"] = int(material.resource_name.get_slice("_", 2)) if "TowerGlow" in material.resource_name else -1
                _base_light_materials.append(entry)


func _apply_lod_and_shadow_policy() -> void:
    # Units contribute far more instances than buildings, so omit their shadow
    # passes and fade small mechanical details at strategic zoom distances.
    var unit_core: Dictionary = {}
    if kind == "soldier":
        unit_core = {
            "ArmorCoreMesh": true,
            "HelmetMesh": true,
            "Shoulder_L_Mesh": true,
            "Shoulder_R_Mesh": true,
            "Arm_L_Mesh": true,
            "Arm_R_Mesh": true,
            "HipsMesh": true,
            "Leg_L_Mesh": true,
            "Leg_R_Mesh": true,
            "WeaponMesh": true
        }
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
    _refresh_base_lights()


func _refresh_base_lights() -> void:
    for entry: Dictionary in _base_light_materials:
        var index: int = entry.tower_index
        var energy := clampf(base_windows_power, 0.0, 1.0)
        if index >= 0:
            var local_time := fposmod(base_scan_phase, 2.4) - float(index) * 0.32
            energy = 0.0
            if base_windows_power > 0.0 and local_time >= 0.0 and local_time < 0.28:
                energy = minf(clampf(local_time / 0.04, 0.0, 1.0), clampf((0.28 - local_time) / 0.06, 0.0, 1.0))
        var material: StandardMaterial3D = entry.material
        var tint := 1.9 if flash_enabled else (0.62 if construction_tint else 1.0)
        material.albedo_color = (entry.base_color as Color) * lerpf(0.035, 0.55 if index < 0 else 0.25, energy) * tint
        material.emission_energy_multiplier = energy * (0.65 if index < 0 else 2.5)


func _capture_base_construction_defaults() -> void:
    if kind != "base":
        return
    for node_name: String in ["BaseFoundation", "BaseRing_0", "BaseRing_1", "BaseRing_2", "BaseRing_3", "BaseTower", "BaseCrown"]:
        var node_path := "base/" + node_name
        var node := model.get_node(node_path) as Node3D
        _base_construction_defaults[node_path] = node.position


func _base_property_track(animation: Animation, property: String, keys: Array) -> void:
    var track := animation.add_track(Animation.TYPE_VALUE)
    animation.track_set_path(track, "..:" + property)
    animation.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS)
    for key: Array in keys:
        animation.track_insert_key(track, float(key[0]), key[1])


func _create_animation_player() -> void:
    animation_player = AnimationPlayer.new()
    animation_player.name = "StateAnimationPlayer"
    add_child(animation_player)
    animation_player.root_node = animation_player.get_path_to(model)
    if not _shared_animation_libraries.has(kind):
        _shared_animation_libraries[kind] = _build_animation_library()
    animation_player.add_animation_library("", _shared_animation_libraries[kind])
    animation_player.active = kind != "rock"


func _capture_soldier_animation_defaults() -> void:
    if kind != "soldier":
        return
    for node_name: String in [
        "soldier/ArmorCore",
        "soldier/Helmet",
        "soldier/Arm_L",
        "soldier/Arm_R",
        "soldier/Hips",
        "soldier/Leg_L",
        "soldier/Leg_R",
        "soldier/Weapon",
        "soldier/Muzzle"
    ]:
        var node := model.get_node_or_null(NodePath(node_name))
        if node == null:
            continue
        _soldier_animation_defaults[node_name] = {
            "position": node.position,
            "rotation": node.rotation,
            "scale": node.scale
        }


func _soldier_default_transform(node_name: String, property: String, fallback: Vector3) -> Vector3:
    var entry: Dictionary = _soldier_animation_defaults.get(node_name, {})
    var value = entry.get(property, fallback)
    return value if value is Vector3 else fallback


func _reset_soldier_animation_state() -> void:
    for node_name: String in _soldier_animation_defaults:
        var node := model.get_node_or_null(NodePath(node_name))
        var defaults: Dictionary = _soldier_animation_defaults[node_name]
        if node == null:
            continue
        node.position = defaults.get("position", Vector3.ZERO)
        node.rotation = defaults.get("rotation", Vector3.ZERO)
        node.scale = defaults.get("scale", Vector3.ONE)


func _capture_bunker_construction_defaults() -> void:
    if kind != "bunker":
        return
    for node_name: String in [
        "bunker/BunkerBody",
        "bunker/Turret",
        "bunker/FactionLights",
        "bunker/FactionLights/FactionLight_L",
        "bunker/FactionLights/FactionLight_R"
    ]:
        var node := model.get_node_or_null(NodePath(node_name))
        if node == null:
            continue
        _bunker_construction_defaults[node_name] = {
            "position": node.position,
            "rotation": node.rotation,
            "scale": node.scale
        }


func _bunker_default_transform(node_name: String, property: String, fallback: Vector3) -> Vector3:
    var entry: Dictionary = _bunker_construction_defaults.get(node_name, {})
    var value = entry.get(property, fallback)
    return value if value is Vector3 else fallback


func _reset_bunker_construction_state() -> void:
    for node_name: String in _bunker_construction_defaults:
        var node := model.get_node_or_null(NodePath(node_name))
        var defaults: Dictionary = _bunker_construction_defaults[node_name]
        if node == null:
            continue
        node.position = defaults.get("position", Vector3.ZERO)
        node.rotation = defaults.get("rotation", Vector3.ZERO)
        node.scale = defaults.get("scale", Vector3.ONE)


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
    var armor_position := _soldier_default_transform("soldier/ArmorCore", "position", Vector3.ZERO)
    var helmet_rotation := _soldier_default_transform("soldier/Helmet", "rotation", Vector3.ZERO)
    _add_value_track(animation, "soldier/ArmorCore", "position", [armor_position, armor_position + Vector3(0, 0.018, 0), armor_position])
    _add_value_track(animation, "soldier/Helmet", "rotation", [helmet_rotation, helmet_rotation + Vector3(0, 0.12, 0), helmet_rotation])
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
    var weapon_position := _soldier_default_transform("soldier/Weapon", "position", Vector3.ZERO)
    var muzzle_position := _soldier_default_transform("soldier/Muzzle", "position", Vector3(0, 0, 1))
    var right_arm_rotation := _soldier_default_transform("soldier/Arm_R", "rotation", Vector3.ZERO)
    # The visible soldier front and corrected weapon both use local +Z.
    _add_value_track(animation, "soldier/Weapon", "position", [weapon_position, weapon_position + Vector3(0, 0, -0.14), weapon_position])
    _add_value_track(animation, "soldier/Muzzle", "position", [muzzle_position, muzzle_position + Vector3(0, 0, -0.14), muzzle_position])
    _add_value_track(animation, "soldier/Arm_R", "rotation", [right_arm_rotation + Vector3(-0.16, 0, 0), right_arm_rotation + Vector3(0.10, 0, 0), right_arm_rotation + Vector3(-0.16, 0, 0)])
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
    var animation := _make_animation(2.4)
    _base_property_track(animation, "base_windows_power", [[0.0, 1.0], [2.4, 1.0]])
    _base_property_track(animation, "base_scan_phase", [[0.0, 0.0], [2.4, 2.4]])
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
    var turret_rotation := _bunker_default_transform("bunker/Turret", "rotation", Vector3.ZERO)
    var left_light_scale := _bunker_default_transform("bunker/FactionLights/FactionLight_L", "scale", Vector3.ONE)
    var right_light_scale := _bunker_default_transform("bunker/FactionLights/FactionLight_R", "scale", Vector3.ONE)
    _add_value_track(animation, "bunker/Turret", "rotation", [
        turret_rotation + Vector3(0, -0.12, 0),
        turret_rotation + Vector3(0, 0.12, 0),
        turret_rotation + Vector3(0, -0.12, 0)
    ])
    _add_value_track(animation, "bunker/FactionLights/FactionLight_L", "scale", [
        left_light_scale,
        left_light_scale * 1.24,
        left_light_scale
    ])
    _add_value_track(animation, "bunker/FactionLights/FactionLight_R", "scale", [
        right_light_scale,
        right_light_scale * 1.24,
        right_light_scale
    ])
    return animation


func _bunker_fire() -> Animation:
    var animation := _make_animation(0.5)
    var barrel_position := _bunker_default_transform("bunker/Turret/Barrel", "position", Vector3.ZERO)
    var turret_rotation := _bunker_default_transform("bunker/Turret", "rotation", Vector3.ZERO)
    var muzzle_scale := _bunker_default_transform("bunker/Turret/MuzzleFlash", "scale", Vector3.ONE)
    _add_value_track(animation, "bunker/Turret/Barrel", "position", [
        barrel_position,
        barrel_position + Vector3(0, 0, 0.12),
        barrel_position
    ])
    _add_value_track(animation, "bunker/Turret", "rotation", [
        turret_rotation,
        turret_rotation + Vector3(0.035, 0, 0),
        turret_rotation
    ])
    _add_value_track(animation, "bunker/Turret/MuzzleFlash", "scale", [
        muzzle_scale,
        Vector3(1.35, 0.75, 1.35),
        muzzle_scale
    ])
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
    if kind == "base":
        var stages := [
            ["BaseFoundation", 0.0, 0.12, 0.18],
            ["BaseRing_0", 0.12, 0.24, 1.25],
            ["BaseRing_1", 0.24, 0.36, 1.25],
            ["BaseRing_2", 0.36, 0.48, 1.25],
            ["BaseRing_3", 0.48, 0.60, 1.25],
            ["BaseTower", 0.60, 0.82, 2.75],
            ["BaseCrown", 0.82, 0.95, 3.45]
        ]
        for stage: Array in stages:
            var node_path := "base/" + str(stage[0])
            var final_position: Vector3 = _base_construction_defaults[node_path]
            var hidden_position := final_position - Vector3(0, float(stage[3]), 0)
            var track := animation.add_track(Animation.TYPE_VALUE)
            animation.track_set_path(track, node_path + ":position")
            animation.track_insert_key(track, 0.0, hidden_position)
            animation.track_insert_key(track, float(stage[1]), hidden_position)
            animation.track_insert_key(track, float(stage[2]), final_position)
            animation.track_insert_key(track, 1.0, final_position)
        _base_property_track(animation, "base_windows_power", [[0.0, 0.0], [1.0, 0.0]])
        _base_property_track(animation, "base_scan_phase", [[0.0, 0.0], [1.0, 0.0]])
        return animation
    if kind == "bunker":
        var body_position := _bunker_default_transform("bunker/BunkerBody", "position", Vector3.ZERO)
        var turret_position := _bunker_default_transform("bunker/Turret", "position", Vector3.ZERO)
        var lights_position := _bunker_default_transform("bunker/FactionLights", "position", Vector3.ZERO)
        var left_light_scale := _bunker_default_transform("bunker/FactionLights/FactionLight_L", "scale", Vector3.ONE)
        var right_light_scale := _bunker_default_transform("bunker/FactionLights/FactionLight_R", "scale", Vector3.ONE)
        var body_hidden := body_position + Vector3(0, -0.85, 0)
        var turret_hidden := turret_position + Vector3(0, -0.45, 0)
        var lights_hidden := lights_position + Vector3(0, -0.85, 0)
        _add_value_track(animation, "bunker/BunkerBody", "position", [
            body_hidden,
            body_hidden,
            body_position + Vector3(0, -0.25, 0),
            body_position
        ])
        _add_value_track(animation, "bunker/Turret", "position", [
            turret_hidden,
            turret_hidden,
            turret_position + Vector3(0, -0.18, 0),
            turret_position
        ])
        _add_value_track(animation, "bunker/FactionLights", "position", [
            lights_hidden,
            lights_hidden,
            lights_position + Vector3(0, -0.25, 0),
            lights_position
        ])
        _add_value_track(animation, "bunker/FactionLights/FactionLight_L", "scale", [
            Vector3.ZERO,
            Vector3.ZERO,
            left_light_scale * 0.35,
            left_light_scale
        ])
        _add_value_track(animation, "bunker/FactionLights/FactionLight_R", "scale", [
            Vector3.ZERO,
            Vector3.ZERO,
            right_light_scale * 0.35,
            right_light_scale
        ])
        return animation
    var low := Vector3(1, 0.2, 1)
    _add_value_track(animation, kind, "scale", [low, Vector3.ONE])
    return animation
