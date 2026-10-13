# Iron Front

Iron Front 是一个 Godot 4 RTS 主机对等联机原型，主分支 `main` 使用 3D 实体表现、基础 AI、LAN 联机、资源采集、建造、生产、战斗、迷雾和快照同步。

## 运行

开发源码需要先安装 Git LFS，然后执行：

```powershell
git lfs install
git clone https://github.com/ddxpd/RTS_DIMO.git
cd RTS_DIMO
git lfs pull
```

已有克隆更新后也应执行 `git lfs pull`，再用 Godot 打开项目。正式 `assets/` 中的模型、Blender 源文件及备份、位图、音频、字体和二进制 `.res` 使用 LFS；SVG、场景、文本资源与导入配置仍为普通 Git 文件。不要通过仓库 Download ZIP 获取完整美术资源。

`assets/concept_art/`、`.local/` 资源库和模拟快照不上传 Git、LFS 或 Release；游戏采用的素材必须复制到正式资源目录。EXE 继续通过 Release 发布。本次迁移仅处理未发布提交和当前资源，已发布历史中的普通二进制仍然保留。

- 开局菜单提供“荒漠矿区”和单机地形样板区；默认使用荒漠矿区，LAN 加入者跟随主机。荒漠地图含可进入矿坑、高台、坡道及地形视线遮挡。旧原型地图已移除。
- Windows 下载：前往 [GitHub Releases](https://github.com/ddxpd/RTS_DIMO/releases)，下载发布附件 `IronFront.exe`；资源已内嵌，无需另配 PCK。预发布版本的已知限制见对应发布说明。
- EXE 不再随 Git 跟踪；开发者仍可导出到本地 `build/IronFront.exe`。发布附件提供 SHA256 校验文件。
- 源码验证：普通改动使用 `tools/codex/run-validation.ps1 -Level Light -Area <影响面>`，跨系统改动使用 `-Level Full`；不要直接调用未固定路径的 Godot/Python。
- 局域网：主机使用 `Create LAN Host`，客户端输入主机 IP 后选择 `Join Host`；默认 UDP 端口为 `24560`。

## 基本操作

- 地形组件验收：选择“荒漠样板区（临时测试）”进入单机；当前样板为 +128 高台、-128 矿坑、宽/长均 256 的短坡。单位应从坡道上下；3×4 兵营可在整块平地部署，跨坡或跨崖占地会被拒绝。
- 编辑器准备：12 类运行组件在 `assets/maps/components/`，可编辑布局为 `assets/maps/desert_sample_layout.json`。布局实例使用稳定组件 ID，不依赖素材库文件名。地图编辑器界面仍是后续任务。
- 制作预览保存在 `assets/concept_art/desert_terrain_kit/editor_ready/` 和 `assets/concept_art/sample-*-components-v1.png`，这些文件仍由个人素材库管理、不提交 Git。运行时使用独立组件资源与缩略图。


- 左键选择、拖框选择、选择己方建筑；右键移动、采集或攻击可见敌人。
- `A` 进入攻击模式，`S` 停止，`R` 设置集结点，鼠标滚轮缩放，中键/方向键移动镜头。
- `B` 建造兵营；选中建筑后使用生产按钮；`Esc` 取消当前模式或返回菜单。
- 胜利条件是摧毁敌方全部基地；主机退出会结束对局，红方客户端断线可重连。

## 文档

项目文档入口是 [agent_md/README.md](agent_md/README.md)。推荐先看：

1. [当前任务计划](agent_md/task_plan.md)
2. [架构发现](agent_md/findings.md)
3. [验证索引](agent_md/VERIFICATION.md)
4. [游戏规则](agent_md/game_rules_zh.md)

第三方插件说明位于 `addons/godot_ai/README.md`，不属于项目文档维护范围。

## 目录与代码入口

- 运行所需美术必须独立保存在正式`assets/`子目录，并随项目版本管理。不得直接引用不上传的`assets/concept_art/`、`.local/art-library/`或其他本机路径；从资源库采用素材时先复制正式资源，再修改游戏引用。GLB使用外置贴图时也必须携带这些依赖。`run-structure.ps1`自动检查该边界。
- `scripts/definitions/`：单位、建筑、名称、生产关系和公共规则的统一定义；`simulation.gd` 保留兼容常量和权威状态。
- `scripts/simulation_systems/`：同步模拟系统；`snapshot_validator.gd`：快照合法性；`runtime/network_session.gd`：共享 RPC 处理。
- `scripts/presentation/`：单位、建筑、特效和覆盖层显示；`world_visual_sync.gd` 管理节点生命周期，`ui/` 管理 HUD。
- `assets/models/` 与 `assets/art/`：按 `units/`、`buildings/`、`effects/`、`environment/` 分类。制作源文件仍在 `assets/models/source/`，概念图由用户单独管理。
- `tests/`：按 `simulation/`、`ui/`、`network/`、`visual/`、`performance/`、`previews/`、`helpers/`、`tooling/` 分组；`fixtures/` 保存冻结轨迹。执行范围集中登记在 `tools/codex/validation-suites.json`。
- `tools/blender/`：按资产分组，制作依赖见 `pipelines.json`，输出路径共用 `project_paths.py`。机动兵 v5 仍依赖 v3、v2 基础模块，不能当作废弃版本删除。
- `archive/entity_prototypes/` 保存未使用的旧实体原型，`archive/verification/` 保存历史验证证据，均通过 `.gdignore` 隔离。新增自动检查日志和可再生输出放在 `.godot/`。
- 旧路径映射见 `tools/codex/structure-migration.json`；目录审计使用 `tools/codex/run-structure.ps1`。美术库应用该映射时保留原资源 ID 和用户元数据。

## 项目边界

- 主机以 20 Hz 运行权威模拟；客户端接收快照并负责表现同步。
- 当前原型不包含战役、科技树、坦克、完整音乐系统、地图编辑器、NAT 穿透或主机迁移。
- 修改后按 `agent_md/AGENTS.md` 选择与影响范围相称的验证；只有启动了项目进程时才执行对应清理。不要执行未明确授权的远程 push。
