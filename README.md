# IMGX

面向 Apple Silicon、macOS 26+ 的原生图片转换与压缩工具。使用 SwiftUI 与 AppKit，图片仅在本机处理。

## 使用

构建后打开 `dist/IMGX.app`。选择或拖入 JPG、JPEG、PNG、WebP、HEIC 静态图片，调整输出格式、质量及尺寸，通过滑杆或分屏检查真实编码结果，再选择文件夹导出全部图片。输出支持 WebP、JPEG、PNG；同名文件自动编号，保留原文件。

- ⌘O 添加图片，⌘Return 导出全部，⌘0 适应窗口。
- 侧栏上下键切图；非编辑状态下 Delete 移除选中。
- 画布滚轮/捏合缩放、拖动平移、双击复位；获得焦点后支持方向键、`+`/`-`、`0`、`[`/`]`。
- 100% 表示适应窗口的基准比例，不是像素一一对应。

## 开发与验证

需要 Xcode 26+ 与 Swift 6.2+。在项目目录执行：

```sh
swift build
swift test
bash Scripts/build-app.sh
open dist/IMGX.app
```

也可使用 Xcode 打开 `Package.swift`。WebP 1.6.0 和 libsharpyuv 已静态入库，运行和构建无需 Homebrew；库当前仅提供 arm64 架构。第三方许可位于 `Vendor/WebP`，打包时也复制至应用 Resources。

`bash Scripts/build-app.sh debug` 生成调试应用。仅 Debug 构建支持 `IMGX_DEV_APPEARANCE=dark/light`、`IMGX_DEV_SMALL_WINDOW=1` 和以换行分隔路径的 `IMGX_DEV_INPUTS`，用于应用内外观及文件导入验收，不修改系统设置。Release 构建不启用这些辅助入口。

## 验收与边界

当前 11 项自动化测试覆盖编码、透明通道、EXIF 方向、尺寸规则、导入管理、异步预览、导出快照、失败继续与排他文件保护。窗口实操及未覆盖事项见 [开发与验收记录](docs/IMPLEMENTATION.md)。

使用临时签名，仅面向本地开发分发，尚未正式签名、公证或上架。不支持动图保留，不承诺 EXIF、ICC、HDR 等信息完整保留。列表和设置不跨启动保存。

[原始 PRD](docs/PRD.md) 中的旧代码基线与已有验证属于历史描述；本仓库从空目录建立，完成情况以本仓库验收记录为准。
