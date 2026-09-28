# 开发历史

本文件保存已完成工作的压缩记录。当前待办只写入 [task_plan.md](task_plan.md)；验证数字集中在 [VERIFICATION.md](VERIFICATION.md)。

## 2026-09-29：删除效果图库

- 删除开发期本地素材图库、全部跟踪概念图、本地导入/垃圾桶数据和三个图库专用生成脚本。
- 移除 `run-mcp.ps1` 的 `gallery` 动作、8765 端口清理、忽略规则和活动文档入口；游戏运行时与 Blender MCP 不受影响。

## 2026-09-29：移除统一 Python 工具入口

- 删除 `project_tools.py`、共享运行时和专用依赖声明，恢复 Godot、Blender、ENet、MCP、导出检查、清理与图库的 PowerShell wrappers。
- 恢复固定 wrapper 的 Codex allowlist 和 ExecutionPolicy 规则；没有放宽任意 PowerShell、Python、Godot 或 Blender 调用。
- 保留风险分级验证政策和独立业务 Python 工具；PowerShell 语法、权限自检、工具版本、execpolicy、进程/端口及残留引用检查通过。

## 2026-09-28：PowerShell 弹窗治理

- 症状：执行开发和验证任务时出现大量 PowerShell 控制台窗口，联机回归还存在 PowerShell 再启动 PowerShell 的套用。
- 根因：`run-network.ps1` 为 `.ps1` runner 创建了第二个 `powershell.exe`；`godot_ai` 的端口和进程身份查询反复通过 `OS.execute()` 调用 PowerShell，却没有在命令参数和 Godot 调用层同时固定无窗口模式；图库为延迟打开浏览器额外启动了 PowerShell。
- 修复：联机 runner 改为当前 runspace 直接执行；插件统一增加 `-NonInteractive -WindowStyle Hidden` 并显式传递 `open_console=false`；图库把浏览器延迟打开移入 `server.py`；新增固定 `regression` 动作，将八项常规测试收敛到一个可信 wrapper 入口。
- 验证：PowerShell Parser、工具回归、八项批量 Godot 回归、完整 ENet、图库 `/api/health`、wrapper 权限自检、Windows 重新导出和 5 秒 EXE 冒烟运行全部通过；最终项目进程和端口为空。execpolicy CLI 子检查因当前 `PATH` 无 `codex` 被跳过。

## 2026-09-19：操作栏与编码规范

- 完成编码风格全量整改：缩进、空格、函数空行、文件换行和字符串一致性。
- 重做底部状态栏、生产队列、编队、集结点和按钮命令模式。
- 验证：核心 gameplay/presentation 回归、SOLO 和 Windows 导出通过。

## 2026-09-20：经济、镜头和输入

- 加入矿场、矿车自动采矿、资源扣除/退款、建筑过滤和镜头设置。
- 修复窗口边缘滚动、鼠标锁定、拖选被 HUD 打断、丢失释放事件和重复按下重置拖选。
- 修复编队绕角卡死、末格冻结、矿车对撞死锁；为每项保留回归测试。
- 验证：gameplay、camera、presentation 和实机 SOLO/联机流程通过。

## 2026-09-21：UI 与 3D 首版

- 完成多建筑选择、SC2 风格状态栏、单位卡、生产队列和 3D 表现层首版。
- 规则文档与操作说明建立；视觉同步仍由 `main.gd` 负责。

## 2026-09-22：Blender 模型与图库

- 将单位、建筑、矿石和岩石从像素 Sprite3D 替换为 Blender/GLB 模型；加入状态动画、阵营颜色、光照和建筑预览。
- 建立本地效果图库：IndexedDB、上传、缩略图、收藏、搜索、排序、下载和删除。
- 已知限制：真实浏览器控制通道不可用，因此图库使用静态 HTML/API 验证。

## 2026-09-23：视觉性能与朝向

- 合并静态网格、缓存材质/动画库、清理重复贴图、降低远景阴影和 draw calls。
- 建筑施工动画改为真实建造时长；士兵和矿车按模型前轴修正朝向；补充四方向和攻击朝向回归。
- Bug 修复：士兵外观背向目标。根因是把 +Z 误当作所有模型的正面；修复为按模型选择前轴，并验证武器/枪口与目标一致。
- Bug 修复：地堡正面朝向错误。根因是 Blender 结构与 Godot -Z 约定不一致；修正前板、炮塔和 recoil 轨道，并通过层级/动画断言。

## 2026-09-24：图库生命周期与运行时拆分

- 图库普通导入保存到 `library/`，移入 `.trash/` 后可恢复或永久删除；服务端拦截路径穿越。
- 生成概念图预览曾加入，后按需求移除可见预览区，保留普通图库流程。
- 从 `main.gd` 提取 `WorldVisualSync`、`GameSession`、`CommandBus`、`NetworkSession`、`InputController`、`HudController` 和 `AudioController`。
- Bug 修复：HUD 提取初版遗留旧 wrapper/编码占位文本；重建 controller、路由刷新和构造流程，保留临时兼容入口。

## 2026-09-25：快照边界

- 为快照增加顶层键、版本、Variant 类型、实体字段、位置/计时器、队列、效果、资金、视野、表大小和范围校验。
- `apply_snapshot()` 仅在完整验证后深拷贝写入；非法网络状态会拒绝、断开并提示，旧版本包仍按协议忽略。
- 新增 malformed snapshot 回归；gameplay 64/0，核心视觉和 ENet 回归通过，导出进程检查通过。

## 2026-09-25：Esc 菜单输入修复

- 症状：游戏中按 `Esc` 无法稳定打开菜单；在攻击键重绑界面按 `Esc` 后，后续按键仍可能被当作重绑输入。
- 根因：快捷键只在 `_unhandled_input` 阶段处理，HUD 控件可能先消费事件；重绑分支遇到 `Esc` 时没有清除 `rebinding_attack`。
- 修复：在 `InputController._input()` 先处理 Escape，并同时检查 `keycode`/`physical_keycode`；集中取消重绑、建造/待命令和菜单切换逻辑；保留 `_unhandled_input()` 兼容路径。
- 验证：`tests/presentation.gd` 新增菜单打开/关闭和重绑取消回归，脚本退出码 0；项目进程和端口清理完成。

## 2026-09-26：地堡模型替换与动画续作

- 完成：按 UUID 参考图重建低矮圆台单管地堡，替换 `assets/models/bunker.glb`，并只删除共享 Blender 源文件中的旧 `bunker` 层级，保留其他模型。
- 完成：新增 `BunkerBody`、单管 `Barrel`、`MuzzleFlash` 和左右 `FactionLight` 节点；Godot 运行时加入地下升起建造、炮管后坐/炮口闪光和炮塔预警巡查/灯带脉冲。
- Bug 修复：Blender 导出初次使用不兼容的 `export_selected_objects` 参数，导致 GLB 未生成；根因是 Blender 5.2.2 的 glTF operator 只接受 `use_selection`；修复为兼容参数并通过日志确认导出完成。
- Bug 修复：Godot 视觉测试仍加载旧 9 月 24 日导入缓存；根因是无界面脚本不会主动重建已删除的 `.godot/imported` 场景；修复 `run-godot.ps1 -Action import` 并强制重导入，视觉测试随后通过。
- Bug 修复：新 Body 根节点被共享场景中的士兵 `Body` 自动改名为 `Body_001`；根因是 Blender 对象名全局唯一；修复为 `BunkerBody` 并同步动画/测试路径，视觉测试随后通过。
- Bug 修复：导出游戏冒烟运行 wrapper 传入空参数数组时 PowerShell 参数绑定失败；根因是空 `string[]` 不被当前 PowerShell 接受；修复为传递 `--smoke` 哨兵参数，并通过 5 秒存活检查。
- 验证：视觉、玩法、功能、表现、相机、操作栏、性能和 ENet 回归通过；性能独立重跑为 `sync_visuals_ms=6.54535`；Windows 导出退出码 0，EXE 冒烟运行 5 秒通过；项目进程和端口清理完成。

## 2026-09-26：地堡施工灯光悬浮修复

- 症状：地堡尚未建造完成时，左右警示灯保持在最终高度，悬浮在仍处于地下的主体上方。
- 根因：施工动画只移动 `BunkerBody` 和 `Turret`，`FactionLights` 是独立兄弟节点，仅做缩放淡入，没有同步施工下沉/升起。
- 修复：在 `assets/art/entity_visual.gd` 中记录 `FactionLights` 默认变换，新增其位置施工轨道，并在退出施工状态时恢复默认位置；保留灯光原有的缩放淡入效果。
- 验证：`tests/visual_models.gd` 新增施工中点位置、动画轨道和完工复位断言；视觉测试、玩法/功能/表现/相机/操作栏回归、性能测试和 ENet 回归均通过；重新导出 EXE，5 秒冒烟运行通过，项目进程和端口清理完成。

## 2026-09-26：士兵与能量弹模型重做

- 完成：以 `exec-c83c3377-171b-4b9e-b39e-5a03cb723d5d` 为参考，重建简约硬表面士兵；运行时层级改为 `ArmorCore`、`Helmet`、`Shoulder_L/R`、`Arm_L/R`、`Hips`、`Leg_L/R`、`Weapon`、`Muzzle`，并同步 idle/move/attack 动画路径。
- 完成：阵营材质只保留在左右护肩，枪械、前臂、头盔侧面和其余装甲使用中性材质；新增蓝白发光 `assets/models/bullet.glb`，替代旧白色方点射击效果。
- Bug 修复：首次 ENet 回归中，`frame + index` 效果键可能让 `shot` 的 Node3D 与死亡 Sprite3D 复用，随后对空 Sprite3D 写入 `modulate`。修复为在复用前检查视觉节点类型，不匹配时释放并按当前效果种类重建。
- 验证：Blender 导出/预览、Godot 导入、视觉模型、玩法 64/0、功能、表现、相机、操作栏、视觉性能（`sync_visuals_ms=6.61585`）和完整 ENet 回归通过；Windows EXE 重新导出，5 秒冒烟运行通过。

## 2026-09-26：2D 格子血条

- 完成：移除单位和建筑实体上的 3D HP `Sprite3D`，新增 `HealthGridOverlay` 自绘 2D 控件挂载到 HUD `CanvasLayer`，通过相机投影跟随实体顶部。
- 完成：每 10 点最大生命值显示一格，最后不足 10 点的格子按比例填充；单位和建筑分别使用目标总宽自动缩放格宽，阵营色保留在已填充格中。
- 保持：建造进度条和采集量显示不变；未修改 Simulation HP、伤害判定、快照 schema 或 ENet 协议。
- 验证：`tests/visual_models.gd`、玩法 64/0、表现、功能、相机、操作栏、视觉性能（`sync_visuals_ms=7.2193`）和完整 ENet 回归通过；Windows EXE 重新导出，5 秒冒烟运行通过。

## 2026-09-26：绿色 3D 选中圈

- 完成：为单位和建筑增加延迟创建的地面 `TorusMesh` 选中圈，固定使用醒目绿色发光材质，不使用阵营颜色；单位和建筑尺寸通过 `SELECTION_RING_PROFILES` 按类型配置。
- Bug 修复：选中圈原先通过缩放和亮度脉冲表现选中状态，现已移除时间驱动的呼吸效果，保持静态大小和亮度；建筑半径改为底座半对角线加安全边距，完整覆盖底座。
- Bug 修复：新建建筑在 `_ready()` 前收到选中状态时，原先不会创建选中圈；现由 `_ready()` 末尾补应用待处理状态，并用回归断言验证。
- 预览：通过 Blender 生成 `build/verification/selection_ring_preview.png`，确认士兵与建筑底部的圆环可见且比例合理。
- 验证：视觉、玩法 64/0、表现、功能、相机、操作栏、视觉性能（`sync_visuals_ms=6.9522`）和完整 ENet 回归通过；Windows EXE 重新导出，5 秒冒烟运行通过。

## 记录规则

- 确认 bug 必须在同一条记录中写明症状、根因、具体修复和验证。
- 不在本文件维护未完成 TODO；未完成内容统一放入 `task_plan.md` 和 `findings.md`。
- 新记录按日期追加，重复的测试数字只引用 `VERIFICATION.md`。
