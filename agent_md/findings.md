# Findings：coding style 全量整改（2026-09-19）

## 违规分布（整改前）
- scripts/main.gd：707 处（tab 缩进为主）
- scripts/simulation.gd：443 处
- tests/gameplay.gd：142 处；network_probe.gd：134 处；presentation.gd：92 处
- tests/network_guest.gd：18 处；assets/art/pixel_art.gd：33 处
- soldier/harvester entity：单行函数、缺空行、int=100、逗号无空格
- camera_controller.gd / barracks / base / building / combat / game_entity：基本合规

## 整改方式
- Node 脚本批量处理：tab→4空格、CRLF→LF、BOM 清除、逗号后加空格、
  赋值/比较运算符两侧加空格（字符串/注释感知）、行尾空白清理、
  文件尾单换行、函数定义前保证空行
- 两个 entity 小文件手工重写（拆分单行函数、补空行）

## 质量护栏
- 修复器的字符串切分器曾有一个 bug，污染了 gameplay.gd 的一个字符串
  （" checks; failures=" → " checks; failures ="）
- 通过 git HEAD 逐文件比对全部字符串字面量发现并已修复
- 最终校验：15/15 文件字符串与 HEAD 完全一致

## 验证
- gameplay.gd headless：47 checks; failures=[]，退出码 0
- presentation.gd headless：failures=[]，退出码 0
- 编辑器 filesystem scan：无脚本错误
- project_run 实机验证：菜单→SOLO 对局→AI 建兵营产兵（红方 600→130 消费、
  8 士兵+2 采集车），game log 无错误
- 导出模板 4.7.2 曾缺失，已从 %TEMP% 缓存安装到 AppData 后成功导出
- build/IronFront.exe：109,188,184 字节，2026-09-19 22:25，PCK 内嵌
