# 验证索引

## 2026-09-29：Windows 沙箱文件编辑权限修复

- 仅修复项目 .git 顶层所有者，CodexSandboxOffline → happydog。管理员脚本返回 PASS、DaclUnchanged=true、Recursive=false，原 ACL/所有者备份与结果 JSON 均在 agent_md/。
- task_plan.md 的 HTML 注释通过 apply_patch 修改后读回，再通过 apply_patch 还原；原计划文本不变。两次操作直接完成，未申请沙箱外执行。
- 沙箱日志 C:/Users/happydog/.codex/.sandbox/sandbox.2026-09-29.log：修复前 21:36:43 为 open deny ACL target for update / setup error；修复后 21:49:50 为 applied deny ACE to protect ...\.git / errors=[]。
- 初始化后再次逐条比较 ACL：原条目全部保留，Codex 自动新增当前沙箱 SID 的两个 Deny 条目及继承 Allow 条目。原始备份与最终 DACL 不再逐字相等，所有者修复步骤本身未改 DACL。
- 本轮只修复文件系统权限和记录诊断，无游戏源码/工具链改动，不运行 Light/Full、ENet 或导出；未启动游戏、Godot、Blender 或服务。

## 2026-09-29：荒漠地图 Windows 导出

- build/IronFront.exe：2026-09-29 21:02:45，110,159,312 字节（约 105 MiB）。binary_format/embed_pck=true，可单独分发 EXE。
- 固定入口 run-godot.ps1 导出退出 0；.godot/desert-export.log 无 SCRIPT ERROR/ERROR，stderr 为空。包含 desert_quarry 配置、地图脚本和 desert_surface 着色器。
- SHA256：9F1C6EC39BA580306BF4817083E5F014CBCB4C511C8FBBDC2F1BEE6B37782BE3。
- run-exported.ps1 -DurationSeconds 5 返回 EXPORTED_GAME_SMOKE_PASS；只证明启动及五秒存活。用户目录运行日志因沙箱拒绝读取，未据此声称运行日志无错误。
- cleanup -StopTracked -StopUntracked 和单独 ReportOnly 均确认项目进程/24560、8766 端口无残留；共享 Blender MCP 保留。
- 本轮没有源代码改动，不重复 Light/Full/ENet，沿用下方已有验证；未提交或推送。
- 已知预览限制：assets/concept_art/.gdignore 阻止菜单引用的概念图导入，导出中无预览图；地图本体正常打包。此限制未修复。

## 2026-09-29：荒漠矿区与模块地图

- Full：`.godot/validation/20260929-204213-5764/`，总计约 224 秒，全部阶段通过。包括 71 条 gameplay 检查、presentation/features/camera/action_bar/visual_models、双地图 180 单位性能、terrain_maps、terrain_presentation、两张地图完整 ENet 及清理。
- 双地图 ENet：`network/prototype/` 与 `network/desert_quarry/` 均通过协议不匹配拒绝、观战权限、经济、生产、战斗、胜负、断线重连、重开、主机退出与完整快照相等检查。
- 最终补验：`.godot/validation/20260929-205535-12824/`，Light Simulation/Presentation/Visual/Camera/Performance/Tooling 全部通过。荒漠 180 单位平均逻辑帧 19.91 ms，视觉同步 1.89 ms；原型平均逻辑帧 16.29 ms。记录为本机测量，不等同于所有硬件 FPS 保证。
- 地图专项覆盖高度/旋转对称、上坡和下矿坑、崖壁拒绝穿越、道路中心线可通行、坡道拒建/高台建造、矿区连通、配置重叠/坡道接缝拒绝、遮挡射击及碉堡、攻击移动释放遮挡目标、上下高地视野、地图身份及内容不匹配拒绝。
- OpenGL 实机专项：`.godot/terrain-render.log`，TERRAIN_PRESENTATION PASS，无脚本错误。验证高台/坡道/坑底点选、贴地表现、标记法线、地图切换与重开。截图：[总览](../assets/concept_art/desert-quarry-overview.png)、[高台](../assets/concept_art/desert-quarry-highland.png)、[矿坑](../assets/concept_art/desert-quarry-pit.png)、[开局实机](../assets/concept_art/desert-quarry-gameplay.png)。
- 导入：`.godot/terrain-final-import.log` 扫描及导入完成，错误日志为空；编辑器退出超过 60 秒后被入口终止。后续导入资源加载及渲染通过。部分 headless 测试有单个 ObjectDB 退出泄漏警告，保留说明。
- Tooling：PS1 语法及 27 个 allow 正例、5 个 deny 反例通过；ToolchainSmoke 未重复执行，Godot 已由游戏验证覆盖。最终 Light 不重复 ENet，因为最后改动仅为外观、道路绘制、点选和配置验证；协议边界已由 Full 覆盖。
- 未导出 EXE、未推送；本任务无发布交付要求。项目进程/24560、8766 端口清理通过，共享 Blender MCP 进程按规则保留。

## 2026-09-29：工具执行授权定向验证

- `run-validation.ps1 -Level Light -Area Tooling`：退出 0，793ms；所有工具 PS1 语法通过，实际桌面版 Codex CLI 完成规则检查。
- 九个固定入口 × 三种 PowerShell 名称：27 个 allow 正例；原始 PowerShell、原始 cmd、未列入白名单的脚本、外部同名脚本、近似路径：5 个反例均未匹配 allow。只做规则求值，不执行反例命令。
- 参数边界：Light 不传 Area、Light 传 Unknown、Full 传 Tooling，均退出 1 且返回预期参数错误；单 Area 的 Light Tooling 正常运行。
- 范围差异检查通过；普通 MD/PS1 使用 apply_patch 编辑成功，没有为这些编辑请求沙箱升级。仅受保护的 `.codex/rules/default.rules` 更新走了平台授权。
- 不运行 Simulation、Visual、ENet、导出或 ToolchainSmoke：仅权限规则/工具验证改变，无游戏行为或服务启动，不需项目进程清理。
- 限制：仅验证项目规则文件，不声称覆盖全局/管理规则或证明当前会话已加载；重启 Codex 后采用新规则。未更改 `.codex/config.toml` 或任何 AGENTS.md，未开启全盘访问。

## 2026-09-29：工业装甲鼠标版本 Windows 导出

- 已重新导出 `build/IronFront.exe`，2026-09-29 19:01:33，110,131,480 字节（约 105 MiB）。PCK 内嵌，只需分发 EXE。
- 导出退出 0，stderr 为空；打包日志包含五种 cursor PNG 导入资源、cursor_controller 与 destination_marker，包含本轮鼠标及目的地效果。
- SHA256：`28870F67984FD427680A938F2DAD54326F26194CF18C23F7CDD9D6BC50870D0A`。
- `run-exported.ps1 -DurationSeconds 5` 返回 `EXPORTED_GAME_SMOKE_PASS`，仅证明 EXE 启动并存活五秒，不代替完整玩法验证。随后停止冒烟进程，cleanup 与 ReportOnly 确认项目进程/端口均无残留，共享 MCP 未停止。
- 本轮只导出交付，不改源码；沿用前一轮通过的 Light Simulation/Presentation/Visual/Camera/ActionBar/Tooling 和真实硬件光标验证，不重复 Full/ENet。未提交或推送。

## 2026-09-29：工业装甲鼠标与目的地反馈

- `Light -Area Simulation,Presentation,Visual,Camera,ActionBar,Tooling` 全部通过：gameplay、presentation、camera、action_bar、visual_models、wrapper syntax/execpolicy 与 cleanup；首次汇总约 7.1 秒。
- `tests/cursor_checks.gd` 接入现有 presentation/visual_models 套件：覆盖五状态、模式优先级、UI/菜单/旁观者/胜负、迷雾不可泄露、兼容单位、有效/无效建造和采集、无选择不产生标记、16 个上限、稳定 ID、两种几何/配色、0.18/0.35/0.52/0.70 秒阶段和独立透明度、销毁。
- 单独 import 日志确认五张 PNG 导入完成；编辑器仍有既有的退出超时，30 秒后由 wrapper 终止。后续资源加载与实际渲染均成功，未将超时宣称为正常退出。
- 实际 OpenGL 窗口通过 `tests/cursor_preview.gd` 检查真实悬停、A 键进入攻击模式、无效采集切换；`CURSOR_RENDER_PREVIEW_PASS`，stderr 为空。输出 [光标原尺寸与放大对照](../assets/concept_art/cursor_runtime/cursor-assets.png)、[初始落点](../assets/concept_art/cursor_runtime/destination-000.png)、[确认落点](../assets/concept_art/cursor_runtime/destination-035.png) 及淡出/相机变化帧。
- `inspect-cursor.ps1` 使用 Win32 读取前台 Godot 的真实硬件光标，不以场景截图代替：default/select/move/attack/blocked 全部 40×40，热点分别为 (9,6)/(9,8)/(11,10)/(20,20)/(13,9)。原生图保存在 `.godot/cursor-native/`。
- 实机探针初次选择单位 3 的地面投影落入底部 HUD，正确返回 default；改选地图内的单位 6 后整条原生状态链通过，未改变游戏的 HUD 优先级。
- 定向 headless 日志有一个 AudioStreamGeneratorPlayback 退出泄漏警告，之前的 `.godot/base-visual-tests.log.err` 也有同类 ObjectDB 警告；本任务未修复音频生命周期问题。新实际窗口预览在退出前释放场景，未出现该警告。
- 未运行 Full/ENet，因为未改命令路由、模拟、RPC 或快照；未导出 EXE/运行导出冒烟，因为本次没有请求交付二进制。
- 资源由内置 imagegen 生成，源图与 [完整提示词](../assets/concept_art/cursor-production-prompts.txt) 保存在概念图目录；正式 PNG 位于 `assets/ui/cursors/`，仅通过 Godot 工具脚本做机械裁边和缩小。

## 2026-09-29：新基地版本 Windows 导出

- 已按用户请求导出 `build/IronFront.exe`，含指挥中心 v2 模型与动画；文件大小 110106648 字节，2026-09-29 14:15:30 生成。
- 使用 Windows Desktop release preset，`embed_pck=true`，可单独分发 EXE。
- 导出日志无 stderr；`run-exported.ps1 -DurationSeconds 5` 返回 EXPORTED_GAME_SMOKE_PASS。
- 冒烟仅确认程序存活；AppData 运行日志读取被沙箱拒绝，未据此宣称运行日志无错误。测试后清理及 ReportOnly 均确认无项目进程或端口残留。
- 本轮只执行导出与启动冒烟；源码的 Light Simulation/Visual/Tooling 已在模型实现阶段通过，无新增源码变更，未重复运行 Full/ENet。

## 2026-09-29：指挥中心 v2 基地

- 最终命令：`run-validation.ps1 -Level Light -Area Simulation,Visual,Tooling`。
- 最终摘要：passed；gameplay passed（2821ms）、visual_models passed（539ms）、tooling passed（538ms）、cleanup passed（463ms）。Tooling 语法通过；本机 PATH 没有 codex，execpolicy 检查跳过；独立 toolchain smoke 未请求。
- 覆盖：160×160 占地、相邻放置、阻挡、模型范围与高度、预览和选择环、七段施工边界/反向进度跳转/完工复位、六灯向下扫描/间歇、蓝红窗口与塔灯、实例间材质和动画相位隔离。
- 实际 GPU 验证：`run-godot.ps1 -Action script -Script res://tests/base_preview.gd -Rendered`，OpenGL Compatibility / RTX 5070 Ti，输出 36 帧施工、24 帧扫描和红方静帧；stderr 为空。预览位于 `assets/concept_art/base_animation/index.html`。
- Blender 预览：`assets/concept_art/基地-模型预览.png`；模型约 6136 三角面、31 mesh，本地边界 4.9×4.9×3.37。原 blend1 的大小与修改时间保持不变。
- 导入限制：编辑器日志确认 base.glb 重导入结束且无脚本错误，但编辑器没有自行退出，wrapper 超时终止。新 GLB 已通过后续节点契约、实际渲染及运行时测试确认载入。
- 未运行 Full/ENet/导出：本次未改网络快照、命令边界及打包路径，未要求 EXE；只选择受影响区域。进程清理确认项目进程和端口均无残留。

更新时间：2026-09-29

本文件只保留当前验证证据、最近基线和可复用入口。实现历史见 [dev_log.md](dev_log.md)。

## 2026-09-29 A 键攻击移动修复

- `Light -Area Simulation,Presentation,Visual` 通过：gameplay、presentation、visual_models 和最终 cleanup 均为 passed，总耗时约 5.4 秒。
- gameplay 当前为 66 项检查 / 0 项失败；新增覆盖连续沿途交战、目标死亡后恢复以及抵达原始目的地。
- presentation 通过真实根视口输入覆盖一次 `A` 只开启一次攻击模式、地面点击生成攻击移动、命令后选中保持和一次性模式关闭。
- visual_models 覆盖攻击移动交战时的追击/攻击动画、临时目标朝向，以及释放目标后恢复原目的地方向。
- 12 个本次修改文件的限定 `git diff --check` 通过；5 份 Markdown 的 UTF-8、NUL 和本地链接检查通过。
- RPC、命令格式、快照字段和 `Simulation.VERSION` 未改变，因此未运行 ENet；打包路径未改变，因此未导出或执行 EXE 冒烟。

## 2026-09-29 两级开发验证

- `Light` 参数拒绝通过：缺少 Area、Full 携带 Area、未知 Area 均返回非零；逗号分隔 Area 会去重。
- `Light -Area Simulation,Tooling,Simulation` 通过，只运行一次 tooling 和 gameplay，随后执行一次完整清理；摘要状态为 passed，总耗时约 4.8 秒。
- `Full` 通过：gameplay、presentation、features、camera、action_bar、visual_models、visual_performance、完整 ENet 和最终清理均为 passed；总耗时约 110 秒。
- ENet 覆盖协议不匹配、观战权限、双 guest、经济、生产、战斗、胜负、快照一致性、重连和主机退出。
- 网络日志写入 `.godot/validation/<run-id>/network/`；Git 跟踪的 `build/verification` 网络日志未被修改。
- 固定 PowerShell wrapper 增至 8 个，Parser 与 execpolicy 自检通过；裸 PowerShell 仍不获授权。
- `--editor --quit` 与专用 `--import` 均完成扫描后停留在编辑器生命周期，无法自动退出；两级验证不再自动 import，并为同步 Godot 阶段保留超时保护。该导入限制尚未修复。
- 按两级规则未执行 Windows 导出或 EXE 冒烟，因为本次没有修改打包、启动或交付路径。

## 2026-09-29 工作流精简

- `verify-permissions.ps1` 默认静态检查通过：全部 PowerShell wrapper 语法有效，8 个固定入口均命中 allow 规则，裸 `Get-Process` 不命中。
- `powershell.exe`、`powershell` 和系统绝对路径三种执行名称均命中同一个候选数组规则；不带 `-ExecutionPolicy Bypass` 的旧调用不再命中。
- `.codex/rules/` 只保留一个规则文件；重复的 Windows execution-policy 文件已删除。
- `run-mcp.ps1 -Action stop` 按预期被 ValidateSet 拒绝；服务停止统一使用完整清理 wrapper。
- 遗留的空 `.codex/runtime/processes.json` 和目录已删除；当前进程台账继续使用系统临时目录。
- 12 份项目 Markdown 的 UTF-8、NUL 和本地链接检查通过；活动工作流无已知失效引用；限定 `git diff --check` 通过，仅有既有 LF/CRLF 提示。
- 本次未启动 Godot、Blender 或游戏，未运行玩法、ENet、导出或 EXE 冒烟测试，因为游戏运行时、网络协议、资产和打包路径未改变。

## 最近基线

| 类别 | 入口/范围 | 结果 | 日期 |
| --- | --- | --- | --- |
| 玩法 | `tests/gameplay.gd` | 66 项检查 / 0 项失败 | 2026-09-29 |
| 表现与视觉 | presentation、visual_models、features、camera、action_bar | 通过 | 2026-09-29 |
| 性能 | `tests/visual_performance.gd`，180 个单位 | 阈值检查通过 | 2026-09-29 |
| 多人联机 | `tools/codex/run-network.ps1` | 协议、权限、双 guest、快照、重连和主机退出通过 | 2026-09-29 |
| Windows 导出 | 嵌入资源 EXE | 无界面导出退出 0，EXE 存活检查通过 | 2026-09-26 |
| 工具工作流 | 8 个固定 PowerShell wrappers、两级验证和单一 execpolicy | 静态及 Light/Full 检查通过 | 2026-09-29 |

## 常用验证命令

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/codex/verify-permissions.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/codex/verify-permissions.ps1 -ToolchainSmoke
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/codex/run-validation.ps1 -Level Light -Area Simulation
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/codex/run-validation.ps1 -Level Full
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/codex/run-godot.ps1 -Action version
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/codex/run-network.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/codex/run-godot.ps1 -Action export -Output build/IronFront.exe
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/codex/cleanup-project-processes.ps1 -StopTracked -StopUntracked
```

具体 Godot 测试脚本位于 `tests/`；网络测试在默认路径不可用时传入 `-GodotPath`。验证按 [AGENTS.md](AGENTS.md) 的风险分级规则选择。

## 解释规则与限制

- “通过”表示对应脚本退出码为 0 且没有失败项，不等同于 MCP 测试套件已经注册。
- 性能测试接近阈值时必须独立重跑并记录波动。
- 导出的 EXE/PCK 必须按项目发布规则成对处理；当前配置使用嵌入资源。
- MCP 测试套件发现当前返回 0 个套件，测试仍依赖直接脚本入口。
- 默认 Godot/Blender 路径仍依赖当前机器；Godot 可通过 wrapper 的 `-GodotPath` 显式指定受信安装路径。
- 当前无界面 Godot import 完成扫描后不会自行退出；源资产变更需单独处理导入并检查结果，不能用现有 Light/Full 代替。
- Git LFS 临时目录可能在受限环境报 `Access is denied`，会影响二进制 diff 读取。
