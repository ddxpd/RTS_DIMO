extends SceneTree
# Headless verification for the bottom action bar wiring.
const MAIN = preload("res://scenes/main.tscn")

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    Engine.max_fps = 120
    var game := MAIN.instantiate()
    root.add_child(game)
    game.play_solo()
    var failures: Array = []

    # Select the first friendly soldier.
    var unit_id := -1
    for id: int in game.sim.units:
        if game.sim.units[id].owner == 1 and game.sim.units[id].type == "soldier":
            unit_id = id
            break
    if unit_id < 0:
        failures.append("no friendly soldier found")
    else:
        game._clear_selection()
        game.selected_units.append(unit_id)
        game._refresh_ui()
        if game.action_buttons[0].text != "STOP (S)" or game.action_buttons[0].disabled:
            failures.append("STOP button not enabled with hotkey label")
        if game.action_buttons[1].text != "MOVE (RMB)" or game.action_buttons[1].disabled:
            failures.append("MOVE button not enabled with hint label")
        if game.action_buttons[2].text != "ATTACK (A)" or game.action_buttons[2].disabled:
            failures.append("ATTACK button not enabled with hotkey label")
        if game.action_buttons[3].disabled == false or game.action_buttons[4].disabled == false:
            failures.append("unused action slots not disabled")

        # Clicking MOVE must arm the pending command instead of issuing instantly.
        game.action_buttons[1].emit_signal("pressed")
        if game.pending_command != "move":
            failures.append("MOVE click did not arm pending command")

        # The next battlefield click issues the move order and clears the mode.
        game._pending_click(Vector2(500, 300))
        if game.sim.units[unit_id].order != "move":
            failures.append("pending click did not issue move order")
        if game.pending_command != "":
            failures.append("pending command not cleared after issue")

        # STOP button must issue the stop order.
        game.action_buttons[0].emit_signal("pressed")
        await process_frame
        await process_frame
        if game.sim.units[unit_id].order != "idle":
            failures.append("STOP click did not stop the unit")

    print("ACTION_BAR_TEST failures=", failures)
    quit(0 if failures.is_empty() else 1)
