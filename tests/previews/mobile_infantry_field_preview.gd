extends Node3D

var game: Node3D
var preview_models: Array[Node3D] = []
var capture_ready := false


func _ready() -> void:
	get_viewport().msaa_3d = Viewport.MSAA_4X
	game = load("res://scenes/main.tscn").instantiate()
	game.selected_map_id = "desert_sample"
	add_child(game)
	game.set_process(false)
	game.play_solo()
	game.set_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	for child in game.get_children():
		if child is CanvasLayer:
			child.hide()
	var scene := load("res://assets/models/units/mobile_infantry/mobile_infantry.glb") as PackedScene
	var center := Vector2(2320, 2180)
	for index in range(3):
		var model := scene.instantiate() as Node3D
		add_child(model)
		var mesh_instance := model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var box := mesh_instance.get_aabb()
		var scale_factor := 68.0 / box.size.y
		model.scale = Vector3.ONE * scale_factor
		var point := center + Vector2((index - 1) * 100, 0)
		model.position = Vector3(point.x, game.sim.terrain.height_at(point) - box.position.y * scale_factor, point.y)
		model.rotation.y = PI + float(index - 1) * 0.35
		preview_models.append(model)
		if index == 2:
			for surface in range(mesh_instance.mesh.get_surface_count()):
				var source := mesh_instance.mesh.surface_get_material(surface) as StandardMaterial3D
				if "Faction" in source.resource_name:
					var red := source.duplicate() as StandardMaterial3D
					red.albedo_color = Color(0.40, 0.022, 0.013)
					mesh_instance.set_surface_override_material(surface, red)
	game.camera_controller.focus = center
	game.camera_zoom_level = 1.0
	game._update_camera_transform()
	for index in range(12):
		await get_tree().process_frame
	capture_ready = true
	print("MOBILE_INFANTRY_FIELD ", await capture_review())


func capture_review() -> Dictionary:
	var path := "res://assets/concept_art/mobile_infantry/"
	game.camera_zoom_level = 1.0
	game._update_camera_transform()
	await RenderingServer.frame_post_draw
	var normal := get_viewport().get_texture().get_image()
	var normal_error := normal.save_png(path + "mobile-infantry-game-scale-v3.png")
	var screen: Vector2 = game.camera.unproject_position(preview_models[1].position + Vector3(0, 34, 0))
	var rect := Rect2i(Vector2i(screen) - Vector2i(110, 110), Vector2i(220, 220))
	rect = rect.intersection(Rect2i(Vector2i.ZERO, normal.get_size()))
	var crop_error := normal.get_region(rect).save_png(path + "mobile-infantry-game-crop-v3.png")
	game.camera_zoom_level = 2.0
	game._update_camera_transform()
	await RenderingServer.frame_post_draw
	var zoom_error := get_viewport().get_texture().get_image().save_png(path + "mobile-infantry-game-close-v3.png")
	var mesh_instance := preview_models[1].find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var triangles := 0
	for surface in range(mesh_instance.mesh.get_surface_count()):
		triangles += mesh_instance.mesh.surface_get_array_index_len(surface) / 3
	return {"normal": normal_error, "crop": crop_error, "close": zoom_error, "display_height": 68, "fov": game.camera.fov, "pitch": 42, "triangles": triangles}
