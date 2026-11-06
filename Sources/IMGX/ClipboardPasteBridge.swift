import AppKit
import SwiftUI

/// 将粘贴接在窗口之后；文本编辑器仍先响应原生粘贴，画布也不必抢占键盘事件。
struct ClipboardPasteBridge: NSViewRepresentable {
    let isEnabled: Bool
    let perform: ([NSItemProvider]) -> Void

    func makeNSView(context: Context) -> ClipboardPasteView { ClipboardPasteView() }
    func updateNSView(_ view: ClipboardPasteView, context: Context) {
        view.responder.isEnabled = isEnabled
        view.responder.perform = perform
    }
    static func dismantleNSView(_ view: ClipboardPasteView, coordinator: ()) { view.detach() }
}

final class ClipboardPasteView: NSView {
    let responder = ClipboardPasteResponder()
    private weak var installedWindow: NSWindow?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        detach()
        guard let window else { return }
        installedWindow = window
        responder.window = window
        responder.nextResponder = window.nextResponder
        window.nextResponder = responder
    }
    func detach() {
        if let window = installedWindow, window.nextResponder === responder {
            window.nextResponder = responder.nextResponder
        }
        responder.nextResponder = nil
        responder.window = nil
        installedWindow = nil
    }
}

final class ClipboardPasteResponder: NSResponder, NSUserInterfaceValidations {
    var isEnabled = false
    var perform: (([NSItemProvider]) -> Void)?
    weak var window: NSWindow?
    var pasteboard: NSPasteboard = .general

    private var canPaste: Bool {
        isEnabled && (window?.isKeyWindow ?? true) && window?.attachedSheet == nil && NSApp?.modalWindow == nil &&
        pasteboard.canReadItem(withDataConformingToTypes: ClipboardImport.contentTypes.map(\.identifier))
    }

    @objc func paste(_ sender: Any?) {
        guard canPaste else { return }
        let providers = ClipboardImport.providers(from: pasteboard)
        if !providers.isEmpty { perform?(providers) }
    }

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        item.action == #selector(paste(_:)) && canPaste
    }
}
