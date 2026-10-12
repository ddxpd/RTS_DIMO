@tool
extends "res://addons/godot_ai/testing/test_suite.gd"

const Sim = preload("res://scripts/simulation.gd")


func suite_name() -> String:
    return "mobile_infantry_gameplay"


func test_small_body_passages_and_formation() -> void:
    var sim := Sim.new()
    sim.reset(false, "desert_sample")
    sim.units.clear()
    sim.buildings.clear()
    sim.ores.clear()
    sim.obstacles.clear()
    sim.ai_enabled = false
    sim._add_building(1, "base", Vector2(384, 384), true)
    sim._add_building(2, "base", Vector2(4416, 2816), true)
    var radius: float = Sim.UNIT_TYPES.mobile_infantry.radius
    assert_eq(radius, 12.0, "Mobile body radius is 12 world units")
    assert_eq(radius * 2.0 / Sim.CELL, 0.75, "Mobile body diameter is 0.75 cells")
    # Grid-aligned bunkers leave precisely one cell between their footprints.
    var origin := Vector2(1024, 128)
    sim._add_building(1, "bunker", origin + Vector2(928, 928), true)
    var right: int = sim._add_building(1, "bunker", origin + Vector2(1024, 928), true)
    sim.rebuild_navigation()
    var start := origin + Vector2(976, 816)
    var finish := origin + Vector2(976, 1040)
    assert_true(sim.movement_free(start, finish, radius), "New body fits a one-cell corridor")
    assert_true(not sim.movement_free(start, finish, 18.0), "Old body could not fit that corridor")
    var id := sim.add_unit(1, "mobile_infantry", start)
    assert_eq(sim.command(1, {"action": "move", "units": [id], "pos": finish}), "", "Move through one-cell gap")
    var crossed := false
    var legal := true
    for tick in range(140):
        var previous: Vector2 = sim.units[id].pos
        sim.step()
        var point: Vector2 = sim.units[id].pos
        legal = legal and sim.movement_free(previous, point, radius)
        crossed = crossed or (point.y > origin.y + 896 and point.y < origin.y + 960 and absf(point.x - start.x) < 4.01)
    assert_true(crossed and legal and sim.units[id].pos.distance_to(finish) < 8, "Actual unit crosses the gap without clipping")
    sim.buildings[right].pos.x -= 32
    sim.rebuild_navigation()
    assert_true(not sim.movement_free(origin + Vector2(960, 816), origin + Vector2(960, 1040), radius), "Touching buildings still form an impassable seam")
    sim.obstacles.assign([Rect2(origin + Vector2(1300, 880), Vector2(64, 160)), Rect2(origin + Vector2(1384, 880), Vector2(64, 160))])
    assert_true(not sim.movement_free(origin + Vector2(1374, 816), origin + Vector2(1374, 1104), radius), "20-unit diagnostic slit rejects 24-unit body")
    sim.obstacles.clear()
    sim.units.clear()
    sim.rebuild_navigation()
    var squad: Array = []
    for i in range(8):
        squad.append(sim.add_unit(1, "mobile_infantry", origin + Vector2(704 + i * 28, 1168)))
    for destination: Vector2 in [Vector2(1200, 1264), Vector2(688, 1104)]:
        assert_eq(sim.command(1, {"action": "move", "units": squad, "pos": origin + destination}), "", "Dense squad move and reverse")
        for tick in range(300):
            sim.step()
        for a: int in squad:
            assert_true(sim.units[a].order == "idle", "Small infantry settles into formation")
            assert_true(sim.position_free(sim.units[a].pos, radius), "Formation avoids static obstacles")
            for b: int in squad:
                if b > a:
                    assert_true(sim.units[a].pos.distance_to(sim.units[b].pos) >= radius * 2 - 0.1, "Formation bodies do not overlap")


func test_production_and_restrictions() -> void:
    var sim := Sim.new()
    sim.reset()
    sim.units.clear()
    var barracks: int = sim._add_building(1, "barracks", Vector2(800, 600), true)
    var refinery: int = sim._add_building(1, "refinery", Vector2(1000, 600), true)
    var money: int = sim.money[1]
    assert_eq(sim.command(1, {"action": "produce", "building": barracks, "type": "mobile_infantry"}), "", "Barracks accepts new infantry")
    assert_eq(sim.money[1], money - 100, "Production cost")
    assert_true(not sim.command(1, {"action": "produce", "building": refinery, "type": "mobile_infantry"}).is_empty(), "Wrong producer rejected")
    assert_true(not sim.command(2, {"action": "produce", "building": barracks, "type": "mobile_infantry"}).is_empty(), "Enemy producer rejected")
    sim.command(1, {"action": "cancel_production", "building": barracks})
    assert_eq(sim.money[1], money, "Cancellation refunds cost")
    sim.buildings[barracks].remaining = 1
    assert_true(not sim.command(1, {"action": "produce", "building": barracks, "type": "mobile_infantry"}).is_empty(), "Incomplete barracks rejected")
    sim.buildings[barracks].remaining = 0
    for state in ["taking_off", "airborne", "landing"]:
        sim.buildings[barracks].flight.state = state
        assert_true(not sim.command(1, {"action": "produce", "building": barracks, "type": "mobile_infantry"}).is_empty(), "No training while " + state)
    sim.buildings[barracks].flight.state = "grounded"
    sim.command(1, {"action": "set_rally", "building": barracks, "pos": Vector2(1200, 600)})
    sim.command(1, {"action": "produce", "building": barracks, "type": "mobile_infantry"})
    for tick in range(50):
        sim.step()
    var produced := 0
    for unit: Dictionary in sim.units.values():
        if unit.type == "mobile_infantry":
            produced += 1
            assert_eq(unit.order, "move", "New infantry follows barracks rally")
    assert_eq(produced, 1, "Production finishes and spawns new kind")


func test_combat_and_snapshot() -> void:
    var sim := Sim.new()
    sim.reset()
    var own: int = sim.add_unit(1, "mobile_infantry", Vector2(1200, 500))
    var enemy: int = sim.add_unit(2, "mobile_infantry", Vector2(1260, 500))
    assert_true(Sim.is_combat_unit("mobile_infantry"), "Mobile infantry has combat capability")
    assert_true(not Sim.is_combat_unit("harvester"), "Miner is not a combat unit")
    sim.update_visibility()
    assert_eq(sim.command(1, {"action": "attack", "units": [own], "kind": "unit", "target": enemy}), "", "Attack command accepted")
    for tick in range(3):
        sim.step()
    assert_true(sim.units[enemy].hp < 100, "Weapon deals authoritative damage")
    sim.units[enemy].hp = 0
    sim.step()
    assert_true(not sim.units.has(enemy), "Dead unit removed immediately")
    var events: Array = sim.effects.filter(func(event: Dictionary) -> bool: return event.get("entity_id", -1) == enemy)
    assert_eq(events.size(), 1, "Death has one identity-bearing event")
    var snapshot: Dictionary = sim.snapshot()
    var guest := Sim.new()
    guest.reset()
    assert_true(guest.apply_snapshot(snapshot), "New unit and death event roundtrip")
    assert_eq(guest.units[own].type, "mobile_infantry", "Guest preserves type")
    if not events.is_empty():
        var bad := snapshot.duplicate(true)
        for event: Dictionary in bad.effects:
            if event.has("entity_id"):
                event.entity_id = "invalid"
        assert_true(not guest.apply_snapshot(bad), "Malformed death identity rejected")
    var old := snapshot.duplicate(true)
    old.version = "rts-barracks-heading-6"
    assert_true(not guest.apply_snapshot(old), "Old protocol rejected")


func test_mixed_orders_and_ai() -> void:
    var sim := Sim.new()
    sim.reset()
    var old: int = sim.add_unit(1, "soldier", Vector2(1200, 500))
    var mobile: int = sim.add_unit(1, "mobile_infantry", Vector2(1230, 500))
    assert_eq(sim.command(1, {"action": "attack_move", "units": [old, mobile], "pos": Vector2(1500, 500)}), "", "Mixed army attack move")
    for id in [old, mobile]:
        assert_eq(sim.units[id].order, "attack_move", "Both infantry kinds receive order")
    assert_eq(sim.command(1, {"action": "stop", "units": [old, mobile]}), "", "Mixed army stop")
    for id in [old, mobile]:
        assert_eq(sim.units[id].order, "idle", "Both infantry kinds stop")
    for has_moving_infantry in [false, true]:
        var army := Sim.new()
        army.reset()
        army.units.clear()
        var barracks: int = army._add_building(2, "barracks", Vector2(3700, 2600), true)
        if has_moving_infantry:
            var busy: int = army.add_unit(2, "mobile_infantry", Vector2(3900, 2800))
            army.command(2, {"action": "move", "units": [busy], "pos": Vector2(3800, 2800)})
        army._ai_step()
        assert_eq(army.buildings[barracks].queue[0].type, "mobile_infantry", "AI produces only active infantry with either idle or moving army")
