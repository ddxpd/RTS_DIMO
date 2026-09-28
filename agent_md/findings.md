# 架构发现与决策

## 2026-09-29：工具入口回退决策

- 项目以 Windows 开发与发布为主，允许 PowerShell 依赖；统一 Python runner 会额外引入解释器选择、共享运行时和 `psutil` 安装要求，不再作为项目工具入口。
- 恢复 `tools/codex/*.ps1` 的职责划分，由固定 wrappers 继续提供项目路径限制、参数白名单、进程台账、loopback 服务约束和清理边界。
- Codex 执行策略只允许固定 PowerShell wrapper 路径及必要的进程级 `ExecutionPolicy Bypass`，不放宽为任意 PowerShell、Python、Godot 或 Blender 调用。
- Blender 资产生成脚本仍是独立业务工具；删除入口 runner 不代表禁止项目使用 Python。
- 风险分级验证政策与工具入口语言无关，因此保持不变。

## 2026-09-28：PowerShell 弹窗来源与处理

- 任务刚开始时的大量窗口，主要来自代理将多个只读检查拆成并行的外层 PowerShell 调用；仅消除项目脚本内部的嵌套 PowerShell，无法消除这些外层窗口。
- 合理方式是每个任务先做一次聚焦的批量只读检查、复用检查结果，并把非交互 wrapper 统一为 `-NonInteractive -WindowStyle Hidden`。
- 需要人工观察输出并用 `Ctrl+C` 结束的前台流程仍可保持可见；隐藏窗口规则不适用于这种明确的交互场景。

## 2026-09-28：风险分级验证

- 原规则把“项目修改”作为全量回归和 Windows 导出的唯一触发条件，无法区分文档、工具、局部 UI、网络协议与发布任务，导致低风险修改产生大量无关进程、耗时和二进制写入。
- 新规则以影响面为触发条件：先执行最小相关验证，只有失败、共享依赖、跨系统风险、发布节点或用户明确要求时才扩大范围。
- Windows EXE 只在导出/打包/启动路径、明确二进制交付或发布验证时强制生成；普通文档和无关源码修改不再重建二进制。
- 完整清理命令本身会重新查询项目进程和端口并在残留时失败，因此默认无需立即重复 `-ReportOnly`；长驻服务和异常场景仍保留独立复查。

## 2026-09-28：PowerShell 弹窗治理

- 当前固定执行链以 `tools/codex/*.ps1` 为安全边界，不能简单改成未固定的裸 `python.exe` 调用，否则会破坏项目 execpolicy 约束。
- `run-network.ps1` 会再启动 `tests/run_network_guest.ps1`，形成 `PowerShell -> PowerShell -> Godot`；内层脚本本身只负责多进程编排，适合改成由现有 wrapper 直接完成或调用固定的无窗口辅助程序。
- `project-common.ps1` 对 Godot、Blender 和导出程序设置了 `WindowStyle = Hidden`，这些子进程不是大量 PowerShell 弹窗的主要来源。
- `addons/godot_ai/utils/port_resolver.gd` 通过 `OS.execute()` 多次调用 `powershell.exe`，用于端口 PID、进程祖先、命令行和指纹查询；这些调用没有 Windows `CREATE_NO_WINDOW` 控制，是连续弹窗的主要风险点。
- 插件现有 `client_configurator.gd` 已采用 `pythonw.exe + subprocess(..., creationflags=0x08000000)` 解决 Windows stdio 子进程弹窗，证明项目已有可复用的无窗口设计先例。
- 本次采用更小的兼容修复：PowerShell CLI 原生支持 `-NonInteractive -WindowStyle Hidden`，可继续使用现有同步 `OS.execute()` 输出通道，不引入 Python 路径发现或新依赖。
- 联机 runner 无需迁移语言；PowerShell 通过调用运算符 `&` 可在当前 runspace 直接执行 `.ps1`，保留参数、异常和退出语义并消除第二个 `powershell.exe`。
- 效果图库只为延迟打开浏览器而额外启动 PowerShell；延迟打开逻辑已移入现有 `server.py` 的守护计时线程，避免浏览器早于 HTTP 监听器启动，也不再派生 PowerShell。
- `verify-permissions.ps1` 的 wrapper 语法、Godot/Blender 固定入口和进程清理检查通过；当前命令环境的 `PATH` 没有 `codex` 可执行文件，因此脚本内的 execpolicy CLI 子检查按设计跳过，规则文件本身未改动。

## 2026-09-28：Markdown 中文化

- 项目规则要求所有计划、发现、进度和验证记录留在 `agent_md/`，因此本次任务记录不写入项目根目录。
- 现有 `agent_md/task_plan.md`、`findings.md` 和 `progress.md` 含中文；PowerShell 未显式指定 UTF-8 时曾出现终端乱码，后续读取必须使用 UTF-8。
- 翻译时保留代码块、行内代码、路径、命令、URL、Godot/GDScript/API 等技术标识符，避免破坏可执行示例和链接。
- Markdown 清单共 14 份：根目录 2 份、`agent_md/` 9 份、`tools/` 2 份、`addons/godot_ai/` 1 份；项目文档叙述已是中文，英文重点集中在规则入口、授权日志和第三方 README。

## 2026-09-26：绿色 3D 选中圈

- 选择状态由 `main.gd` 的 `selected_units`、`selected_building` 和 `selected_buildings` 提供；`WorldVisualSync` 每帧同步单位/建筑视觉，适合在此调用 `EntityVisual.set_selected()`。
- 选中圈采用实体表现层的延迟创建 `TorusMesh`，作为 `EntityVisual` 的兄弟节点放在地面上方，不加入 GLB 模型层级和动画轨道；固定亮绿色，不使用阵营材质。
- 单位圆环默认半径为单位碰撞半径的 1.25 倍；建筑圆环默认半径为底座矩形半对角线加 4.0 安全边距，确保完整覆盖底座四角。`SELECTION_RING_PROFILES` 支持按类型配置倍率、边距或绝对半径覆盖；圆环关闭阴影并保持固定亮度和大小。
- `EntityVisual.set_selected()` 可能在 `_ready()` 前被调用，因此 `_ready()` 末尾必须补应用待处理的选中状态，避免刚建造且已选中的建筑缺少圆环。
- 已生成 `build/verification/selection_ring_preview.png`，预览确认士兵与建筑均能被醒目的绿色圆环包围；视觉、玩法、表现、功能、相机、操作栏、性能、ENet 和 Windows EXE 冒烟运行均已通过。

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
- 新 GLB 导出后必须执行 `run-godot.ps1 -Action import`，否则无界面脚本可能继续加载旧 `.godot/imported` 缓存。
- 2026-09-26 验证结果：视觉、玩法、功能、表现、相机、操作栏、ENet 全部通过；最终性能独立重跑 6.53065ms；Windows EXE 冒烟运行 5 秒通过。

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
| P0 | 字典驱动 `Simulation` 与 `scripts/entities/*` 并存，所有权不清 | 未修复 | 完成调用审计，确定唯一权威模型 |
| P0 | 单位分离未覆盖全部相邻空间哈希单元 | 未修复 | 补齐邻居偏移和密集边界回归 |
| P0 | MCP 测试发现没有已注册测试套件 | 未修复 | 建立统一入口、退出码和机器可读结果 |
| P0 | `main.gd` 仍有兼容 wrapper 和 `_create_ui_legacy()` | 已缓解 | 下游测试迁移后删除兼容层 |
| P1 | 路径、可见性、AI、战斗、经济耦合在同一 tick | 未修复 | 按固定顺序拆成确定性系统 |
| P1 | 核心状态大量使用裸 Dictionary/string key | 未修复 | 逐步引入类型化 records/resources |
| P1 | AI 仍硬编码在 `Simulation`，策略不可配置 | 未修复 | 抽出可测试 AI controller/policy |
| P1 | 平衡与地图参数硬编码在 GDScript | 未修复 | 迁移到经过校验的 Resource/config |
| P2 | 主机按模拟频率发送完整快照 | 未修复 | 在规模需要时加入 delta/relevancy/compression |
| P2 | Blender/GLB 节点、轴向和动画合约隐式 | 部分缓解 | 增加导出元数据与自动断言 |
| P2 | `godot_ai` 开发态/发布态边界不明确 | 未修复 | 明确 export policy 并验证 release 启动 |
| P2 | 网络脚本默认 Godot 路径依赖机器环境 | 已缓解 | 保留 override，同时加入自动发现 |
| P3 | 项目文档/UI 文本存在历史编码损坏 | 未修复 | 统一 UTF-8 并加入检查 |

## 不变约束

- 继续保持 `Simulation.VERSION`、RPC 名称、快照字段形状和确定性 tick 顺序兼容。
- 不修改第三方 `addons/godot_ai` 源码。
- 任何重构必须保留 gameplay、presentation、视觉和 ENet 回归证据。
- 未完成项必须在计划中有明确 owner/验收标准，不能只留下无主的 TODO。

## 已知限制

- MCP 测试套件发现当前为 0，测试脚本仍通过直接 Godot 入口运行。
- 受限环境访问 `.git/lfs/tmp` 偶发失败，包含 LFS 二进制的 diff 可能不完整。
