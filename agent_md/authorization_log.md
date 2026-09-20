# 授权操作记录

> 用途：仅记录工作过程中需要用户授权的操作，供后续归纳总结。
> 本文件不构成规则，不改变任何现有授权策略。

## 记录格式

- 日期 | 操作 | 分类 | 需要授权的原因 | 是否已存前缀规则

## 2026-09-19（coding style 整改会话）

- 2026-09-19 | 安装 Godot 4.7.2 导出模板到 AppData\Roaming\Godot\export_templates\ | 工作区外写入 | 沙箱仅允许写项目目录与 TEMP | 是（Copy-Item 前缀）
- 2026-09-19 | Godot headless 导出 Windows EXE（第 1 次） | 外部程序执行 | 启动项目外的 Godot 编辑器可执行文件 | 是（Godot --headless 前缀）
- 2026-09-19 | Godot headless 导出 Windows EXE（第 2 次，绝对路径 + verbose 排查） | 外部程序执行 | 同上；首导出未更新文件需重试 | 是（含绝对路径的完整命令前缀）
- 备注：TEMP 内解压模板包本身在沙箱允许范围内，但也被保存了命令前缀

## 待后续会话追加

（此后每次触发授权时在此追加一行）
- 2026-09-19 | Get-Process 查询 IronFront/Godot 进程 | 进程枚举 | 排查导出文件占用 | 是
- 2026-09-19 | Stop-Process 结束旧版 IronFront.exe (PID 136360) | 进程终止 | 旧游戏进程锁定 EXE 导致导出重命名失败 | 是
- 2026-09-20 | git add . / git commit（35 文件，2809+/1673-） | 版本控制 | 暂存并提交本次会话改动 | 是
- 2026-09-20 | git push origin main（用户明确要求上传后执行） | 网络推送 | 上传 48 个本地提交；因历史中多个 ~104MB EXE LFS 对象导致上传缓慢 | 是
- 2026-09-20 | 用户取消推送（Ctrl+C 中断） | — | LFS 历史对象过多，推送耗时过长；远端未更新，本地提交保留 | —
- 2026-09-20 | git filter-branch 剥离 50 个未推送提交中的历史 EXE（已建 backup/pre-exe-rewrite 备份） | 历史重写 | 用户选择"只保留最新 EXE"方案；远端不受影响 | 是
- 2026-09-20 | git push origin HEAD~1:main（方案 B） | 网络推送 | 用户明确选择排除 EXE：仅推源码与文档，50 个提交 6 秒完成，零 LFS 上传 | 是
