# 架构发现与决策

## 2026-09-29：工业装甲光标接入

- 当前使用系统箭头；点击字典含 action，但渲染全部为 0.55 秒黄色 billboard。
- issue() 不返回权威确认，因此落点只代表本机意图，不能声称命令成功或已寻路。
- 五种 40 像素硬件光标；箭头热点对齐箭尖，攻击热点居中。概念图目录带 .gdignore，正式资源须放在 assets/ui/cursors。
- 光标读取现有操作模式，尊重 UI 与迷雾；表现层不改 Simulation 或协议。
- Windows 原生检查须使用物理像素 DPI 上下文，否则 PowerShell 看到的 cursor bitmap/hotspot 会被虚拟化。当前五种纹理实际注册均为 40×40；不需修改游戏缩放。
- 目的地采用两套缓存 ArrayMesh 与每实例材质；固定 XZ 几何，浅层分离描边/颜色避免共面闪烁，最大同时 16 个，无逐帧网格生成。
- 原生光标无法由普通 Viewport 截图证明，增加独立 Win32 读取；实际预览同时用真实悬停、A 键与采集模式驱动状态，而非仅强制切换纹理。

## 2026-09-29：指挥中心 v2 基地

- 基地已改为 160×160（5×5），模型本地跨度 4.9×4.9，运行时缩放 32，高度约 107.84。地基、四段环体、塔身、塔冠独立分组。
- GLB 只存几何/材质，`EntityVisual` 保留共享 AnimationLibrary，并通过实例属性 `base_scan_phase` / `base_windows_power` 控制独立材质，避免多个基地之间串色或互相影响扫描相位。
- 施工沿既有 remaining/time 同步进度，阶段为地基 0–12%、四段环体 12–60%、塔身 60–82%、塔冠 82–95%。完工恢复位置并切换 2.4 秒灯光循环。
- 塔身六段灯从上到下扫描，窗口常亮；材质发光色进行饱和处理，避免 Compatibility 渲染中蓝红灯过曝成白色。
- `run-godot.ps1 -Rendered` 仅用于项目脚本的真实渲染；`tests/base_preview.gd` 输出 61 张实际动画帧及两阵营效果，目录内 HTML 可离线播放。概念图目录用 `.gdignore` 排除运行时导入与打包。

## 2026-09-29：A 键攻击移动

- `InputController` 作为场景树子节点会自动收到 `_input/_unhandled_input`，`main.gd` 的兼容 wrapper 又把相同事件转发给它；按一次 `A` 会切换两次攻击模式，随后地面左键落入普通选择逻辑并清空选中。
- 攻击移动目的地已经保存在单位 `target` 中，无需增加快照字段。交战期间保持 `order = "attack_move"`，使用既有 `attack_kind/attack_id` 表示临时目标即可在目标失效后恢复行军。
- 保持 `attack_move` 状态交战时必须同步调整动画、朝向和 stuck 计数：有活动目标时朝向目标并按距离播放移动/攻击动画，且不能把原地射击误判为移动卡住。
- 修复不改变命令、RPC、快照字段或 `Simulation.VERSION`，验证范围为 Light Simulation、Presentation、Visual，不触发 ENet 或导出。

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

- 2026-09-29 权限排查：项目配置仍为 workspace-write/on-request；八个固定入口已有 allow，新增 inspect-cursor.ps1 尚未覆盖。普通 MD/PS1 编辑授权与整条命令的沙箱外执行权限不同，采用工作区内 apply_patch 编辑、不放行任意解释器。
- 官方规则说明：https://learn.chatgpt.com/docs/agent-configuration/rules 。项目必须受信，规则在启动时加载；修改后需重启客户端。当前 PATH 无 codex，原自检会跳过规则检查，需取得实际 CLI 完成验证。

- 项目允许依赖 PowerShell；Godot、Blender、ENet、MCP、导出和清理通过 `tools/codex/*.ps1` 固定入口执行，不恢复统一 Python runner。
- Blender 资产生成脚本属于独立业务工具，不受入口语言决策影响。
- 验证以实际影响面为触发条件；失败、共享依赖、跨系统风险、发布节点或用户明确要求时才扩大范围。
- 进程清理必须保持 PID 指纹、端口归属和防误杀检查；归属不明的共享服务只报告，不停止。
- `Simulation.VERSION`、RPC 名称、快照字段形状和确定性 tick 顺序保持兼容。
- MCP 测试套件发现当前为 0；受限环境访问 `.git/lfs/tmp` 可能失败。

历史实现和问题修复见 [dev_log.md](dev_log.md)，验证证据见 [VERIFICATION.md](VERIFICATION.md)。
# 2026-09-29：立体地图接入点

- 已实现：`assets/maps/desert_quarry.tres` 为地图布局数据，`scripts/maps/map_catalog.gd` 登记地图。新增地图可复制配置并登记 ID，布局无须改动模拟或渲染代码。
- `terrain_modules.gd` 的 sand/gravel/plateau/ramp/quarry/rock 定义统一高度、材质、可通行/可建造规则；位置和尺寸对齐 32，rotation 为 0–3 个四分之一转。道路通过 points/width 配置直段、转弯和交汇；岩壁从相邻表面高度差自动生成。
- `map_terrain.gd` 生成单层高度场、通行净空、连通性及视线缓存；移动保留 Vector2，表现统一查询高度。高度允许 -96 至 192；新模块或算法变更须同步维护模块 REVISION/地图版本。
- 坡道端点高度、模块重叠、出生区域平整度与矿区连通性在加载时验证；矿坑使用 -48 台阶与 -96 坑底，中央入口坡道连接地面。
- 新协议 rts-terrain-3 在快照内传 map_id/map_version/map_checksum。校验值覆盖模块算法版本和地图配置，不传任意文件路径或每帧完整地形；不同版本客户端需使用同版项目资源。
- 地图装配固定布局，尚无随机生成器、游戏内编辑器、桥下通行或洞穴；高差不提供伤害/射程加成，水平距离规则保留。

以下为修改前的接入调查：

- 当前 reset 硬编码障碍、出生点和矿点；地图平面、输入射线、标记与实体均假设 y=0。
- AStarGrid2D 与 Vector2 逻辑坐标可保留，静态地形生成通行栅格，所有移动/避让/分离必须增加线段检查。
- 快照未包含地图标识，两个 RPC 入口都需适配。视野目前仅为半径，射击无地形遮挡。
- 本工作开始前已有光标、基地、输入和验证脚本等未提交改动，须保留。
