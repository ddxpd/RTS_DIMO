# 任务计划：全项目 Coding Style 整改

## 范围
- 自有代码：scripts/（含 entities）、tests/、assets/art/ 共 15 个 .gd 文件
- 排除：addons/godot_ai/（第三方插件，不改动）

## 步骤
1. [x] 读取 agent_md/AGENTS.md 的 coding style 规范
2. [x] 全量扫描自有脚本，输出违规清单
3. [x] 修复：tab→4空格、运算符/逗号空格、单行函数拆分、函数间空行、文件尾空行、CRLF→LF
4. [x] 复审：重跑审计脚本直到 0 违规
5. [x] 验证：Godot 编辑器扫描 + 测试套件 + 游戏运行验证 + Windows 导出
6. [x] 记录结果

## 结果
- 15/15 文件通过风格审计（tab、行尾空白、逗号/运算符空格、分号、函数空行）
- 字符串字面量 15/15 与 git HEAD 完全一致（零内容改动）
- gameplay 测试：47 checks / 0 failures；presentation 测试：0 failures
- 运行时验证：SOLO 对局启动，AI 建兵营并产兵，无运行时错误
- 导出：build/IronFront.exe 已更新（2026-09-19 22:25，PCK 内嵌，单文件分发）
