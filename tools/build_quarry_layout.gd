extends SceneTree
## Battle-map assemblies are retained independently of the editable training map.
const Layout = preload("res://scripts/maps/component_layout.gd")

func _initialize() -> void:
    var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/source/terrain/quarry_assemblies.json"))
    var instances: Array = []
    var rotation := Basis(Vector3.UP, PI / 2)
    for raw: Dictionary in source.instances:
        if Layout.Catalog.entry(raw.component).layer != "surface":
            continue
        var p := Vector3(raw.position[0], raw.position[1], raw.position[2])
        var plateau := p.x < 2400
        var origin := Vector3(1888, 0, 1984) if plateau else Vector3(2912, 0, 1856)
        var target := Vector3(1536, 0, 1088) if plateau else Vector3(3872, 0, 704)
        var point := rotation * (p - origin) + target
        for side in range(2):
            var item := raw.duplicate(true)
            var position := point if side == 0 else Vector3(4800 - point.x, point.y, 3200 - point.z)
            item.id = "quarry_%d_%s" % [side, raw.id]
            item.position = [snappedf(position.x, 32), position.y, snappedf(position.z, 32)]
            item.rotation = float(raw.rotation) + PI / 2 + side * PI
            instances.append(item)
    for point: Vector2 in [Vector2(2208, 544), Vector2(224, 1376)]:
        for side in range(2):
            var p := point if side == 0 else Vector2(4800, 3200) - point
            for offset in [-96, 32]:
                instances.append({"id": "rock_%d_%d_%d" % [int(p.x), side, offset], "component": "rock_large", "position": [p.x, 0, p.y + offset], "rotation": 0, "scale": 1})
    var layout := Layout.new()
    var data := {"version": Layout.VERSION, "catalog_revision": Layout.Catalog.REVISION, "seed": 29471, "bounds": [0, 0, 4800, 3200], "instances": instances}
    if not layout.configure(data):
        push_error(layout.error)
        quit(1)
        return
    assert(layout.save_file("res://assets/maps/desert_quarry_layout.json") == OK)
    print("QUARRY_LAYOUT_PASS instances=", instances.size())
    quit()
