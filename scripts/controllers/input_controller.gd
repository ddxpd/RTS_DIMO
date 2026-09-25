class_name InputController
extends Node

var host

func configure(owner) -> void:
    host = owner

func _unhandled_input(event: InputEvent) -> void:
    # _input and _unhandled_input can receive different subsets of injected or
    # platform events, so keep the anti-duplicate timestamp accurate in both.
    if event is InputEventMouseMotion:
        host.last_mouse_event_msec = Time.get_ticks_msec()
    if event is InputEventKey and event.pressed and not event.echo:
        if host.rebinding_attack:
            if event.keycode != KEY_ESCAPE:
                host.attack_keycode = event.keycode
                host.rebinding_attack = false
                host.attack_rebind_button.text = "Rebind attack key (current: %s)" % OS.get_keycode_string(host.attack_keycode)
                host._notify("Attack key set to %s." % OS.get_keycode_string(host.attack_keycode))
            get_viewport().set_input_as_handled()
            return
        if event.keycode == KEY_ESCAPE:
            if not host.build_mode.is_empty() or not host.pending_command.is_empty():
                host.build_mode = ""
                host.pending_command = ""
            else:
                host._toggle_menu()
        elif host.active and not host.menu_visible and event.keycode == host.attack_keycode:
            host.attack_mode = not host.attack_mode
            host._notify("Attack mode %s. Left-click a target or ground." % ("ON" if host.attack_mode else "OFF"))
        elif host.active and not host.menu_visible and event.keycode == KEY_B:
            host._begin_build("barracks")
        elif host.active and not host.menu_visible and event.keycode == KEY_S:
            host._stop()
        elif host.active and not host.menu_visible and event.keycode >= KEY_1 and event.keycode <= KEY_9:
            _control_group_key(int(event.keycode) - int(KEY_1) + 1, event.ctrl_pressed, event.shift_pressed)
        elif host.active and not host.menu_visible and event.keycode == KEY_TAB:
            if host.selected_buildings.size() > 1:
                host.building_tab_index = (host.building_tab_index + 1) % host.selected_buildings.size()
                host._notify("Building %d / %d" % [host.building_tab_index + 1, host.selected_buildings.size()])
    if not host.active or host.menu_visible:
        return
    if event is InputEventMouseButton:
        var pos: Vector2 = host._screen_to_world(event.position)
        var button := event as InputEventMouseButton
        if button.button_index == MOUSE_BUTTON_LEFT:
            var was_held: bool = host.left_button_held
            if button.pressed and not button.canceled:
                host.left_button_held = true
            if button.pressed and host._screen_is_map(event.position):
                # Preserve the original box when Windows emits a duplicate press
                # while the tracked button is still held. Stale drags fall
                # through so their lost release can be recovered below.
                if host.selection_dragging and was_held:
                    var press_msec := Time.get_ticks_msec()
                    if press_msec - host.last_mouse_event_msec < 1500:
                        return
                if not host.build_mode.is_empty():
                    host._place_building(pos)
                else:
                    host.selection_dragging = true
                    host.selection_start    = pos
                    host.selection_current  = pos
            elif not button.pressed and host.selection_dragging:
                if not button.canceled:
                    _finish_drag_select(pos)
            if not button.pressed and not button.canceled:
                host.left_button_held = false
        elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed and host._screen_is_map(event.position):
            if not host.build_mode.is_empty():
                host.build_mode = ""
            else:
                host._right_click(pos)
        elif event.button_index == MOUSE_BUTTON_MIDDLE:
            host.middle_dragging = event.pressed
        elif event.pressed and host._screen_is_map(event.position) and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
            var before: Vector2 = host._screen_to_world(event.position)
            var factor := 1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
            host.camera_zoom_level = clampf(host.camera_zoom_level * factor, host._min_zoom(), 6.0)
            # Iterative anchor: perspective projection needs multiple passes
            # to converge the world point under the cursor exactly.
            for i in range(3):
                host._update_camera_transform()
                var after: Vector2 = host._screen_to_world(event.position)
                host.camera_controller.focus += before - after
            host._update_camera_transform()
    elif event is InputEventMouseMotion:
        if host.middle_dragging:
            host.camera_controller.focus += Vector2(event.relative.x, event.relative.y) / host.camera_zoom_level
        if host.selection_dragging:
            host.selection_current = host._screen_to_world(event.position)

func _input(event: InputEvent) -> void:
    # _input runs before the HUD consumes events, so an host.active drag keeps
    # tracking (and can complete) even while the cursor is over HUD panels.
    if event is InputEventMouseMotion:
        host.last_mouse_event_msec = Time.get_ticks_msec()
        if host.selection_dragging:
            host.selection_current = host._screen_to_world(event.position)
    if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
        host.middle_dragging = false
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        var button := event as InputEventMouseButton
        var now := Time.get_ticks_msec()
        # A second press while the button is already held mid-drag is a
        # spurious duplicate from the input stack (seen with confined cursor
        # on Windows): swallow it so the original box start is preserved.
        # Stale drags (release event lost entirely) restart from this press.
        if button.pressed and host.selection_dragging and host.left_button_held and not button.canceled:
            if now - host.last_mouse_event_msec < 1500:
                get_viewport().set_input_as_handled()
                return
            _finish_drag_select(host.selection_current)
        host.last_mouse_event_msec = now
        # Track the button ourselves: Godot's Input state is also corrupted by
        # canceled events, so only non-canceled presses/releases update it.
        if not button.canceled:
            host.left_button_held = button.pressed
        if not button.pressed and host.selection_dragging:
            # Canceled releases (focus quirks, confined-cursor edge pressure)
            # must not end a drag while the button is still physically held.
            if button.canceled or host.left_button_held:
                return
            _finish_drag_select(host._screen_to_world(event.position))

# Complete a box drag: treat tiny drags as clicks, larger ones as selections.
func _finish_drag_select(pos: Vector2) -> void:
    host.selection_dragging = false
    if (pos - host.selection_start).length() * host.camera_zoom_level < 8:
        _left_click(pos)
    else:
        _select_rect(Rect2(host.selection_start, pos - host.selection_start).abs())

func _left_click(pos: Vector2) -> void:
    if not host.pending_command.is_empty():
        host._pending_click(pos)
        return
    if host.attack_mode:
        _attack_click(pos)
        return
    host._clear_selection()
    for id: int in host.sim.units:
        var u: Dictionary = host.sim.units[id]
        if u.owner == host.local_slot and (u.pos as Vector2).distance_to(pos) <= 20:
            var now := Time.get_ticks_msec() / 1000.0
            if id == host.last_click_unit and now - host.last_click_time <= 0.4:
                _select_same_type_on_screen(str(u.type))
                host.last_click_unit = -1
            else:
                host.selected_units.append(id)
                host.last_click_unit = id
            host.last_click_time = now
            return
    for id: int in host.sim.buildings:
        if host.sim.buildings[id].owner == host.local_slot and host.sim.footprint(host.sim.buildings[id]).has_point(pos):
            var now := Time.get_ticks_msec() / 1000.0
            if id == host.last_click_building and now - host.last_click_building_time <= 0.4:
                _select_same_type_buildings_on_screen(str(host.sim.buildings[id].type))
                host.last_click_building = -1
            else:
                host.selected_building = id
                host.selected_buildings.clear()
                host.selected_buildings.append(id)
                host.last_click_building = id
            host.last_click_building_time = now
            return

# Double-click: grab every on-screen building of the same kind as the clicked one.
func _select_same_type_buildings_on_screen(kind: String) -> void:
    host.selected_units.clear()
    host.selected_buildings.clear()
    var half: Vector2 = host.camera_controller._visible_ground_rect().size / 2.0
    var view := Rect2(host.camera_controller.focus - half, half * 2.0)
    for id: int in host.sim.buildings:
        var b: Dictionary = host.sim.buildings[id]
        if b.owner == host.local_slot and b.type == kind and view.has_point(b.pos):
            host.selected_buildings.append(id)
    if not host.selected_buildings.is_empty():
        host.selected_building = host.selected_buildings[0]
        host._notify("All %ss on screen!" % kind)

# Double-click: grab every on-screen unit of the same kind as the clicked one.
func _select_same_type_on_screen(kind: String) -> void:
    host.selected_units.clear()
    host.selected_building = -1
    var half: Vector2 = host.camera_controller._visible_ground_rect().size / 2.0
    var view := Rect2(host.camera_controller.focus - half, half * 2.0)
    for id: int in host.sim.units:
        var u: Dictionary = host.sim.units[id]
        if u.owner == host.local_slot and u.type == kind and view.has_point(u.pos):
            host.selected_units.append(id)
    if not host.selected_units.is_empty():
        host._respond(host.selected_units[0], "All %ss on screen!" % kind)

func _attack_click(pos: Vector2) -> void:
    var kind := ""
    var target_id := -1
    for id: int in host.sim.units:
        if (host.sim.units[id].pos as Vector2).distance_to(pos) <= 24:
            kind = "unit"
            target_id = id
            break
    if target_id < 0:
        for id: int in host.sim.buildings:
            if host.sim.footprint(host.sim.buildings[id]).has_point(pos):
                kind = "building"
                target_id = id
                break
    if target_id >= 0:
        host.issue({"action": "attack", "units": host.selected_units.duplicate(), "kind": kind, "target": target_id, "force": true})
        host.clicks.append({"pos": pos, "life": 0.55, "action": "attack"})
    else:
        host.issue({"action": "attack_move", "units": host.selected_units.duplicate(), "pos": pos})
        host.clicks.append({"pos": pos, "life": 0.55, "action": "attack_move"})
    if not host.selected_units.is_empty():
        host._respond(host.selected_units[0], "Attack order!")
    host.attack_mode = false

func _select_rect(rect: Rect2) -> void:
    host._clear_selection()
    for id: int in host.sim.units:
        if host.sim.units[id].owner == host.local_slot and rect.has_point(host.sim.units[id].pos):
            host.selected_units.append(id)

# Ctrl+N assigns the selection to group N, Shift+N adds to it, N alone recalls it.
# A group can hold units and/or one building; recalling prefers units for orders.
func _control_group_key(group: int, ctrl: bool, shift: bool) -> void:
    if ctrl:
        if host.selected_units.is_empty() and host.selected_building < 0:
            host.control_groups.erase(group)
            host._notify("Group %d cleared." % group)
            return
        var members: Array[int] = []
        for id: int in host.selected_units:
            members.append(id)
        var building_list: Array[int] = host.selected_buildings.duplicate()
        if building_list.is_empty() and host.selected_building >= 0:
            building_list.append(host.selected_building)
        host.control_groups[group] = {"units": members, "building": host.selected_building, "buildings": building_list}
        var label := "%d unit(s)" % members.size() if not members.is_empty() else "%d building(s)" % host.selected_buildings.size()
        host._notify("Group %d assigned: %s." % [group, label])
        return
    if shift:
        if host.selected_units.is_empty() and host.selected_building < 0:
            return
        var merged: Dictionary = {"units": [], "building": -1}
        if host.control_groups.has(group):
            merged = (host.control_groups[group] as Dictionary).duplicate()
        var current: Array[int] = []
        for value: Variant in merged.get("units", []):
            current.append(int(value))
        for id: int in host.selected_units:
            if not current.has(id):
                current.append(id)
        merged.units = current
        if host.selected_building >= 0:
            merged.building = host.selected_building
        host.control_groups[group] = merged
        host._notify("Group %d now has %d unit(s)." % [group, current.size()])
        return
    if not host.control_groups.has(group):
        return
    var state: Dictionary = host.control_groups[group]
    var group_units: Array[int] = []
    for value: Variant in state.get("units", []):
        var id := int(value)
        if host.sim.units.has(id) and host.sim.units[id].owner == host.local_slot and not group_units.has(id):
            group_units.append(id)
    var group_building := int(state.get("building", -1))
    if group_building >= 0 and (not host.sim.buildings.has(group_building) or host.sim.buildings[group_building].owner != host.local_slot):
        group_building = -1
    if group_units.is_empty() and group_building < 0:
        host.control_groups.erase(group)
        return
    if not group_units.is_empty():
        host.selected_units = group_units
        host.selected_building = -1
        host.selected_buildings.clear()
        host._respond(group_units[0], "Group %d reporting." % group)
    else:
        var group_buildings: Array[int] = []
        for value: Variant in state.get("buildings", []):
            var bid := int(value)
            if host.sim.buildings.has(bid) and host.sim.buildings[bid].owner == host.local_slot and not group_buildings.has(bid):
                group_buildings.append(bid)
        host.selected_units.clear()
        host.selected_buildings = group_buildings
        host.selected_building = group_buildings[0] if not group_buildings.is_empty() else -1
        host._notify("Group %d building ready." % group)

# Guest-side smoothing: derive per-unit velocity from consecutive snapshots.
