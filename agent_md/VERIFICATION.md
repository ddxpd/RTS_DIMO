# 验证索引

更新时间：2026-09-29

本文件只保留可复用的验证入口、最近基线和已知限制。详细实现历史见 [dev_log.md](dev_log.md)。

## 2026-09-29 效果图库移除

- 删除本地效果图库页面、服务、启动器、概念图、导入数据、垃圾桶数据和专用生成脚本。
- `run-mcp.ps1` 不再提供 `gallery` 动作；项目清理端口集合不再包含 8765。
- 本次不修改游戏运行时、网络协议、导出配置或 Blender MCP 行为。
- PowerShell Parser 通过，旧 `gallery` 参数按预期被 ValidateSet 拒绝；活动代码、工具入口和忽略规则没有图库或 8765 残留引用。
- 13 份剩余 Markdown 的 UTF-8、NUL 和链接检查、scoped `git diff --check` 均通过。
- 最终没有项目进程、24560/8766 项目端口或遗留的 8765 监听；共享 Blender MCP 进程只报告、未停止。
- 未运行 gameplay、ENet、Windows 导出或 EXE 冒烟测试，因为游戏运行时、网络协议和打包路径未改变。

## 2026-09-29 工具入口回退

- 删除统一 Python runner、共享运行时和专用依赖声明；恢复固定 PowerShell wrappers 与窄权限执行规则。
- 项目规则、README、验证命令和清理命令已切回 PowerShell；Blender 资产生成器等独立 Python 工具保留。
- 风险分级验证政策保持不变；本次不涉及游戏逻辑、网络协议或打包配置。
- PowerShell Parser 覆盖 `tools/codex/`、效果图库和测试 runner，全部通过；`verify-permissions.ps1` 的 Godot/Blender 版本入口、wrapper 自检以及最终完整清理退出码为 0。
- execpolicy 允许固定 `run-exported.ps1`，旧 Python 入口无匹配规则；最终没有项目进程或 24560/8765/8766 端口残留，共享 Blender MCP 进程只报告、未停止。
- 未运行 gameplay、ENet、Windows 导出或 EXE 冒烟测试，因为本次未修改游戏、网络协议、打包配置或可执行文件启动逻辑。

## 最近基线

| 类别 | 入口/范围 | 结果 | 日期 |
| --- | --- | --- | --- |
| 玩法 | `tests/gameplay.gd` | 64 项检查 / 0 项失败 | 2026-09-26 |
| 表现 | `tests/presentation.gd` | 通过 | 2026-09-26 |
| 视觉 | `tests/visual_models.gd`、features、camera、action_bar | 通过，包含新士兵层级/护肩阵营材质、2D 格子血条、绿色 3D 选中圈、3D 能量弹方向/生命周期和地堡灯光施工跟随/复位断言 | 2026-09-26 |
| 性能 | `tests/visual_performance.gd`，180 个单位 | `sync_visuals_ms=6.9522`，低于 8ms 阈值 | 2026-09-26 |
| 多人联机 | `tools/codex/run-network.ps1` | 协议、权限、双 guest、快照、重连、主机退出全部通过 | 2026-09-28 |
| 导出 | Windows 嵌入资源 EXE | 无界面运行退出 0；EXE 冒烟运行存活 5 秒通过 | 2026-09-26 |
| 文档 | Markdown 链接、`git diff --check`、项目自有文档 UTF-8/NUL 基础扫描 | 通过 | 2026-09-25 |
| 工具工作流 | 固定 PowerShell wrappers、ENet、Blender MCP、Windows EXE | 通过；路径、参数、进程和 loopback 安全边界保持 | 2026-09-29 |

## 2026-09-26 绿色 3D 选中圈

- 需求：选中单位或建筑后，在对象底部显示简单醒目的圆环效果；不使用阵营颜色，并先生成预览图。
- 实现：`EntityVisual` 延迟创建低面数 `TorusMesh`，使用固定绿色发光材质、关闭阴影并保持静态大小/亮度；`WorldVisualSync` 根据单位/建筑选择数组同步，并通过 `SELECTION_RING_PROFILES` 提供按类型覆盖。建筑半径按底座矩形半对角线加边距计算，完整包围底座。
- 回归：补充静态缩放/亮度、底座外接圆覆盖以及 `_ready()` 前选中状态的初始化断言。
- 预览：生成 `build/verification/selection_ring_preview.png`，包含士兵与建筑的绿色地面圆环。
- 验证：单选、多选、建筑选择、清空选择、核心回归、性能回归、完整 ENet 回归、Windows 导出和 5 秒 EXE 冒烟运行全部通过。

## 2026-09-26 2D 格子血条

- 需求：血条不再制作成模型，以屏幕空间 2D 方式显示；每 10 点生命值为一格，最后不足 10 点按比例填充。
- 实现：新增 `HealthGridOverlay` 自绘 HUD 控件，单位和建筑仅提交世界坐标、HP、最大 HP、阵营和可见性；移除实体节点上的 3D HP bar。单位目标宽 72px、建筑目标宽 120px，并按格子数量缩放格宽。
- 保持：建造进度和采集量继续使用现有辅助状态条；Simulation、伤害判定、快照字段和 ENet 协议未改变。
- 验证：视觉格子断言、核心回归、性能回归、完整 ENet 回归、Windows 导出和 5 秒 EXE 冒烟运行全部通过。

## 2026-09-26 士兵与能量弹模型重做

- 症状：士兵模型需要按参考图重做并简化线条；旧 `shot` 仍是方格白色 `Sprite3D`，且队伍标识分散在枪械、手臂或头盔侧面。
- 根因：旧 GLB 层级与运行时动画路径绑定旧节点，射击效果没有独立 3D 弹体资源。
- 修复：完全重建 `soldier` 层级和 `bullet.glb`；士兵仅在左右护肩使用阵营材质，枪械/前臂/头盔侧面保持中性材质；`WorldVisualSync` 让 `shot` 实例化蓝白能量弹并沿飞行方向旋转。效果键类型复用时会检测 Node3D/Sprite3D 不匹配并重建，避免将 `modulate` 写入错误类型。
- 验证：Blender GLB 导出和预览完成；Godot 导入后 `tests/visual_models.gd`、核心回归、`tests/visual_performance.gd`、完整 ENet 回归均通过；重新导出的 `build/IronFront.exe` 冒烟运行存活 5 秒通过。

## Esc 菜单回归

- `tests/presentation.gd` 验证 Escape 可以打开和关闭菜单。
- 同一测试验证 Escape 可以取消攻击键重绑，且不会错误打开菜单。
- 修复后的脚本退出码为 0；随后 gameplay、features、camera、action_bar 和 ENet 回归也通过。

## 常用验证命令

项目工具通过固定 PowerShell wrappers 调用：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/codex/run-godot.ps1 -Action version
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/codex/run-network.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/codex/run-godot.ps1 -Action export -Output build/IronFront.exe
```

具体 Godot 测试脚本位于 `tests/`；网络测试在默认路径不可用时传入 `-GodotPath`。

## 解释规则

- “通过”表示脚本退出码为 0 且没有失败项，不等同于 MCP 测试套件已注册。
- 性能测试接近阈值时必须独立重跑，并记录波动，不以单次超阈值直接修改逻辑。
- 导出的 EXE/PCK 必须按项目发布规则成对处理；当前配置使用嵌入资源。
- 任何确认 bug 的记录必须同时包含症状、根因、修复和验证。

## 2026-09-26 地堡续作验证

- `tests/visual_models.gd`：通过，包含单炮、灯带、地下升起和建造完成复位断言。
- `tests/gameplay.gd`：64 项检查 / 0 项失败。
- `tests/features.gd`、`presentation.gd`、`camera.gd`、`action_bar.gd`：全部通过。
- `tests/visual_performance.gd`：最终独立重跑 `sync_visuals_ms=6.53065`，低于 8 ms 阈值。
- ENet：协议不匹配、观战权限、双 guest、快照一致性、重连和主机退出全部通过。
- Windows 导出：无界面运行退出码 0；`tools/codex/run-exported.ps1 -DurationSeconds 5` 报告 `EXPORTED_GAME_SMOKE_PASS`。
- Blender：GLB 导出和预览渲染完成；共享源文件中的其他模型未被清空。

## 当前限制

- MCP 测试套件发现当前返回 0 个套件，测试依赖直接脚本入口。
- Git LFS 临时目录可能在受限环境报 `Access is denied`，会影响二进制 diff 读取。
- 默认 Godot 路径仍可能因机器不同而不可用，应通过 wrapper 的 `-GodotPath` 显式指定受信安装路径。
