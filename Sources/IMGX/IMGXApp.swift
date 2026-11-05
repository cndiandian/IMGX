import SwiftUI

@main
struct IMGXApp: App {
    @State private var updater = AppUpdateModel()
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
                .environment(\.locale, Locale(identifier: L10n.language.rawValue))
                .frame(minWidth: 1000, minHeight: 700)
                .ignoresSafeArea(.container, edges: .top)
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands { ImageCommands(); AppInfoCommands() }

        Window(L10n.text(.about), id: "about") {
            AboutView(updater: updater)
                .environment(\.locale, Locale(identifier: L10n.language.rawValue))
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
    }
}
