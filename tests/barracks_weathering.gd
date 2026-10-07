extends SceneTree

const OUTPUT := "res://assets/concept_art/barracks_weathering/"
const Motion = preload("res://assets/art/barracks_motion.gd")
var failures: Array[String] = []
var world: Node3D
var camera: Camera3D

class Rig extends Node3D:
    var model: Node3D
    var motion: RefCounted


func _initialize() -> void:
    run.call_deferred()


func load_model(path: String) -> Node3D:
    var document := GLTFDocument.new()
    var state := GLTFState.new()
    if document.append_from_file(path, state) != OK:
        failures.append("Cannot load " + path)
        return null
    return document.generate_scene(state)


func apply_materials(model: Node3D, faction: int, airborne: bool, far: bool) -> void:
    var shared := {}
    var team: Color = EntityVisual.TEAM_COLORS[faction]
    for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
        var name := str(mesh.name)
        mesh.visible = not (far and (name.begins_with("Gear") or name.begins_with("RampRod") or name.begins_with("RampCylinder") or name == "BarracksFlag"))
        mesh.lod_bias = 1000
        for surface in range(mesh.mesh.get_surface_count()):
            var source := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
            if not shared.has(source):
                var material := source.duplicate() as StandardMaterial3D
                if "Faction" in material.resource_name or material.resource_name == "FlagBlueFabric":
                    if material.albedo_texture != null:
                        var pixels: Image = material.albedo_texture.get_image().duplicate()
                        if pixels.is_compressed():
                            pixels.decompress()
                        pixels.adjust_bcs(1.5, 1.0, 0.0)
                        material.albedo_texture = ImageTexture.create_from_image(pixels)
                    material.albedo_color = team if "Paint" in material.resource_name else team.lightened(.35)
                    material.emission_enabled = true
                    material.emission = team.lightened(.25)
                    material.emission_energy_multiplier = .12
                if "Thrust" in material.resource_name:
                    material.emission_energy_multiplier = 2.0 if airborne else 0.0
                if far:
                    material.vertex_color_use_as_albedo = true
                shared[source] = material
            mesh.set_surface_override_material(surface, shared[source])


func run() -> void:
    root.size = Vector2i(1280, 720)
    world = Node3D.new()
    root.add_child(world)
    camera = Camera3D.new()
    world.add_child(camera)
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.position = Vector3(170, 230, -270)
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-55, -30, 0)
    light.shadow_enabled = true
    world.add_child(light)
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color("303943")
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color("bccde0")
    environment.environment.ambient_light_energy = .6
    world.add_child(environment)
    var floor_mesh := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(2200, 2200)
    floor_mesh.mesh = plane
    var floor_material := StandardMaterial3D.new()
    floor_material.albedo_color = Color("615a49")
    floor_mesh.material_override = floor_material
    world.add_child(floor_mesh)
    var caption := Label.new()
    caption.position = Vector2(560, 32)
    caption.add_theme_font_size_override("font_size", 28)
    root.add_child(caption)
    var cases := [
        ["close-blue", 180, 1, false, 0], ["normal-blue", 320, 1, false, 0],
        ["normal-red", 320, 2, false, 0], ["medium-blue", 550, 1, false, 1],
        ["far-blue", 1000, 1, false, 2], ["airborne-blue", 500, 1, true, 0],
        ["airborne-red", 500, 2, true, 0]
    ]
    for version: String in ["before", "after"]:
        caption.text = version.to_upper()
        var folder := OUTPUT + "before/" if version == "before" else "res://assets/models/"
        for settings: Array in cases:
            var rig := Rig.new()
            rig.model = load_model(folder + "barracks.glb")
            rig.add_child(rig.model)
            world.add_child(rig)
            rig.model.scale = Vector3.ONE * 12
            rig.motion = Motion.new(rig)
            rig.motion.wind.seek(.5, true)
            rig.motion.wind.pause()
            rig.motion.apply({"state": "airborne" if settings[3] else "grounded", "ticks": 80 if settings[3] else 0})
            if settings[4] > 0:
                var lod := load_model(folder + "barracks_lod%d.glb" % settings[4])
                for mesh: MeshInstance3D in lod.find_children("*", "MeshInstance3D", true, false):
                    var original: MeshInstance3D = rig.model.find_child(str(mesh.name), true, false)
                    original.mesh = mesh.mesh
                lod.free()
            apply_materials(rig.model, settings[2], settings[3], settings[4] == 2)
            rig.position.y = 144 if settings[3] else 0
            camera.size = settings[1]
            camera.look_at(Vector3(0, 90 if settings[3] else 45, 0))
            for frame in range(4):
                await process_frame
            await RenderingServer.frame_post_draw
            var path: String = OUTPUT + version + "-" + settings[0] + ".png"
            if root.get_texture().get_image().save_png(path) != OK:
                failures.append("Capture " + path)
            rig.free()
    for settings: Array in cases:
        var pair := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
        for side in range(2):
            var prefix := "before" if side == 0 else "after"
            var captured := Image.load_from_file(OUTPUT + prefix + "-" + settings[0] + ".png")
            captured.convert(Image.FORMAT_RGBA8)
            pair.blit_rect(captured, Rect2i(320, 0, 640, 720), Vector2i(side * 640, 0))
        if pair.save_png(OUTPUT + "compare-" + settings[0] + ".png") != OK:
            failures.append("Comparison image")
    print("BARRACKS_WEATHERING_PREVIEW ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
    world.free()
    caption.free()
    quit(0 if failures.is_empty() else 1)
