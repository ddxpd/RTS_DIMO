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


func _ring_contains_footprint(visual: EntityVisual, footprint: Vector2) -> bool:
    if visual.selection_ring == null or not visual.selection_ring.mesh is TorusMesh:
        return false
    var torus := visual.selection_ring.mesh as TorusMesh
    var half_diagonal := sqrt(pow(footprint.x * 0.5, 2.0) + pow(footprint.y * 0.5, 2.0))
    return visual._selection_ring_radius * torus.outer_radius >= half_diagonal


func _check_base(visual: EntityVisual) -> void:
    check(visual.model.get_node_or_null("base/RadarDish") == null, "Base no longer contains the old radar")
    check(visual.model.get_node_or_null("base/Hologram") == null, "Base no longer contains the old hologram")
    check(_has_animations(visual.get_animation_names(), ["idle", "construction"]), "Base exposes construction and idle")
    var clip := visual.animation_player.get_animation("construction")
    check(clip.loop_mode == Animation.LOOP_NONE and is_equal_approx(clip.length, 1.0), "Base construction is normalized and non-looping")
    visual.set_animation("construction")
    var stage_names := ["BaseFoundation", "BaseRing_0", "BaseRing_1", "BaseRing_2", "BaseRing_3", "BaseTower", "BaseCrown"]
    var boundaries := [0.12, 0.24, 0.36, 0.48, 0.60, 0.82, 0.95]
    for i in range(stage_names.size()):
        visual.set_construction_progress(float(boundaries[i]), 7.0)
        for j in range(stage_names.size()):
            var node := visual.model.get_node("base/" + str(stage_names[j])) as Node3D
            check(is_zero_approx(node.position.y) if j <= i else node.position.y < -0.1, "Base stage %d restores finished modules and keeps later ones underground (%d)" % [i, j])
        check(is_zero_approx(visual.base_windows_power), "Base construction keeps window power off")
    visual.set_construction_progress(0.70, 7.0)
    check(is_equal_approx(visual.animation_player.speed_scale, 1.0 / 7.0), "Base construction maps to seven seconds")
    # Jumping backwards must restore the earlier construction state too.
    visual.set_construction_progress(0.0, 7.0)
    check((visual.model.get_node("base/BaseTower") as Node3D).position.y < -2.0, "Base supports backward construction seeks")
    visual.set_animation("idle")
    for node_name: String in stage_names:
        check((visual.model.get_node("base/" + node_name) as Node3D).position.is_equal_approx(Vector3.ZERO), "Base completion resets " + node_name)
    var bounds := _visual_world_aabb(visual)
    check(_fits_footprint(bounds, Vector2(160, 160), 0.1), "Base model fits its 5x5 footprint")
    check(bounds.end.y <= visual.get_model_height() + 0.1, "Base health bar anchor clears the tower roof")
    var lights: Array[StandardMaterial3D] = []
    for i in range(6):
        var node := visual.model.get_node("base/BaseTower/TowerLight_%d" % i) as MeshInstance3D
        lights.append(node.get_active_material(0))
        if i > 0:
            var previous := visual.model.get_node("base/BaseTower/TowerLight_%d" % (i - 1)) as Node3D
            check(previous.position.y > node.position.y, "Base lamps are ordered top to bottom")
    for i in range(6):
        visual.animation_player.seek(float(i) * 0.32 + 0.12, true)
        for j in range(6):
            check(lights[j].emission_energy_multiplier > 2.0 if i == j else is_zero_approx(lights[j].emission_energy_multiplier), "Base scan lights only segment %d at phase %d" % [j, i])
    visual.animation_player.seek(2.1, true)
    check(lights.all(func(mat: StandardMaterial3D) -> bool: return is_zero_approx(mat.emission_energy_multiplier)), "Base scan pauses with all lamps off")
    visual.animation_player.seek(0.12, true)
    var other := EntityVisual.new("base", 2)
    game.add_child(other)
    other.animation_player.seek(0.44, true)
    var other_top := (other.model.get_node("base/BaseTower/TowerLight_0") as MeshInstance3D).get_active_material(0) as StandardMaterial3D
    check(other_top != lights[0], "Two bases have independent light materials")
    check(is_zero_approx(other_top.emission_energy_multiplier) and lights[0].emission_energy_multiplier > 2.0, "Two bases keep independent scan phases")
    other.free()
    visual.set_faction(2)
    check(lights[0].emission.r > lights[0].emission.b, "Base tower light switches to red faction")
    var window_count := 0
    for entry: Dictionary in visual._base_light_materials:
        if int(entry.tower_index) < 0:
            window_count += 1
            var mat: StandardMaterial3D = entry.material
            check(mat.emission.r > mat.emission.b and mat.emission_energy_multiplier > 0.0, "Base windows stay lit in red faction")
    check(window_count == 5, "Base has four ring window groups and one command-window group")
    visual.set_flash(true)
    check(lights[0].emission_energy_multiplier > 2.0 and is_zero_approx(lights[1].emission_energy_multiplier), "Damage tint preserves the active scan segment")
    visual.set_flash(false)
    visual.set_faction(1)
    check(lights[0].emission.b > lights[0].emission.r, "Base tower light switches back to blue faction")


func _check_track_count(visual: EntityVisual, animation_name: String, expected: int, message: String) -> void:
    var animation := visual.animation_player.get_animation(animation_name)
    check(animation != null and animation.get_track_count() == expected, message)


func _has_track(visual: EntityVisual, animation_name: String, expected_path: String, message: String) -> void:
    var animation := visual.animation_player.get_animation(animation_name)
    if animation == null:
        check(false, message)
        return
    for track_index: int in range(animation.get_track_count()):
        if String(animation.track_get_path(track_index)) == expected_path:
            check(true, message)
            return
    check(false, message)


func _check_visual_forward(visual: EntityVisual, heading: Vector2, message: String) -> void:
    visual.set_heading(heading)
    visual._process(1.0)
    var forward := visual.get_visual_forward()
    check(forward.is_equal_approx(Vector3(heading.x, 0, heading.y)), message)


func _check_attack_recoil(visual: EntityVisual, node_name: String, message: String) -> void:
    var animation := visual.animation_player.get_animation("attack")
    var expected_path := "soldier/%s:position" % node_name
    for track_index: int in range(animation.get_track_count()):
        if String(animation.track_get_path(track_index)) != expected_path:
            continue
        check(animation.track_get_key_count(track_index) == 3, "%s attack key count matches" % node_name)
        var first: Vector3 = animation.track_get_key_value(track_index, 0)
        var recoil: Vector3 = animation.track_get_key_value(track_index, 1)
        var last: Vector3 = animation.track_get_key_value(track_index, 2)
        check(first.z > recoil.z and is_equal_approx(first.z, last.z), message)
        return
    check(false, "%s attack recoil track exists" % node_name)


func _check_faction_materials_on_shoulders(visual: EntityVisual) -> void:
    var faction_meshes := 0
    for node: Node in visual.model.find_children("*", "MeshInstance3D", true, false):
        var mesh_instance := node as MeshInstance3D
        for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
            var material := mesh_instance.get_active_material(surface_index)
            if material == null or "Faction" not in material.resource_name:
                continue
            faction_meshes += 1
            check(mesh_instance.get_parent().name in ["Shoulder_L", "Shoulder_R"], "Soldier team marking stays on the shoulders")
    check(faction_meshes == 2, "Soldier exposes exactly two shoulder team markings")


func _check_attack_muzzle_forward(visual: EntityVisual, heading: Vector2, message: String) -> void:
    visual.set_heading(heading)
    visual._process(1.0)
    visual.set_animation("attack")
    visual.animation_player.seek(0.0, true)
    var muzzle := visual.model.get_node("soldier/Muzzle") as Node3D
    var flat_muzzle := Vector3(muzzle.position.x, 0, muzzle.position.z)
    var muzzle_direction := (visual.global_transform.basis * flat_muzzle).normalized()
    check(muzzle.position.z > 0.9, "Attack muzzle keeps its local +Z position")
    check(muzzle_direction.dot(Vector3(heading.x, 0, heading.y)) > 0.7, message)


func run() -> void:
    root.size = Vector2i(1280, 800)
    game = MAIN.instantiate()
    game.selected_map_id = "prototype"
    root.add_child(game)
    game.play_solo()
    game.set_process(false)
    game.sim.ai_enabled = false
    await process_frame
    await process_frame
    game._sync_visuals()

    var health_overlay = game.health_grid_overlay
    check(health_overlay != null, "Health bars use the 2D HUD overlay")
    check(not game.unit_visuals[3].has("hp_bar"), "Soldier no longer owns a 3D health bar")
    check(not game.building_visuals[1].has("hp_bar"), "Building no longer owns a 3D health bar")
    var soldier_health: Dictionary = health_overlay.entries["unit_3"]
    var base_health: Dictionary = health_overlay.entries["building_1"]
    check(int(soldier_health.cell_count) == 10, "100 HP soldier uses ten health cells")
    check(int(base_health.cell_count) == 80, "800 HP base uses eighty health cells")
    game.sim.units[3].hp = 25
    game._sync_units()
    soldier_health = health_overlay.entries["unit_3"]
    var soldier_fractions: Array = soldier_health.cell_fractions
    check(
        is_equal_approx(float(soldier_fractions[0]), 1.0)
        and is_equal_approx(float(soldier_fractions[1]), 1.0)
        and is_equal_approx(float(soldier_fractions[2]), 0.5),
        "Health cells partially fill the final ten-point segment"
    )
    var projected_health_position: Vector2 = game.camera.unproject_position(soldier_health.world_position)
    check(soldier_health.screen_position.is_equal_approx(projected_health_position), "Health grid tracks the 3D camera projection")
    game.sim.units[3].hp = 100
    game._sync_units()

    var soldier_visual: EntityVisual = game.unit_visuals[3].visual
    game.selected_units.clear()
    game.selected_units.append(3)
    game._sync_units()
    check(soldier_visual.selection_ring != null and soldier_visual.selection_ring.visible, "Selected soldier shows a ground ring")
    var soldier_ring_material := soldier_visual.selection_ring.material_override as StandardMaterial3D
    check(
        soldier_ring_material != null
        and soldier_ring_material.albedo_color.g > soldier_ring_material.albedo_color.r * 1.5,
        "Selection ring uses a fixed bright green material"
    )
    var static_ring_scale := soldier_visual.selection_ring.scale
    var static_ring_energy := soldier_ring_material.emission_energy_multiplier
    soldier_visual._process(1.0)
    check(soldier_visual.selection_ring.scale.is_equal_approx(static_ring_scale), "Selection ring scale stays static while selected")
    check(is_equal_approx(soldier_ring_material.emission_energy_multiplier, static_ring_energy), "Selection ring brightness stays static while selected")
    check(
        is_equal_approx(
            soldier_visual._selection_ring_radius,
            float(Sim.UNIT_TYPES.soldier.radius) * game.visual_sync.SELECTION_RING_PROFILES.soldier.radius_multiplier
        ),
        "Soldier selection radius comes from the per-kind profile"
    )
    game.selected_units.append(4)
    game._sync_units()
    check((game.unit_visuals[4].visual as EntityVisual).selection_ring.visible, "Multi-selection shows a ring for each soldier")
    game.selected_units.clear()
    game.selected_building = 1
    game.selected_buildings.append(1)
    game._sync_buildings()
    var base_visual: EntityVisual = game.building_visuals[1].visual
    check(base_visual.selection_ring.visible, "Selected building shows a ground ring")
    check(_ring_contains_footprint(base_visual, Sim.BUILD_TYPES.base.size), "Base selection ring contains the complete footprint")
    _check_base(base_visual)

    var pending_selection_visual := EntityVisual.new("bunker", 1)
    pending_selection_visual.set_selected(true, 50.0)
    root.add_child(pending_selection_visual)
    await process_frame
    check(
        pending_selection_visual.selection_ring != null and pending_selection_visual.selection_ring.visible,
        "Selection requested before ready still creates a visible ring"
    )
    pending_selection_visual.queue_free()

    game._clear_selection()
    game._sync_units()
    game._sync_buildings()
    check(not soldier_visual.selection_ring.visible, "Clearing selection hides the ground ring")

    check(soldier_visual.kind == "soldier", "Soldier uses the 3D model visual")
    check(soldier_visual.owner_id == 1, "Soldier visual records blue ownership")
    check(_has_animations(soldier_visual.get_animation_names(), ["idle", "move", "attack"]), "Soldier exposes state animations")
    _check_track_count(soldier_visual, "idle", 2, "Soldier idle animation keeps both tracks")
    _check_track_count(soldier_visual, "move", 5, "Soldier move animation keeps all limb tracks")
    _check_track_count(soldier_visual, "attack", 3, "Soldier attack animation keeps recoil tracks")
    check(soldier_visual.model.find_children("*", "MeshInstance3D", true, false).size() <= 12, "Optimized soldier keeps at most 12 mesh nodes")
    check(soldier_visual.model.get_node_or_null("soldier/ArmorCore") != null, "Soldier exposes the simplified armor core")
    check(soldier_visual.model.get_node_or_null("soldier/Shoulder_L") != null, "Soldier exposes the left shoulder rig")
    check(soldier_visual.model.get_node_or_null("soldier/Shoulder_R") != null, "Soldier exposes the right shoulder rig")
    _check_faction_materials_on_shoulders(soldier_visual)
    _check_visual_forward(soldier_visual, Vector2.RIGHT, "Soldier faces east when moving east")
    _check_visual_forward(soldier_visual, Vector2.LEFT, "Soldier faces west when moving west")
    _check_visual_forward(soldier_visual, Vector2.DOWN, "Soldier faces south when moving south")
    _check_visual_forward(soldier_visual, Vector2.UP, "Soldier faces north when moving north")
    _check_attack_recoil(soldier_visual, "Weapon", "Soldier weapon attack track exists")
    _check_attack_recoil(soldier_visual, "Muzzle", "Soldier muzzle attack track exists")
    _check_attack_muzzle_forward(soldier_visual, Vector2.RIGHT, "Attacking soldier aims east")
    _check_attack_muzzle_forward(soldier_visual, Vector2.LEFT, "Attacking soldier aims west")
    _check_attack_muzzle_forward(soldier_visual, Vector2.DOWN, "Attacking soldier aims south")
    _check_attack_muzzle_forward(soldier_visual, Vector2.UP, "Attacking soldier aims north")

    game.sim.effects = [{
        "from": Vector2(640, 256),
        "to": Vector2(760, 256),
        "life": 5,
        "kind": "shot",
        "owner": 1,
        "frame": game.sim.frame
    }]
    game._sync_effects()
    check(game.effect_visuals.size() == 1, "Shot effect creates one projectile visual")
    var bullet_visual := game.effect_visuals.values()[0] as Node3D
    check(bullet_visual != null and not bullet_visual is Sprite3D, "Shot effect uses a 3D projectile model")
    check(bullet_visual.get_node_or_null("bullet/EnergyCore") != null, "Projectile exposes the energy core mesh")
    var bullet_direction := Vector3(1, 0, 0)
    check(bullet_visual.global_transform.basis.z.dot(bullet_direction) > 0.85, "Projectile points along its flight direction")
    game.sim.effects.clear()
    game._sync_effects()
    check(game.effect_visuals.is_empty(), "Projectile visual is removed when the shot expires")

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
    var attack_target: Vector2 = game.sim.buildings[2].pos
    var attack_origin: Vector2 = game.sim.units[3].pos
    var attack_direction := (attack_target - attack_origin).normalized()
    _check_visual_forward(soldier_visual, attack_direction, "Soldier body faces the attacked building")
    _check_attack_muzzle_forward(soldier_visual, attack_direction, "Soldier rifle points at the attacked building")

    game.sim.units[3].order  = "attack_move"
    game.sim.units[3].target = Vector2(800, 300)
    game._sync_units()
    check(soldier_visual.animation_state == "attack", "Engaged attack-move plays attack animation in range")
    _check_visual_forward(soldier_visual, attack_direction, "Engaged attack-move faces its temporary target")
    game.sim.units[3].attack_kind = ""
    game.sim.units[3].attack_id   = -1
    game._sync_units()
    check(soldier_visual.animation_state == "move", "Attack-move resumes move animation after releasing its target")
    var resume_target: Vector2 = game.sim.units[3].target
    var resume_origin: Vector2 = game.sim.units[3].pos
    var resume_direction := (resume_target - resume_origin).normalized()
    _check_visual_forward(soldier_visual, resume_direction, "Resumed attack-move faces its original destination")

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
    _check_visual_forward(harvester_visual, Vector2(0.6, 0.8).normalized(), "Harvester drill faces its travel direction")
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
    game.selected_building = refinery_id
    game.selected_buildings.clear()
    game.selected_buildings.append(refinery_id)
    game._sync_buildings()
    check(_ring_contains_footprint(refinery_visual, Sim.BUILD_TYPES.refinery.size), "Refinery selection ring contains the complete footprint")
    var barracks_visual: EntityVisual = game.building_visuals[barracks_id].visual
    game.selected_building = barracks_id
    game.selected_buildings.clear()
    game.selected_buildings.append(barracks_id)
    game._sync_buildings()
    check(_ring_contains_footprint(barracks_visual, Sim.BUILD_TYPES.barracks.size), "Barracks selection ring contains the complete footprint")
    var barracks_animation := barracks_visual.animation_player.get_animation("construction")
    check(barracks_animation.loop_mode == Animation.LOOP_NONE, "Construction animation does not loop")
    check(is_equal_approx(barracks_animation.length, 1.0), "Construction animation is normalized")
    check(is_equal_approx(barracks_visual.animation_player.speed_scale, 0.25), "Barracks construction animation matches its four-second build time")
    game.sim.buildings[barracks_id].remaining = Sim.BUILD_TYPES.barracks.time / 2
    game._sync_buildings()
    check(is_equal_approx(barracks_visual.animation_player.current_animation_position, 0.5), "Construction animation seeks to the current build progress")
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

    var construction_cases := [
        {"kind": "refinery", "position": Vector2(1250, 900)},
        {"kind": "bunker", "position": Vector2(1450, 1050)},
        {"kind": "base", "position": Vector2(1650, 1200)}
    ]
    var bunker_construction_id := -1
    for case: Dictionary in construction_cases:
        var kind := str(case.kind)
        var case_time: int = Sim.BUILD_TYPES[kind].time
        var case_id: int = game.sim._add_building(1, kind, case.position, false)
        if kind == "bunker":
            bunker_construction_id = case_id
        game.sim.buildings[case_id].remaining = case_time / 2
        game._sync_buildings()
        var case_visual: EntityVisual = game.building_visuals[case_id].visual
        var expected_speed := 1.0 / (float(case_time) / float(Sim.TICK))
        check(case_visual.animation_state == "construction", "%s receives a construction animation" % kind)
        check(is_equal_approx(case_visual.animation_player.speed_scale, expected_speed), "%s construction animation matches its build time" % kind)
        check(is_equal_approx(case_visual.animation_player.current_animation_position, 0.5), "%s construction animation starts at snapshot progress" % kind)

    var bunker_construction_visual: EntityVisual = game.building_visuals[bunker_construction_id].visual
    var bunker_body := bunker_construction_visual.model.get_node("bunker/BunkerBody") as Node3D
    var bunker_lights := bunker_construction_visual.model.get_node("bunker/FactionLights") as Node3D
    check(bunker_body.position.y < -0.20, "Bunker construction keeps the body below ground at mid-progress")
    check(bunker_lights.position.y < -0.20, "Bunker construction keeps the warning lights with the body")
    _has_track(bunker_construction_visual, "construction", "bunker/FactionLights:position", "Bunker construction raises the warning lights")
    game.sim.buildings[bunker_construction_id].remaining = 0
    game._sync_buildings()
    check(bunker_construction_visual.animation_state == "idle", "Completed bunker returns to idle animation")
    check(bunker_body.position.is_equal_approx(Vector3.ZERO), "Completed bunker restores the body base position")

    var bunker_id: int = game.sim._add_building(1, "bunker", Vector2(1150, 760), true)
    game.sim.buildings[bunker_id].cooldown = 10
    game._sync_buildings()
    var bunker_visual: EntityVisual = game.building_visuals[bunker_id].visual
    game.selected_building = bunker_id
    game.selected_buildings.clear()
    game.selected_buildings.append(bunker_id)
    game._sync_buildings()
    check(_ring_contains_footprint(bunker_visual, Sim.BUILD_TYPES.bunker.size), "Bunker selection ring contains the complete footprint")
    var completed_bunker_lights := bunker_visual.model.get_node("bunker/FactionLights") as Node3D
    check(bunker_lights.position.is_equal_approx(completed_bunker_lights.position), "Completed bunker restores the warning light position")
    check(bunker_visual.animation_state == "fire", "Bunker cooldown plays fire animation")
    check(bunker_visual.model.get_node_or_null("bunker/Turret/Barrel") != null, "Bunker keeps the single barrel under the turret rig")
    check(bunker_visual.model.get_node_or_null("bunker/Turret/MuzzleFlash") != null, "Bunker exposes a muzzle flash node")
    check(bunker_visual.model.get_node_or_null("bunker/FactionLights/FactionLight_L") != null, "Bunker exposes the left warning light")
    check(bunker_visual.model.get_node_or_null("bunker/FactionLights/FactionLight_R") != null, "Bunker exposes the right warning light")
    _has_track(bunker_visual, "idle", "bunker/Turret:rotation", "Bunker idle scans the turret")
    _has_track(bunker_visual, "idle", "bunker/FactionLights/FactionLight_L:scale", "Bunker idle pulses the left warning light")
    _has_track(bunker_visual, "idle", "bunker/FactionLights/FactionLight_R:scale", "Bunker idle pulses the right warning light")
    _has_track(bunker_visual, "fire", "bunker/Turret/Barrel:position", "Bunker fire recoils the barrel")
    _has_track(bunker_visual, "fire", "bunker/Turret/MuzzleFlash:scale", "Bunker fire pulses the muzzle flash")
    _has_track(bunker_visual, "construction", "bunker/BunkerBody:position", "Bunker construction rises from underground")
    _has_track(bunker_visual, "construction", "bunker/Turret:position", "Bunker construction raises the turret")
    _has_track(bunker_visual, "construction", "bunker/FactionLights/FactionLight_L:scale", "Bunker construction enables the left warning light")

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

    game._begin_build("base")
    game._sync_build_preview()
    check(game.build_preview_model.kind == "base", "Build preview uses the new command base")
    check(game.build_preview_visual.scale.is_equal_approx(Vector3(1.6, 1, 1.6)), "Base preview matches its 160x160 footprint")
    check(_fits_footprint(_visual_world_aabb(game.build_preview_model), Vector2(160, 160), 0.1), "Base preview model matches the footprint")

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

    preload("res://tests/cursor_checks.gd").visual(game, check)
    print("VISUAL_MODELS_TEST failures=", failures)
    quit(0 if failures.is_empty() else 1)
