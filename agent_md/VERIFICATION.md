# 验证索引

更新时间：2026-09-29

本文件只保留当前验证证据、最近基线和可复用入口。实现历史见 [dev_log.md](dev_log.md)。

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
| 玩法 | `tests/gameplay.gd` | 64 项检查 / 0 项失败 | 2026-09-29 |
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
