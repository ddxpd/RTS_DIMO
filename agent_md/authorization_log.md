# 授权操作记录

本文件只记录需要用户授权或会改变外部状态的操作；它不替代 `agent_md/AGENTS.md` 的规则。

## 格式

`日期 | 操作 | 分类 | 授权原因/范围 | 结果`

## 已记录授权

| 日期 | 操作 | 分类 | 授权原因/范围 | 结果 |
| --- | --- | --- | --- | --- |
| 2026-09-19 | 安装 Godot 导出模板到 AppData | 工作区外写入 | 受限环境无法使用 TEMP 模板 | 完成 |
| 2026-09-19 | Godot headless 导出与进程检查 | 外部程序 | 启动项目外部可执行文件 | 完成 |
| 2026-09-19 | 查询/停止占用旧 EXE 的进程 | 进程管理 | 解除导出文件锁 | 完成 |
| 2026-09-20 | 本地 commit、历史清理和 LFS 清理 | Git 本地操作 | 用户确认保留源码与最新二进制历史 | 完成 |
| 2026-09-20 | 多次 `git push`（含/不含 EXE） | 远程上传 | 用户明确指定 push 范围并确认大文件 | 已记录，之后仍需用户主动要求 |
| 2026-09-23 | 3D 分支审查、模型修改、测试、临时 EXE 导出和本地提交 | 项目开发 | 用户明确授权本地开发范围 | 完成，未推送 |
| 2026-09-25 | 文档整理、脚本验证和项目导出检查 | 项目开发 | 用户明确要求实施文档计划 | 完成；未执行远程上传 |
| 2026-09-29 | 建立 Markdown 编辑授权规则 | 项目规则 | 用户明确授权本次修改所有 `AGENTS.md` 适用的项目规则 | 完成；普通现有 Markdown 免重复确认，所有 `AGENTS.md` 仍需逐次明确同意，新 Markdown 创建前先确定后续权限 |
| 2026-09-29 | 建立 Light/Full 两级开发验证规则 | 项目规则 | 用户明确授权本次修改 `agent_md/AGENTS.md`，发布验证不作为固定等级 | 完成；仅限本次两级验证规则改动 |
| 2026-09-29 | 禁止普通 Markdown 编辑触发无沙箱重试 | 项目规则 | 用户明确授权本次修改 `agent_md/AGENTS.md`，并选择仅放行现有非 `AGENTS.md` Markdown 的修改 | 完成；此类文件仅使用工作区内编辑方式，失败时不申请无沙箱升级 |

## 持续规则

- 2026-09-25 | commit `b1f2883` and push `origin/feature/3d-models` | remote upload | User selected source/docs/tools only; current EXE excluded from the new commit | Push also uploaded 3 historical LFS objects (about 330 MB) because the remote branch lacked objects referenced by earlier commits; current EXE remains local.

- 本地读写、测试、导出和 commit 属于项目授权范围；远程 push、远程分支和大文件上传必须由用户在当前请求中主动提出。
- 涉及 EXE/PCK 的远程上传必须先确认是否包含大文件，并提供 Release 方案。
- 启动 Godot、Blender、MCP 或 Python 服务后，结束前必须执行项目进程清理并报告残留。
- 现有且文件名不是 `AGENTS.md` 的 Markdown 可直接通过工作区内工具修改，不得仅为编辑或验证此类文件申请无沙箱重试；所有 `AGENTS.md` 修改均需事先明确同意；其他新 Markdown 必须在创建前确认并记录后续编辑权限。
