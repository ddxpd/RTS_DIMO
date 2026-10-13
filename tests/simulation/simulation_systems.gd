extends SceneTree
## Versioned deterministic traces; v9 remains archived, v11 includes twin-dock rules.
const Sim = preload("res://scripts/simulation.gd")
const BASELINE := "res://tests/fixtures/simulation_systems_v11_baseline.json"
const SAMPLE_BASELINE := "res://tests/fixtures/sample_base_only_trace.json"
const GRID_BASELINE := "res://tests/fixtures/simulation_systems_v14_depot4.json"
const PREVIOUS_GRID := "res://tests/fixtures/simulation_systems_v14_compact_depot.json"
const ARCHIVE := "res://tests/fixtures/simulation_systems_baseline.json"
const ARCHIVE_SHA := "44314a7b43d74c796e574b936696fdf5dafededdc2791c3fc3ddfac68c1509a8"
const ORIGINAL_SHA := "b360c9975aede67a969aec3fc4dff48a8852125252aab6f6ea575c69955f8811"
# Local diagnostic data only: never commit, upload to LFS, or attach to Releases.
const AUDIT_DIR := "res://.local/simulation_audits/"
var trace: Array = []
var failures: Array[String] = []
var capture := false
var expected: Array = []
var commands: Array = []
var capture_sample := false
var sample_trace: Array = []
var sample_expected: Array = []
var audit_states: Array = []
var audit_before := false
var capture_grid := false
var grid_audit: Array = []


func _initialize() -> void:
    run.call_deferred()


func check(ok: bool, message: String) -> void:
    if not ok:
        failures.append(message)
        push_error(message)


func issue(sim, owner: int, command: Dictionary) -> void:
    commands.append([owner, command.duplicate(true), sim.command(owner, command)])


func record(sim, scenario: String, tick: int) -> void:
    # Paths, timers, queues, effects and fog are all present in the snapshot.
    # Include allocation state too: it affects later IDs but is not replicated.
    var snapshot: Dictionary = sim.snapshot()
    # Keep the v11 hash projection so v13 changes can be audited against archived
    # behavior. Grid semantics have a new immutable baseline; rally has direct tests.
    snapshot.version = "rts-desert-only-11"
    for building: Dictionary in snapshot.buildings.values():
        building.erase("rally_mode")
        building.erase("rally_ore")
    var state := [snapshot, sim.next_id, sim.ai_enabled, commands]
    if audit_before or capture_grid:
        audit_states.append({"scenario": scenario, "tick": tick, "state": state.duplicate(true)})
    var digest := HashingContext.new()
    digest.start(HashingContext.HASH_SHA256)
    digest.update(var_to_bytes(state))
    var entry := {"scenario": scenario, "tick": tick, "sha256": digest.finish().hex_encode()}
    var sample_tick := scenario == "reset" and tick >= 30 and tick < 60
    var expected_entry: Dictionary = expected[trace.size()] if trace.size() < expected.size() else {}
    if sample_tick and Sim.VERSION == "rts-desert-only-12":
        sample_trace.append(entry)
        if not capture_sample:
            expected_entry = sample_expected[tick - 30]
    if not capture and not capture_grid and not (sample_tick and capture_sample) and entry != expected_entry and failures.is_empty():
        check(false, "Behavior changed at %s tick %d: expected %s, got %s" % [scenario, tick, expected[trace.size()], entry])
        var file := open_audit_output("simulation-systems-mismatch.bin")
        if file != null:
            file.store_var(state)
    trace.append(entry)
    commands.clear()


func open_audit_output(filename: String) -> FileAccess:
    var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AUDIT_DIR))
    check(error == OK, "Cannot create local audit directory: " + AUDIT_DIR)
    if error != OK:
        return null
    var ignore := FileAccess.open(AUDIT_DIR + ".gdignore", FileAccess.WRITE)
    check(ignore != null, "Cannot exclude local audits from Godot imports")
    if ignore == null:
        return null
    ignore.close()
    var file := FileAccess.open(AUDIT_DIR + filename, FileAccess.WRITE)
    check(file != null, "Cannot write local audit: " + filename)
    return file


func run() -> void:
    audit_before = "--audit-before" in OS.get_cmdline_args() or "--audit-grid-before" in OS.get_cmdline_args() or "--audit-mobile-size-before" in OS.get_cmdline_args() or "--audit-roster-before" in OS.get_cmdline_args() or "--audit-base-only-before" in OS.get_cmdline_args()
    capture_grid = "--capture-depot4" in OS.get_cmdline_args()
    if capture_grid:
        check(not FileAccess.file_exists(GRID_BASELINE), "Refusing to overwrite 4x4 depot baseline")
        var audit_file := FileAccess.open(AUDIT_DIR + "base-only-before.bin", FileAccess.READ)
        check(audit_file != null, "Pre-change audit states are required")
        if audit_file != null:
            grid_audit = audit_file.get_var()
    capture_sample = "--capture-sample-base" in OS.get_cmdline_args()
    if capture_sample:
        check(not FileAccess.file_exists(SAMPLE_BASELINE), "Refusing to overwrite sample baseline")
    else:
        check(FileAccess.file_exists(SAMPLE_BASELINE), "Base-only sample baseline exists")
        if failures.is_empty():
            var sample_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAMPLE_BASELINE))
            check(sample_data.protocol == "rts-desert-only-12" and sample_data.trace.size() == 30, "Archived sample baseline protocol and length")
            sample_expected = sample_data.trace
            for entry: Dictionary in sample_expected:
                entry.tick = int(entry.tick)
    capture = capture or "--capture-depot-v11" in OS.get_cmdline_user_args()
    check(FileAccess.get_sha256(ARCHIVE) == ARCHIVE_SHA, "Original pre-refactor fixture is preserved byte-for-byte")
    if capture:
        check(not FileAccess.file_exists(BASELINE), "Refusing to overwrite frozen baseline")
        check(Sim.VERSION == "rts-desert-only-11", "This capture authorizes only the approved twin-dock protocol")
    else:
        check(FileAccess.file_exists(BASELINE), "Frozen behavior baseline is required")
        if failures.is_empty():
            var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASELINE))
            check(data.archive_sha256 == ARCHIVE_SHA and data.protocol == "rts-desert-only-11" and Sim.VERSION == "rts-desert-only-14", "Frozen v11 provenance and explicit v14 mining adapter")
            expected = data.trace
            if not capture_grid:
                check(FileAccess.file_exists(GRID_BASELINE), "Frozen 4x4 depot baseline exists")
                if failures.is_empty():
                    var grid_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GRID_BASELINE))
                    check(grid_data.get("mobile_radius", -1) == Sim.UNIT_TYPES.mobile_infantry.radius, "Mobile size baseline matches approved radius")
                    check(grid_data.get("active_units", []) == Sim.ACTIVE_UNIT_TYPES, "Baseline matches active roster")
                    check(grid_data.previous_grid_sha256 == FileAccess.get_sha256(PREVIOUS_GRID) and grid_data.protocol == Sim.VERSION and grid_data.previous_sha256 == FileAccess.get_sha256(BASELINE) and grid_data.sample_sha256 == FileAccess.get_sha256(SAMPLE_BASELINE), "Grid baseline preserves previous provenance")
                    expected = grid_data.trace
            # JSON represents all numbers as floats; normalize the trace index only.
            for entry: Dictionary in expected:
                entry.tick = int(entry.tick)
    if not failures.is_empty():
        quit(1)
        return
    ai_scenario()
    mixed_scenario()
    flight_scenario()
    reset_scenario()
    if capture_grid and failures.is_empty():
        check(grid_audit.size() == audit_states.size(), "Every grid audit state has a previous counterpart")
        var report: Dictionary = {}
        for index in range(audit_states.size()):
            var after: Dictionary = audit_states[index]
            var before: Dictionary = grid_audit[index]
            var section: Dictionary = report.get(after.scenario, {"changed_ticks": 0, "unchanged_ticks": 0, "first_change": {}, "changed_fields": {}})
            if before.state == after.state:
                section.unchanged_ticks += 1
            else:
                section.changed_ticks += 1
                if section.first_change.is_empty():
                    section.first_change = {"tick": after.tick, "details": first_changes(before.state[0], after.state[0])}
                for field: String in after.state[0]:
                    if before.state[0].get(field) != after.state[0][field]:
                        section.changed_fields[field] = int(section.changed_fields.get(field, 0)) + 1
            report[after.scenario] = section
        var report_file := open_audit_output("depot4-baseline-audit.json")
        if report_file != null:
            report_file.store_string(JSON.stringify(report, "  "))
        var grid_file := FileAccess.open(GRID_BASELINE, FileAccess.WRITE)
        grid_file.store_string(JSON.stringify({"protocol": Sim.VERSION, "mobile_radius": Sim.UNIT_TYPES.mobile_infantry.radius, "active_units": Sim.ACTIVE_UNIT_TYPES, "base_only_start": true, "hash_projection": "v11 snapshot fields", "previous_grid_sha256": FileAccess.get_sha256(PREVIOUS_GRID), "previous_sha256": FileAccess.get_sha256(BASELINE), "sample_sha256": FileAccess.get_sha256(SAMPLE_BASELINE), "reason": "Approved 4x4 ore depot: 12 solid cells and two internal 1x2 traversable lanes; full 16-cell construction reservation. Harvester size unchanged, temporary exterior unload stops. Previous compact depot trace retained.", "audit": report, "trace": trace}, "  ") + "\n")
    if capture_sample and failures.is_empty():
        var sample_file := FileAccess.open(SAMPLE_BASELINE, FileAccess.WRITE)
        sample_file.store_string(JSON.stringify({"protocol": Sim.VERSION, "reason": "User requested base-only sample v4: no initial units, production buildings or ore. Only reset ticks 30-59 change; all other frozen v11 entries still compared.", "trace": sample_trace}, "  ") + "\n")
    if capture and failures.is_empty():
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/fixtures"))
        var file := FileAccess.open(BASELINE, FileAccess.WRITE)
        file.store_string(JSON.stringify({"source_sha256": FileAccess.get_sha256("res://scripts/simulation.gd"), "archive_sha256": ARCHIVE_SHA, "reason": "Approved ore depot: 352x320 compound footprint, deterministic dual-berth queue and unload/exit; mixed fixture starts outside body and allows full round trips.", "protocol": Sim.VERSION, "trace": trace}, "  ") + "\n")
    elif not capture:
        check(trace.size() == expected.size(), "All frozen ticks were compared")
    if audit_before and failures.is_empty():
        var audit_name := "mobile-size-before.bin" if "--audit-mobile-size-before" in OS.get_cmdline_args() else "mining-before.bin"
        if "--audit-roster-before" in OS.get_cmdline_args():
            audit_name = "roster-before.bin"
        if "--audit-base-only-before" in OS.get_cmdline_args():
            audit_name = "base-only-before.bin"
        if "--audit-before" in OS.get_cmdline_args():
            audit_name = "current-before.bin"
        var audit_file := open_audit_output(audit_name)
        if audit_file != null:
            audit_file.store_var(audit_states)
            audit_file.close()
            var saved := FileAccess.open(AUDIT_DIR + audit_name, FileAccess.READ)
            check(saved != null, "Local audit can be reopened")
            if saved != null:
                check(saved.get_var() == audit_states, "Local audit round trip preserves full states")
    print("SIMULATION_SYSTEMS ticks=", trace.size(), " capture=", capture, " failures=", failures)
    quit(0 if failures.is_empty() else 1)


func first_changes(before: Dictionary, after: Dictionary) -> Array:
    var changes: Array = []
    for category: String in ["buildings", "units"]:
        for id: int in after[category]:
            if not before[category].has(id):
                changes.append({"entity": category + "/" + str(id), "added": str(after[category][id])})
                continue
            for key: String in after[category][id]:
                if before[category][id].get(key) != after[category][id][key]:
                    changes.append({"entity": category + "/" + str(id), "field": key, "before": str(before[category][id].get(key)), "after": str(after[category][id][key])})
    return changes


func ai_scenario() -> void:
    var sim := Sim.new()
    sim.reset(true)
    record(sim, "ai", -1)
    for tick in range(700):
        if tick == 90:
            sim.add_unit(1, "soldier", Vector2(4096, 2784))
        if tick == 300:
            issue(sim, 1, {"action": "move", "units": [3, 4, 5], "pos": Vector2(1000, 700)})
        sim.step()
        record(sim, "ai", tick)
    check(sim.buildings.size() > 2 and sim.units.size() > 13, "AI scenario exercises construction and production")


func mixed_scenario() -> void:
    var sim := Sim.new()
    sim.reset()
    sim.units.clear()
    var refinery: int = sim._add_building(1, "refinery", Vector2(768, 1792), true)
    var factory: int = sim._add_building(1, "barracks", Vector2(1600, 1900), true)
    var bunker: int = sim._add_building(1, "bunker", Vector2(1600, 2240), true)
    sim.ores[1] = {"pos": Vector2(1088, 1792), "amount": 95}
    var miner: int = sim.add_unit(1, "harvester", Vector2(1040, 1792))
    var fighter: int = sim.add_unit(1, "mobile_infantry", Vector2(1400, 2112))
    var enemy: int = sim.add_unit(2, "soldier", Vector2(1720, 2240))
    var blocker: int = sim.add_unit(1, "harvester", Vector2(1612.36, 1824))
    sim.units[blocker].auto = false
    sim.rebuild_navigation()
    sim.update_visibility()
    issue(sim, 1, {"action": "gather", "units": [miner], "target": 1})
    issue(sim, 1, {"action": "produce", "building": factory, "type": "mobile_infantry"})
    issue(sim, 1, {"action": "produce", "building": factory, "type": "mobile_infantry"})
    issue(sim, 1, {"action": "set_rally", "building": factory, "pos": Vector2(1450, 2000)})
    issue(sim, 1, {"action": "attack_move", "units": [fighter], "pos": Vector2(1720, 2200)})
    issue(sim, 0, {"action": "move", "units": [miner], "pos": Vector2.ZERO})
    issue(sim, 1, {"action": "produce", "building": refinery, "type": "mobile_infantry"})
    record(sim, "mixed", -1)
    var partial_returned := false
    for tick in range(900):
        if tick == 10:
            issue(sim, 1, {"action": "cancel_production", "building": factory})
        if tick == 55:
            check(sim.buildings[factory].queue.size() == 1 and sim.buildings[factory].queue[0].remaining == 0, "Production waits at blocked exit")
        if tick == 60:
            issue(sim, 1, {"action": "move", "units": [blocker], "pos": Vector2(1800, 1700)})
        if tick == 100:
            issue(sim, 1, {"action": "stop", "units": [fighter]})
        if tick == 125:
            issue(sim, 1, {"action": "attack", "units": [fighter], "kind": "unit", "target": enemy})
        if tick == 210:
            issue(sim, 1, {"action": "produce", "building": factory, "type": "mobile_infantry"})
            sim.buildings[factory].hp = 0
        if tick == 300:
            sim.buildings[bunker].hp = 0
        sim.step()
        partial_returned = partial_returned or (sim.ores[1].amount == 0 and sim.units[miner].cargo == 0)
        record(sim, "mixed", tick)
    check(partial_returned, "Miner returns the exhausted partial load before automatically gathering elsewhere")
    check(not sim.buildings.has(factory) and not sim.units.has(enemy), "Scenario covers death cleanup and queued-building refund")


func flight_scenario() -> void:
    var sim := Sim.new()
    sim.reset()
    sim.units.clear()
    var id: int = sim._add_building(1, "barracks", Vector2(1600, 1900), true)
    sim.rebuild_navigation()
    sim.update_visibility()
    issue(sim, 1, {"action": "barracks_takeoff", "building": id})
    record(sim, "flight", -1)
    for tick in range(300):
        if tick == 85:
            issue(sim, 1, {"action": "barracks_move", "building": id, "pos": Vector2(1792, 1888)})
        if tick == 140:
            issue(sim, 1, {"action": "barracks_stop", "building": id})
        if tick == 145:
            sim.visible[1].fill(1)
            issue(sim, 1, {"action": "barracks_deploy", "building": id, "pos": Vector2(1728, 1888)})
        sim.step()
        record(sim, "flight", tick)
    check(sim.buildings[id].flight.state == "grounded", "Flight scenario completes deployment")


func reset_scenario() -> void:
    var sim := Sim.new()
    sim.reset()
    var mirror := Sim.new()
    mirror.reset()
    for tick in range(120):
        if tick == 0:
            check(sim.units.is_empty() and sim.buildings.size() == 2, "Formal reset has only two bases")
        if tick == 30:
            sim.reset(false, "desert_sample")
            check(sim.units.is_empty() and sim.ores.is_empty() and sim.buildings.size() == 1 and sim.buildings[1].type == "base", "Sample switch keeps only the main base")
        if tick == 60:
            sim.reset()
        if tick == 90:
            sim.buildings[2].hp = 0
        sim.step()
        check(mirror.apply_snapshot(sim.snapshot()), "Snapshot accepted during reset/map switch")
        check(mirror.snapshot() == sim.snapshot(), "Mirror keeps complete snapshot during reset/map switch")
        record(sim, "reset", tick)
