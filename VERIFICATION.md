# Correction verification — 2026-09-15

The earlier implementation only contained combat fields and decorative buildings. It has been replaced by an authoritative simulation with working economy, construction, production, combat, match lifecycle, and a separate presentation layer.

## Passed

- 47 simulation assertions: both factions' mining and delivery, finite ore, cargo capacity, construction cost/time/placement, production cost/time/spawn/cancel/limit, factory destruction and refunds, terrain/building navigation, circle separation, pursuit, cooldown, automatic target acquisition, death cleanup, victory freeze, snapshots, AI, fog exploration, friendly fire, and attack-move interception.
- 12 viewport/input assertions: left select, blank deselect, no left movement, right orders and marker, drag selection, building selection, production button callback, placement confirmation, wheel zoom, A-key friendly-fire attack, A-key attack-move, and runtime attack-key rebinding.
- Real rendered OpenGL run of the input test, with screenshot saved to build/verification/gameplay.png.
- Multi-process ENet test: incompatible version rejection, spectator ownership enforcement, red faction mining/building/production/attack/victory, host/client complete-state equality, reconnect and restart, and stopping the guest after host exit.
- Windows release export with embedded resources. Launching IronFront.exe from the build directory without a project.godot or adjacent IronFront.pck completed a 30-frame startup smoke check without logged errors.
- Runtime-generated AudioStreamGenerator cues are wired for shots, hits, build/production actions and soldier responses; the audio player initializes in a release build without external files.

## Evidence and reproduction

- tests/gameplay.gd — GAMEPLAY_TEST 43 checks; failures=[]
- tests/presentation.gd — PRESENTATION_TEST failures=[]
- tests/run_network_guest.ps1 — launches the real host, player and spectator processes; logs under build/verification.
- build/verification/export.log — release export log.
- build/verification/exported.log — standalone release startup log.

Tests were executed against source in Godot. The exported EXE received a startup smoke check; an attempted external test-script run on the release binary did not complete and is not counted as a passed gameplay test. No claims are made about WAN latency/loss, high unit counts, or competitive anti-cheat. Full gameplay network tests used separate local processes.

See README.md for controls, supported features and explicit prototype limits. The new deliverable is build/IronFront.exe; older RTS_Host_P2P_Prototype files are earlier builds.
