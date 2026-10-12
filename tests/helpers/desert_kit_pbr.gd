extends "res://tests/helpers/desert_kit_geometry.gd"
## Review-only meshes and portable PBR textures. No production dependencies.

var textured := true
var pbr: Dictionary = {}
var texture_report: Array[Dictionary] = []
var noise := FastNoiseLite.new()


func initialize() -> void:
	noise.seed = 719
	noise.frequency = 0.022
	noise.fractal_octaves = 3


func prepare_textures() -> void:
	for kind in ["sand", "rock", "rubble"]:
		var size := 1024 if kind == "rubble" else 2048
		var n := FastNoiseLite.new()
		n.seed = 761 if kind == "sand" else 189
		n.frequency = 0.002 if kind == "sand" else 0.005
		n.fractal_octaves = 5
		var macro: Image = n.get_seamless_image(size, size, false, false, 0.15, true)
		n.frequency = 0.45 if kind == "sand" else 0.12
		n.seed += 21
		var micro: Image = n.get_seamless_image(size, size, false, false, 0.1, true)
		macro.convert(Image.FORMAT_RF)
		micro.convert(Image.FORMAT_RF)
		var values := macro.get_data().to_float32_array()
		var fine := micro.get_data().to_float32_array()
		var heights := PackedFloat32Array()
		heights.resize(size * size)
		var colors := PackedByteArray()
		var orm := PackedByteArray()
		colors.resize(size * size * 3)
		orm.resize(size * size * 3)
		for y in range(size):
			for x in range(size):
				var i := y * size + x
				var broad := values[i]
				var detail := fine[i]
				var band := sin(TAU * (float(y) / size * (14.0 if kind == "sand" else 9.0) + broad * 0.65))
				var cracks := pow(clampf((0.43 - detail) * 6.0, 0.0, 1.0), 3.0)
				var h := broad * 0.38 + detail * 0.16
				var base := Color(0.64, 0.47, 0.28)
				var shade := broad * 0.32 + detail * 0.12 + 0.68
				if kind == "sand":
					h = broad * 0.12 + detail * 0.025 + band * 0.012
					base = Color(0.67, 0.56, 0.41)
					shade = 0.91 + broad * 0.12 + detail * 0.025 + band * 0.012
				else:
					h += band * 0.13 - cracks * 0.14
					shade += band * 0.11 - cracks * 0.20
				var color := base * shade
				if kind == "rock":
					# Bottom part of the wall UV gradually collects pale windblown sand.
					var deposit := smoothstep(0.78, 0.99, float(y) / size + (broad - 0.5) * 0.1)
					color = color.lerp(Color(0.64, 0.54, 0.4), deposit)
					h = lerpf(h, broad * 0.1 + detail * 0.025, deposit)
				heights[i] = h
				colors[i * 3] = int(clampf(color.r, 0, 1) * 255)
				colors[i * 3 + 1] = int(clampf(color.g, 0, 1) * 255)
				colors[i * 3 + 2] = int(clampf(color.b, 0, 1) * 255)
				orm[i * 3] = int((1.0 - cracks * (0.04 if kind == "sand" else 0.24)) * 255)
				orm[i * 3 + 1] = int(clampf(0.78 + detail * 0.18, 0, 1) * 255)
				orm[i * 3 + 2] = 0
		var normals := PackedByteArray()
		normals.resize(size * size * 3)
		for y in range(size):
			for x in range(size):
				var i := y * size + x
				var dx := heights[y * size + (x + 1) % size] - heights[y * size + (x + size - 1) % size]
				var dy := heights[((y + 1) % size) * size + x] - heights[((y + size - 1) % size) * size + x]
				var normal := Vector3(-dx * 9.0, dy * 9.0, 1.0).normalized()
				normals[i * 3] = int((normal.x * 0.5 + 0.5) * 255)
				normals[i * 3 + 1] = int((normal.y * 0.5 + 0.5) * 255)
				normals[i * 3 + 2] = int((normal.z * 0.5 + 0.5) * 255)
		var maps := [Image.create_from_data(size, size, false, Image.FORMAT_RGB8, colors), Image.create_from_data(size, size, false, Image.FORMAT_RGB8, normals), Image.create_from_data(size, size, false, Image.FORMAT_RGB8, orm)]
		var textures: Array[Texture2D] = []
		for index in range(3):
			var filename: String = "v2_%s_%s.png" % [kind, ["basecolor", "normal", "orm"][index]]
			maps[index].save_png(OUT + filename)
			maps[index].generate_mipmaps()
			textures.append(ImageTexture.create_from_image(maps[index]))
		var mat := StandardMaterial3D.new()
		mat.resource_name = "Desert_" + kind
		mat.albedo_texture = textures[0]
		mat.normal_enabled = true
		mat.normal_texture = textures[1]
		mat.normal_scale = 0.4 if kind == "sand" else 0.45
		mat.roughness = 1.0
		mat.roughness_texture = textures[2]
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		mat.ao_enabled = true
		mat.ao_texture = textures[2]
		mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		pbr[kind] = mat
		texture_report.append({"kind": kind, "resolution": size, "maps": 3, "uncompressed_rgb_mip_bytes": size * size * 3 * 3 * 4 / 3})
		print("DESERT_PBR_TEXTURE_READY ", kind)


func make_surface(st: SurfaceTool, name_value: String, kind: String, smooth: bool = false) -> MeshInstance3D:
	if smooth:
		st.generate_normals()
	st.generate_tangents()
	st.index()
	var mesh := MeshInstance3D.new()
	mesh.name = name_value
	mesh.mesh = st.commit()
	mesh.material_override = pbr[kind] if textured else material(SAND if kind == "sand" else ROCK)
	return mesh


func face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, vertical: bool = false) -> void:
	for tri in [[a, b, c], [a, c, d]]:
		var normal: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
		if normal.length_squared() < 0.1:
			continue
		for point: Vector3 in tri:
			st.set_normal(normal)
			st.set_uv(Vector2((point.x + point.z) / 192.0, 1.0 - point.y / 192.0) if vertical else Vector2(point.x, point.z) / 192.0)
			st.add_vertex(point)


func flat(width: float, depth: float, color: Color = SAND) -> MeshInstance3D:
	var st := begin()
	face(st, Vector3.ZERO, Vector3(width, 0, 0), Vector3(width, 0, depth), Vector3(0, 0, depth))
	return make_surface(st, "SandFlat", "sand")


func cliff_point(x: float, band: int, length: float, height: float) -> Vector3:
	var section := profile(height)[band]
	var edge := sin(PI * x / length)
	var envelope := sin(PI * section.x / height)
	var displacement := noise.get_noise_2d(x, section.x * 1.7) * 48.0 * edge * envelope
	var crest := noise.get_noise_2d(x, 37) * edge * pow(section.x / height, 4.0)
	return Vector3(x, section.x + displacement * 0.25 + crest * 9.0, -section.y + displacement + crest * 24.0)


func cliff(length: float = 256.0, height: float = 128.0) -> Node3D:
	var root := Node3D.new()
	root.name = "WeatheredCliff"
	var steps := maxi(8, int(length / 8))
	for band in range(profile(height).size() - 1):
		var st := begin()
		for i in range(steps):
			var x0 := length * i / steps
			var x1 := length * (i + 1) / steps
			face(st, cliff_point(x0, band, length, height), cliff_point(x1, band, length, height), cliff_point(x1, band + 1, length, height), cliff_point(x0, band + 1, length, height), true)
		root.add_child(make_surface(st, "FracturedStratum%d" % band, "rock", true))
	return root


func slope_point(x: float, t: float, width: float, length: float, height: float) -> Vector3:
	# Flat socket rows have no displacement; all three pieces sample one function.
	var y := ramp_height(t, height, length)
	var erosion := sin(PI * t) * sin(PI * x / width) * noise.get_noise_2d(x, t * length) * 1.3
	return Vector3(x, y + erosion, t * length)


func ramp_piece(width: float, length: float, height: float, start: float, finish: float, name_value: String) -> Node3D:
	var root := Node3D.new()
	root.name = name_value
	var st := begin()
	var steps := maxi(4, int(length * (finish - start) / 8))
	for z in range(steps):
		var t0 := lerpf(start, finish, float(z) / steps)
		var t1 := lerpf(start, finish, float(z + 1) / steps)
		for x in range(32):
			var x0 := width * x / 32.0
			var x1 := width * (x + 1) / 32.0
			for tri in [[slope_point(x0, t0, width, length, height), slope_point(x1, t0, width, length, height), slope_point(x1, t1, width, length, height)], [slope_point(x0, t0, width, length, height), slope_point(x1, t1, width, length, height), slope_point(x0, t1, width, length, height)]]:
				for point: Vector3 in tri:
					var t := point.z / length
					var dx := slope_point(point.x + 0.2, t, width, length, height) - slope_point(point.x - 0.2, t, width, length, height)
					var dz := slope_point(point.x, t + 0.2 / length, width, length, height) - slope_point(point.x, t - 0.2 / length, width, length, height)
					st.set_normal(dz.cross(dx).normalized())
					st.set_uv(Vector2(point.x, point.z) / 192.0)
					st.add_vertex(point)
	root.add_child(make_surface(st, "ContinuousSandRamp", "sand"))
	# Sloped, eroded rock shoulders replace the old vertical slab sides.
	for side: float in [-1.0, 1.0]:
		var shoulder := begin()
		for z in range(steps):
			var t0 := lerpf(start, finish, float(z) / steps)
			var t1 := lerpf(start, finish, float(z + 1) / steps)
			var x := 0.0 if side < 0 else width
			var a := slope_point(x, t0, width, length, height)
			var b := slope_point(x, t1, width, length, height)
			var c := Vector3(x + side * (12.0 + 46.0 * t1), 0, t1 * length)
			var d := Vector3(x + side * (12.0 + 46.0 * t0), 0, t0 * length)
			if side < 0:
				face(shoulder, a, b, c, d, true)
			else:
				face(shoulder, d, c, b, a, true)
		root.add_child(make_surface(shoulder, "RockShoulder", "rock", true))
	return root


func stone(size: Vector3, seed_value: int) -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rings: Array[PackedVector3Array] = []
	for layer in range(5):
		var ring := PackedVector3Array()
		for i in range(12):
			var a := TAU * i / 12
			var r: float = [0.72, 1.0, 0.91, 0.74, 0.22][layer] * rng.randf_range(0.87, 1.13)
			ring.append(Vector3(cos(a) * size.x * r * 0.5, size.y * layer / 4.0, sin(a) * size.z * r * 0.5))
		rings.append(ring)
	var st := begin()
	for layer in range(4):
		for i in range(12):
			face(st, rings[layer][i], rings[layer][(i + 1) % 12], rings[layer + 1][(i + 1) % 12], rings[layer + 1][i], true)
	var top := Vector3(0, size.y, 0)
	for i in range(12):
		face(st, rings[4][i], rings[4][(i + 1) % 12], top, top)
	return make_surface(st, "LayeredStone", "rubble", true)


func sample() -> Node3D:
	var root := Node3D.new()
	root.name = "DesertShortRampSample"
	place(root, flat(1024, 420), Vector3(-512, -0.8, -420))
	root.add_child(plateau_surface())
	place(root, cliff(256), Vector3(-384, 0, 0))
	place(root, cliff(256), Vector3(128, 0, 0))
	place(root, ramp(256, 256, 128), Vector3(-128, 0, -256))
	var rng := RandomNumberGenerator.new()
	rng.seed = 348
	for i in range(42):
		var side := -1.0 if i % 2 == 0 else 1.0
		var t := rng.randf_range(0.12, 0.97)
		var scale_value := rng.randf_range(9, 29)
		var point := Vector3(side * (140 + 46 * t), -1, -256 + t * 256)
		if i > 23:
			point = Vector3(side * rng.randf_range(175, 390), -1, rng.randf_range(-96, -56))
		place(root, stone(Vector3(scale_value * 1.7, scale_value * 0.6, scale_value), i + 311), point, rng.randf_range(0, TAU))
	# The crest is part of the cliff/top meshes, not a row of loose cap stones.
	for side: float in [-1.0, 1.0]:
		place(root, stone(Vector3(87, 17, 49), 591), Vector3(side * 330, 124, 36), side * 0.37)
		var apron := begin()
		for i in range(32):
			var x0 := 128 + i * 8.0
			var x1 := x0 + 8.0
			var z0 := -94 + noise.get_noise_2d(x0, 719) * 32
			var z1 := -94 + noise.get_noise_2d(x1, 719) * 32
			if side > 0:
				face(apron, Vector3(x0, 0, z0), Vector3(x1, 0, z1), Vector3(x1, 9, -48), Vector3(x0, 9, -48))
			else:
				face(apron, Vector3(-x1, 0, z1), Vector3(-x0, 0, z0), Vector3(-x0, 9, -48), Vector3(-x1, 9, -48))
		root.add_child(make_surface(apron, "WindblownSandApron", "sand", true))
	return root


func plateau_point(x: float, z: float) -> Vector3:
	var result := Vector3(x, 128, z)
	if absf(x) < 128 or z >= 64:
		return result
	var local_x := x + 384 if x < 0 else x - 128
	var edge_point := cliff_point(local_x, 7, 256, 128)
	var fade := pow(1.0 - z / 64.0, 2)
	result.y += (edge_point.y - 128) * fade
	result.z += edge_point.z * fade
	return result


func plateau_surface() -> MeshInstance3D:
	var st := begin()
	for x in range(96):
		for z in range(12):
			var x0 := -384.0 + x * 8
			var z0 := z * 32.0
			face(st, plateau_point(x0, z0), plateau_point(x0 + 8, z0), plateau_point(x0 + 8, z0 + 32), plateau_point(x0, z0 + 32))
	return make_surface(st, "MatchedNaturalPlateauEdge", "sand", true)


func plateau_tile() -> MeshInstance3D:
	var st := begin()
	for x in range(32):
		for z in range(8):
			var points: Array[Vector3] = []
			for corner_value in [Vector2(x * 8, z * 32), Vector2((x + 1) * 8, z * 32), Vector2((x + 1) * 8, (z + 1) * 32), Vector2(x * 8, (z + 1) * 32)]:
				var value: Vector3 = plateau_point(corner_value.x - 384, corner_value.y)
				points.append(value - Vector3(-384, 128, 0))
			face(st, points[0], points[1], points[2], points[3])
	return make_surface(st, "NaturalPlateauTile", "sand", true)
