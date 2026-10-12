extends RefCounted
## Shared mineral surfaces; per-deposit light follows the visual's fog visibility.

static var crystal_material: ShaderMaterial
static var rock_material: StandardMaterial3D


static func attach(visual: Node3D) -> void:
    if crystal_material == null:
        crystal_material = ShaderMaterial.new()
        crystal_material.resource_name = "CrystalOreShared"
        crystal_material.shader = preload("res://assets/art/environment/ore/crystal_ore.gdshader")
        crystal_material.set_shader_parameter("mineral_color", preload("res://assets/models/environment/ore/ore_crystal_basecolor.png"))
        crystal_material.set_shader_parameter("mineral_detail", preload("res://assets/models/environment/ore/ore_crystal_detail.png"))
        rock_material = StandardMaterial3D.new()
        rock_material.resource_name = "CrystalBasaltShared"
        rock_material.albedo_texture = preload("res://assets/models/environment/ore/ore_rock_basecolor.png")
        rock_material.normal_enabled = true
        rock_material.normal_texture = preload("res://assets/models/environment/ore/ore_rock_normal.png")
        rock_material.normal_scale = 0.6
        rock_material.roughness = 0.86
        rock_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    for mesh: MeshInstance3D in visual.model.find_children("*", "MeshInstance3D", true, false):
        if mesh.name == "CrystalCluster":
            mesh.material_override = crystal_material
        elif mesh.name == "FracturedRockBed":
            mesh.material_override = rock_material
    var light := OmniLight3D.new()
    light.name = "MineralBounceLight"
    light.light_color = Color("#24a9ff")
    light.light_energy = 1.5
    light.omni_range = 52.0
    light.omni_attenuation = 1.6
    light.position.y = 16.0
    light.shadow_enabled = false
    light.distance_fade_enabled = true
    light.distance_fade_begin = 1000.0
    light.distance_fade_length = 500.0
    visual.add_child(light)
