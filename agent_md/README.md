# 项目文档目录

本目录保存项目约束、当前计划、架构发现、验证证据和历史记录。文档按职责分工，避免同一状态在多个文件重复维护。

## 推荐阅读顺序

1. [项目规则与代理约束](AGENTS.md)
2. [当前任务计划](task_plan.md)
3. [架构发现与决策](findings.md)
4. [最近进度](progress.md)
5. [验证索引](VERIFICATION.md)
6. [游戏规则](game_rules_zh.md)
7. [开发历史](dev_log.md)

## 文档职责

| 文件 | 用途 | 更新方式 |
| --- | --- | --- |
| `AGENTS.md` | 项目工作、安全、验证和编码约束 | 规则变化时更新 |
| `authorization_log.md` | 用户授权和远程操作记录 | 发生授权操作时追加 |
| `task_plan.md` | 唯一有效的当前路线图和未完成事项 | 阶段开始/完成时更新 |
| `findings.md` | 架构审查、风险、决策和未解决问题 | 发现或解决架构问题时更新 |
| `progress.md` | 最近会话进度、阻塞和下一步 | 每个阶段结束时更新 |
| `VERIFICATION.md` | 测试、导出和运行验证的证据索引 | 验证后更新 |
| `game_rules_zh.md` | 当前可玩规则和数值参考 | 规则变化时更新 |
| `dev_log.md` | 按日期保存的历史实现和 bug 修复 | 只追加或压缩重复历史 |

仓库外部的项目自有说明还包括根目录 `README.md`、`tools/codex/README.md` 和 `tools/effect-gallery/README.md`；第三方插件 `addons/godot_ai/README.md` 不改动。

## 当前状态（2026-09-25）

- 运行时职责拆分、快照边界校验和现有回归已完成。
- 当前未完成重构集中在 `task_plan.md` 的架构后续项；不要从旧历史条目的复选框判断状态。
- 最近验证基线：gameplay 64/0，presentation、visual、features、camera、action-bar 通过，ENet 多进程回归通过，Windows 导出进程检查通过。
- MCP 测试发现当前仍为 0 个已注册 suite；这是已记录的测试基础设施限制。

## 维护规则

- 计划写 `task_plan.md`，不要把新计划塞进历史日志。
- 验证数字写 `VERIFICATION.md`，`progress.md` 只保留摘要。
- 已解决问题必须记录症状、根因、修复和验证；未解决问题必须明确标记 `unfixed`。
- 所有项目自有文档使用 UTF-8；第三方 `addons/godot_ai/README.md` 不在本目录维护范围内。
