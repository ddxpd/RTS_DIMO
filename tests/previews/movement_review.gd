extends SceneTree
var game: Node3D
var miner: int
var squad: Array = []
var frames := 0
const OUT := "res://assets/concept_art/hover_harvester/"


func _initialize() -> void:
    run.call_deferred()


func capture(name: String) -> void:
    game._sync_visuals()
    game._refresh_ui()
    for i in range(4):
        await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(OUT + name + ".png")


func run() -> void:
    root.size = Vector2i(1600, 1000)
    game = load("res://scenes/main.tscn").instantiate()
    root.add_child(game)
    game.play_solo()
    game.set_process(false)
    game.sim.ai_enabled = false
    game.sim.units.clear()
    game.sim._add_building(1, "bunker", Vector2(1152, 1792), true)
    miner = game.sim.add_unit(1, "harvester", Vector2(880, 1792))
    for i in range(12):
        squad.append(game.sim.add_unit(1, "soldier", Vector2(880 + (i % 4) * 48, 2050 + int(i / 4) * 48)))
    game.sim.rebuild_navigation()
    game.sim.update_visibility()
    game.camera_controller.focus = Vector2(1160, 1930)
    game.camera_zoom_level = 1.05
    game._update_camera_transform()
    game.selected_units.assign(squad + [miner])
    game.sim.command(1, {"action": "move", "units": [miner], "pos": Vector2(1450, 1792)})
    game.sim.command(1, {"action": "move", "units": squad, "pos": Vector2(1460, 2080)})
    await capture("movement-00-start")
    for tick in range(260):
        game.sim.step()
        game._sync_visuals(0.05)
        for entry: Dictionary in game.unit_visuals.values():
            entry.visual._process(0.05)
        if tick in [45, 80, 120, 200, 259]:
            await capture("movement-%03d" % tick)
    var arrived := 0
    for id: int in squad + [miner]:
        arrived += int(game.sim.units[id].order == "idle")
    print("MOVEMENT_REVIEW arrived=", arrived, "/13 miner=", game.sim.units[miner].pos)
    game.queue_free()
    await process_frame
    quit(0 if arrived == 13 else 1)
