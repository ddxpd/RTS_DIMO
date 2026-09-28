# 最近进度

## 2026-09-29：建立两级开发验证（已完成）

- [x] 已确认现有七个本地 Godot 套件、完整 ENet、权限静态检查和独立导出/冒烟入口。
- [x] 已确定轻量验证按 Simulation、Presentation、Features、Camera、ActionBar、Visual、Performance、Network、Tooling 影响面选择。
- [x] 已确认纯游戏数值通常不需要 ENet；网络边界变化仍必须运行完整 ENet。
- [x] 已实现统一 wrapper、ENet 日志隔离和第八个窄权限入口；PowerShell Parser 与 execpolicy 自检通过。
- [x] 已同步授权后的项目规则、根 README、工具说明和验证命令；导出/冒烟保持独立条件触发。
- [x] Full 导入探针连续三种方式均停在编辑器生命周期；已完整清理并将自动 import 从两级验证剥离，保留 Godot 阶段超时保护。
- [x] 参数拒绝、Area 解析/去重、Light Simulation+Tooling、8-wrapper 静态自检全部通过。
- [x] Full 的七个本地套件、性能、完整 ENet 和最终清理全部通过，总耗时约 110 秒。
- [x] ENet 日志只写入 `.godot/validation/`；Git 跟踪的历史网络日志没有变化。

状态：完成；本次 Full 明确不包含 Windows 导出或 EXE 冒烟。无界面 import 不自动退出，已从两级验证中剥离并记录为未修复限制。

## 2026-09-29：精简项目工作流（已完成）

- [x] 将两份 PowerShell execpolicy 规则合并到 `.codex/rules/default.rules`，21 条重复规则缩减为 7 条候选数组规则。
- [x] 删除 `run-mcp.ps1` 的重复 `stop` 动作；服务停止统一使用完整清理 wrapper。
- [x] 删除失效的 `.codex/runtime/` 忽略项。
- [x] 删除工作区内遗留的空 `.codex/runtime/processes.json` 和空目录；当前台账继续使用系统临时目录。
- [x] 将权限自检拆为默认静态检查和可选 `-ToolchainSmoke`；静态检查逐个断言七个固定 wrapper，并确认裸 PowerShell 不获授权。
- [x] PowerShell Parser、execpolicy 静态自检和旧 MCP `stop` 参数拒绝检查通过。
- [x] 收口活动计划、发现和进度文档，移除已完成历史与失效状态。
- [x] 12 份项目 Markdown 的 UTF-8、NUL 和链接检查通过；活动残留引用检查和限定 `git diff --check` 通过。

状态：完成。按风险分级规则，本次未启动 Godot、Blender 或游戏，也未运行玩法、ENet、导出或 EXE 冒烟测试。

## 当前验证基线

| 类别 | 最近结果 | 日期 |
| --- | --- | --- |
| 玩法 | 64 项检查 / 0 项失败 | 2026-09-29 |
| 表现与视觉 | presentation、visual_models、features、camera、action_bar 通过 | 2026-09-29 |
| 性能 | 180 单位阈值检查通过 | 2026-09-29 |
| 多人联机 | 协议、权限、双 guest、快照、重连、主机退出通过 | 2026-09-29 |
| Windows 导出 | 无界面导出退出码 0，导出程序存活检查通过 | 2026-09-26 |

以上是既有基线，不代表本次工作重新运行了对应验证。

## 当前未完成

- 统一 Simulation 与旧实体模型所有权。
- 补齐空间分离邻居检查和密集边界回归。
- 注册 MCP/CI 可发现测试入口。
- 删除不再需要的 `main.gd` 兼容 wrapper。
- 后续 typed state、tick 子系统、AI controller、配置外置、增量快照和 GLB 契约重构。

完整历史见 [dev_log.md](dev_log.md)，当前路线见 [task_plan.md](task_plan.md)。
