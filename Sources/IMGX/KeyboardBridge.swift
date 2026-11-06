import SwiftUI
import AppKit

/// Handles image shortcuts only when a text editor or modal panel does not own focus.
struct KeyboardBridge: NSViewRepresentable {
    var isEditing: Bool
    var remove: () -> Void
    var canMoveSelection: Bool
    var moveSelection: (Int) -> Void
    var canToggleComparison: Bool
    var toggleComparison: () -> Void
    func makeNSView(context: Context) -> KeyboardMonitorView { KeyboardMonitorView() }
    func updateNSView(_ view: KeyboardMonitorView, context: Context) {
        view.canMoveSelection = canMoveSelection
        view.moveSelection = moveSelection
        view.remove = remove
        view.isEditing = isEditing
        view.canToggleComparison = canToggleComparison
        view.toggleComparison = toggleComparison
    }
    static func dismantleNSView(_ view: KeyboardMonitorView, coordinator: ()) { view.stop() }
}

final class KeyboardMonitorView: NSView {
    var remove: (() -> Void)?
    var canMoveSelection = false
    var moveSelection: ((Int) -> Void)?
    var canToggleComparison = false
    var toggleComparison: (() -> Void)?
    var isEditing = false
    private var monitor: Any?
    private var menuObservers: [NSObjectProtocol] = []
    private var trackingMenuCount = 0
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        menuObservers = [
            NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.trackingMenuCount += 1 }
            },
            NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.trackingMenuCount = max(0, self.trackingMenuCount - 1)
                }
            }
        ]
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self, let window = self.window, event.window === window,
                  window.attachedSheet == nil, NSApp.modalWindow == nil, self.trackingMenuCount == 0 else { return event }
            let editing = window.firstResponder as? NSTextView
            if event.type == .leftMouseDown {
                // End editing on background clicks while keeping text inputs and Tab navigation native.
                if editing != nil, let content = window.contentView,
                   let target = content.hitTest(content.convert(event.locationInWindow, from: nil)),
                   !(target is NSTextView), !(target is NSTextField) {
                    window.makeFirstResponder(nil)
                }
                return event
            }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  editing == nil, !self.isEditing, !(window.firstResponder is NSTextField),
                  !(window.firstResponder is NSTextInputClient) else { return event }
            if self.canMoveSelection, [125, 126].contains(Int(event.keyCode)),
               !event.modifierFlags.contains(.shift) {
                self.moveSelection?(event.keyCode == 125 ? 1 : -1)
                return nil
            }
            if self.canToggleComparison, event.characters == "\\",
               event.modifierFlags.intersection(.shift).isEmpty {
                if !event.isARepeat { self.toggleComparison?() }
                return nil
            }
            if [51, 117].contains(Int(event.keyCode)) {
                self.remove?()
                return nil
            }
            return event
        }
    }
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        menuObservers.forEach(NotificationCenter.default.removeObserver)
        menuObservers.removeAll()
        trackingMenuCount = 0
    }
}
