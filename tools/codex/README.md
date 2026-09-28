# 项目工具 wrapper

这些脚本固定项目根目录和允许的参数，避免直接调用机器相关的 Godot、Blender、Python 或 MCP 服务。

## 常用命令

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\project\godot_project\rts_host_p2p_prototype\tools\codex\run-godot.ps1 -Action version
powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\project\godot_project\rts_host_p2p_prototype\tools\codex\run-validation.ps1 -Level Light -Area Simulation
powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\project\godot_project\rts_host_p2p_prototype\tools\codex\run-validation.ps1 -Level Full
powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\project\godot_project\rts_host_p2p_prototype\tools\codex\run-godot.ps1 -Action export -Output build\IronFront.exe
powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\project\godot_project\rts_host_p2p_prototype\tools\codex\run-network.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\project\godot_project\rts_host_p2p_prototype\tools\codex\cleanup-project-processes.ps1 -StopTracked -StopUntracked
powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\project\godot_project\rts_host_p2p_prototype\tools\codex\run-exported.ps1 -DurationSeconds 5
powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\project\godot_project\rts_host_p2p_prototype\tools\codex\verify-permissions.ps1
```

## wrapper 范围

- `run-godot.ps1`：Godot 版本检查、项目脚本执行和 Windows 导出。
- `run-network.ps1`：项目 ENet 回归。
- `run-exported.ps1`：启动项目内 Windows EXE 做受限 smoke run，并登记进程供清理 wrapper 回收。
- `run-blender.ps1`：Blender 版本检查和项目内脚本执行。
- `run-mcp.ps1`：只启动 loopback 绑定的项目 MCP 服务。
- `run-validation.ps1`：运行 `Light` 定向验证或不含导出的 `Full` 完整源码验证，并输出机器可读摘要。
- `cleanup-project-processes.ps1`：停止并报告项目拥有的进程和端口。
- `verify-permissions.ps1`：默认检查 wrapper 语法，并在 Codex CLI 位于 PATH 时检查 execpolicy；显式传入 `-ToolchainSmoke` 时才检查 Godot、Blender 和当前进程状态。

`Light` 支持 `Simulation`、`Presentation`、`Features`、`Camera`、`ActionBar`、`Visual`、`Performance`、`Network` 和 `Tooling`；可同时传入多个 Area。`Network` 固定包含 gameplay 与完整 ENet。`Full` 固定运行全部本地套件、性能与 ENet，但不执行 Godot import 或导出 EXE；源资产变更需在 `Visual` 前单独执行 import。

服务 ledger 写入用户临时目录，验证日志写入被忽略的 `.godot/validation/`。wrapper 只允许本地项目路径；外部网络和未列出的解释器调用仍需单独审批。
