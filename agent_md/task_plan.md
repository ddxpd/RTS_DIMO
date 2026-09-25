# 当前任务计划

更新时间：2026-09-25

## 已完成里程碑

- [x] 全项目自有 GDScript coding style 整改与回归。
- [x] Blender/GLB 实体视觉替换、动画、朝向、光照和性能优化。
- [x] 本地图像收藏页、IndexedDB、垃圾桶和本地文件 API。
- [x] 从 `main.gd` 提取 `WorldVisualSync`、`GameSession`、`CommandBus`、`NetworkSession`、`InputController`、`HudController` 和 `AudioController`。
- [x] 快照版本、类型、边界、数量校验，深拷贝应用，以及异常网络快照处理。
- [x] 现有 gameplay、presentation、visual、features、camera、action-bar、性能和 ENet 回归；Windows 导出与运行检查。

## 当前重构路线

### P0：收口现有边界

- [ ] **统一实体所有权**：审计 `Simulation` 字典状态与 `scripts/entities/*` 的实际调用，选择一个权威模型，迁移或删除另一套。
  - 验收：运行时只有一个权威实体状态源；旧类有明确保留理由或被移除；核心回归不变。
- [ ] **补齐空间分离**：覆盖空间哈希的全部相邻单元，并增加密集边界回归。
  - 验收：边界、角落和高密度单位场景均不穿模、不死锁，性能预算不退化。
- [ ] **注册统一测试入口**：让 MCP/CI 能发现并执行现有 Godot 测试脚本。
  - 验收：suite discovery 不再为 0；结果有稳定的退出码和机器可读摘要。
- [ ] **删除兼容层**：确认下游测试不再调用 `main.gd` wrapper 后，移除 `_create_ui_legacy()` 和不再需要的转发方法。
  - 验收：`main.gd` 只保留组装和生命周期协调职责。

### P1：拆分核心模拟

- [ ] **拆分 deterministic tick**：将路径、可见性、AI、战斗、经济拆为独立系统接口，并保留固定 tick 顺序。
- [ ] **类型化状态边界**：为单位、建筑、资源、效果、可见性和命令引入 typed records/resources，逐步替代裸 Dictionary/string key。
- [ ] **AI controller 化**：将 AI 从 `Simulation` 移到可测试 controller，策略和节奏可配置。
- [ ] **配置外置**：将平衡和地图参数迁移到经过校验的 Resource/config，并保留默认值兼容。

### P2：网络与资产契约

- [ ] **增量网络状态**：在当前已校验的完整快照之上，根据实体规模加入 delta、相关性和压缩策略；保持 RPC 和版本兼容。
- [ ] **GLB 导出契约**：为节点命名、朝向、动画轨道和材质添加元数据及自动化层级/方向断言。
- [ ] **发布策略明确化**：记录 `godot_ai` 的开发态/发布态边界，验证 release 不依赖编辑器插件。
- [ ] **工具路径可移植**：为测试脚本提供统一 Godot 自动发现和显式覆盖机制，去除机器特定默认路径。

### P3：文档质量

- [x] 统一项目自有 Markdown 为 UTF-8，并完成链接/空白/NUL 基础检查。
- [ ] 统一运行时 UI 文本为 UTF-8，并加入持续编码检查。
- [x] 建立本目录索引，明确计划、发现、进度、验证和历史文档的职责边界。

## 约束与不变项

- 不改变现有 `Simulation.VERSION`、RPC 名称、快照字段形状和确定性 tick 行为，除非单独建立兼容迁移方案。
- 不修改第三方 `addons/godot_ai` 源码。
- 每个代码阶段必须运行核心回归、多人回归和导出运行检查；文档阶段至少运行 Markdown/编码/链接检查。
- 不主动推送远程仓库；大二进制继续按项目发布规则处理。

## 当前阻塞与限制

- MCP suite discovery 当前报告 0 个 suite，需要先完成统一入口注册。
- Git LFS 在受限环境读取 `.git/lfs/tmp` 偶发 `Access is denied`；不影响源文件文档整理，但会限制包含 LFS 二进制的完整 diff。
- 浏览器控制通道不可用时，只能执行图库的静态 HTTP/API 验证。

## 本阶段验收

- 文档索引中的项目自有 Markdown 均有明确用途，链接有效。
- 不再存在“历史计划显示未完成、但后续记录已完成”的冲突复选框。
- `findings.md`、`progress.md`、`VERIFICATION.md` 与本文件的当前状态一致。
