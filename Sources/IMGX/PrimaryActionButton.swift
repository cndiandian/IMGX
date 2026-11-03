import AppKit
import SwiftUI

/// Native push button keeps keyboard focus, pressed, disabled and inactive appearances.
struct PrimaryActionButton: NSViewRepresentable {
    let title: String
    var isDefault = false
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.activate))
        button.focusRingType = .none
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.title = title
        button.isEnabled = enabled
        button.keyEquivalent = isDefault ? "\r" : ""
        button.keyEquivalentModifierMask = []
        button.bezelColor = scheme == .dark ? NSColor(white: 0.94, alpha: 1) : NSColor(white: 0.2, alpha: 1)
        let foreground: NSColor = enabled ? (scheme == .dark ? .black : .white) : .disabledControlTextColor
        button.contentTintColor = foreground
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: foreground,
            .font: NSFont.systemFont(ofSize: 13, weight: .medium)
        ])
        button.attributedAlternateTitle = button.attributedTitle
    }
    @MainActor final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func activate() { action() }
    }
}
