# 最近进度

更新时间：2026-09-25

## 当前阶段

文档整理与架构路线收口。运行时控制器拆分和快照边界阶段已完成，下一阶段从 `task_plan.md` 的 P0 项开始。

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
