extends Node3D


func _ready() -> void:
    get_viewport().msaa_3d = Viewport.MSAA_4X
    var scene := load("res://assets/models/units/mobile_infantry/mobile_infantry.glb") as PackedScene
    for index in range(2):
        var model := scene.instantiate() as Node3D
        add_child(model)
        model.position.x = -0.75 if index == 0 else 0.75
        if index == 1:
            for instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
                for surface in range(instance.mesh.get_surface_count()):
                    var source := instance.mesh.surface_get_material(surface) as StandardMaterial3D
                    if "Faction" in source.resource_name:
                        var material := source.duplicate() as StandardMaterial3D
                        material.albedo_color = Color(0.58, 0.035, 0.022)
                        instance.set_surface_override_material(surface, material)
    var camera := Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 3.5
    camera.far = 20.0
    add_child(camera)
    camera.position = Vector3(2.4, 2.6, 6)
    camera.look_at(Vector3(0, 0.95, 0))
    camera.current = true
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-45, -35, 0)
    light.light_energy = 0.7
    light.shadow_enabled = true
    light.directional_shadow_max_distance = 12.0
    light.shadow_normal_bias = 0.04
    light.shadow_bias = 0.02
    add_child(light)
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color.WHITE
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color.WHITE
    environment.environment.ambient_light_energy = 0.65
    add_child(environment)
    var floor_mesh := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(200, 200)
    floor_mesh.mesh = plane
    var floor_material := StandardMaterial3D.new()
    floor_material.albedo_color = Color.WHITE
    floor_mesh.material_override = floor_material
    add_child(floor_mesh)
