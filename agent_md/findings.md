# 架构发现与决策

更新时间：2026-09-25

本文件只记录当前仍有价值的架构风险、决策和限制。历史实现细节见 [dev_log.md](dev_log.md)，测试证据见 [VERIFICATION.md](VERIFICATION.md)。

## 已解决

1. `main.gd` 的世界表现、会话、命令、网络、输入、HUD 和音频职责已拆到独立控制器；兼容 wrapper 暂时保留。
2. `Simulation.apply_snapshot()` 已加入版本、类型、边界、数量和字段校验，并在验证后深拷贝应用。
3. 匹配版本的非法网络快照会拒绝、断开并提示；过期或版本不匹配的 world 包仍按设计忽略。
4. GLB 静态网格、材质缓存、单位朝向、施工动画和性能热点已完成第一轮修正。

## 未完成架构项

| 优先级 | 发现 | 当前状态 | 下一步 |
| --- | --- | --- | --- |
| P0 | 字典驱动 `Simulation` 与 `scripts/entities/*` 并存，所有权不清 | unfixed | 完成调用审计，确定唯一权威模型 |
| P0 | 单位分离未覆盖全部相邻空间哈希单元 | unfixed | 补齐邻居偏移和密集边界回归 |
| P0 | MCP 测试发现没有已注册 suite | unfixed | 建立统一入口、退出码和机器可读结果 |
| P0 | `main.gd` 仍有兼容 wrapper 和 `_create_ui_legacy()` | mitigated | 下游测试迁移后删除兼容层 |
| P1 | 路径、可见性、AI、战斗、经济耦合在同一 tick | unfixed | 按固定顺序拆成 deterministic systems |
| P1 | 核心状态大量使用裸 Dictionary/string key | unfixed | 逐步引入 typed records/resources |
| P1 | AI 仍硬编码在 `Simulation`，策略不可配置 | unfixed | 抽出可测试 AI controller/policy |
| P1 | 平衡与地图参数硬编码在 GDScript | unfixed | 迁移到经过校验的 Resource/config |
| P2 | 主机按模拟频率发送完整快照 | unfixed | 在规模需要时加入 delta/relevancy/compression |
| P2 | Blender/GLB 节点、轴向和动画合约隐式 | partially mitigated | 增加导出元数据与自动断言 |
| P2 | `godot_ai` 开发态/发布态边界不明确 | unfixed | 明确 export policy 并验证 release 启动 |
| P2 | 网络脚本默认 Godot 路径依赖机器环境 | mitigated | 保留 override，同时加入自动发现 |
| P3 | 项目文档/UI 文本存在历史编码损坏 | unfixed | 统一 UTF-8 并加入检查 |

## 不变约束

- 继续保持 `Simulation.VERSION`、RPC 名称、快照字段形状和确定性 tick 顺序兼容。
- 不修改第三方 `addons/godot_ai` 源码。
- 任何重构必须保留 gameplay、presentation、视觉和 ENet 回归证据。
- 未完成项必须在计划中有明确 owner/验收标准，不能只留下无主的 TODO。

## 已知限制

- MCP suite discovery 当前为 0，测试脚本仍通过直接 Godot 入口运行。
- 受限环境访问 `.git/lfs/tmp` 偶发失败，包含 LFS 二进制的 diff 可能不完整。
- 浏览器控制通道不可用时，效果图库只能做静态 HTTP/API 验证。
