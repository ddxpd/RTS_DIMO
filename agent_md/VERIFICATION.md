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
