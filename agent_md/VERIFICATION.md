# 验证索引

更新时间：2026-09-25

本文件只保留可复用的验证入口、最近基线和已知限制。详细实现历史见 [dev_log.md](dev_log.md)。

## 最近基线

| 类别 | 入口/范围 | 结果 | 日期 |
| --- | --- | --- | --- |
| Gameplay | `tests/gameplay.gd` | 64 checks / 0 failures | 2026-09-25 |
| Presentation | `tests/presentation.gd` | 通过 | 2026-09-25 |
| Visual | `tests/visual_models.gd`、features、camera、action_bar | 通过 | 2026-09-25 |
| Performance | `tests/visual_performance.gd`，180 units | 重跑低于 8ms 阈值 | 2026-09-25 |
| Multiplayer | `tests/run_network_guest.ps1` | 协议、权限、双 guest、快照、重连、主机退出全部通过 | 2026-09-25 |
| Export | Windows embedded-resource EXE | headless 退出 0；渲染进程存活检查通过 | 2026-09-25 |
| Gallery | HTML/Node/PowerShell/Python/API 静态检查 | 通过；浏览器控制不可用 | 2026-09-24 |
| Documentation | Markdown links、`git diff --check`、项目自有文档 UTF-8/NUL 基础扫描 | 通过 | 2026-09-25 |

## Esc 菜单回归

- `tests/presentation.gd` 验证 Escape 可以打开和关闭菜单。
- 同一测试验证 Escape 可以取消攻击键重绑，且不会错误打开菜单。
- 修复后的脚本退出码为 0；随后 gameplay、features、camera、action_bar 和 ENet 回归也通过。

## 常用验证命令

项目工具必须通过 `tools/codex/` wrapper 调用：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/codex/run-godot.ps1 -Action version
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/codex/run-network.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/codex/run-godot.ps1 -Action export -Output build/IronFront.exe
```

具体 Godot 测试脚本位于 `tests/`；网络测试在默认路径不可用时传入 `-GodotPath`。

## 解释规则

- “通过”表示脚本退出码为 0 且没有失败项，不等同于 MCP suite 已注册。
- 性能测试接近阈值时必须独立重跑，并记录波动，不以单次超阈值直接修改逻辑。
- 导出的 EXE/PCK 必须按项目发布规则成对处理；当前配置使用嵌入资源。
- 任何确认 bug 的记录必须同时包含症状、根因、修复和验证。

## 当前限制

- MCP suite discovery 当前返回 0 个 suite，测试依赖直接脚本入口。
- Git LFS 临时目录可能在受限环境报 `Access is denied`，会影响二进制 diff 读取。
- 浏览器 runtime 没有可用控制通道，图库无法做真实浏览器 UI 自动化。
- 默认 Godot 路径仍可能因机器不同而不可用，应优先使用 wrapper 或显式 `-GodotPath`。
