extends SceneTree

const OUT := "res://assets/concept_art/gaia_command_base/"
var preview: Node3D
var base: GaiaCommandBase
var camera: Camera3D
var failures: Array[String] = []


func _initialize() -> void:
    run.call_deferred()
    create_timer(180).timeout.connect(func(): quit(1))


func capture(name: String, position: Vector3, target: Vector3, ortho: float = 0) -> void:
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL if ortho > 0 else Camera3D.PROJECTION_PERSPECTIVE
    camera.size = ortho if ortho > 0 else 1
    camera.position = position
    camera.look_at(target, Vector3.FORWARD if absf(position.x-target.x)+absf(position.z-target.z) < 0.01 else Vector3.UP)
    for frame in range(16):
        await process_frame
    await RenderingServer.frame_post_draw
    if root.get_texture().get_image().save_png(OUT + name + ".png") != OK:
        failures.append("capture " + name)


func run() -> void:
    root.size = Vector2i(1600, 1000)
    root.msaa_3d = Viewport.MSAA_4X
    preview = load("res://tests/previews/gaia_command_base_preview.tscn").instantiate()
    root.add_child(preview)
    preview.set_process(false)
    preview.get_node("PreviewControls").hide()
    base = preview.base
    camera = preview.camera
    base.automatic_animation = false
    base.forced_lod = 0
    base.seek_pose("deployed", 0)
    await capture("01-perspective", Vector3(230, 150, -280), Vector3(0, 65, 0))
    await capture("02-top", Vector3(0, 600, 0), Vector3(0, 40, 0), 240)
    await capture("03-front", Vector3(0, 72, -600), Vector3(0, 72, 0), 220)
    await capture("04-side", Vector3(500, 100, 0), Vector3(0, 72, 0), 210)
    await capture("05-rear", Vector3(-340, 155, 400), Vector3(0, 65, 0))
    await capture("06-tower-detail", Vector3(100, 150, -185), Vector3(0, 95, 0))
    await capture("07-reactor-detail", Vector3(210, 72, -190), Vector3(87, 40, -43))
    base.seek_pose("airborne", 0)
    await capture("08-underside", Vector3(280, 45, -330), Vector3(0, 140, 0))
    base.seek_pose("deployed", 0)
    var miner := EntityVisual.new("harvester", 1)
    preview.add_child(miner)
    miner.position = Vector3(175, 0, -100)
    miner.harvester_motion.sample({"cargo": 60, "work": 0}, 0, null)
    await capture("09-scale-comparison", Vector3(400, 280, -510), Vector3(22, 50, 0))
    miner.queue_free()
    var depot := EntityVisual.new("refinery", 1)
    var barracks := EntityVisual.new("barracks", 1)
    preview.add_child(depot)
    preview.add_child(barracks)
    depot.position = Vector3(300, 0, 0)
    barracks.position = Vector3(-300, 0, 0)
    depot.model.set_lod(0)
    depot.model.set_process(false)
    barracks.barracks_presentation.set_lod(0)
    base.forced_lod = 0
    await capture("12-buildings-same-scale", Vector3(500, 540, -800), Vector3(0, 40, 0), 850)
    await capture("13-buildings-top-scale", Vector3(0, 800, 0), Vector3.ZERO, 850)
    depot.free()
    barracks.free()
    for level in range(3):
        base.forced_lod = level
        base.seek_pose("deployed", 0)
        await capture("10-lod-%d" % level, Vector3(350, 210, -420), Vector3(0, 65, 0))
    base.forced_lod = 0
    for pose: Array in [["taking_off",3.0,false],["airborne",6.0,true],["landing",3.0,false]]:
        base.seek_pose(pose[0],pose[1],pose[2])
        await capture("11-" + pose[0], Vector3(350, 240, -460), Vector3(0, 105, 0))
    # Short frame sequence, directly rendered and suitable for later video assembly.
    DirAccess.make_dir_recursive_absolute(OUT + "motion")
    base.seek_pose("deployed", 0)
    for frame in range(49):
        if frame == 12:
            base.take_off()
        elif frame == 24:
            base.set_cruising(true)
        elif frame == 36:
            base.land()
        await capture("motion/frame-%03d" % frame, Vector3(350, 250, -490), Vector3(0, 105, 0))
        base.advance(0.5)
    print("GAIA_REVIEW ", JSON.stringify({"renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "failures": failures}))
    preview.queue_free()
    await process_frame
    quit(0 if failures.is_empty() else 1)
