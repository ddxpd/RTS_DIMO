# 项目工具 wrapper

## 单位百科与数值草案

独立工具位于 `tools/balance_designer/`。双击 `tools/balance_designer/start.cmd`，打开 `http://127.0.0.1:8811`；`stop.cmd` 停止服务。Node.js 22+ 与本机项目 Godot 工具链即可运行，无运行时 npm 依赖。端口占用只报错，不停止其他进程。

- 百科包含当前三单位/四建筑及公共规则、实际模型截图、源文件行号与 SHA256、生产关系与理论 DPS；总表支持筛选、排序、有效值自动保存，多方案并排比较。
- 所有编辑仅写 `.local/balance_designer/state.json`；上一版为 `state.json.bak`。主存档损坏时保留损坏文件并恢复备份。复制或备份项目时另行保留该忽略目录。浏览器缓存不是存档。
- “刷新游戏资料”通过 Godot 只读导出并对所有方案三方合并；新增简单字段自动加入，未知复杂字段只读，删除字段保留历史，同时修改产生可选择冲突。没有游戏回写接口。
- 固定入口 `run-balance-designer.ps1 -Action start|stop|status|refresh|export|portraits|test`。`export` 仅产生原始资料，网页或 `refresh` 才合并方案；`portraits` 用 Forward+ 更新 `assets/concept_art/balance_designer/` 七张模型图。详情见 `tools/balance_designer/usage.txt`。
- `test` 复用现有 `tools/art_library/node_modules/playwright` 与 Edge，使用 `.local/balance-test-*` 隔离存档；截图保存于 concept_art。只有依赖缺失时才需先准备现有艺术库测试环境。
- 保留该服务进行通用验证时，把其 PID 与艺术库 PID 一并传给 `run-validation.ps1` / cleanup 的 `-PreserveProcessId`；清理端口列表包含 8811。

## 个人美术资源库

本机资源浏览器位于 `tools/art_library/`，需要 Node.js 22+；依赖锁定在 package-lock.json。首次双击 `tools/art_library/install.cmd` 安装，之后双击 `tools/art_library/start.cmd` 启动并打开 `http://127.0.0.1:8810`。关闭网页不会停止服务；双击 `tools/art_library/stop.cmd` 停止。当前不对局域网或公网开放，不提供多人账号。

固定入口：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File <项目绝对路径>\tools\codex\run-art-library.ps1 -Action install|start|stop|status|test`。`test` 使用本机 Edge 无头浏览器，测试数据仅写入 `.local/art-library-test-*`，截图写入 `assets/concept_art/_verification/<本轮测试目录>/`，不被资源库索引。新的入口未加入自动审批规则，不修改全局权限；平台仍可能要求批准。

- 页面自动索引 `assets/` 内支持的资源，显示正式资源、概念图、制作源文件和个人导入。搜索名称/路径/标签，按分类/格式筛选；点击“刷新索引”同步磁盘上的新增或修改。
- 图片支持透明格/深色/浅色背景、滚轮缩放、拖动平移和重置；卡片右上角选择两项进行并排对比。GLB 支持旋转、缩放、动画选择/播放/速度；“生成模型封面”为当前筛选范围中的模型生成本地缓存。所有网页依赖由本机提供。
- 同一资源支持多个普通分类。图片预览上方“图片分类”复选后立即保存，其他资源在详情勾选后“保存信息”；取消全部普通分类归入“其他”。列表勾选卡片后“设置图片分类”，默认追加分类，也可移除所选分类或替换全部分类，混选时明确跳过非图片。正式游戏图片也可整理分类，不移动原文件、不改变其他元数据。统一选择最多 1000 项；恰好两项时可比较，删除和归类不受两项限制。切换区域、分类、搜索、格式或排序清空选择，加载更多保留选择。
- 左侧固定“最近一天新增”按服务端首次发现/导入后不足24小时自动归类，覆盖所有格式；与建筑等普通分类叠加，不允许改名。改名、内容修改、同身份回收站恢复不重置时间，新版本单独计时。历史项目文件没有可靠入库时间时不因升级变为新增，既有导入文件沿用导入时间。页面加载或主动“刷新索引”更新自动归类，无后台定时移除。
- 图片可在详情或列表点击“临时加入最近新增”，只保留在当前页面内存，不改变普通分类或入库时间。切换分类、保存资料等内部刷新保留；浏览器刷新/重新打开页面或成功刷新索引清除临时加入，仍符合24小时条件的项目自动保留。批量临时加入跳过非图片。
- 预览左右按钮或键盘 ←/→ 按当前区域、分类、搜索和排序浏览所有匹配图片，包括尚未加载的卡片；首尾禁用，不循环。打开时固定队列，归类后继续原队列，重新打开才按最新筛选重建；输入文字或其他弹窗打开时不响应切图快捷键。切图重置缩放和平移。
- 名称、标签、备注等尚未保存时，切图/关闭详情提供保存、放弃、取消；保存失败保留内容。即时归类不会顺带保存其他草稿。`POST /api/assets/category` 接收 `{ids, categoryIds, mode}`，mode为add/remove/replace，数组接口默认add；旧`categoryId`请求默认replace。详情PATCH支持categoryIds；导入用重复的categoryIds查询参数，新版本继承父资源全部普通分类。沿用会话校验与串行队列，批量全部校验后一次保存，批量接口拒绝非图片及自动分类ID。
- 左侧分为“原文件仅查看”（正式游戏资源、制作源文件）和“文件可改动”（个人导入、非源文件的概念资源）。分类区支持新增单层分类、铅笔按钮改名；分类与区域筛选组合生效，空分类保留。分类不移动文件。
- 所有资源详情均可修改显示名称、分类、标签、备注和关联文件，复制路径或下载原文件。显示名称只修改资源库记录；留空时显示文件名，不影响游戏加载。GLB 三角形数量是网格定义统计，不包含场景节点复用产生的实例数量。
- 可改动资源详情提供“重命名文件”，保持目录和扩展名、拒绝同名覆盖及非法 Windows 文件名；保留 ID、关联、版本和自定义显示名称。概念文件若有 `.import`/`.uid` 伴随文件或项目源码/配置的明确路径引用，显示原因并阻止改名，不自动改写游戏引用。扫描不覆盖动态拼接路径、概念目录内部依赖或外部工具；这类资源仍应通过对应制作工具管理。
- 可改动资源支持详情单项删除和列表勾选后“移入回收站”。全选只包含当前已加载的筛选结果，确认清单显示实际路径、数量、大小和保护原因；受保护项跳过，失败项保留可重试。未被项目明确路径引用的概念资源可与同名 `.import`/`.uid` 一起回收，删除权限独立于改名权限；正式资源和制作源文件仍保护。批量预检与执行各扫描一次源码引用，执行前重新核对整组文件及 SHA256；先回收原文件，成功移除后再回收伴随文件，部分失败逐个显示路径和原因。静态扫描不覆盖动态路径、UID-only 引用、概念目录内部依赖或外部工具，不能保证检测所有依赖。Windows 回收站不可用时不降级为永久删除，不清空系统回收站。固定 `recycle-art-files.ps1` 从标准输入接收服务端校验后的文件清单，禁止目录/符号链接/根目录越界，并重新验证内容 SHA256；使用 Windows IFileOperation 回收标志和删除前回调拒绝永久删除。
- 删除只是从原位置移走选定文件，活动列表及关联/版本列表隐藏该项；恢复记录保留 ID、分类、备注、版本号和关联。系统回收站还原到原路径后点“刷新索引”，内容校验一致才恢复原条目；其他位置或不同内容不继承旧身份。网页不提供回收站管理，不连带删除其他版本。
- 导入支持图片、内嵌资源 GLB、未压缩 BLEND、TXT/JSON/HTML/TRES/GDSHADER，单文件 512 MB 上限，图片解码上限 6400 万像素。同名上传独立保存；从详情“导入新版本”才建立版本关系。HTML/源文件仅下载，上传内容不执行、不自动解压。
- `.local/art-library/imports/` 保存个人导入原文件，`catalog.json` 保存 ID、版本、校验记录、备注和显式关联，`cache/` 保存可再生缩略图。这些数据不提交 Git；备份个人库时应同时复制 imports 与 catalog.json。现有资产只索引，不复制进个人库，仍需按原目录备份。
- 资源库内改名通过持久路径映射保留原 ID；旧路径被新文件复用时不会占用已改名资源的 ID。直接在资源管理器中改名仍可能形成新条目。外部原地修改只更新当前内容/校验，不自动保存旧文件副本；需要保留版本时使用“导入新版本”。新导入可选当前分类，新版本继承父资源分类。正式游戏资产仍由 Git 管理，concept_art 继续独立管理。
- `catalog.json` 自动升级为 schema 3，迁移前在同目录保留相应的`catalog.json.schema1-*.bak`或`catalog.json.schema2-*.bak`。普通分类以categoryIds数组保存，首次入库时间按资源ID保存在firstSeenAt，历史未知时间为null。目录GET返回automaticCategories、统一evaluatedAt，以及每项firstSeenAt/isRecent；兼容输出categoryId/category代表首个普通分类，新页面使用数组。迁移保留ID、关联、版本、删除记录；需要回退旧程序时先停止服务并恢复对应备份，旧程序不支持schema3。改名使用同目录硬链接/解除链接保证不覆盖目标，并以`rename-pending.json`记录中断恢复；文件系统不支持硬链接时操作失败，不改用覆盖式移动。异常恢复失败会保留记录并提示检查。
- 网页展示 GLB 自带动画和浏览器光照，不能等同于 Godot 程序步态/施工/地形贴合效果；使用关联实机截图补充。BLEND 不在网页直接渲染，外部依赖的 GLB 和需要远程解码器的特殊压缩模型需先转换为可离线预览版本。

这些脚本固定项目根目录和允许的参数，避免直接调用机器相关的 Godot、Blender、Python 或 MCP 服务。

## 结构、测试与数值工具

- 自动测试顺序、影响面、渲染要求和完成标记统一来自 `validation-suites.json`。Full 包含 34 个自动专项与完整 ENet；手动预览、辅助脚本及额外性能探针单独登记，不冒充自动覆盖。新增测试须登记。
- `run-structure.ps1` 检查测试登记、资源引用、UID、GLB 外部贴图、Blender 语法与制作路径。迁移验收可加 `-PreservedManifest .local/structure_before/preserved_sha256.json` 核对本轮保存的原文件字节。
- 目录旧新路径保存在 `structure-migration.json`；历史文字日志维持当时路径，查找对应文件时使用映射。旧的 `build/verification` 证据已归档，新可再生输出不进入 Git。
- 数值工具独立安装依赖：`run-balance-designer.ps1 -Action install`，本机已有缓存时可加 `-Offline`。不再借用美术库的 node_modules。
- 数值由 Godot 直接导出 `scripts/definitions/` 中的常量，来源清单统一使用 `tools/balance_designer/sources.json`。原有草案和冲突处理保持不变，刷新只更新基线，不将草案写回游戏。

## 验证截图工作流

- 功能验证截图默认属于临时产物。用户未要求保留、且没有明确留存用途时，完成自动验证和必要目视检查后按本次文件清单清理；设计效果图、制作源文件、材质和正式运行预览不属于此规则。
- 新验证输出使用 `assets/concept_art/_verification/<任务或运行 ID>/`，不混入正式效果图目录。记录截图清单和校验值；失败且仍待排查时暂留，问题验证结束后清理。明确要留存时只把选定图片转存正式概念图目录并记录用途，不执行本轮清理动作。
- 资源库测试生成 `.local/art-library-test-*/screenshots.json` 和最近一次清单指针。检查完毕后运行固定入口 `run-art-library.ps1 -Action cleanup-reviewed`，仅回收该清单下路径和内容匹配的临时 PNG。检查其他轮次后可用 `-VerificationManifest <完整 screenshots.json 路径>` 指定清单。测试本身不会在目视检查之前自动销毁截图。
- 旧 Godot 测试若仍写入固定预览路径，执行前记录其预期输出，验证后检查是否被正式游戏引用、有无导入伴随文件，再清理本次确认为验证产物的文件；不要清空目录或仅凭 PNG 后缀删除。新建/修改截图脚本时优先采用隔离目录和清单。
- 历史清理使用 `run-art-library.ps1 -Action inventory-history` 生成 `.local/verification-history-cleanup.json`，按明确测试输出规则列出证据和保护原因；`-Action cleanup-history` 通过同一回收站接口执行。维护前停止个人库，避免多个进程写同一索引。报告记录移除、失败、跳过项目，保留文字验证结果。
- Windows 行为依据：[IFileOperation 操作标志](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-ifileoperation-setoperationflags)及[删除前回调](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-ifileoperationprogresssink-predeleteitem)。

## 文件编辑与执行授权

- 项目内普通 `.ps1` 和已有非 `AGENTS.md` 的 `.md` 文件，可按任务需要直接使用 `apply_patch` 修改，不重复询问；不要仅为这类编辑改用 `cmd`/PowerShell 写文件或申请 `retry without sandbox`。
- `AGENTS.md` 仍须事先明确同意；新增其他 Markdown 仍须先询问后续编辑权限。遵循 [项目规则](../../agent_md/AGENTS.md)，本说明不改变这些例外。
- 保留 `workspace-write` + `on-request`，不启用 Full access，不给任意 `cmd`、PowerShell 或所有 PS1 添加宽泛执行授权。修改脚本与执行脚本是不同的权限。
- 固定入口按下方完整命令形式调用：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File <绝对脚本路径>`。不要再包一层 `cmd /c`、改成 `-Command` 或拼接临时脚本来期望匹配同一规则。
- 初始化生成的 `.codex/rules/local-toolchain.rules` 仅对白名单内九个固定入口放行；新增入口须审查用途、参数与副作用后显式添加精确规则，并同步权限自检，不按扩展名自动授予执行权限。
- `.codex` 是平台保护目录，规则文件更新可能仍需一次平台审批。受信项目的规则在 Codex 启动时加载，更新后重启客户端；已有会话和更高优先级的管理策略不保证立即采用新规则。
- 自检只验证项目规则，不代表全局/管理规则或当前会话一定无弹窗。若还有弹窗，应检查完整被拦截命令及具体越界原因，不能因为目标文件是 MD/PS1 就扩大整条命令权限。普通编辑失败时报告限制，不绕过平台保护。

规则语义与加载方式见 [OpenAI 官方规则文档](https://learn.chatgpt.com/docs/agent-configuration/rules)。

## 本机初始化与换机

从自己的普通终端克隆仓库，再在仓库根目录运行初始化。工具发现只检查文件位置，不启动发现的候选程序；Godot 必需，Blender 和 MCP 按需安装。

```powershell
$toolDir = (Resolve-Path .\tools\codex).Path
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$toolDir\setup-local.ps1" -CheckOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$toolDir\setup-local.ps1"
```

发现顺序为显式参数、已有有效本机配置、PATH、安装登记与标准安装位置、`-SearchRoot` 指定的补充目录。补充目录最多搜索四层，不扫描整块磁盘、不跟随目录链接。多候选会列出路径并要求用 `-GodotPath`、`-BlenderPath` 或 `-BlenderMcpPath` 指定；同版本 Godot 的 console 配套程序优先。找不到 Godot 时不写文件；可选工具缺失时，仅对应入口不可用。

`-CheckOnly` 展示拟保存的路径和规则差异，不写文件。确认后去掉该参数。`-SearchRoot` 接受目录数组；也可以直接将相应 `-...Path` 参数设为已安装程序的完整路径。

本机配置保存在 `.codex/toolchain.local.json`，九条精确入口规则保存在 `.codex/rules/local-toolchain.rules`；两者已被 Git 忽略。初始化入口本身不在免审批名单中。规则和配置位于平台保护目录，首次配置可能需要批准写入；这与日常编辑普通项目文件不同。

日常运行只使用登记的路径，不再自动选择其他版本。换机、移动仓库或更换工具安装后重新初始化；失效或异地复制的配置会明确报错。初始化不会覆写自定义规则：请将自定义规则保存在独立 `.rules` 文件中。更新后重启 Codex，并确保项目受信。

当前生成器只更新自身管理的规则文件；跟踪的 `default.rules` 保留说明，不含旧机器授权路径。用户全局规则和 Codex 的全局 MCP 配置由用户管理，初始化不修改。

Windows 沙箱的目录所有权/ACL 初始化故障需要单独处理；工具路径初始化不修改目录安全权限、不关闭沙箱，也不能保证所有平台审批消失。

## 常用命令

验证时若需要保留已确认属于用户的编辑器或常驻素材库，先查询并确认当前PID，再向 `run-validation.ps1` 传入 `-PreserveProcessId 12345,67890`（示例PID，不能直接照抄）。该严格数字列表会传给清理入口：保留指定PID的进程、ledger记录及其监听端口，其余测试进程仍正常清理；独立调用 `cleanup-project-processes.ps1` 同样支持此参数。不要用保留列表隐藏测试残留进程。

运行需要真实渲染的项目预览脚本时，给 `run-godot.ps1 -Action script` 添加 `-Rendered`。例如 `-Script res://tests/previews/base_preview.gd -Rendered` 会把基地施工与塔灯的实机帧写入 `assets/concept_art/base_animation/`，可打开其中的 `index.html` 查看。默认脚本与回归测试仍以 headless 运行，注册表要求渲染的 HUD 和音效专项除外。

光标预览使用 `-Script res://tests/previews/cursor_preview.gd -Rendered`，实际素材对照和落点动画帧保存到 `assets/concept_art/cursor_runtime/`。预览运行时可在另一终端调用 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$toolDir\inspect-cursor.ps1"`，检查前台 Godot 的五种原生硬件光标尺寸及热点；诊断只截取光标本身，不截取桌面、不发送输入，输出到 `.godot/cursor-native/`。需要让预览窗口保持前台。

透明源图通过 imagegen 生成并保存在概念图目录；用 `run-godot.ps1 -Action script -Script res://tools/art/prepare_cursors.gd` 做保留 alpha 的机械裁边、缩小和居中，更新正式 PNG 后单独运行 import。正式光标位于 `assets/ui/cursors/`，热点见 `scripts/ui/cursor_controller.gd`，箭头热点不能误用装饰框左上角。

```powershell
$toolDir = (Resolve-Path .\tools\codex).Path
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$toolDir\run-godot.ps1" -Action version
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$toolDir\run-validation.ps1" -Level Light -Area Simulation
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$toolDir\run-validation.ps1" -Level Full
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$toolDir\run-godot.ps1" -Action export -Output build\IronFront.exe
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$toolDir\run-network.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$toolDir\cleanup-project-processes.ps1" -StopTracked -StopUntracked
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$toolDir\run-exported.ps1" -DurationSeconds 5
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$toolDir\verify-permissions.ps1"
```

## wrapper 范围

- `run-godot.ps1`：Godot 版本检查、项目脚本执行和 Windows 导出。
- `run-network.ps1`：荒漠矿区 ENet 回归；样板区只支持单机，旧原型地图已移除。
- `run-exported.ps1`：启动项目内 Windows EXE 做受限 smoke run，并登记进程供清理 wrapper 回收。
- `run-blender.ps1`：Blender 版本检查和项目内脚本执行。
- `run-mcp.ps1`：只启动 loopback 绑定的项目 MCP 服务。
- `run-validation.ps1`：运行 `Light` 定向验证或不含导出的 `Full` 完整源码验证，并输出机器可读摘要。
- `cleanup-project-processes.ps1`：停止并报告项目拥有的进程和端口。
- `inspect-cursor.ps1`：只读检查项目预览的原生光标，诊断结果写入项目 `.godot/`，不发送输入。
- `verify-permissions.ps1`：检查 wrapper 语法、本机配置与规则一致性、路径迁移回归、九个固定入口的三种解释器名称，以及原始 shell、未授权/外部/近似路径的反例。优先使用 PATH 中的 Codex CLI，再查桌面版标准安装位置；找不到 CLI 时明确失败，不将跳过规则检查当作通过。显式传入 `-ToolchainSmoke` 时才检查 Godot、Blender 和当前进程状态。

`Light` 支持 `Simulation`、`Presentation`、`Features`、`Camera`、`ActionBar`、`Visual`、`Performance`、`Network` 和 `Tooling`；可同时传入多个 Area。`Network` 固定包含 gameplay 与完整 ENet。`Full` 固定运行全部本地套件、性能与 ENet，但不执行 Godot import 或导出 EXE；源资产变更需在 `Visual` 前单独执行 import。

服务 ledger 按项目绝对路径的哈希隔离，写入用户临时目录，验证日志写入被忽略的 `.godot/validation/`。wrapper 只允许本地项目路径；外部网络和未列出的解释器调用仍需单独审批。
