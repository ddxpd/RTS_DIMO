extends RefCounted
## Review-only geometry in game units. No navigation or production-map dependency.

const OUT := "res://assets/concept_art/desert_terrain_kit/"
const SAND := Color("#c8aa78")
const ROCK := Color("#98724e")
const RAMP := Color("#877b62")
var records: Array[Dictionary] = []
var checks := 0
var failures: Array[String] = []
var materials: Dictionary = {}


func material(color: Color) -> StandardMaterial3D:
	if not materials.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.92
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		materials[color] = mat
	return materials[color]


func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for tri in [[a, b, c], [a, c, d]]:
		var n: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0])
		if n.length_squared() < 0.0001:
			continue
		for point: Vector3 in tri:
			st.set_normal(n.normalized())
			st.set_uv(Vector2(point.x, point.z) / 256.0)
			st.add_vertex(point)


func surface(st: SurfaceTool, name: String, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = st.commit()
	instance.material_override = material(color)
	return instance


func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func flat(width: float, depth: float, color: Color = SAND) -> MeshInstance3D:
	var st := begin()
	quad(st, Vector3.ZERO, Vector3(width, 0, 0), Vector3(width, 0, depth), Vector3(0, 0, depth))
	return surface(st, "WalkableFlat", color)


func profile(height: float) -> Array[Vector2]:
	# Every cliff and corner uses the exact same edge section: height, outward offset.
	return [Vector2(0, 64), Vector2(height * 0.08, 59), Vector2(height * 0.29, 39),
		Vector2(height * 0.32, 43), Vector2(height * 0.62, 23),
		Vector2(height * 0.65, 27), Vector2(height * 0.93, 8), Vector2(height, 0)]


func cliff(length: float = 256.0, height: float = 128.0) -> Node3D:
	var root := Node3D.new()
	root.name = "CliffStraight"
	var p := profile(height)
	for band in range(p.size() - 1):
		var st := begin()
		for segment in range(8):
			var x0 := length * segment / 8.0
			var x1 := length * (segment + 1) / 8.0
			quad(st, Vector3(x0, p[band].x, -p[band].y), Vector3(x1, p[band].x, -p[band].y),
				Vector3(x1, p[band + 1].x, -p[band + 1].y), Vector3(x0, p[band + 1].x, -p[band + 1].y))
		root.add_child(surface(st, "Stratum%d" % band, ROCK.lightened(0.055 if band % 3 == 0 else 0.0)))
	return root


func corner(height: float = 128.0, inner: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "CliffInnerCorner" if inner else "CliffOuterCorner"
	var p := profile(height)
	for band in range(p.size() - 1):
		var st := begin()
		for segment in range(8):
			var a0 := segment * PI / 16.0
			var a1 := (segment + 1) * PI / 16.0
			var r0 := 64.0 - p[band].y if inner else p[band].y
			var r1 := 64.0 - p[band + 1].y if inner else p[band + 1].y
			quad(st, Vector3(-cos(a0) * r0, p[band].x, -sin(a0) * r0),
				Vector3(-cos(a1) * r0, p[band].x, -sin(a1) * r0),
				Vector3(-cos(a1) * r1, p[band + 1].x, -sin(a1) * r1),
				Vector3(-cos(a0) * r1, p[band + 1].x, -sin(a0) * r1))
		root.add_child(surface(st, "CornerStratum%d" % band, ROCK.lightened(0.055 if band % 3 == 0 else 0.0)))
	if inner:
		var cap := begin()
		for index in range(8):
			var a0 := index * PI / 16.0
			var a1 := (index + 1) * PI / 16.0
			quad(cap, Vector3(-64, height, -64), Vector3(-64 * cos(a0), height, -64 * sin(a0)),
				Vector3(-64 * cos(a1), height, -64 * sin(a1)), Vector3(-64, height, -64))
		root.add_child(surface(cap, "InnerCornerTop", SAND))
	return root


func end_cap(height: float = 128.0) -> Node3D:
	var root := Node3D.new()
	root.name = "CliffEnd"
	root.add_child(cliff(128, height))
	var cap := corner(height)
	root.add_child(cap)
	return root


func ramp_height(t: float, height: float, length: float) -> float:
	var edge := minf(64.0, length / 8.0) / length
	if t < edge:
		var u := t / edge
		return height * edge * u * u * (2.0 - u)
	if t > 1.0 - edge:
		var u := (t - 1.0 + edge) / edge
		return height * (1.0 - edge) + height * edge * (u + u * u - u * u * u)
	return height * t


func ramp_piece(width: float, length: float, height: float, start: float, finish: float, name: String) -> Node3D:
	var root := Node3D.new()
	root.name = name
	var top := begin()
	var side := begin()
	var steps := maxi(4, int((finish - start) * length / 16))
	for index in range(steps):
		var t0 := lerpf(start, finish, float(index) / steps)
		var t1 := lerpf(start, finish, float(index + 1) / steps)
		var z0 := t0 * length
		var z1 := t1 * length
		var y0 := ramp_height(t0, height, length)
		var y1 := ramp_height(t1, height, length)
		quad(top, Vector3(0, y0, z0), Vector3(width, y0, z0), Vector3(width, y1, z1), Vector3(0, y1, z1))
		quad(side, Vector3(0, 0, z0), Vector3(0, y0, z0), Vector3(0, y1, z1), Vector3(0, 0, z1))
		quad(side, Vector3(width, 0, z1), Vector3(width, y1, z1), Vector3(width, y0, z0), Vector3(width, 0, z0))
	root.add_child(surface(top, "UnbuildableRamp", RAMP))
	root.add_child(surface(side, "RampSides", ROCK))
	return root


func ramp(width: float, length: float, height: float) -> Node3D:
	var root := Node3D.new()
	root.name = "RampAssembly"
	var edge := minf(64.0, length / 8.0) / length
	root.add_child(ramp_piece(width, length, height, 0, edge, "Toe"))
	root.add_child(ramp_piece(width, length, height, edge, 1 - edge, "Run"))
	root.add_child(ramp_piece(width, length, height, 1 - edge, 1, "Crest"))
	return root


func rock(size: Vector3, seed_value: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rings: Array[PackedVector3Array] = []
	for layer in range(4):
		var ring := PackedVector3Array()
		var radius: float = [0.85, 1.0, 0.72, 0.30][layer]
		for index in range(8):
			var a := TAU * index / 8.0
			var r := radius * rng.randf_range(0.88, 1.10)
			ring.append(Vector3(cos(a) * size.x * 0.5 * r, layer * size.y / 3.0, sin(a) * size.z * 0.5 * r))
		rings.append(ring)
	var st := begin()
	for layer in range(3):
		for index in range(8):
			var next := (index + 1) % 8
			quad(st, rings[layer][index], rings[layer][next], rings[layer + 1][next], rings[layer + 1][index])
	for index in range(8):
		quad(st, rings[3][index], rings[3][(index + 1) % 8], Vector3(0, size.y, 0), Vector3(0, size.y, 0))
	return surface(st, "RockSilhouette", ROCK)


func rubble() -> Node3D:
	var root := Node3D.new()
	root.name = "RubbleCluster"
	for index in range(7):
		var stone := rock(Vector3(24 + index * 3, 12 + index * 2, 20 + index * 3), index + 77)
		stone.position = Vector3((index % 3) * 38, 0, (index / 3) * 32)
		root.add_child(stone)
	return root


func place(parent: Node3D, child: Node3D, point: Vector3, angle: float = 0) -> Node3D:
	parent.add_child(child)
	child.position = point
	child.rotation.y = angle
	return child


func platform(height: float, ramp_width: float = 256, ramp_length: float = 256) -> Node3D:
	var root := Node3D.new()
	root.name = "HighlandAssembly"
	for x in range(2):
		for z in range(2):
			place(root, flat(256, 256), Vector3(x * 256 - 256, height, z * 256))
	var shoulder := (512 - ramp_width) / 2.0
	if shoulder > 0:
		place(root, cliff(shoulder, height), Vector3(-256, 0, 0))
		place(root, cliff(shoulder, height), Vector3(ramp_width / 2, 0, 0))
	place(root, cliff(512, height), Vector3(256, 0, 512), PI)
	place(root, cliff(512, height), Vector3(-256, 0, 512), PI / 2)
	place(root, cliff(512, height), Vector3(256, 0, 0), -PI / 2)
	for data in [[-256, 0, 0.0], [256, 0, -PI / 2], [-256, 512, PI / 2], [256, 512, PI]]:
		place(root, corner(height), Vector3(data[0], 0, data[1]), data[2])
	place(root, ramp(ramp_width, ramp_length, height), Vector3(-ramp_width / 2, 0, -ramp_length))
	return root


func pit(height: float = 128) -> Node3D:
	var root := Node3D.new()
	root.name = "QuarryAssembly"
	place(root, flat(512, 768), Vector3(-256, -height, 0))
	place(root, cliff(64, height), Vector3(-128, -height, 0), PI)
	place(root, cliff(64, height), Vector3(192, -height, 0), PI)
	place(root, cliff(384, height), Vector3(-192, -height, 768))
	place(root, cliff(640, height), Vector3(-256, -height, 64), -PI / 2)
	place(root, cliff(640, height), Vector3(256, -height, 704), PI / 2)
	for data in [[-192, 64, 0.0], [192, 64, -PI / 2], [-192, 704, PI / 2], [192, 704, PI]]:
		place(root, corner(height, true), Vector3(data[0], -height, data[1]), data[2])
	# Bottom-to-top ramp rotated toward the approach, with matching floor height.
	place(root, ramp(256, 256, height), Vector3(128, -height, 256), PI)
	place(root, flat(256, 896), Vector3(-512, 0, -64))
	place(root, flat(256, 896), Vector3(256, 0, -64))
	place(root, flat(512, 128), Vector3(-256, 0, 768))
	place(root, flat(512, 128), Vector3(-256, 0, -128))
	return root


func register(id: String, title: String, node: Node3D, size: Vector3, use: String, budget: int) -> Dictionary:
	node.name = id
	var data := {"id": id, "title": title, "node": node, "size": size, "use": use, "formal_lod0_triangle_budget": budget}
	records.append(data)
	return data


func catalog() -> Array[Dictionary]:
	register("sand_flat", "沙地平面", flat(256, 256), Vector3(256, 0, 256), "可通行／预期可建造", 128)
	register("plateau_top", "高台顶面", flat(256, 256, SAND.lightened(0.06)), Vector3(256, 0, 256), "可通行／预期可建造", 256)
	register("cliff_straight", "直线崖壁", cliff(), Vector3(256, 128, 64), "不可通行", 1800)
	register("cliff_outer", "崖壁外角", corner(), Vector3(64, 128, 64), "不可通行", 1200)
	register("cliff_inner", "崖壁内角", corner(128, true), Vector3(64, 128, 64), "不可通行", 1200)
	register("cliff_end", "崖壁端头", end_cap(), Vector3(192, 128, 64), "不可通行", 1200)
	register("ramp_run", "坡道主体", ramp_piece(256, 256, 128, 0.125, 0.875, "Run"), Vector3(256, 96, 192), "可通行／不可建造", 512)
	register("ramp_toe", "坡脚过渡", ramp_piece(256, 256, 128, 0, 0.125, "Toe"), Vector3(256, 16, 32), "可通行／不可建造", 256)
	register("ramp_crest", "坡顶过渡", ramp_piece(256, 256, 128, 0.875, 1, "Crest"), Vector3(256, 16, 32), "可通行／不可建造", 256)
	register("rock_large", "大岩块", rock(Vector3(128, 96, 112), 51), Vector3(128, 96, 112), "预期阻挡／待接入玩法", 1000)
	register("rock_medium", "中岩块", rock(Vector3(64, 48, 56), 52), Vector3(64, 48, 56), "阻挡规则待确认", 500)
	register("rubble_cluster", "碎石簇", rubble(), Vector3(128, 24, 112), "预期装饰／不阻挡", 600)
	return records


func triangles(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		for index in range(mesh.get_surface_count()):
			var indices: int = mesh.surface_get_array_index_len(index)
			count += (indices if indices > 0 else mesh.surface_get_array_len(index)) / 3
	for child in node.get_children():
		count += triangles(child)
	return count


func mark_owners(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		mark_owners(child, root)


func export_asset(node: Node3D, file: String) -> void:
	mark_owners(node, node)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var error := doc.append_from_scene(node, state)
	if error == OK:
		error = doc.write_to_filesystem(state, OUT + file + ".glb")
	checks += 1
	if error != OK:
		failures.append("Export " + file + ": " + str(error))
		return
	# Read the actual file back: successful serialization alone is insufficient.
	var loaded := GLTFState.new()
	error = doc.append_from_file(OUT + file + ".glb", loaded)
	checks += 1
	if error != OK:
		failures.append("Reimport " + file + ": " + str(error))
		return
	var roundtrip := doc.generate_scene(loaded)
	checks += 1
	if roundtrip == null:
		failures.append("Empty GLB " + file)
		return
	if triangles(roundtrip) != triangles(node):
		failures.append("GLB triangle mismatch " + file)
	roundtrip.free()


func verify() -> void:
	for height in [96.0, 128.0, 160.0]:
		var p := profile(height)
		checks += 1
		if p[0].x != 0 or p[-1] != Vector2(height, 0):
			failures.append("Cliff endpoint mismatch")
		# Outer corner endpoint equals the same section rotated into either wall.
		for section in p:
			var edge := Vector3(-section.y, section.x, 0)
			var straight := Vector3(0, section.x, -section.y).rotated(Vector3.UP, PI / 2)
			checks += 1
			if edge.distance_to(straight) > 0.001:
				failures.append("Corner socket mismatch")
	for length: float in [256.0, 320.0, 512.0]:
		for width: float in [192.0, 256.0, 320.0]:
			checks += 3
			if absf(ramp_height(0, 128, length)) > 0.001 or absf(ramp_height(1, 128, length) - 128) > 0.001:
				failures.append("Ramp endpoint mismatch")
			var t := minf(64.0, length / 8.0) / length
			if absf(ramp_height(t, 128, length) - 128 * t) > 0.001:
				failures.append("Toe/run mismatch")
			if absf(ramp_height(1 - t, 128, length) - 128 * (1 - t)) > 0.001:
				failures.append("Run/crest mismatch")
