// swift-tools-version: 6.2
import PackageDescription
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

let package = Package(
    name: "IMGX",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "IMGX", targets: ["IMGX"])],
    targets: [
        .systemLibrary(name: "CWebP"),
        .executableTarget(name: "IMGX", dependencies: ["CWebP"], linkerSettings: [
            .unsafeFlags(["\(root)/Vendor/WebP/lib/libwebp.a", "\(root)/Vendor/WebP/lib/libsharpyuv.a"])
        ]),
        .testTarget(name: "IMGXTests", dependencies: ["IMGX"])
    ]
)
