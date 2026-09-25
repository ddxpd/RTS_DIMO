# 开发历史

本文件保存已完成工作的压缩记录。当前待办只写入 [task_plan.md](task_plan.md)；验证数字集中在 [VERIFICATION.md](VERIFICATION.md)。

## 2026-09-19：操作栏与编码规范

- 完成 coding style 全量整改：缩进、空格、函数空行、文件换行和字符串一致性。
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

## 记录规则

- 确认 bug 必须在同一条记录中写明症状、根因、具体修复和验证。
- 不在本文件维护未完成 TODO；未完成内容统一放入 `task_plan.md` 和 `findings.md`。
- 新记录按日期追加，重复的测试数字只引用 `VERIFICATION.md`。
