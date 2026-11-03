# IMGX

面向 Apple Silicon、macOS 26+ 的原生图片转换与压缩工具，采用 SwiftUI 与 AppKit，图片仅在本地处理。

## 开发

需要 Xcode 26 或更新版本及 Swift 6.2+。在项目目录执行：

```sh
swift build
bash Scripts/build-app.sh
open dist/IMGX.app
```

也可使用 Xcode 打开 `Package.swift`。构建产物使用本机临时签名，正式分发签名不在本阶段范围内。

图片编码核心建立后将加入 `swift test` 验证；初始化阶段以构建和签名检查为准。

## 需求与进度

- [原始 PRD](docs/PRD.md)
- [开发与验收记录](docs/IMPLEMENTATION.md)

PRD 中的旧代码基线与已有验证属于输入文档的历史描述，本仓库从空目录开始，功能完成情况以本仓库验收记录为准。
