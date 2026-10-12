extends SceneTree
const MAIN = preload("res://scenes/main.tscn")

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    root.size = Vector2i(1440, 1000)
    var game := MAIN.instantiate()
    root.add_child(game)
    game.play_solo()
    game.set_process(false)
    game.sim.ai_enabled = false
    game.sim.units.clear()
    game.sim.buildings.clear()
    game.sim.ores.clear()
    var point := Vector2(1600, 1900)
    var id: int = game.sim._add_building(1, "refinery", point, true)
    point = game.sim.buildings[id].pos
    for slot in range(2):
        var pos: Vector2 = Simulation.DepotDocking.berth(game.sim.buildings[id], slot) if slot == 0 else Simulation.DepotDocking.entrance(game.sim.buildings[id], slot)
        var uid: int = game.sim.add_unit(1, "harvester", pos)
        game.sim.units[uid].cargo = 60 if slot == 0 else 20
        game.sim.units[uid].order = "gather"
        game.sim.units[uid].dock = {"station": id, "slot": slot, "phase": "enter", "target": Simulation.DepotDocking.berth(game.sim.buildings[id], slot), "requested": 0, "stalled": 0, "last_pos": pos}
    game.sim.visible[1].fill(1)
    game.sim.explored[1].fill(1)
    game._sync_visuals()
    var visual: EntityVisual = game.building_visuals[id].visual
    visual.model.set_process(false)
    for u: Dictionary in game.unit_visuals.values():
        u.visual.set_heading(Vector2.DOWN, true)
    var destination := Vector3(point.x, game.sim.terrain.height_at(point) + 35, point.y)
    game.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    game.camera.size = 440
    game.camera.position = destination + Vector3(380, 460, -610)
    game.camera.look_at(destination)
    var folder := "res://assets/concept_art/ore_depot"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
    for lod in range(3):
        visual.model.set_lod(lod)
        for i in range(3):
            await process_frame
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png(folder + "/forward_lod%d.png" % lod)
    visual.model.set_lod(0)
    game.camera.size = 480
    game.camera.position = destination + Vector3(0, 800, -0.1)
    game.camera.look_at(destination)
    await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(folder + "/top.png")
    game.queue_free()
    await process_frame
    print("ORE_DEPOT_RENDER PASS")
    quit()
