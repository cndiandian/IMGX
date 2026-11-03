import SwiftUI

@main
struct IMGXApp: App {
    var body: some Scene {
        WindowGroup("IMGX") {
            ContentView()
                .frame(minWidth: 1000, minHeight: 700)
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.hiddenTitleBar)
    }
}
