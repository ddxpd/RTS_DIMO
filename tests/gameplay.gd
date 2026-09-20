extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
var failures: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
    checks += 1
    if not value:
        failures.append(message)
        push_error(message)

func advance(s: RefCounted, ticks: int) -> void:
    for i in range(ticks):
        s.step()

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    var s := Sim.new()
    s.reset()
    check(s.units.size() == 12 and s.buildings.size() == 2, "Starting armies / bases")
    check(s.command(0, {"action": "move", "units": [3], "pos": Vector2(400, 300)}) != "", "Spectator rejected")
    check(s.command(2, {"action": "move", "units": [3], "pos": Vector2(400, 300)}) != "", "Enemy control rejected")
    check(s.command(1, {"action": "move", "units": [3], "pos": Vector2(NAN, 1)}) != "", "Non-finite position rejected")
    var blue_miner: int = s.add_unit(1, "harvester", Vector2(600, 800))
    check(s.command(1, {"action": "gather", "units": [blue_miner], "target": 1}) == "", "Harvester accepts ore order")
    var blue_refinery: int = s._add_building(1, "refinery", Vector2(288, 432), true)
    var red := Sim.new()
    red.reset()
    var red_refinery: int = red._add_building(2, "refinery", Vector2(4416, 2496), true)
    advance(s, 900)
    check(s.money[1] > 6000, "Harvester delivers cargo for spendable credits")
    check(s.ores[1].amount < 4000, "Ore is depleted by harvesting")
    check(s.units[5].cargo <= 60, "Cargo capacity respected")
    var red_miner: int = red.add_unit(2, "harvester", Vector2(4200, 2600))
    red.command(2, {"action": "gather", "units": [red_miner], "target": 2})
    advance(red, 900)
    check(red.money[2] > 6000, "Red harvester delivers credits")
    var before: int = s.money[1]
    check(s.command(1, {"action": "build", "type": "barracks", "pos": Vector2(704, 320)}) == "", "Barracks placement succeeds")
    var barracks: int = s.next_id - 1
    check(s.money[1] == before - 250, "Construction costs deducted")
    check(s.buildings[barracks].remaining > 0, "Construction is timed")
    check(s.command(1, {"action": "produce", "building": barracks, "type": "soldier"}) != "", "Incomplete building cannot produce")
    check(s.command(1, {"action": "build", "type": "barracks", "pos": Vector2(704, 320)}) != "", "Overlapping building rejected")
    check(s.command(1, {"action": "build", "type": "barracks", "pos": Vector2(2400, 400)}) != "", "Terrain or remote construction rejected")
    s.command(1, {"action": "stop", "units": [5]})
    advance(s, 80)
    check(s.buildings[barracks].remaining == 0, "Construction completes")
    var count: int = s.units.size()
    var credits: int = s.money[1]
    check(s.command(1, {"action": "produce", "building": barracks, "type": "soldier"}) == "", "Soldier production accepted")
    check(s.money[1] == credits - 100, "Production charged once")
    advance(s, 49)
    check(s.units.size() == count, "Production waits for timer")
    advance(s, 1)
    check(s.units.size() == count + 1 and s.buildings[barracks].queue.is_empty(), "Production actually spawns soldier")
    check(s.command(1, {"action": "produce", "building": 1, "type": "harvester"}) != "", "Base no longer produces miners")
    check(s.command(1, {"action": "produce", "building": barracks, "type": "harvester"}) != "", "Barracks only produces soldiers")
    check(s.command(1, {"action": "produce", "building": blue_refinery, "type": "soldier"}) != "", "Refinery only produces miners")
    s.command(1, {"action": "produce", "building": blue_refinery, "type": "harvester"})
    s.command(1, {"action": "cancel_production", "building": blue_refinery})
    check(s.money[1] == credits - 100, "Cancellation refunds full price")
    s.money[1] = 0
    check(s.command(1, {"action": "produce", "building": barracks, "type": "soldier"}) != "", "Insufficient credits rejected")
    s.money[1] = 1000
    for i in range(5):
        s.command(1, {"action": "produce", "building": barracks, "type": "soldier"})
    check(s.command(1, {"action": "produce", "building": barracks, "type": "soldier"}) != "", "Queue limit enforced")
    check(not s.position_free(Vector2(704, 320), 11), "Building footprint blocks movement")
    # Destruction refunds queued jobs and frees its navigation footprint.
    s.buildings[barracks].hp = 0
    var refund_start: int = s.money[1]
    s.step()
    check(not s.buildings.has(barracks) and s.money[1] == refund_start + 500, "Destroyed factory clears and refunds production queue")
    check(s.position_free(Vector2(704, 320), 11), "Destroyed building releases footprint")
    # Navigation must route around the middle terrain obstacle.
    s.reset()
    s.units[3].pos = Vector2(1900, 400)
    s.command(1, {"action": "move", "units": [3], "pos": Vector2(2700, 400)})
    var valid := true
    for i in range(700):
        s.step()
        if not s.position_free(s.units[3].pos, 11):
            valid = false
    check(valid, "Unit never enters terrain / building volume")
    check((s.units[3].pos as Vector2).distance_to(Vector2(2700, 400)) < 8, "Path reaches destination beyond obstacle")
    # Repeated movement to a shared destination keeps circle bodies separate.
    s.reset()
    s.units[3].pos = Vector2(580, 560)
    s.units[4].pos = Vector2(580, 560)
    advance(s, 2)
    check((s.units[3].pos as Vector2).distance_to(s.units[4].pos) >= 22.9, "Overlapping units separate")
    s.command(1, {"action": "move", "units": [3, 4], "pos": Vector2(600, 600)})
    advance(s, 200)
    check((s.units[3].pos as Vector2).distance_to(s.units[4].pos) >= 22.9, "Moving group keeps collision spacing")
    # Head-on miners must sidestep past each other instead of deadlocking.
    var west := s.add_unit(1, "harvester", Vector2(1000, 1900))
    var east := s.add_unit(1, "harvester", Vector2(1400, 1900))
    s.command(1, {"action": "move", "units": [west], "pos": Vector2(1400, 1900)})
    s.command(1, {"action": "move", "units": [east], "pos": Vector2(1000, 1900)})
    var west_arrived := false
    var east_arrived := false
    for i in range(400):
        s.step()
        if (s.units[west].pos as Vector2).distance_to(Vector2(1400, 1900)) < 25:
            west_arrived = true
        if (s.units[east].pos as Vector2).distance_to(Vector2(1000, 1900)) < 25:
            east_arrived = true
        if west_arrived and east_arrived:
            break
    check(west_arrived, "West miner crosses after head-on meeting")
    check(east_arrived, "East miner crosses after head-on meeting")
    # Chase, cooldown, damage, effects, safe removal and stale target reset.
    s.reset()
    s.units[3].pos = Vector2(300, 400)
    s.units[9].pos = Vector2(600, 400)
    s.units[9].hp  = 32
    check(s.command(1, {"action": "attack", "units": [3], "kind": "unit", "target": 9}) == "", "Enemy attack order accepted")
    var shots := false
    for i in range(300):
        s.step()
        if not s.effects.is_empty():
            shots = true
    check(shots and not s.units.has(9), "Chasing attack fires, damages and removes enemy")
    check(s.units[3].attack_id == -1, "Dead target released")
    s.reset()
    s.units[3].pos = Vector2(900, 400)
    s.units[9].pos = Vector2(950, 400)
    advance(s, 2)
    check(s.units[9].hp == 84, "Idle soldier automatically acquires enemy")
    advance(s, 5)
    check(s.units[9].hp == 84, "Cooldown prevents damage every frame")
    s.reset()
    var auto_miner: int = s.add_unit(1, "harvester", Vector2(800, 900))
    advance(s, 10)
    check(s.units[auto_miner].order == "gather", "Idle miner auto-seeks nearest visible ore")
    s.command(1, {"action": "stop", "units": [auto_miner]})
    advance(s, 20)
    check(s.units[auto_miner].order == "idle", "Stopped miner stays idle")
    s.reset()
    s.units.clear()
    var attacker := s.add_unit(1, "soldier", Vector2(4320, 2880))
    s.buildings[2].hp = 16
    var red_outpost := s._add_building(2, "barracks", Vector2(4416, 2432), true)
    s.buildings[red_outpost].hp = 16
    s.command(1, {"action": "attack", "units": [attacker], "kind": "building", "target": 2})
    advance(s, 3)
    check(not s.buildings.has(2) and s.winner == 0, "Losing the base alone no longer ends the match")
    s.units[attacker].pos = Vector2(4352, 2368)
    s.command(1, {"action": "attack", "units": [attacker], "kind": "building", "target": red_outpost})
    advance(s, 12)
    check(not s.buildings.has(red_outpost) and s.winner == 1, "Destroy last enemy building to win")
    var frozen := s.frame
    s.step()
    check(s.frame == frozen, "Match freezes after victory")
    check(s.command(1, {"action": "build", "type": "barracks", "pos": Vector2(400, 160)}) != "", "Orders rejected after match")
    s.reset()
    s.units[4].hp = 100
    check(s.command(1, {"action": "attack", "units": [3], "kind": "unit", "target": 4, "force": true}) == "", "Force attack accepts friendly unit")
    advance(s, 2)
    check(s.units[4].hp < 100, "Force attack damages selected friendly target")
    s.reset()
    s.units[3].pos   = Vector2(1000, 400)
    s.units[4].pos   = Vector2(800, 400)
    s.units[4].owner = 2
    check(s.command(1, {"action": "attack_move", "units": [3], "pos": Vector2(600, 160)}) == "", "Attack-move order accepted")
    advance(s, 80)
    check((not s.units.has(4) or s.units[4].hp < 100) and s.units[3].pos.x > 600, "Attack-move stops and engages encountered enemy")
    var mirror := Sim.new()
    mirror.reset()
    mirror.apply_snapshot(s.snapshot())
    check(mirror.snapshot() == s.snapshot(), "Snapshot carries combat, economy, buildings, effects, result")
    s.reset(true)
    check(s.can_see(1, Vector2(384, 384)) and not s.can_see(1, Vector2(4416, 2816)), "Fog starts around own army only")
    s.units[3].pos = Vector2(1000, 700)
    s.update_visibility()
    check(s.can_see(1, Vector2(1000, 700)), "Scout reveals new terrain")
    s.units[3].pos = Vector2(640, 320)
    s.update_visibility()
    var cell := Vector2i(31, 21)
    check(not s.can_see(1, Vector2(1000, 700)) and s.explored[1][cell.y * Sim.GRID.x + cell.x] == 1, "Explored terrain stays remembered when vision leaves")
    advance(s, 1400)
    var ai_building := false
    for b: Dictionary in s.buildings.values():
        if b.owner == 2 and b.type == "barracks" and b.remaining == 0:
            ai_building = true
    check(ai_building and s.units.size() > 12 and s.ores[2].amount < 4000, "AI mines, constructs and produces")
    print("GAMEPLAY_TEST ", checks, " checks; failures=", failures)
    quit(0 if failures.is_empty() else 1)
