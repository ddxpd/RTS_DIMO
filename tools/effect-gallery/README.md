# Iron Front 效果图库

本地图片导入、预览、收藏和垃圾桶工具。图片记录保存在浏览器 IndexedDB；普通导入会同时复制到 `library/`，生成图片来自 `generated/`。

## 启动

在项目根目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/effect-gallery/start.ps1
```

脚本会选择本地端口，启动 `server.py`，并尝试打开浏览器。按 `Ctrl+C` 停止服务。

## 功能

- 支持 PNG、JPG/JPEG、WebP 的单文件、文件夹和拖放导入。
- 卡片可收藏、搜索、排序、预览和下载。
- 垃圾桶支持恢复和永久删除；永久删除只作用于图库管理的副本。
- 早期只有 IndexedDB 记录、没有文件系统路径的项目，永久删除时只清理浏览器副本。

## 部署限制

`index.html` 可以静态展示，但导入、垃圾桶和永久删除必须通过本地服务运行。`library/` 和 `.trash/` 是运行时目录，不应提交到 Git。浏览器 IndexedDB 按浏览器和域名隔离，部署到新地址不会自动迁移记录。
