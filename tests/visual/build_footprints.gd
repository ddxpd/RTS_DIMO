extends SceneTree
const MAIN = preload("res://scenes/main.tscn")
const Sim = preload("res://scripts/simulation.gd")
var game
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
    run.call_deferred()


func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)


func preview(kind: String, point: Vector2) -> void:
    game._begin_build(kind)
    game.visual_sync._sync_build_preview(point)


func legal_site(kind: String, anchor: Vector2) -> Vector2:
    for y in range(-352, 353, 32):
        for x in range(-352, 353, 32):
            var point: Vector2 = game.sim.snap_building(kind, anchor + Vector2(x, y))
            if game.sim.build_error(1, kind, point).is_empty():
                return point
    check(false, "Legal fixture for " + kind)
    return anchor


func geometry(node: Node) -> Array[GeometryInstance3D]:
    var found: Array[GeometryInstance3D] = []
    if node is GeometryInstance3D:
        found.append(node)
    for child in node.get_children():
        found.append_array(geometry(child))
    return found


func capture(label: String) -> void:
    if DisplayServer.get_name() == "headless":
        return
    for i in range(3):
        await process_frame
    await RenderingServer.frame_post_draw
    var folder := "res://assets/concept_art/ui_selection/mechanical_hud/footprint_review"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
    check(root.get_texture().get_image().save_png(folder + "/" + label + ".png") == OK, "Save " + label)


func key(code: Key) -> void:
    var event := InputEventKey.new()
    event.keycode = code
    event.physical_keycode = code
    event.pressed = true
    root.push_input(event, true)


func click(point: Vector2, button: MouseButton) -> void:
    var event := InputEventMouseButton.new()
    event.position = game._world_to_screen(point)
    event.button_index = button
    event.pressed = true
    root.push_input(event, true)
    event = event.duplicate()
    event.pressed = false
    root.push_input(event, true)


func run() -> void:
    root.size = Vector2i(1920, 1080)
    root.content_scale_size = root.size
    game = MAIN.instantiate()
    game.selected_map_id = "desert_quarry"
    root.add_child(game)
    game.play_solo()
    game.set_process(false)
    var sim = game.sim
    sim.ai_enabled = false
    sim.units.clear()
    sim.money[1] = 10000
    sim.visible[1].fill(1)
    sim.explored[1].fill(1)
    var base_id := -1
    for id: int in sim.buildings:
        if sim.buildings[id].owner == 1:
            base_id = id
            break
    var anchor: Vector2 = sim.buildings[base_id].pos
    game.camera_controller.focus = anchor
    game.camera_zoom_level = 1.15
    game._update_camera_transform()
    game._refresh_ui()
    game._sync_visuals()
    var sizes := {"base": Vector2i(10, 6), "barracks": Vector2i(4, 3), "refinery": Vector2i(4, 4), "bunker": Vector2i(2, 2)}
    for kind: String in sizes:
        var point := legal_site(kind, anchor)
        game.camera_controller.focus = anchor.lerp(point, 0.5)
        game._update_camera_transform()
        preview(kind, point)
        var overlay = game.visual_sync.footprint_overlay
        var count: Vector2i = sizes[kind]
        check(overlay.dimensions == count, kind + " correct cell dimensions")
        check(overlay.footprint == sim.placement_bounds(kind, point), kind + " exact footprint")
        var expected_edges: int = count.x * (count.y + 1) + count.y * (count.x + 1)
        check(overlay.segments.size() == expected_edges, kind + " no duplicate shared edges or reserved center gap")
        check(overlay.segments.all(func(edge: Dictionary) -> bool: return edge.color == overlay.VALID), kind + " valid green wireframe")
        var meshes := geometry(game.build_preview_model)
        check(not meshes.is_empty() and meshes.all(func(mesh: GeometryInstance3D) -> bool: return is_equal_approx(mesh.transparency, 0.6) and mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF), kind + " ghost opacity and no shadows across all LOD meshes")
        check(overlay.occupied.has(base_id), "Existing base perimeter during " + kind)
        check(not overlay.outline_material.no_depth_test, "Occupied outline respects model depth")
        check(overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE and overlay.clip_contents, "Overlay is clipped and input-transparent")
        check(geometry(game.visual_sync.building_visuals[base_id].visual).all(func(mesh: GeometryInstance3D) -> bool: return is_zero_approx(mesh.transparency)), "Real base opacity unchanged")
        var original_mesh = overlay.occupied[base_id].mesh.mesh
        game.visual_sync._sync_build_preview(point)
        check(overlay.occupied[base_id].mesh.mesh == original_mesh, "Occupied geometry cached between frames")
        await capture(kind + "-valid")
        if DisplayServer.get_name() != "headless":
            check(Rect2(Vector2.ZERO, overlay.size).encloses(overlay.label_rect), "Label stays inside map viewport")
        game.visual_sync._sync_build_preview(anchor)
        check(not overlay.error.is_empty() and overlay.segments.all(func(edge: Dictionary) -> bool: return edge.color == overlay.INVALID), kind + " blocked red wireframe")
    var point := legal_site("barracks", anchor)
    var barracks: int = sim._add_building(1, "barracks", point, true)
    var enemy: int = sim._add_building(2, "bunker", anchor + Vector2(240, 160), true)
    sim.buildings[barracks].remaining = 10
    game._sync_visuals()
    preview("bunker", anchor)
    var overlay = game.visual_sync.footprint_overlay
    check(overlay.occupied.has(barracks), "Construction footprint shown")
    check(overlay.occupied.has(enemy), "Visible enemy footprint shown")
    sim.visible[1].fill(0)
    game.visual_sync._sync_build_preview(anchor)
    check(not overlay.occupied.has(enemy) and overlay.occupied.has(base_id), "Fog hides enemy footprint without hiding known own base")
    sim.visible[1].fill(1)
    sim.buildings[enemy].pos = Vector2(4500, 3000)
    game.visual_sync._sync_build_preview(anchor)
    check(not overlay.occupied.has(enemy), "Offscreen footprint excluded")
    sim.buildings[barracks].remaining = 0
    sim.buildings[barracks].flight.state = "airborne"
    sim.buildings[barracks].flight.height = sim.terrain.height_at(point) + 150
    game.visual_sync._sync_build_preview(anchor)
    check(not overlay.occupied.has(barracks), "Airborne footprint excluded")
    game.build_mode = ""
    game.deploy_building = barracks
    game._sync_visuals()
    game.visual_sync._sync_deploy_preview(point)
    check(overlay.dimensions == Vector2i(4, 3) and overlay.cells.size() == 12, "Deployment shares twelve-cell preview")
    check(overlay.error.is_empty(), "Deployment fixture is legal")
    check(not overlay.occupied.has(barracks), "Deploying building not duplicated in occupied outlines")
    var blocker: int = sim.add_unit(1, "soldier", point + Vector2(48, 32))
    game.visual_sync._sync_deploy_preview(point)
    check(overlay.cells.any(func(cell: Dictionary) -> bool: return not cell.error.is_empty()) and overlay.cells.any(func(cell: Dictionary) -> bool: return cell.error.is_empty()), "Partial obstruction preserves per-cell results")
    check(overlay.segments.any(func(edge: Dictionary) -> bool: return edge.color == overlay.INVALID) and overlay.segments.any(func(edge: Dictionary) -> bool: return edge.color == overlay.VALID), "Deployment mixes red and green edges")
    await capture("deploy-partial-block")
    game._deploy_click(point)
    check(not sim.buildings[barracks].flight.deploy, "Blocked deployment rejected by existing rules")
    sim.units.erase(blocker)
    key(KEY_ESCAPE)
    game.visual_sync._sync_build_preview(point)
    check(not overlay.visible and not overlay.ground_root.visible and not game.build_preview_model.visible, "Esc clears model/grid/occupied outlines")
    preview("bunker", anchor)
    click(anchor, MOUSE_BUTTON_RIGHT)
    game.visual_sync._sync_build_preview(anchor)
    check(game.build_mode.is_empty() and not overlay.visible, "Right click cancels through input-transparent overlay")
    preview("bunker", anchor)
    game._toggle_menu()
    game.visual_sync._sync_build_preview(anchor)
    check(not overlay.visible and not overlay.ground_root.visible, "Menu hides all placement hints")
    game._toggle_menu()
    sim.buildings.erase(barracks)
    sim.buildings.erase(enemy)
    var bunker_point := legal_site("bunker", anchor)
    game.camera_controller.focus = bunker_point
    game._update_camera_transform()
    preview("bunker", bunker_point)
    var before: int = sim.buildings.size()
    check(game._get_map_screen_rect().has_point(game._world_to_screen(bunker_point)), "Build click lies in map viewport")
    click(bunker_point, MOUSE_BUTTON_LEFT)
    game.visual_sync._sync_build_preview(bunker_point)
    check(sim.buildings.size() == before + 1 and not overlay.visible and game.build_mode.is_empty(), "Successful build places building and clears hints")
    var refinery_point := legal_site("refinery", anchor)
    game.camera_controller.focus = anchor.lerp(refinery_point, 0.5)
    for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(2560, 1080)]:
        root.size = resolution
        root.content_scale_size = resolution
        game._refresh_ui()
        game.camera_zoom_level = 0.8 if resolution.x == 1280 else 1.5
        game._update_camera_transform()
        await process_frame
        game._sync_visuals()
        preview("refinery", refinery_point)
        await capture("grid-%dx%d" % [resolution.x, resolution.y])
        check(overlay.get_global_rect() == game._get_map_screen_rect(), "Map clipping follows HUD layout " + str(resolution))
        if DisplayServer.get_name() != "headless":
            check(Rect2(Vector2.ZERO, overlay.size).encloses(overlay.label_rect), "Label remains within map after resize")
    var old_overlay: WeakRef = weakref(overlay)
    game.restart_match()
    await process_frame
    check(old_overlay.get_ref() == null and game.visual_sync.footprint_overlay == null, "Restart frees preview and occupied cache")
    game.return_to_title()
    game.selected_map_id = "desert_sample"
    game.play_solo()
    var elevated := Vector2.ZERO
    for y in range(960, 2176, 64):
        for x in range(1504, 3296, 64):
            var candidate := Vector2(x, y)
            if sim.terrain.height_at(candidate) > 16 and sim.terrain.build_error(Rect2(candidate - Vector2(48, 48), Vector2(96, 96))).is_empty():
                elevated = candidate
                break
        if elevated != Vector2.ZERO:
            break
    check(elevated != Vector2.ZERO, "Elevated terrain fixture exists")
    game.camera_controller.focus = elevated + Vector2(80, 80)
    game.camera_zoom_level = 1.1
    game._update_camera_transform()
    var high_building: int = sim._add_building(1, "bunker", elevated, true)
    for index in range(7):
        sim._add_building(1, "bunker", elevated + Vector2((index % 4) * 96, (1 + index / 4) * 96), index % 2 == 0)
    game._refresh_ui()
    game._sync_visuals()
    preview("barracks", elevated + Vector2(256, -128))
    overlay = game.visual_sync.footprint_overlay
    check(overlay.occupied.has(high_building) and overlay.occupied.size() >= 7, "Dense completed/construction footprints visible")
    var vertices: PackedVector3Array = overlay.occupied[high_building].mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
    var grounded := true
    for vertex in vertices:
        grounded = grounded and absf(vertex.y - sim.terrain.height_at(Vector2(vertex.x, vertex.z)) - 0.85) < 0.002
    check(not vertices.is_empty() and grounded, "Occupied perimeter follows elevated terrain")
    await capture("sample-elevated-crowded")
    game.return_to_title()
    game.visual_sync._sync_build_preview()
    check(game.visual_sync.footprint_overlay == null and game.build_preview_model == null, "Title clears preview state")
    game.audio_controller.reset_state()
    await process_frame
    await create_timer(0.1).timeout
    game.queue_free()
    await process_frame
    await create_timer(0.1).timeout
    print("BUILD_FOOTPRINTS checks=", checks, " failures=", failures)
    quit(0 if failures.is_empty() else 1)
