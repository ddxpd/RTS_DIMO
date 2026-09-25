# Iron Front

Iron Front 是一个 Godot 4 RTS 主机对等联机原型，当前分支包含 3D 实体表现、基础 AI、LAN 联机、资源采集、建造、生产、战斗、迷雾和快照同步。

## 运行

- Windows 构建：`build/IronFront.exe`（当前导出使用嵌入资源）。
- 源码验证：使用 `tools/codex/run-godot.ps1` 和 `tools/codex/run-network.ps1`，不要直接调用未固定路径的 Godot/Python。
- 局域网：主机使用 `Create LAN Host`，客户端输入主机 IP 后选择 `Join Host`；默认 UDP 端口为 `24560`。
- 效果图库：在项目根目录运行 `tools/effect-gallery/start.ps1`。

## 基本操作

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

## 项目边界

- 主机以 20 Hz 运行权威模拟；客户端接收快照并负责表现同步。
- 当前原型不包含战役、科技树、坦克、完整音乐系统、地图编辑器、NAT 穿透或主机迁移。
- 修改代码后必须按 `agent_md/AGENTS.md` 完成回归、导出和进程清理；不要执行未明确授权的远程 push。
