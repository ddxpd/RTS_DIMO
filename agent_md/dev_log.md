# 开发日志

## 2026-09-19：RTS 操作增强（第 4 批功能）

### 新增功能

#### 1. 左键双击同类选择
- 双击某个己方单位（0.4 秒内两次点击同一单位）→ 选中当前屏幕范围内所有同类单位
- 实现位置：main.gd 的 _left_click 与新增 _select_same_type_on_screen
- 屏幕范围按相机视野矩形（viewport / zoom 计算）判定

#### 2. 底部状态栏生产进度与队列
- 选中生产建筑时，底部新增：
  - 进度条（ProgressBar）：当前建造单位的完成百分比
  - 队列文本：QUEUE (n / 5) + 每项名称（当前项显示百分比）
- 底部栏重构为 HBox 布局：单位状态 | 生产面板 | 操作按钮
- 无建筑选中时自动隐藏

#### 3. 编队（控制组）
- Ctrl + 数字：将当前选中单位设为该编队（重新创建）
- Shift + 数字：将当前选中单位追加到该编队
- 单独按数字：召回编队（自动过滤已死亡/非己方单位）
- 支持编队 1–9；空选时 Ctrl+数字清除编队
- 实现位置：main.gd 的 _unhandled_input 数字键分支与 _control_group_key

#### 4. 建筑集合点（集结点）
- 选中建筑后右键点击地图设置集结点（32px 网格吸附）
- 新单位生产完毕出生后自动向集结点移动
- 选中建筑时绘制集结点标记：建筑→集结点连线 + 圆圈 + R 标签
- 网络协议新增 set_rally 命令（主机权威校验），建筑快照携带 rally 字段
- 实现位置：simulation.gd 的 command / step / _add_building；main.gd 的 _right_click / _draw

### 功能改变
- 底部提示栏更新操作说明（双击、编队、集结点按键提示）
- 建筑状态栏标题增加 Right-click: rally point 提示
- _add_building 数据结构新增 rally 字段（默认 Vector2.ZERO = 不集结）

### 验证记录
- 新增 tests/features.gd：4 项功能 headless 全测通过
- 回归：gameplay 47/0、presentation 0、action_bar 0 全过
- 实机验证：双击选中 2 同类 / Ctrl+1 编组召回 / 进度条 1% 显示 / 集结点吸附 (608,512)
- 导出 build/IronFront.exe（2026-09-19 23:12:22）

## 2026-09-19：底部状态栏遮挡修复

### 问题原因（两处叠加）
1. 消息栏（底部 42px）与底部面板（原底部 132px）重叠：按钮第 2 行底边 1048 > 消息栏顶 1038，被盖住 10px
2. 操作按钮网格共 16 个（4 行），第 3 行起 y=1052 已超出 1080 视口，完全不可见
3. 队列文本最多 6 行（5 个任务逐行列出），进一步撑高生产面板

### 修复
- 底部面板上移至消息栏正上方：offset_top -174 / offset_bottom -42（高度不变 132px）
- 操作按钮精简为 8 个（4 列 × 2 行），删除本来就看不见的第 3、4 行
- 队列文本压缩为固定 3 行：QUEUE (n / 5) / Now: X 进度% / Next: Y+Z…

### 修复后布局（1080p 实测）
- 按钮两行：918–960、964–1006，全部位于面板 906–1038 内
- 消息栏 1038–1080，与面板零重叠（余量 32px）

### 验证
- 实机矩形数值验证 + 截图确认
- 回归：gameplay 47/0、presentation、action_bar、features 全过
- 导出时发现旧版 IronFront.exe 进程占用文件导致重命名失败，结束进程后导出成功（23:22:11）

## 2026-09-19：修复建筑无法编队召回

### 问题
- Ctrl+数字 选中建筑时，_control_group_key 只检查 selected_units；建筑选中时该数组为空，走入"清除编队"分支，导致按数字无法召回

### 修复
- 编队数据结构升级：Array[int] → {"units": Array[int], "building": int}
- Ctrl+N：同时保存当前选中单位与建筑
- Shift+N：追加单位；若当前选中的是建筑则保存/替换编队建筑
- 按 N 召回：优先召回单位（可下令）；无单位时召回建筑（显示生产面板）；建筑被摧毁后自动失效

### 验证
- tests/features.gd 新增：建筑编队召回、混合编队优先单位，全过
- 实机复现用户场景：基地 Ctrl+1 → 清空 → 按 1 → 成功选中基地（recalled_building=1）
- 回归 4 套全过；导出 EXE（23:45:32）

## 2026-09-19：地堡单位 + 新胜利条件

### 新增：地堡（Bunker）
- 类型：建筑（不可移动、可攻击），由基地生产
- 数值：HP 500 / $300 / 生产 6 秒 / 射程 190 / 伤害 14 / 冷却 0.7 秒
- 生产流程：基地队列 BUNKER → 完成后在基地附近自动寻找无碰撞落点（32px 吸附，避开建筑/岩石/矿石）直接放置
- 战斗：自动攻击射程内最近的可视敌方单位（受战争迷雾约束），曳光效果与单位攻击一致
- UI：选中基地时出现 BUNKER ($300) 按钮；选中地堡显示射程圈
- 美术：新增 16x16 像素地堡贴图（Team 色炮塔 + 灰色掩体）

### 规则改变：胜利条件
- 旧：失去全部基地即判负
- 新：失去**全部建筑**（基地/兵营/地堡任一存活即继续比赛）

### 实现要点
- BUILD_TYPES 新增 bunker 条目（含 range/damage/cooldown）；建筑字典新增 cooldown 字段
- 生产校验/取消退款改用 _job_stats(kind) 统一查单位与地堡数值
- sim.command 新增 bunker 生产分支；step 完成时走 _bunker_site 自动放置
- 胜利判定 has_base → has_building

### 验证
- tests/gameplay.gd 更新：拆基地但留兵营不判负 + 拆光全部建筑才判负（48 checks 全过）
- tests/features.gd 新增：地堡生产/自动放置/开火 用例全过
- 实机：BUNKER ($300) 按钮可用、自动放置 (320,192)、红方士兵进入射程掉血、蓝方仅剩地堡不判负
- 回归 4 套全过；导出 EXE（23:55:06）

## 2026-09-20：经济系统重构（矿场 / 地堡直接建造 / 自动采矿）

### 新增：矿场（Refinery）
- 类型：建筑，直接放置建造（与兵营一致，进度条施工）
- 数值：HP 600 / $400 / 建造 5 秒
- 职能：生产矿车（MINER $200）；矿车卸货交付点（替代基地）
- AI 优先建造矿场恢复经济，再建兵营

### 规则改变
1. 地堡不再由基地生产：改为像兵营一样直接放置建造（BUNKER $300 按钮，进度条施工）
2. 基地不再生产矿车：生产按钮禁用（生产职能移交矿场）
3. 兵营仅生产枪兵（soldier）
4. 矿车自动采矿：闲置/新生产的矿车自动前往最近可见金矿采矿；明确 stop 后停止自动（新指令 gather 恢复）

### 实现要点
- BUILD_TYPES 新增 refinery；建筑按钮重排：[1]生产（兵营=枪兵/矿场=矿车） [2]BARRACKS [3]REFINERY [4]CANCEL [5]BUNKER [6]BASE
- 单位字典新增 auto 字段：stop 置 false，gather/新单位置 true；闲置矿车每 10 tick 调用 _auto_mine 找最近可见矿
- _gather 卸货目标 base → refinery（无矿场则满载等待）
- 移除基地生产地堡分支与 _bunker_site 自动放置；新增矿场像素贴图

### 验证
- gameplay 53 checks 全过（新增：基地/兵营拒绝矿车、矿场拒绝枪兵、闲置自动采矿、stop 后保持 idle）
- features：矿场生产+集结、地堡直接放置+施工+开火 全过
- presentation 适配矿场（建筑计数 3→4）
- 实机：矿场 MINER ($200) 可用、新矿车自动 gather 矿1、stop 后 idle、基地生产按钮禁用
- 回归 4 套全过；导出 EXE（00:14:54）

## 2026-09-20：移除侧栏过时生产按钮

### 问题
- 右侧 FIELD COMMAND 面板残留 "Train Soldier $100" 与 "Build Harvester $200" 两个常驻按钮，无视当前选中建筑；选中矿场时它们仍可点击（点击后 sim 拒绝并弹错误提示），让用户误以为矿场可以生产其他单位

### 核实
- 运行时验证：矿场 + Train Soldier → 队列 0、提示 Wrong production building（模拟层校验一直正确）
- 误导来源确认是 UI 而非逻辑

### 修复
- 删除侧栏两个过时生产按钮；生产入口统一为底部操作栏的上下文按钮（兵营=SOLDIER、矿场=MINER）

### 验证
- 回归 4 套全过；导出 EXE（00:18:39）

## 2026-09-20：修复屏幕边界滚动镜头

### 问题
- 放大地图后无法用鼠标贴屏幕边缘移动镜头

### 根因
- camera_controller.gd 早已实现边界滚动（32px 边缘检测、速度随缩放换算），但 main.gd 只声明了 camera_controller 变量，从未实例化、也从未在 _process 中调用 update(delta)——整个控制器是死代码，任何缩放级别下边界滚动都不工作
- zoom=1 时世界(1600x960)小于视口(1920x1080)，镜头被钳制在世界中心无法移动；放大后世界超出视口，用户因此才暴露此问题

### 修复
- _ready 中实例化 CameraController（传入相机、世界尺寸、视口尺寸与地图屏幕区域 provider，区域与 _screen_is_map 一致：顶部 52px/右侧 260px/底部 132px 以内）
- _process 在 active 且非菜单时调用 camera_controller.update(delta)，与键盘 WASD/方向键移动并存

### 验证
- 实机：zoom=2.0、鼠标贴左边缘 0.5 秒，镜头 x 798.5→692.1（210px/s = 420/zoom，精确匹配）
- 鼠标在地图区域内非边缘位置不移动；菜单时禁用
- 回归 4 套全过；导出 EXE（00:21:56）

## 2026-09-20：窗口模式鼠标锁定

### 功能
- 进入对局（单人/主机/加入）时设置 Input.mouse_mode = MOUSE_MODE_CONFINED，鼠标被限制在游戏窗口内、指针仍可见
- 离开对局时恢复 MOUSE_MODE_VISIBLE：return_to_title / 主机断开 / 连接失败
- 新增 _exit_tree 兜底恢复，游戏节点退出时永不遗留锁定状态

### 验证
- 实机：标题=VISIBLE(0) → 进对局=CONFINED(3) → 回标题=VISIBLE(0)
- tests/features.gd 增加进对局锁定/回标题释放断言（headless 无窗口环境自动跳过）
- 回归 4 套全过；导出 EXE（00:25:52）

## 2026-09-20：镜头"挪不动"修复 + 完整镜头测试

### 根因
- 缩放范围原来允许 0.65，但世界(1600x960)在 zoom<=1.2 时整体小于视口(1920x1080)，镜头被钳死在世界中心完全无法移动
- 滚轮向下很容易误触缩小 → 一旦越过临界值就"挪不动"——与用户报告"移动一会儿后挪不动"吻合

### 修复
- 新增 _min_zoom()：max(viewport.x/WORLD.x, viewport.y/WORLD.y) + 0.05，保证任何缩放级别下世界两轴都严格大于视口，镜头永远有移动余量
- 滚轮 clamp 0.65→_min_zoom()；_reset_view 初始 zoom 也遵守下限
- CameraController 重构：鼠标位置改为 provider 注入（生产接 camera.get_viewport().get_mouse_position()，测试可注入确定值），行为不变

### 新增 tests/camera.gd（6 组用例）
1. 动态缩放下限：世界不可整体装入视口
2. 连续 10 次滚轮缩小压不破下限
3. 四方向边缘滚动（zoom 2，各移动 210px）
4. 世界边缘钳制（不越界）
5. 长时间滚动到边界后反向可恢复（"卡死"场景回归）
6. 缩放锚定（鼠标所指世界点不漂移，窗口模式）

### 实机验证
- min_zoom=1.25，开局 zoom=1.25，20 次缩小事件后仍 1.25
- zoom 2 连续滚动：800→590→480（边界钳制）→保持，反向恢复正常
- 回归 5 套全过；导出 EXE（00:35:01）

## 2026-09-20：垂直边缘滚动改用窗口边界

### 改动
- 上下边缘滚动触发从"地图区域边界"（顶 52px/底 132px HUD 内沿）改为**窗口物理边缘**（上下 32px）
- 水平保持不变：左侧=窗口/地图重合，右侧仍锚定地图区右沿（侧面板遮挡）
- 原 map_rect.has_point 门外移除——鼠标在顶部标题栏/底部状态栏区域贴窗口边时也能垂直滚动

### 验证（tests/camera.gd + 实机）
- 窗口顶 y=2：镜头 480→270（上移，钳制上边界）
- 窗口底 y=1078：480→690（下移，钳制下边界）
- 旧地图条带 y=60 / y=940：不再触发（新增 3b 死区用例）
- 回归 5 套全过；导出 EXE（00:38:23）

## 2026-09-20：镜头速度设置

### 新增
- 暂停/标题菜单新增 Camera speed 滑条：0.5x–3.0x（步进 0.1），实时显示倍率
- 默认 1.4x（较原速稍快）：边缘滚动 420→588 px/s，键盘 500→700 px/s
- 同时作用于边缘滚动与 WASD/方向键
- 设置持久化到 user://settings.cfg，重启后保留

### 实现
- CameraController 新增 speed_multiplier；main 侧 _camera_speed_changed 同步滑条/倍率/控制器并保存
- _ready 时 _load_settings 读取（带范围钳制），创建控制器后应用

### 验证
- tests/camera.gd 用例 7：默认 1.4x、倍率缩放边缘滚动（2.0x 时 1 秒移动 420px）、控制器同步
- 实机：滑条默认 1.4x / 标签 1.4x / 控制器 1.4；设 2.0 后三者同步为 2.0，标签 2.0x
- 回归 5 套全过；导出 EXE（00:43:44）

## 2026-09-20：建筑界面按类型过滤 + 规则总结文档

### 修复
- 之前任何选中建筑都显示全部建造按钮（兵营/矿场/地堡/基地）——矿场界面能看到"建造兵营"等无关选项
- 改为按建筑类型过滤：兵营=SOLDIER+CANCEL；矿场=MINER+CANCEL；基地=四种建造指令；地堡=无按钮
- 集结点提示只在兵营/矿场显示（基地已不生产）

### 实机验证
- refinery → ["MINER ($200)","CANCEL (Refund)"]；barracks → ["SOLDIER ($100)","CANCEL"]；base → 四种建造；bunker → 空

### 文档
- 新增 agent_md/game_rules_zh.md：全部现行规则中文总结（模式/胜负/经济/单位/建筑/生产/战斗/视野/操作/镜头/设置/AI）

### 验证
- 回归 5 套全过；导出 EXE（00:54:19）

## 2026-09-20：上传策略与历史清理

### 新增规则（agent_md/AGENTS.md）
- 大文件上传规则：推送包含 >10MB 大文件（EXE/PCK/LFS 对象）前，必须单独询问用户是否包含，并提供"排除大文件 / 改用 GitHub Releases"选项，等待明确批准

### 历史清理
- filter-branch 从 50 个未推送提交中剥离全部旧版 EXE（本地保留 backup/pre-exe-rewrite 备份分支）
- 最新 EXE 以单一 LFS 对象重新提交（7da45af，仅本地）

### 上传（方案 B）
- 用户选择排除 EXE：git push origin HEAD~1:main，50 个提交 6 秒完成，零 LFS 流量
- 远端 main：4f274c6 → 5e48a8c；本地保留 1 个未推送提交（EXE）

## 2026-09-20：Guest 顿挫改善（20Hz 快照 + 客户端平滑）

### 问题
- Guest 以 10Hz 接收主机快照（每 2 逻辑帧发 1 次），且两次快照之间状态完全静止，144FPS 渲染下移动呈明显跳档

### 改动
1. 快照频率 10Hz → 20Hz：主机每个逻辑帧（0.05s）广播一次 _world（LAN 下带宽可接受）
2. Guest 端逐帧外推：_world 时由相邻快照计算每单位速度（上限 400px/s）；渲染帧之间按 v×delta 推进位置，下一快照到达即被权威状态校正
3. Guest 端特效平滑：曳光/爆炸的 life 在渲染帧间按 20tick/s 本地衰减，不再只随快照跳变

### 测试
- network_probe 新增断言：连续 30 个快照帧差恒为 1（20Hz）、render_velocities 覆盖全部单位
- 适配矿场经济的探针流程（先建矿场→采矿→兵营→产兵，金额按 200/260/110 阶段校验）
- 网络 4 场景全过：guest r1（快照一致性）、guest r2（重连+主机断开）、spectator（权限）、mismatch（协议拒绝）
- 本地回归 5 套全过；导出 EXE（19:26:07）

## 2026-09-20：右边缘滚动改用窗口边界

### 问题
- 右侧水平滚动的触发带锚定在"地图区域"右沿（x=1660，侧面板内沿，触发带 x≥1628）——鼠标距窗口右缘约 290px 时镜头就开始移动

### 修复
- 四个方向统一以**窗口物理边缘**（上下左右各 32px）触发
- 移除 CameraController 的 map_area_provider（不再需要地图区域）；侧面板所在的中段区域成为自然死区，鼠标在面板上操作不会误滚

### 验证
- tests/camera.gd：右侧用例改为窗口右缘触发；旧地图条带（x=1652 等 3 处）新增死区断言不触发；边界恢复用例同步修正
- 实机：x=1652 镜头不动；x=1910 右移触发
- 回归 5 套全过；导出 EXE（19:30:13）

## 2026-09-20：地图×10 + 资金×10 + 矿车对撞修复

### 地图与经济
- WORLD 1600x960 → 4800x3200（面积精确 10 倍）；网格 50x30 → 150x100（GRID/GROUP 常量化，消除全部硬编码）
- 初始资金 600 → 6000；双方基地/部队/矿脉/岩石按比例重新布局（点对称）
- 动态最小缩放自适应大地图（~0.45，可拉远观察全局）

### 矿车对撞死锁修复（三层机制）
1. 单位阻挡检测：move_towards 新增 _unit_blocks（position_free 只查地形/建筑，不含单位——旧实现对撞双方直接走进重叠再被分离推回，循环卡死）
2. 右侧让行：被单位阻挡时向行进方向右侧 45° 变道——相向车流天然形成双向车道
3. 分离仅处理深度重叠（< 最小间距-1），贴合状态交给变道逻辑，消除"切向分离 vs 路径引力"的平衡死锁；地形受阻时双向侧步 + 放弃被裁剪的航点（修复岩石拐角冻结）

### 测试适配
- gameplay 55 checks：新增对撞双向通过断言（轮询到达，规避自动采矿时序）；战斗用例迁移到无干扰坐标；网格索引 GRID 化
- network_probe：红方建造坐标避开矿脉判定区；金额阈值适配 6000 经济；超时 55s→120s（大地图行程）
- 全量回归 5 套 + 网络 round1（含快照一致性）全过

### 实机验证
- 面积比 10.0、资金 6000、对撞矿车 110 tick 双向到达
- 导出 EXE（19:59:19）

## 2026-09-20：开局配置调整（6 枪兵 / 无矿车）

### 改动
- 开局单位：双方各 2 枪兵+1 矿车 → **各 6 枪兵、0 矿车**（单列纵队贴基地右侧）
- 单位 ID 体系随之变化：蓝方士兵 3-8，红方士兵 9-14
- AI 经济适配：矿场建成后自动生产矿车（上限 3，队列≤2），维持采矿收入

### 测试适配
- gameplay：开局 12 单位断言；采集/自动采矿/红方交付用例改为显式 add_unit 矿车；战斗目标 ID 8→9（红方士兵）；AI 数量阈值 >12
- network_probe：采矿流程改为"建矿场→产矿车→选中→采集"；击杀用例改选红方 9 号；位置等待改距离阈值（适配 guest 位置外推）
- features：编队附加矿车改为显式生成

### 验证
- 实机开局：1_soldier=6 / 2_soldier=6，无矿车；30 秒后 AI 自产 4 矿车、15 士兵、采矿中（ore 4000→3820）
- 本地 5 套 + 网络 round1（快照一致）全过
- 导出 EXE（20:19:23）

## 2026-09-20：修复框选被 HUD 打断

### 根因
- _input 中"左键松开位置不在地图区 → selection_dragging = false"：拖选越过底部状态栏/右侧面板时松开，整次框选被静默丢弃
- 且鼠标经过 HUD 期间，GUI 会吞掉 motion 事件，_unhandled_input 收不到 → 框不再跟随

### 修复
1. _input 在 GUI 消费之前处理：拖选中 motion 持续更新 selection_current（框在 HUD 上方也不冻结）
2. 松开时调用新提取的 _finish_drag_select(pos)：完成选择（小位移=点击，大位移=框选），不再因位置丢弃
3. _unhandled_input 的松开分支同样改用 _finish_drag_select；_input 已处理后 dragging=false，天然不会重复处理

### 验证
- presentation 新增用例：拖到 HUD 上松开仍完成选择（6 单位）
- 实机：地图按下→拖过 HUD→松开 → selected=6、dragging=false
- 回归 5 套全过；导出 EXE（20:27:14）

## 2026-09-20：资源扩展 + AI 小队化 + 采矿减速 + 规则数值化

### 资源
- 金矿 3 处 → **9 处**（点对称：双方近点/二矿/上下路/远点，储量 4000-7000）
- 采矿时间 ×5：每 10 矿 4 tick(0.2s) → **20 tick(1.0s)**，实机精确验证

### AI 重写
- 旧：frame>1200 后每个闲置士兵排队攻击敌方基地
- 新：经济优先（矿场→5 矿车→兵营→持续产兵→富余 $1200 建地堡）；防御优先（敌入己方建筑 600px 内派 ≤6 士兵拦截）；小队战术（<6 士兵基地旁集结，≥6 以 attack_move 扑向**最近敌方建筑**，途中自动交战）
- 实机 2 分钟：AI 建齐 4 类建筑、6 矿车采矿、19 士兵 attack_move 猎杀、推平无操作蓝方

### 规则文档
- agent_md/game_rules_zh.md 重写：完整数值表（单位 HP/价格/时间/移速/半径/攻击五维、建筑四维、9 矿坐标储量、岩石、采矿节拍、AI 行为树、开局配置）

### 验证
- 本地 5 套 + 网络 round1（快照一致，探针超时上调 180s 适配慢采矿）全过
- 导出 EXE（20:41:10）

## 2026-09-20：修复按住拖选时框中途消失

### 根因
- Godot 在焦点扰动/鼠标受限顶边时会发送 canceled=true 的 InputEventMouseButton 释放事件；_input 把任何 pressed=false 都当真实释放 → 提前 _finish_drag_select → 框消失
- 且 Input.is_mouse_button_pressed 的内部状态同样会被 canceled 事件污染，不能作为"物理按住"判据

### 修复（三层）
1. 自跟踪按键状态 left_button_held：只由非 canceled 的按下/释放事件更新
2. 释放完成拖选的守卫：canceled 事件直接忽略；left_button_held 仍为 true 时不完成
3. _process 每帧兜底：dragging 且自跟踪状态已释放（事件彻底丢失）时用 selection_current 完成选择，防卡死

### 验证
- presentation 新增 2 用例：canceled 不中断拖选、真实释放正常完成；丢释放事件走帧兜底（需临时启用 _process——该测试默认 set_process(false)）
- 实机：按下→注入 canceled→按住 3 秒（约180帧）→仍存活；真实释放后选出 6 单位
- 回归 5 套全过；导出 EXE（20:52:46）

## 2026-09-20：Download ZIP 分发陷阱与修正

### 事件
- 用户从 GitHub 仓库 Download ZIP 下载后无法运行：报"此应用无法在你的电脑上运行"
- 根因：ZIP 打包不还原 LFS 对象，其中 IronFront.exe 实为 ~134 字节指针文本文件而非 104MB 真实程序；SmartScreen 之后的报错即 Windows 执行非 PE 文件

### 修正
- 提供媒体直链立即解决：https://media.githubusercontent.com/media/ddxpd/RTS_DIMO/main/build/IronFront.exe（校验 109,204,120 字节）
- 指引用户创建 v0.1 Release 并把 EXE 作为附件发布（标准分发渠道）
- 新增 Binary distribution rule：大文件一律走 Release 附件或媒体直链；向用户提供构建时必须附字节级校验

### 教训
- "上传含 EXE 到仓库"≠"用户可从仓库直接下载可执行文件"——LFS 仓库的 ZIP 下载是经典陷阱，今后发布构建默认同时更新 Release 并给直链

## 2026-09-20：编队绕角卡死 + 末格冻结（用户报告 #2）

### 用户报告（确认属实，两个关联 bug）
1. 成团士兵绕地形拐角时部分卡在角落无法通过
2. 同批士兵到达后，被卡士兵完全停止移动（未到终点）

### 根因
- **角落卡死**：地形受阻只尝试 ±45° 侧步；群体挤压下两侧步均被挡 → 放弃航点 → 重寻路回同一路径 → 循环
- **末格冻结**：编队偏移落点贴地形时 position_free 失败 → 终点不追加进路径；士兵到达最后一个导航格中心后路径恒空且直接到达判定缺失 → 永久原地（命令仍 move，>5px）——拥堵解除后恢复走到末格即触发 = "别人到了我就停"

### 修复方法（与 Bug 一一对应）

**Bug 1「角落卡死」→ 修复 ①③**
- ① 侧步升级：move_towards 地形受阻分支由仅 ±45° 扩展为依次尝试 +45°/-45°/+90°/-90°（垂直侧步专治拐角夹持），全部被挡才放弃当前航点
- ③ 卡死兜底：单位新增 stuck 字段；step() 中 move/attack_move/gather 状态每 tick 比较位移，<0.005 计数、有位移清零；连续 40 tick（2 秒）无进展 → _unstick() 在 8 方向 × 半径 12/24/36/48 螺旋搜索 position_free 点，强制迁移并清空路径重寻——保证任何情况都不会永久卡住

**Bug 2「末格冻结（别人到了我就停）」→ 修复 ②④ + 编队落点滑动**
- ② 末段直达：move_towards 中路径为空且与终点同导航格时，不再直接 return，而是 move_toward(destination) 直线走完剩余距离（每步 position_free 校验；终点本身被挡则配合②的滑动已变为可达点）
- ④ 编队落点滑动：command() 的 move 分支在生成 offset 目标后，若 position_free 失败则朝下令单位每次回拉 8px（≤24 次）直至可达——从源头消灭"终点无法追加进路径"的前提

**两 Bug 共用**：③ 兜底同时覆盖两类残余死锁（群挤/边角），是最终保险

### 验证
- gameplay 新增 2 用例（57 checks）：6 士兵绕角 900 tick 内全员 idle；目标点在岩石内仍 3 tick 完成且距点击 65px
- 实机复现用户场景：绕角小队 102 tick 全员到达、0 卡死；岩石内目标 3 tick 到达
- 回归 5 套全过；导出 EXE（23:14:18，期间结束旧版进程 PID 140420 解除文件锁）

## 2026-09-21：虚假重复按下重置框选（用户报告 #3）

### Bug（确认属实）
- 现象：从画面左上按住左键向右下框选时，框中途消失并从当前鼠标位置重新开始——用户全程未松开
- 根因：selection_start 仅在 _unhandled_input 按下分支写入；Windows 输入栈（鼠标受限/原始输入）会注入虚假的重复 WM_LBUTTONDOWN，被无条件接受 → 拖动起点被重置到当前光标 → 旧框变零尺寸"消失"、新框从光标处重新生长

### 修复方法（与 Bug 配对）
- 新增 last_mouse_event_msec 时间戳：_input 收到任意鼠标移动/左键事件时更新
- _input 按下处理新增守卫：按下时若 selection_dragging 且 left_button_held（单键不可能合法二次按下）：
  - 距上次鼠标输入 <1500ms → 判定虚假重复按下，set_input_as_handled 吞噬并返回（_unhandled_input 不会收到，起点保持）
  - ≥1500ms → 判定释放事件已丢失的陈旧拖动：先 _finish_drag_select(selection_current) 完成旧框，再放行本次按下开启新拖动

### 验证
- presentation 新增回归：重复按下后 selection_start 不变且原框完成选择（2 单位）；陈旧拖动（2000ms 无输入）从新按下重启且旧框先完成（6 单位）
- 实机复现用户场景：注入重复按下后起点保持 (560,240)、拖选存活、释放后按原框选出 2 单位
- 回归 5 套全过（gameplay 57 / presentation 含 4 条拖选用例）；导出 EXE（00:15:20）

## 2026-09-21：建筑同类多选 + 分布式生产 + SC2 式编队 UI

### 新增功能
#### 1. 建筑双击同类全选 + 生产分布
- 双击建筑 → 选中屏幕内全部同类建筑（新增 selected_buildings 多选数组，与单选 selected_building 兼容共存）
- 多选生产建筑时下达生产：按"最短队列优先"在已选建筑间轮转分配（4 单 → 2+2 实测）
- 右键集结点批量应用到全部已选建筑
- 编队支持建筑列表（存储 buildings 数组，召回恢复多选；直接设 selected_building 的旧路径有回退兼容）

#### 2. SC2 式编队卡 + 兵种 Tab 功能区
- 状态栏上方新增 9 张编队卡：编号 + 首单位名（空组半透明），点击即召回
- 多单位选中时状态栏显示完整名册（"GROUP 2 SOLDIER + 1 HARVESTER"）
- 混编队伍功能区按兵种分页：显示当前兵种的操作（士兵=STOP/MOVE/ATTACK，矿车=STOP/MOVE/GATHER），状态栏提示 "TAB: SOLDIER (1/2)"
- Tab 键循环切换兵种页

### 验证
- features 新增 4 组用例：双击同类全选、4 单 2+2 分布、混编 Tab 切换（ATTACK↔GATHER）、编队卡显示与点击召回
- 实机六项全过：2 建筑全选 / [2,2] 队列 / "2 x BARRACKS" 标签 / "1: SOLDIER" 卡 / GROUP 名册 / Tab 切换
- 回归 5 套全过；导出 EXE（00:53:26）

## 2026-09-21：多建筑全高亮 + 逐建筑 Tab 详情页

### 改进
- 双击同类全选后，_draw 高亮条件由 selected_building==id 改为 selected_buildings.has(id) or selected_building==id——全部已选建筑同时显示黄框/集结点/地堡射程
- 多建筑选择时 Tab 切换 building_tab_index：状态栏显示 "2 x BARRACKS [i/n]"，功能区、生产进度条、队列文本、取消按钮全部跟随当前 Tab 页建筑；取消精确作用于 Tab 页建筑
- 单建筑/单位选择行为不变（单位混编 Tab 仍切兵种页）

### 验证
- features 回归：多选后首页显示第一建筑（空队列）、Tab 后显示第二建筑（SOLDIER 2%）、取消作用于 Tab 页建筑
- 实机：双击两兵营均选中，Tab [1/2]→[2/2]，进度条 空→可见，队列 QUEUE EMPTY→QUEUE(1/5) Now SOLDIER 2%
- 回归 5 套全过；导出 EXE（01:01:25）

## 2026-09-21：功能区改为 SC2 式同卡共存

### 改进（用户选择"同卡共存"方案）
- 旧交互：混编队伍按 Tab 整卡切换兵种功能页（STOP/MOVE/ATTACK ↔ STOP/MOVE/GATHER）
- 新交互（SC2 命令卡式）：通用命令槽位固定——[0] STOP、[1] MOVE；兵种专属命令各占一槽——[2] ATTACK（含士兵时启用，含 ON 态）、[3] GATHER（含矿车时启用）；四键同屏、各自只对可执行兵种生效（模拟层按类型过滤），无需 Tab
- 移除单位 Tab 分页与 action_type_index/_selected_unit_types；Tab 仅保留多建筑详情页切换
- 命令派发固定：0=停止、1=移动待定、2=攻击模式、3=采集待定

### 验证
- features 回归改写：混编时 ATTACK+GATHER 同时启用；纯士兵 GATHER 禁用；纯矿车 ATTACK 禁用
- 实机三态验证：混编四键全开 / 纯士兵 GATHER 禁 / 纯矿车 ATTACK 禁
- 回归 5 套全过；导出 EXE（01:18:14）

## 2026-09-21：状态栏三区化（地图/状态/指令）

### 结构
- 底部命令栏重构为命名分区（bottom_zones 注册表 + _add_bottom_zone 构建函数，未来新区直接插入无需改动布局）：
  - 左：MAP 地图区——预留 220x96 占位（小地图未实现，暂无内容）
  - 中：STATUS 状态区——选中名册 + 生产进度/队列，水平扩展填充剩余宽度
  - 右：COMMAND 指令区——SC2 式命令卡（caption 标注）

### 验证
- presentation 新增断言：三区存在且地图区预留 ≥200px
- 实机：顺序 map(12,220) → status(244,1232 扩展) → command(1488,420)，按钮网格位于指令区内
- 回归 5 套全过；导出 EXE（18:13:41）

## 2026-09-21：单位缩略图系统（占位字 → 未来图片）

### 设计
- UNIT_THUMBNAILS 映射：soldier→兵、harvester→矿（占位中文字符；用户提供图片后只需改 _make_unit_thumbnail 为 icon 贴图）
- _make_unit_thumbnail(kind, caption, size) 工厂：Button 图标 + 可选角标（数量/进度）；SystemFont（雅黑/黑体回退）保证中文渲染

### 应用
- 状态区名册：多选/单选均按兵种渲染缩略图块（兵 ×2 / 矿 ×1），替代原文字名册；多选时 selection_label 仅保留 "GROUP"
- 生产队列：每个排队单位一枚缩略图，首个带进度百分比角标（如 2%），保留进度条与小号 "QUEUE n / 5" 表头；多建筑 Tab 页显示该建筑队列
- _clear_container 立即释放旧块，刷新无残留

### 验证
- features 断言：混编名册 2 块、分布后队列 2 块、单 job 队列 1 块
- 实机：名册 [兵 x2][矿 x1]，队列 3×兵（首个 2%），进度条可见
- 回归 5 套全过；导出 EXE（18:44:59）

## 2026-09-21：建造队列固定锚点居中化

### 改进
- 状态区内部顺序调整为：名册（定宽 260）→ 生产队列（定宽 240 五槽）→ 文字（弹性填充）——队列从右缘移到中部偏左，位置更居中
- 名册与队列条均定宽：无论选几个兵种、排几个单位，队列条起点恒定，第 i 个任务的渲染 x 恒定（不随队列长度漂移）

### 验证
- 实机：1 个任务与 3 个任务时首图标 x 均=516；第 3 图标 x=604（固定槽距）；条宽恒 240
- 回归 5 套全过；导出 EXE（20:17:02）

## 2026-09-21：2D-v0.1 里程碑标签

- 推送 9 个提交（ae6497b→c05fe0f，含最终 2D EXE 109MB LFS 对象）
- 附注标签 **2D-v0.1** 指向 c05fe0f：3D 重写前完整 2D 版本（地图×10、9 矿、AI 小队、SC2 式命令卡/编队卡、三区状态栏、缩略图系统、全部修复与 57 项 gameplay 回归）
- 此里程碑后进入饥荒式 3D 表现层重写

## 2026-09-21：饥荒式 3D 表现层重写（首版可玩）

### 架构变更
- 场景根 Node2D → Node3D（main.tscn + main.gd）
- Camera2D → Camera3D：透视投影，固定偏航 0°/俯角 33°/FOV 50，焦距=650/zoom_level
- CameraController 重写为 3D：focus(Vector2 地面坐标)驱动相机位置，_visible_ground_rect() 用四角射线求地面可见范围
- 地形：TileMapLayer → 4 块 2400×1600 烘焙贴图平面（视觉与 2D 一致）
- 迷雾：1.5 万个 draw_rect → 单张 150×100 alpha 纹理平面（nearest 采样）
- 实体：_draw() 即时绘制 → _sync_visuals() 标记-清扫管理 Sprite3D 广告牌（units/buildings/ores/rocks）
- 覆盖层：选框/点击标记/建造预览 → 贴地 PlaneMesh + Sprite3D
- 输入：get_global_transform_with_canvas → _screen_to_world（射线∩y=0 平面）+ _world_to_screen（unproject）
- 模拟层 simulation.gd、HUD CanvasLayer、全部玩法逻辑零改动

### 已验证
- gameplay 57/0、features 0、action_bar 0、camera 3D 版 0——4 套通过
- 实机：3D 场景渲染正常（地形/迷雾/单位/建筑），左键选择 [3]，右键移动 idle→move
- EXE 导出（22:03:22）

### 已知待办
- presentation 测试需 3D 坐标全面适配（当前 headless 下超时，事件坐标与 3D 投影不匹配）
- 特效/血条/进度条/名册缩略图为占位实现（Sprite3D 无纹理），后续迭代
- 建造预览/集结点/地堡射程等 overlay 的视觉细节待打磨

## 2026-09-22：Blender 3D 实体模型替换像素贴图
### 实现
- 新增 assets/models/source/ironfront_models.blend 与 8 个独立 GLB：soldier、harvester、base、barracks、refinery、bunker、ore、rock。
- 新增 EntityVisual：统一缩放、底部落地、阵营材质实例、受击/施工染色、朝向平滑和 AnimationPlayer 状态动画。
- main.gd 的单位/建筑/矿石/岩石/建筑预览改为 Node3D 模型；新增战场阳光与环境光，地面接受光照和阴影。
- 保持模拟、网络协议、选择判定、迷雾规则和 HUD 交互不变。

### Bug 与修复（成对记录）
- 症状：headless 注入路径中重复鼠标按下会重启框选。根因：_input 与 _unhandled_input 接收子集不一致，left_button_held / motion 时间戳不完整。修复：_unhandled_input 幂等维护按钮状态与 motion 时间戳，并在重复按下时保留原框选。验证：presentation.gd 0 failures。
- 症状：协议不兼容/观战阶段日志大量 PackedByteArray 越界。根因：local_slot=0 时 explored 数组不存在，岩石可见性仍直接索引。修复：取得 explored 后检查 size，无数据或索引越界时隐藏岩石。验证：多进程网络测试不再出现越界。
- 症状：网络 guest 建成兵营后无法生产士兵。根因：测试直接设置 selected_building，但 _clean_selection 因 selected_buildings 为空将其清空。修复：合法单选自动同步到 selected_buildings。验证：guest queue=1、units 达到 14 并继续完成攻击/胜利流程。
- 症状：round2 重开测试永久等待移动。根因：红方 guest 固定命令蓝方单位 6，被主机权限校验拒绝。修复：重开后动态选择第一个红方单位，并在近距目标验证移动与冻结快照。验证：round2 快照一致和主机退出处理 PASS。

### 验证
- visual_models / gameplay(57 checks) / features / camera / action_bar / presentation：全部 0 failures。
- 多进程 ENet：协议不匹配拒绝、观战权限、红方经济/建造/生产/攻击/胜利、两轮完整快照一致、重开与主机退出处理全部 PASS。
- SOLO 实机截图：build/verification/visual_models.png；战场区域绿色地面约 67%，机械灰约 11%，迷雾/阴影约 14%，存在蓝色阵营与黄色矿石像素。

## 2026-09-23：3D 分支审查修正
### Bug 与修复（成对记录）
- 症状：采集车 cargo=0 后货物条仍显示背景。根因：仅把填充宽度置 0，holder 未隐藏。修复：cargo>0 显示 holder，cargo=0 隐藏 holder。验证：visual_models 断言空货物条不可见。
- 症状：士兵追击远目标时播放 attack。根因：动画状态只看 order。修复：按单位/建筑边缘距离判断射程，未进入射程播放 move。验证：远/近目标两组动画断言。
- 症状：主机与客户端岩石装饰位置可能不同。根因：使用进程随机数。修复：基于障碍/行列索引字符串哈希生成 jitter 与 scale。验证：重建岩石后 transform 完全一致。
- 症状：180 单位仅约 6 FPS。根因：每实体重复材质刷新/动画库、模型碎片多、单位阴影多、O(N²) 单位分离。修复：状态早退、共享动画库、静态网格合并、LOD/阴影策略、空间哈希分离。验证：约 98 FPS、1106 draw calls。
- 症状：删除 GLB 抽取贴图后 Godot 重新生成。根因：glTF embedded_image_handling=1。修复：改为 0 保留内嵌资源并删除派生 PNG。验证：视觉/性能测试与导出运行通过。


## 2026-09-23：施工动画与单位朝向修正
### Bug 与修复（成对记录）
- 症状：施工动画 1.5 秒循环，而兵营/精炼厂/地堡/基地分别需要 4/5/6/7 秒，导致动画重复且与进度条不同步。根因：动画固定时长且 LOOP_LINEAR。修复：construction 归一化为 1 秒 LOOP_NONE，由 set_construction_progress(progress, duration) 按 Simulation 建造时长设置 speed_scale 并 seek 当前比例；基地也补齐施工动画。验证：visual_models 覆盖四种建筑时长与 50% 快照进度，核心七套测试通过。
- 症状：士兵背对前进方向。根因：模型正面为局部 -Z，旧 set_heading 使用 +Z 计算 atan2。修复：改为 atan2(-heading.x, -heading.y)。验证：士兵东南西北和采集车斜向朝向断言全部通过，实机运行初始采样确认。

## 2026-09-23：士兵可见正面攻击朝向修正

### Bug 与修复（成对记录）
- 症状：士兵攻击建筑时身体背对目标。根因：旧实现把士兵和采集车统一按局部 -Z 当正面；实际士兵身体正面是局部 +Z，采集车钻头才是 -Z，而旧的自动化测试只验证了假设的 -Z 基向量，没有验证可见身体正面。修复：`EntityVisual` 按模型解析正面轴（soldier=+Z、harvester=-Z），并把 Blender 源文件及导出的 soldier GLB 中 Weapon/Muzzle 移到局部 +Z，身体和枪口同向。验证：visual_models 覆盖东南西北、真实建筑攻击方向、身体正面与枪口方向，failures=[]；实机 MCP 攻击探针 body-forward·target=0.99999994、muzzle·target=0.8137319。
- 症状：camera 回归偶尔在本机报 “default camera speed is not the faster 1.4x”。根因：测试读取启动值，受 `user://settings.cfg` 中玩家持久化速度影响。修复：测试先显式应用 1.8x 再断言，避免依赖本机配置。验证：camera 单独回归 failures=[]。

### 验证
- 核心回归：visual_models、visual_performance、gameplay(57 checks/0 failures)、features、camera、action_bar、presentation 全部 failures=[]；同批串行运行时 camera 在输出 failures=[] 后遇到一次 Godot headless 关闭崩溃，单独复跑退出码 0，不影响游戏判定。
- 多人回归：协议不匹配拒绝、观战权限、红方采矿/建造/生产/攻击/胜利、两轮完整快照一致、重开与主机退出处理全部 PASS。
- 实机截图：`build/verification/soldier_attack_facing_fixed.png`。
- 导出：`build/IronFront.exe`，109,693,864 bytes，时间 2026-09-23 20:51:16，SHA256 `A6C302D03A0BEF09EBB9C54A1208DFEA7F20B0DA595EA9A58B349FCC0A0B369D`；导出后 headless 180 帧与真实渲染 300 帧进程退出码均为 0。

## 2026-09-23：高科技人类阵营兵营效果图
- 生成基础：从 `assets/models/source/ironfront_models.blend` 单独渲染兵营 GLB，再用 Pillow 制作四张 1600x1000 概念图和一张总览图。
- 产物：`tools/effect-gallery/generated/00_contact_sheet.png`、`barracks_tech_blueprint.png`、`barracks_tech_night_ops.png`、`barracks_tech_modules.png`、`barracks_tech_combat_ready.png`。
- 页面：本地服务 `http://127.0.0.1:8765/` 已启动并用系统默认浏览器打开；可直接访问 `/generated/00_contact_sheet.png` 预览，或在页面用文件夹导入 `tools/effect-gallery/generated`。
- 限制：当前环境没有可用的内置浏览器控制接口；本批图为程序化概念图，不是 AI 生成图。若要 AI 生成风格，需要用户明确选择 CLI fallback 并配置 `OPENAI_API_KEY`。
- 验证：五个图片 URL 均 HTTP 200；`visual_models` 0 failures、`gameplay` 57/0；导出 `build/IronFront.exe` 后 headless 180 帧与真实渲染 300 帧均退出码 0。
- 补充验证限制：最后一次真实渲染 300 帧导出版进程在退出阶段出现一次间歇性 Windows access violation（`0xC0000005`），立即同参数复跑退出码 0；headless 180 帧退出码 0。本批改动仅涉及网页效果图资源与导出排除规则，未改游戏脚本。

## 2026-09-23：刷新不显示生成图片
- 症状：刷新效果图页面后主网格仍为空。根因：主网格只渲染 IndexedDB 记录；`tools/effect-gallery/generated/` 中的文件只是静态 HTTP 资源，刷新不会自动写入 IndexedDB。修复：页面新增“高科技人类阵营：兵营概念图”静态预览区，刷新即显示；新增“导入这组概念图”按钮，将服务器文件获取为 File 并写入现有图库。验证：HTMLParser 无未闭合标签，两个 inline script 通过 node --check，页面和五个图片 URL HTTP 200；导出后 headless 180 帧退出码 0，真实渲染 300 帧一次遇到已知间歇性关闭崩溃、同参数复跑退出码 0。

## 2026-09-24：效果图素材墙与垃圾桶
- 症状：图库原先的“删除”只删除浏览器 IndexedDB 记录，无法保留待恢复状态，也不能按用户要求在永久清除时删除文件系统图片。根因：页面使用纯静态 HTTP 服务，浏览器没有任意本地文件删除权限。修复：新增 `tools/effect-gallery/server.py`，普通导入保存到 `library/`，移除先移动到 `.trash/`，垃圾桶提供恢复和永久清除；IndexedDB 升级为独立 `trash` 对象仓库，生成目录图片也接入相同流程。验证：本地 API 完成导入→移入垃圾桶→恢复→再次移入→永久删除全生命周期测试，并拦截路径穿越。
- 症状：`start.ps1` 使用 `python` 时服务启动失败，Python 将脚本路径和参数视为一个字符串。根因：PowerShell `if` 表达式返回单元素数组后退化为字符串，`+=` 拼接了整条命令参数。修复：改为先创建空数组，再逐项追加 `-3`、脚本路径和服务参数。验证：PowerShell parser 通过，脚本在 18766 端口启动服务，页面/API 返回 200。

## 2026-09-24: human barracks concept-art generation
- Symptom: the gallery had no current generated human-barracks set after prior generated files were removed or moved to the recycle bin.
- Root cause: the gallery is file-backed for generated concepts, so it needs fresh project files in tools/effect-gallery/generated/.
- Fix: generated five new human-faction barracks concepts with the built-in imagegen workflow and copied stable PNGs into the generated directory.
- Verification: all five PNG files are present; /api/health and /api/generated return successfully; the gallery HTML contains the generated-concepts section.
- Build verification: fresh build/IronFront.exe export completed; tests/presentation.gd and tests/gameplay.gd exited 0; the exported EXE remained alive for the five-second headless smoke check.

## 2026-09-24: remove generated-concepts preview section
- Symptom: the gallery showed a dedicated “high-tech human faction barracks” panel that was not needed in the user's workflow.
- Root cause: the earlier gallery enhancement added a server-file preview area and import control for generated concepts.
- Fix: removed that section and its client-side generated-file discovery/rendering handlers; kept ordinary file/folder import and all gallery management features intact. The generated PNG files were not deleted.
- Verification: served HTML no longer contains the section or import button; inline scripts pass syntax checks; fresh EXE export, presentation test, gameplay test, and five-second exported-process check all passed.

## 2026-09-24: simplify gallery import copy
- Symptom: the uploader exposed browser-storage implementation details and a project-specific folder name.
- Root cause: the original copy described IndexedDB persistence and named `build/verification` even though the folder chooser accepts any directory.
- Fix: removed the persistence note, renamed the button to “选择图片文件夹”, and documented PNG/JPG/JPEG/WebP folder import in README.
- Verification: static page checks and script syntax checks follow; EXE/game verification was intentionally skipped per user instruction.

## 2026-09-24: extract world presentation from main runtime
### Bug and fix (paired record)
- Symptom: `scripts/main.gd` owned simulation orchestration, network callbacks, input, UI, audio, camera, and all 3D entity/fog/preview synchronization in one 1,900-line script, making presentation changes high-risk and difficult to test in isolation.
- Root cause: the 3D presentation subsystem had no independent owner; its state dictionaries and helper functions were embedded in the root gameplay node.
- Fix: added `scripts/world_visual_sync.gd` as a dedicated `Node3D` controller for rocks, ore, units, buildings, effects, selection overlays, build previews, status bars, animations, and fog. `main.gd` now creates/configures the controller and exposes temporary compatibility properties/wrappers for existing tests and callers.
- Verification: `--check-only`, `visual_models`, `gameplay` (57 checks), `presentation`, `features`, `visual_performance`, and the full ENet regression all passed. A fresh `build/IronFront.exe` export (110,191,584 bytes) launched and exited cleanly in the exported headless smoke run, and the non-headless render process remained alive for five seconds.

## 2026-09-25：快照边界校验与网络接收重构

### Bug 与修复（成对记录）

- 症状：`Simulation.apply_snapshot()` 直接接收远端字典，缺少字段、错误类型、越界坐标、过大表或不完整效果记录可能在后续 tick/渲染阶段触发错误；网络 RPC 也忽略了应用失败结果。根因：快照只有版本字符串和少量帧序判断，没有统一 schema 边界。修复：增加严格 `validate_snapshot()`，覆盖必需键、Variant 类型、枚举、坐标/计时器/资源上限、单位/建筑/矿石/效果/视野表大小；应用前验证并对所有表深拷贝；`NetworkSession` 与 main 兼容 wrapper 对匹配但损坏的包断开并提示原因，旧帧/错比赛包仍忽略。验证：`tests/gameplay.gd` 新增缺表、字符串强转、越界坐标、不完整效果、不完整视野、超量单位表回归，64 checks / 0 failures；完整 ENet 两次均通过。
- 症状：快照校验器初版用 `int(...)` 先转换再判断，字符串形式的数字可能绕过类型边界。根因：Variant 类型检查顺序错误。修复：所有整数/布尔/字符串字段先检查 `typeof`，再做范围转换；增加 owner="1" 负例。验证：gameplay 64/0。

### 验证

- 核心：gameplay 64/0；presentation、visual_models、features、camera、action_bar 全部 failures=[]。
- 性能：探针两次近阈值超 8ms（8.08645、8.1944），独立重跑两次通过（7.57705、7.2757）；未改变性能实现。
- 多人：协议不匹配、观战权限、两轮红方流程、快照一致、重连与主机断开全部 PASS。
- 导出：`build/IronFront.exe` 110,233,632 bytes，嵌入资源；`Start-Process` headless `--quit-after 180` ExitCode=0；真实渲染启动存活 5 秒后按计划停止。
