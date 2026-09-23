# 任务计划：全项目 Coding Style 整改

## 范围
- 自有代码：scripts/（含 entities）、tests/、assets/art/ 共 15 个 .gd 文件
- 排除：addons/godot_ai/（第三方插件，不改动）

## 步骤
1. [x] 读取 agent_md/AGENTS.md 的 coding style 规范
2. [x] 全量扫描自有脚本，输出违规清单
3. [x] 修复：tab→4空格、运算符/逗号空格、单行函数拆分、函数间空行、文件尾空行、CRLF→LF
4. [x] 复审：重跑审计脚本直到 0 违规
5. [x] 验证：Godot 编辑器扫描 + 测试套件 + 游戏运行验证 + Windows 导出
6. [x] 记录结果

## 结果
- 15/15 文件通过风格审计（tab、行尾空白、逗号/运算符空格、分号、函数空行）
- 字符串字面量 15/15 与 git HEAD 完全一致（零内容改动）
- gameplay 测试：47 checks / 0 failures；presentation 测试：0 failures
- 运行时验证：SOLO 对局启动，AI 建兵营并产兵，无运行时错误
- 导出：build/IronFront.exe 已更新（2026-09-19 22:25，PCK 内嵌，单文件分发）

# 任务计划：Blender 3D 实体模型替换像素贴图（2026-09-22）

## 目标
- 使用 Blender 制作务实写实机械风 3D 模型，替换士兵、采集车、4 种建筑、矿石与岩石的 Sprite3D 像素表现。
- 接入状态动画、蓝/红阵营标识、清晰战场光照，并保留现有玩法、迷雾、HUD 与网络同步。

## 阶段
1. [in_progress] 建立 Blender 源文件与 8 个可导出 GLB 资产
2. [ ] 重构 Godot 实体视觉层、状态动画与光照
3. [ ] 新增视觉回归测试并运行全套既有测试
4. [ ] 实机 SOLO/联机验证与截图检查
5. [ ] 导出并运行 Windows EXE，更新 agent_md 记录

## 约定
- 不改模拟数值、网络协议、选择逻辑和存档格式。
- 地面纹理第一阶段保留。
- 原像素生成器保留为回退资源。
## 阶段更新（2026-09-22）
1. [x] Blender 源资产与 8 个 GLB 完成
2. [x] Godot EntityVisual / 状态动画 / 光照 / 建筑预览完成
3. [x] visual_models 与全部既有回归完成
4. [x] SOLO 实机截图与完整多进程联机验证完成
5. [in_progress] 最终回归、Windows 导出与导出版运行验证
## 最终状态（2026-09-22）
5. [x] 最终回归、Windows 导出与导出版运行验证完成
状态：完成

# 任务计划：本地效果图收藏网页（2026-09-22）

## 目标
- 新增零依赖本地静态网页，用于导入、保存、预览和管理效果图。
- 使用浏览器 IndexedDB 持久保存图片 Blob 与收藏状态。
- 提供“全部效果图 / 中意收藏”两个标签，并支持搜索、排序、下载和删除。

## 阶段
1. [in_progress] 创建静态图馆页面与本地启动脚本
2. [ ] 浏览器端实现 IndexedDB、上传、缩略图、标签、搜索和排序
3. [ ] 执行真实浏览器端功能与持久化验证
4. [ ] 记录验证结果并提交本地 Git commit

## 约定
- 不新增后端、账号或外部依赖。
- 不修改 Godot 游戏逻辑。
- 后续可静态部署；数据仍按浏览器源隔离。
## 阶段更新（2026-09-22）
1. [x] 静态图馆页面与启动脚本完成
2. [x] IndexedDB、上传、缩略图、标签、搜索、排序、预览、下载、删除完成
3. [x] 静态/HTTP 验证完成；真实浏览器控制通道不可用，已记录限制
4. [in_progress] 最终记录与本地 Git 提交
## 最终状态（2026-09-22）
4. [x] 最终记录与本地 Git 提交完成
状态：完成

# 任务计划：3D 分支审查修正与性能优化（2026-09-23）

## 目标
- 修复 cargo 空条、追击动画、岩石多人一致性问题。
- 消除每帧重复材质刷新、缓存动画库、关闭装饰阴影。
- 优化 Blender 模型静态网格与材质实例，降低高单位数 draw calls。
- 删除未使用重复贴图，扩展视觉/性能测试，导出临时 3D EXE 验证。

## 阶段
1. [in_progress] 清理审查副作用并修复运行时行为/性能问题
2. [ ] 优化 Blender 模型、重导 GLB、清理重复资产
3. [ ] 扩展视觉与性能测试，运行核心和多人回归
4. [ ] 导出 build/IronFront3D-review.exe 并运行验证
5. [ ] 更新文档与 agent_md，本地提交；不推送

## 约定
- 不修改跟踪的 build/IronFront.exe。
- 不提交新的 111MB LFS EXE。
- 不合并 main，未收到明确请求不推送。
## 阶段更新（2026-09-23）
1. [x] 运行时行为/性能修复完成
2. [x] Blender 静态网格合并、GLB 重导与重复贴图清理完成
3. [x] 视觉/性能/核心/多人回归完成
4. [x] build/IronFront3D-review.exe 导出与运行验证完成
5. [in_progress] 最终记录与本地提交
## 最终状态（2026-09-23）
5. [x] 最终记录与本地提交完成
状态：完成


# 任务计划：施工动画与单位朝向修正（2026-09-23）

## 目标
- 建筑施工动画一次播放，并精确匹配每种建筑的真实建造时长。
- 士兵和采集车模型正面朝向运动/目标方向。

## 阶段
1. [x] 修正 EntityVisual 施工动画、进度映射和 -Z 朝向
2. [x] main.gd 传入模拟施工比例与真实建造时长
3. [x] 扩展 visual_models 覆盖四个朝向和四种建筑时长
4. [x] 核心、联网、实机与导出验证完成
状态：完成

# Task plan: fix visible soldier attack facing (2026-09-23)

- [x] Reproduce the visible body-facing failure and identify the authoritative model front axis.
- [x] Correct the soldier source model/weapon direction and runtime per-model heading logic.
- [x] Strengthen tests to validate the visible soldier front and muzzle against all target directions and a real attack order.
- [x] Run Godot regressions, real rendered gameplay validation, and export a fresh Windows EXE.
- [x] Record bug/root cause/fix/verification together in the development log.
