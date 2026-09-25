# Correction verification — 2026-09-15

The earlier implementation only contained combat fields and decorative buildings. It has been replaced by an authoritative simulation with working economy, construction, production, combat, match lifecycle, and a separate presentation layer.

## Bunker model and animation verification - 2026-09-24

- Source model saved in `assets/models/source/ironfront_models.blend`; runtime GLB exported to `assets/models/bunker.glb` (390,848 bytes).
- Godot runtime hierarchy resolves `bunker/Turret/Barrel_L`, `Barrel_R`, `MuzzleFlash`, `BlastShutter_L`, `Stabilizer_L`, `SensorMast`, and `FactionSensor`.
- Runtime animation counts: construction 7 tracks, idle 3 tracks, fire 5 tracks.
- Mid-animation evaluation: idle turret Y = 0.10 and sensor mast Y = 0.04; fire barrels Z = 0.48 with muzzle scale = (1.40, 0.75); construction shutter scale = 0.575 and stabilizer scale = 0.55.
- Project launch reported the game helper live with no current or recent project errors.
- Direct headless runs passed `tests/visual_models.gd` (`failures=[]`), `tests/gameplay.gd` (57 checks / 0 failures), and `tests/presentation.gd` (`failures=[]`). The editor MCP test runner independently discovered 0 registered suites in this session.
- Orientation regression: symptom was a loaded new hierarchy that appeared like the old bunker from the gameplay camera; root cause was the Blender-to-Godot front axis on the new bunker. Fix moved front plates/shutters to Godot -Z and set the turret plus idle/fire tracks to a π base rotation. Runtime check reports turret Y ≈ 3.24 and shutter Z = -1.08.

## Passed

- 47 simulation assertions: both factions' mining and delivery, finite ore, cargo capacity, construction cost/time/placement, production cost/time/spawn/cancel/limit, factory destruction and refunds, terrain/building navigation, circle separation, pursuit, cooldown, automatic target acquisition, death cleanup, victory freeze, snapshots, AI, fog exploration, friendly fire, and attack-move interception.
- 12 viewport/input assertions: left select, blank deselect, no left movement, right orders and marker, drag selection, building selection, production button callback, placement confirmation, wheel zoom, A-key friendly-fire attack, A-key attack-move, and runtime attack-key rebinding.
- Real rendered OpenGL run of the input test, with screenshot saved to build/verification/gameplay.png.
- Multi-process ENet test: incompatible version rejection, spectator ownership enforcement, red faction mining/building/production/attack/victory, host/client complete-state equality, reconnect and restart, and stopping the guest after host exit.
- Windows release export with embedded resources. Launching IronFront.exe from the build directory without a project.godot or adjacent IronFront.pck completed a 30-frame startup smoke check without logged errors.
- Runtime-generated AudioStreamGenerator cues are wired for shots, hits, build/production actions and soldier responses; the audio player initializes in a release build without external files.

## 2026-09-25：validated simulation snapshot boundary

- `Simulation.validate_snapshot()` now requires the complete snapshot top-level schema and validates strict Variant types, enum values, world/vector bounds, HP/timers/cargo/work/cooldowns, production queues, effect metadata, money owners, visibility/exploration buffers, and per-table size caps.
- `Simulation.apply_snapshot()` rejects before mutation and deep-copies all accepted tables.
- `NetworkSession` and main compatibility RPC wrappers handle rejected matching snapshots by disconnecting and reporting the validator error; stale or mismatched world packets remain ignored.
- Focused regression coverage in `tests/gameplay.gd`: valid acceptance, missing tables, numeric-string coercion, out-of-bounds unit position, incomplete effect, incomplete visibility, and oversized unit table. Result: `GAMEPLAY_TEST 64 checks; failures=[]`.
- Final source regressions: `presentation`, `visual_models`, `features`, `camera`, and `action_bar` all `failures=[]`; full ENet host/guest/spectator regression passed protocol mismatch, permissions, both rounds, snapshot equality, reconnect, and host disconnect.
- Visual-performance probe had two near-threshold samples above 8ms (8.08645 and 8.1944) and two independent passing retries (7.57705 and 7.2757); no gameplay or rendering code change was made for this timing noise.
- Fresh export: `build/IronFront.exe`, 110,233,632 bytes, embedded resources. Exported headless process exited 0 after `--quit-after 180`; a rendered exported process stayed alive for five seconds before clean termination.

## Evidence and reproduction

- tests/gameplay.gd — GAMEPLAY_TEST 43 checks; failures=[]
- tests/presentation.gd — PRESENTATION_TEST failures=[]
- tests/run_network_guest.ps1 — launches the real host, player and spectator processes; logs under build/verification.
- build/verification/export.log — release export log.
- build/verification/exported.log — standalone release startup log.

Tests were executed against source in Godot. The exported EXE received a startup smoke check; an attempted external test-script run on the release binary did not complete and is not counted as a passed gameplay test. No claims are made about WAN latency/loss, high unit counts, or competitive anti-cheat. Full gameplay network tests used separate local processes.

See [README.md](../README.md) for controls, supported features and explicit prototype limits. The new deliverable is build/IronFront.exe; older RTS_Host_P2P_Prototype files are earlier builds.

## 2026-09-22：Blender 3D 模型替换验证
- 静态导入：8 个 GLB 均被 Godot 识别为 PackedScene；源 .blend 目录用 .gdignore 排除，避免把源编辑文件当作运行时资源。
- 视觉测试：tests/visual_models.gd 覆盖模型实例、动画清单、士兵 move/attack、采集车 mine/unload、施工/生产/地堡开火、资源迷雾与建筑预览，failures=[]。
- 核心回归：visual_models 0；gameplay 57 checks / 0 failures；features 0；camera 0；action_bar 0；presentation 0。
- 多人验证：tests/run_network_guest.ps1 全部 PASS，包括协议不匹配拒绝、观战权限、红方采矿/建造/生产/攻击/胜利、两轮完整快照一致、重开与主机退出处理。
- 实机画面：build/verification/visual_models.png；战场裁剪区绿色地面约 67%，机械灰约 11%，迷雾/阴影约 14%，存在蓝色阵营与黄色矿石像素。
- 导出：build/IronFront.exe，111,121,248 字节，时间 2026-09-22 08:43:23，PCK 内嵌。
- 导出版运行：`--headless --quit-after 180` 退出码 0；真实渲染进程 5 秒后仍存活并按计划关闭。

## 2026-09-22：本地效果图收藏网页
- 新增 `tools/effect-gallery/index.html`、`README.md`、`start.ps1`。
- 静态服务验证：`GET /` 返回 200，Content-Type `text/html`。
- HTML 结构：doctype 正确、无未闭合标签、无重复 ID。
- JavaScript：两个 script 块通过 Node 语法检查。
- PowerShell：`start.ps1` 通过 Parser 检查；支持 python/py 与自动空闲端口。
- Godot 回归：visual_models、gameplay、features、camera、action_bar、presentation 全部退出码 0。
- 导出：build/IronFront.exe，111,121,248 bytes，2026-09-22 12:32:16；headless 冒烟退出码 0，真实渲染进程 5 秒存活。
- 限制：当前会话 Browser runtime 初始化成功但浏览器列表为空，未能自动执行上传/收藏/刷新持久化的真实浏览器 UI 测试。

## 2026-09-23：3D 分支审查修正
- 行为修复：空采集车货物条整体隐藏；士兵追击时 move、进入射程后 attack；岩石变换改为确定性哈希；guest 渲染速度回退修复。
- 性能修复：EntityVisual 状态变化早退、共享 AnimationLibrary、隐藏实体暂停动画、单位远距小件 LOD、单位阴影关闭、状态条/预览无阴影。
- 模型优化：Blender 源文件合并同材质静态网格，8 个模型 Mesh 对象 123→76；重导 GLB；glTF 内嵌贴图，删除 8 张重复 PNG。
- 模拟优化：单位分离改为 64px 空间哈希，寻路重算按目标哈希错峰。
- 核心回归：visual_models、visual_performance、gameplay、features、camera、action_bar、presentation 全部退出码 0。
- 性能：180 单位真实渲染约 98 FPS、1106 draw calls、0.0254s/process；优化前约 6 FPS、5440 draw calls、0.218s/process。
- 联网：完整 ENet 回归通过协议拒绝、观战权限、红方经济/生产/攻击/胜利、两轮完整快照一致、重开与主机退出。
- 临时 EXE：build/IronFront3D-review.exe，109719480 bytes，SHA256 EC13B695119C7ECD9A251AA63F45C1B96B70FABB93755EDB771A5C36F04BC515；headless 退出码 0，真实渲染 5 秒存活。
- Git 中跟踪的 build/IronFront.exe 未修改；临时 EXE 不提交。


## 2026-09-23：施工动画与单位朝向修正
- 行为：construction 动画 LOOP_NONE，归一化进度与 Simulation.BUILD_TYPES.time / TICK 完全同步；中途加入按当前 remaining seek。
- 朝向：士兵和采集车局部 -Z 为正面，东南西北四个方向测试通过。
- 核心回归：visual_models、visual_performance、gameplay、features、camera、action_bar、presentation 全部退出码 0。
- 多人回归：协议拒绝、观战权限、红方经济/生产/攻击/胜利、两轮完整快照一致、重开与主机退出全部 PASS。
- 临时 EXE：build/IronFront3D-review.exe，109720184 bytes，SHA256 AA0E0C873C84A22FCBC1EB0C29F290D38C46DC89AF9E165C9ADBAF9F43AEE316；headless 180 帧退出码 0，真实渲染 5 秒存活。
- Git 跟踪的 build/IronFront.exe 未修改。

## 2026-09-23：士兵可见攻击朝向修正验证
- 根因验证：Blender 源模型士兵身体正面为 Godot 局部 +Z，采集车为 -Z；修复后士兵身体与 Weapon/Muzzle 同为 +Z。
- `tests/visual_models.gd`：东南西北移动/攻击方向、真实建筑攻击方向、身体正面、Weapon/Muzzle 轨道全部通过，failures=[]。
- MCP 实机：攻击状态 body-forward·target=0.99999994，muzzle·target=0.8137319；截图 `build/verification/soldier_attack_facing_fixed.png`。
- 回归：visual_models、visual_performance、gameplay(57/0)、features、camera、action_bar、presentation 全部 failures=[]；完整 ENet 两轮回归 PASS。
- 导出：`build/IronFront.exe` 109,693,864 bytes，SHA256 `A6C302D03A0BEF09EBB9C54A1208DFEA7F20B0DA595EA9A58B349FCC0A0B369D`；headless 180 帧与真实渲染 300 帧均退出码 0。
