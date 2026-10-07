extends SceneTree

const Visual = preload("res://assets/art/entity_visual.gd")
var failures: Array[String] = []
var rifle_vertices := PackedVector3Array()
var minimum_carry_clearance := INF

class FlatGround:
    func height_at(_point: Vector2) -> float:
        return 0.0


class RampGround:
    var slope := .18

    func height_at(point: Vector2) -> float:
        return point.y * slope


func _initialize() -> void:
    run.call_deferred()


func check(value: bool, message: String) -> void:
    if not value and not failures.has(message):
        failures.append(message)
        push_error(message)


func inspect_assets(motion) -> void:
    check(motion.skeleton.get_bone_count() == 20, "Twenty articulated bones")
    var shared_skin: Skin = motion.lod.instance.skin
    for level in 3:
        var mesh: Mesh = motion.lod.meshes[level]
        check(mesh.get_surface_count() == 2, "Exactly two surfaces at every LOD")
        var triangles := 0
        var blended := 0
        for surface in mesh.get_surface_count():
            var arrays := mesh.surface_get_arrays(surface)
            triangles += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
            var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
            for w: float in weights:
                if w > .01 and w < .99:
                    blended += 1
            var material := mesh.surface_get_material(surface) as StandardMaterial3D
            check(material != null and material.albedo_texture != null, "PBR atlas survives import")
            check(material.albedo_texture.get_width() == 1024, "Shared atlas is 1024 square")
            check(material.normal_enabled and material.normal_texture != null, "Normal atlas enabled")
            check(material.roughness_texture != null and material.metallic_texture != null, "ORM channels imported")
            check(material == motion.lod.meshes[0].surface_get_material(surface), "LOD materials and textures share resources")
        check(triangles <= [10000, 3500, 900][level], "LOD triangle budget")
        check(blended > 0, "Soft joints retain blended weights after simplification")
        var source: Node = load(motion.lod.PATHS[level]).instantiate()
        var sk: Skeleton3D = source.find_children("*", "Skeleton3D", true, false)[0]
        var skin: Skin = source.find_children("*", "MeshInstance3D", true, false)[0].skin
        for bone in 20:
            check(sk.get_bone_name(bone) == motion.skeleton.get_bone_name(bone), "LOD skeleton order matches")
            check(sk.get_bone_global_rest(bone).is_equal_approx(motion.rests[bone]), "LOD bind pose matches")
        for binding in shared_skin.get_bind_count():
            check(shared_skin.get_bind_name(binding) == skin.get_bind_name(binding), "LOD skin joint map matches")
            check(shared_skin.get_bind_pose(binding).is_equal_approx(skin.get_bind_pose(binding)), "LOD inverse bind matches")
        var paint := mesh.surface_get_arrays(1)
        var joints: PackedInt32Array = paint[Mesh.ARRAY_BONES]
        var paint_weights: PackedFloat32Array = paint[Mesh.ARRAY_WEIGHTS]
        for index in joints.size():
            if paint_weights[index] > .001:
                check(skin.get_bind_name(joints[index]) in [&"Clavicle_L", &"Clavicle_R"], "Shoulder shell marking follows clavicle, not upper-arm twist")
        source.free()
        print("SOLDIER_LOD level=", level, " triangles=", triangles, " blended_weights=", blended)


func inspect_grip(motion) -> void:
    var weapon: Transform3D = motion.skeleton.get_bone_global_pose(motion.bones.Weapon) * motion.rests[motion.bones.Weapon].affine_inverse()
    for side: String in ["L", "R"]:
        var grip := Vector3(.17, 1.74, .90) if side == "L" else Vector3(.17, 1.73, .52)
        var hand: Vector3 = motion.skeleton.get_bone_global_pose(motion.bones["Hand_" + side]).origin
        check(hand.distance_to(weapon * grip) < .001, "Hand maintains physical rifle contact")
        var upper: int = motion.bones["UpperArm_" + side]
        var elbow: int = motion.bones["Forearm_" + side]
        var wrist: int = motion.bones["Hand_" + side]
        var a: Vector3 = motion.skeleton.get_bone_global_pose(upper).origin
        var b: Vector3 = motion.skeleton.get_bone_global_pose(elbow).origin
        check(absf(a.distance_to(b) - motion.rests[upper].origin.distance_to(motion.rests[elbow].origin)) < .002, "Upper arm never stretches")
        check(absf(hand.distance_to(b) - motion.rests[wrist].origin.distance_to(motion.rests[elbow].origin)) < .002, "Forearm never stretches")
    check(motion.muzzle.position.distance_to(weapon * Vector3(.17, 1.84, 1.36)) < .001, "Muzzle follows the weapon transform")


func inspect_carry_clearance(motion) -> void:
    if rifle_vertices.is_empty():
        var mesh: Mesh = motion.lod.meshes[0]
        var skin: Skin = motion.lod.instance.skin
        for surface in mesh.get_surface_count():
            var arrays := mesh.surface_get_arrays(surface)
            var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
            var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
            var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
            for vertex in vertices.size():
                for weight in 4:
                    var index := vertex * 4 + weight
                    if weights[index] > .99 and skin.get_bind_name(joints[index]) == &"Weapon":
                        rifle_vertices.append(vertices[vertex])
                        break
        check(not rifle_vertices.is_empty(), "Clearance uses the actual rifle mesh")
    # Conservative envelopes from the authored armor, in each bone's bind frame.
    # Unlike a muzzle-only check these include stock, magazine and receiver.
    var envelopes := [
        ["Spine", Vector3(0, 1.94, .055), Vector3(.455, .30, .27)],
        ["Spine", Vector3(0, 2.19, .28), Vector3(.36, .11, .055)],
        ["Spine", Vector3(0, 1.585, .17), Vector3(.275, .115, .07)],
        ["Pelvis", Vector3(0, 1.42, .27), Vector3(.35, .115, .075)]
    ]
    for side: String in ["L", "R"]:
        var x := -.22 if side == "L" else .22
        envelopes.append(["Thigh_" + side, Vector3(x, 1.04, .04), Vector3(.17, .20, .18)])
        envelopes.append(["Shin_" + side, Vector3(x, .73, .20), Vector3(.145, .12, .085)])
        envelopes.append(["Shin_" + side, Vector3(x, .405, .045), Vector3(.16, .175, .18)])
    var weapon: Transform3D = motion.poses[motion.bones.Weapon] * motion.rests[motion.bones.Weapon].affine_inverse()
    for envelope: Array in envelopes:
        var bone: int = motion.bones[envelope[0]]
        var to_bind: Transform3D = motion.rests[bone] * motion.poses[bone].affine_inverse() * weapon
        var center: Vector3 = envelope[1]
        var half_size: Vector3 = envelope[2]
        for vertex: Vector3 in rifle_vertices:
            var outside := (to_bind * vertex - center).abs() - half_size
            var clearance := outside.max(Vector3.ZERO).length() + minf(maxf(outside.x, maxf(outside.y, outside.z)), 0.0)
            minimum_carry_clearance = minf(minimum_carry_clearance, clearance)
            if clearance <= .01 and not failures.has("Vertical rifle clears " + str(envelope[0]) + " armor throughout the run"):
                print("CARRY_CONTACT bone=", envelope[0], " vertex=", vertex, " in_bind=", to_bind * vertex,
                    " clearance=", clearance, " phase=", motion.phase)
            check(clearance > .01, "Vertical rifle clears " + str(envelope[0]) + " armor throughout the run")


func inspect_response(visual: Node3D) -> void:
    var sim := preload("res://scripts/simulation.gd").new()
    sim.reset(false, "prototype")
    sim.units.clear()
    var id: int = sim.add_unit(1, "soldier", Vector2(1200, 1200))
    var u: Dictionary = sim.units[id]
    sim.command(1, {"action": "move", "units": [id], "pos": Vector2(1600, 1200)})
    var start: Vector2 = u.pos
    sim.step()
    check(absf(start.distance_to(u.pos) - 5.0) < .01, "First movement tick uses full 100 units/sec speed")
    sim.command(1, {"action": "move", "units": [id], "pos": Vector2(900, 1200)})
    start = u.pos
    sim.step()
    check(u.pos.x < start.x and absf(start.distance_to(u.pos) - 5.0) < .01, "Reverse order has no turn or acceleration wait")
    sim.command(1, {"action": "stop", "units": [id]})
    start = u.pos
    sim.step()
    check((u.pos as Vector2).is_equal_approx(start), "Stop command has no deceleration travel")
    var enemy: int = sim.add_unit(2, "soldier", u.pos + Vector2(0, 50))
    var motion = visual.soldier_motion
    motion.observe_combat(sim.frame, 0)
    var count_before: int = motion.shot_count
    visual.set_animation("idle")
    motion.attack_blend = 0.0
    sim.command(1, {"action": "attack", "units": [id], "kind": "unit", "target": enemy})
    sim.step()
    check(sim.units[enemy].hp == 84 and u.cooldown == 12, "First attack tick deals damage without raise-gun wait")
    visual.set_animation("attack")
    motion.observe_combat(sim.frame, u.cooldown)
    motion.sample(u.pos, 1.0 / 60.0, sim.frame, 1, sim.terrain, true, Vector2.ZERO, Vector2.DOWN)
    check(motion.shot_count == count_before + 1, "Simulation shot drives presentation immediately")
    check(motion.attack_blend == 1.0, "Real shot interrupts low carry and shoulders the rifle immediately")
    for tick in 11:
        sim.step()
    check(sim.units[enemy].hp == 84, "Shot cooldown remains twelve ticks")
    sim.step()
    check(sim.units[enemy].hp == 68, "Next shot arrives on the unchanged cooldown boundary")


func inspect_running() -> void:
    var visual := Visual.new("soldier", 1)
    root.add_child(visual)
    visual.set_heading(Vector2.DOWN, true)
    visual.set_animation("move")
    var motion = visual.soldier_motion
    var ground := FlatGround.new()
    var flight_samples := 0
    var stance_samples := 0
    var folded_leg := false
    var lowest_pelvis := INF
    var highest_pelvis := -INF
    var highest_heel := 0.0
    var smallest_knee_angle := PI
    for frame in 480:
        motion.sample(Vector2(0, frame * 100.0 / 120.0), 1.0 / 120.0, frame, 1, ground, true, Vector2(0, 100), Vector2.ZERO)
        inspect_grip(motion)
        if frame < 60:
            continue
        inspect_carry_clearance(motion)
        var pelvis_y: float = motion.poses[motion.bones.Pelvis].origin.y
        lowest_pelvis = minf(lowest_pelvis, pelvis_y)
        highest_pelvis = maxf(highest_pelvis, pelvis_y)
        for foot in 2:
            highest_heel = maxf(highest_heel, motion.foot_world(foot).y)
        var weapon: Transform3D = motion.poses[motion.bones.Weapon] * motion.rests[motion.bones.Weapon].affine_inverse()
        var direction := weapon.basis * Vector3.BACK
        var chest_basis: Basis = motion.poses[motion.bones.Spine].basis * motion.rests[motion.bones.Spine].basis.inverse()
        var down := chest_basis * Vector3.DOWN
        check(absf(rad_to_deg(direction.angle_to(down)) - 10.0) < .1, "Running rifle stays ten degrees from the torso's downward axis")
        check(motion.poses[motion.bones.Weapon].origin.y < motion.poses[motion.bones.Clavicle_R].origin.y - .2, "Rifle receiver stays below the shoulders during travel")
        var chest: Transform3D = motion.poses[motion.bones.Spine] * motion.rests[motion.bones.Spine].affine_inverse()
        var stock_in_chest: Vector3 = chest.affine_inverse() * (weapon * Vector3(.17, 1.86, .17))
        check(stock_in_chest.z > .34, "Lowered stock clears the breastplate instead of entering the chest")
        if motion.planted[0]:
            stance_samples += 1
        if not motion.planted[0] and not motion.planted[1]:
            if motion.foot_world(0).y > .1 and motion.foot_world(1).y > .1:
                flight_samples += 1
        for side: String in ["L", "R"]:
            var hip: Vector3 = motion.poses[motion.bones["Thigh_" + side]].origin
            var knee: Vector3 = motion.poses[motion.bones["Shin_" + side]].origin
            var foot: Vector3 = motion.poses[motion.bones["Foot_" + side]].origin
            var angle := acos(clampf((hip - knee).normalized().dot((foot - knee).normalized()), -1, 1))
            folded_leg = folded_leg or angle < deg_to_rad(95.0)
            smallest_knee_angle = minf(smallest_knee_angle, angle)
    check(flight_samples > 110 and flight_samples < 155, "Running flight is visible for about a third of the cycle")
    check(stance_samples > 130 and stance_samples < 165, "Single-foot support occupies about thirty-four percent of the cycle")
    check(folded_leg, "Swing leg folds at the knee")
    check(highest_pelvis - lowest_pelvis > .085, "Running has a visible compression and rebound")
    check(highest_heel > 11.0 and smallest_knee_angle < deg_to_rad(75.0), "Recovery lifts the heel and folds the lower leg")
    for state: String in ["attack", "idle"]:
        visual.set_animation(state)
        for frame in 3:
            motion.sample(Vector2(0, 400), 1.0 / 60.0, 500 + frame, 1, ground, true, Vector2.ZERO, Vector2.ZERO)
            inspect_grip(motion)
        check(is_equal_approx(motion.attack_blend, 1.0 if state == "attack" else 0.0), "Carry/aim transition finishes within fifty milliseconds")
    print("SOLDIER_RUN flight_samples=", flight_samples, " stance_samples=", stance_samples,
        " min_rifle_armor_clearance=", minimum_carry_clearance, " pelvis_range=", highest_pelvis - lowest_pelvis,
        " heel_height=", highest_heel, " knee_angle=", rad_to_deg(smallest_knee_angle))
    motion.observe_combat(600, 0)
    motion.observe_combat(601, 12)
    motion.sample(Vector2(0, 400), 1.0 / 60.0, 601, 1, ground, true, Vector2.ZERO, Vector2.ZERO)
    check(motion.attack_blend == 1.0, "A killing shot remains shouldered even when the order already became idle")
    inspect_grip(motion)
    visual.free()


func inspect_carry_routes() -> void:
    for route: String in ["curve", "uphill", "downhill"]:
        print("CARRY_ROUTE ", route)
        var visual := Visual.new("soldier", 1)
        root.add_child(visual)
        var motion = visual.soldier_motion
        var ground := RampGround.new()
        ground.slope = 0.0 if route == "curve" else .18 if route == "uphill" else -.18
        var position := Vector2.ZERO
        for frame in 180:
            var moving := frame < 90 or frame >= 105
            var heading := Vector2.DOWN.rotated(frame / 60.0 * 100.0 / 50.0) if route == "curve" else Vector2.DOWN
            visual.set_heading(heading, true)
            visual.set_animation("attack" if frame >= 150 else "move" if moving else "idle")
            if moving:
                position += heading * (100.0 / 60.0)
            motion.sample(position, 1.0 / 60.0, frame, 1, ground, true,
                heading * 100.0 if moving else Vector2.ZERO, heading if frame >= 150 else Vector2.ZERO)
            inspect_grip(motion)
            if motion.blend > .99 and motion.attack_blend < .001:
                inspect_carry_clearance(motion)
        check(motion.attack_blend == 1.0, "Moving attack raises the rifle on " + route)
        visual.free()
    print("SOLDIER_CARRY_ROUTES min_rifle_armor_clearance=", minimum_carry_clearance)


func run() -> void:
    var visual := Visual.new("soldier", 1)
    root.add_child(visual)
    var motion = visual.soldier_motion
    var ground := FlatGround.new()
    inspect_assets(motion)
    motion.observe_combat(100, 8)
    check(motion.shot_count == 0, "First snapshot does not replay a historic shot")
    for state: String in ["idle", "move", "attack"]:
        visual.set_animation(state)
        for frame in 120:
            var speed := 100.0 if state == "move" else 0.0
            motion.sample(Vector2(frame * speed / 60.0, 0), 1.0 / 60.0, frame, 1, ground, true, Vector2(speed, 0), Vector2.ZERO)
            inspect_grip(motion)
    check(motion.shot_count == 0 and motion.shot_age > .12, "Attack stance alone never invents shots")
    var before: Vector3 = motion.muzzle.position
    motion.observe_combat(101, 0)
    motion.observe_combat(102, 12)
    for repeat in 5:
        motion.observe_combat(102, 12)
    check(motion.shot_count == 1, "Actual cooldown reset triggers exactly one recoil")
    motion.sample(Vector2.ZERO, .05, 102, 1, ground, true, Vector2.ZERO, Vector2.ZERO)
    check(motion.muzzle.position.z < before.z - .03, "Real shot recoils within the firing frame interval")
    motion.observe_combat(0, 12)
    check(motion.shot_count == 1 and motion.shot_age == 1.0, "World rewind does not replay a shot")
    var skin: Skin = motion.lod.instance.skin
    var faction: Material = motion.lod.instance.get_active_material(1)
    for height: float in [80, 42, 39, 37]:
        motion.lod.select_height(height)
        check(motion.lod.level == 1, "LOD hysteresis holds medium above 36px")
    motion.lod.select_height(35)
    check(motion.lod.level == 2, "Far LOD below hysteresis boundary")
    motion.lod.select_height(43)
    check(motion.lod.level == 2, "Far LOD does not flicker at 40px")
    motion.lod.select_height(45)
    motion.lod.select_height(105)
    check(motion.lod.level == 1, "Medium LOD does not flicker at 100px")
    motion.lod.select_height(111)
    check(motion.lod.level == 0, "Near LOD returns above 110px")
    check(motion.lod.instance.skin == skin and motion.lod.instance.get_active_material(1) == faction, "LOD preserves live skin and team overrides")
    var body := motion.lod.instance.get_active_material(0) as StandardMaterial3D
    var base_tint := body.albedo_color
    visual.set_faction(2)
    check((faction as StandardMaterial3D).albedo_color.r > (faction as StandardMaterial3D).albedo_color.b, "Shared atlas preserves red faction tint")
    visual.set_flash(true)
    motion.lod.select_height(20)
    check(body.albedo_color.r > base_tint.r * 1.8, "Damage flash survives LOD switch with textured body")
    visual.set_flash(false)
    check(body.albedo_color.is_equal_approx(base_tint), "Damage flash restores original body tint")
    visual.set_animation("move")
    for level in 3:
        motion.lod.select_height([150.0, 70.0, 20.0][level])
        var before_solves: int = motion.solve_count
        for frame in 60:
            motion.sample(Vector2(frame * 100.0 / 60.0, 0), 1.0 / 60.0, 200 + frame, 1, ground, true, Vector2(100, 0), Vector2.ZERO)
        var solves: int = motion.solve_count - before_solves
        check(absi(solves - [60, 30, 15][level]) <= 2, "LOD solves at requested frequency")
        print("SOLDIER_POSE_HZ level=", level, " solves=", solves)
    motion.lod.on_screen = false
    var before_solves: int = motion.solve_count
    var before_distance: float = motion.distance
    for frame in 60:
        motion.sample(Vector2(100 + frame * 100.0 / 60.0, 0), 1.0 / 60.0, 300 + frame, 1, ground, true, Vector2(100, 0), Vector2.ZERO)
    check(motion.solve_count == before_solves, "Offscreen units skip skeleton solves")
    check(absf(motion.distance - before_distance - 100.0) < .01, "Offscreen stride distance stays current")
    motion.lod.on_screen = true
    motion.sample(Vector2(200, 0), 1.0 / 60.0, 360, 1, ground, true, Vector2(100, 0), Vector2.ZERO)
    check(motion.solve_count == before_solves + 1 and not motion.replant, "Reappearing unit rebuilds contacts immediately")
    inspect_response(visual)
    visual.free()
    inspect_running()
    inspect_carry_routes()
    print("SOLDIER_RIG ", "PASS" if failures.is_empty() else JSON.stringify(failures))
    quit(0 if failures.is_empty() else 1)
