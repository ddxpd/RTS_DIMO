extends SceneTree


func _initialize() -> void:
    run.call_deferred()
    create_timer(120).timeout.connect(func(): quit(1))


func settle(count: int) -> void:
    for i in range(count):
        await process_frame


func run() -> void:
    root.size = Vector2i(1600, 1000)
    root.msaa_3d = Viewport.MSAA_4X
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    Engine.max_fps = 0
    var preview: Node3D = load("res://tests/previews/gaia_command_base_preview.tscn").instantiate()
    root.add_child(preview)
    preview.set_process(false)
    preview.get_node("PreviewControls").hide()
    var assets: Array[GaiaCommandBase] = [preview.base]
    for i in range(7):
        var base: GaiaCommandBase = load("res://assets/art/buildings/gaia/gaia_command_base.tscn").instantiate()
        preview.add_child(base)
        assets.append(base)
    var camera: Camera3D = preview.camera
    RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
    var measurements: Array[Dictionary] = []
    for scenario: Array in [[0,0],[1,0],[1,1],[1,2],[8,1]]:
        var count: int = scenario[0]
        var level: int = scenario[1]
        for i in range(assets.size()):
            assets[i].visible = i < count
            assets[i].automatic_animation = i < count
            assets[i].forced_lod = level
            assets[i].position = Vector3((i%4-1.5)*340,0,(i/4-0.5)*240) if count>1 else Vector3.ZERO
            assets[i].seek_pose("deployed", 0)
        camera.position = Vector3(230,150,-280) if count<2 else Vector3(1000,800,-1200)
        camera.look_at(Vector3(0,65,0))
        await settle(60)
        var frames: Array[float] = []
        var gpu: Array[float] = []
        for i in range(120):
            var begin := Time.get_ticks_usec()
            await process_frame
            frames.append((Time.get_ticks_usec()-begin)/1000.0)
            gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
        frames.sort()
        gpu.sort()
        measurements.append({"count":count,"lod":level,"frame_median_ms":frames[60],"frame_p95_ms":frames[113],"gpu_median_ms":gpu[60],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
    var result := {"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"resolution":root.size,"msaa":4,"vsync":false,"scenarios":measurements,"scope":"isolated preview; not full match or minimum-hardware guarantee"}
    var file := FileAccess.open("res://assets/concept_art/gaia_command_base/performance-report.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(result,"  "))
    print("GAIA_PERFORMANCE ",JSON.stringify(result))
    preview.queue_free()
    await process_frame
    quit()
