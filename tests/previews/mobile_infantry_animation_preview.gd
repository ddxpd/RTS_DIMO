extends Node3D

var game: Node3D
var unit_id := -1
var building_id := -1
var elapsed := 0.0
var ticks := 0.0
var stage := 0
var saved: Array[String] = []
var failures: Array[String] = []
var gait_rotation := Quaternion.IDENTITY
var gait_variation := 0.0


func _ready() -> void:
	get_viewport().msaa_3d = Viewport.MSAA_4X
	game = load("res://scenes/main.tscn").instantiate()
	game.selected_map_id = "desert_sample"
	add_child(game)
	game.play_solo()
	game.set_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	game.sim.units.clear()
	unit_id = game.sim.add_unit(1, "mobile_infantry", Vector2(2320, 2180))
	building_id = game.sim._add_building(1, "barracks", Vector2(2160, 2040), true)
	game.sim.rebuild_navigation()
	game.selected_building = building_id
	game.selected_buildings.assign([building_id])
	game.camera_controller.focus = Vector2(2320, 2180)
	game.camera_zoom_level = 3.0
	game._update_camera_transform()
	game.sim.update_visibility()
	game.visual_sync.sync(0.0)
	game._refresh_ui()


func _process(delta: float) -> void:
	if game == null:
		return
	elapsed += delta
	ticks += delta
	while ticks >= 0.05:
		game.sim.step()
		ticks -= 0.05
	game.visual_sync.sync(delta)
	game._refresh_ui()
	if stage == 1 and game.visual_sync.unit_visuals.has(unit_id):
		var motion = game.visual_sync.unit_visuals[unit_id].visual.mobile_motion
		var rotation: Quaternion = motion.skeleton.get_bone_pose_rotation(motion.skeleton.find_bone("thigh.L"))
		if gait_rotation != Quaternion.IDENTITY:
			gait_variation += gait_rotation.angle_to(rotation)
		gait_rotation = rotation
	if stage == 0 and elapsed > 1.0:
		stage = 1
		await capture("idle")
		var error: String = game.sim.command(1, {"action": "move", "units": [unit_id], "pos": Vector2(2600, 2180)})
		if not error.is_empty():
			failures.append(error)
	elif stage == 1 and elapsed > 2.1:
		stage = 2
		if gait_variation < 0.3:
			failures.append("Runtime gait did not animate the thigh")
		await capture("jog")
	elif stage == 2 and elapsed > 4.2:
		game.sim.command(1, {"action": "stop", "units": [unit_id]})
		var enemy: int = game.sim.add_unit(2, "harvester", game.sim.units[unit_id].pos + Vector2(80, 0))
		game.sim.units[enemy].auto = false
		game.sim.update_visibility()
		game.sim.command(1, {"action": "attack", "units": [unit_id], "kind": "unit", "target": enemy})
		game.camera_controller.focus = game.sim.units[unit_id].pos
		game._update_camera_transform()
		stage = 3
	elif stage == 3 and elapsed > 4.9:
		stage = 4
		var motion = game.visual_sync.unit_visuals[unit_id].visual.mobile_motion
		var weapon: Vector3 = motion.skeleton.get_bone_global_pose(motion.skeleton.find_bone("weapon")).origin
		if weapon.y < 1.30:
			failures.append("Runtime firing did not raise the weapon")
		await capture("fire")
	elif stage == 4 and elapsed > 6.0:
		game.sim.units[unit_id].hp = 0
		stage = 5
	elif stage == 5 and elapsed > 6.85:
		stage = 6
		await capture("death")
		if game.sim.units.has(unit_id):
			failures.append("Dead unit still in simulation")
	elif stage == 6 and elapsed > 8.2:
		if not game.visual_sync.mobile_deaths.is_empty():
			failures.append("Corpse not cleaned")
		print("MOBILE_INFANTRY_ANIMATION_REVIEW ", {"saved": saved, "gait_variation": gait_variation, "failures": failures})
		stage = 7
		set_process(false)


func capture(label: String) -> void:
	# Advance the state before awaiting a rendered frame to avoid repeated capture.
	var path := "res://assets/concept_art/mobile_infantry/v6/mobile-infantry-action-" + label + "-v6.png"
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(path)
	if result == OK:
		saved.append(label)
	else:
		failures.append("Capture %s returned %d" % [label, result])
