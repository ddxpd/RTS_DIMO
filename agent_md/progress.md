# 最近进度

## 2026-09-29：删除效果图库功能

- [x] 已确认图库仅用于开发期素材管理，游戏运行时没有引用。
- [x] 已删除图库目录、本地数据、专用生成脚本、MCP 动作、8765 端口处理和文档入口。
- [x] PowerShell Parser 通过，`gallery` 参数被 ValidateSet 拒绝，活动代码无图库/8765 残留引用。
- [x] 13 份剩余 Markdown 的 UTF-8、NUL 和链接检查通过；scoped `git diff --check` 通过。
- [x] 最终完整清理通过，项目进程与 24560/8766 端口为空；8765 亦无监听，共享 Blender MCP 未停止。

状态：完成；未运行 gameplay、ENet、导出或 EXE 冒烟测试，因为游戏运行时、网络协议和打包路径未改变。

## 2026-09-29：移除统一 Python 工具入口

- [x] 已确认统一 Python runner 是当前未提交工具迁移的一部分，并识别全部脚本、执行规则和文档引用。
- [x] 已删除 `project_tools.py`、共享 Python 运行时和专用 `psutil` 依赖声明。
- [x] 已恢复 Godot、Blender、ENet、MCP、导出检查、进程清理和图库的 PowerShell wrappers。
- [x] 已恢复固定 PowerShell wrapper 的 Codex allowlist 与 ExecutionPolicy 规则，没有授权任意解释器调用。
- [x] 已将项目规则和活动命令切回 PowerShell，同时保留风险分级验证政策和独立业务 Python 工具。
- [x] 全部相关 `.ps1` 通过 PowerShell Parser，权限自检、Godot/Blender 版本入口和最终完整清理退出码为 0。
- [x] execpolicy 允许固定 `run-exported.ps1`，旧 Python 入口无匹配规则；项目进程和 24560/8765/8766 端口为空。
- [x] 最终扫描只在本次计划/完成记录中保留被删除入口的名称，活动命令和配置没有残留引用。

状态：完成；按风险分级规则未运行 gameplay、ENet、Windows 导出或 EXE 冒烟测试。

## 2026-09-28：PowerShell 启动方式优化（已完成）

- [x] 已增加单次批量启动检查规则，禁止为节省延迟而并行启动多组 PowerShell。
- [x] 已将可信非交互 wrapper 标准改为隐藏、无交互调用，并同步执行策略与文档。
- [x] 已补齐权限自检中的 `run-network.ps1`、`run-exported.ps1` 清单。
- [x] 按风险分级完成静态检查；本次未启动 Godot/Blender，未运行游戏测试或导出。

## 2026-09-28：验证流程改为风险分级

- [x] 已将项目级验证规则改为按实际影响选择最小充分测试集。
- [x] 已取消文档、小型工具和局部改动默认触发全套 gameplay、ENet、导出和 EXE 冒烟运行。
- [x] 已保留网络、发布、跨系统改动和失败升级场景的完整验证要求。
- [x] 已减少常规清理的重复 PowerShell 调用，同时保留高风险场景的独立复查。
- [x] 本次只修改规则与记录，按新策略未启动 Godot/Blender、未运行玩法或 ENet、未导出 EXE；文本复核和 scoped `git diff --check` 已通过。

## 2026-09-28：消除任务执行期间的 PowerShell 弹窗

- [x] 已审计全部 `.ps1`、Codex execpolicy 规则和 Godot 插件的 PowerShell/进程调用点。
- [x] 已确认联机测试存在一层可移除的 PowerShell 套用。
- [x] 已确认插件 `port_resolver.gd` 的同步 PowerShell 查询是大量可见窗口的主要风险来源。
- [ ] 正在实现无窗口查询和联机 runner 去嵌套，并准备回归测试。
- [x] 已选定最小兼容实现：同 runspace 联机调用、PowerShell CLI 隐藏参数、图库直接打开 URL；无需新增 Python 依赖或放宽 execpolicy。
- [x] `run-network.ps1` 已改为在当前 runspace 执行 runner，不再创建第二个 `powershell.exe`。
- [x] `port_resolver.gd` 已统一使用 `-NonInteractive -WindowStyle Hidden`，并显式设置 `open_console=false`。
- [x] 效果图库浏览器延迟打开逻辑已移入 `server.py`，启动脚本不再派生 PowerShell。
- [x] 已新增 `tests/tooling.gd`，验证隐藏参数和同步输出捕获。
- [x] PowerShell Parser 静态语法检查通过；全仓库 diff 检查受既有 Git LFS 临时目录权限限制，转为限定文本范围检查。
- [x] `tests/tooling.gd` 退出码为 0，确认 GDScript 编译、隐藏参数和 PowerShell 输出捕获通过。
- [x] 完整 ENet 回归通过：协议不匹配、观战权限、双 guest、快照一致性、重连和主机退出均正常。
- [x] 效果图库通过 wrapper 启动并返回 `{"ok":true}`，随后已停止服务且确认项目端口清空。
- [x] 新的固定批量入口顺序运行 tooling、gameplay、presentation、visual_models、features、camera、action_bar、visual_performance，全部通过。
- [x] `verify-permissions.ps1` 的 wrapper 语法、Godot/Blender 入口和清理检查通过；因当前 `PATH` 无 `codex`，execpolicy CLI 子检查被脚本跳过。
- [!] 首次导出因 `cmd` 环境的 `Path/PATH` 重复键与 `Start-Process` 日志重定向冲突而在启动前停止；已切回既有 PowerShell 承载路径。
- [x] 使用既有 PowerShell 承载方式重新导出 `build/IronFront.exe` 成功，文件大小 110,027,832 字节。
- [x] 导出 EXE 存活运行 5 秒，报告 `EXPORTED_GAME_SMOKE_PASS`。
- [x] 已执行 `-StopTracked -StopUntracked` 和最终 `-ReportOnly`；项目进程与 24560/8765/8766 端口均为空，共享 Blender MCP 进程仅报告、未停止。

状态：PowerShell 弹窗治理完成；execpolicy CLI 子检查因当前环境找不到 `codex` 可执行文件而未运行，其余静态、功能、联机、图库、导出和清理验证全部通过。

- [x] 失败导出留下的两份 0 字节临时日志已精确删除；新测试的 Godot UID 文件已保留。
- [x] 最终限定范围 `git diff --check` 通过，仅有仓库既有的 LF/CRLF 提示。
- [x] 最终调用点复核确认已无 `Start-Process powershell` 套用；插件唯一集中执行点显式使用隐藏窗口参数和 `open_console=false`。

## 2026-09-28：全部 Markdown 文档中文化

- [x] 已读取项目级 `agent_md/AGENTS.md` 和适用工作流程。
- [x] 已恢复并检查现有规划文件；未发现需要先同步的中断会话。
- [x] 已盘点 14 份 Markdown 文件并确定翻译范围。
- [x] 已翻译根目录规则、`agent_md/AGENTS.md`、授权日志英文条目和 `addons/godot_ai/README.md`；代码、路径、命令、URL、产品名和状态标识保持原样。
- [ ] 正在进行英文残留、链接、编码和 Markdown 结构检查。

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
- [x] 完成 Godot 回归、ENet 回归、Windows EXE 导出与 5 秒冒烟运行验证。

## 2026-09-26：地堡模型续作实施

- [x] 恢复参考图、现有模型预览、生成脚本和 Godot 动画契约。
- [x] 确认中断脚本存在共享源文件清空风险和单炮管节点未对齐问题。
- [x] 重写 Blender 生成器与运行时动画，完成单炮、灯带、地下升起和建造复位。
- [x] 生成新的 `bunker.glb`、源 `.blend`、预览图和 Windows EXE。
- [x] 完成 Godot 全套回归、ENet 回归、5 秒 EXE 冒烟运行和进程清理。

更新时间：2026-09-25

## 当前阶段

地堡模型续作已完成；运行时控制器拆分和快照边界阶段已完成，后续工作回到 `task_plan.md` 的架构 P0 项。

## 最近完成

- 完成 `WorldVisualSync`、`GameSession`、`CommandBus`、`NetworkSession`、`InputController`、`HudController`、`AudioController` 的职责提取。
- 完成快照 schema/type/bounds/size 校验，非法网络状态不会部分写入本地模拟。
- 完成视觉模型、朝向、施工/攻击表现和 180 单位性能回归。
- 建立 `agent_md/README.md` 文档目录，并清理旧计划中的过时未完成标记。

## 当前验证基线

- 玩法：64 项检查 / 0 项失败。
- presentation、visual_models、features、camera、action_bar：通过。
- ENet：协议不匹配、观战权限、双 guest、快照一致性、重连、主机退出：通过。
- visual performance：独立重跑低于 8ms 阈值。
- Windows 导出：无界面运行退出码 0；渲染进程存活检查通过。

## 当前未完成

- 统一 Simulation 与旧实体模型所有权。
- 补齐空间分离邻居检查和密集边界回归。
- 注册 MCP/CI 可发现测试入口。
- 删除不再需要的 `main.gd` 兼容 wrapper。
- 后续 typed state、tick 子系统、AI controller、配置外置、增量快照和 GLB 契约重构。

## 限制与注意事项

- MCP 测试套件发现仍报告 0 个套件。
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
- [!] 渲染导出进程存活 5 秒后由验证脚本主动停止，退出码 `-1` 属于预期清理结果；无界面运行退出码为 0。

状态：完成；MCP 测试套件发现仍为 0，属于既有测试基础设施限制。

## 2026-09-25：Esc 菜单修复

- [x] 将 Escape 处理前移到 `InputController._input()`，避免 HUD 控件吞掉快捷键。
- [x] 修复攻击键重绑状态按 Escape 后未清除的问题，并兼容 physical keycode。
- [x] 增加 presentation 菜单开关和重绑取消回归；测试退出码 0。
