import SwiftUI

struct AboutView: View {
    let updater: AppUpdateModel

    var body: some View {
        VStack(spacing: 16) {
            BrandIcon(size: 64)
            VStack(spacing: 6) {
                Text("IMGX").font(.system(size: 24, weight: .semibold))
                Text(L10n.text(.version, updater.version, Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))
                    .font(.callout).foregroundStyle(.secondary)
                Text(L10n.text(.subtitle)).font(.callout).foregroundStyle(.secondary)
            }
            ProjectLink().fixedSize().frame(height: 20)
            Divider()
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    if updater.isBusy { ProgressView().controlSize(.small) }
                    Button(updater.isBusy ? L10n.text(.cancel) : L10n.text(.checkUpdates)) {
                        if updater.isBusy { updater.cancel() }
                        else { updater.check() }
                    }
                        .buttonStyle(.bordered).controlSize(.large).focusEffectDisabled()
                }
                status
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(28)
        .frame(width: 420)
        .onChange(of: updater.phase) { _, phase in
            guard !phase.message.isEmpty else { return }
            NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                                 userInfo: [.announcement: phase.message,
                                            .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }

    @ViewBuilder private var status: some View {
        if updater.phase != .idle && updater.phase != .checking {
            VStack(spacing: 8) {
                Text(updater.phase.message)
                if case .opened(_, let file) = updater.phase {
                    Button(L10n.text(.showInFinder)) { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                        .buttonStyle(.borderless)
                }
            }
        }
    }
}

/// 关闭 AppKit 原生焦点环，同时保留链接的键盘操作与无障碍角色。
private struct ProjectLink: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSButton {
        let button = ProjectLinkButton(title: "github.com/cndiandian/IMGX", target: context.coordinator,
                                       action: #selector(Coordinator.openProject))
        button.isBordered = false
        button.bezelStyle = .inline
        button.focusRingType = .none
        button.attributedTitle = NSAttributedString(string: button.title, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.linkColor
        ])
        button.toolTip = L10n.text(.openProject)
        button.setAccessibilityLabel(button.title)
        return button
    }
    func updateNSView(_ nsView: NSButton, context: Context) {}
    @MainActor final class Coordinator: NSObject {
        @objc func openProject() { NSWorkspace.shared.open(GitHubUpdateService.projectURL) }
    }
}

private final class ProjectLinkButton: NSButton {
    override func accessibilityRole() -> NSAccessibility.Role? { .link }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

struct AppInfoCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L10n.text(.about)) { openWindow(id: "about") }
        }
    }
}
