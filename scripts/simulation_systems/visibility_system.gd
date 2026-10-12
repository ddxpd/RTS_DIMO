extends RefCounted
## Synchronous rules; Simulation owns state, caches and tick order.
const Terrain = preload("res://scripts/maps/map_terrain.gd")


static func update_visibility(sim: Simulation) -> void:
    var terrain: Terrain = sim.terrain
    if sim.is_test_map():
        for owner in [1, 2]:
            sim.visible[owner].fill(1)
            sim.explored[owner].fill(1)
        return
    for owner in [1, 2]:
        var cells: PackedByteArray = sim.visible[owner]
        cells.fill(0)
        for collection: Dictionary in [sim.units, sim.buildings]:
            for entity: Dictionary in collection.values():
                if entity.owner != owner or entity.hp <= 0:
                    continue
                var center: Vector2 = entity.pos
                for index in terrain.visible_cells(center, Simulation.EYE_HEIGHTS.get(entity.type, 40.0)):
                    cells[index] = 1
        sim.visible[owner] = cells
        var known: PackedByteArray = sim.explored[owner]
        for i in range(Simulation.GRID_CELLS):
            if cells[i] == 1:
                known[i] = 1
        sim.explored[owner] = known


static func can_see(sim: Simulation, owner: int, pos: Vector2) -> bool:
    if owner == 0:
        return true
    var grid: Vector2i = Simulation.GRID
    var visible: Dictionary = sim.visible
    var cell := Vector2i((pos / float(Simulation.CELL)).floor()).clamp(Vector2i.ZERO, grid - Vector2i.ONE)
    return visible.has(owner) and visible[owner][cell.y * grid.x + cell.x] == 1
