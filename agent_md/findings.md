# 架构发现与决策

## 2026-09-29：两级开发验证

- 模拟由主机单写，客户端显示快照且不计算伤害；价格、伤害、射程、普通速度/冷却等纯数值变更默认只需 gameplay 定向验证。
- `hp`、建造/生产时间、尺寸、半径和部分冷却同时被视觉层用于血条、施工动画、占地或攻击动画，因此这类数值需要 gameplay + visual，而不是 ENet。
- RPC、快照字段/版本/校验、权威归属、命令路由、确定性 tick 和同步频率变化才默认触发完整 ENet。
- 当前网络 runner 会覆盖 Git 跟踪的 `build/verification/*.log`；运行期日志应迁到已忽略的 `.godot/validation/<run-id>/`，历史证据文件保留不动。
- 统一入口采用 `Light` + 明确 Area，以及不含导出的 `Full`；不依据文件名自动猜测，以免同一文件内不同职责触发错误测试集。
- `--editor --quit` 与专用 `--import` 在当前编辑器配置下都能完成文件扫描和布局初始化，但不会自行退出；因此自动 import 不属于 Light/Full，源资产变更单独处理。同步 Godot 阶段保留超时和清理边界。

## 2026-09-29：工作流精简

- 原先 `default.rules` 为 7 个固定 wrapper 各维护 3 种 PowerShell 可执行文件写法，共 21 条规则；第二个规则文件用候选数组重复表达相同入口。
- 项目规定的调用形式包含 `-ExecutionPolicy Bypass`。规则已合并到单一 `default.rules`，每个 wrapper 只维护一条候选数组规则；不带 bypass 的旧形式不再放行。
- `run-mcp.ps1 -Action stop` 只停止 tracked 进程，且与正式清理入口重复；该动作已删除，停止服务统一使用 `cleanup-project-processes.ps1 -StopTracked -StopUntracked`。
- `.codex/runtime/` 已没有生产者；其中只剩旧的空台账。忽略项、空文件和空目录均已删除，当前台账继续位于系统临时目录。
- `verify-permissions.ps1` 默认只执行 wrapper 语法和 execpolicy 静态检查；`-ToolchainSmoke` 才检查 Godot、Blender 和当前进程状态。
- 独立的 Godot、Blender、网络、导出和清理 wrappers 仍是最小权限边界，不为减少文件数而合并。

## 当前有效架构风险

| 优先级 | 发现 | 当前状态 | 下一步 |
| --- | --- | --- | --- |
| P0 | 字典驱动 `Simulation` 与 `scripts/entities/*` 并存，所有权不清 | 未修复 | 完成调用审计，确定唯一权威模型 |
| P0 | 单位分离未覆盖全部相邻空间哈希单元 | 未修复 | 补齐邻居偏移和密集边界回归 |
| P0 | MCP 测试发现没有已注册测试套件 | 未修复 | 建立统一入口、退出码和机器可读结果 |
| P0 | `main.gd` 仍有兼容 wrapper 和 `_create_ui_legacy()` | 已缓解 | 下游测试迁移后删除兼容层 |
| P1 | 路径、可见性、AI、战斗和经济耦合在同一 tick | 未修复 | 按固定顺序拆成确定性系统 |
| P1 | 核心状态大量使用裸 Dictionary/string key | 未修复 | 逐步引入类型化 records/resources |
| P1 | AI 与平衡参数仍硬编码 | 未修复 | 抽出 controller 和经过校验的配置 |
| P2 | 主机按模拟频率发送完整快照 | 未修复 | 按规模需要加入 delta/relevancy/compression |
| P2 | Blender/GLB 合约仍主要依赖隐式节点约定 | 部分缓解 | 增加导出元数据与自动断言 |
| P2 | `godot_ai` 开发态/发布态边界不明确 | 未修复 | 明确 export policy 并验证 release 启动 |
| P2 | Godot/Blender 默认路径依赖当前机器 | 已缓解 | 保留显式覆盖并加入可验证的自动发现 |

## 长期有效决策与限制

- 项目允许依赖 PowerShell；Godot、Blender、ENet、MCP、导出和清理通过 `tools/codex/*.ps1` 固定入口执行，不恢复统一 Python runner。
- Blender 资产生成脚本属于独立业务工具，不受入口语言决策影响。
- 验证以实际影响面为触发条件；失败、共享依赖、跨系统风险、发布节点或用户明确要求时才扩大范围。
- 进程清理必须保持 PID 指纹、端口归属和防误杀检查；归属不明的共享服务只报告，不停止。
- `Simulation.VERSION`、RPC 名称、快照字段形状和确定性 tick 顺序保持兼容。
- MCP 测试套件发现当前为 0；受限环境访问 `.git/lfs/tmp` 可能失败。

历史实现和问题修复见 [dev_log.md](dev_log.md)，验证证据见 [VERIFICATION.md](VERIFICATION.md)。
