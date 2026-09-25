# 项目工具 wrapper

这些脚本固定项目根目录和允许的参数，避免直接调用机器相关的 Godot、Blender、Python 或 MCP 服务。

## 常用命令

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\project\godot_project\rts_host_p2p_prototype\tools\codex\run-godot.ps1 -Action version
powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\project\godot_project\rts_host_p2p_prototype\tools\codex\run-godot.ps1 -Action export -Output build\IronFront.exe
powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\project\godot_project\rts_host_p2p_prototype\tools\codex\run-network.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\project\godot_project\rts_host_p2p_prototype\tools\codex\cleanup-project-processes.ps1 -StopTracked -StopUntracked
```

## wrapper 范围

- `run-godot.ps1`：Godot 版本检查、项目脚本执行和 Windows 导出。
- `run-network.ps1`：项目 ENet 回归。
- `run-blender.ps1`：Blender 版本检查和项目内脚本执行。
- `run-mcp.ps1`：只启动 loopback 绑定的项目 MCP/图库服务。
- `cleanup-project-processes.ps1`：停止并报告项目拥有的进程和端口。

服务 ledger 写入用户临时目录，不写入仓库。wrapper 只允许本地项目路径；外部网络和未列出的解释器调用仍需单独审批。
