# GAIA FRONTIER

GAIA FRONTIER 是一个 Godot 4 RTS 原型，支持独立主界面、训练场、四人房间、基础 AI、资源采集、建造、生产、战斗、迷雾和快照同步。多人房间使用独立权威服务端，旧的主机直连入口保留用于兼容测试。

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
- Windows 下载：前往 [GitHub Releases](https://github.com/ddxpd/RTS_DIMO/releases)，下载发布附件 `GAIA_Frontier.exe` 或便携 ZIP；资源已内嵌，无需另配 PCK 或安装 Godot。预发布版本的已知限制见对应发布说明。
- EXE 不随 Git 跟踪；开发者导出到本地 `build/GAIA_Frontier.exe`。发布附件提供 SHA256 校验文件。当前发布目标为 Windows x64 `v0.2.0-alpha.1`，不是稳定版。
- 源码验证：普通改动使用 `tools/codex/run-validation.ps1 -Level Light -Area <影响面>`，跨系统改动使用 `-Level Full`；不要直接调用未固定路径的 Godot/Python。
- 多人对战：所有玩家先连接同一服务器，再创建或加入房间，默认 UDP 端口为 `24562`。旧版 `Create LAN Host` / `Join Host`、UDP 24560 仅用于兼容测试，不是当前主界面房间入口。

### 本地测试包与异地测试

本轮本地交付路径为 `build/GAIA_Frontier.exe`（资源内嵌），对应校验文件为 `build/GAIA_Frontier.exe.sha256`。双方使用同一份文件并比对 SHA256；正式荒漠矿区使用组件布局，含高台、坡道、岩沙材质和迷雾。

**Alpha 测试版：跨公网连通性和长时间弱网对战仍待验证。** 本机房间和短时网络扰动测试不等于真实异地验收；历史旧直连弱网矩阵也不能替代当前房间验证。当前构建的实际结果与已知限制见发布说明及 [验证索引](agent_md/VERIFICATION.md)。

1. 同机开两个进程：第一个选择“启动本机服务并连接”，第二个连接 `127.0.0.1:24562`；在同一服务器创建并加入房间，全部真人准备后由房主开始。
2. 局域网开服：运行 `start-exported-server.ps1 -BindAddress <服务器局域网IPv4>`，玩家连接该地址的 UDP 24562。脚本在便携包中与 EXE 同目录，也可显式指定 `-GamePath`。
3. 不同网络测试需要可达的服务器地址及入站 UDP 24562；家庭服务器可能需要路由器转发和防火墙放行。CGNAT 下仅填写公网 IP 不保证可达；游戏不会自动配置路由器、防火墙或提供中继。
4. 双方检查建造、生产、采矿卸货、移动攻击、建筑起降、战争迷雾、胜负与重开，再检查意外断线后 60 秒内重连和服务端退出。记录版本、网络类型、单位数量、卡顿时间与复现操作。主动退出对局视为投降。

自动弱网测试使用真实 ENet 数据包经本机 UDP 代理注入延迟、抖动、丢包、限速和短暂断网；它不验证真实路由器、CGNAT、运营商策略或跨网可达性。源码复现入口：`tools/codex/run-network.ps1 -Mode Weak -Profile all -DurationSeconds 180`，默认固定种子 101/202/303，结果位于 `.godot/validation/`。当前两端均启用 ENet FastLZ 压缩，必须使用同一测试包。

## 基本操作

- 地形组件验收：在训练场选择“荒漠训练场”；+128高地与-128洼地的平坦区各24×24格，坡道宽/长均256。六组晶矿数量为5、2、6、2、4、3，共22处，每处6000。单位从坡道上下；建筑可在整块平地部署，跨坡或跨崖占地会被拒绝。
- 编辑器准备：12 类运行组件在 `assets/maps/components/`，可编辑布局为 `assets/maps/desert_sample_layout.json`。布局实例使用稳定组件 ID，不依赖素材库文件名。地图编辑器界面仍是后续任务。
- 训练场晶矿与初始镜头在`assets/maps/desert_sample.tres`。通过固定`run-godot.ps1`运行`res://tools/build_terrain_components.gd -Arguments --layout-only`可重建训练场布局而不重建美术。正式矿区重建单独读取`assets/models/source/terrain/quarry_assemblies.json`，避免训练场扩展连带改变对战地图。
- 制作预览保存在 `assets/concept_art/desert_terrain_kit/editor_ready/` 和 `assets/concept_art/sample-*-components-v1.png`，这些文件仍由个人素材库管理、不提交 Git。运行时使用独立组件资源与缩略图。


- 左键选择、拖框选择、选择己方建筑；右键移动、采集或攻击可见敌人。
- `A` 进入攻击模式，`S` 停止，`R` 设置集结点，鼠标滚轮缩放，中键/方向键移动镜头。
- `B` 建造兵营；选中建筑后使用生产按钮；`Esc` 取消当前模式或返回菜单。
- 摧毁敌方全部建筑可淘汰对手，结果按房间队伍规则判定；独立服务器退出会中断房间对局，客户端意外断线保留席位 60 秒。

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
# GAIA FRONTIER：主界面与房间

启动游戏先进入指挥中心。训练场无需联网，可选择地图、AI 和初始资金；多人对战先连接服务器，再创建房间或输入房间码。支持最多四个席位、混战和 2v2。所有真人准备后由房主开始，配置变更会清除准备状态。对局结束显示结果，点击返回主界面；主动退出视为投降。

“启动本机服务并连接”会在后台启动独立服务端，本机同时可以游玩。默认地址 `127.0.0.1`、UDP 端口 `24562`。退出客户端默认保留服务；多人连接页面可取消“退出游戏后保留本机服务”。房间码只在同一台服务器内有效。意外断线保留席位 60 秒，重新连接后点击“重连上一局”。

从源码单独开服：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/codex/run-frontier-server.ps1`。打包后的游戏也支持 `GAIA_Frontier.exe --headless -- --dedicated --bind=127.0.0.1 --port=24562`；`tools/server/start-exported-server.ps1` 是对应启动入口。发布名称统一为 GAIA FRONTIER / GAIA_Frontier.exe。

局域网服务可显式绑定所在网卡地址，其他电脑填写该地址。未来公网部署使用相同服务程序，Linux systemd 示例位于 `tools/server/gaia-frontier.service`：配置实际 Godot 路径、项目路径及服务用户，并准备完整 LFS 资源与 Godot 导入缓存。公网服务器需允许入站 UDP 24562；普通玩家主动连接服务器，无需配置自己的路由器。仅在本机开服不会自动获得公网入口。本次不包含公网部署、账号系统或匹配服务。

服务端最多同时容纳八个房间、32 个连接。地图和协议不一致会拒绝连接；本版本协议为 `gaia-frontier-19`，所有玩家应使用同一发布包。正式背景位于 `assets/ui/frontier/command_background.png`，不依赖微信临时文件、概念图库或 `.local/art_library`。
