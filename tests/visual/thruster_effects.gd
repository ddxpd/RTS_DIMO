extends SceneTree
const Entity = preload("res://assets/art/entity_visual.gd")
const Thruster = preload("res://assets/art/effects/thruster_plume.gd")
var failures: Array[String] = []
var checks := 0
var world: Node3D
var camera: Camera3D


func _initialize() -> void:
    run.call_deferred()


func check(value: bool, label: String) -> void:
    checks += 1
    if not value:
        failures.append(label)
        push_error(label)


func fixture(state: String = "airborne", moving: bool = true) -> Dictionary:
    return {"type": "barracks", "remaining": 0, "queue": [], "hp": 1400, "pos": Vector2.ZERO,
        "flight": {"state": state, "ticks": 0, "height": 96.0, "heading": 0.0, "target": Vector2(0, -200), "moving": moving}}


func ground(_point: Vector2) -> float:
    return 24.0


func run() -> void:
    world = Node3D.new()
    root.add_child(world)
    var base := Entity.new("base")
    world.add_child(base)
    var barracks := Entity.new("barracks")
    world.add_child(barracks)
    var model: Node3D = base.model
    model.automatic_animation = false
    base.position.y = 96
    barracks.position.y = 96
    model.apply_flight(fixture().flight, 0.0, true, ground)
    barracks.barracks_motion.apply(fixture().flight)
    barracks.barracks_presentation.update(fixture(), 0.0, null, ground)
    check(model.engine_plumes.size() == 4, "Base has four lift jets")
    check(model.engine_plumes[0].radius == 15.0 and model.engine_plumes[0].max_length == 100.0, "Base enlarged lift plume")
    check(barracks.barracks_presentation.lift_jets.size() == 4, "Barracks four lift anchors found")
    check(barracks.barracks_presentation.lift_jets[0].radius == 6.6 and barracks.barracks_presentation.lift_jets[0].max_length == 57.0, "Barracks enlarged lift plume")
    check(barracks.barracks_presentation.rear_jets[0].radius == 7.2 and barracks.barracks_presentation.rear_jets[0].max_length == 72.0, "Barracks enlarged rear plume")
    var jets: Array = []
    jets.append_array(model.engine_plumes)
    jets.append_array(barracks.barracks_presentation.lift_jets)
    jets.append_array(barracks.barracks_presentation.rear_jets)
    for jet: Node3D in jets:
        check(jet.visible and jet.strength > 0.5, "Flight emits visible plasma")
        check(jet.outer.material_override == jets[0].outer.material_override, "Shared shader material")
        check(jet.outer.mesh == jets[0].outer.mesh, "Shared flow mesh")
        check(jet.tail.amount == 6 and jet.tail.emitting, "Bounded near tail particles")
        check(jet.tail.draw_pass_1.material.billboard_keep_scale, "Billboard preserves particle size")
        check(jet.outer.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "No exhaust shadow")
        if jet.lift:
            check((-jet.global_basis.y).normalized().dot(Vector3.DOWN) > 0.99, "Lift points down")
            check(is_equal_approx(jet.dust.global_position.y, 24.6), "Dust uses terrain height under nozzle")
        else:
            check((-jet.global_basis.y).normalized().dot(Vector3.BACK) > 0.999, "Rear exhaust points opposite forward")
    for lod in range(3):
        barracks.barracks_presentation.set_lod(lod)
        for suffix in ["LFront", "LRear", "RFront", "RRear"]:
            check(not barracks.model.find_child("Jet" + suffix, true, false).visible, "Authored solid flame stays hidden at every LOD")
    var plume: Node3D = jets[0]
    plume.advance(0, 0.8, 2, true, ground)
    check(plume.inner.visible and not plume.outer.visible and not plume.tail.emitting and not plume.dust.emitting, "Far LOD core only")
    base.position.y = 22
    plume.advance(0, 0.8, 0, true, ground)
    check(plume.dust.emitting and plume.dust_power > 0.5, "Near ground produces wash")
    base.position.y = ground(Vector2.ZERO) + plume.max_length * 2.0
    plume.advance(0, 0.8, 0, true, ground)
    check(not plume.dust.emitting and plume.dust_power == 0, "High altitude removes dust")
    plume.advance(1.0 / 60.0, 0, 0, true, ground)
    check(plume.strength > 0 and plume.strength < 0.8 and not plume.tail.emitting, "Stop fades flow while ending particle emission")
    plume.advance(0.6, 0, 0, true, ground)
    check(not plume.visible, "Flow fully disappears after shutdown")
    plume.advance(0, 0.8, 0, true, ground)
    plume.advance(0.01, 0.8, 0, false, ground)
    check(not plume.visible and not plume.tail.emitting and not plume.dust.emitting, "Fog hiding stops all emitters immediately")
    var turning := fixture()
    turning.flight.heading = PI
    barracks.barracks_presentation.update(turning, 0.0, null, ground)
    check(barracks.barracks_presentation.rear_jets.all(func(jet: Node3D) -> bool: return jet.target_strength == 0), "Turning never drives rear jets")
    check(barracks.barracks_presentation.lift_jets.all(func(jet: Node3D) -> bool: return jet.strength > 0), "Turning retains lift")
    check(Thruster.lift_power("taking_off", 0.5) > Thruster.lift_power("airborne", 0), "Takeoff boost above hover")
    check(Thruster.lift_power("landing", 1) == 0 and Thruster.lift_power("grounded", 0) == 0, "Touchdown extinguishes lift")
    barracks.set_construction_tint(true)
    barracks.barracks_presentation.update(fixture(), 0.1, null, ground)
    check(not barracks.barracks_presentation.effect_root.visible, "Construction suppresses exhaust")
    barracks.set_construction_tint(false)
    if DisplayServer.get_name() != "headless":
        await render_preview(base, barracks)
    var weak: WeakRef = weakref(plume)
    base.free()
    check(weak.get_ref() == null, "Destroying building releases child emitters")
    world.free()
    print("THRUSTER_EFFECTS ", JSON.stringify({"checks": checks, "failures": failures}))
    quit(0 if failures.is_empty() else 1)


func settle(base: Node3D, barracks: Node3D, b: Dictionary, frames: int) -> void:
    for frame in range(frames):
        base.model.apply_flight(b.flight, 1.0 / 60.0, bool(b.flight.moving))
        barracks.barracks_motion.apply(b.flight)
        barracks.barracks_presentation.update(b, 1.0 / 60.0, camera)
        await process_frame


func capture(label: String) -> void:
    await RenderingServer.frame_post_draw
    var path := "res://assets/concept_art/building_lifecycle/exhaust_" + label + ".png"
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    check(root.get_texture().get_image().save_png(path) == OK, "Preview saved: " + label)


func render_preview(base: Node3D, barracks: Node3D) -> void:
    root.size = Vector2i(1440, 900)
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color(0.035, 0.05, 0.075)
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color(0.62, 0.7, 0.85)
    environment.environment.ambient_light_energy = 0.7
    environment.environment.glow_enabled = true
    environment.environment.glow_intensity = 0.65
    world.add_child(environment)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-40, -35, 0)
    sun.light_energy = 1.6
    world.add_child(sun)
    var floor_mesh := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(4000, 4000)
    var floor_material := StandardMaterial3D.new()
    floor_material.albedo_color = Color(0.17, 0.19, 0.21)
    plane.material = floor_material
    floor_mesh.mesh = plane
    world.add_child(floor_mesh)
    camera = Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 650
    world.add_child(camera)
    camera.current = true
    base.position = Vector3(-130, 105, 0)
    barracks.position = Vector3(190, 96, 0)
    camera.position = Vector3(430, 290, 600)
    camera.look_at(Vector3(0, 105, 0))
    await settle(base, barracks, fixture(), 75)
    await capture("cruise")
    camera.size = 280
    camera.position = barracks.position + Vector3(190, 95, 220)
    camera.look_at(barracks.position + Vector3(0, 20, 5))
    await settle(base, barracks, fixture(), 35)
    await capture("barracks_detail")
    camera.size = 900
    camera.position = Vector3(430, 750, 600)
    camera.look_at(Vector3(0, 70, 0))
    await settle(base, barracks, fixture("airborne", false), 40)
    await capture("rts_hover")
    base.position.y = 15
    barracks.position.y = 12
    camera.size = 600
    camera.position = Vector3(300, 230, 510)
    camera.look_at(Vector3(0, 50, 0))
    var lifting := fixture("taking_off", false)
    lifting.flight.ticks = 20
    await settle(base, barracks, lifting, 180)
    check(base.model.engine_plumes[0].dust.emitting, "Near rendered base emits ground wash")
    var wash: GPUParticles3D = base.model.engine_plumes[0].dust
    check(wash.capture_aabb().size.length() > 10.0, "GPU ground particles occupy the expected world-space region")
    await capture("ground_wash")
    camera.size = 170
    camera.position = base.position + Vector3(30, 65, 195)
    camera.look_at(base.position + Vector3(75, 0, 54))
    await settle(base, barracks, lifting, 40)
    await capture("wash_detail")
    # Same geometry/camera, effects on vs off. Frame timings are descriptive,
    # not a substitute for minimum-hardware acceptance.
    var fleet: Array[Node3D] = [base, barracks]
    for i in range(6):
        var building := Entity.new("base" if i % 2 == 0 else "barracks")
        world.add_child(building)
        building.position = Vector3((i % 3 - 1) * 360, 110, (i / 3 + 1) * -270)
        if building.kind == "base":
            building.model.automatic_animation = false
        fleet.append(building)
    base.position = Vector3(-180, 110, 130)
    barracks.position = Vector3(180, 110, 130)
    camera.size = 1450
    camera.position = Vector3(600, 900, 1100)
    camera.look_at(Vector3(0, 100, -250))
    var timings := {}
    RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
    for effects_enabled: bool in [false, true]:
        var elapsed_us := 0
        var gpu_ms := 0.0
        var cpu_ms := 0.0
        for frame in range(100):
            var start := Time.get_ticks_usec()
            for building in fleet:
                if building.kind == "base":
                    building.model.apply_flight(fixture().flight, 1.0 / 60.0, true)
                    for jet in building.model.engine_plumes:
                        if not effects_enabled:
                            jet.advance(0, 0, 0, false)
                else:
                    building.barracks_motion.apply(fixture().flight)
                    building.barracks_presentation.update(fixture(), 1.0 / 60.0, camera)
                    if not effects_enabled:
                        for jet in building.barracks_presentation.rear_jets + building.barracks_presentation.lift_jets:
                            jet.advance(0, 0, 0, false)
            await process_frame
            if frame >= 40:
                elapsed_us += Time.get_ticks_usec() - start
                gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
                cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
        timings["enabled" if effects_enabled else "disabled"] = {"frame_ms": elapsed_us / 60000.0, "gpu_ms": gpu_ms / 60.0, "render_cpu_ms": cpu_ms / 60.0}
    print("THRUSTER_FLEET_FRAME_MS ", JSON.stringify(timings))
    await capture("fleet")
