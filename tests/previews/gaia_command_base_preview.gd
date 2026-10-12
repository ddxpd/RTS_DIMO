extends Node3D
## Standalone preview: no game scene, simulation or base replacement.

var base: GaiaCommandBase
var camera: Camera3D
var label: Label
var orbit := 0.65
var distance := 570.0
var dragging := false
var travel_time := 0.0


func _ready() -> void:
    var world := WorldEnvironment.new()
    world.environment = Environment.new()
    world.environment.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    var material := ProceduralSkyMaterial.new()
    material.sky_top_color = Color("#526f9b")
    material.sky_horizon_color = Color("#bdccda")
    material.ground_bottom_color = Color("#4a4e53")
    material.ground_horizon_color = Color("#c1c7cc")
    sky.sky_material = material
    world.environment.sky = sky
    world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    world.environment.ambient_light_energy = 0.7
    world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    world.environment.ssao_enabled = true
    world.environment.ssao_radius = 5.0
    world.environment.ssao_intensity = 1.15
    world.environment.glow_enabled = true
    world.environment.glow_intensity = 0.25
    add_child(world)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-43, 145, 0)
    sun.light_energy = 1.4
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 1800
    add_child(sun)
    var fill := DirectionalLight3D.new()
    fill.rotation_degrees = Vector3(-28, -35, 0)
    fill.light_color = Color("#d5e2ef")
    fill.light_energy = 0.55
    add_child(fill)
    var floor_mesh := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(10000, 10000)
    floor_mesh.mesh = plane
    var ground := StandardMaterial3D.new()
    ground.albedo_color = Color("#6b6a64")
    ground.roughness = 0.94
    floor_mesh.material_override = ground
    add_child(floor_mesh)
    base = preload("res://assets/art/buildings/gaia/gaia_command_base.tscn").instantiate()
    add_child(base)
    camera = Camera3D.new()
    camera.fov = 40
    camera.far = 10000
    add_child(camera)
    camera.current = true
    var overlay := CanvasLayer.new()
    overlay.name = "PreviewControls"
    add_child(overlay)
    var panel := VBoxContainer.new()
    panel.position = Vector2(18, 18)
    overlay.add_child(panel)
    label = Label.new()
    panel.add_child(label)
    var buttons := HBoxContainer.new()
    panel.add_child(buttons)
    for entry: Array in [["升空", base.take_off], ["下降", base.land], ["巡航 / 停止", toggle_cruise]]:
        var button := Button.new()
        button.text = entry[0]
        button.pressed.connect(entry[1])
        buttons.add_child(button)
    var hint := Label.new()
    hint.text = "右键拖动环绕 · 滚轮缩放 · 仅模型动作展示；建造生长动画待参考图"
    panel.add_child(hint)


func toggle_cruise() -> void:
    base.set_cruising(not base.cruising)


func _process(delta: float) -> void:
    if base.cruising:
        travel_time += delta
        base.position = Vector3(sin(travel_time * 0.12) * 100, 0, 0)
    var focus := base.position + Vector3(0, 65 + base.presentation.position.y * 0.3, 0)
    camera.position = focus + Vector3(sin(orbit) * distance, distance * 0.42, cos(orbit) * distance)
    camera.look_at(focus)
    label.text = "GAIA 指挥基地  |  %s  |  LOD %d" % [base.state, base.current_lod]


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_RIGHT:
            dragging = event.pressed
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
            distance = maxf(280, distance * 0.90)
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            distance = minf(2400, distance * 1.10)
    elif event is InputEventMouseMotion and dragging:
        orbit -= event.relative.x * 0.006
