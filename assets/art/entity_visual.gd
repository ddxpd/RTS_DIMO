class_name EntityVisual
extends Node3D

const MODEL_SCENES := {
    "mobile_infantry": preload("res://assets/models/units/mobile_infantry/mobile_infantry.glb"),
    "soldier": preload("res://assets/models/units/soldier/soldier.glb"),
    "harvester": preload("res://assets/models/units/harvester/harvester.glb"),
    "base": preload("res://assets/art/buildings/gaia/gaia_command_base.tscn"),
    "barracks": preload("res://assets/models/buildings/barracks/barracks.glb"),
    "refinery": preload("res://assets/art/buildings/refinery/ore_depot.tscn"),
    "bunker": preload("res://assets/models/buildings/bunker/bunker.glb"),
    "ore": preload("res://assets/models/environment/ore/ore.glb"),
}

const MOBILE_INFANTRY_SIZE_FACTOR := 2.0 / 3.0
const MODEL_SETTINGS := {
    "mobile_infantry": {"scale": 68.0 * MOBILE_INFANTRY_SIZE_FACTOR / 1.849, "height": 68.0 * MOBILE_INFANTRY_SIZE_FACTOR},
    "soldier": {"scale": 24.0, "height": 68.0},
    "harvester": {"scale": 17.5, "height": 44.0},
    "base": {"scale": 1.0, "height": 160.0},
    "barracks": {"scale": 12.0, "height": 104.0},
    "refinery": {"scale": 20.0, "height": 72.0},
    "bunker": {"scale": 23.0, "height": 62.0},
    "ore": {"scale": 45.0, "height": 80.0},
}

const TEAM_COLORS := {
    1: Color("#5fa5e0"),
    2: Color("#d66551")
}
const SELECTION_GREEN := Color("#65ff78")
const SELECTION_RING_WIDTH := 1.65
# Display bounds include a small gap around the completed model, independent
# of collision cells (the bunker base extends beyond its logical footprint).
const BUILDING_SELECTION_SIZES := {
    "base": Vector2(336.0, 208.0),
    "barracks": Vector2(140.0, 112.0),
    "refinery": Vector2(144.0, 144.0),
    "bunker": Vector2(96.0, 96.0),
}
const BUILDING_SELECTION_WIDTH := 2.4

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
var soldier_motion: RefCounted
var mobile_motion: RefCounted
var harvester_motion: RefCounted
var mobile_weapon: Node3D
var barracks_motion: RefCounted
var barracks_presentation: RefCounted
var _soldier_shadow_meshes: Array[MeshInstance3D] = []
var _soldier_shadows := false
var _bunker_construction_defaults: Dictionary = {}
var selection_ring: MeshInstance3D
var _selection_ring_material: StandardMaterial3D
var _selection_ring_enabled := false
var _selection_ring_radius := 1.0

static var _shared_animation_libraries: Dictionary = {}
static var _neutral_faction_textures: Dictionary = {}
static var _building_selection_meshes: Dictionary = {}


func _init(model_kind: String, model_owner: int = 1) -> void:
    kind = model_kind
    owner_id = model_owner


func _ready() -> void:
    var settings: Dictionary = MODEL_SETTINGS.get(kind, {"scale": 20.0, "height": 40.0})
    _model_scale = float(settings.scale)
    model = MODEL_SCENES[kind].instantiate()
    add_child(model)
    model.scale = Vector3.ONE * _model_scale
    _capture_bunker_construction_defaults()
    if kind == "ore":
        preload("res://assets/art/environment/ore/crystal_ore.gd").attach(self)
    elif kind != "base":
        _instance_materials()
    if kind == "mobile_infantry":
        mobile_weapon = preload("res://assets/art/units/mobile_infantry/mobile_infantry_weapon.gd").attach(model)
    _apply_lod_and_shadow_policy()
    _create_animation_player()
    if kind == "barracks":
        barracks_motion = preload("res://assets/art/buildings/barracks/barracks_motion.gd").new(self)
        barracks_presentation = preload("res://assets/art/buildings/barracks/barracks_presentation.gd").new(self)
    if kind == "soldier":
        soldier_motion = preload("res://assets/art/units/soldier/soldier_motion.gd").new(self)
    if kind == "mobile_infantry":
        mobile_motion = preload("res://assets/art/units/mobile_infantry/mobile_infantry_motion.gd").new(self)
    if kind == "harvester":
        harvester_motion = preload("res://assets/art/units/harvester/hover_harvester_motion.gd").new(self)
    set_faction(owner_id)
    set_animation("idle")
    _apply_selection_ring_state()


func _process(delta: float) -> void:
    if kind == "barracks":
        return
    if absf(angle_difference(rotation.y, _target_heading)) >= 0.001:
        rotation.y = lerp_angle(rotation.y, _target_heading, minf(delta * 10.0, 1.0))


func set_position_2d(position_2d: Vector2, ground_height: float = 0.0) -> void:
    position = Vector3(position_2d.x, ground_height, position_2d.y)


func set_heading(heading: Vector2, immediate: bool = false) -> void:
    if heading.length_squared() < 0.01:
        return
    var forward_z := _forward_z()
    _target_heading = atan2(heading.x * forward_z, heading.y * forward_z)
    if immediate:
        rotation.y = _target_heading


func get_visual_forward() -> Vector3:
    return (global_transform.basis.z * _forward_z()).normalized()


func _forward_z() -> float:
    # The soldier body is authored facing local +Z. The harvester arms are
    # authored facing local -Z, so facing must be resolved per model kind.
    return 1.0 if kind in ["soldier", "mobile_infantry"] else -1.0


func set_animation(next_state: String) -> void:
    if animation_state == next_state:
        return
    if kind in ["soldier", "mobile_infantry"]:
        animation_state = next_state
        return
    # Construction scales the model inner root. Reset it when leaving that
    # state so a stopped loop cannot leave a completed building double-scaled.
    if animation_state == "construction":
        var animated_root := model.get_node_or_null(NodePath("BarracksMechanicalV2" if kind == "barracks" else kind))
        if animated_root != null:
            animated_root.scale = Vector3.ONE
        if kind == "bunker":
            _reset_bunker_construction_state()
    animation_state = next_state
    if kind == "barracks" and barracks_motion != null:
        barracks_motion.apply({"state": "grounded", "ticks": 0})
    if animation_player == null or not animation_player.has_animation(next_state):
        return
    animation_player.speed_scale = 1.0
    animation_player.play(next_state)


func set_flash(enabled: bool) -> void:
    if flash_enabled == enabled:
        return
    flash_enabled = enabled
    _refresh_material_tint()


func set_soldier_shadow_distance(camera_position: Vector3) -> void:
    var enabled := global_position.distance_squared_to(camera_position) < 600.0 * 600.0
    if enabled == _soldier_shadows:
        return
    _soldier_shadows = enabled
    for mesh in _soldier_shadow_meshes:
        mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


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
    var torus := selection_ring.mesh as TorusMesh
    if torus == null:
        return
    if not is_equal_approx(torus.outer_radius, _selection_ring_radius):
        # Change the circle radius without scaling its stroke or vertical thickness.
        torus.outer_radius = _selection_ring_radius
        torus.inner_radius = maxf(0.0, _selection_ring_radius - SELECTION_RING_WIDTH)


func _create_selection_ring() -> void:
    selection_ring = MeshInstance3D.new()
    selection_ring.name = "SelectionRing"
    var is_building := BUILDING_SELECTION_SIZES.has(kind)
    if is_building:
        selection_ring.mesh = _get_building_selection_mesh(kind)
    else:
        var torus := TorusMesh.new()
        torus.outer_radius = _selection_ring_radius
        torus.inner_radius = maxf(0.0, _selection_ring_radius - SELECTION_RING_WIDTH)
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
    _selection_ring_material.emission_energy_multiplier = 1.1 if is_building else 1.8
    if is_building:
        _selection_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
    selection_ring.material_override = _selection_ring_material
    selection_ring.visible = false
    add_child(selection_ring)


static func _get_building_selection_mesh(building_kind: String) -> ArrayMesh:
    if _building_selection_meshes.has(building_kind):
        return _building_selection_meshes[building_kind]
    # Shorten the arms on small buildings while keeping a fixed world stroke.
    # All four side centers stay open, and instances share immutable geometry.
    var size: Vector2 = BUILDING_SELECTION_SIZES[building_kind]
    var half_size := size * 0.5
    var width := BUILDING_SELECTION_WIDTH
    var arm := minf(30.0, minf(size.x, size.y) * 0.22)
    var chamfer := minf(8.0, arm * 0.28)
    var inner_cut := chamfer + width * (sqrt(2.0) - 1.0)
    var corner := PackedVector2Array([
        Vector2(half_size.x - arm, half_size.y),
        Vector2(half_size.x - chamfer, half_size.y),
        Vector2(half_size.x, half_size.y - chamfer),
        Vector2(half_size.x, half_size.y - arm),
        Vector2(half_size.x - width, half_size.y - arm),
        Vector2(half_size.x - width, half_size.y - inner_cut),
        Vector2(half_size.x - inner_cut, half_size.y - width),
        Vector2(half_size.x - arm, half_size.y - width),
    ])
    var triangles := Geometry2D.triangulate_polygon(corner)
    var vertices := PackedVector3Array()
    var indices := PackedInt32Array()
    for x_sign in [-1.0, 1.0]:
        for z_sign in [-1.0, 1.0]:
            var offset := vertices.size()
            for point in corner:
                vertices.append(Vector3(point.x * x_sign, 0.0, point.y * z_sign))
            for index in triangles:
                indices.append(offset + index)
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    _building_selection_meshes[building_kind] = mesh
    return mesh


func set_faction(next_owner: int) -> void:
    if _faction_applied and owner_id == next_owner:
        return
    owner_id = next_owner
    _faction_applied = true
    var team: Color = TEAM_COLORS.get(owner_id, Color("#8d8d8d"))
    if kind == "base":
        (model as GaiaCommandBase).set_team_color(team)
        return
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
    var barracks_materials: Dictionary = {}
    for mesh_instance: MeshInstance3D in meshes:
        if mesh_instance.mesh == null:
            continue
        for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
            var source: Material = mesh_instance.get_active_material(surface_index)
            if source == null or not source is StandardMaterial3D:
                continue
            if kind == "barracks" and barracks_materials.has(source):
                mesh_instance.set_surface_override_material(surface_index, barracks_materials[source])
                continue
            var material := (source as StandardMaterial3D).duplicate()
            if kind == "barracks":
                barracks_materials[source] = material
            if kind == "barracks" and ("Faction" in material.resource_name or material.resource_name == "FlagBlueFabric") and material.albedo_texture != null:
                var key: int = material.albedo_texture.get_instance_id()
                if not _neutral_faction_textures.has(key):
                    # The body and faction paint share an atlas. Headless image
                    # textures can return the backing Image, so never desaturate it.
                    var pixels: Image = material.albedo_texture.get_image().duplicate()
                    if pixels.is_compressed():
                        pixels.decompress()
                    pixels.adjust_bcs(1.5, 1.0, 0.0)
                    _neutral_faction_textures[key] = ImageTexture.create_from_image(pixels)
                material.albedo_texture = _neutral_faction_textures[key]
            mesh_instance.set_surface_override_material(surface_index, material)
            var entry := {
                "material": material,
                "base_color": material.albedo_color,
                "faction": "Faction" in material.resource_name or (kind == "refinery" and str(mesh_instance.name).begins_with("FactionBadge")) or (kind == "barracks" and material.resource_name == "FlagBlueFabric")
            }
            _materials.append(entry)



func _apply_lod_and_shadow_policy() -> void:
    # Units contribute far more instances than buildings, so omit their shadow
    # passes and fade small mechanical details at strategic zoom distances.
    var unit_core: Dictionary = {}
    if kind == "soldier":
        unit_core = {
            "HeavySoldierMesh": true,
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
        for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
            unit_core[mesh.name] = true

    var is_unit := kind == "soldier" or kind == "harvester"
    for mesh_instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
        if is_unit:
            mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind == "harvester" and mesh_instance.name != "CargoGlass" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            if kind == "soldier":
                _soldier_shadow_meshes.append(mesh_instance)
            if not unit_core.has(mesh_instance.name) and mesh_instance.skin == null:
                mesh_instance.visibility_range_end = 1400.0
        elif mesh_instance.name in ["FactionGlow", "FactionSensor", "FactionBeacon", "FactionLight"]:
            mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _refresh_material_tint() -> void:
    if kind == "base":
        (model as GaiaCommandBase).set_visual_tint(construction_tint, flash_enabled)
        return
    var tint := 1.0
    if construction_tint:
        tint = 0.62
    if flash_enabled:
        tint = maxf(tint, 1.9)
    for entry: Dictionary in _materials:
        var material: StandardMaterial3D = entry.material
        material.albedo_color = (entry.base_color as Color) * tint


func _create_animation_player() -> void:
    if kind == "mobile_infantry":
        var players := model.find_children("*", "AnimationPlayer", true, false)
        if not players.is_empty():
            animation_player = players[0]
            animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
            animation_player.active = true
        return
    animation_player = AnimationPlayer.new()
    animation_player.name = "StateAnimationPlayer"
    add_child(animation_player)
    animation_player.root_node = animation_player.get_path_to(model)
    if not _shared_animation_libraries.has(kind):
        _shared_animation_libraries[kind] = _build_animation_library()
    animation_player.add_animation_library("", _shared_animation_libraries[kind])
    animation_player.active = kind != "soldier"




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
            # State names remain compatible; the distance-driven rig owns poses.
            for state: String in ["idle", "move", "attack"]:
                library.add_animation(state, _make_animation(1.0))
        "harvester":
            # The hover controller poses the rigid mechanism and cargo stages.
            for state: String in ["idle", "move", "mine", "unload"]:
                library.add_animation(state, _make_animation(1.0))
        "base":
            library.add_animation("idle", _make_animation(1.0))
            library.add_animation("construction", _construction_animation())
        "barracks":
            library.add_animation("idle", _barracks_idle())
            library.add_animation("active", _barracks_active())
            library.add_animation("construction", _construction_animation())
        "refinery":
            library.add_animation("idle", _make_animation(1.0))
            library.add_animation("active", _make_animation(1.0))
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




func _barracks_idle() -> Animation:
    return _make_animation(2.0)


func _barracks_active() -> Animation:
    return _make_animation(2.0)



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
    # Mineral geometry stays rigid; a subtle shared shader pulse supplies motion.
    return _make_animation(5.5)


func _construction_animation() -> Animation:
    # Keep this clip normalized. `set_construction_progress()` maps it to the
    # building's actual build time and seeks to the current construction ratio.
    var animation := _make_animation(1.0, false)
    # GAIA keeps a track-free normalized clip for snapshot timing only.
    if kind == "base":
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
    _add_value_track(animation, "BarracksMechanicalV2" if kind == "barracks" else kind, "scale", [low, Vector3.ONE])
    return animation
