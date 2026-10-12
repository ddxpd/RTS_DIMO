extends Node3D
## Presentation only. Dock state is supplied by the authoritative simulation.
const SCENES := [preload("res://assets/models/buildings/refinery/refinery.glb"), preload("res://assets/models/buildings/refinery/refinery_lod1.glb"), preload("res://assets/models/buildings/refinery/refinery_lod2.glb")]
var levels: Array[Node3D] = []
var lamps: Array[Array] = [[], []]
var current_lod := -1


func _ready() -> void:
    var assembly := Node3D.new()
    assembly.name = "refinery"
    add_child(assembly)
    for index in range(3):
        var node: Node3D = SCENES[index].instantiate()
        assembly.add_child(node)
        levels.append(node)
        for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
            for surface in range(mesh.mesh.get_surface_count()):
                var original := mesh.get_active_material(surface) as StandardMaterial3D
                if original == null:
                    continue
                var mat := original.duplicate() as StandardMaterial3D
                mesh.set_surface_override_material(surface, mat)
                if "Glass" in str(original.resource_name):
                    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
                    mat.albedo_color = Color(0.27, 0.64, 0.83, 0.13)
                    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
                    mat.roughness = 0.14
                    mat.metallic = 0.05
                    mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
                if str(mesh.name).begins_with("DockLamp_"):
                    lamps[0 if "DockLamp_L" in str(mesh.name) else 1].append(mesh)
    set_lod(0)


func _process(_delta: float) -> void:
    var camera := get_viewport().get_camera_3d()
    if camera != null:
        var distance := camera.global_position.distance_to(global_position)
        set_lod(0 if distance < 1250 else (1 if distance < 2100 else 2))


func set_lod(index: int) -> void:
    if current_lod == index:
        return
    current_lod = index
    for i in range(levels.size()):
        levels[i].visible = i == index


func update_docks(building: Dictionary, units: Dictionary, building_id: int) -> void:
    var occupied := [false, false]
    for u: Dictionary in units.values():
        if u.has("dock") and u.dock.station == building_id and u.dock.slot >= 0:
            occupied[u.dock.slot] = true
    for slot in range(2):
        var pulse: bool = building.get("dock_flash", [0, 0])[slot] > 0
        var color := Color(0.2, 1.0, 0.65) if pulse else (Color(1.0, 0.58, 0.08) if occupied[slot] else Color(0.05, 0.6, 1.0))
        for mesh: MeshInstance3D in lamps[slot]:
            var mat := mesh.get_active_material(0) as StandardMaterial3D
            mat.emission_enabled = true
            mat.emission = color
            mat.emission_energy_multiplier = 3.0 if pulse else 1.6
