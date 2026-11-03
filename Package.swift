// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "IMGX",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "IMGX", targets: ["IMGX"])],
    targets: [
        .executableTarget(name: "IMGX")
    ]
)
