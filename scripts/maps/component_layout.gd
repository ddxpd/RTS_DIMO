extends RefCounted
## JSON is the editable source; render batches and height caches are derived.

const Catalog = preload("res://scripts/maps/component_catalog.gd")
const VERSION := 2
var data: Dictionary = {}
var error := ""
var surfaces: Array[Dictionary] = []
var decorations: Array[Dictionary] = []
var blockers: Array[Rect2] = []
var buckets: Dictionary = {}


func load_file(path: String) -> bool:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        error = "Cannot open component layout: " + path
        return false
    var parser := JSON.new()
    if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
        error = "Invalid layout JSON: " + path
        return false
    return configure(parser.data)


func save_file(path: String) -> Error:
    if not error.is_empty() or data.is_empty():
        return ERR_INVALID_DATA
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return FileAccess.get_open_error()
    file.store_string(JSON.stringify(data, "  ", true))
    return OK


func configure(value: Dictionary) -> bool:
    error = ""
    data = {}
    surfaces.clear()
    decorations.clear()
    blockers.clear()
    buckets.clear()
    if value.get("version") != VERSION or value.get("catalog_revision") != Catalog.REVISION:
        return fail("Unsupported layout/catalog version")
    if not numeric(value.get("seed")) or float(value.seed) != floorf(float(value.seed)):
        return fail("Layout requires an integer seed")
    if not value.get("bounds") is Array or value.bounds.size() != 4 or not value.get("instances") is Array:
        return fail("Layout requires bounds[4] and instances[]")
    for number in value.bounds:
        if not numeric(number):
            return fail("Bounds must be finite numbers")
    var bounds := Rect2(value.bounds[0], value.bounds[1], value.bounds[2], value.bounds[3])
    if not Catalog.WorldGrid.rect_aligned(bounds):
        return fail("Layout bounds must align to the shared grid")
    if bounds.size.x <= 0 or bounds.size.y <= 0 or not Rect2(0, 0, 4800, 3200).encloses(bounds):
        return fail("Layout bounds outside world")
    var ids := {}
    for raw in value.instances:
        if not raw is Dictionary or not raw.get("id") is String or raw.id.is_empty() or ids.has(raw.id):
            return fail("Each instance needs a unique nonempty ID")
        ids[raw.id] = true
        if not raw.get("component") is String or Catalog.entry(raw.component).is_empty():
            return fail("Unknown component on instance " + raw.id)
        if not raw.get("position") is Array or raw.position.size() != 3:
            return fail("Position must have three numbers: " + raw.id)
        for number in raw.position:
            if not numeric(number):
                return fail("Non-finite position: " + raw.id)
        if float(raw.position[1]) < -128 or float(raw.position[1]) > 128:
            return fail("Instance base height outside -128..128: " + raw.id)
        if not numeric(raw.get("rotation", 0.0)) or not numeric(raw.get("scale", 1.0)):
            return fail("Non-finite transform: " + raw.id)
        var item := Catalog.entry(raw.component)
        var instance: Dictionary = raw.duplicate(true)
        if item.layer == "surface":
            if not is_equal_approx(float(raw.get("scale", 1.0)), 1.0) or absf(wrapf(float(raw.get("rotation", 0)), -PI / 4, PI / 4)) > 0.0001:
                return fail("Terrain requires unit scale and quarter turns: " + raw.id)
            for axis in [0, 2]:
                if absf(float(raw.position[axis]) / Catalog.GRID - roundf(float(raw.position[axis]) / Catalog.GRID)) > 0.001:
                    return fail("Terrain must align to 32-unit grid: " + raw.id)
        elif float(raw.get("scale", 1)) < 0.1 or float(raw.get("scale", 1)) > 4.0:
            return fail("Decoration scale outside 0.1..4: " + raw.id)
        var footprint := Catalog.rect(instance)
        if item.blocking:
            if not is_equal_approx(float(raw.get("scale", 1.0)), 1.0) or absf(wrapf(float(raw.get("rotation", 0)), -PI / 4, PI / 4)) > 0.0001 or not Catalog.WorldGrid.rect_aligned(footprint):
                return fail("Blocking terrain requires aligned integer-cell footprint: " + raw.id)
        if not bounds.grow(0.01).encloses(footprint):
            return fail("Instance outside layout bounds: " + raw.id)
        instance["_rect"] = footprint
        instance["_inverse"] = Catalog.transform(instance).affine_inverse()
        if item.layer == "decoration":
            decorations.append(instance)
            if item.blocking:
                blockers.append(footprint)
            continue
        for previous in surfaces:
            if footprint.grow(-0.01).intersects(previous._rect):
                return fail("Overlapping terrain: " + raw.id + " / " + previous.id)
        surfaces.append(instance)
    # Adjacent endpoints are checked in world space, including negative heights.
    # A ramp's sides may expose a vertical cliff; its two ends must connect.
    for instance in surfaces:
        var size: Vector2 = Catalog.entry(instance.component).size
        var t := Catalog.transform(instance)
        for side in range(4):
            if instance.component.begins_with("ramp") and side < 2:
                continue
            var length := size.y if side < 2 else size.x
            for step in range(1, int(length / 8.0)):
                var local := Vector2(0 if side == 0 else size.x, step * 8.0) if side < 2 else Vector2(step * 8.0, 0 if side == 2 else size.y)
                var normal: Vector3 = [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK][side]
                var world := t * Vector3(local.x, 0, local.y)
                var probe := world + t.basis * normal * 0.1
                var point := Vector2(world.x, world.z)
                var connected := false
                for neighbor in surfaces:
                    if neighbor.id == instance.id or not (neighbor._rect as Rect2).has_point(Vector2(probe.x, probe.z)):
                        continue
                    if neighbor.component.begins_with("ramp"):
                        var neighbor_point := Catalog.local_point(neighbor, point)
                        var neighbor_size: Vector2 = Catalog.entry(neighbor.component).size
                        if neighbor_point.x < 0.2 or neighbor_point.x > neighbor_size.x - 0.2:
                            connected = true
                            continue
                    connected = true
                    if absf(Catalog.world_height(instance, point) - Catalog.world_height(neighbor, point)) > 0.1:
                        return fail("Incompatible connection: " + instance.id + " / " + neighbor.id)
                if not connected and absf(Catalog.world_height(instance, point)) > 0.1:
                    return fail("Unconnected elevated edge: " + instance.id)
    data = value.duplicate(true)
    data.instances.sort_custom(func(a, b): return a.id < b.id)
    for instance in surfaces:
        var r: Rect2 = instance._rect.grow(0.1)
        for z in range(floori(r.position.y / 256), floori(r.end.y / 256) + 1):
            for x in range(floori(r.position.x / 256), floori(r.end.x / 256) + 1):
                var key := Vector2i(x, z)
                if not buckets.has(key):
                    buckets[key] = []
                buckets[key].append(instance)
    return true


func fail(message: String) -> bool:
    error = message
    return false


static func numeric(value) -> bool:
    return (value is float or value is int) and is_finite(float(value))


func surface_at(p: Vector2) -> Dictionary:
    var found: Dictionary = {}
    for instance: Dictionary in buckets.get(Vector2i(floori(p.x / 256), floori(p.y / 256)), []):
        if (instance._rect as Rect2).grow(0.001).has_point(p):
            # At a lateral ramp/cliff border the walkable lip owns the vertex.
            # Do not let JSON ID ordering erode one grid strip of clear width.
            if instance.component.begins_with("ramp"):
                return instance
            if found.is_empty():
                found = instance
    return found


func height_at(p: Vector2) -> float:
    var instance := surface_at(p)
    if instance.is_empty():
        return 0.0
    var q: Vector3 = instance._inverse * Vector3(p.x, 0, p.y)
    return float(instance.position[1]) + Catalog.height(instance.component, Vector2(q.x, q.z))


func blocked(p: Vector2, radius: float) -> bool:
    for footprint in blockers:
        if footprint.grow(radius).has_point(p):
            return true
    return false


func checksum() -> String:
    return JSON.stringify(data, "", true).sha256_text()


func ramps() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for instance in surfaces:
        if instance.component != "ramp_toe":
            continue
        var t := Catalog.transform(instance)
        var low := t * Vector3(128, 0, 0)
        var high := t * Vector3(128, 128, 256)
        var downhill := low.y < -1
        result.append({"start": Vector2(high.x, high.z) if downhill else Vector2(low.x, low.z), "end": Vector2(low.x, low.z) if downhill else Vector2(high.x, high.z), "height": -128.0 if downhill else 128.0, "width": 256.0})
    return result
