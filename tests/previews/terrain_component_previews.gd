extends SceneTree
## Retained deliverables, not temporary verification screenshots.
const Catalog = preload("res://scripts/maps/component_catalog.gd")
const OUT := "res://assets/concept_art/desert_terrain_kit/editor_ready/"
var stage: Node3D
var camera: Camera3D


func _initialize() -> void:
    run.call_deferred()


func run() -> void:
    root.size = Vector2i(512, 512)
    DirAccess.make_dir_recursive_absolute(OUT)
    DirAccess.make_dir_recursive_absolute(Catalog.ROOT + "thumbnails")
    stage = Node3D.new()
    root.add_child(stage)
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color("ddd8cf")
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color("dfe8f4")
    environment.environment.ambient_light_energy = 0.5
    stage.add_child(environment)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-52, -35, 0)
    sun.light_energy = 1.0
    sun.shadow_enabled = true
    stage.add_child(sun)
    camera = Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.far = 8000
    stage.add_child(camera)
    for id: String in Catalog.IDS:
        var node: MeshInstance3D = load(Catalog.entry(id).scene).instantiate()
        var document := GLTFDocument.new()
        var state := GLTFState.new()
        if document.append_from_scene(node, state) != OK or document.write_to_filesystem(state, OUT + id + ".glb") != OK:
            push_error("Cannot export library preview " + id)
            quit(1)
            return
        stage.add_child(node)
        var box := node.mesh.get_aabb()
        var focus := box.get_center()
        camera.size = maxf(160, maxf(box.size.x, box.size.z) * 1.5)
        camera.position = focus + Vector3(-0.4, 0.85, -1).normalized() * 1000
        camera.look_at(focus)
        for frame in range(6):
            await process_frame
        await RenderingServer.frame_post_draw
        var image := root.get_texture().get_image()
        image.save_png(OUT + id + ".png")
        image.resize(256, 256, Image.INTERPOLATE_LANCZOS)
        image.save_png(Catalog.ROOT + "thumbnails/" + id + ".png")
        stage.remove_child(node)
        node.free()
    stage.queue_free()
    await process_frame
    print("TERRAIN_COMPONENT_PREVIEWS saved=12")
    quit()
