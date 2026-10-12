extends RefCounted
## Explicit test armies for input/combat fixtures. Real matches start base-only.


static func seed(sim) -> void:
    assert(sim.units.is_empty(), "Army fixture requires an empty match")
    for owner in [1, 2]:
        var spawn: Vector2 = sim.terrain.definition.spawns[owner - 1]
        var facing := 1.0 if owner == 1 else -1.0
        for index in range(6):
            sim.add_unit(owner, "mobile_infantry", spawn + Vector2(256.0, -128.0 + index * 64.0) * facing)
    sim.update_visibility()
