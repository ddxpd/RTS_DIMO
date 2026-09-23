# Progress：coding style 全量整改（2026-09-19）

- [x] 读取规范与全量扫描（160 个 .gd，自有 15 个，插件 145 个排除）
- [x] 批量整改 13 个文件 + 手工重写 2 个 entity 文件
- [x] 字符串完整性比对（发现并修复 1 处污染）
- [x] 风格复审：15/15 零违规
- [x] 编辑器扫描 + gameplay(47/0) + presentation(0 failures)
- [x] 实机运行验证（SOLO 对局 + AI 行为）
- [x] 安装导出模板并重新导出 EXE
- [x] 记录归档：task_plan.md / findings.md / progress.md

状态：完成

# Progress：等号对齐规则（2026-09-19 追加）

- [x] agent_md/AGENTS.md 新增指导：连续赋值左侧长度相近（差异约 <=9 字符）时对齐 = 号；个别特别长或导致过长的行不强制
- [x] 全量扫描 15 个自有脚本，识别 40+ 连续赋值块
- [x] 对齐 26 个块（main.gd 16 处、simulation.gd 6 处、game_entity.gd 1 处、tests 6 处）；差异过大的块跳过
- [x] 验证：字符串 15/15 与 HEAD 一致；风格审计通过；gameplay 47/0、presentation 0 failures
- [x] 重新导出 EXE（22:34:44）并启动游戏验证无错误

状态：完成

# Progress：底部操作栏可点击化（2026-09-19 追加）

## 实现
- [x] 修复 _refresh_ui 顺序 bug：原来单位分支设置按钮后又被整体重置为"—"，选中单位永远看不到操作
- [x] 16 个操作按钮连接 pressed 信号到 _action_clicked(index)
- [x] 标签改为括号快捷键格式：STOP (S) / MOVE (RMB) / ATTACK (A) / GATHER (RMB)、
      SOLDIER ($100) / HARVESTER ($200) / BARRACKS (B) / BASE ($500) / CANCEL (Refund)
- [x] 新增待定命令模式：点 MOVE/GATHER 后左键点地图/矿脉下发指令；Esc/右键取消
- [x] 建筑按钮：生产、建造、取消队列全部可点
- [x] 修复按钮信号被吞 bug：每帧整体 disabled 切换会清掉 Button 按下状态，改为只重置未用槽位
- [x] 顺手修复两处 UI 字符串乱码（鈥? → —）

## 验证
- [x] 新增 tests/action_bar.gd headless 测试：标签/启用状态/MOVE 待定流程/STOP 生效 全部通过
- [x] gameplay 47/0、presentation 0 failures 回归通过
- [x] 实机运行：选中士兵显示 STOP (S) / MOVE (RMB) / ATTACK (A)，截图确认
- [x] 导出 build/IronFront.exe（22:49:03）

状态：完成

# Progress：RTS 操作增强四件套（2026-09-19 追加）

- [x] 双击同类全屏选择（0.4s 判定 + 相机视野矩形）
- [x] 底部生产进度条 + 队列显示（HBox 重构）
- [x] 编队 Ctrl/Shift/数字 召回（1-9 组，死亡单位自动过滤）
- [x] 建筑集结点：右键设置、网格吸附、新单位自动移动、选中时绘制标记
- [x] tests/features.gd 全过 + 全套回归 + 实机验证 + EXE 导出
- [x] 开发日志 agent_md/dev_log.md 建立

状态：完成

# Progress：Blender 3D 模型替换（2026-09-22）
- [x] 确认现有视觉架构、模拟状态与测试耦合点
- [x] 确认美术决策：务实写实机械风、实体+资源替换、状态动画、机械灰+阵营色、清晰战场光
- [ ] Blender 源资产与 GLB 导出
状态：进行中
- [x] 生成并保存 assets/models/source/ironfront_models.blend：8 模型 / 142 对象 / 128 网格 / 11 材质
- [x] 导出 soldier、harvester、base、barracks、refinery、bunker、ore、rock 独立 GLB
- 遇到并解决：Blender MCP 禁止 read_factory_settings、Principled 节点本地化命名、修改器上下文、构建器参数签名混用、旧版 glTF 参数 export_colors
状态：Blender 资产阶段完成，准备 Godot 导入
- [x] Godot 导入 8 个 GLB；新增 EntityVisual 统一模型缩放、阵营材质、受击/施工染色、朝向与状态动画
- [x] main.gd 替换单位/建筑/矿石/岩石视觉、建筑预览，并新增战场阳光与环境光
- [x] 新增 tests/visual_models.gd：模型/动画/施工/生产/开火/资源迷雾/预览全通过
- [x] 回归 visual_models / gameplay / features / camera / action_bar / presentation 全部 0 failures
- [x] 修复并记录：重复按下在 headless 注入路径可能重启框选；_unhandled_input 同步维护按钮状态和 motion 时间戳
状态：Godot 表现层与回归测试完成，进入实机验证
- [x] 实机 SOLO 启动并保存 1920x1080 战场截图；像素统计确认绿色地面约 67%、机械灰约 11%、迷雾/阴影约 14%，存在蓝色阵营与黄色矿石像素
- [x] 完整多进程网络验证通过：协议不匹配拒绝、观战权限、红方采矿/建造/生产/攻击/胜利、两轮快照一致、重开与主机退出处理
- [x] 修复迷雾边界 bug：local_slot 无 explored 数组时岩石直接隐藏，避免空数组越界
- [x] 修复建筑单选 bug：直接设置合法 selected_building 时自动同步 selected_buildings，生产回调不再被清理
- [x] 修复网络测试假设：round2 动态选择红方单位并用近距目标验证重开后命令与冻结快照
状态：实机与联机验证完成，待最终回归/导出
- [x] 移除临时截图/重置热键；保留 build/verification/visual_models.png 作为实机证据
- [x] 全套回归最终结果：visual_models=0、gameplay=57/0、features=0、camera=0、action_bar=0、presentation=0
- [x] 导出 build/IronFront.exe：111,121,248 字节（PCK 内嵌）
- [x] 导出版 headless 冒烟：退出码 0，无游戏脚本错误
- [x] 导出版真实渲染进程运行 5 秒存活后自动关闭：alive_after_5s=true
状态：完成

# Progress：本地效果图收藏网页（2026-09-22）
- [x] 确认现有网页为空、效果图位置与用户交付偏好
状态：进行中
- [x] 遇到 Windows CreateProcess 206 命令长度限制；改为分块写入静态页面
- [x] 新增 tools/effect-gallery/index.html：两个标签、上传/拖拽/文件夹导入、IndexedDB、搜索排序、卡片、预览、下载、删除、清空
- [x] 新增 tools/effect-gallery/start.ps1 与 README.md；启动脚本支持 python/py、自动空闲端口、静态服务和打开浏览器
- [x] 修复一次 PowerShell 写入导致的 start.ps1/README 中文编码损坏；start.ps1 改为 ASCII，README 用 UTF-8 重写
- [x] 修复 py launcher 参数顺序问题：-3 必须位于 -m http.server 之前
- [x] 静态验证：HTML 标签/doctype/重复 ID 检查通过；2 个 script 块 node --check 通过；start.ps1 Parser 通过；HTTP 200
状态：页面实现完成；浏览器控制通道不可用，待项目回归与导出
- [x] HTTP 验证：本地静态服务返回 200，页面 23,420 bytes
- [x] HTML Parser：doctype、标签闭合、重复 ID 检查通过
- [x] Node --check：2 个脚本块语法通过
- [x] PowerShell Parser：start.ps1 语法通过，python/py 参数顺序正确
- [x] Godot 回归：visual_models/gameplay/features/camera/action_bar/presentation 全部退出码 0
- [x] 导出 build/IronFront.exe：111,121,248 bytes，时间 2026-09-22 12:32:16
- [x] 导出版 headless 冒烟退出码 0；真实渲染进程 5 秒存活后关闭
- [!] 真实浏览器 UI 测试限制：Browser runtime 可初始化但浏览器列表为空
状态：实现完成，待提交
- [x] 本地提交完成：70708b2 Add local effect image gallery
状态：完成

# Progress：3D 分支审查修正（2026-09-23）
- [x] 完成当前分支静态审查、六套核心回归、完整 ENet 回归和 180 单位压力探针
- [x] 清理审查测试触碰的 import/log 状态与临时性能探针
状态：进行中
- [x] 修复空 cargo 背景条、追击/开火动画状态、guest 渲染速度回退和岩石确定性
- [x] EntityVisual 增加状态早退、共享动画库、LOD/阴影策略；隐藏实体暂停 AnimationPlayer
- [x] 合并 Blender 静态网格并重导 8 个 GLB；删除 8 张重复抽取贴图
- [x] simulation 单位分离改为空间哈希；寻路重算间隔按目标哈希错峰
- [x] 核心七套测试全部通过；完整多进程 ENet 回归两轮全部 PASS
- [x] 180 单位真实渲染：约 98 FPS、1106 draw calls、0.0254s/process
- [x] 导出临时 build/IronFront3D-review.exe：109719480 bytes；headless 0，真实渲染 5 秒存活
状态：最终记录中
- [x] 最终复跑：核心七套退出码 0；完整 ENet 回归两轮快照一致全部 PASS
状态：完成


# Progress：施工动画与单位朝向修正（2026-09-23）
- [x] construction 动画改为一次性播放，速度匹配 4/5/6/7 秒真实建造时间
- [x] 基地新增施工动画；guest 中途加入按 remaining 进度 seek
- [x] 士兵与采集车正面 -Z 朝向运动/目标方向
- [x] visual_models 覆盖东南西北和四种建筑时长/50% 进度
- [x] 核心七套测试全部退出码 0；完整 ENet 回归全部 PASS
- [x] 临时 EXE：109720184 bytes，SHA256 AA0E0C873C84A22FCBC1EB0C29F290D38C46DC89AF9E165C9ADBAF9F43AEE316；headless 0，真实渲染 5 秒存活
状态：完成
