# 项目工具 wrapper

这些脚本固定项目根目录和允许的参数，避免直接调用机器相关的 Godot、Blender、Python 或 MCP 服务。

## 文件编辑与执行授权

- 项目内普通 `.ps1` 和已有非 `AGENTS.md` 的 `.md` 文件，可按任务需要直接使用 `apply_patch` 修改，不重复询问；不要仅为这类编辑改用 `cmd`/PowerShell 写文件或申请 `retry without sandbox`。
- `AGENTS.md` 仍须事先明确同意；新增其他 Markdown 仍须先询问后续编辑权限。遵循 [项目规则](../../agent_md/AGENTS.md)，本说明不改变这些例外。
- 保留 `workspace-write` + `on-request`，不启用 Full access，不给任意 `cmd`、PowerShell 或所有 PS1 添加宽泛执行授权。修改脚本与执行脚本是不同的权限。
- 固定入口按下方完整命令形式调用：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File <绝对脚本路径>`。不要再包一层 `cmd /c`、改成 `-Command` 或拼接临时脚本来期望匹配同一规则。
- `.codex/rules/default.rules` 仅对白名单内九个固定入口放行；新增入口须审查用途、参数与副作用后显式添加精确规则，并同步权限自检，不按扩展名自动授予执行权限。
- `.codex` 是平台保护目录，规则文件更新可能仍需一次平台审批。受信项目的规则在 Codex 启动时加载，更新后重启客户端；已有会话和更高优先级的管理策略不保证立即采用新规则。
- 自检只验证项目规则，不代表全局/管理规则或当前会话一定无弹窗。若还有弹窗，应检查完整被拦截命令及具体越界原因，不能因为目标文件是 MD/PS1 就扩大整条命令权限。普通编辑失败时报告限制，不绕过平台保护。

规则语义与加载方式见 [OpenAI 官方规则文档](https://learn.chatgpt.com/docs/agent-configuration/rules)。

## 常用命令

运行需要真实渲染的项目预览脚本时，给 `run-godot.ps1 -Action script` 添加 `-Rendered`。例如 `-Script res://tests/base_preview.gd -Rendered` 会把基地施工与塔灯的实机帧写入 `assets/concept_art/base_animation/`，可打开其中的 `index.html` 查看。默认脚本与回归测试仍以 headless 运行。

光标预览使用 `-Script res://tests/cursor_preview.gd -Rendered`，实际素材对照和落点动画帧保存到 `assets/concept_art/cursor_runtime/`。预览运行时可在另一终端调用 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\project\godot_project\rts_host_p2p_prototype\tools\codex\inspect-cursor.ps1`，检查前台 Godot 的五种原生硬件光标尺寸及热点；诊断只截取光标本身，不截取桌面、不发送输入，输出到 `.godot/cursor-native/`。需要让预览窗口保持前台。

透明源图通过 imagegen 生成并保存在概念图目录；用 `run-godot.ps1 -Action script -Script res://tools/art/prepare_cursors.gd` 做保留 alpha 的机械裁边、缩小和居中，更新正式 PNG 后单独运行 import。正式光标位于 `assets/ui/cursors/`，热点见 `scripts/ui/cursor_controller.gd`，箭头热点不能误用装饰框左上角。

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
- `inspect-cursor.ps1`：只读检查项目预览的原生光标，诊断结果写入项目 `.godot/`，不发送输入。
- `verify-permissions.ps1`：检查所有 wrapper 语法、九个固定入口的三种解释器名称，以及原始 shell、未授权/外部/近似路径的反例。优先使用 PATH 中的 Codex CLI，再查桌面版标准安装位置；找不到 CLI 时明确失败，不将跳过规则检查当作通过。显式传入 `-ToolchainSmoke` 时才检查 Godot、Blender 和当前进程状态。

`Light` 支持 `Simulation`、`Presentation`、`Features`、`Camera`、`ActionBar`、`Visual`、`Performance`、`Network` 和 `Tooling`；可同时传入多个 Area。`Network` 固定包含 gameplay 与完整 ENet。`Full` 固定运行全部本地套件、性能与 ENet，但不执行 Godot import 或导出 EXE；源资产变更需在 `Visual` 前单独执行 import。

服务 ledger 写入用户临时目录，验证日志写入被忽略的 `.godot/validation/`。wrapper 只允许本地项目路径；外部网络和未列出的解释器调用仍需单独审批。
