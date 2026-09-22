# Iron Front 效果图收藏

零依赖本地网页，用于导入、预览、收藏和删除效果图。图片与收藏状态保存在当前浏览器的 IndexedDB 中，刷新后仍会保留。

## 启动

在项目根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/effect-gallery/start.ps1
```

脚本会自动选择本地端口、启动静态服务并打开浏览器。在 PowerShell 窗口按 `Ctrl+C` 停止服务。

## 导入

- 点击“选择图片文件”导入单个或多个图片。
- 点击“选择 build/verification 文件夹”批量导入现有效果图。
- 拖拽图片或文件夹到上传区。

支持 PNG、JPG/JPEG、WebP。

## 收藏

- 点击卡片右上角星标收藏或取消收藏。
- “中意收藏”标签只显示收藏图片。
- 收藏状态保存在 IndexedDB，刷新后不会丢失。

## 后续部署

`index.html` 是纯静态页面，可部署到 GitHub Pages、Cloudflare Pages、Netlify 或任意静态服务器。注意 IndexedDB 按浏览器和域名隔离，部署到新地址后本地图片不会自动迁移。
