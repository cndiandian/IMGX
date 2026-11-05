import AppKit
import SwiftUI

/// 启动页与关于窗口直接复用安装包图标，不另画一套符号、底板或阴影。
struct BrandIcon: View {
    let size: CGFloat

    private static let image: NSImage = {
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String {
            let filename = name.hasSuffix(".icns") ? name : name + ".icns"
            if let url = Bundle.main.url(forResource: filename, withExtension: nil),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }
        // swift run 等未打包环境沿用系统提供的当前应用图标。
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }()

    var body: some View {
        Image(nsImage: Self.image)
            .resizable().scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
