extends SceneTree

const MAIN = preload("res://scenes/main.tscn")
const Sim = preload("res://scripts/simulation.gd")

var game: Node3D
var failures: Array[String] = []


func _initialize() -> void:
    run.call_deferred()


func check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
        push_error(message)


func _has_animations(available: Array[StringName], required: Array[String]) -> bool:
    for animation_name: String in required:
        if not available.has(StringName(animation_name)):
            return false
    return true


func _visual_world_aabb(visual: EntityVisual) -> AABB:
    var result := AABB()
    var first := true
    for node: Node in visual.model.find_children("*", "MeshInstance3D", true, false):
        var mesh_instance := node as MeshInstance3D
        if mesh_instance == null or mesh_instance.mesh == null:
            continue
        var box := mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
        if first:
            result = box
            first = false
        else:
            result = result.merge(box)
    return result

func _fits_footprint(box: AABB, footprint: Vector2, tolerance: float = 8.0) -> bool:
    return box.size.x <= footprint.x + tolerance and box.size.z <= footprint.y + tolerance


func _check_track_count(visual: EntityVisual, animation_name: String, expected: int, message: String) -> void:
    var animation := visual.animation_player.get_animation(animation_name)
    check(animation != null and animation.get_track_count() == expected, message)


func run() -> void:
    root.size = Vector2i(1280, 800)
    game = MAIN.instantiate()
    root.add_child(game)
    game.play_solo()
    game.set_process(false)
    game.sim.ai_enabled = false
    await process_frame
    await process_frame
    game._sync_visuals()

    var soldier_visual: EntityVisual = game.unit_visuals[3].visual
    check(soldier_visual.kind == "soldier", "Soldier uses the 3D model visual")
    check(soldier_visual.owner_id == 1, "Soldier visual records blue ownership")
    check(_has_animations(soldier_visual.get_animation_names(), ["idle", "move", "attack"]), "Soldier exposes state animations")
    _check_track_count(soldier_visual, "idle", 2, "Soldier idle animation keeps both tracks")
    _check_track_count(soldier_visual, "move", 5, "Soldier move animation keeps all limb tracks")
    _check_track_count(soldier_visual, "attack", 3, "Soldier attack animation keeps recoil tracks")
    check(soldier_visual.model.find_children("*", "MeshInstance3D", true, false).size() <= 12, "Optimized soldier keeps at most 12 mesh nodes")

    game.sim.units[3].order = "move"
    game.sim.units[3].target = Vector2(800, 300)
    game._sync_units()
    check(soldier_visual.animation_state == "move", "Soldier move order plays move animation")

    game.sim.units[3].order = "attack"
    game.sim.units[3].attack_kind = "building"
    game.sim.units[3].attack_id = 2
    game._sync_units()
    check(soldier_visual.animation_state == "move", "Soldier chasing a distant target plays move animation")

    game.sim.units[3].pos = Vector2(4300, 2700)
    game._sync_units()
    check(soldier_visual.animation_state == "attack", "Soldier in building range plays attack animation")

    var ore_id := 1
    var harvester_id: int = game.sim.add_unit(1, "harvester", game.sim.ores[ore_id].pos)
    game.sim.units[harvester_id].order = "gather"
    game.sim.units[harvester_id].ore = ore_id
    game._sync_units()
    var harvester_visual: EntityVisual = game.unit_visuals[harvester_id].visual
    check(_has_animations(harvester_visual.get_animation_names(), ["idle", "move", "mine", "unload"]), "Harvester exposes state animations")
    _check_track_count(harvester_visual, "idle", 2, "Harvester idle animation keeps both tracks")
    _check_track_count(harvester_visual, "move", 11, "Harvester move animation keeps wheel and hull tracks")
    _check_track_count(harvester_visual, "mine", 3, "Harvester mine animation keeps drill tracks")
    _check_track_count(harvester_visual, "unload", 3, "Harvester unload animation keeps cargo tracks")
    check(harvester_visual.model.find_children("*", "MeshInstance3D", true, false).size() <= 22, "Optimized harvester keeps at most 22 mesh nodes")
    check(harvester_visual.animation_state == "mine", "Harvester at ore plays mine animation")

    var refinery_id: int = game.sim._add_building(1, "refinery", Vector2(960, 960), true)
    game.sim.units[harvester_id].pos = Vector2(960, 990)
    game.sim.units[harvester_id].cargo = 60
    game._sync_units()
    check(harvester_visual.animation_state == "unload", "Full harvester at refinery plays unload animation")
    check(game.unit_visuals[harvester_id].cargo_bar.visible, "Cargo bar is visible while carrying ore")

    game.sim.units[harvester_id].cargo = 0
    game._sync_units()
    check(not game.unit_visuals[harvester_id].cargo_bar.visible, "Cargo bar hides after unloading")

    var barracks_id: int = game.sim._add_building(1, "barracks", Vector2(960, 760), false)
    game._sync_buildings()
    var refinery_visual: EntityVisual = game.building_visuals[refinery_id].visual
    var refinery_box := _visual_world_aabb(refinery_visual)
    check(_fits_footprint(refinery_box, Sim.BUILD_TYPES.refinery.size), "Completed refinery stays within its 80x80 visual footprint")
    var barracks_visual: EntityVisual = game.building_visuals[barracks_id].visual
    barracks_visual.animation_player.seek(1.0, true)
    await process_frame
    var construction_box := _visual_world_aabb(barracks_visual)
    check(_fits_footprint(construction_box, Sim.BUILD_TYPES.barracks.size), "Construction animation never double-scales the model")
    check(barracks_visual.animation_state == "construction", "Unfinished building plays construction animation")
    game.sim.buildings[barracks_id].remaining = 0
    game.sim.buildings[barracks_id].queue.append({"type": "soldier", "remaining": 1})
    game._sync_buildings()
    var completed_barracks_box := _visual_world_aabb(barracks_visual)
    check(_fits_footprint(completed_barracks_box, Sim.BUILD_TYPES.barracks.size), "Completed barracks stays within its 64x64 visual footprint")
    check(barracks_visual.animation_state == "active", "Building with queue plays active animation")

    var bunker_id: int = game.sim._add_building(1, "bunker", Vector2(1150, 760), true)
    game.sim.buildings[bunker_id].cooldown = 10
    game._sync_buildings()
    var bunker_visual: EntityVisual = game.building_visuals[bunker_id].visual
    check(bunker_visual.animation_state == "fire", "Bunker cooldown plays fire animation")

    check(game.ore_visuals.size() == game.sim.ores.size(), "Every ore has a 3D visual")
    check(game.rock_visuals.size() > 0, "Rock obstacles use 3D rock models")
    game.sim.explored[1].fill(1)
    game._sync_rocks()
    check(game.rock_visuals.all(func(visual: EntityVisual) -> bool: return visual.visible), "Explored rocks become visible")

    var rock_transforms: Array[Vector3] = []
    for visual: EntityVisual in game.rock_visuals:
        rock_transforms.append(Vector3(visual.position.x, visual.position.z, visual.scale.x))
    for visual: EntityVisual in game.rock_visuals:
        visual.free()
    game.rock_visuals.clear()
    game._sync_rocks()
    var regenerated_transforms: Array[Vector3] = []
    for visual: EntityVisual in game.rock_visuals:
        regenerated_transforms.append(Vector3(visual.position.x, visual.position.z, visual.scale.x))
    check(rock_transforms == regenerated_transforms, "Rock decoration transforms are deterministic")

    game._begin_build("barracks")
    game._sync_build_preview()
    var barracks_size: Vector2 = Sim.BUILD_TYPES.barracks.size
    check(game.build_preview_model != null and game.build_preview_model.kind == "barracks", "Build preview uses the barracks 3D model")
    check(is_equal_approx(game.build_preview_visual.scale.x, barracks_size.x / 100.0) and is_equal_approx(game.build_preview_visual.scale.z, barracks_size.y / 100.0), "Barracks preview matches its 64x64 footprint")

    game._begin_build("refinery")
    game._sync_build_preview()
    var refinery_size: Vector2 = Sim.BUILD_TYPES.refinery.size
    check(game.build_preview_model != null and game.build_preview_model.kind == "refinery", "Build preview uses the refinery 3D model")
    check(is_equal_approx(game.build_preview_visual.scale.x, refinery_size.x / 100.0) and is_equal_approx(game.build_preview_visual.scale.z, refinery_size.y / 100.0), "Refinery preview matches its 80x80 footprint")

    print("VISUAL_MODELS_TEST failures=", failures)
    quit(0 if failures.is_empty() else 1)
