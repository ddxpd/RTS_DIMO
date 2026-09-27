# 架构发现与决策

## 2026-09-26：绿色 3D 选中圈

- 选择状态由 `main.gd` 的 `selected_units`、`selected_building` 和 `selected_buildings` 提供；`WorldVisualSync` 每帧同步单位/建筑视觉，适合在此调用 `EntityVisual.set_selected()`。
- 选中圈采用实体表现层的延迟创建 `TorusMesh`，作为 `EntityVisual` 的兄弟节点放在地面上方，不加入 GLB 模型层级和动画轨道；固定亮绿色，不使用阵营材质。
- 单位圆环默认半径为单位碰撞半径的 1.25 倍；建筑圆环默认半径为底座矩形半对角线加 4.0 安全边距，确保完整覆盖底座四角。`SELECTION_RING_PROFILES` 支持按类型配置倍率、边距或绝对半径覆盖；圆环关闭阴影并保持固定亮度和大小。
- `EntityVisual.set_selected()` 可能在 `_ready()` 前被调用，因此 `_ready()` 末尾必须补应用待处理的选中状态，避免刚建造且已选中的建筑缺少圆环。
- 已生成 `build/verification/selection_ring_preview.png`，预览确认士兵与建筑均能被醒目的绿色圆环包围；visual、gameplay、presentation、features、camera、action_bar、性能、ENet 和 Windows EXE smoke 均已通过。

## 2026-09-26：2D 格子血条

- 现有单位/建筑 HP 显示由 `WorldVisualSync._make_status_bar()` 创建 billboard `Sprite3D`，并挂在实体模型顶部；HUD 已有 `CanvasLayer`，主相机提供 `unproject_position()` 和地图区域裁剪入口。
- 新血条采用单个 `HealthGridOverlay` 自绘 `Control`，条目只保存实体世界坐标、投影位置、当前/最大 HP、阵营和每格填充比例，不创建模型或逐格节点。
- 每 10 点最大生命值生成一格，最后不足 10 点按比例填充；单位目标宽 72px、建筑目标宽 120px，按格子数量缩放格宽，最小格宽 1.5px。
- 建造进度和采集量不是 HP，继续使用现有辅助状态条；模拟 HP 字段、伤害判定、快照和 ENet 协议不变。
- `tests/visual_models.gd` 已确认士兵 100 HP 为 10 格、基地 800 HP 为 80 格、25 HP 的第三格为半格，并确认投影位置与相机一致；性能回归 180 单位下 `sync_visuals_ms=7.2193`。

## 2026-09-26：士兵与能量弹重做

- 当前士兵由 `assets/models/soldier.glb` 提供；运行时动画仍依赖旧 `Body`、`Head`、`Arm_L/R`、`Leg_L/R`、`Hips`、`Weapon`、`Muzzle` 路径。本次按用户选择完全重做内部层级，并同步动画与测试。
- 新士兵语义节点确定为 `ArmorCore`、`Helmet`、`Shoulder_L/R`、`Arm_L/R`、`Hips`、`Leg_L/R`、`Weapon`、`Muzzle`；正面继续使用本地 `+Z`，保持现有朝向约定。
- 队伍材质只允许出现在左右护肩标识；枪械、前臂、头盔侧面和其他装甲使用中性材质。现有 `set_faction()` 可继续通过材质名中的 `Faction` 识别阵营材质。
- 当前 `shot` 表现是 `WorldVisualSync._sync_effects()` 创建的白色 billboard `Sprite3D`；模拟已提供 `from`、`to`、`life`、`owner`、`frame`，足以驱动 3D 弹体，无需修改快照 schema。
- 能量弹采用独立 `bullet.glb`，本地 `+Z` 为前向，蓝白发光核心加简洁尾焰；死亡效果继续使用现有 Sprite3D。
- 共享 Blender 源必须只删除并重建 `soldier`/`bullet` 层级，保留地堡和其他资产；导出后必须强制 Godot import。
- Blender 预览已生成：士兵是简化的大块硬表面护甲，护肩有浅蓝阵营标识，枪械/前臂/头盔侧面没有阵营标识；能量弹预览为实体核心、外壳和锥形尾焰，已不再是方点。
- 生成日志仅有 Blender 5.2.2 的 `Material.use_nodes` 弃用警告，不影响 GLB 导出；Godot import 后的新 GLB 节点路径、材质名、动画、弹体朝向和生命周期断言均已通过。
- ENet 回归首次发现：效果键只由 `frame` 和数组索引组成时，能量弹体 Node3D 可能被死亡 Sprite3D 复用，导致把 `modulate` 写入空 Sprite3D 类型。修复为按效果类型检查并重建不匹配的视觉节点；重新运行视觉测试和完整 ENet 主客机回归后通过。
- Godot import 后新 GLB 节点契约加载成功；`tests/visual_models.gd` 已通过，确认新士兵动画、护肩阵营材质、3D 能量弹朝向和过期清理均正常。

## 2026-09-26：地堡模型续作

- UUID 参考图位于 `C:\Users\happydog\.codex\generated_images\01a0d8a7-d5de-72f3-a027-d8e07be6d0e1\exec-bbaa3646-52d1-4d57-a8ec-67b7b1aa17cd.png`，目标是低矮圆台装甲、单管炮塔和两侧蓝色灯带。
- 中断的 `tools/blender/create_bunker.py` 会清空共享 Blender 场景，并且节点仍是旧契约不完整；实施时必须只删除 `bunker` 层级，并以 `-BlendFile assets/models/source/ironfront_models.blend` 显式运行。
- Godot 动画由 `assets/art/entity_visual.gd` 运行时生成，GLB 只提供静态层级；新的契约采用单炮管和 `FactionLights/FactionLight_L/R`。
- 建造动画采用地下升起成型，使用 Body、Turret 和灯带的归一化变换轨道，并在离开 construction 时复位子节点。
- 实际导入后共享 Blender 场景中已有士兵 `Body` 名称，因此地堡根节点使用 `BunkerBody` 保证 GLB 路径稳定；对应 Godot 路径为 `bunker/BunkerBody`。
- 新 GLB 导出后必须执行 `run-godot.ps1 -Action import`，否则 headless 脚本可能继续加载旧 `.godot/imported` 缓存。
- 2026-09-26 验证结果：视觉、玩法、功能、表现、相机、操作栏、ENet 全部通过；最终性能独立重跑 6.53065ms；Windows EXE smoke 5 秒通过。

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
