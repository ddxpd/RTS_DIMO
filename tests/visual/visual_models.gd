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


func _marker_has_size(visual: EntityVisual, size: Vector2) -> bool:
    if visual.selection_ring == null or not visual.selection_ring.mesh is ArrayMesh:
        return false
    var bounds := visual.selection_ring.mesh.get_aabb()
    return Vector2(bounds.size.x, bounds.size.z).is_equal_approx(size) and bounds.size.y < 0.01


func _check_selection_widths() -> void:
    var building_sizes := {
        "base": Vector2(336, 208), "barracks": Vector2(140, 112),
        "refinery": Vector2(144, 144), "bunker": Vector2(96, 96),
    }
    for building_kind: String in Sim.BUILD_TYPES:
        check(building_sizes.has(building_kind), building_kind + " has a corner marker profile")
    for kind: String in ["soldier", "mobile_infantry", "harvester", "base", "barracks", "refinery", "bunker"]:
        var visual := EntityVisual.new(kind)
        game.add_child(visual)
        var size: Vector2 = Sim.BUILD_TYPES[kind].size if Sim.BUILD_TYPES.has(kind) else Vector2.ZERO
        var radius: float = Sim.UNIT_TYPES[kind].radius if Sim.UNIT_TYPES.has(kind) else maxf(size.x, size.y) * 0.5
        radius = game.visual_sync._selection_ring_radius(kind, radius, size)
        visual.set_selected(true, radius)
        if Sim.BUILD_TYPES.has(kind):
            var marker := visual.selection_ring.mesh
            check(marker is ArrayMesh, kind + " uses corner brackets rather than a circle")
            check(_marker_has_size(visual, building_sizes[kind]), kind + " brackets closely fit the visual footprint")
            check(visual.selection_ring.scale == Vector3.ONE, kind + " bracket stroke is not scaled")
            var arrays := marker.surface_get_arrays(0)
            var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
            var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
            check(vertices.size() == 32 and indices.size() == 72, "Four separate chamfered corners use 24 triangles")
            var half_size: Vector2 = building_sizes[kind] * 0.5
            for vertex in vertices:
                check(absf(vertex.x) >= half_size.x * 0.55 and absf(vertex.z) >= half_size.y * 0.55, kind + " bracket leaves side centers empty")
            check(is_equal_approx(absf(vertices[0].z - vertices[7].z), 2.4), kind + " horizontal stroke stays 2.4")
            check(is_equal_approx(absf(vertices[3].x - vertices[4].x), 2.4), kind + " vertical stroke stays 2.4")
            var other := EntityVisual.new(kind)
            game.add_child(other)
            other.set_selected(true, radius)
            check(other.selection_ring.mesh == marker, kind + " instances share geometry")
            visual.set_selected(true, radius + 20.0)
            check(visual.selection_ring.mesh == marker, kind + " ignores circular radius and reuses geometry")
            visual.set_selected(false)
            check(not visual.selection_ring.visible and other.selection_ring.visible, kind + " selection remains per instance")
            other.queue_free()
            visual.queue_free()
            continue
        var torus := visual.selection_ring.mesh as TorusMesh
        check(is_equal_approx(torus.outer_radius - torus.inner_radius, 1.65), kind + " has fixed world stroke width")
        check(is_equal_approx(torus.outer_radius, radius), kind + " preserves selection radius")
        check(visual.selection_ring.scale == Vector3.ONE, kind + " does not scale the stroke")
        visual.set_selected(true, radius + 20.0)
        check(is_equal_approx(torus.outer_radius - torus.inner_radius, 1.65), kind + " changing radius preserves width")
        visual.set_selected(false, radius)
        check(not visual.selection_ring.visible, kind + " deselection hides ring")
        check(visual.selection_ring.mesh == torus, kind + " reuses selection mesh")
        visual.free()


func _check_base(visual: EntityVisual) -> void:
    check(visual.model is GaiaCommandBase, "Base uses independent GAIA component")
    var gaia := visual.model as GaiaCommandBase
    gaia.automatic_animation = false
    gaia.seek_pose("deployed", 0)
    var box := _visual_world_aabb(visual)
    check(_fits_footprint(box, Sim.BUILD_TYPES.base.size, 0.1), "GAIA fits 320x192 footprint")
    check(box.end.y <= visual.position.y + visual.get_model_height(), "Base anchor clears radar")
    check(absf(box.size.x - 320) < 0.1 and absf(box.size.z - 192) < 0.1, "GAIA fills 10x6 grid footprint: " + str(box.size))
    check(visual.animation_player.get_animation("construction").get_track_count() == 0, "Construction placeholder has no geometry tracks")
    visual.set_animation("construction")
    visual.set_construction_tint(true)
    var armor: StandardMaterial3D = gaia.materials["GAIA_Armor"]
    var dim_color := armor.albedo_color
    for progress in [0.0, 0.5, 1.0, 0.0]:
        visual.set_construction_progress(progress, 7.0)
        check(_visual_world_aabb(visual).is_equal_approx(box), "Construction and reverse seeks retain complete model")
    var other := EntityVisual.new("base", 2)
    game.add_child(other)
    var second := other.model as GaiaCommandBase
    check(second.materials["GAIA_Armor"] != armor, "Base materials isolated between instances")
    visual.set_flash(true)
    check(armor.albedo_color.r > dim_color.r, "Damage flashes construction armor")
    check(not second.flash_enabled, "Damage does not affect second base")
    visual.set_flash(false)
    check(armor.albedo_color.is_equal_approx(dim_color), "Damage restores construction tint")
    visual.set_construction_tint(false)
    visual.set_animation("idle")
    check(armor.albedo_color.r > dim_color.r, "Completion restores armor brightness")
    for owner in [2, 1]:
        visual.set_faction(owner)
        var team: StandardMaterial3D = gaia.materials["GAIA_Team"]
        check(team.emission.is_equal_approx(EntityVisual.TEAM_COLORS[owner]), "Faction refresh uses team palette")
        for level in range(3):
            gaia.forced_lod = level
            gaia.update_lod()
            var visible_count := 0
            for model: Node3D in gaia.models:
                if model.visible:
                    visible_count += 1
                for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
                    for surface in range(mesh.mesh.get_surface_count()):
                        var material := mesh.get_active_material(surface)
                        check(material == gaia.materials[material.resource_name], "LOD shares controlled material instance")
            check(visible_count == 1, "Exactly one base LOD is visible")
    gaia.forced_lod = -1
    gaia.automatic_animation = true
    other.free()


func _check_mobile_barracks(visual: EntityVisual) -> void:
    var names := ["HullMesh", "DoorL", "DoorR", "Ramp", "LiftPodLFront", "LiftPodLRear", "LiftPodRFront", "LiftPodRRear", "LegLFront", "FootLFront"]
    check(visual.model.find_child("BarracksFlag", true, false) == null, "Barracks flag removed")
    for part: String in names:
        check(visual.model.find_child(part, true, false) != null, "V4 barracks has independent part: " + part)
    check(visual.barracks_motion != null, "V4 mechanical player exists")
    var foot := visual.model.find_child("FootLFront", true, false) as Node3D
    visual.barracks_motion.apply({"state": "grounded", "ticks": 0})
    var deployed := foot.position
    visual.barracks_motion.apply({"state": "airborne", "ticks": 0})
    check(absf(foot.position.x) < absf(deployed.x) - 0.5, "Airborne foot retracts inward")
    check(foot.position.y > deployed.y + 0.4, "Airborne foot stores inside chassis")
    check(visual.barracks_motion.body.position.is_zero_approx(), "Root animation does not duplicate simulation lift")
    visual.barracks_motion.apply({"state": "grounded", "ticks": 0})
    visual.set_animation("idle")
    var bounds := _visual_world_aabb(visual)
    check(_fits_footprint(bounds, Sim.BUILD_TYPES.barracks.size, 0.1), "V4 barracks fits 4x3 footprint")
    check(bounds.end.y <= visual.position.y + visual.get_model_height(), "Mobile barracks health anchor clears antennas")
    visual.set_faction(2)
    var painted := 0
    for entry: Dictionary in visual._materials:
        if entry.faction:
            painted += 1
            check(entry.material.albedo_color.r > entry.material.albedo_color.b, "Barracks panels switch to red faction")
    check(painted > 0, "New barracks has faction materials")
    visual.set_faction(1)


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
    var motion = visual.soldier_motion
    motion.attack_blend = 1.0
    motion.shot_age = 1.0
    motion._pose(Vector2.ZERO)
    var first: Vector3 = motion.muzzle.position
    motion.observe_combat(motion.combat_frame + 1, 0)
    motion.observe_combat(motion.combat_frame + 1, 12)
    motion.shot_age = 0.06
    motion._pose(Vector2.ZERO)
    check(motion.muzzle.position.z < first.z, message + " follows weapon bone: " + node_name)
    motion.attack_blend = 0.0
    motion._pose(Vector2.ZERO)


func _check_faction_materials_on_shoulders(visual: EntityVisual) -> void:
    var faction_meshes := 0
    for node: Node in visual.model.find_children("*", "MeshInstance3D", true, false):
        var mesh_instance := node as MeshInstance3D
        for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
            var material := mesh_instance.get_active_material(surface_index)
            if material == null or "Faction" not in material.resource_name:
                continue
            faction_meshes += 1
            check(mesh_instance.skin != null, "Team marking is bound to the skinned soldier")
    check(faction_meshes == 1, "Soldier batches both shoulder markings into one team surface")


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
    game.selected_map_id = "desert_quarry"
    root.add_child(game)
    game.play_solo()
    preload("res://tests/fixtures/army_setup.gd").seed(game.sim)
    game.set_process(false)
    game.sim.ai_enabled = false
    # Retired soldier art remains reviewable; inject it only in this asset test.
    game.sim.units[3].type = "soldier"
    game.visual_sync.reset_world()
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
    _check_selection_widths()
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
    check(base_visual.selection_ring.visible, "Selected base shows corner brackets")
    var bracket_size := base_visual.selection_ring.mesh.get_aabb().size
    check(Vector2(bracket_size.x, bracket_size.z).is_equal_approx(Vector2(336, 208)), "Base selection follows model dimensions with a small gap")
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
    check(soldier_visual.soldier_motion != null, "Soldier has distance-driven locomotion")
    check(soldier_visual.model.find_children("*", "MeshInstance3D", true, false).size() <= 12, "Optimized soldier keeps at most 12 mesh nodes")
    for bone: String in ["Pelvis", "Spine", "Head", "Weapon", "Thigh_L", "Shin_L", "Foot_L", "UpperArm_R", "Forearm_R", "Hand_R"]:
        check(soldier_visual.soldier_motion.bones.has(bone), "Soldier articulates " + bone)
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
    Sim.MiningSystem.request(game.sim, game.sim.units[harvester_id], ore_id)
    game.sim.units[harvester_id].mining.phase = "work"
    game.sim.units[harvester_id].mining.ghost = true
    game._sync_units()
    var harvester_visual: EntityVisual = game.unit_visuals[harvester_id].visual
    check(_has_animations(harvester_visual.get_animation_names(), ["idle", "move", "mine", "unload"]), "Harvester exposes state animations")
    check(harvester_visual.harvester_motion != null, "Harvester has dedicated hover and claw controller")
    check(harvester_visual.model.find_child("Drill", true, false) == null, "Legacy drill is removed")
    check(harvester_visual.model.find_child("LeftWheel_0", true, false) == null, "Legacy wheels are removed")
    check(harvester_visual.harvester_motion.cargo_stage == 0, "Empty harvester has empty transparent bin")
    check(harvester_visual.model.find_children("*", "MeshInstance3D", true, false).size() <= 22, "Optimized harvester keeps at most 22 mesh nodes")
    _check_visual_forward(harvester_visual, Vector2(0.6, 0.8).normalized(), "Harvester arms face its travel direction")
    check(harvester_visual.animation_state == "mine", "Harvester at ore plays mine animation")
    game.sim.units[harvester_id].cargo = 10
    game._sync_units()
    check(harvester_visual.animation_state == "mine", "Partly loaded harvester keeps mining")
    check(harvester_visual.harvester_motion.cargo_stage == 1, "First batch appears inside cargo bin")

    var refinery_id: int = game.sim._add_building(1, "refinery", Vector2(960, 960), true)
    game.sim.units[harvester_id].pos = Vector2(960, 990)
    game.sim.units[harvester_id].cargo = 60
    game._sync_units()
    check(harvester_visual.animation_state == "idle", "Full harvester waits for a real dock reservation")
    check(game.unit_visuals[harvester_id].cargo_bar.visible, "Cargo bar is visible while carrying ore")
    check(harvester_visual.harvester_motion.cargo_stage == 3, "Full cargo shows all three crystal layers")

    game.sim.units[harvester_id].cargo = 0
    game._sync_units()
    check(not game.unit_visuals[harvester_id].cargo_bar.visible, "Cargo bar hides after unloading")
    check(harvester_visual.harvester_motion.cargo_stage == 0, "Unloading clears crystal layers without tipping")

    var barracks_id: int = game.sim._add_building(1, "barracks", Vector2(960, 760), false)
    game._sync_buildings()
    var refinery_visual: EntityVisual = game.building_visuals[refinery_id].visual
    _check_ore_depot(refinery_visual)
    var refinery_box := _visual_world_aabb(refinery_visual)
    check(_fits_footprint(refinery_box, Vector2(128, 128), 0.1), "Completed refinery stays within its 4x4 footprint")
    var relative := refinery_box.position - refinery_visual.global_position
    check(relative.x >= -64.1 and relative.z >= -64.1 and relative.x + refinery_box.size.x <= 64.1 and relative.z + refinery_box.size.z <= 64.1, "All geometry fits the centered square")
    game.selected_building = refinery_id
    game.selected_buildings.clear()
    game.selected_buildings.append(refinery_id)
    game._sync_buildings()
    check(_marker_has_size(refinery_visual, Vector2(144, 144)), "Refinery uses fitted corner brackets")
    var barracks_visual: EntityVisual = game.building_visuals[barracks_id].visual
    game.selected_building = barracks_id
    game.selected_buildings.clear()
    game.selected_buildings.append(barracks_id)
    game._sync_buildings()
    check(_marker_has_size(barracks_visual, Vector2(140, 112)), "Barracks uses fitted corner brackets during construction")
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
    game.sim.buildings[barracks_id].queue.append({"type": "mobile_infantry", "remaining": 1})
    game._sync_buildings()
    var completed_barracks_box := _visual_world_aabb(barracks_visual)
    check(_fits_footprint(completed_barracks_box, Sim.BUILD_TYPES.barracks.size), "Completed barracks stays within its 64x64 visual footprint")
    check(barracks_visual.animation_state == "active", "Building with queue plays active animation")
    _check_mobile_barracks(barracks_visual)

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
    check(_marker_has_size(bunker_visual, Vector2(96, 96)), "Bunker brackets surround its visible base")
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
    check(game.terrain_view != null, "Authored terrain owns rock decoration")
    check(game.terrain_view.rock_material.get_shader_parameter("fog_map") == game.fog_texture, "Terrain rocks share the exploration fog texture")
    var decorations: Array[Transform3D] = []
    for child in game.terrain_view.get_children():
        if child is MultiMeshInstance3D:
            for index in range(child.multimesh.instance_count):
                decorations.append(child.multimesh.get_instance_transform(index))
    check(not decorations.is_empty(), "Desert has instanced rock decoration")
    var repeated := preload("res://scripts/maps/terrain_view.gd").new()
    repeated.build(game.sim.terrain, game.fog_texture)
    var regenerated: Array[Transform3D] = []
    for child in repeated.get_children():
        if child is MultiMeshInstance3D:
            for index in range(child.multimesh.instance_count):
                regenerated.append(child.multimesh.get_instance_transform(index))
    check(decorations == regenerated, "Desert decoration transforms are deterministic")
    repeated.free()

    game._begin_build("base")
    game.visual_sync._sync_build_preview(Vector2(512, 512))
    check(game.build_preview_model.kind == "base", "Build preview uses the new command base")
    check(game.visual_sync.footprint_overlay.footprint.size == Sim.BUILD_TYPES.base.size and game.visual_sync.footprint_overlay.dimensions == Vector2i(10, 6), "Base preview matches its 10x6 footprint")
    check(_fits_footprint(_visual_world_aabb(game.build_preview_model), Sim.BUILD_TYPES.base.size, 0.1), "Base preview model matches the footprint")

    game._begin_build("barracks")
    game.visual_sync._sync_build_preview(Vector2(512, 512))
    var barracks_size: Vector2 = Sim.BUILD_TYPES.barracks.size
    check(game.build_preview_model != null and game.build_preview_model.kind == "barracks", "Build preview uses the barracks 3D model")
    check(game.visual_sync.footprint_overlay.footprint.size == barracks_size and game.visual_sync.footprint_overlay.dimensions == Vector2i(4, 3), "Barracks preview matches its 4x3 footprint")

    game._begin_build("refinery")
    game.visual_sync._sync_build_preview(Vector2(512, 512))
    var refinery_size: Vector2 = Sim.BUILD_TYPES.refinery.size
    check(game.build_preview_model != null and game.build_preview_model.kind == "refinery", "Build preview uses the refinery 3D model")
    check(game.visual_sync.footprint_overlay.footprint.size == Vector2(128, 128) and game.visual_sync.footprint_overlay.dimensions == Vector2i(4, 4), "Refinery preview matches its 4x4 footprint")

    preload("res://tests/ui/cursor_checks.gd").visual(game, check)
    preload("res://tests/helpers/soldier_heading_checks.gd").basic(game, check)
    print("VISUAL_MODELS_TEST failures=", failures)
    # Drain deferred selection sounds before freeing the scene and audio mixer.
    game.set_process(false)
    game.audio_controller.reset_state()
    await process_frame
    await create_timer(0.1).timeout
    game.queue_free()
    await process_frame
    await create_timer(0.1).timeout
    quit(0 if failures.is_empty() else 1)


func _check_ore_depot(visual: EntityVisual) -> void:
    var depot: Node3D = visual.model
    check(depot.levels.size() == 3, "Depot provides three real LODs")
    var budget := [24000, 9000, 2500]
    for level in range(3):
        var triangles := 0
        var textured := false
        var glass := false
        for mesh: MeshInstance3D in depot.levels[level].find_children("*", "MeshInstance3D", true, false):
            for surface in range(mesh.mesh.get_surface_count()):
                var arrays := mesh.mesh.surface_get_arrays(surface)
                var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
                triangles += indices.size() / 3 if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size() / 3
                var mat := mesh.get_active_material(surface) as StandardMaterial3D
                if "Armor" in mat.resource_name:
                    textured = textured or mat.albedo_texture != null
                if "Glass" in mat.resource_name:
                    glass = mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and mat.albedo_color.a < 0.25
        check(triangles <= budget[level], "Depot LOD%d geometry stays within budget" % level)
        check(textured and glass, "Depot LOD%d retains PBR textures and transparent glass" % level)
        depot.set_lod(level)
        check(depot.levels[level].visible and not depot.levels[(level + 1) % 3].visible, "Only selected depot LOD is drawn")
    depot.set_lod(0)
    check(depot.lamps[0].size() == 3 and depot.lamps[1].size() == 3, "Both dock indicators survive all LODs")
