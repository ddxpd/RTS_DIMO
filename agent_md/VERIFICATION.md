# 验证索引

## 2026-10-13：美术 Git LFS 迁移

- 125个正式二进制文件、392279696字节全部核对SHA256、长度及HEAD指针内容；`git lfs fsck`通过。该统计包括二进制.res，不包括SVG/文本场景，与此前美术总量统计口径不同。
- `run-structure.ps1`1064项通过；origin/main仍为HEAD祖先，个人配置哈希未变，concept_art/.local/.godot/EXE没有被跟踪。
- 仅迁移3个未发布提交；两个backup分支保留本地恢复点，不上传。首轮Git元数据写入受沙箱拒绝，平台授权后成功；此前TLS故障本轮fetch已恢复。
- 本次不改变资源内容或游戏逻辑，不重复Light/Full/ENet、不导出EXE；此前Presentation/Tooling验证仍适用。远端下载验证待推送后执行。

## 2026-10-13：运行美术依赖边界

- 结构检查修复前失败项仅`main.gd -> assets/concept_art/desert-quarry-overview.png`；复制正式资源并修正引用后1064项通过，扫描运行脚本/场景/资源文本、Git忽略状态与全部模型GLB外部图片/缓冲区。检查覆盖静态资源路径与正式资产，不声称任意动态字符串可被静态证明。
- 预览源和副本SHA256一致，副本与.import文件不受Git忽略；它们目前待提交，远端尚未获得本轮修复。`.godot/runtime-art-boundary-import.log`导入通过、stderr空；菜单回归确认预览纹理存在且使用正式maps路径。
- Light/Presentation,Tooling最终`.godot/validation/20261013-115713-34172/`全通过，24.201秒，包括结构、工具、界面、Forward+ HUD82项、音频47项和cleanup。首次113949受沙箱日志/证书/Codex临时目录访问限制，获准固定入口重跑通过。
- 仅资源依赖和界面显示变化，未运行Full、ENet或EXE导出；未在另一台电脑做安装验收。保留现有两个工具服务及共享MCP。

## 2026-10-13：本地模拟审计目录

- `.godot/simulation-audit-path.log`：2023状态匹配原冻结基线，`--audit-before`成功写入`.local/simulation_audits/current-before.bin`并读回与完整内存状态比较一致，stderr空。没有重录或修改`tests/fixtures/`。
- 13份历史文件从`.godot/`迁移到新目录，迁移前后SHA256逐项一致；新目录有`.gdignore`。`git check-ignore -v`确认快照/报告被忽略，`git ls-files .local/simulation_audits`为空。
- Light/Tooling最终passed（5.102秒）：结构629项、包装器语法、路径与进程环境、参数规则、27允许/7拒绝规则用例及cleanup。首次运行被沙箱Codex临时目录访问限制阻断，批准固定入口重跑通过；可选完整工具链smoke未启用。此改动仅涉及测试输出，不运行Full、ENet或模型导入。

## 2026-10-12：基地模型占地对齐、兵营去旗

- `.godot/barracks-no-flag-build.log`三档7758/3589/1587三角面、每档三个杆件移除断言、97姿态净空通过，生产LOD0仅Landing/Takeoff动画；原带旗纹理动画基线未修改。`.godot/base-size-no-flag-import.log`资源导入成功，stderr空。
- Light/Visual：`.godot/validation/20261012-235756-46976/`全部13专项、629项结构检查及cleanup passed，50.293秒，错误日志为空。包括GAIA资产213项实测(320,144,192)、模型和选择框、兵营航向/集成、69项建造显示及其他Visual回归。首次235208整轮受沙箱user日志/证书/地形保存访问限制，不计为通过；随后获准重跑。
- `.godot/base-size-review.log`Forward+无失败，已查看`assets/concept_art/gaia_command_base/12-buildings-same-scale.png`和`13-buildings-top-scale.png`：三建筑共用正交相机尺度，基地320×192、卸载站128×128，兵营无旗杆且屋顶完整。`.local/balance_designer/portraits.log`七张缩略图刷新通过。
- 基地改变的是Godot组件中的模型显示缩放，原GLB/Blender网格坐标保持；三档、嵌套挂点和独立灯光同步，高度及逻辑占地未变。未改网络边界，不执行ENet；无热路径扩展，不执行Full性能压力；无交付请求，不导出EXE。

## 2026-10-12：所有建筑统一四角标记

- 验证等级：`Light -Area Visual`，通过，53594ms；结构审计629检查，以及visual_models、build_footprints、soldier_locomotion、soldier_rig、mobile_infantry、mobile_impact、terrain_components、terrain_presentation、terrain_sample_view、barracks_heading、barracks_integration、gaia_command_base、hover_harvester全部通过。
- 新增回归覆盖四类建筑角标尺寸、32顶点/24三角面、边中段开口、2.4固定线宽、忽略圆半径、同类网格复用和实例独立显隐；兵营升降/插值转向时维持水平并跟随建筑。
- `.godot/building-marker-measure.log`记录模型实际包围范围；`.godot/all-building-markers-preview.log`记录Forward+ / RTX5070Ti真实渲染及`ALL_BUILDING_MARKERS_PREVIEW_PASS`，stderr为空。渲染脚本同时检查四建筑多选与逐一单选时显隐正确。
- 实际截图：`assets/concept_art/selection_markers/all-buildings-c-overview-v1.png`，以及`base-c-unified-v1.png`、`barracks-c-unified-v1.png`、`refinery-c-unified-v1.png`、`bunker-c-unified-v1.png`。总览和三类新角标近景已人工查看，后角自然受建筑/环境遮挡。
- 本次仅修改程序化选择标记及视觉断言，无模型源资产变化，无需重新导入；玩法/网络协议/打包未改，跳过Full、ENet和EXE导出。固定进程清理保留原有47508/34692服务及共享Blender MCP。

## 2026-10-12：基地C方案四角标记

- Light -Area Visual全部通过，52172ms，包含structure与13视觉套件；第一次仅新AABB高度断言失败，因平面网格高度由引擎补为0.00001，已改为XZ尺寸+薄平面容差并复验。
- 最终文件复核`.godot/selection-c-models-final.log`：VISUAL_MODELS_TEST failures=[]；`.godot/selection-c-preview-final.log`：Forward+ RTX5070Ti、SELECTION_C_PREVIEW_PASS，两份stderr为空。实际标记AABB为(-152,0,-88)，尺寸(304,0.00001,176)。
- 三张实机图已目视，四角完整形状见俯视图；斜视下保留建筑正常遮挡。无模型源文件变更，不执行重导入；无玩法/网络边界变更，Full/ENet跳过；未请求二进制交付，EXE导出跳过。

## 2026-10-12：卸载站4×4内嵌通道

- 模型：`.godot/depot4-build.log`三档14495/8324/1076三角面及边界断言通过；`.godot/depot4-import.log`导入通过。`.godot/depot4-preview.log`Forward+渲染通过，正面和俯视截图已检查，全部模型位于128×128占地内。
- Light/Simulation,Visual：`.godot/validation/20261012-225910-45588/`完整27专项passed，103.190秒，结构审计629项与cleanup通过，无ERROR/SCRIPT ERROR。包括双泊位812项、建筑484项、建造显示69项、模型/选择圈、采矿/移动/生产/战斗等回归。
- 确定性：新`tests/fixtures/simulation_systems_v14_depot4.json`2023状态独立重放通过，旧compact_depot及更早轨迹保留。`.godot/depot4-baseline-audit.json`记录AI671状态变化、mixed901状态变化；flight301/reset120全部一致。尺寸改变导致格心吸附和AI摆放变化。捕获阶段曾出现沙箱用户日志/证书错误；最终获准的整轮独立重放无错误。
- 百科：`.local/balance_designer/test.log`90项/59字段通过，涵盖内部通道不重复计数、草案尺寸变化提示及真实浏览器显示。7张模型缩略图刷新；本地服务revision7/stale=false，128×128、两处32×64通道、internalDockPads=true；原方案ID/名称/覆盖值/冲突/历史逐项一致。
- 范围限制：矿车半径48不变，只在入口外直接卸矿，尚不驶入1格宽通道。未运行Full性能压力、完整ENet或EXE导出，因为网络契约和打包路径未变；卸载状态快照往返仍有直接回归覆盖。

## 2026-10-12：紧凑矿石卸载站

- 模型：`.godot/compact-depot-build.log`三档14775/8339/1024三角面、几何边界断言通过；`.godot/compact-depot-import.log`导入通过。`.godot/compact-depot-preview.log`Forward+通过，已查看`assets/concept_art/ore_depot/forward_lod0.png`和`top.png`。
- Light/Simulation,Visual：首次`.godot/validation/20261012-222005-47088/`被沙箱用户日志/证书/测试存档权限影响；获准重跑`.godot/validation/20261012-222724-46300/`27专项中26项通过，仅通用玩法夹具入口被主基地阻挡。修正该夹具后`.godot/compact-depot-gameplay-all.log`73项通过、stderr空；未将之前失败的整轮摘要标成通过。
- 核心专项：双泊位780项、建筑网格484项、建造显示69项、模型LOD/包围盒检查通过。2023状态的新冻结轨迹通过；旧base_only轨迹原样保留，`.godot/compact-depot-baseline-audit.json`列明AI与mixed变化，flight301帧和reset120帧完全不变。
- 百科：88项通过；新摘要显示主体5×4、两处1×1、共22、外接5×5格。七张缩略图重生成，本地服务revision6/stale=false，方案ID/名称/覆盖值/冲突/历史刷新前后一致。
- 未运行完整ENet、Full性能压力或EXE导出：本轮未改变RPC、快照字段或打包路径；卸载状态有直接快照往返回归。保留此前性能门槛波动记录，不作性能全绿声明。

## 2026-10-12：目录与核心代码整理

- 迁移371个文件；main 1531→1045行、simulation 781→475行、world_visual_sync 736→217行。保持RPC地址、协议14、代理属性与模拟顺序，职责进入统一定义、快照校验、显示子模块和共享RPC处理。
- 保留性：`run-structure.ps1 -PreservedManifest .local/structure_before/preserved_sha256.json`最终706项通过，78项资产/源文件/冻结轨迹SHA256不变；另比对源码包，129个UID文件不变。最终导入`.godot/structure-final-import.log`的stderr为空。首次迁移导入有旧缓存文件警告，重新导入后消失。
- 确定性：2023个状态与`simulation_systems_v14_base_only.json`一致；没有重录或覆盖冻结轨迹。
- Full：`.godot/validation/20261012-195814-47056/`执行34个自动专项，该轮性能及旧采集夹具失败，Full **未全绿**，ENet如实跳过。采集夹具随后修正为允许离开矿区/泊位等待期间的idle，`structure-harvester-final.log`418项通过；其余32个功能专项在该轮通过，包含Forward+ HUD82项和真实音频47项。
- 未解决的性能限制：168单位动画同步8.600ms（门槛8ms）、模拟25.629ms（门槛25ms）；前一轮为7.944/24.041ms，通过但不稳定，不能据此宣称Full通过。保存的旧显示代码与新代码隔离对照为7.976/7.841ms，未见明显显示开销增加；该隔离夹具关闭自动处理，不等同于常规压力场景。没有提高阈值、减少单位或把压力测试移出Full。
- 联机补验：`Light -Area Network`，`.godot/validation/20261012-200255-40788/`全通过，148.504秒。包含玩法、泊位、即时命中、地形与完整ENet，协议拒绝、旁观权限、采矿容量、相邻格建造、生产、兵营迁移、攻击、重开和断线处理通过，两轮完整快照一致。
- 工具：Light Tooling通过，包括包装器语法、注册/迁移、PATH环境、27个允许和7个拒绝规则用例。Blender5.2.2实际导入机动兵v5→v3→v2制作链通过；源文件图像审计33个已打包贴图、0个外部缺失，没有执行完整资产重建。
- 网页：数值工具独立安装依赖，72项/59字段通过；美术库198项通过，含路径身份、标签/关联、封面、浏览器与移动布局。16个内嵌模型封面成功，3个外部贴图GLB明确跳过。检查代表截图后按本轮清单回收18张临时图片。
- 用户数据：美术库已有20个迁移路径沿用原ID，旧元数据/分类/个人导入记录一致；数值草案ID、名称、覆盖值、冲突和历史不变，刷新到revision4、stale=false。8810/8811服务已恢复。未导出EXE、未提交或推送；完整资产重建、手工预览与额外性能探针未执行。

## 2026-10-12：普通士兵停用与双方仅基地开局

- 最终选择Full：`.godot/validation/20261012-174103-40112/`，24套源码测试、完整ENet和cleanup全部passed，223.048秒。包含零初始部队/两基地、AI从基地开始发展、主机拒绝退役兵种、旧队列退款、机动兵生产、移动战斗采矿/UI及归档模型骨骼动画；联机两轮快照一致，明确检查重开后客户端零单位/两基地，再注入测试部队验证移动。协议14及RPC/快照结构未变。
- 基线：先保存`.godot/base-only-before.bin`，新增独立`simulation_systems_v14_base_only.json`，保留active_roster过渡版本及全部旧版本。2023状态独立重放通过；AI701、mixed901、flight301、reset90状态变化，样板reset30状态不变。移除初始部队改变实体ID分配和可见性，显式夹具场景也因next_id变化；没有覆盖旧轨迹来掩盖变化。
- 首轮Full（172658）实际有旧UI名称和机动兵生产/AI夹具假设失败，不能按旧wrapper的passed汇总视为通过。修复测试为当前名单、隔离生产夹具；增加机动兵runner的push_error，并让wrapper拒绝非空failures数组。用保存的两份失败日志与通过日志验证判定。随后Light Features/Visual/Tooling（173639）全部通过，46.507秒；沙箱内173505因用户日志/存档/证书访问失败，批准固定入口重跑后通过。
- 最终Full所有stderr为空。性能夹具本次显式168单位（取消开局12人后总量相应减少），模拟22.347ms、动画同步7.589ms；不是180单位同负载对比或最低配置验收。前一轮旧测试出现的ObjectDB退出警告不据此宣称已修复。
- Forward+最终停用专项19项（`.godot/active-roster-final.log`）、HUD82项（active-roster-hud）、集结点78项（active-roster-rally）通过，三份stderr为空。最后只更新开局教学文案与截图夹具的建筑视野，重新运行Forward+停用专项通过，不重跑无逻辑变化的Full。兵营截图位于`assets/concept_art/ui_selection/mechanical_hud/active_roster_review/`；归档soldier资源仍可实例化。
- 数值工具72项领域/API/真实浏览器检查通过，59个字段，日志`.local/balance_designer/test.log`。新增退役字段草案保留历史、当前生产关系断言，采矿来源映射均verified；初次浏览器因默认旧对象退回矿车而超时，改默认机动兵后通过。服务已用固定入口重启为PID46684/8811，刷新revision3，stale=false，7对象（两单位/四建筑/共享）、兵营仅产机动兵；原方案ID和一份草案保持。
- 未修改GLB/贴图，不需资源重导入；无EXE交付请求，不导出/打包/推送。旧数值服务33484不在ledger，普通stop未停止；经固定cleanup精确保留素材库12848和共享MCP，再重启数值服务。最终清理保留12848/46684。

## 2026-10-12：机动兵0.75格实施验收

- 选择Light Simulation/Visual：`.godot/validation/20261012-171038-43560/`全部18套加cleanup passed，82.528秒，所有stderr为空。涵盖2023确定性状态、58采矿容量、六车斜坡1538tick/到账360、483格线、1102卸矿、71游戏行为、编队、模型/占地/士兵动画/机动兵/即时命中及两地图组件表现；没有放宽原断言。
- 机动兵专项最终238项、failures=[]，100单位动画CPU约1.667ms/帧（非完整GPU帧率）。新增半径12/直径0.75格、对齐一格建筑通道的实际穿行与连续扫掠、旧半径18拒绝、贴邻建筑封缝、20单位诊断窄缝拒绝、八人往返编队不重叠、实际步幅与步频、角色/枪械只缩一次及血条/光圈尺寸；保留原六动作双手握枪误差<0.8与双向斜坡检查。
- Forward+固定入口`tests/mobile_infantry_size_view.gd`最终11项通过，`.godot/mobile-size-view.log`及stderr无错误。验证实际光圈、血条、一格通道跑动、即时命中与枪口闪光8单位且贴合挂点。已查看`assets/concept_art/mobile_infantry/size_075_review/`的comparison、one-cell-passage及fire-close三张截图；最后居中通道并同步镜头后的血条/选择状态，仅调整验证夹具，未重跑无变化的Simulation/Visual生产逻辑。
- `.godot/mobile-size-measurement.log`每动画33帧实际顶点/蒙皮测量，stderr空：角色缩放24.51776；站立身体/含枪半径10.804/13.555、行走12.292/13.431、跑动13.932、开火12.743/19.256。符合同比2/3；允许脚步与枪口超出碰撞圆，数值不是任意斜坡IK/插值情况下的严格上界。
- 修改前`.godot/mobile-size-before.log`全部2023状态匹配旧v14采矿基线，完整审计保存`.godot/mobile-size-before.bin`。新`tests/fixtures/simulation_systems_v14_mobile_size.json`记录旧文件SHA256与半径12，旧v14/v13及更早基线未改。差异报告`.godot/mobile-size-baseline-audit.json`：1622状态不变，AI场景从tick299单位21位置/路径开始变化401状态，随后经济/战斗时序变化；mixed901、flight301、reset120状态全部一致。最终Light独立重跑匹配新2023状态。
- 首次通道夹具放到样板区边界外导致失败，修正实际平地后238项通过；截图脚本最初`is preload(...)`语法错误，改类型常量后通过。无游戏断言被删除或忽略。环境已知user日志/证书受沙箱限制，Light使用平台批准固定入口运行。
- 本次保持协议14/RPC/快照格式、战斗与生产数值、逻辑视线不变，因此不跑Network/完整ENet/Full；无GLB或贴图源修改，不需import；无交付请求，不导出EXE。最终固定cleanup重新确认无项目测试残留，保留素材库12848/8810、数值工具33484/8811和共享Blender MCP。无提交/推送/concept_art暂存。

## 2026-10-12：机动兵模型与碰撞半径只读测量

- 固定Godot入口执行`.godot/mobile_footprint_probe.gd`，读取实际EntityVisual缩放68/1.849、蒙皮逆绑定/当前骨骼变换及独立武器挂点；四个动画各采样33帧，按每个顶点距单位中心的XZ距离取最大值，排除光圈。`.godot/mobile-footprint.log`成功，stderr空。
- 平地动画采样半径（身体 / 含武器）：idle 16.205 / 20.333；walk 18.437 / 20.146；jog 20.898 / 20.898；fire 19.114 / 28.884，单位为世界单位。碰撞半径固定18，选中环半径22.5。结果是采样估计，不代表任意坡面IK、姿态混合及视觉平滑相对模拟位置偏差的严格上界。
- 本次仅询问尺寸：没有修改游戏数值/模型/源码；不运行Light/Full或导出。测量后执行固定cleanup，保留素材库、数值工具与共享MCP。

## 2026-10-12：小地图方向与输入一致性

- Forward+固定入口执行`tests/mechanical_hud.gd`，`.godot/minimap-direction.log`：83项、failures=[]、stderr空。新增四个真实相机方向、世界角点、四象限非对称地形/迷雾实际像素、拖动定位检查；保留隐藏敌军、坐标往返、点击隔离及四分辨率回归。HUD刷新0.043ms，小地图刷新1.252ms。
- 已查看`assets/concept_art/ui_selection/mechanical_hud/review/resolution-1920x1080.png`，地图标记与战场左右/上下关系一致，视野框正常。原逻辑格序保持不变，绘制层统一180°变换。
- 选择Light Presentation/Camera，最终`.godot/validation/20261012-142513-31152/`两套及cleanup全部passed，总计7.292秒。首次`20261012-142452-40376`虽功能断言通过，沙箱阻止user日志及系统证书读取，整次记failed；平台批准后完整重跑，无stderr错误。
- 固定cleanup确认无项目测试进程残留，保留PID12848/33484与共享Blender MCP。仅本地UI映射变化，不跑Simulation/Network/Full；无源资产修改或交付请求，不需导入或EXE导出。

## 2026-10-12：整格逻辑占地、五车预约与斜坡采集

- 跨地形、采矿调度、碰撞和协议边界，选择Full。首次`.godot/validation/20261012-133059-24620/`中卸货、旧动画夹具与性能失败，修复后第二次Full `.godot/validation/20261012-134112-43780/`的23套源检查全部通过；该次ENet因新测试出生点落入矿坑边缘而超时，所以该整次Full仍记failed。测试坐标修正并新增合法性断言后，Light Network `.godot/validation/20261012-140434-42028/`通过（154.322秒，完整ENet127.751秒）。最后补出口恢复边界后，最终Light Simulation/Network `.godot/validation/20261012-140834-38496/`全部通过（180.358秒，ENet125.874秒），11套源检查stderr均空，两轮完整主客机快照一致，包含五预约一等待、取消后递补、采矿/生产/升降/战斗/胜利/重连/重开/断线与协议拒绝。复用Full已通过且未改变的画面/镜头/命令卡/性能结果，未重复这些领域。
- 容量专项`tests/mining_capacity.gd`58项通过：五个预约、第六个等待、重叠矿车及士兵无推挤、等待无产出、满载释放/停止安全退出、29/30/31格严格边界、跨矿原子预约、原搜索中心不漂移、双方共享上限、死亡/重开清理、不可达/不可见/耗尽候选拒绝、伪造豁免/超额预约/未来请求/非对齐建筑拒绝、地图非法矿点与岩石拒绝。封闭作业区解除阻挡用例先失败，补退出阶段每秒重查后通过。
- 斜坡专项`tests/mining_slope_probe.gd`保留真实组件地形、矿车半径48和卸载站规则。原逻辑六车中四车长期无货且stuck反复清零；改后1538tick六车均采过矿、累计到账360，每步静态扫掠合法，采矿预约始终≤5，定期快照有效，矿石扣除=到账+货仓总数。测试矿点是独立夹具，未恢复用户取消的样板区初始矿场/单位。
- 格线专项481项、卸货1102项、组件148项、游戏71项、占地表现69项及原编队/兵营/地形等回归通过。矿车仍是圆形半径1.5格、直径3格；只在取得预约进入半径4格作业区及安全退出阶段忽略单位体积，静态体积未缩小。扫掠连接图仅用于组件地形粗路径中不通的边，主地图没有该额外热点开销。
- Forward+ `.godot/mining-view.log`通过且stderr空：真实点击晶矿显示预约5/5、等待1，矿车等待/采集状态与动画一致，斜坡渲染截图在`assets/concept_art/ui_selection/mechanical_hud/mining_grid_review/`；已查看`slope-mining.png`。`.godot/mining-audio.log`47项实际混音检查通过，等待车辆即使靠近矿点也无采矿循环，mixer峰值0.176、空间音效峰值0.071。
- 180单位最终Full性能：模拟23.691ms（预算25）、动态动画同步7.387ms（预算8）、单位同步1.730ms、整体视觉同步1.750ms。之前27.432ms失败保留记录，修复限定接缝图范围及减少碰撞热路径调用后通过；未放宽阈值。仍有既有5个ObjectDB实例退出警告，未修复；结果不是完整对局GPU帧率或最低硬件保证。
- 版本化审计：独立`tests/fixtures/simulation_systems_v14_mining.json`，旧v11/v12/v13文件字节保留；SHA256分别以`e47a9e5a`、`8babf434`、`15360fec`开头。修改前2023完整状态保存`.godot/mining-before.bin`，分类审计`.godot/mining-baseline-audit.json`：地图版本、校验和及矿点格中心使2023状态全部变化，经济/路径时序差异另按字段统计；最终代码重新匹配全部2023新状态。新基线捕获第一次有沙箱用户日志/证书错误，平台批准后最终捕获与回归stderr空；中间草稿移到.godot，未覆盖旧规则基线。
- 音频与画面检查独立运行；无模型/纹理源改动，不需重导入；未请求二进制交付，未导出EXE。没有上传或暂存concept_art。固定清理在验证末尾执行，保留素材库PID12848/端口8810、数值工具PID33484/端口8811和共享Blender MCP。
- 最终cleanup已通过并复查无本轮项目测试进程；局部diff/UTF-8检查通过，仅Git提示现有CRLF转换。原全局格线v13文件及旧基线未覆盖。测试错误（初版诊断误用tick、实例误调用new）均已修正入口并重跑，未作为游戏功能失败隐藏。

## 2026-10-12：全局格线、紧邻建造与逻辑占地阻挡

- 采用Light Simulation/Visual/Presentation/Features/Network/Performance，覆盖规则、占地表现、热路径与协议13边界。`.godot/validation/20261012-090427-35760/`的17套源检查全部通过，stderr均空；该次ENet因新增地堡支出后的旧余额门槛超时，不将该整次运行记作通过。修正测试资金门槛后，最终`.godot/validation/20261012-095350-41512/`的Network/Performance及cleanup全部通过，总计160.770秒，其中完整ENet125.535秒。
- 新增`tests/building_grid.gd`481检查：两地图初始格线、幂等吸附、64种建筑/方向贴邻组合、实际重叠拒绝、主机位置一致、接缝/转角防穿越、单位半径通道、紧邻升降、阻塞出口等待恢复与卸矿、协议拒绝及快照往返。既有卸矿1102项、兵营朝向558项、两地图兵营集成、占地69项与编队全员到达检查通过，原断言未放宽。
- `tests/building_grid_view.gd`在Forward+实际渲染通过，`.godot/grid-view.log.err`为空；人工复查三面贴邻的合法绿色预览与共享格线。截图位于`assets/concept_art/ui_selection/mechanical_hud/grid_alignment_review/three-neighbors-valid.png`及`one-cell-overlap.png`。
- 保留v11/v12旧基线文件与SHA256；修改前2023完整状态审计保存在忽略目录`.godot/grid-before.bin`（初次日志/证书访问受沙箱限制，但状态比较成功）。新`tests/fixtures/simulation_systems_v13_grid.json`独立记录2023状态与旧哈希，语义断言通过后才捕获。审计120状态不变、1903变化，首差异为对齐后的基地/矿站x+16或兵营y+4，后续路径、视野、采矿和战斗时序随位置改变。最终代码再次匹配全部2023新基线状态。
- 发现并修复：泊位对齐后无可用粗网格节点，enter/exit改连续扫掠并保留全部碰撞/避让；基地位置改变后编队目标被闲置队友包围，增加安全连接点与同编队同类型目标交换。兵营夹具改读吸附中心；新专项误删两侧基地导致提前判胜、选址落入地形的问题均修正。两个Godot包装器并发写进程登记表报不可读流，后续串行重跑通过。
- 完整ENet验证访客贴邻建造复制、集结点与生产、采矿及货量、兵营迁移/降落、即时命中战斗、胜利、重连重开、观战权限、旧协议拒绝及主机断线；两轮主客机完整快照一致。首次超时来自新增地堡支出300而保留旧资金门槛，测试门槛减去额外花费后通过，未减少原采矿/生产覆盖。
- 180单位性能通过：动画同步7.607ms、模拟23.130ms、单位同步1.737ms、视觉同步1.883ms、UI0.035ms。性能套件仍有既有的5个ObjectDB实例退出警告，未修复；这不是完整对局GPU帧率或最低硬件保证。
- 固定cleanup已完成，无本轮项目测试进程残留，保留素材库PID12848/端口8810、数值工具PID33484/端口8811及共享Blender MCP。未另跑Full的Camera/ActionBar领域：本次无对应输入/镜头行为变化，已按影响覆盖上述六领域。无源资产改动，不需重新导入；无包装交付请求，未导出EXE或上传。

## 2026-10-12：建造占地线框与已建建筑边框

- 级别：`Light -Area Presentation,Visual,Features`，固定包装器最终目录`.godot/validation/20261012-002124-40388/`，45.660秒，11套件与清理PASS；核对实际失败结果、全部stderr为空。`build_footprints`已注册Visual/Full，headless69检查。
- Forward+专项：`.godot/footprint-review-complete.log`，87检查、failures=[]、stderr空；`.godot/footprint-barracks.log`兵营集成PASS，stderr空。覆盖尺寸/公共边不重复/红绿逐格/实例透明度/无投影/正式模型不变/缓存复用/迷雾/施工和空中建筑/鼠标点击穿透/Esc和右键/菜单/放置/重置/标题。
- 截图：`assets/concept_art/ui_selection/mechanical_hud/footprint_review/`，四建筑合法预览、降落部分阻挡、1280×720/1920×1080/2560×1440/2560×1080，以及样板区高台密集建筑；已查看卸载站、720p与高台图，格线可辨，已建主体没有色块覆盖。
- 首轮专项测试误用不存在的方法，改成真实鼠标事件；标题返回已销毁地面节点，断言改成检查引用清空，最终87项通过。首次Light在沙箱内因user日志、系统证书、测试存档访问受限失败（20261012-001038-40940），经平台批准后完整重跑通过，未放宽断言。
- 清理：最终验证包装器报告PROJECT_PROCESSES none；原素材库12848、数值页面33484与共享Blender MCP保留。仅表现层改动，不跑Simulation/ENet/Full或EXE导出；无生产资产变化，不需重导入。

## 2026-10-11：样板区仅主基地与操作静音

- `tests/audio.gd`通过固定入口Forward+执行，`.godot/sample-silent-audio.log`为46项failures=[]，stderr空；新增建筑/建筑编队静音、右键移动静音、移动按钮及落点静音检查。原其他音效播放与循环断言保留，混音峰值0.175795/空间音0.070886均非零。
- `.godot/sample-base-trace.log`验证1993原冻结状态不变并采集30帧样板v4补充基线`tests/fixtures/sample_base_only_trace.json`；之后常规2023状态比较通过。首次采集参数被外层Shell合并未进入capture模式，修正为固定入口单一参数后成功，未覆盖旧基线。
- Light Simulation/Presentation/Features/ActionBar：`.godot/validation/20261011-231830-42588`中模拟、玩法、卸矿、输入及地形全部通过，唯样板重开仍期待7单位的旧断言失败。更新为仅主基地并补充可视模型清理断言后，Light Features定向复验`.godot/validation/20261011-232005-34680`三套件及cleanup全部PASS，17.927秒。
- 样板状态验证初始和重开均为0单位、0矿点、1完整己方基地；地形拾取、上下坡和正式地图AI/迷雾恢复继续通过。仅单机样板配置与本地音效变化，无协议修改，跳过Network/ENet与Full；未改资源导入参数或交付配置，不导出EXE。最终清理无测试残留，保留原12848/33484服务和共享MCP。

## 2026-10-11：建筑集结点

- 固定run-godot入口独立导入`.godot/rally-import.log`，stderr空；正式新增两张SVG图标。最终Forward+专项`res://tests/rally_points.gd`，`.godot/rally-review-final.log`记录89项failures=[]、stderr空；四分辨率截图保存于`assets/concept_art/ui_selection/mechanical_hud/rally_review/`，已目视检查1080p与720p，六按钮和旗标均正常。
- 专项覆盖原点目标、归属/生产资格/非法位置/隐藏矿点校验、两种步兵出生移动、矿车定向采矿、耗尽/删除回退、清除不改既有单位、快照字段与版本拒绝、真实按钮/鼠标/R键、HUD隔离、取消/菜单/换选/召回/攻击切换、旗标阵营与迷雾、施工预设、升空编辑锁、清除与销毁。
- Light选择Simulation、Presentation、Features、ActionBar、Visual、Network、Performance，日志`.godot/validation/20261011-202448-40860`，18源码套件、完整ENet与cleanup，205.997秒。2023冻结状态使用显式v11快照结构投影比较，未修改任何冻结JSON；新模式另测。卸矿1100、玩法71、编队/路径、动画、地形检查均通过。
- 首轮ActionBar实际输出两条旧预期失败（升降时要求所有图标消失），已改为生产图标清空且集结点按钮禁用，保留行为约束；最终输入互斥变更后Light Presentation/Features/ActionBar定向复验`.godot/validation/20261011-205000-40248`全部failures=[]，24.803秒。包装器未识别首次非空failures数组、汇总仍报PASS的问题未修复（不属于本次范围），本次逐项检查日志并以修正后的专项输出为准。
- ENet首次/重连两轮完整快照相等；访客设置矿点后出生即采矿、搬迁保留地面集结和清除同步均通过；版本不符、观战越权与主机断线处理通过。协议12双方必须一致。
- 180单位性能预算通过：UI刷新0.03482ms、动画同步7.79058ms、模拟23.0845ms；仍有既有5个ObjectDB退出警告，无资源或脚本错误。本机单次测量不代表最低硬件性能。
- 最终固定清理PASS，无测试进程残留，保留原12848/33484服务及共享MCP。本次无导出/打包改动且未请求EXE，跳过导出烟测；按定向Light完成所需覆盖，未重复Full。

## 2026-10-11：紧凑机械终端 HUD

- 已通过固定入口单独导入七张正式头像，导入size_limit=512；运行HUD不引用concept_art。Forward+专项入口：`run-godot.ps1 -Action script -Script res://tests/mechanical_hud.gd -Rendered`；最终`.godot/mechanical-hud-review2.log`为71检查、failures=[]，stderr为空。
- 专项覆盖七种对象头像和真实生命/矿仓/队列、施工/飞行/出口堵塞、死亡过渡、多选、持久节点、迷雾隐藏敌人、观战、坐标往返、小地图真实点击/拖出边界释放、选择/命令隔离、右侧战场可点击、按钮框内布局。Forward+保存并检查1280×720、1920×1080、2560×1440、2560×1080截图，位于`assets/concept_art/ui_selection/mechanical_hud/review/`。
- Light选择Presentation、Features、Camera、ActionBar、Visual、Performance，运行13套件及cleanup。`.godot/validation/20261011-195854-36280`中除visual_models退出音频资源错误外其余全部通过；补齐该测试的排队音效取消及场景清理后，Visual定向复验`.godot/validation/20261011-200011-31012`全部通过，耗时32.978秒。不为已通过的其他领域重复运行。最终固定清理PASS，无测试进程残留，明确保留12848素材库、33484数值工具及共享MCP。
- 本机一次测量：HUD刷新0.04136ms，小地图10Hz单次更新1.2653ms；180单位性能套件UI刷新0.03494ms、动画同步7.60882ms、模拟23.031ms，现有预算通过。性能套件仍有既有ObjectDB退出警告，未出现脚本错误或资源错误；不代表最低硬件性能保证。
- 首轮沙箱无法写Godot用户日志/地形临时文件，已通过平台授权固定入口复验。旧测试位置遮挡通过移动镜头并保留原断言解决；退出音频错误通过取消排队播放及等待混音器解决，未放宽阈值或隐藏错误。
- 改动为本地UI/镜头交互，现有生产和下令行为由Presentation/Features/ActionBar覆盖；未改权威模拟或协议，跳过Simulation、Network/ENet与Full。未请求二进制交付且导出配置未改，跳过EXE和导出烟测。

## 2026-10-11：正式游戏音频

- 固定入口独立导入完成，最终 audio-import-final.log.err为空；正式8 WAV为48kHz双声道PCM，循环精确192000帧。
- 固定 run-godot.ps1 -Action script -Script res://tests/audio.gd -Rendered：`.godot/audio-rendered-final.log`，Forward+ RTX5070Ti，42检查failures=[]，stderr空。包含八资源、同帧重复shot、快照去重/客户端新增生产、敌方不播通知、部署、按钮与选择、采矿满载/停工/死亡/雾遮/远离、并发上限、重开及标题清理。
- AudioEffectCapture确认UI峰值0.175795、空间shot峰值0.070886，均非零且小于1；两类4秒循环播放设置正确，实际引擎循环等待4.2秒仍播放且进度回绕。这是技术播放验收，不等于主观听审。
- Light -Area Presentation,ActionBar,Performance最终PASS，11140ms，三个套件及cleanup全通过；180单位sync_units1.70854ms、animated_sync7.28242ms、simulation22.71335ms，为本机一次测量，不承诺最低硬件性能。未改协议，ENet/Full跳过；未交付二进制，导出/smoke跳过。
- 曾出现AudioStreamWAV/PlaybackWAV退出残留，详细日志定位select音同帧反复play/reset；改帧末队列+代际取消、显式停流及测试退出等待后复验通过。未忽略任何错误行。

## 2026-10-11：单位百科与数值草案

- 固定入口 `tools/codex/run-balance-designer.ps1 -Action export|portraits|test`；导出三单位/四建筑，68个数值字段；Forward+ RTX5070Ti渲染七张模型图。日志在 `.local/balance_designer/`。
- 最终70项专项通过（隔离存档`.local/balance-test-50vIHH`）：类型/整数tick/范围校验、DPS、源映射失败、新增/移除字段、三方冲突与重复刷新、约束变化、独立复制、原子存档及损坏备份恢复、服务重启、旧revision拒绝、Host/Origin/token和无回写入口。
- Edge实际浏览器：自动保存/刷新恢复、非法值保留、秒转tick、命名方案创建/复制/重命名/删除、搜索分类/差异对比、真实模型图、并发冲突/重载、刷新冲突处理、导出等待保存、窄屏操作。游戏源文件SHA256前后相同；没有修改用户游戏数值。
- Light Tooling通过（5050ms）：固定入口语法、工具路径与进程Path、实际Godot启动、execpolicy 27允许/7拒绝、固定清理。首次沙箱Codex临时目录拒绝访问已通过平台授权重跑解决。ToolchainSmoke未选；无玩法/联机/EXE影响，跳过Simulation/Network/EXE。
- 当前服务仅监听127.0.0.1:8811，明确保留其PID和原艺术库8810；清理没有残留测试进程。原共享Blender MCP不停止。截图及测试存档不作为正式游戏资产。

## 2026-10-11：八种离线音效小样

- 生成入口 assets/concept_art/audio_samples/generate_samples.py，执行退出0，9 WAV读回PASS；详情在同目录 validation.json、cue_sheet.json。48kHz双声道16位，独立时长0.15/0.35/1/0.5/4/4/2.5/0.8秒，合集29秒。
- 峰值分别为-12/-12/-5/-8/-10/-12/-6/-10 dBFS，合集-5 dBFS；无整数削波、整段静音或超限直流。单次音首尾为0；循环接缝最大通道步长0.0002441/0.0002136，10ms块无掉音，接缝附近差分检查通过。
- 范围为离线音频资产生成和检查，无游戏源码、工具包装器或运行资源变化，因此不适用Light/Full；未运行Godot导入、ENet、EXE或启动服务。未进行主观听审，不声称声音质感已验收。

## 2026-10-11：双泊位矿石卸载站

- 独立导入`.godot/depot-import.log`，Blender构建`.godot/depot-build.log`，删除旧子树`.godot/depot-retire.log`。保留共享源其他117对象。三级20403/8352/1232三角面，6/6/5材质；Forward+实际预览在`assets/concept_art/ore_depot/`，含三级斜视与俯视。
- 双泊位最终1100断言通过：四车排队互斥、双车同tick结算、17单位尾矿、取消/新命令/死亡/建筑销毁、堵塞100tick换站、不瞬移不丢货、侧后生产出口、快照往返与畸形/重复预约拒绝；新增占用期间入口被堵、同站另一泊位可用时重新预约覆盖，领取泊位也检查完整可达路线。v11轨迹2023状态复验通过，v9原JSON哈希保持不变。
- 首次Light Simulation/Visual/Performance/Tooling在`.godot/validation/20261011-122734-11228/`因沙箱用户日志/系统证书/临时目录权限失败，功能输出不视作整套通过。通过固定脚本升级执行的`.godot/validation/20261011-122904-31840/`中Tooling、性能及其余功能通过，仅地形样板大矿车起点落入新建筑的半径膨胀范围失败；起点向东移64，保持原坡道目的地与返程覆盖。
- 本轮180单位CPU模拟23.201ms（预算25ms），动画7.482ms（预算8ms）通过；此前环境波动下动画约8.5ms超限的历史记录保留，本次没有修改性能门限或宣称解决该历史问题。
- Light Simulation/Visual/Network在`.godot/validation/20261011-123110-39240/`的全部14套源码检查通过。Visual包含真实LOD预算、贴图保留、透明玻璃、双指示灯与互斥绘制断言。ENet首轮卸矿通过后，迁移兵营的旧降落测试点被新训练点产出的士兵占用；改为训练点北侧192的合法空地，保留真实占用检查。
- 最终Light Network在`.godot/validation/20261011-123524-14088/`通过，ENet124.041秒：进站/卸矿离站同步、生产、兵营迁移、目标绑定攻击、胜利、重连/重开、两轮完整快照相等、版本不符拒绝、观战权限、主机退出全部通过。最后同站换泊位修复不改变协议或快照字段，已用专项1100断言和2023状态基线复验。
- 固定验证脚本清理均成功，保留共享MCP与用户艺术库PID12848。已有部分测试ObjectDB退出警告仍保留。无包装/分发改动，不导出EXE；未运行无关Camera/ActionBar等独立范围及可选ToolchainSmoke。
- 收尾Light Simulation：`.godot/validation/20261011-123835-24768/`全部7套通过，包含最终1100泊位断言与2023状态基线，39.198秒，清理成功。首次失败均保留原始日志及对应修复记录，未覆盖旧基线或放宽预算。

## 2026-10-11：机动兵即时命中特效

- 选择Light Simulation/Visual/Network，目录`.godot/validation/20261011-110905-35048/`。相关源码检查通过，包括1543原玩法轨迹、gameplay71项、机动兵132项及首次命中49项；首轮ENet因测试把既有士兵原地改为机动兵而沿用旧显示控制器失败。改为创建独立机动兵，保留正式游戏的固定兵种身份；胜利快照不触发普通snapshot_applied信号，测试显式检查最终快照。
- Light Network/Performance/Tooling：`.godot/validation/20261011-111339-33800/`。工具链、玩法和命中专项通过；180单位模拟24.260ms（预算25ms）、动画8.583ms（预算8ms），因此整轮failed、ENet跳过。历史动画性能限制保持未修复，未通过降低阈值或重写基线掩盖。
- 最终命中专项扩展52项，含本地时钟在胜利/快照暂停后继续衰减；100个同时存在的命中CPU更新0.356ms（4ms专项预算）。这个数字只描述特效脚本更新，不代表整场游戏GPU帧率。
- 最终Forward+ RTX5070Ti实际渲染，`.godot/mobile-impact-final-render.log`，52项通过、stderr为空，100特效CPU0.364ms；`assets/concept_art/mobile_impact/targets.png`、`close.png`和`decay.png`已输出并复查近景与衰减，确认火花位于受击面。
- 最终Light Network：`.godot/validation/20261011-111456-36540/`全部通过，100.357秒；gameplay71项、mobile_impact52项、terrain_maps及完整ENet。客机实际收到机动兵单位命中与建筑致死命中，双方两轮完整快照一致；采矿、生产、兵营迁移、攻击胜利、重连/重开、主机断开、旧协议拒绝及观战权限通过。
- 未修改模型/贴图源资产，运行时程序生成小型径向贴图和火花网格，无需资产重导入；不做Full、打包导出或EXE启动，本次按明确受影响区域检查。部分既有场景的ObjectDB退出警告仍未修复。
- 最终固定cleanup通过，无本轮测试进程残留；素材库PID12848/端口8810与共享MCP保留。预览按用户规则留在concept_art，不提交或上传。

## 2026-10-11：五个核心模拟系统拆分

- 使用Full（跨核心系统结构调整），额外单独执行Network补验、Tooling入口检查及矿车/移动/飞行专项。Full目录`.godot/validation/20261011-104123-35608/`：16套功能检查通过，性能套件动画8.243ms超过8ms，模拟24.343ms低于25ms；整体failed，ENet被跳过，不能将本次Full写作全绿。
- 冻结行为：`tests/simulation_systems.gd`，AI700、混合420、飞行300、重开120tick加三个初始状态，共1543检查点；Full和迁移各阶段完全一致。签名包括完整快照、next_id、AI开关、命令及返回值。覆盖路径/落点、冷却/工作进度、队列/退款、视野/探索、死亡效果/胜负及镜像应用。
- 基线为Godot 4.7.2在重构前捕获：原源码SHA256 `b360c9975aede67a969aec3fc4dff48a8852125252aab6f6ea575c69955f8811`，JSON SHA256 `44314a7b43d74c796e574b936696fdf5dafededdc2791c3fc3ddfac68c1509a8`。捕获入口拒绝覆盖现有文件、拒绝非原源码；正式回归只读基线。未来有意改变玩法或升级引擎时应单独评审基线版本更新，不自动接受差异；本次不宣称跨引擎/跨平台位级一致性。
- 性能诊断：`.godot/systems-performance-sweep.log`原阈值专项通过（模拟23.714ms、动画7.929ms）；Full动画失败后，隔离场景重跑原始源码与新源码，`.godot/systems-perf-before-diagnostic.log`/`systems-perf-after-diagnostic.log`分别模拟24.370/23.754ms、动画8.474/8.495ms，起始帧均5。另一个暂停自动更新的诊断起始帧0，双方冷启动模拟均超预算。未改正式测试、未重写轨迹基线、未降低负载或放宽阈值；动画预算波动仍是未解决限制。
- 通过固定import入口注册Simulation脚本类型，`.godot/systems-typed-import.log.err`为空。没有源模型/材质变化；不重复资产验证截图，不运行包装/EXE导出或上传。
- 联机补验：Light Network `.godot/validation/20261011-104431-5884/`全部通过，140.314秒，gameplay71项、terrain_maps与完整ENet；两轮完整主客机快照一致，采矿/生产、飞行部署、战斗胜利、重连重开、主机断开、协议拒绝和观战权限正常。该结果补齐了被Full性能门槛跳过的网络检查，并不把原Full改记为通过。
- Tooling：Light Tooling通过，4.544秒，语法、工具发现/迁移夹具、Path/PATH真实启动、27项允许及7项拒绝的execpolicy检查通过；可选全工具链smoke未启用，本轮不需要Blender或MCP服务启动。
- 专项：`.godot/systems-final-movement_volumes.log`（102项）、`systems-final-hover_harvester.log`（321项）、`systems-final-barracks_flight.log`（46项）、`systems-final-barracks_heading.log`（558项）、`systems-final-barracks_integration.log`全部通过。矿车与兵营集成仍有历史ObjectDB退出单实例警告，保持未修复。
- 最终固定cleanup通过：无本轮测试进程/端口残留，素材库PID12848/端口8810和共享MCP按规则保留；源码与记录局部diff/UTF-8检查通过。

## 2026-10-11：移动体积与群体避让

- 专项日志：`.godot/movement-final-movement_volumes.log`（102项）、`movement-final-hover_harvester.log`（321项）、`movement-final-barracks_heading.log`（558项）、`movement-final2-barracks_flight.log`（46项）、`movement-final2-barracks_integration.log`，全部通过。
- Forward+实际渲染：`.godot/movement-review.log`，13/13到达、stderr为空；6张截图保存在`assets/concept_art/hover_harvester/movement-*.png`，已复查`movement-080.png`绕障朝向和`movement-259.png`到达间距。
- Full运行目录：`.godot/validation/20261011-003950-39636/`。源码16套已通过，ENet在采矿后因旧兵营选址与士兵体积重叠而被终止；该次Full整体状态为failed。180单位：模拟23.029ms/tick，动画同步7.340ms，站位分配19.351ms，等待重试最大3.759ms；原性能阈值不变。
- 首次Light Network复验`.godot/validation/20261011-004919-2980/`在落地检查发现新兵占位，测试落点同步调整间距。最终Light Network目录`.godot/validation/20261011-005112-9956/`全部通过，141.586秒：gameplay71项、terrain_maps、完整ENet与cleanup。包括采矿/生产、兵营转向迁移及落地、跨地图攻击胜利、两轮完整快照相等、重连重启、主机断开、协议不符拒绝和观战权限。此次只更改测试夹具，复用Full已通过的表现与性能结果。
- 若干场景退出仍有历史ObjectDB单实例泄漏警告，未修复；最终专项与实机没有脚本运行错误。本次不涉及资产重导入或包装交付，未执行导入/EXE导出或上传。固定清理确认无残留测试进程，原编辑器/Blender/素材库/共享MCP保留。

## 2026-10-10：固定世界线宽选择圈

- Light Visual：`.godot/validation/20261010-235305-30900/`，七套与cleanup通过，28.879秒；visual_models新增七类对象共42个线宽/圈径/缩放/更新/隐藏/复用断言。既有ObjectDB退出警告仍在。
- Forward+实机：`.godot/selection-width-review-final.log`，81项通过，stderr空；`assets/concept_art/gaia_command_base/selection-width-comparison.png`及`selection-width-far.png`、`selection-width-near.png`展示1.2/0.8/1.8镜头下基地和士兵同时选中。
- 无源模型变化，无需单独导入；仅选择表现修改，未跑Simulation/Network/Performance，不导出EXE。

## 2026-10-10：GAIA 主基地正式接入

- 导入：`.godot/gaia-integration-import.log`，stderr空。
- 最终Light Visual/Simulation/Performance：`.godot/validation/20261010-234641-33528/`，12套测试与清理通过，40.805秒。包括gameplay71项、arrival_formation、visual_models、soldier_locomotion、soldier_rig、mobile_infantry、visual_performance及五套地形检查。已有visual_models/terrain_presentation的ObjectDB退出警告未解决。
- 独立资产：`.godot/gaia-asset-integration-final.log`，212项通过、stderr空，含旧模型哈希不变。
- 实机集成：`.godot/gaia-integration-review-final.log`，78项通过、stderr空，Forward+/RTX5070Ti；验证双方初始基地、320×192寻路阻挡、AI间距、原建造费用与140tick计时、施工完整姿态、完成隐藏进度条和快照占地一致。
- 截图：`assets/concept_art/gaia_command_base/game-main-base.png`、`game-construction.png`、`game-completed.png`。实际游戏场景、HUD与原环境；已人工复查。
- 未跑ENet：没有RPC、快照结构或同步边界变化；未导出EXE/打包验证：本轮仅源码与模型接入。未实测最低硬件性能，不宣称最低配置达标。

## 2026-10-10：GAIA 独立基地资产

- 构建报告 assets/models/source/gaia_command_base_report.json：源尺寸18×10×9、展示288×160×144、三级93088/26588/4092三角面，各13网格/4材质；装甲4K/机械2K，Cycles法线及AO烘焙。构建 .godot/gaia-build-final.log；最终共享贴图导入 .godot/gaia-shared-import.log（stderr为空）。
- 旧 base.glb、ironfront_models.blend、create_base.py 的SHA256与构建前一致；tests/gaia_command_base.gd在最终新进程再次验证。GLB使用外部图像URI，共用六张相邻 gaia_shared_*.png；Blender源打包图像，包含隐藏的可编辑烘焙源与三级模型。
- .godot/gaia-runtime-final.log：212项全部通过，精确尺寸、部署12、待机11.5–12.5、PBR贴图/UV、LOD预算与互斥显示、旧基地映射、30/60/144fps六秒起落和巡航停止、雷达独立控制；stderr为空。
- .godot/gaia-review-final.log：Forward+ / RTX5070Ti，15张静态图及49帧连续24秒动作采样，stderr为空；输出 assets/concept_art/gaia_command_base，review.html可播放2fps采样，流畅预览使用 tests/gaia_command_base_preview.tscn。人工检查前/顶/侧/后/塔楼/底部/与作业机尺寸；非参考图逐像素复刻。
- .godot/gaia-performance.log：1600×1000、MSAA4x、无垂直同步，预热60帧、采样120帧。空场GPU中位0.352ms；单LOD0/1/2为0.504/0.445/0.401ms；8个LOD1为0.498ms。报告 assets/concept_art/gaia_command_base/performance-report.json。八基地使用更远镜头，不能作为同像素量线性扩展结论；不是完整对局或最低配置保证。
- .godot/validation/20261010-165841-18064：Light Visual七套测试和cleanup通过，28.189秒；既有部分ObjectDB退出警告仍在。本轮未运行Simulation/Full/ENet，因资产和展示组件未接入模拟、指令或协议。未导出EXE。固定清理无本轮进程残留，原编辑器4368/Blender9544/素材库12848及共享MCP保留。
- 建造生长动画明确延期；当前升降只用于起落展示。动作交付为Godot控制器，不是GLB内嵌动画。未来迁移速度、占地、空中建造和受击规则未实现。

## 2026-10-10：悬浮作业机放大 25%

- 参数：显示缩放 17.5，地形采样跨度 30，高度锚点 44；模型与模拟数据未修改，不需要重新导入。
- .godot/hover-harvester-size-runtime.log：338 项专项通过，最近夹爪距矿心 11.353，坡道最低推进器间隙 8.316；覆盖采矿交付、四档货量、停止收臂和地面通行。继承的 ObjectDB 退出警告未修复。
- .godot/hover-harvester-size-review.log：Forward+ / RTX 5070 Ti 实机输出 13 张图，stderr 为空。同镜头比较：assets/concept_art/hover_harvester/scale-14 为原尺寸，父目录为放大后；已目视检查满仓和实际晶矿接触。
- .godot/validation/20261010-162746-32132：Light Visual 七套检查与固定 cleanup 通过，26.915 秒；本轮无进程残留，原编辑器、Blender、素材库和共享 MCP 保留。未运行 Simulation/Performance/Full/ENet：本次仅两个显示参数，模型复杂度、算法、模拟和协议未变；已有采矿专项复验。未导出 EXE。

## 2026-10-10：悬浮采矿机

- 构建：.godot/hover-harvester-build-final.log，29786 三角面 / 18 网格 / 48 块三层晶体；独立源 hover_harvester.blend。旧源删除 23 对象并断言其余 128 对象相同，日志 .godot/hover-harvester-retirement.log。重导入 .godot/hover-harvester-final-import.log。
- 专项 tests/hover_harvester.gd：338 项全部通过；真实命令、采集经济、四档载货、耗尽部分返航、停止收臂、镜像快照、地面坡道和悬崖限制。夹爪最近距矿心 14.004，推进器坡道最低间隙 6.633，报告 assets/concept_art/hover_harvester/runtime-report.json。
- 固定 Light Visual/Performance/Simulation：12 套测试与 cleanup 全部通过，39.532 秒，目录 .godot/validation/20261010-100233-9860。180 单位 sync_units 1.671ms、sync_visuals 1.725ms、动态同步 7.117ms、模拟 16.516ms，网格 1132。这是 CPU/headless 基准，不是完整对局 GPU 帧率。
- tests/hover_harvester_review.gd 实机 Forward+ / RTX 5070 Ti / MSAA4x，13 张截图位于 assets/concept_art/hover_harvester：前后、0/10/30/60 货量、4 个采矿阶段、矿点近景/正常视距。日志 .godot/hover-harvester-review.log，stderr 为空；近景不代表默认游玩视距。
- 首轮沙箱用户目录写入/系统证书读取失败，经平台批准重跑成功。未执行 Full/ENet，因为模拟规则、RPC、快照边界未修改；未请求 EXE 交付。部分 headless 测试存在历史 ObjectDB 退出警告。玻璃透明和晶矿裂纹为实时近似，未实现物理多次折射；参考图工业细节简化。
- 最后固定 cleanup -StopTracked -StopUntracked 成功：本轮项目进程无残留，保留 4368 编辑器、9544 Blender、12848 素材库及共享 MCP；8810 仅归属保留的素材库。

## 2026-10-10：蓝色晶矿与 Forward+

- 源：create_crystal_ore.py 从空场景生成；4852 三角面、2 网格、34 晶体/84 岩石碎块，2K 晶矿和 1K 岩石贴图。半径 0.798879 × 45 < 38，最高 78.94 < 标签锚点 80；GLB 含 COLOR_0 和 TEXCOORD_0/1。
- 旧模型删除：retire_legacy_ore.py 移除共享源旧 ore 树 5 对象，剩余 151 对象类型、网格顶点数和世界矩阵相同；日志 .godot/crystal-ore-retire.log。独立新源 assets/models/source/crystal_ore.blend。
- 实际 GPU：Godot 4.7.2 / Vulkan / Forward+ / RTX 5070 Ti。tests/crystal_ore_review.gd 20 项检查通过，包括两图共享材质、岩石贴图、尺寸、锚点、无旧几何/缩放轨道、矿量归零和迷雾同时隐藏模型与灯。最终 .godot/crystal-ore-review.log.err 为空。
- 图片：assets/concept_art/crystal_ore 下 01 正常镜头、02 最近缩放、03/04 模型前后近景、05 样板场景、06 同屏矿簇、07 独立引擎资产近景。全部为实际 Godot 渲染；近景不代表正常游玩视距。
- 性能：1600×1000、4x MSAA、无垂直同步，独立 0/1/24 矿簇预热后各 90 帧，GPU 中位 0.163/0.177/0.263ms；帧中位 0.416/0.424/0.519ms。仅此显卡/独立场景，不证明完整对局、最低硬件或所有地图帧率。
- 固定验证：Light -Area Visual,Performance,Presentation,Camera，通过 10 套检查及 cleanup，共 33.869 秒，目录 .godot/validation/20261010-005329-11104。首轮沙箱 user:// 写入与系统证书读取失败，平台审批后重跑成功；既有 ObjectDB 退出警告仍存在。
- 未运行 Full/ENet：模拟与网络边界未改动。未导出 EXE：没有交付二进制请求。矿车互动验收按用户明确要求推迟；常规视觉套件中的旧矿车动画断言不能代替新矿车交互验收。
- 材质限制：使用不透明多层裂纹与局部灯模拟晶体通透和染光，不宣称物理多次折射或参考图像素级一致。

## 2026-10-09：机动兵 v5 连续主体与法线细节

- 几何：49 源部件，2154 四边面 / 4308 导出三角面，0 N-gon；原 v4 为 78 部件 / 4992 三角面。ContinuousBody（躯干与双裤腿共享裆部顶点）、双袖、HelmetShell 各 1 个拓扑连通分量；闭合边、正体积和退化检查通过。保留独立活动硬护甲与武器。
- UV/PBR：881 独立 UV 岛、10px 间距，4308 UV 三角形 / 28923 候选相交检查为 0。两材质 / 2048 贴图 / 1 运行网格；头盔完整外壳使用材质参数区分面罩和眼窗。接缝、通风槽和浅褶由高源高度细节烘焙到法线，头盔法线最大偏差 0.0994；法线开启/关闭及侧光图人工检查。
- 蒙皮：23 变形骨 + 6 源控制骨，六动作不变。实际变形网格覆盖 walk/jog/fire/death 各 9 时刻，共 36；未绑定顶点 0，最大权重误差 2.98e-8，边长比例 0.244～2.025。修复肘内侧最近骨段选择导致的权重跳变，源审计已纳入 v5 导出前门禁。该检查不声称完成所有自相交的精确碰撞检测。
- 最终 GLB 5702840 字节，MD5 `b15b034f4dcba4750c32098d02d14d43` 与 Godot source_md5 一致；重新导入后运行新进程 runtime_checks，共 110 项检查零失败，覆盖资产、生产、战斗、快照、上下坡、停止、实际 UI 和尸体重置。100 人 / 60 帧动画 CPU 采样最终 1.91665 ms/帧；非 GPU/整场 FPS 基准。
- 最终动作实景：idle/jog/fire/death 四图保存成功、failures=[]，实际腿骨累计变化 3.549 rad；检查抬枪、死亡和清理。模型前/后/三视/红蓝、头盔法线开关/侧光共 7 图，加四动作共 11 张正式交付，统一位于 `assets/concept_art/mobile_infantry/v5/`，无需按临时截图清理。
- 素材库：23 项归入单位分类并关联，运行模型标题为 v5，GLB 封面已确认 saved=true；API 解析 4308 三角面 / 2 材质 / 6 动作 / 无外部依赖。BLEND 封面 API 不支持，使用关联预览，不改库功能。
- 选择 Light -Area Visual,Performance；固定 version 预检因 toolchain.local.json 缺失失败，完整 Light 未运行，专项不等于整个 Light 通过。本轮未改变网络、模拟或生产协议，不重复完整 ENet；既有联机验证记录保留。无导出或 EXE smoke。
- 收尾：游戏经 MCP 停止；ReportOnly 确认原素材库 node PID 127056 / TCP 8810，保护原服务，不运行广泛 StopUntracked。Blender 原 soldier.blend / Scene 未保存或关闭；git diff --check 通过；无提交/推送。

## 2026-10-09：机动兵 v4 独立骨架与玩法

- 交付：`assets/models/mobile_infantry.glb`、`assets/models/source/mobile_infantry.blend`；独立骨架 23 变形骨 + 6 源控制骨。源网格 2652 顶点、2496 四边面、0 N-gon；未绑定顶点为 0，每点最多 2 权重，归一化最大误差 2.98e-8。IK 控制在源文件中，约束为编辑用途且默认 muted；运行使用烘焙动作，不依赖 Blender 约束。
- GLB：4992 三角面、1 网格、2 材质、2048 PBR，只有肩甲阵营换色。六个动作 RESET/idle/walk/jog/fire/death。文件 4998860 字节，MD5 `9b677b12833d2d1796e7ba14ed10be25`，与 Godot source_md5 一致。
- 导入后 MCP 资产套件 3 测试 / 43 断言通过。为排除 GDScript preload 热缓存，新启动 `mobile_infantry_runtime_checks.tscn` 再执行资产及玩法套件，并覆盖真实 EntityVisual 上下坡/低谷往返、有限骨骼矩阵、高度连续、停止后闲置、射击抬枪、死亡头部落地、真实 UI 混选生产、移除与死亡区分、地图重置，共 103 项，failures=[]。
- 实机 `mobile_infantry_animation_preview.tscn` 保存 idle/jog/fire/death 四张正式预览，保存成功，实际腿骨累计变化 3.577 rad、射击武器抬高 >1.30 模型单位，死亡从模拟立即移除、表现于 1.8 秒内清理；无本轮运行错误。图在 `assets/concept_art/mobile_infantry/mobile-infantry-action-*-v4.png`。
- `mobile_infantry_network_preview.tscn`：两个独立 SceneMultiplayer、127.0.0.1:24561 的真实 ENet、本项目实际 RPC；握手/分配客机阵营/客机生产/移动权威与快照/死亡事件与移除均通过。仅同进程本机测试，非跨机、多进程或丢包回归。协议更新为 rts-mobile-infantry-7，不兼容旧版连接。
- 性能限度：100 个真实蒙皮实例，60 帧动画采样平均 CPU 1.884 ms/帧；未覆盖完整场景 GPU、阴影和多人高负载，不宣称整场帧率达标。
- 选定 Full（跨模拟、表现、UI、网络）；run-godot 固定入口预检仍失败：toolchain.local.json 缺失。因此 run-validation Full、完整多进程 ENet 尚未执行，不以专项冒充 Full 通过。未运行无关导出/EXE smoke。
- 新增 SceneTree 入口 `tests/mobile_infantry.gd`，纳入固定 Full / Light Visual；PowerShell AST 解析通过。入口的 scene 推断编译错误已以显式 Node 类型修复，重新扫描通过；受工具链缺失影响，尚未从固定包装器执行该入口。
- 素材库重扫后运行 GLB 元数据为 v4，API 确认 6 动作、4992 三角面、无外部依赖；7 个当前资源统一单位分类并相互关联，原外观封面保留。四张动作图属正式交付，临时诊断场景已删除。
- 收尾：MCP 停止本轮游戏；ReportOnly 识别原素材库 node PID 127056 / TCP 8810，继续保留；未运行会停止原服务的广泛 StopUntracked。Blender 用户原 soldier.blend 未保存/关闭。git diff --check 通过，仅既有 CRLF 提示。无提交、推送或导出。

## 2026-10-09：机动兵 v3 肩甲阵营色与表面法线

- 结构：78 部件、2496 四边面，0 源三角面/N-gon；全部闭合、正体积、无退化。234 UV 岛、10px 间隔；4992 个 UV 三角形 / 40588 候选对，无正面积交叠。
- GLB：4992 三角面、1 网格、2 材质、3 张 2048 内嵌贴图、无外部 URI；仅 ShoulderArmorL/R 使用阵营材质。头盔无中性法线覆盖，高源几何和高度细节共同烘焙；高度源图只保存在源资产，不进入游戏 GLB。
- 源文件读取检查：一个角色场景、两个低/高源集合、157 对象、4 张图；未包含摄影棚或用户 soldier.blend 内容。源高度图已 packed，运行低模法线连接在对比渲染结束后恢复。
- 最终导入：GLB MD5 4fd24f41a83a0c963e64dbb8106e6740 与 .godot 导入记录一致。Godot MCP 专项 3 测试 / 34 断言通过，含导出肩甲实际顶点位置检查、独立换色、PBR、预算和源报告。MCP 有通用 preload 缓存提醒，本次模型使用 IGNORE_DEEP，实景为新启动进程；未改玩法脚本依赖。
- 目视：真实低模白底前/后/三视/红蓝图、同机位头盔法线开启/关闭、侧光浅刻缝；最后细化后复查近景。荒漠样板新进程输出正常缩放/近景/原生 220px 裁图，3 个保存返回码 0，运行日志无本轮错误。编辑器保留 v2 已修复 screen 类型推断的历史行，不作为本轮新错误；当前脚本明确 Vector2 且实景运行成功。
- 资源库：24 项全部为单位分类，每项 23 个关联；GLB 封面与标题为 v3。10 张预览均为本轮正式效果交付，非默认清理的功能验证截图；v2 源模型已归档。
- 选择 Light -Area Visual；固定 Godot version 入口因 toolchain.local.json 缺失失败，因此完整 Light Visual 未运行。未执行无关 Full、ENet、导出或 EXE smoke。MCP 专项不等于整个 Light Visual 通过。
- 收尾：本次实景通过 MCP 停止。ReportOnly 在受限环境返回无进程/端口，但个人库 HTTP 可访问，故不能据此声称全部进程已清空；未运行会停止原服务的广泛 StopUntracked。保留原有 Blender/Godot 和个人库；无新增驻留服务、无提交/推送。

## 2026-10-09：机动兵 v2 参考重制

- 资产检查：低模源 2752 四边面、0 N-gon/三角面、部件正体积/流形/非退化；258 UV 岛、10px 间距，5504 个 UV 三角形检查 47892 对无正面积交叠。游戏导出 5504 三角面、1 网格、2 材质、3 张 2048 内嵌图，0 外部 URI；独立高模未进入 GLB。
- 源 BLEND 只含新角色的低/高模集合和根节点，3 张 packed 图，无摄影棚或原有用户模型。用户原 Blender 场景及未保存状态未覆盖。圆顶使用原有平滑法线避免窄冠部转移条纹，其他部位保留高模法线，AO 为局部部件烘焙。
- Godot：独立扫描/重导入；mobile_infantry 专项 2 测试/28 断言涵盖预算、材质、换色、AO/法线/粗糙度、报告匹配及无骨骼。读取新 PackedScene 使用 CACHE_MODE_IGNORE_DEEP；另由新运行进程验证，避免编辑器旧资源缓存。
- 渲染验收：白底四图与真实荒漠场景三图。独立场景冻结模拟、使用游戏光照与镜头，3 名静态预览角色显示高度68；日志报告模型5504三角面，原比例/裁图/近景保存均返回0。三视图检查轮廓、握枪和头盔穿插，游戏尺寸检查阵营色和接地。
- 常规级别为 Light / Visual，但固定入口 `run-godot.ps1 -Action version` 因 `.codex/toolchain.local.json` 缺失失败，整套未运行。Full、联网、生产玩法、EXE 不适用。ReportOnly 保留原个人库 PID 127056 / 8810；只停止自有预览游戏，保护原有编辑器与未保存场景。
- 最终核对导入记录 source_md5 与 GLB 内容一致；最新游戏日志3张保存均OK。素材库21项单位分类与模型封面可读取；灰模过程图已回收，七张交付预览保留，文档 diff --check 通过（只有换行提示）。


## 2026-10-08：机动兵静态资产

- 范围：静态模型、材质、UV、独立预览；选择 Light / Visual。未改变玩法/联网/兵营生产，Full、Simulation、ENet、EXE 导出/冒烟不适用。
- 导入独立执行：Godot MCP filesystem scan + mobile_infantry.glb reimport 成功。专项 `mobile_infantry` 2 测试、23 断言通过，包含 4480 三角面、1 网格、2 PBR 材质、2048 内嵌贴图、独立阵营面、无骨骼与报告约束。MCP 有预载缓存提示；本轮创建新脚本且没有修改旧预载依赖，重导入后另以新运行进程检查实际画面。
- Blender 验证 2240 源四边面、0 三角面/N-gon、无退化面、部件流形和正体积、UV 范围/10px 间距。独立 UV 三角形裁剪检查 4480 面、36214 对，正面积交叠 0；源文件 69 对象（68 部件+根）、2 材质、3 张 packed 图，GLB 0 外部 URI。
- 4 张正式 Cycles 设计图目视检查并留存；Godot 独立 preview 场景红蓝换色/材质/几何/投影复查，启动报告无错误。四张过程验证截图已通过固定 recycle-art-files 入口回收，不保留临时图。源 GLB 和素材库结构统计一致；15 项分类、关联和模型封面已保存。
- 限制：本机 toolchain.local.json 缺失，Blender 固定入口实测失败；Light Visual 总入口还会清理原已有服务，因此未运行整套常规验证。未修复该环境配置，不声称 Visual 全部通过。
- 进程：MCP 停止本次预览游戏；保留任务前已打开且未保存的 Blender、Godot 编辑器以及个人库 PID 127056（`node.exe .../tools/art_library/server.mjs`，127.0.0.1:8810）。ReportOnly 确认个人库；保护已有共享进程优先，未运行会关闭它的全量 cleanup。


## 2026-10-08：科技风 UI 六张效果图

- 内置 imagegen 生成 D/E/F 三种士兵界面，分别编辑对应兵营状态；检查后发现首次兵营图漏掉部署文字，通过局部编辑补齐，最终六张均已目视检查。
- UI 主要中文、头像/完整建筑肖像、选中标记及组内框架风格可读且一致；兵营含已部署、生产队列和训练/升空/集结点。保持同一荒漠战场供对比。均为概念示意，画面数值与快捷键未写入游戏。
- 六图写入 `assets/concept_art/ui_selection/` 的 d/e/f 开头 v2 PNG；素材库 API 确认每张 1672×941，界面分类及配对关联保存成功。提示词 JSON 可解析，concept_art 仍被 Git 忽略，旧六张 v1 图保留。
- 仅文件/设计与本地索引检查，不运行 Light/Full、Godot import、ENet 或 EXE 导出。使用原已运行的素材库，无新增服务与临时验证截图，不关闭用户已有服务。

## 2026-10-08：图片分类与前后浏览

- `run-art-library.ps1 -Action test`：138 项通过；隔离目录 `.local/art-library-test-Fti6vR`，真实个人库数据未被测试修改。
- 新增 32 项覆盖分类校验与无部分修改、去重、正式图片归类、重启持久化、元数据/文件字节保留；55 张队列跨首批 48 张、筛选排序与重开刷新、单张/首尾边界、分类不丢草稿、保存/放弃/取消及保存失败保护、输入中方向键不导航、延迟旧响应不覆盖、混选批量归类、390px 预览。
- 桌面、手机及原功能截图共 8 张已检查：分类入口、左右按钮及计数可见，手机无横向溢出，GLB 预览仍正常。验证完毕按清单回收，不作为长期附件。
- Light / Tooling 未通过：缺少本机 `.codex/rules/local-toolchain.rules`；这是已有配置问题，未修复或修改权限。其 cleanup 已通过。Full、游戏/ENet、Godot import、EXE export/smoke 均未执行：不涉及游戏源代码、资产及分发行为。

## 2026-10-08：单项/批量回收与截图清理

- 最终固定资源库测试 106 项 PASS；覆盖预检查去重/未知 ID/保护项、原位置文件移除、仅所选版本、重复票据拒绝、确认后内容变化拒绝、批量部分失败、重启状态、同路径校验恢复、错误内容不继承身份、删除后编辑元数据仍保留归档关联、模拟回收后索引保存前中断。专用一次性文件实际进入 Windows 回收站；恢复索引测试使用隔离假回收站移动文件模拟 Windows 还原，不宣称测试了 Explorer 的还原按钮。
- 浏览器真实点击单项/批量回收：确认显示路径，受保护模型被跳过，加载结果全选与清空、列表刷新均通过；预览/动画/封面/上传和 390px 无溢出回归通过。stderr 为空，控制台错误、页面错误、外部网络请求均为零。
- 历史清理 188 成功、0 失败、20 保护跳过；报告 `.local/verification-history-cleanup.json` 记录 SHA256、文件路径与输出证据。原正式地图预览引用保留；未删除材质/GLB/BLEND/设计效果图。
- 本轮验证截图已目视检查后按清单回收（17 张）；截图文件不再保留，文字结果与每轮 `.local/art-library-test-*/screenshots.json` 保留。不应继续依赖旧验证截图链接作为永久文档附件。
- Light Tooling 已尝试但因本机 `.codex/rules/local-toolchain.rules` 缺失未能执行自检；本轮没有游戏代码/正式资产修改，Full/ENet/Godot 导入/导出跳过。
- 最终文件检查：188 个已回收路径均不存在，临时验证目录剩余 PNG 为 0，UI 方案六张均保留；文档 diff 检查通过。固定 StopTracked/StopUntracked 和独立 ReportOnly 均确认项目进程与 24560/8766/8810 端口为空，个人库服务已停止。

## 2026-10-08：分类与文件重命名

- `run-art-library.ps1 -Action test`：85 项 PASS，`.local/art-library-test.log.err` 为 0 字节。新增分类/改名/非法名称/重复名、旧索引备份迁移、运行资源与源文件保护、引用与 .import/.uid 拒绝、中文和大小写文件名、ID/分类/校验/版本/关联/缩略图保存、旧路径复用、同目录目标竞态、保存失败回滚、启动时提交前后恢复全部通过。
- Edge 实际点击验证：只读详情按钮禁用但可编辑元数据，新增空分类、分类改名、分类继承导入、双筛选、显示名称不改文件、实际改名保留显示名称、刷新页面持久化、窄屏分类编辑。原有预览/动画/上传/封面测试通过，控制台错误/脚本错误/外部网络请求为零，运行模型内容校验未变。
- 真实本机服务启动：403 个资源、5 个分类、schema 2，原 catalog.json 的 schema1 备份存在；未对真实用户资产执行测试改名。图片逐张抽查总览、窄屏及新增 library-rename.png。
- Light Tooling 已运行但失败：缺少 `.codex/rules/local-toolchain.rules`，本机工具链未配置；未修复该环境问题，不算通过。Full/ENet/Godot import/EXE 无影响而跳过。
- 固定 cleanup StopTracked/StopUntracked 通过，项目进程与 24560/8766/8810 端口为空；共享 MCP 识别因工具链未配置发出警告，未停止归属不明共享服务。

## 2026-10-08：选中单位 UI 效果图

- 六张 PNG 逐张目视检查：三种风格、士兵/兵营肖像匹配、主要中文标签清晰、兵营生产队列与训练/升空/集结点入口可辨。
- 仅概念图与日志，不运行 Light/Full、Godot 导入、ENet 或 EXE 导出；未启动需清理的服务。
- 文件位于被忽略的 `assets/concept_art/ui_selection/`；提示词和参考图关系归档为 `prompts-v1.json`。

## 2026-10-08：个人美术资源库

- 固定 run-art-library.ps1 -Action test：39 项 PASS，日志 .local/art-library-test.log，stderr 空。接口验证原资源索引、SHA-256/GLB 统计、缩略图、Range、loopback 绑定、Host/跨站/会话令牌限制、路径穿越/类型/无效 GLB/超限上传、同名多版本、元数据重启持久化及 HTML 下载隔离。
- Edge 无头浏览器实际验证搜索、图片背景/缩放/重置、GLB 加载与动画播放/暂停/切换、备注保存、双栏比较、选文件与拖放上传；正式项目 13 模型封面生成，395 项资源索引，390px 页面无横向溢出。全程脚本错误/控制台错误/外部网络请求为零，源模型 SHA256 未变。未声明 Godot 程序动画等同于网页动画。
- 四张截图位于 assets/concept_art/art-library：library-overview.png、library-models.png、library-barracks.png、library-mobile.png；白模修复后重新生成并目视复核总览与兵营详情。模型封面缓存复制到个人库，未把测试导入或测试备注带入正式个人库。
- 固定 start/重复 start/stop 已验证实际服务及幂等启动；本机地址 http://127.0.0.1:8810。批处理的浏览器自动打开未在交互桌面运行，底层固定启动入口和页面已分别验证。
- 已选择 Light Tooling；原有权限自检因缺少 .codex/rules/local-toolchain.rules 失败，不能记为通过。该机尚未运行新工具登记流程，未在本轮改动 .codex 权限规则。无游戏改动，跳过 Full、ENet、游戏导入和 EXE 导出；未提交或推送。
- 最终固定 cleanup -StopTracked -StopUntracked 以及 -ReportOnly 通过：项目进程为空，24560/8766/8810 端口为空。服务未常驻；使用 start.cmd 重新启动。缺失本机工具登记导致共享 MCP 识别警告，未终止归属不明进程。

## 2026-10-07：加强跑步辨识度

- 最终 Light Visual/Performance：.godot/validation/20261007-232546-23700/，全部通过，20.503 秒。覆盖动作、模型、180 人双地图性能、地形与握枪；部分既有测试的单个 ObjectDB 退出警告仍在。
- 稳定跑步：腾空采样 127 / 420，单脚支撑 155；骨盆起伏 .12997，实际抬脚最高 14.80995，膝角最小 66.77°。枪/护甲包络最小间距 .01361，握点/骨长/立即开火与启停均通过。
- 连续性：30/60/144FPS、主客端曲线、不同速度、坡道、急转/短停均通过。接地误差 .05018、单帧最大滑移 .000244 世界单位；设计回弹与 IK 修正分开断言，保留原额外修正限值。
- 渲染：.godot/soldier-clear-run-preview.log，无 stderr；保存 32 帧近景与 32 帧远景（15Hz 骨骼）循环。180 人三轮平均 6.028ms，365 绘制调用、611642 图元。[同步动态对比](../assets/concept_art/soldier_clear_run/index.html)保留上一版朝下持枪作为对照。
- 实机地图：.godot/soldier-clear-run-game.log，SOLDIER_PREVIEW PASS after，stderr 空；曲线最低骨盆 1.14125、最大单帧下降 .04094；上下坡、转弯/停止及正常镜头截图独立保存至 soldier_clear_run/game。完整地图 180 人平均 24.871ms、P95 54.754ms，包含地图与模拟开销。
- 本轮无模型资源变化，不需要重新导入；未改网络/模拟协议，不运行 ENet，不导出 EXE。

## 2026-10-07：跑步纵向朝下携枪

- 最终 Light Visual/Performance：.godot/validation/20261007-231321-26364/，全部通过，20.615 秒。包括 visual_models、soldier_locomotion、soldier_rig、两地图 visual_performance、terrain_presentation、terrain_sample_view。部分原有测试仍有单个 ObjectDB 退出警告。
- 新增几何检查：完整平地跑步周期最小枪/护甲包络间距 .03114；加入转弯、上下坡和启停后最小 .01735。逐帧握点、手臂骨长和真实射击响应通过；原腾空 63、单脚支撑 186 采样保持，原步态接地和滑移上限保持。
- 实机地图：.godot/soldier-vertical-game-preview.log，SOLDIER_PREVIEW PASS after，stderr 空；覆盖正面、上坡、下坑、返回、转向停步、曲线，42 张截图独立保存。180 人完整地图平均 24.442ms、P95 56.1ms（含地图及模拟，非纯动画基准）。
- 独立预览与渲染：.godot/soldier-vertical-preview.log，stderr 空；32 帧跑步循环及近景截图已检查。180 人独立场景三轮平均 6.262ms，365 绘制调用、611642 图元，供记录，不与完整地图数据混比。
- 本轮没有模型资源变化，不需要重新导入；没有模拟/网络或打包变化，未运行 ENet 或导出 EXE。[动态前后对比](../assets/concept_art/soldier_vertical_carry/index.html)存于 Git 忽略的用户预览目录。

## 2026-10-07：右下角战术命令图标

- SVG 独立导入通过：.godot/command-icons-import.log，无 SCRIPT ERROR/ERROR。
- 最终 Light ActionBar/Presentation：.godot/validation/20261007-225115-26300/，全部通过，3.511 秒；覆盖图标/提示/费用、攻击改键/高亮、矿车混选、生产取消、起降状态、取消选择清理、刷新夹在鼠标按下/释放之间仍能点击，以及两种窗口尺寸的布局。presentation 仍有既有单个 ObjectDB 退出警告。
- 兵营三地图集成：.godot/command-icons-barracks.log，BARRACKS_INTEGRATION PASS failures=[]。
- 实机渲染：.godot/command-icons-preview.log，ACTION_BAR_TEST failures=[]，stderr 空；1920×1080 与 1280×720 各保存单位、兵营、基地悬停提示三张截图，位于 assets/concept_art/command_icons/。已目视检查图标及提示，无命令区溢出。
- 未运行模型/性能/ENet 全量或导出：本轮只改八个命令按钮的界面表现，无模拟、模型或网络接口变化。

## 2026-10-07：肩甲覆盖与双手低位携枪跑步

- 构建：`.godot/soldier-run-build.log` PASS，20 骨、9,800 / 3,398 / 875 三角面、每档两个材质分面；源保持独立 soldier.blend。肩甲原绑定上臂且甲片绕序朝内，已改为锁骨绑定、增加封闭内衬并修正绕序；每块甲片导出前有向体积 >0。`.godot/soldier-run-import.log` 导入通过、stderr 空。
- 专项：最终 Light 内 soldier_rig PASS，覆盖每档肩标锁骨权重、共享蒙皮/材质/贴图、双手接触和手臂长度、低位枪口俯角/枪托胸前净空、50ms 抬枪/放枪完成、射击即时抵肩、击杀当帧清除命令后仍保持后坐，以及原始即时移动/停止/掉头/伤害/12tick 射击间隔。420 个稳定跑步采样含 63 个双脚实际离地、186 个左脚支撑采样，并检测到摆腿膝关节折叠 <95°。
- 步态：soldier_locomotion PASS，30/60/144FPS、主客端位移、50/100/150 速度、坡面/曲线/急转/短停通过；最大接地误差 0.05019 世界单位，站立脚滑移 0.000245，紧弯骨盆最大下降 0.033001（原阈值 <0.04）。携枪转换幅度增加，转换帧阈值按混合增量增加，稳定步态仍保留 <0.15；观测转换枪口最大帧移 0.40948 模型单位，没有放宽四肢长度或地面接触限制。
- 实机：`.godot/soldier-run-game-preview.log` PASS，样板地图前向、转弯、上坡、下坑、返回和停步；骨盆最低 1.10462，最大下降 0.02020。完整游戏 180 人场景平均 23.020ms、P95 52.913ms。已检查近景跑步侧面/斜前、攻击背面和远景红方截图，甲片外壳正常显示。
- 性能对照：`.godot/soldier-run-before.log` / `soldier-run-after.log`，同镜头 180 名士兵独立场景、相同速度与采样数、关闭 VSync，前后各三轮。之前 5.621 / 5.549 / 5.612ms；之后 5.690 / 5.579 / 5.610ms；平均 5.594 → 5.626ms（+0.58%），满足不超过 5% 的回退预算。绘制调用均为 365，图元 612,002 → 611,642。数据与[前后对比/32帧跑步循环](../assets/concept_art/soldier_run_carry/index.html)保存在用户管理的 concept_art，不加入 Git。
- 最终分区：`Light -Area Visual,Performance` PASS，15.388 秒，`.godot/validation/20261007-222820-10636/`；visual_models、soldier_locomotion、soldier_rig、双地图 visual_performance、terrain_presentation、terrain_sample_view 和 cleanup 全通过。保留既有 ObjectDB 退出警告。未改模拟/网络合同/打包，未重跑完整 gameplay、ENet 或 EXE；实际即时玩法由专项验证。
- 开发问题与修复：首次混合读取与 wrapper 调用触发继承 Path/PATH 冲突，改用独立固定 wrapper 调用后生成通过，未更改环境安全设置；补充击杀当帧姿态时出现 should_aim 类型推断失败，改为显式 bool 后完整重跑通过。失败套件被中止时曾与后续测试启动发生清理竞态，等待该套件结束后再重跑；最终固定 cleanup 确认无项目进程及 24560/8766 端口，另做 ReportOnly 复核。

## 2026-10-07：士兵动作与 RTS 渲染优化

- 构建/导入：`.godot/soldier-build-v3b.log` 与 `.godot/soldier-import-v3b.log` 通过，stderr 空。独立源 soldier.blend，不覆盖其他单位源；20 骨、三档 9,800 / 3,400 / 880 三角面、两个材质分面。GLB 导出和运行时实际资源预算分别检查。
- 专项：`tests/soldier_rig.gd` PASS，最终 `.godot/soldier-rig-final.log`。验证全部 LOD 的骨序、逆绑定、权重、共享材质纹理、1024 图集、双手接触与手臂长度、枪口随枪、首快照不补射、同帧不重射、真实 cooldown 后坐、滞回、60/30/15 次每秒求解、离屏相位累计和回屏重建。直接 Simulation 检查移动首帧满速、掉头无等待、停止无惯性、攻击首 tick 扣血且 12 tick 间隔不变。
- 原步态回归：30/60/144FPS、50/100/150 速度、主客端位移输入、急转/曲线/坡道/短停全部通过。脚底最大高度误差 0.05019 世界单位、站立脚滑移 0.000245、过渡枪口单帧位移 0.13844 模型单位。即时瞄准方向切换由 soldier_heading_checks 检查，不再要求该指令帧满足旧的延迟转向平滑限制。
- 分区验证：`Light -Area Visual,Performance` PASS，16.267 秒，`.godot/validation/20261007-215135-25120/`；运行 visual_models、soldier_locomotion、新增 soldier_rig、双地图 visual_performance、terrain_presentation、terrain_sample_view，全部零失败。既有单个 ObjectDB 退出警告保留。未改模拟和网络合同，未重跑完整 gameplay/ENet；即时玩法行为由上述专项验证。打包未变，不导出 EXE。
- 渲染预览：`.godot/soldier-game-preview-v3.log` PASS，真实样板地图转向、停步、曲线、上坡、下坑及返回；曲线骨盆最低 1.05091、最大下降 0.04314，符合实机原阈值。完整游戏 180 人移动平均 23.979ms、P95 52.867ms、游戏 CPU 18.829ms，仅作为当前整场景观测。
- 公平对照：`tests/soldier_quality.gd` 在同机器、同镜头、同 180 人/速度/帧数、禁用 VSync 条件前后各三轮。旧帧耗时 19.486 / 19.586 / 19.440ms；末轮新耗时 5.563 / 5.555 / 5.584ms，均明显优于 +5% 回退上限。平均动画 CPU 4.220 → 3.284ms，GPU 15.513 → 2.767ms，可见绘制调用 1,085 → 365，可见三角图元 1,736,282 → 612,002。仅代表该独立渲染场景，不等于整场游戏帧率提升 71%。JSON、同镜头姿势样本、三档蓝红截图和[对比页面](../assets/concept_art/soldier_upgrade/index.html)在 assets/concept_art/soldier_upgrade/，不加入 Git。
- 开发问题及修复：旧导入配置丢弃图集导致发黑，改为内嵌 Basis Universal 后重导入，实际纹理与渲染通过；首版抬枪幅度过大导致枪口跳动，缩小准备姿势与瞄准姿势差值后保留原 <0.15 阈值通过；曲线骨盆落差过大，降低关键姿势垂向幅度并恢复行进蹲伏后通过。未用增加操作延迟解决表现问题。
- PowerShell 语法解析通过，最终源码空白/UTF-8/预览路径检查及固定 cleanup；保留现有工作树改动，不上传。

## 2026-10-07：兵营定向飞行与背部双推进器

- 原问题与修复：兵营移动只同步位置，导致任意方向均为横移；新增主机 heading，以 90°/秒原地转向后前进，到部署点先恢复默认朝向，再复查落点及降落。更新快照类型/范围校验与协议版本，世界表现插值朝向，排除通用单位回正对兵营的覆盖。
- 构建：固定 run-blender 生成三档生产 GLB，日志 `.godot/rear-engines-build.log`；新增背部双喷口，原基线未修改。97 帧机械净空与底盘保留检查通过，已有贴图/动画嵌入校验通过。首次生成的本地化节点名问题已改为按节点类型查找并重跑成功。固定 import 成功，日志 `.godot/rear-engines-import.log`，stderr 空。
- 专项：`barracks_heading.gd` 558 项检查通过，日志 `.godot/barracks-heading.log`，包括四向、两秒掉头、转向暂停平移、停止、部署转正、落点晚到阻塞、阶段快照恢复、非法朝向与角度边界。远端地图完整斜线逐帧检查曾发现临近目标重新转向停顿；修复为 0.001 弧度浮点容差后全部通过。原飞行规则 46 项通过，日志 `.godot/barracks-flight-direction.log`。
- 实机：`barracks_rts.gd -Rendered --skip-benchmark` PASS，日志 `.godot/barracks-rear-render.log`；可见三角面近/中/远为 8333/4163/1487，surface 为 41/41/27，PBR 贴图及远景颜色回归通过。四向尾焰反向、转向/悬停/隐藏关闭和三档喷口保持通过。已查看[背部推进](../assets/concept_art/barracks_rts/direction-0.png)、[另一方向](../assets/concept_art/barracks_rts/direction-90.png)和[悬停](../assets/concept_art/barracks_rts/rear-engines-hover.png)。
- 三地图 `barracks_integration.gd -Rendered` PASS，日志 `.godot/barracks-direction-integration.log`，实际 UI 的右键转向/推进、S 停止尾焰、部署及跟随光圈回归通过。
- 分区验证：`Light -Area Simulation,Visual,Network,Performance` PASS，256.538 秒，日志 `.godot/validation/20261007-185234-20048/`。运行 gameplay、arrival_formation、visual_models、soldier_locomotion、双地图 visual_performance、terrain_maps、terrain_presentation、terrain_sample、terrain_sample_view，以及 prototype/desert_quarry 完整 ENet。网络加入实际转向后移动、停止角度保持和降落恢复默认朝向的断言；原有版本拒绝、观战权限、采矿、生产、战斗、完整快照一致、重连/重开/主机断线全部通过。
- 首轮网络在荒漠战斗阶段被外层 110 秒上限中断，日志 `.godot/validation/20261007-184648-27172/`；兵营迁移阶段已成功。外层时限改为 185 秒，与测试内部既有 180 秒超时检测配套；增加攻击阶段日志，最终完整通过。PowerShell 语法解析及 `git diff --check` 通过。
- 限制：既有单个 ObjectDB 退出泄漏警告仍存在，本轮未处理。使用定向 Light 覆盖实际影响，不运行无关 Camera/ActionBar 等完整套件；未运行单独 1/16/64 建筑绘制基准，已有模型预算检查及通用 Performance 通过。未改打包，未导出 EXE。最终固定 cleanup 返回 PROJECT_PROCESSES none，24560/8766 端口无残留；未新增长期服务。

## 2026-10-07：兵营选中光圈随本体升降

- 问题与修复：`world_visual_sync.gd` 原先用 `ground - visual.position.y + 0.6` 抵消建筑升空高度，导致光圈始终停在地面。兵营存在 flight 状态时改用固定局部高度 0.6，由父节点带动光圈跟随插值后的建筑位置，覆盖起飞、悬停、移动与降落；其他建筑保持原逻辑，光圈半径、材质与水平朝向不变。地面阴影和降落格保持原行为。
- 回归：扩展 `tests/barracks_integration.gd`，在 prototype、desert_quarry、desert_sample 上验证地面偏移、起飞及降落中间帧、实际插值高度、悬停、横向移动、取消选中与空中重新选中。渲染运行 `BARRACKS_INTEGRATION PASS failures=[]`，日志 `agent_md/barracks_selection_ring.log`，stderr 为空；原有部署阻塞、快捷键与落地检查也通过。
- 实机截图：[样板地图升空](../assets/concept_art/barracks-v4-game-desert_sample-airborne.png)，已检查光圈位于建筑底部、投影仍在地面；同轮生成三地图蓝红地面/升空及部署提示截图。
- 通用验证：`Light -Area Visual` PASS，25.413 秒，visual_models、soldier_locomotion、terrain_presentation、terrain_sample_view 全部通过。已有单个 ObjectDB 退出泄漏警告仍存在；固定 cleanup 确认项目进程及端口无残留，保留共享 Blender MCP。
- 本次仅调整选中表现，未改模型资产、模拟、网络或打包，因此未重新导入资产、运行 Full/ENet/性能基准或导出 EXE。修改仍在 `.godot/barracks-rts-optimization`，未合并、提交或推送。

## 2026-10-07：兵营表面材质做旧

- 原因与修复：此前基色变化约 1.5%、粗糙度扰动最多 0.035，积灰主要在底部；最近减面只重烘焙法线，基础色及 ORM 与原版 SHA256 完全相同。按用户选择的“明显使用过、维护良好”，新增 `tools/blender/barracks_weathering.py`，在原 UV 上重新烘焙 2K 基础色和 ORM：装甲明暗分区、屋顶与接缝积灰、设备周围局部熏黑、墙面纵向雨痕、边缘擦损、坡道通行磨损，以及涂装/金属/橡胶的粗糙度与金属度区别。灯、旗帜、阵营色及满血/损伤状态仍独立。
- 边缘定位：烘焙时按原网格连通部件计算包围盒属性，定位每块装甲的边缘，避免 Pointiness 在导入的分裂法线上把整个平面变成均匀斑点。首版喷点效果已替换，不作为交付图。
- 当前生产模型只替换 GLB 内两张图片及 LOD2 顶点颜色；逐项校验顶点、索引、法线、UV、形态键、节点及动画数据摘要，与保留的修改前模型一致。三个 LOD 仍为 7,981 / 3,943 / 1,483 三角面、37 / 37 / 35 材质分段，远景可见 1,387 三角面；没有添加运行时污渍贴片、着色器或贴图采样槽。
- 构建路径：`optimize_barracks_rts.py` 已接入新材质生成，防止下次重建恢复旧贴图。在独立预览输出目录从原始模型完整重建，`WEATHERING_REBUILD_CHECK PASS`，原有每档 97 姿态检查、底盘覆盖、面数及材质预算通过；最终远景颜色转换另执行 `WEATHERING_FINAL_FAR_BUILD PASS`。生产模型仍采用保留几何数据的材质替换结果。
- 本轮修复的关联问题：glTF UV 的 V 方向与 Blender 像素数组相反，初版直接取样导致远景过黑；已翻转 V 并将基色 sRGB 转为线性顶点色。新增运行时采样回归，最终平均颜色误差 0.00223（含 Godot 顶点颜色量化）。同时在阵营色中性化前复制 Image，避免无界面资源返回共享图像时把主体贴图一同去色；渲染与无界面检查都验证主体贴图没有被修改。
- 同镜头、灯光与曝光的对照：[近景蓝方](../assets/concept_art/barracks_weathering/compare-close-blue.png)、[正常距离蓝方](../assets/concept_art/barracks_weathering/compare-normal-blue.png)、[正常距离红方](../assets/concept_art/barracks_weathering/compare-normal-red.png)。同目录另含中景、远景、蓝红升空对照；左 BEFORE、右 AFTER。修改前是已修复底盘的版本，非缺底盘版本。远距离只保留大色块，不承诺能看到细小擦痕。
- 导入及验证：`barracks_weathering_import.log.err` 为空；兵营渲染专项、无界面专项和 14 张前后截图全部通过。专项从生产 GLB 解码新图片，与 Godot 实际材质逐点比较，并检查粗糙度 G / 金属度 B 通道，排除旧内嵌纹理或导入缓存。原有底盘、LOD、灯光、烟火恢复检查仍通过。日志前缀为 `agent_md/barracks_weathering_*`。
- `Light -Area Visual` 最终 PASS，20.843 秒，日志 `.godot/validation/20261007-104220-14972/`：visual_models、soldier_locomotion、terrain_presentation、terrain_sample_view 和 cleanup 全部通过。已有单个 ObjectDB 退出泄漏警告仍存在。无界面检查最初受沙箱日志/证书权限限制，已通过平台批准的固定入口重跑。
- 未增加几何、材质分段、运行时纹理数量或逐帧计算，未重复性能基准；未改模拟、网络或打包，未运行 Full/ENet、未导出 EXE。工作目录仍为 `.godot/barracks-rts-optimization`，尚未合并、提交或推送。预览、修改前副本和原始日志留在本地，不纳入提交。

## 2026-10-07：修复兵营底盘误删

- 问题与根因：优化后底盘外沿和底部承重结构消失，支腿看似与主体脱离。此前将 HullMesh 中 Z < 1.10 的面整体当作隐藏结构删除，并将低处顶点抬至该高度，误伤了可见底盘。下方 10 月 6 日的资产数字与几何处理说明属于修复前记录，以本节为准。
- 修复：从保留的原始 GLB 重建；按完整连通部件分离底盘、孔位顶板、支腿轴承与上部壳体，分别减面后合回原 HullMesh。取消按高度删面和抬高顶点。底盘近/中/远预算为 550/550/480 三角面；远景去掉少量细小锁扣，将预算留给底盘和起落架收纳槽。保持原有层级、枢轴、动画和贴图 UV，重新烘焙两张法线贴图。
- 最终完整 GLB 为 LOD0 7,981、LOD1 3,943、LOD2 1,483 三角面，均在既定预算内；远景隐藏旗帜和细杆后可见 1,387 三角面。材质分段仍为 37/37/35，材质数 6/6/4。
- 构建验证：每档导出后回导，检查底盘中央与两侧承重区域的 9 个向上射线，以及 97 个起落姿态。三个档位底盘采样面相对原版最大高度误差均为 0.00847 模型单位；脚掌、喷口、液压机构的规定穿插检查通过。构建日志 `chassis_repair_build.log` 显示 `BARRACKS_RTS_BUILD PASS`，stderr 为空。
- 回归测试：新增 Godot 底盘覆盖检查，旧资产三个 LOD 共 27 个检测点全部失败（`chassis_regression_before.log`）；最终资产全部通过（`chassis_repair_runtime_final.log`）。同时验证面数、LOD 滞回、材质、状态灯、损伤效果，输出三个档位的仰视截图及正常 RTS 视角截图。原版、近景、中景、远景的 1/16/64 栋渲染对照完整运行；64 栋近景为 4,818 绘制调用，CPU/GPU 12.399/12.925 ms，仅作本机采样。
- 原生渲染检查：底盘外沿、加强梁、四个喷口及支腿收纳空间重新可见。截图在 [落地近景](../assets/concept_art/barracks_rts/comparison-near.png) 与 [升空底部](../assets/concept_art/barracks_rts/chassis-underside-lod0.png)。远景模型只用于战略缩放；强制放大时仍有明显简化和上部表面瑕疵，未将其视为近景品质。
- 起落专项 45 项通过（`chassis_repair_flight.log`）。三地图渲染交互专项复查通过（`chassis_repair_integration_recheck.log`，stderr 为空）；第一次运行有 5 项部署/快捷键相关失败，未改游戏逻辑的复查未复现，原因尚未确认，不宣称解决了该偶发问题。
- Godot 最终导入成功，`chassis_repair_import_final.log.err` 为空。最初沙箱内导入/通用验证出现证书和用户日志/编辑器设置权限错误，通过平台批准的固定入口重跑后排除了这些环境错误。
- `Light -Area Visual,Performance`：视觉模型、士兵动画、地形表现及样板地图视图通过；性能失败，日志 `.godot/validation/20261007-101152-29200/`。180 单位 animated sync 16.065 ms（阈值 8）、unit sync 4.230 ms（阈值 2）、simulation 34.178 ms（阈值 25）；这些项目在此前未修改主分支对照中也失败，本次未放宽阈值或修复整场游戏性能。地形套件仍有既有单个 ObjectDB 退出泄漏警告。
- 未改模拟规则、网络协议或打包，因此未重复 Full/ENet，未导出 EXE。改动位于 `.godot/barracks-rts-optimization`，未合并到根项目、未提交、未推送。预览和原始日志不纳入提交。
- 收尾：固定 cleanup 确认项目进程与端口无残留；`git diff --check` 和本次文本的严格 UTF-8/NUL/尾空白检查通过。保存的原始 GLB 与根项目原模型 SHA256 仍一致，未改动原工作区的模型或 EXE。

## 2026-10-06：兵营 RTS 模型与状态表现

- 工作目录：`.godot/barracks-rts-optimization`，分支 `feature/barracks-rts-optimization`，基于主分支 `c6f86ce`。原工作区、用户 EXE 和原始概念资产保持不变；本轮没有推送或发布。
- 资产预算（完整 GLB）：原版 32,900 三角面 / 66 材质分段 / 14 材质；LOD0 为 7,432 / 37 / 6，LOD1 为 3,751 / 37 / 6，LOD2 为 1,199 / 35 / 4。主体由 20,212 降到 3,600；四个喷口近景合计 1,440。远景隐藏旗面和细液压杆后，实际可见 1,103 三角面、23 分段。
- `tools/blender/optimize_barracks_rts.py` 从 `assets/models/source/barracks_rts_baseline.glb` 重建三个档位。保留外部壳体、动画节点、枢轴、旗帜形态键，去掉隐蔽设备底板与小倒角几何。近、中景由原始高模向低模投射 2K 切线法线，沿用原有基础色/ORM 和旗帜 512 贴图；远景烘焙顶点色。构建先输出到预览目录，预算、动画与回导检查通过后才复制到运行时资产。
- 三档共用一套运动层级，通过网格替换切换；以 1080p 归一化投影尺寸 160/80 像素为界，使用 10% 滞回。升降中最低使用中景，近景旗帜正常更新、中景 10 Hz、远景隐藏旗面。静止机械姿态不再反复 seek；同一建筑的重复材质实例复用。
- 状态灯读取现有队列：就绪常亮、训练慢脉冲、队首 remaining=0 且仍未出队时橙色快闪；升空时开启推进器自发光。HP 低于 50% 出烟、低于 25% 增加间歇火花和屋顶焦痕，最多 8 个烟粒子和 4 个火花粒子；隐藏/离屏停止发射，恢复血量清除表现。保留血条、四秒起降、128×96 占地、当前飞行高度和全部游戏规则；未增加升级、占领或禁用机制。
- 修复：原模型导入配置 `gltf/embedded_image_handling=0` 丢弃 PBR 贴图，导致运行时侧面发黑；三档配置统一保留内嵌贴图，并增加基础色/法线实际导入断言。远景的材质覆盖需显式启用顶点色，否则退化为白模；已修复并增加网格颜色数组及材质开关断言。
- 修复：Blender 的 Image.copy 同时复制旧 packed PNG，普通 pack 会令导出器沿用旧法线；改成读取新烘焙 PNG 后显式 pack 字节，并断言 GLB 内纹理 SHA256 与新 PNG 一致、与原法线不同。两个近景档位均通过该校验。
- Blender 验证：每档导出并重新导入后，运行原有 97 姿态起降间隙、占地、支脚收纳与喷口离地检查，全部通过。近景保留 Takeoff / Landing / Flag_Wind_Loop。原始报告在 `assets/concept_art/barracks_rts/asset_report.json`。
- Godot 验证：先独立 import；`Light -Area Visual,Performance,Features` 中 features、visual_models、soldier_locomotion、terrain_presentation、terrain_sample_view 通过。兵营专项 `barracks_flight.gd` 45 项通过，`barracks_integration.gd -Rendered` 在 prototype、desert_quarry、desert_sample 上通过，包含红蓝、地面/升空、旗帜、部署阻塞和快捷键；`barracks_rts.gd -Rendered` 覆盖预算、LOD 滞回、贴图、灯光、损伤恢复、隐藏/离屏停发与 64/128/256 像素截图。
- 通用性能仍未通过，未放宽阈值：本分支 180 单位 animated sync / visual sync / unit sync / simulation 为 21.392 / 9.710 / 5.695 / 43.714 ms；同机未修改主分支对应 22.624 / 8.431 / 7.957 / 52.495 ms，也在相同四项失败。主分支日志在 `.godot/main3d-integration/.godot/validation/20261006-011324-2040/`；本分支日志在 `.godot/validation/20261006-010951-29524/`。该对照确认原有瓶颈仍存在，不据此声称整场游戏达到帧率目标。Features/地形套件退出时仍有既有单个 ObjectDB 泄漏警告。
- 未改模拟规则、RPC 或快照边界，未重复 Network/ENet；未改打包或要求交付 EXE，因此未导出。性能套件的原型地图先失败，runner 的后续沙漠性能子项没有运行；地图功能和兵营实机测试另行通过。
- 最终内嵌纹理修正后重新 import、运行渲染专项及 `Light -Area Visual`，全部通过；最后一次 Light 为 20.385 秒，日志 `.godot/validation/20261006-023136-25824/`。固定 cleanup 确认项目进程和端口无残留，保留共享 Blender MCP。原始模型与保存的基线 SHA256 一致。改动仍保留为独立工作区中的未提交修改。

同机兵营专项对照：相同着地姿态、镜头、阴影、分辨率和机械控制器；每组预热 20 帧后采样 60 帧，显式网格 LOD，包含阴影绘制。CPU/GPU 是渲染计时，排除玩法与完整同步耗时；结果受电源状态及其他应用影响，不作为 FPS 承诺。1/16/64 个兵营的四档完整数据在 `assets/concept_art/barracks_rts/runtime_report.json`。

| 数量 | 原版绘制调用 | 近景绘制调用 | 远景绘制调用 | 原版 CPU/GPU ms | 近景 CPU/GPU ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 137 | 79 | 51 | 0.523 / 0.890 | 0.447 / 0.712 |
| 16 | 2,117 | 1,189 | 741 | 4.735 / 5.119 | 4.140 / 4.499 |
| 64 | 8,607 | 4,818 | 3,003 | 18.424 / 18.998 | 12.308 / 12.841 |

- 绘制调用和几何负担稳定减少；重复采样中也曾出现 16 个兵营的近景 GPU 读数高于原版，故不将一次计时推广为所有环境下的改善。表格为最终烘焙资产的完整采样结果。预览及前后对照保存在 `assets/concept_art/barracks_rts/`，实机地图截图在 `assets/concept_art/barracks-v4-game-*.png`；概念目录与临时日志不纳入提交。

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
# 2026-10-09 独立机枪 / 机动兵 v6

- 最终重导入后 run45 再验：132 检查零失败，100 人 CPU 1.877ms/帧；机枪源文件 MD5 3f64d145f1c73dddd3926519a02a190c 与 Godot 导入缓存匹配，人物 MD5 467c6e2346a664ba3d37a71264425cf0 匹配。最终预览已 stop。

- 目标级别：Light，Visual + Performance；固定启动器预检受缺失 .codex/toolchain.local.json 阻挡，完整分级套件未执行。既有素材库服务不能作为本次测试进程清理。
- MCP 新进程 run43：132 检查，0 失败。包含独立武器/PBR/UV/稳定挂点、六动作各9次双手采样、坡地移动与停步、UI兵营生产、死亡/重置清理、百单位共享网格和材质。
- run44 实景四动作预览：idle/jog/fire/death 保存成功，0 失败。正式展示图保存于 assets/concept_art/mobile_infantry/v6，武器三个视角位于 assets/concept_art/mobile_machine_gun；没有额外临时验证截图遗留。
- 100 人动画 CPU 约1.853ms/帧；隔离无阴影视口纯人物200 draws、人物+枪300 draws。并非完整游戏 GPU 性能结论。
- 源模型：人物3540 tris，机枪1056 tris，合计4596 tris；源四边面、无ngon、UV实际三角形相交0。Python七个相关脚本 AST 检查通过，scoped diff --check 通过。
- 素材库组合 GLB 验证：2 mesh、3 材质、6动作、无外部贴图依赖，逐动作握持误差接近浮点精度；独立人物 GLB 不包含武器。没有改变战斗数值或网络协议，不运行 Network/ENet。

## 2026-10-09 荒漠自然地形比例草模

- 范围：独立tests/desert_kit_geometry.gd、desert_kit_review.gd及场景；目标级别Light / Visual。生产地图、模拟和网络未在本任务修改，因此未运行玩法/ENet；未请求EXE，不导出。
- 固定run-godot.ps1 -Action version预检再次报Toolchain is not configured；缺失.codex/toolchain.local.json。完整run-validation Light/Visual未运行，不记作通过；其finally全局清理还会停止既有素材库服务。
- MCP扫描后真实运行review场景，最终run50（r62844258-50）：12类组件，96项检查，0失败。包括高度端点、旋转剖面衔接、坡道三段端点、14个GLB导出后回读及三角面计数一致性。
- 五页1920×1080实际画面已保存并检查，最终标签和单位参照可见；输出为正式审阅交付图，无额外临时截图。目录位于assets/concept_art/desert_terrain_kit，保持Git忽略。
- 素材库/api/rescan及元数据回读确认21项，14模型/5图片标题、分类、标签及资源关联已更新；JSON/TXT说明亦已索引。服务仍为127.0.0.1:8810，仅本地访问。
- MCP stop停止本轮预览；固定cleanup-project-processes.ps1 -ReportOnly退出0，只报告既有node PID127056、8810端口。遵守共享进程保护规则，未执行会停止该服务的StopTracked/StopUntracked。
- 限制：开放草模无底盖/碰撞；UV为程序占位，未制作正式PBR/LOD。通行与建造仅作标注，非玩法验收。未在i5-8400/GTX1060硬件上实测，不作200单位60FPS承诺。

## 2026-10-09 删除原型地图

- 目标级别Full（默认模拟、表现及协议均改变）。固定run-godot.ps1预检因缺失.codex/toolchain.local.json失败；Full与完整多进程ENet未执行，不能记为通过。未更改安全/权限设置。
- 替代覆盖：MCP新进程run51—53，.godot/removal_suite_runner.gd仅适配SceneTree的生命周期、root、await、quit，在真实Godot游戏内执行原测试断言。17套最终通过：gameplay、arrival_formation、presentation、features、camera、action_bar、visual_models、soldier_locomotion、soldier_rig、mobile_infantry、visual_performance、terrain_maps、terrain_presentation、terrain_sample、terrain_sample_view、barracks_flight、barracks_integration。
- 首轮失败及修复：战斗测试瞬移/新建单位未刷新视野，原型豁免曾掩盖问题；更新真实视野、将响应测试布置在荒漠平地，run52 gameplay 71项和soldier_rig通过。样板测试旧菜单索引越界且期待无地形；更新两地图索引和真实地形断言，run53通过。未弱化伤害、时序或部署断言。
- 旧岩石测试改为荒漠MultiMesh存在、共享雾纹理及重新生成的变换一致性；run53 visual_models通过。新增旧地图ID/旧版本快照拒绝及失败不改变活动对局检查，run51 terrain_maps通过。
- run51机动兵132检查通过，180单位性能套件通过；此为当前电脑检查，不证明最低配置达标。MCP嵌入窗口的root.size请求未总能改变实际视口，不能作为完整双分辨率验收。
- run54同进程ENet真实RPC：握手、客机兵营生产、移动命令、主机快照和死亡同步，failures=[]；它不覆盖完整多进程重连/观战/退出矩阵。
- 4个专用文件删除已确认，运行源码无prototype/pixel_art/rock.glb/fog_plane/rock_visuals残留；prototype只保留为拒绝用例。限定diff --check和3个修改的PowerShell脚本Parser检查通过。
- 未生成新的验证截图。MCP stop后固定ReportOnly只发现既有素材库node PID127056/8810；专项24561端口TCP/UDP端点0。为保护共享服务，未执行会终止素材库的StopTracked/StopUntracked。无EXE导出、提交或远程上传。

## 2026-10-09 素材库统一多选与删除

- 专项固定入口run-art-library.ps1 -Action test：ART_LIBRARY_TEST PASS checks=162；日志.local/art-library-test.log，隔离目录.local/art-library-test-w9V5uj。新增覆盖五项复选框选择/真实回收、两项比较限制、加载更多保留/搜索清空、改名和删除权限独立、分组大小/路径清单、伴随失败partial、原文件失败跳过伴随、确认后哈希变化/新增引用阻止回收。既有分类、改名、导航、恢复、版本、GLB、移动端回归通过。
- Light -Area Tooling：失败于Required permission file is missing: .codex/rules/local-toolchain.rules；非专项失败，未修改安全配置。清理阶段通过，无残余进程/端口；未运行Godot游戏、ENet或EXE验证，本次仅素材库行为变化。
- 目视复核library-unified-delete.png及library-overview.png；9张本轮截图经固定cleanup-reviewed全部回收，failed=0。用户现有概念图未用于删除验证。
- 重新启动素材库PID90368/127.0.0.1:8810，361项；GET详情确认现有barracks-v4-game-desert_quarry-airborne-red.png为canDelete=true、canRename=false、2个组文件。HTML已提供统一操作栏及删除原因，无旧batch-toggle。ReportOnly仅保留预期素材库服务。
- 限定diff检查通过。静态引用保护不覆盖动态路径、UID-only、概念目录内部及外部工具依赖。

## 2026-10-09 多分类与最近一天新增

- run-art-library.ps1 -Action test最终ART_LIBRARY_TEST PASS checks=194；日志.local/art-library-test.log，最终夹具.local/art-library-test-mMmRm2。既有分类/改名/回收/恢复/版本/安全/导航/模型/移动端回归通过。
- 新增控制时钟覆盖首次扫描、未知历史null、导入历史时间迁移、24小时前1ms与恰好24小时、修改/重命名/恢复保持时间、新版本单独计时、重启保持时间和多分类。schema2备份与输入完全一致，数组去重、非法自动分类拒绝、旧接口replace与空数组归其他通过。
- 浏览器覆盖同资源跨普通分类、真实最近新增、详情及批量临时加入、切换/保存保留、F5与刷新索引清除、真正近期资源保留、超时刷新移除、批量默认add/移除/替换、窄屏无溢出，脚本错误0。
- 首轮191项通过后补充3项检查并调整分类文字换行，最终194项通过。两轮均目视复核关键截图；各11张通过固定cleanup-reviewed回收，失败0，未删除用户现有素材。
- Light -Area Tooling失败于缺失.codex/rules/local-toolchain.rules，清理阶段通过；未改安全设置。游戏/ENet未跑（本次仅本机资源管理器），无EXE导出。
- 新服务PID31880/127.0.0.1:8810：schema3，351个资源，最近新增0，原有分类遗失0，schema2备份已存在；ReportOnly仅此预期服务。JavaScript语法与限定diff卫生检查通过。

## 2026-10-09 短坡及荒漠局部PBR样板

- 实际验证入口：既有Godot MCP project_run(custom,res://tests/desert_kit_pbr_review.tscn,autosave=false)。run56因side数组循环Variant推断失败，显式float修正后run57启动；run57—60目视迭代，最终run61完成258项、failures=[]。最终文字结果在assets/concept_art/desert_terrain_kit/v2-sample-manifest.json。
- 验证包括：基础目录端点/角连接；22个导出GLB写入、回读及三角面数量一致；三段坡面实际网格连接行的位置、法线与UV相等；每段33个连接顶点；崖壁端点保持标准剖面；33个自然崖顶/高台匹配点。坡长256=32+192+32，宽256高128。
- 组合样板10258三角形、3材质。GLB文件45073068字节，9内嵌图像，3组normalTexture及occlusionTexture/metallicRoughnessTexture，无外部图像URI；独立直崖448面、坡脚272、坡身1632、坡顶272、匹配顶面512。
- 目视检查1920×1080实机长短坡同相机对照、同网格纯色/PBR同光照对照、俯视、近景及三段接缝辅助线。初版颗粒/石帽问题已修复并重拍；交付图保留，未产生额外临时验证截图。没有用AI示意图代替实际模型截图。
- 贴图由确定性程序噪声生成，沙地/岩石2048²、碎石1024²，每套BaseColor/Normal/ORM；包含mip的未压缩RGB计算108MiB，尚未达到原暂拟96MiB预算，实际显存和GPU压缩未验收。没有最低配置帧率/同屏200单位、LOD、碰撞或导航验证。
- 计划级别Light/Visual受固定run-godot.ps1 version预检阻挡：Toolchain is not configured（.codex/toolchain.local.json缺失）。专项MCP运行不等同通用Visual全部通过；无玩法/网络改动，不跑ENet与EXE。
- 最终MCP stop完成；固定ReportOnly仅素材库node PID31880监听127.0.0.1:8810。遵循不停止共享基础设施规则，未执行会停止素材库的全局清理。限定diff检查通过，无提交推送。
## 2026-10-09：荒漠 v3 岩石质量样板

- 范围：独立美术生成脚本与Godot审阅，不涉及生产地图、碰撞、寻路或网络。目标级别Light/Visual；先行import入口因缺少.codex/toolchain.local.json预检失败。未执行会在finally误停共享素材库的完整validation入口；专项不代替Light套件。
- Blender MCP在独立Scene制作并通过libraries.write保存源文件，未覆盖当前soldier.blend。执行selected-to-active NORMAL/EMIT/AO，最终253728高模面、3738三角形崖壁、862三角形岩石及四种碎石。
- 初次导出包含其他Scene选中模型：use_selection并不限定Scene，修复为use_active_scene=True，77项实际GLB字节检查确认每个独立文件仅1mesh/1material、组合2mesh/2material，无骨骼动画和外部图像/缓冲区；法线、AO、metallicRoughness连接存在。低模导出前固定三角化，并保留UV、切线。
- 首轮薄板堆叠感、二轮横向木纹感和强凹凸：改连续岩体、块状风化底色、稳定三角化、高模平滑与法线强度0.38。完成同光照v2/v3、独立岩石近景、岩沙近景、单位俯视、法线开关对照，实际Godot画面经目视复核。仍存在规则岩体和材质细节不足，未声称等同参考图。
- 最终run65：14201项细粒度检查0失败（大部分逐顶点有限值），组合导出回读三角形27308一致，5 PNG正常保存；editor cursor9后无新错误。77项独立GLB文件审计0失败，结果v3-export-audit.json。
- 预算：两个共享材质表面；岩石2K三图约48MiB，加复用沙地2K两图约32MiB，RGB+mip名义80MiB。独立GLB内嵌图集产生磁盘重复，尚未生产GPU压缩；未做LOD/最低显卡性能/端口拼接验证。
- 交付20项由本地素材库索引并归类关联。所有5截图为交付内容，未产生需要删除的功能验证截图。游戏已通过MCP stop，固定cleanup ReportOnly仅项目素材库PID31880，8810；按共享基础设施保护例外不运行全局强停。未启动新Blender进程，既有PID70240保留。
## 2026-10-09：工具链本机配置恢复验证

- 修复缺失的.codex/toolchain.local.json与.codex/rules/local-toolchain.rules，均继续被Git忽略。使用setup-local原有入口与明确安装路径，CheckOnly预览后经平台批准写入，无源码、安全模式或ACL改动。
- 固定run-godot/run-blender版本动作退出码0；.godot/toolchain-godot-version.log记录4.7.2.stable.official.ed1daf0bf，toolchain-blender-version.log记录5.2.2 LTS；对应.err均0字节。
- verify-permissions：WRAPPER_SYNTAX、TOOLCHAIN_PATHS、PROCESS_PATH_CHECK、PROCESS_PATH_NATIVE、GODOT_ARGUMENT_RULES及EXECPOLICY均PASS（27允许/7拒绝）。测试中的Saved Godot installation is unavailable警告为失效路径夹具的预期输出，并非实际登记路径失效。
- setup-local -CheckOnly复查两文件UNCHANGED；git check-ignore确认两文件不提交。只恢复本机数据，不属于游戏/源代码变更；未运行完整Light/Visual/Full，前轮美术检查限制的历史记录保留。
- cleanup ReportOnly：版本子进程已退出，项目常驻仅素材库31880/8810；共享MCP进程保留。按共享进程保护要求未运行全局StopTracked/StopUntracked。新规则需重启受信项目Codex会话加载；官方依据https://learn.chatgpt.com/docs/agent-configuration/rules。
## 2026-10-09：恢复工具链后的完整 Visual 结果

- 先行导入：run-godot.ps1 -Action import -LogFile .godot/visual-import-20261009.log -TimeoutSeconds 180，退出0，日志无ERROR/WARNING，stderr为空。
- 验证命令：run-validation.ps1 -Level Light -Area Visual,Tooling -PreserveProcessId 31880,142840。运行目录.godot/validation/20261009-222342-88636，总耗时28946ms，汇总status=passed。
- tooling=2831ms；visual_models=2272ms；soldier_locomotion=1523ms；soldier_rig=5872ms；mobile_infantry=3654ms（132检查0失败）；terrain_presentation=3930ms；terrain_sample_view=5133ms；cleanup=3707ms，全部通过。
- 地图检查涵盖荒漠/样板切换、地形表现、拾取与坡道连接、单位地表朝向等现有断言；使用headless入口，无新增实机截图、不评价参考图美术相似度，也不是GPU/GTX1060性能验收。独立v3艺术样板仍以之前专项检查为准。
- 非致命警告：visual_models和terrain_presentation退出各报告1 ObjectDB泄漏，根因未定位、未修复；其余套件无此日志，本轮并未把有警告描述为全洁净。
- 清理修复与验收：原脚本会终止所有含项目路径的进程，包括常驻素材库；加入显式PreserveProcessId并贯穿验证入口，tracked/untracked/残留端口使用相同保留集合。实际-StopTracked -StopUntracked清理后PROJECT_PROCESSES none；编辑器142840、素材库31880及8810端口均明确保留，共享MCP未停止。Tooling语法与规则回归亦通过。
- 当前平台沙箱初始化失败(setup refresh had errors)，读取和固定验证命令经平台批准执行；未尝试关闭沙箱或更改ACL。与已修复的本机工具路径登记问题区分。

## 2026-10-09：地图编辑器前置准备验收

- 资源导入独立执行，最终导入日志 `.godot/components-delivery-import.log`，无解析错误。Full 运行 `.godot/validation/20261009-231948-45984`，171431ms，16 个源套件、ENet 与清理全部通过。正式地图回归、两轮 guest、完整快照相等、生产/兵营迁移/战斗与主机断线均通过。
- 末轮边界/输入检查及平面网格精简后，Light Simulation/Visual/Tooling 运行 `.godot/validation/20261009-232427-13892`，41521ms，全部通过；不重复已通过且不受最后变更影响的 ENet。
- `terrain_components` 148 项零失败：JSON 读写与乱序稳定哈希、四方向完整拼接、未知 ID/变换/越界/缺件拒绝、运行网格与 PBR 属性、缩略图、贴图压缩 mip、通行缓存保守性、完整兵营占地、悬崖/岩石阻挡、短坡及 -128 坑底拾取、正式地图隔离。
- JSON 已加入 export include_filter，并通过隔离 PCK 打包/挂载/回读相同布局哈希；遵循本轮不导出 EXE 的范围，没有生成或启动新 EXE。
- `barracks_flight` 独立 46 项零失败，日志 `.godot/components-deployment.log`，样板与正式地图均发现可部署高地/低谷，坡道拒绝；实际起飞、搬迁、落地恢复生产通过。
- 修复与验证：短坡顶点被邻接崖壁抢占导致边缘通行失败，改为坡道拥有共享顶点；士兵脚踝偏移未跟随脚掌旋转导致误差 0.72，改为旋转后的局部偏移；坑底射线终止高度恰好落在采样下限可能漏采，扩大向下搜索余量。上述均在最终专项和完整套件中通过。
- 仍有部分既有套件退出时报告 1 ObjectDB 泄漏警告，未定位根因、未修复；无 SCRIPT ERROR，不能将本次描述为无警告。最低配置 GTX1060/i5-8400 未实测，参考图级最终美术质量也不属于本轮自动化验收。
- 最终实机画面日志 `.godot/components-render-budget.log`，1080p / Ryzen7 9700X / RTX5070Ti：初始 7 单位平均 6.94ms，200 静态 6.94ms，200 活动 23.01ms（p95 37.92ms），模拟 tick 15.22ms；活动帧率仍有明显波动，未达到稳定 60FPS 验收。最终活动计数 707 draw calls / 910681 primitives（含通道）/ 227.35MiB 纹理；仅新共享贴图 18.67MiB。实际 Rendered 套件所有功能断言通过，不将该 PASS 当作性能达标。
- 已查看最终 overview 与 cliff 图，确认短坡、组件高地/坑底和 PBR 装饰接入；现阶段模块重复感与规则边界仍明显，不声称等同参考图写实质量。12 个模型 GLB 与封面、7 张场景图均保存在 concept_art，素材库按“组件v1”标签可检索，54 项分类/关联与 12 个模型封面复核成功。
- 最终菜单/缩略图导入 `.godot/components-handoff-import.log` 成功；之后固定 cleanup -StopTracked -StopUntracked -PreserveProcessId 31880,142840 返回 PROJECT_PROCESSES none，现有 Godot 编辑器、8810 素材库和共享 MCP 均保留。
