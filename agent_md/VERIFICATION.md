# 验证索引

## 2026-10-05：3D Releases 分发

- 用户选择 Releases 分发并要求实施：移除 `build/IronFront.exe` 的 Git 跟踪，保留忽略规则、旧 Git 历史和本机文件。README 改为 Releases 下载入口；原工作区的未提交 EXE 保持不变。
- 在隔离整合工作目录从当前 3D 源码重新导出：退出 0，`agent_md/release_3d_export.log.err` 为 0 字节；EXE 为 131,747,840 字节，PCK 内嵌。
- SHA256：`3cd05b170850ce27ef1f6f4c3dfbfc5c192fb1e1a2b85633966d0fefe37c7418`。发布附件包含 EXE 和对应 `.sha256` 文件，不将二者加入 Git。
- `run-exported.ps1 -DurationSeconds 10` 返回 `EXPORTED_GAME_SMOKE_PASS`，固定 cleanup 确认项目进程和端口无残留；启动检查不等同于导出包完整玩法回归。
- 源码验证沿用下方 3D 整合记录；本次仅改分发与文档，不重复 Full。用户已要求在已告知性能限制后继续发布；性能问题仍未修复，Full 不宣称通过，发布说明列明限制并标记预发布。
- 计划版本 `3D-v0.1`，附件上传后再将 main 与标签指向最终源码提交，公开 Release 并回下载校验大小与 SHA256。发布结果在交付时以远端状态为准。

## 2026-10-05：3D 主分支整合

- 整合基线：`origin/main` 的 `91c41c3` 与 3D 分支 `36418b2`，在独立 worktree 中正常合并，保留两条历史；README 冲突保留 3D 说明。原工作区未提交的 EXE 不参与整合。
- 旧 2D 清理：删除 `pixel_art.gd` 的无引用像素精灵与 TileSet 生成函数、`main.gd` 的无引用 billboard 辅助函数。保留原型地图需要的 `terrain_image()`、两张可玩地图、二维模拟与寻路、HUD 和血条，不改变网络协议或游戏规则。
- 导入：沙箱内受证书读取和用户配置写权限限制；通过固定入口在授权环境重跑，退出 0，`agent_md/main3d_import_authorized.log.err` 为 0 字节。原始日志仅留在整合工作目录，不提交。
- `Full`：授权环境运行 53.034 秒。gameplay 71 项、编队、表现、功能、相机、操作栏、3D 模型、士兵动画及所有地图套件通过；性能失败，ENet 按 runner 规则跳过，cleanup 通过。日志目录 `.godot/validation/20261005-205226-23576/`。
- 已有性能问题（未修复）：180 单位动画同步 16.692 ms（阈值 8 ms）、单位同步 4.210 ms（阈值 2 ms）、模拟步进 35.103 ms（阈值 25 ms）。对未修改的 3D 基线独立运行 `Light -Area Performance`，对应为 15.974 / 4.116 / 35.039 ms，同样失败；基线日志位于原工作区 `.godot/validation/20261005-205339-22344/`。本次没有放宽阈值或将 Full 标为通过；尚需性能优化或用户明确接受已有限制后才能发布。
- `Light -Area Tooling,Network` PASS，257.937 秒：工具语法与路径回归、27 个允许/7 个拒绝授权用例、gameplay 71 项、地形规则、两张地图完整 ENet、清理均通过。联机覆盖采矿、建造、生产、兵营迁移、战斗、重连、主机断开及两轮完整快照一致；日志目录 `.godot/validation/20261005-210040-22304/network/`。
- 交付状态：整合保留在本地 `integrate/3d-main`，远端 main 尚未更新；等待性能处理决定和大文件发布范围确认。原工作区 EXE（131,750,416 字节）未修改、未纳入整合；沿用 3D 分支的 LFS 指针（110,233,632 字节），本次未重新导出。验证日志及截图不随合并新增提交。配置文件只去掉末尾多余空行，不改变权限设置。

## 2026-10-05：工具路径可移植性

- 问题：换机后工具找不到、旧仓库路径无法匹配授权规则。原因：工具入口和九条规则固定了开发机安装目录/仓库位置。修复：新增 `tools/codex/setup-local.ps1` 和公共解析器；自动发现后固定到本机 JSON，规则按当前仓库路径生成；移除跟踪文件里的真实机器路径。配置和生成规则均被 Git 忽略，用户全局配置不变。
- 初始化提供只读预览、显式工具路径和补充搜索目录。Godot 必需，Blender/MCP 可选；多候选要求显式选择，日常执行拒绝未登记或失效路径。迁移后必须重新初始化；规则文件有自定义修改时拒绝覆盖。进程台账按项目路径哈希隔离，共享 MCP 进程仅识别/报告。
- `Light -Area Tooling` 最终 PASS，11.281 秒：PowerShell 语法、PATH 环境回归、真实 Godot 启动、工具发现/注册/中文空格目录/迁移/失效路径/可选缺失/幂等性/规则保护/台账隔离。授权检查 27 个正例、7 个反例通过。其他盘符测试仅验证规则生成，没有在另一台实体电脑上运行。
- `Light -Area Network` PASS，258.743 秒；gameplay 71 项、terrain_maps、两张地图完整 ENet 与清理通过。网络日志目录 `.godot/validation/20261005-124044-25800/network`，覆盖版本拒绝、观战权限、生产战斗、兵营迁移、重连/重开、主机退出及两轮完整快照一致。
- 实际 Blender 启动通过，版本 5.2.2 LTS，日志 `.godot/toolchain-blender-version.log`。MCP 本轮验证路径注册和共享进程识别，没有额外启动 MCP 服务或执行 Blender 场景操作。
- Windows 导出退出 0，`.godot/toolchain-portable-export.log.err` 为空；`build/IronFront.exe` 为 131,750,416 字节，PCK 内嵌。导出启动验证返回 `EXPORTED_GAME_SMOKE_PASS`（存活 10 秒），该检查不代替导出包完整玩法测试。
- 最终 cleanup 确认项目进程和 24560/8766 端口无残留，共享 MCP 未停止。执行配置/脚本残留扫描仅有刻意构造的测试路径；已有文档历史路径保留。没有游戏逻辑/资产改动，未重复 Full/Visual/Performance；未提交或推送。
- 独立限制仍未修复：Windows 沙箱因本仓库根目录和 `.git` 的 ACL 更新失败而无法初始化，本轮经平台批准在沙箱外验证。此改造不修改 Windows 所有者/ACL、不关闭沙箱，不保证消除该故障产生的审批；项目本机规则需重启 Codex 后加载。

## 2026-10-04：3D 分支 Windows 导出

- `feature/3d-models` 通过固定 `run-godot.ps1 -Action export` 导出 `build/IronFront.exe`，退出 0，131,752,160 字节，PCK 内嵌；仅需分发 EXE。导出日志为 `agent_md/export_3d_20261004.log`，对应 `.err` 为 0 字节。
- SHA256：`5875A5D0AECD347069268CE4BD6B8705F793DB6D469A4AD334E92E501C8883C6`。
- `run-exported.ps1 -DurationSeconds 10` 返回 `EXPORTED_GAME_SMOKE_PASS`；仅验证导出程序启动并存活十秒，运行日志为空，不宣称完整玩法或联机回归通过。
- 导出入口最初无法找到 Godot，原因是安装根目录仍为旧路径；已在 `tools/codex/project-common.ps1` 加入当前 `D:\mysoftware\Godot_v4.7.2` 根目录及 console 候选路径，实际导出和原生 Godot 启动验证通过。
- 选择 `Light -Area Tooling`：脚本语法、Path 环境变量检查和原生 Godot 启动通过；整体结果失败，原因是 `.codex/rules/default.rules` 仍指向旧仓库 `D:\project\godot_project\rts_host_p2p_prototype`，无法匹配本仓库入口。此权限配置问题未修复；没有修改权限规则。无游戏源码/资源行为变更，跳过 Simulation、Visual、Full/ENet。
- 冒烟后固定 cleanup 停止测试游戏并确认项目进程和 24560/8766 端口无残留；交付前另执行 ReportOnly 复查。工具修改 diff 检查通过。未提交或推送。

## 2026-09-30：v4 兵营版本 Windows 导出

- 固定 run-godot.ps1 -Action export 成功，.godot/barracks-v4-export.log 显示 savepack DONE，stderr 空；build/IronFront.exe 为 131,752,000 字节，binary_format/embed_pck=true，无需配套 PCK。
- run-exported.ps1 -DurationSeconds 5 输出 EXPORTED_GAME_SMOKE_PASS；固定 cleanup 清理后无项目进程与端口，共享 MCP 未停止。
- 本轮无源码改动，不重复 Light/Full；玩法依据下方已通过的 Full、专用兵营规则和三地图实机测试。导出包验证范围为启动存活，不是导出环境完整玩法回归。

## 2026-09-30：v4 兵营游戏接入

- 选择 Full：本轮跨越模拟状态、快照协议、输入/UI、模型动画和占地；.godot/validation/20260930-144905-52004，260.403 秒，全部通过。运行 gameplay、arrival_formation、presentation、features、camera、action_bar、visual_models、soldier_locomotion、visual_performance（含荒漠）、terrain_maps、terrain_presentation、terrain_sample、terrain_sample_view、完整 ENet 和 cleanup。
- ENet 在 prototype/desert_quarry 两地图验证旧协议拒绝、观战权限、逐 RPC 连续 20Hz 快照、主客机生产战斗、兵营升空/迁移/部署、重连/重开/主机断线及两轮完整快照一致。最终目录检索无 SCRIPT ERROR 或 ERROR；既有 ObjectDB 退出警告尚未修复。
- .godot/barracks-flight-rules.log：45 项通过，包含队列/施工/权限、空地目标、状态快照及非法高度、飞行速度、停止、免费远距离部署、预约与到达复查、不可见/坡道拒绝、高台与低谷、落地正面出兵。荒漠矿区存在合法高台和低谷；样板区矿坑空间不足，按规则拒绝。
- .godot/barracks-integration.log：三地图实际渲染 PASS，覆盖 L/D/S/右键、行动栏、空中点选、12 格及非法确认、取消、快捷键冲突、旗帜多帧变形与落地/飞行机械姿态。stderr 为空；assets/concept_art/barracks-v4-game-*.png 共 12 张，落地、飞行和红格部署图目视复核。
- 编辑器资源扫描/导入完成且实际运行加载成功；.godot/barracks-flight-import-final.log 无 stderr，但批量导入编辑器退出仍超时（45 秒），未修复该生命周期问题，不能记作干净导入退出。残余项目进程已通过固定入口清理；共享 MCP 保留。
- 包装/导出路径未改，本轮未请求 EXE，跳过导出和 exported smoke；未提交/推送。Markdown 与代码 scoped diff 检查通过，仅有 Git CRLF 提示。

## 2026-09-30：底置推进器与收放落架 v4

- .godot/barracks-v4-build.log 最终 BUILD PASS：32,900 三角形、34 网格、三段动画、贴图内嵌、导出重载。97 个姿态检查占地、离地高度、脚垫与机身/喷口、喷口与机身、液压件与机身、转臂与喷口的 BVH 表面相交；连接铰链允许正常装配接触，未做完整物理求解。
- .godot/barracks-v4-render.log 最终 RENDER PASS：七个静态视角和两段 49 帧 APNG，由交付 GLB 的实际动画渲染。旗帜独立循环；静态图目视检查动力舱外壳、底部喷口与收纳脚垫。全部位于 assets/concept_art。
- .godot/barracks-v4-godot.log 最终 GODOT PASS：起飞/降落各 4 秒、旗帜 2 秒；实际动画播放检查先升再收、先放再降、坡道关闭与打开终点、落架内收坐标和旗帜独立 morph 变化，61 个带法线纹理的材质表面。三张 Compatibility 引擎截图。最终三个日志 stderr 均空。
- Light -Area Visual PASS，10.439 秒；运行 visual_models / soldier_locomotion / terrain_presentation / terrain_sample_view，清理确认无项目进程和端口。沿用套件中既有 ObjectDB 退出警告。没有玩法/网络改动，未运行 Full/ENet；没有运行模型替换，无须编辑器重导入；未导出 EXE。
- 正式 barracks.glb、ironfront_models.blend、simulation.gd、entity_visual.gd SHA256 未变化。HTML 本地资源链接做存在性检查，浏览器端交互与 APNG 播放未自动化测试。预览入口：assets/concept_art/兵营底置推进器预览-v4.html。

## 2026-09-30：兵营轻度写实 v3

- 最终构建 .godot/barracks-realism-build-final.log：BARRACKS_CLEARANCE、BUILD、REALISTIC_DELIVERY 全部 PASS。四推进器与主要装甲/动力舱 BVH 表面无相交（正常连接支架排除）；不代表做了全模型物理碰撞求解。
- 33,754 三角形/26 网格，作者坐标范围 [-5.1442,-3.4300,-0.0211] 至 [5.1442,3.9334,8.5050]，缩放 12 时在目标 128×96 范围；旗帜 13 个固定边顶点、半周期变形 0.24417、首尾误差 0。所有贴图嵌入 GLB、源文件打包，另交付主体 2K 和旗帜 512 的基础色/法线/ORM PNG。
- .godot/barracks-realism-render-final.log：六姿态/视图、24 帧 APNG、局部近景、中性/荒漠光照及同镜头前后对比 PASS。目视复核修正了表面颗粒过重、切角漏封板和前封板超长。
- .godot/barracks-realism-godot.log：Compatibility 实际渲染 PASS，62 个贴图表面及法线纹理有效，旗帜 morph 值随动画变化；四张引擎截图。Godot 画面与 Blender 棚拍仍有光照/阴影差异，未进行正式地图接入、海量建筑压力或浏览器端播放验证。
- Light Visual：.godot/validation/20260930-125243-84852，10.359 秒，四套件及 cleanup 全通过。已有 ObjectDB 退出警告保留；未动模拟/网络，不运行 Full/ENet；隔离 GLB 直接加载，不执行编辑器导入或 EXE 导出。
- 预览入口 10 个图片/链接文件均存在。运行兵营、共享源、simulation.gd、entity_visual.gd SHA256 与修改前一致。最终固定 cleanup 报无项目进程与端口，共享 MCP 不终止。

## 2026-09-30：兵营旗帜飘动

- .godot/barracks-flag-build.log PASS，stderr 空：34,998 三角形/26 网格；最大高度 8.505，XY 仍在 4×3 目标范围。GLB 重载后 MainFan 不存在，旗帜动画动作存在。
- 重载后采样帧 1/13/25/49：13 个旗杆侧顶点固定，半周期最大顶点位移 0.24417，首尾差 0；四种建筑姿态仍通过有限矩阵检查。数值在独立模型目录 validation.json。
- .godot/barracks-flag-render.log 六静态图及 24 帧/12fps APNG PASS、stderr 空；APNG 帧控制块数量检查通过。目视检查主视/飞行构图，没有浏览器实际播放验证。
- 四个运行文件 SHA256 未变；预览未接入游戏，因此不跑 Light/Full、导入、ENet 或导出 EXE。最终固定 cleanup：PROJECT_PROCESSES none、PROJECT_PORTS none，共享 MCP 保留。

## 2026-09-30：兵营入口简化复查

- .godot/barracks-v2-simple-build.log：PASS，36,440 三角形/26 网格，4×3 范围与导出重载检查通过，四姿态矩阵有限；stderr 空。
- .godot/barracks-v2-simple-render-fixed.log：六张 GLB 渲染 PASS、stderr 空。目视复查开门/关门外观，并在门扇 Y 从 2.38 内移至 2.25 后再次检查落地主视，解决打开的门板覆盖装甲表面的问题。
- 中文 PNG 直接保存两次失败（含沙箱外重试），改为同目录 ASCII 临时图与 os.replace 后默认沙箱内成功；底层原因未完全定位。六张图仍存原 v2 路径。
- 四个运行文件 SHA256 与修改前相同。验证仅覆盖离线样板，不运行游戏 Light/Full、导入、ENet 或 EXE；最终 cleanup 确认项目进程/端口为空，保留共享 MCP。

## 2026-09-30：4×3 军用机械兵营独立样板

- 固定 Blender 入口构建：.godot/barracks-v2-build-final.log 输出 BARRACKS_V2_BUILD PASS。独立 GLB 重新导入后 26 网格一致，落地/升空/飞行/部署四姿态矩阵均为有限值；最终 41,080 三角形。
- 包围盒作者坐标最小值 [-5.0442,-3.4300,-0.0224]，最大值 [5.0442,3.9263,6.5200]，预定缩放 12 时满足宽 128、深 96 的目标范围；细节记录在 assets/concept_art/barracks_mechanical_v2/validation.json。坡板底梁初始穿地通过缩短坡板和修正角度解决，最终最低点满足地面容差。
- .godot/barracks-v2-render-final.log 输出 BARRACKS_V2_RENDER PASS six GLB views；六张 1800×1200 PNG 逐张目视检查。修复共面骨架重叠、风扇叶片遮挡及后壁上方缺口后重渲染。图像来自实际交付模型，不代表游戏内截图。
- SHA256 对比确认 assets/models/barracks.glb、assets/models/source/ironfront_models.blend、scripts/simulation.gd、assets/art/entity_visual.gd 未变。新样板目录有 .gdignore，运行占地和资源未接入。
- 验证范围为离线模型几何、导出重载和静态姿态；不适用游戏 Light/Full、导入和 ENet，未测游戏性能或完整动画。最终 cleanup 报 PROJECT_PROCESSES none、PROJECT_PORTS none；共享 MCP 不终止。

## 2026-09-30：方案一可升空兵营实际模型

- 唯一运行资源 assets/models/barracks.glb 已替换，共享源 ironfront_models.blend 的旧兵营树已删除；其他 12 个根对象结构摘要不变。固定 Blender 入口两次构建成功，最终 25,872 三角形/12 网格，包围盒 7.62×6.85×5.71；候选 GLB 重新导入后网格数一致。游戏缩放 8，保持 64×64（2×2）占地及高度锚点 48，遵循用户保留夸张比例的选择。
- 通过固定入口单独运行资源导入。两次资源处理完成，编辑器退出分别超时 60/30 秒被终止；此退出问题未修复。后续最终 GLB 正常加载，通过视觉断言和真实 OpenGL 渲染，不能将导入进程描述为正常退出。
- 最终 Light Visual/Performance：.godot/validation/20260930-093140-120224，13.313 秒通过；包括 visual_models、soldier_locomotion、两地图 visual_performance、terrain_presentation、terrain_sample_view 及 cleanup。新增断言验证两门横向开启和停产关闭、新风扇转动、落地推进器保持关闭、占地/血条/阵营色，保留建设及选中圈检查。180 混合单位动态显示同步 6.43/6.39ms，CPU 指标不代表完整渲染帧率。
- .godot/mobile-barracks-preview-final.log：通过实际 produce 指令生产一名士兵并恢复 idle；与基地、士兵同屏展示真实游戏比例，截图 assets/concept_art/兵营模型-方案一-荒漠实机-v1.png。另五张图由同一最终 GLB 在 Blender 渲染，覆盖落地、背侧、升空、飞行底部、部署，未用 AI 替代实际模型。最终渲染和实机 stderr 为空。
- 预览修正：GLB 坡板使用四元数导致 Euler 赋值无效，改为明确 XYZ；喷焰整体缩放导致横向偏离喷口，改为固定 XY、沿 Z 缩放并补偿顶端高度；相机扩大取景避免裁切天线。最终目视复查通过。既有部分无界面套件退出 ObjectDB 警告仍存在，未在本轮定位。
- 无模拟/协议/UI 功能改动，不跑 Full/ENet 或其他无关区域；不导出 EXE。飞行移动和选址部署玩法未实现，当前仅模型分件与姿态。最终固定 cleanup 确认项目进程及端口为空，共享 Blender MCP 保留。未提交、未推送。

## 2026-09-30：高地边缘紧凑集结与 EXE 更新

- 缺陷：旧四列偏移接受崖下合法位置，失败后还向出发点修正，点击高地边缘会跨层分散。修复为地形连通平台区域内、点击点 128 世界单位范围的紧凑候选；验证体积、通路、占用及预约。容量不足保留意图等待，每单位每秒重试；战斗后恢复，停止/新命令释放预约；抵达后分离保持平台。
- Light 选用 Simulation/Visual/Camera/Performance/Network，覆盖模拟、模型与运动、相机拾取、规模性能和新的快照边界；未运行无关的 Presentation/Features/ActionBar 或完整 Full，资产未变不重复导入。最终功能套件见 `.godot/validation/20260930-073444-85588/`；该轮 ENet 的 20Hz 接收断言与渲染检查并行时失败，不能称整轮通过。停止并行引擎负载后，`.godot/validation/20260930-073716-25012/` 单独 Light Network 通过（214.840 秒），包含 gameplay、terrain_maps、两张地图各两轮完整 ENet、协议不匹配/旁观者权限/断线及完整快照一致性，未放宽断言。负载影响尚属推测。
- arrival_formation 回归通过：六人在高地四侧实际抵达、混合士兵/矿车进入矿坑、攻击移动、建筑占位、不可达命令原子拒绝、180 人溢出等待与预约保护、释放后补位、停止清理、快照恢复与非法区域拒绝。180 人分配 63.662ms；20 个逻辑帧分摊重试总 36.848ms、单帧峰值 3.234ms。此前 100 人分配超过 500ms，缓存候选及导航连通性并优先过滤占用后解决；这不是完整渲染帧率保证。
- `.godot/arrival-preview.log`：实际游戏右键输入和地表拾取，六人在第 431 渲染帧全部抵达点击平台，`ARRIVAL_PREVIEW PASS`，stderr 为空；停步截图 `assets/concept_art/highland-edge-arrived.png`。
- 导出 `.godot/arrival-export.log` 完成且 stderr 为空；`build/IronFront.exe` 为 130,685,072 字节，2026-09-30 07:42:15（本地），内嵌 PCK。固定入口 5 秒 EXE 启动检查通过；最终清理及 ReportOnly 无项目进程/端口残留，共享 Blender MCP 保留。协议 rts-terrain-4，联机双方必须使用新版。
- 限制：既有 world_visual_sync.gd 的朝向与 up 向量共线警告及部分无界面套件退出时 ObjectDB 警告未在本任务修复；未覆盖每种手工操作组合的观感验收。人工复验可选择六名士兵，分别右键高地边缘和矿坑边缘，确认最终停在点击的平台；空间不足时移走先到单位观察后续补位。

## 2026-09-30：垮腰修复与 EXE 更新

- 已确认缺陷及修复：连续转弯时旧落脚目标不随方向更新，外侧脚超出可达范围，骨盆被压低；现在持续预测落点、按弯道缩短步幅并平滑 20Hz 朝向变化。普通抬脚保留跨越支撑相位边界的时间，消除多拖脚一帧。并非单纯屏蔽骨盆下移或取消足底锁定。
- 修复前 .godot/gait-collapse-before.log：圆弧半径 25/50/100 最低骨盆分别 0.245/0.245/0.644，触发回归失败。最终 .godot/gait-tick-final.log：18 组圆弧全部通过，最低 1.0847，最大单帧下降 0.02281；直行/坡道/启停/校正/攻击断言仍通过，最大贴地误差 0.0502、接地漂移 0.000244。
- `Light -Area Visual,Performance` 通过（13.084 秒），日志 `.godot/validation/20260930-010957-55356/`：模型、运动、两张地图性能、地形展示和清理。180 混合单位动态显示同步 6.52/6.72ms。源码未改模拟、RPC/快照，不跑 Full/ENet；没有重新生成模型，因此不重复资产导入。
- 实机 `.godot/gait-collapse-render.log`：通过实际指令和寻路的圆弧路线最低骨盆 1.05091、最大下压 0.03662，`SOLDIER_PREVIEW PASS after`，stderr 为空；预览在 assets/concept_art/heavy-soldier-curve-*.png。180 纯士兵渲染平均 31.25ms、P95 51.14ms、CPU 平均 15.72ms，密集场景性能仍有明显波动，未达到稳定 60FPS。
- EXE：固定导出入口生成 build/IronFront.exe，130,673,616 字节，2026-09-30 01:11:44（本地），PCK 内嵌；.godot/gait-collapse-export.log.err 为空，5 秒启动检查通过。最终清理和 ReportOnly 确认无项目进程/端口残留，共享 Blender MCP 保留。
- 人工复验使用本次更新后的 EXE：在样板测试场拉近视角，让单兵持续沿弯线移动，再观察坡道与多人移动；重点看转弯换脚时腰部是否突降。测试证明已复现的连续转弯缺陷修复，不代表所有地形/拥挤组合均完成观感验收。

## 2026-09-30：重装士兵版本 EXE 导出

- 按用户要求通过固定 run-godot.ps1 导出 Windows Release 到 build/IronFront.exe，包含当前士兵模型和自然小跑改动；文件 130,673,088 字节，时间 2026-09-30 01:00:19（本地）。PCK 已嵌入，单个 EXE 可运行。
- .godot/heavy-soldier-export.log 显示 savepack 完成，stderr 为空；固定 run-exported.ps1 的 5 秒启动检查通过。最终 StopTracked/StopUntracked 及 ReportOnly 均确认项目进程和端口无残留，共享 Blender MCP 保留。
- 本轮仅导出，未改游戏源码，沿用上轮通过的 Light Visual/Performance，不重复 Full/ENet；启动检查不等同于完整游戏回归。未提交、未推送。

## 2026-09-30：重装士兵模型与自然小跑

- 资源：固定 Blender 入口构建成功（.godot/heavy-build.log，6174 多边形、16 骨骼）。单独执行 Godot import，资源导入完成但编辑器退出超过 35 秒，由入口终止；后续模型测试和真实渲染均成功加载新 GLB，不能将导入进程描述为正常退出。
- 最终源码验证：`run-validation.ps1 -Level Light -Area Visual,Performance` 通过，13.627 秒；日志目录 `.godot/validation/20260930-005235-16500/`。覆盖 visual_models、soldier_locomotion、原型/荒漠 visual_performance、terrain_presentation、terrain_sample_view 和 cleanup。
- 运动断言：30/60/144 FPS 下两秒显示距离均为 195（20Hz 显示插值落后一模拟帧）；50/100/150 速度比例、上下高地和矿坑、被挡原地停步、客户端校正不推进步频、传送/重置、90/180 度转向、攻击过渡及 3/5/12 帧短停再启动。读取实际骨骼而非控制器目标值；落脚最大水平漂移 0.000244、地面误差 0.0502 世界单位，腿长不拉伸；枪口局部逐帧位移最大 0.1343，低于 0.15。
- CPU 压力：180 混合单位的动态同步原型 7.43ms、荒漠 6.79ms；普通单位同步 1.41/1.43ms，均满足原测试预算。血条已有掉血格子与相机投影断言通过。
- 最终实机：`soldier_motion_preview.gd -Rendered` 输出 `SOLDIER_PREVIEW PASS after`，日志 `.godot/soldier-final-render.log`，stderr 为空。42 张基线/预览位于 `assets/concept_art/heavy-soldier-*.png`，其中新预览 36 张，覆盖平地、正面、高地、矿坑往返与转弯停步。
- 渲染性能限制：1280×900、RTX 5070 Ti、Compatibility、180 纯士兵移动时平均 22.90ms（约 44 FPS），P95 47.87ms，游戏 CPU 平均 14.73ms。密集单位场景尚未达稳定 60 FPS；本轮没有进一步改模拟、地形或渲染架构来追求帧率。
- 其他限制：部分无头套件退出仍报告一个 ObjectDB 实例未释放，断言与套件退出状态通过，该退出警告本轮未定位。早期测试出现过 user:// 日志访问错误，已用获授权固定入口完成重试；未修改安全或审批配置。
- 范围选择：未改模拟规则或 RPC/快照边界，因此未跑 Full/ENet；客户端校正由局部显示测试覆盖，未声称完成跨进程联机体验验收。本轮未更新 EXE，不执行导出/打包测试。
- 手动复验：从 Godot 运行项目（F5），选择荒漠样板测试场；拉近观察士兵沿平地移动、上下坡、连续转向，再以很短间隔停下和重新移动。重点观察落脚是否滑动、身体是否突然下沉或抬起、膝踝是否连续屈伸。现有 EXE 仍是旧构建，不能用它验收本轮动画。
- 进程清理：最终 `cleanup-project-processes.ps1 -StopTracked -StopUntracked` 确认项目进程/端口为空，共享 Blender MCP 三个进程保留。

## 用户复验：默认沙箱两次地图渲染

- 按用户要求使用 use_default，依次执行固定 run-godot.ps1 的 terrain_sample_view.gd -Rendered，日志分别为 .godot/sandbox-acceptance-first.log 和 .godot/sandbox-acceptance-second.log。
- 两次退出码均为 0，均输出 TERRAIN_SAMPLE_VIEW PASS failures=0，两个 .err 文件均为 0 字节；未发现 Path/PATH、重复键或脚本错误。
- 本轮无 require_escalated 请求或审批等待，固定清理入口同样在默认沙箱通过；无项目进程/端口残留，共享 Blender MCP 保留。
- 这是已修复入口的针对性复验，未改源码，不重复 Light/Full/ENet 或 EXE 导出；不将两次成功推广为所有未来命令均免审批。

## Path/PATH 启动兼容修复与用户验收

- 最终 Light Tooling 通过，3.055 秒：WRAPPER_SYNTAX、PROCESS_PATH_CHECK、PROCESS_PATH_NATIVE、GODOT_ARGUMENT_RULES、EXECPOLICY 和 cleanup。原生回归日志 .godot/path-native-regression.log 输出 Godot 4.7.2，stderr 为空；真实构造两项 Path 后经固定入口合并为一项、启动 Godot 并保存日志，全部环境值保持，测试后恢复原始进程环境。
- .godot/path-check-b.log 与 path-check-c.log 为两次不同日志名的实际 OpenGL 渲染检查，均 TERRAIN_SAMPLE_VIEW PASS failures=0、stderr 为空。所有调用均为默认沙箱，未要求 require_escalated。最终无项目进程/端口残留，共享 Blender MCP 保留。
- 仅修改启动工具和回归检查，采用 Light Tooling 加针对性渲染；不重复 Full/ENet/游戏玩法测试，不导出 EXE。未改 Codex 审批策略、系统环境变量或权限。
- 局限：本轮修复前的版本启动也成功，未直接复现历史启动异常；验证证明真实重复环境可被修复并启动 Godot，上游注入重复项的来源仍未知。EXECPOLICY 是显式指定项目规则文件的检查，不能单凭它证明当前宿主加载情况或承诺所有未来命令免审批。

用户可在项目目录重复运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\project\godot_project\rts_host_p2p_prototype\tools\codex\run-validation.ps1 -Level Light -Area Tooling
```

预期 PROCESS_PATH_NATIVE PASS、GODOT_ARGUMENT_RULES PASS、EXECPOLICY PASS 和最终 VALIDATION_SUMMARY 的 status 为 passed。此项自动构造异常环境，不需要手工修改 Windows PATH。

检查 Codex 审批体验必须让 Codex 在默认沙箱执行下面命令，然后仅将日志名 b 改为 c 再执行；手动终端运行只能检查程序功能，不能验证 Codex 的审批行为：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\project\godot_project\rts_host_p2p_prototype\tools\codex\run-godot.ps1 -Action script -Script res://tests/terrain_sample_view.gd -Rendered -LogFile .godot\path-check-b.log -TimeoutSeconds 150
```

验收：两次正常退出、对应日志均 TERRAIN_SAMPLE_VIEW PASS failures=0、.err 为空，且未因重复键申请沙箱外重试。运行结束执行固定 cleanup-project-processes.ps1 -StopTracked -StopUntracked。若未来仍弹审批，应记录具体命令和原因，区分环境异常复发与独立的权限边界。

## 2026-09-29：坡道分界优化版 Windows 导出

- 固定 run-godot.ps1 导出退出 0，.godot/ramp-boundary-export.log 无脚本/导出错误、stderr 为空；确认 sample_surface.gdc、sample_view.gdc、desert_sample 资源及 sample_surface.gdshader 已打包。
- build/IronFront.exe：130555640 字节，2026-09-29 23:33:50，资源内嵌。SHA256：92F87AB12E7D4A5B7402B713AC95A7D4C49DD3A497AE7A9A458A927C14BB5999。
- run-exported.ps1 存活 5 秒检查通过；cleanup -StopTracked -StopUntracked 及 -ReportOnly 通过，无项目进程/端口残留，共享 Blender MCP 保留。
- 本轮未改源码，沿用上一轮 Light Simulation/Visual/Camera 与实际渲染检查；不重复 Light/Full/ENet，EXE 本轮仅验证启动。未提交或推送；替代下面实现阶段未导出的历史状态。

## 2026-09-29：坡道与平地分界增强

- 最终选择 Light Simulation/Visual/Camera，.godot/validation/20260929-233020-142204，耗时 14.981 秒全部通过：gameplay 71 项、camera、visual_models、terrain_maps、terrain_presentation、terrain_sample、terrain_sample_view 及 cleanup。
- 新增断言覆盖：两侧 24 半径矿车净空、中段坡度稳定、端点坡度归零与高度连续、平路不受坡面遮罩影响、上坡/下坡的坡顶坡脚标识、装饰石整个占地避开通行核心。原平地可建造/坡面拒绝/陡崖不可穿越断言继续通过。
- 士兵与矿车分别实际往返高台/矿坑；两条绕行路线逐步检查模型高度与同一表面高度相差小于 0.01，保持士兵面向实际位移；两端连接及坡面屏幕点选误差小于 1 单位。
- 固定 run-godot.ps1 的 terrain_sample_view.gd -Rendered -Arguments:--ramp-before / --ramp-after 各通过，日志 .godot/ramp-boundary-before.log / ramp-boundary-after.log，stderr 为空。1920×1080 Compatibility 实机生成四个视角各一对 before-v2 / after-v2 PNG；已检查默认、远景及高台/矿坑近景，坡面色差及两侧轮廓更明确，车辙连续，无新增横向黑线或实体挡路。
- 所有图片位于 assets/concept_art/ramp-boundary-*.png；本轮未更改纹理图片，shader 和 tres 直接运行加载，因此无需额外资源 import。仅改单机样板区且未修改网络边界，跳过 Full/ENet；未导出 EXE、提交或推送。
- 清理确认项目进程及 24560/8766 端口无残留，共享 Blender MCP 保留。部分 headless 套件仍有既有 ObjectDB 退出警告；不将其标为本轮已修复。

## 2026-09-29：士兵朝向修复版 Windows 导出

- 固定 run-godot.ps1 导出退出 0，.godot/soldier-heading-export.log 无脚本/导出错误，stderr 为空；确认更新后的 world_visual_sync.gdc 与 entity_visual.gdc 已打包。
- build/IronFront.exe：130552040 字节，2026-09-29 23:01:22，embed_pck=true，可单独运行。SHA256：6E8895A311A657887F1DEEDCEEC8ECBC4594A80C8497AC68E350B49D2C0BD6A2。
- run-exported.ps1 存活 5 秒检查通过；cleanup -StopTracked -StopUntracked 与 -ReportOnly 通过，无项目进程/端口残留，共享 Blender MCP 保留。
- 本轮未修改源码，沿用上一轮 Light Visual 及实际 OpenGL 路线测试；不重复 Light/Full/ENet，EXE 仅做启动冒烟，未推送远端。此导出替代下面实现阶段“EXE 尚不包含修复”的历史状态。

## 2026-09-29：士兵跟随实际行进方向

- 最终 Light Visual 通过（8.503 秒），日志 .godot/validation/20260929-225604-133008，包含 visual_models、terrain_presentation、terrain_sample_view；直接检查同步后的模型正面方向，不由断言助手手动改朝向。
- 覆盖无路径保持原朝向、首次路径节点优先、实际避让位移、模拟帧间保持、停步、交战瞄准、目标移除后恢复移动朝向、客户端快照速度及反向位置校正、零速度、实体销毁/ID 复用/世界重置。
- 高台与矿坑各跑实际 command/step 寻路，要求存在超过 5 个方向偏离终点的绕行步，并逐步校验模型方向与位移点积大于 0.999，最终抵达目标 20 单位以内。
- 固定 run-godot.ps1 -Action script -Script res://tests/terrain_sample_view.gd -Rendered -Arguments:--heading-capture 通过，.godot/soldier-heading-render.log 无错误、stderr 为空。1920×1080 OpenGL 实机截图四张位于 assets/concept_art/soldier-heading-{highland,quarry}-{turn,ramp}-v1.png，已查看。
- 本次只有视觉层与测试变更，不修改模拟或快照；因此跳过 Simulation/Full/完整 ENet，无源素材变化故无需 import。按确认计划未导出/启动 EXE，已有 EXE 尚不包含这次朝向修复。
- 最终 cleanup -StopTracked -StopUntracked 与 -ReportOnly 均通过，无项目进程/端口残留；共享 Blender MCP 保留。部分 headless 套件仍有既有 ObjectDB 退出警告，此问题不在本次修复范围。

## 2026-09-29：荒漠样板区 1–8 项升级

- 开发验证选择 Light Simulation/Visual/Tooling，全部通过：原 gameplay、visual_models、terrain_maps、terrain_presentation，以及新增 terrain_sample / terrain_sample_view；wrapper 语法与 execpolicy 27 个允许 / 5 个负例通过。该阶段跳过其余 UI 和 ENet，因为交付前另执行 Full。
- 样板规则断言：7 单位/3 建筑/10000 资金、无 AI/胜负、全图可见、确定性生成、平面可建造/坡面拒绝、不可穿越崖壁、道路中心连续可通行。士兵和矿车通过实际 command/step 分别到达高台及坑底，切回普通地图恢复 AI/迷雾。
- 场景断言：菜单第三项、禁止样板建主机、实际 NetworkSession 快照入口拒绝样板、重开不重复地形、切图恢复正式规则、四处高低地/坡道屏幕点选误差小于 1 单位、运行时预览已导入。
- 实际 Compatibility/OpenGL，1920×1080、RTX 5070 Ti：初始场景平均 6.943 ms，P95 7.187 ms；180 单位静态显示 7.057 ms，P95 8.768 ms；180 单位运行平均 21.102 ms（约 47 FPS），P95 36.896 ms；独立逻辑 tick 平均 17.369 ms。该结果只代表本机短时测试，未作最低配置保证。
- 样板地形 129024 三角形，首次构建约 0.76 秒。测试命令为固定 run-godot.ps1，-Action script -Script res://tests/terrain_sample_view.gd -Rendered -Arguments:--capture。日志 .godot/sample-render.log；TERRAIN_SAMPLE_VIEW PASS；最终渲染轮次出现既有 ObjectDB 退出警告，无脚本或渲染错误。
- 固定视角 overview/highland/cliff/quarry/materials/gameplay/menu 共七张 PNG 位于 assets/concept_art；已查看并确认高低轮廓、岩壁碎石、道路、材质及菜单预览。菜单运行时图另在 assets/maps/sample/preview.png。
- 单独资源导入完成，日志 sample-import.log / sample-preview-import.log 中有 DONE；编辑器既有退出挂起通过超时/清理入口回收，未宣称 editor 生命周期修复。部分 headless / 实际渲染场景仍有既有 ObjectDB 退出警告，未修复该独立问题。
- Full 已通过，耗时 228.223 秒，日志 .godot/validation/20260929-223627-80592。全部 11 个本地套件通过，ENet 对 prototype/desert_quarry 分别完成协议不匹配、观察者权限、采矿、建造、生产、击杀、重连、重开、快照一致性和主机断线处理。导出独立执行，结果见下。
- 最后发现自定义着色器贴图没有自动生成 mipmap，已显式启用八张材质图的导入设置，并新增运行时 has_mipmaps 断言；重新导入完成，编辑器 45 秒退出超时由 wrapper 终止。该纯资源变更之后补跑 Light Visual（8.539 秒）及实机截图均通过，包括八张贴图 has_mipmaps 断言；远景密集闪点减少，不重复无关 ENet。

- Windows 导出退出 0，日志 .godot/sample-export.log，stderr 为空；确认样板配置、共享表面/渲染脚本、shader、八张材质和运行时预览均打包。build/IronFront.exe 为 130550632 字节（约 124.5 MiB），embed_pck=true，无需另配 PCK。
- EXE SHA256：33A13AE8FA8408D5E83A9CD1E3CB96CDC99C845F1FB0ACC7BAFD46C5073C3CAF。run-exported.ps1 检查启动存活 5 秒通过；EXE 内未另跑完整交互回归，交互证据来自相同源码的实际 OpenGL 场景测试。
- 最终 cleanup -StopTracked -StopUntracked 和独立 -ReportOnly 均通过，项目进程及 24560/8766 端口无残留；共享 Blender MCP 进程仅报告、不终止。Git 限定源码差异检查通过，本轮未提交/推送。

## 2026-09-29：Windows 沙箱文件编辑权限修复

- 仅修复项目 .git 顶层所有者，CodexSandboxOffline → happydog。管理员脚本返回 PASS、DaclUnchanged=true、Recursive=false，原 ACL/所有者备份与结果 JSON 均在 agent_md/。
- task_plan.md 的 HTML 注释通过 apply_patch 修改后读回，再通过 apply_patch 还原；原计划文本不变。两次操作直接完成，未申请沙箱外执行。
- 沙箱日志 C:/Users/happydog/.codex/.sandbox/sandbox.2026-09-29.log：修复前 21:36:43 为 open deny ACL target for update / setup error；修复后 21:49:50 为 applied deny ACE to protect ...\.git / errors=[]。
- 初始化后再次逐条比较 ACL：原条目全部保留，Codex 自动新增当前沙箱 SID 的两个 Deny 条目及继承 Allow 条目。原始备份与最终 DACL 不再逐字相等，所有者修复步骤本身未改 DACL。
- 本轮只修复文件系统权限和记录诊断，无游戏源码/工具链改动，不运行 Light/Full、ENet 或导出；未启动游戏、Godot、Blender 或服务。

## 2026-09-29：荒漠地图 Windows 导出

- build/IronFront.exe：2026-09-29 21:02:45，110,159,312 字节（约 105 MiB）。binary_format/embed_pck=true，可单独分发 EXE。
- 固定入口 run-godot.ps1 导出退出 0；.godot/desert-export.log 无 SCRIPT ERROR/ERROR，stderr 为空。包含 desert_quarry 配置、地图脚本和 desert_surface 着色器。
- SHA256：9F1C6EC39BA580306BF4817083E5F014CBCB4C511C8FBBDC2F1BEE6B37782BE3。
- run-exported.ps1 -DurationSeconds 5 返回 EXPORTED_GAME_SMOKE_PASS；只证明启动及五秒存活。用户目录运行日志因沙箱拒绝读取，未据此声称运行日志无错误。
- cleanup -StopTracked -StopUntracked 和单独 ReportOnly 均确认项目进程/24560、8766 端口无残留；共享 Blender MCP 保留。
- 本轮没有源代码改动，不重复 Light/Full/ENet，沿用下方已有验证；未提交或推送。
- 已知预览限制：assets/concept_art/.gdignore 阻止菜单引用的概念图导入，导出中无预览图；地图本体正常打包。此限制未修复。

## 2026-09-29：荒漠矿区与模块地图

- Full：`.godot/validation/20260929-204213-5764/`，总计约 224 秒，全部阶段通过。包括 71 条 gameplay 检查、presentation/features/camera/action_bar/visual_models、双地图 180 单位性能、terrain_maps、terrain_presentation、两张地图完整 ENet 及清理。
- 双地图 ENet：`network/prototype/` 与 `network/desert_quarry/` 均通过协议不匹配拒绝、观战权限、经济、生产、战斗、胜负、断线重连、重开、主机退出与完整快照相等检查。
- 最终补验：`.godot/validation/20260929-205535-12824/`，Light Simulation/Presentation/Visual/Camera/Performance/Tooling 全部通过。荒漠 180 单位平均逻辑帧 19.91 ms，视觉同步 1.89 ms；原型平均逻辑帧 16.29 ms。记录为本机测量，不等同于所有硬件 FPS 保证。
- 地图专项覆盖高度/旋转对称、上坡和下矿坑、崖壁拒绝穿越、道路中心线可通行、坡道拒建/高台建造、矿区连通、配置重叠/坡道接缝拒绝、遮挡射击及碉堡、攻击移动释放遮挡目标、上下高地视野、地图身份及内容不匹配拒绝。
- OpenGL 实机专项：`.godot/terrain-render.log`，TERRAIN_PRESENTATION PASS，无脚本错误。验证高台/坡道/坑底点选、贴地表现、标记法线、地图切换与重开。截图：[总览](../assets/concept_art/desert-quarry-overview.png)、[高台](../assets/concept_art/desert-quarry-highland.png)、[矿坑](../assets/concept_art/desert-quarry-pit.png)、[开局实机](../assets/concept_art/desert-quarry-gameplay.png)。
- 导入：`.godot/terrain-final-import.log` 扫描及导入完成，错误日志为空；编辑器退出超过 60 秒后被入口终止。后续导入资源加载及渲染通过。部分 headless 测试有单个 ObjectDB 退出泄漏警告，保留说明。
- Tooling：PS1 语法及 27 个 allow 正例、5 个 deny 反例通过；ToolchainSmoke 未重复执行，Godot 已由游戏验证覆盖。最终 Light 不重复 ENet，因为最后改动仅为外观、道路绘制、点选和配置验证；协议边界已由 Full 覆盖。
- 未导出 EXE、未推送；本任务无发布交付要求。项目进程/24560、8766 端口清理通过，共享 Blender MCP 进程按规则保留。

## 2026-09-29：工具执行授权定向验证

- `run-validation.ps1 -Level Light -Area Tooling`：退出 0，793ms；所有工具 PS1 语法通过，实际桌面版 Codex CLI 完成规则检查。
- 九个固定入口 × 三种 PowerShell 名称：27 个 allow 正例；原始 PowerShell、原始 cmd、未列入白名单的脚本、外部同名脚本、近似路径：5 个反例均未匹配 allow。只做规则求值，不执行反例命令。
- 参数边界：Light 不传 Area、Light 传 Unknown、Full 传 Tooling，均退出 1 且返回预期参数错误；单 Area 的 Light Tooling 正常运行。
- 范围差异检查通过；普通 MD/PS1 使用 apply_patch 编辑成功，没有为这些编辑请求沙箱升级。仅受保护的 `.codex/rules/default.rules` 更新走了平台授权。
- 不运行 Simulation、Visual、ENet、导出或 ToolchainSmoke：仅权限规则/工具验证改变，无游戏行为或服务启动，不需项目进程清理。
- 限制：仅验证项目规则文件，不声称覆盖全局/管理规则或证明当前会话已加载；重启 Codex 后采用新规则。未更改 `.codex/config.toml` 或任何 AGENTS.md，未开启全盘访问。

## 2026-09-29：工业装甲鼠标版本 Windows 导出

- 已重新导出 `build/IronFront.exe`，2026-09-29 19:01:33，110,131,480 字节（约 105 MiB）。PCK 内嵌，只需分发 EXE。
- 导出退出 0，stderr 为空；打包日志包含五种 cursor PNG 导入资源、cursor_controller 与 destination_marker，包含本轮鼠标及目的地效果。
- SHA256：`28870F67984FD427680A938F2DAD54326F26194CF18C23F7CDD9D6BC50870D0A`。
- `run-exported.ps1 -DurationSeconds 5` 返回 `EXPORTED_GAME_SMOKE_PASS`，仅证明 EXE 启动并存活五秒，不代替完整玩法验证。随后停止冒烟进程，cleanup 与 ReportOnly 确认项目进程/端口均无残留，共享 MCP 未停止。
- 本轮只导出交付，不改源码；沿用前一轮通过的 Light Simulation/Presentation/Visual/Camera/ActionBar/Tooling 和真实硬件光标验证，不重复 Full/ENet。未提交或推送。

## 2026-09-29：工业装甲鼠标与目的地反馈

- `Light -Area Simulation,Presentation,Visual,Camera,ActionBar,Tooling` 全部通过：gameplay、presentation、camera、action_bar、visual_models、wrapper syntax/execpolicy 与 cleanup；首次汇总约 7.1 秒。
- `tests/cursor_checks.gd` 接入现有 presentation/visual_models 套件：覆盖五状态、模式优先级、UI/菜单/旁观者/胜负、迷雾不可泄露、兼容单位、有效/无效建造和采集、无选择不产生标记、16 个上限、稳定 ID、两种几何/配色、0.18/0.35/0.52/0.70 秒阶段和独立透明度、销毁。
- 单独 import 日志确认五张 PNG 导入完成；编辑器仍有既有的退出超时，30 秒后由 wrapper 终止。后续资源加载与实际渲染均成功，未将超时宣称为正常退出。
- 实际 OpenGL 窗口通过 `tests/cursor_preview.gd` 检查真实悬停、A 键进入攻击模式、无效采集切换；`CURSOR_RENDER_PREVIEW_PASS`，stderr 为空。输出 [光标原尺寸与放大对照](../assets/concept_art/cursor_runtime/cursor-assets.png)、[初始落点](../assets/concept_art/cursor_runtime/destination-000.png)、[确认落点](../assets/concept_art/cursor_runtime/destination-035.png) 及淡出/相机变化帧。
- `inspect-cursor.ps1` 使用 Win32 读取前台 Godot 的真实硬件光标，不以场景截图代替：default/select/move/attack/blocked 全部 40×40，热点分别为 (9,6)/(9,8)/(11,10)/(20,20)/(13,9)。原生图保存在 `.godot/cursor-native/`。
- 实机探针初次选择单位 3 的地面投影落入底部 HUD，正确返回 default；改选地图内的单位 6 后整条原生状态链通过，未改变游戏的 HUD 优先级。
- 定向 headless 日志有一个 AudioStreamGeneratorPlayback 退出泄漏警告，之前的 `.godot/base-visual-tests.log.err` 也有同类 ObjectDB 警告；本任务未修复音频生命周期问题。新实际窗口预览在退出前释放场景，未出现该警告。
- 未运行 Full/ENet，因为未改命令路由、模拟、RPC 或快照；未导出 EXE/运行导出冒烟，因为本次没有请求交付二进制。
- 资源由内置 imagegen 生成，源图与 [完整提示词](../assets/concept_art/cursor-production-prompts.txt) 保存在概念图目录；正式 PNG 位于 `assets/ui/cursors/`，仅通过 Godot 工具脚本做机械裁边和缩小。

## 2026-09-29：新基地版本 Windows 导出

- 已按用户请求导出 `build/IronFront.exe`，含指挥中心 v2 模型与动画；文件大小 110106648 字节，2026-09-29 14:15:30 生成。
- 使用 Windows Desktop release preset，`embed_pck=true`，可单独分发 EXE。
- 导出日志无 stderr；`run-exported.ps1 -DurationSeconds 5` 返回 EXPORTED_GAME_SMOKE_PASS。
- 冒烟仅确认程序存活；AppData 运行日志读取被沙箱拒绝，未据此宣称运行日志无错误。测试后清理及 ReportOnly 均确认无项目进程或端口残留。
- 本轮只执行导出与启动冒烟；源码的 Light Simulation/Visual/Tooling 已在模型实现阶段通过，无新增源码变更，未重复运行 Full/ENet。

## 2026-09-29：指挥中心 v2 基地

- 最终命令：`run-validation.ps1 -Level Light -Area Simulation,Visual,Tooling`。
- 最终摘要：passed；gameplay passed（2821ms）、visual_models passed（539ms）、tooling passed（538ms）、cleanup passed（463ms）。Tooling 语法通过；本机 PATH 没有 codex，execpolicy 检查跳过；独立 toolchain smoke 未请求。
- 覆盖：160×160 占地、相邻放置、阻挡、模型范围与高度、预览和选择环、七段施工边界/反向进度跳转/完工复位、六灯向下扫描/间歇、蓝红窗口与塔灯、实例间材质和动画相位隔离。
- 实际 GPU 验证：`run-godot.ps1 -Action script -Script res://tests/base_preview.gd -Rendered`，OpenGL Compatibility / RTX 5070 Ti，输出 36 帧施工、24 帧扫描和红方静帧；stderr 为空。预览位于 `assets/concept_art/base_animation/index.html`。
- Blender 预览：`assets/concept_art/基地-模型预览.png`；模型约 6136 三角面、31 mesh，本地边界 4.9×4.9×3.37。原 blend1 的大小与修改时间保持不变。
- 导入限制：编辑器日志确认 base.glb 重导入结束且无脚本错误，但编辑器没有自行退出，wrapper 超时终止。新 GLB 已通过后续节点契约、实际渲染及运行时测试确认载入。
- 未运行 Full/ENet/导出：本次未改网络快照、命令边界及打包路径，未要求 EXE；只选择受影响区域。进程清理确认项目进程和端口均无残留。

更新时间：2026-09-29

本文件只保留当前验证证据、最近基线和可复用入口。实现历史见 [dev_log.md](dev_log.md)。

## 2026-09-29 A 键攻击移动修复

- `Light -Area Simulation,Presentation,Visual` 通过：gameplay、presentation、visual_models 和最终 cleanup 均为 passed，总耗时约 5.4 秒。
- gameplay 当前为 66 项检查 / 0 项失败；新增覆盖连续沿途交战、目标死亡后恢复以及抵达原始目的地。
- presentation 通过真实根视口输入覆盖一次 `A` 只开启一次攻击模式、地面点击生成攻击移动、命令后选中保持和一次性模式关闭。
- visual_models 覆盖攻击移动交战时的追击/攻击动画、临时目标朝向，以及释放目标后恢复原目的地方向。
- 12 个本次修改文件的限定 `git diff --check` 通过；5 份 Markdown 的 UTF-8、NUL 和本地链接检查通过。
- RPC、命令格式、快照字段和 `Simulation.VERSION` 未改变，因此未运行 ENet；打包路径未改变，因此未导出或执行 EXE 冒烟。

## 2026-09-29 两级开发验证

- `Light` 参数拒绝通过：缺少 Area、Full 携带 Area、未知 Area 均返回非零；逗号分隔 Area 会去重。
- `Light -Area Simulation,Tooling,Simulation` 通过，只运行一次 tooling 和 gameplay，随后执行一次完整清理；摘要状态为 passed，总耗时约 4.8 秒。
- `Full` 通过：gameplay、presentation、features、camera、action_bar、visual_models、visual_performance、完整 ENet 和最终清理均为 passed；总耗时约 110 秒。
- ENet 覆盖协议不匹配、观战权限、双 guest、经济、生产、战斗、胜负、快照一致性、重连和主机退出。
- 网络日志写入 `.godot/validation/<run-id>/network/`；Git 跟踪的 `build/verification` 网络日志未被修改。
- 固定 PowerShell wrapper 增至 8 个，Parser 与 execpolicy 自检通过；裸 PowerShell 仍不获授权。
- `--editor --quit` 与专用 `--import` 均完成扫描后停留在编辑器生命周期，无法自动退出；两级验证不再自动 import，并为同步 Godot 阶段保留超时保护。该导入限制尚未修复。
- 按两级规则未执行 Windows 导出或 EXE 冒烟，因为本次没有修改打包、启动或交付路径。

## 2026-09-29 工作流精简

- `verify-permissions.ps1` 默认静态检查通过：全部 PowerShell wrapper 语法有效，8 个固定入口均命中 allow 规则，裸 `Get-Process` 不命中。
- `powershell.exe`、`powershell` 和系统绝对路径三种执行名称均命中同一个候选数组规则；不带 `-ExecutionPolicy Bypass` 的旧调用不再命中。
- `.codex/rules/` 只保留一个规则文件；重复的 Windows execution-policy 文件已删除。
- `run-mcp.ps1 -Action stop` 按预期被 ValidateSet 拒绝；服务停止统一使用完整清理 wrapper。
- 遗留的空 `.codex/runtime/processes.json` 和目录已删除；当前进程台账继续使用系统临时目录。
- 12 份项目 Markdown 的 UTF-8、NUL 和本地链接检查通过；活动工作流无已知失效引用；限定 `git diff --check` 通过，仅有既有 LF/CRLF 提示。
- 本次未启动 Godot、Blender 或游戏，未运行玩法、ENet、导出或 EXE 冒烟测试，因为游戏运行时、网络协议、资产和打包路径未改变。

## 最近基线

| 类别 | 入口/范围 | 结果 | 日期 |
| --- | --- | --- | --- |
| 玩法 | `tests/gameplay.gd` | 66 项检查 / 0 项失败 | 2026-09-29 |
| 表现与视觉 | presentation、visual_models、features、camera、action_bar | 通过 | 2026-09-29 |
| 性能 | `tests/visual_performance.gd`，180 个单位 | 阈值检查通过 | 2026-09-29 |
| 多人联机 | `tools/codex/run-network.ps1` | 协议、权限、双 guest、快照、重连和主机退出通过 | 2026-09-29 |
| Windows 导出 | 嵌入资源 EXE | 无界面导出退出 0，EXE 存活检查通过 | 2026-09-26 |
| 工具工作流 | 8 个固定 PowerShell wrappers、两级验证和单一 execpolicy | 静态及 Light/Full 检查通过 | 2026-09-29 |

## 常用验证命令

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/codex/verify-permissions.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/codex/verify-permissions.ps1 -ToolchainSmoke
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/codex/run-validation.ps1 -Level Light -Area Simulation
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/codex/run-validation.ps1 -Level Full
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/codex/run-godot.ps1 -Action version
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/codex/run-network.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/codex/run-godot.ps1 -Action export -Output build/IronFront.exe
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/codex/cleanup-project-processes.ps1 -StopTracked -StopUntracked
```

具体 Godot 测试脚本位于 `tests/`；网络测试在默认路径不可用时传入 `-GodotPath`。验证按 [AGENTS.md](AGENTS.md) 的风险分级规则选择。

## 解释规则与限制

- “通过”表示对应脚本退出码为 0 且没有失败项，不等同于 MCP 测试套件已经注册。
- 性能测试接近阈值时必须独立重跑并记录波动。
- 导出的 EXE/PCK 必须按项目发布规则成对处理；当前配置使用嵌入资源。
- MCP 测试套件发现当前返回 0 个套件，测试仍依赖直接脚本入口。
- 默认 Godot/Blender 路径仍依赖当前机器；Godot 可通过 wrapper 的 `-GodotPath` 显式指定受信安装路径。
- 当前无界面 Godot import 完成扫描后不会自行退出；源资产变更需单独处理导入并检查结果，不能用现有 Light/Full 代替。
- Git LFS 临时目录可能在受限环境报 `Access is denied`，会影响二进制 diff 读取。
