# Findings：coding style 全量整改（2026-09-19）

## 违规分布（整改前）
- scripts/main.gd：707 处（tab 缩进为主）
- scripts/simulation.gd：443 处
- tests/gameplay.gd：142 处；network_probe.gd：134 处；presentation.gd：92 处
- tests/network_guest.gd：18 处；assets/art/pixel_art.gd：33 处
- soldier/harvester entity：单行函数、缺空行、int=100、逗号无空格
- camera_controller.gd / barracks / base / building / combat / game_entity：基本合规

## 整改方式
- Node 脚本批量处理：tab→4空格、CRLF→LF、BOM 清除、逗号后加空格、
  赋值/比较运算符两侧加空格（字符串/注释感知）、行尾空白清理、
  文件尾单换行、函数定义前保证空行
- 两个 entity 小文件手工重写（拆分单行函数、补空行）

## 质量护栏
- 修复器的字符串切分器曾有一个 bug，污染了 gameplay.gd 的一个字符串
  （" checks; failures=" → " checks; failures ="）
- 通过 git HEAD 逐文件比对全部字符串字面量发现并已修复
- 最终校验：15/15 文件字符串与 HEAD 完全一致

## 验证
- gameplay.gd headless：47 checks; failures=[]，退出码 0
- presentation.gd headless：failures=[]，退出码 0
- 编辑器 filesystem scan：无脚本错误
- project_run 实机验证：菜单→SOLO 对局→AI 建兵营产兵（红方 600→130 消费、
  8 士兵+2 采集车），game log 无错误
- 导出模板 4.7.2 曾缺失，已从 %TEMP% 缓存安装到 AppData 后成功导出
- build/IronFront.exe：109,188,184 字节，2026-09-19 22:25，PCK 内嵌

# Findings：Blender 3D 模型替换（2026-09-22）
- 现项目无外部模型资源；8 类实体均由 `assets/art/pixel_art.gd` 动态生成纹理并经 `Sprite3D` 显示。
- 模拟状态足以驱动动画：士兵 idle/move/attack，采集车 move/mine/unload，建筑 construction/active/fire，不需要改协议。
- `main.gd` 视觉同步与选择逻辑解耦，替换 Node3D 表现层不会影响框选、点击或网络状态。
- Blender 当前连接可用，可执行 bpy 程序化建模与 glTF 导出。
- Blender 5.2 中文界面下 Principled 节点名称为本地化文本，必须按 `ShaderNodeBsdfPrincipled` 类型查找。
- 程序化 bmesh 细分比临时对象 + modifier_apply 更稳定。
- glTF 导出器可用 `use_selection=True + export_apply=True` 导出每个模型根及其子层级。
- EntityVisual 在运行时复制 StandardMaterial3D，避免不同阵营/受击状态污染共享 GLB 材质。
- 动画由 AnimationPlayer 动态库生成，直接引用 GLB 保留节点名（Leg_L、Drill、RadarDish 等）。
- presentation.gd 原本仍访问旧 2D 相机 camera.zoom，并要求反投影浮点坐标完全相等；已更新为 3D 相机状态和容差断言。
- 框选重复按下 bug：headless root.push_input 路径不一定完整经过 _input；在 _unhandled_input 幂等维护 left_button_held 与 last_mouse_event_msec 后修复。
- 实机画面确认：新 DirectionalLight + WorldEnvironment 后，战场截图不再全黑；模型、阵营色、矿石与迷雾同时存在。
- 协议握手失败/观战阶段 local_slot 可能为 0，视觉层必须容忍 explored 字典缺项。
- 网络测试的 50 秒 guest 等待对 3D 资产加载与完整经济流程偏紧；110 秒可稳定覆盖。
- round2 原测试固定移动单位 6（蓝方）却由红方 guest 下令，会被主机正确拒绝；应动态选择红方单位。

# Findings：本地效果图收藏网页（2026-09-22）
- 项目当前没有网页结构；现有效果图集中在 build/verification，包含 visual_models、demo_move、demo_build_preview、demo_build_construction 等 PNG。
- 用户确认：第一版做本地网页、本地上传、浏览器 IndexedDB 保存；后续可再静态部署。
- 采用零依赖单文件静态页面 + Python HTTP 本地启动脚本，避免引入 Node 或构建链。
- Windows PowerShell 5 的 Set-Content 管道会把部分中文字符写成损坏字节；网页内容经 Node UTF-8 读取确认正常，start.ps1 改为 ASCII，README 用 Node fs UTF-8 重写。
- 浏览器技能运行时初始化成功但 agent.browsers.list() 为空，因此本轮无法进行真实浏览器 UI 测试；已记录为验证限制。
- 静态页面通过 HTTP 200、Node 语法检查、HTML Parser 标签/ID 检查和 PowerShell Parser 检查。
- start.ps1 最终采用 ASCII 错误/提示文案，避免 Windows PowerShell 管道编码损坏；README 和页面保持 UTF-8。
- py 启动路径参数顺序已修正为 `py -3 -m http.server ...`；直接 python 路径保持 `python -m http.server ...`。
- 本地 HTTP 服务已停止，端口 8765 未占用。

# Findings：3D 分支审查（2026-09-23）
- 六套 headless 回归与完整 ENet 回归均通过。
- cargo=0 时货物条背景仍可见；确认是 `_update_status_bar(..., 0)` 只隐藏填充未隐藏 holder。
- 士兵 order=attack 时无论是否在射程内都播放 attack；追击阶段应播放 move。
- 岩石 jitter/scale 使用全局随机，多人客户端装饰布局可能不一致。
- 180 单位真实渲染压力探针：约 6 FPS、5440 draw calls、5653 render objects、0.218s/process；每个士兵复制 16 个材质，动画库逐实体构建。
- 8 张 `assets/models/*_IF_Steel_Metallic-IF_Steel_Roughness.png` 及 import 未被 GLB 导入场景引用，可删除。
- Blender 静态网格合并后，8 个模型的可渲染 Mesh 对象从 123 降到 76；单位关闭阴影并对远距小件使用 1400 单位 visibility range。
- Godot glTF `embedded_image_handling=1` 会持续从 GLB 抽取金属/粗糙贴图；改为 0 后可删除 8 张重复 PNG，测试仍通过。
- 180 单位真实渲染优化后约 98 FPS、1106 draw calls、0.0254s/process；优化前约 6 FPS、5440 draw calls、0.218s/process。
- 剩余性能瓶颈曾位于 simulation：O(N²) 分离循环。改为 64px 空间哈希并 3 次迭代后，逻辑 tick 从约 61ms 降到约 14ms。


# Findings：施工动画与单位朝向修正（2026-09-23）
- 建筑真实时长：兵营 4 秒、精炼厂 5 秒、地堡 6 秒、基地 7 秒；此前施工动画固定 1.5 秒且循环。
- 导出后的士兵正面位于局部 -Z：Weapon z=-0.52、Muzzle z=-0.98；采集车钻头同样位于局部 -Z。
- 旧朝向公式把 +Z 当正面，导致模型背对前进方向；正确公式为 atan2(-heading.x, -heading.y)。
- 施工动画改为归一化 1 秒、LOOP_NONE，并通过 AnimationPlayer speed_scale 与 seek 精确映射模拟进度。

## Soldier facing correction investigation (2026-09-23)

- The prior test only asserted Godot's generic local -Z basis and muzzle node position. It did not establish which side of the soldier mesh is the visible face, so it could pass while the body faced away.
- Blender source inspection: the soldier's faction glow and original weapon/muzzle sit at Blender +Y, which exports to Godot local -Z. The visible soldier front is Blender -Y / Godot +Z. The harvester drill is genuinely Blender +Y / Godot -Z.
- Correct design: use a per-model forward axis (soldier +Z, harvester -Z), and place the soldier weapon/muzzle on +Z so body and rifle both face the target.

## Effect-gallery generation request (2026-09-23)
- The gallery is intentionally a collection/import page, not an AI or procedural generator.
- Browser runtime discovery returned no available browser, so the page cannot be remotely opened in this session. The local server can still be prepared and the URL reported.
- Generated five local preview assets from the actual barracks GLB: one contact sheet plus blueprint, night-ops, module-family, and combat-ready variants. These are procedural concept overlays, not AI-generated images.
- The generated files are served by the gallery server under `/generated/`; `tools/*` was added to the export exclude filter so the web-gallery assets do not inflate the game PCK.

## Refresh behavior finding (2026-09-23)
- The main gallery grid intentionally renders only records in IndexedDB. Files placed under `tools/effect-gallery/generated/` are served by HTTP but are not automatically inserted into IndexedDB, so refreshing the page leaves the main grid empty unless the user imports them.
- The updated page now has a dedicated generated-concepts section that renders server files on every refresh, independent of IndexedDB. The new import button fetches those files and stores them as normal gallery records.
