# 最近进度

## 2026-09-26：绿色 3D 选中圈

- [x] 审计选择状态和现有表现层挂载点。
- [x] 生成士兵/建筑选中圈效果预览图。
- [x] 接入固定绿色 TorusMesh 圆环、按类型可调的单位/建筑尺寸，并取消缩放和亮度呼吸效果。
- [x] 添加单选、多选、建筑选择和清空选择断言。
- [x] 建筑半径改用底座外接圆加安全边距，覆盖底座四角；修复 `_ready()` 前已选中新建建筑时圆环未创建的问题。
- [x] 核心回归、性能、ENet、导出和运行验证。

## 2026-09-26：2D 格子血条

- [x] 审计当前单位/建筑 3D 血条和 HUD CanvasLayer 投影入口。
- [x] 新增自绘 2D 格子血条覆盖层，移除单位与建筑 HP 的 Sprite3D 节点。
- [x] 完成每 10 点一格、末格比例填充、建筑高血量格子缩放和投影断言。
- [x] 核心回归、性能、ENet、导出和运行验证。

## 2026-09-26：士兵与能量弹模型重做

- [x] 审计当前士兵 GLB 契约、运行时动画与白色方点射击效果。
- [x] 锁定全新士兵层级、护肩集中队伍标识和蓝白能量弹方案。
- [x] Blender 生成、GLB 导出与预览。
- [x] Godot 接入、视觉测试和弹体方向/生命周期断言。
- [x] 核心回归、性能、ENet、导出和运行验证。

## 2026-09-26：地堡施工灯光修复

- [x] 修复施工中 `FactionLights` 未随地堡主体下沉而悬浮的问题。
- [x] 增加施工中点位置、施工轨道和完工复位回归断言。
- [x] 完成 Godot 回归、ENet 回归、Windows EXE 导出与 5 秒 smoke 验证。

## 2026-09-26：地堡模型续作实施

- [x] 恢复参考图、现有模型预览、生成脚本和 Godot 动画契约。
- [x] 确认中断脚本存在共享源文件清空风险和单炮管节点未对齐问题。
- [x] 重写 Blender 生成器与运行时动画，完成单炮、灯带、地下升起和建造复位。
- [x] 生成新的 `bunker.glb`、源 `.blend`、预览图和 Windows EXE。
- [x] 完成 Godot 全套回归、ENet 回归、5 秒 EXE smoke 和进程清理。

更新时间：2026-09-25

## 当前阶段

地堡模型续作已完成；运行时控制器拆分和快照边界阶段已完成，后续工作回到 `task_plan.md` 的架构 P0 项。

## 最近完成

- 完成 `WorldVisualSync`、`GameSession`、`CommandBus`、`NetworkSession`、`InputController`、`HudController`、`AudioController` 的职责提取。
- 完成快照 schema/type/bounds/size 校验，非法网络状态不会部分写入本地模拟。
- 完成视觉模型、朝向、施工/攻击表现和 180 单位性能回归。
- 完成本地效果图库、IndexedDB、垃圾桶和文件 API 的静态验证。
- 建立 `agent_md/README.md` 文档目录，并清理旧计划中的过时未完成标记。

## 当前验证基线

- gameplay：64 checks / 0 failures。
- presentation、visual_models、features、camera、action_bar：通过。
- ENet：协议不匹配、观战权限、双 guest、快照一致性、重连、主机退出：通过。
- visual performance：独立重跑低于 8ms 阈值。
- Windows 导出：headless 退出码 0；渲染进程存活检查通过。

## 当前未完成

- 统一 Simulation 与旧实体模型所有权。
- 补齐空间分离邻居检查和密集边界回归。
- 注册 MCP/CI 可发现测试入口。
- 删除不再需要的 `main.gd` 兼容 wrapper。
- 后续 typed state、tick 子系统、AI controller、配置外置、增量快照和 GLB 契约重构。

## 限制与注意事项

- MCP suite discovery 仍报告 0 个 suite。
- Git LFS 临时目录在受限环境可能拒绝访问；没有执行远程上传。
- 浏览器控制通道不可用时，图库只执行静态 HTTP/API 检查。

## 下一步

先完成实体所有权审计，记录调用关系和迁移边界，再修改运行时代码；每个代码阶段必须补齐核心、多人和导出验证。

## 2026-09-25：Markdown 文档整理

- [x] 新增 `agent_md/README.md`，明确文档职责和推荐阅读顺序。
- [x] 重写 `task_plan.md` 为当前路线图，清除历史计划中的过时未完成项。
- [x] 精简 `findings.md`、`progress.md`、`VERIFICATION.md`、`dev_log.md`、`authorization_log.md`、规则文档和工具 README。
- [x] 更新根 `README.md`，加入文档入口和当前项目边界。
- [x] Markdown 链接检查、`git diff --check`、Godot 核心回归、ENet 回归、Windows 导出和导出进程检查通过。
- [!] 渲染导出进程存活 5 秒后由验证脚本主动停止，退出码 `-1` 属于预期清理结果；headless 退出码为 0。

状态：完成；MCP suite discovery 仍为 0，属于既有测试基础设施限制。

## 2026-09-25：Esc 菜单修复

- [x] 将 Escape 处理前移到 `InputController._input()`，避免 HUD 控件吞掉快捷键。
- [x] 修复攻击键重绑状态按 Escape 后未清除的问题，并兼容 physical keycode。
- [x] 增加 presentation 菜单开关和重绑取消回归；测试退出码 0。
