import SwiftUI

@main
struct IMGXApp: App {
    init() {
        #if DEBUG
        if let appearance = ProcessInfo.processInfo.environment["IMGX_DEV_APPEARANCE"] {
            NSApplication.shared.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        }
        #endif
    }
    var body: some Scene {
        WindowGroup("IMGX") {
            ContentView()
                .frame(minWidth: 1000, minHeight: 700)
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands { ImageCommands() }
    }
}
