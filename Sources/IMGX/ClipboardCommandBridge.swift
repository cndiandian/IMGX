import AppKit
import SwiftUI

/// 在窗口响应链中处理图片复制/粘贴；文本编辑器优先处理原生命令。
struct ClipboardCommandBridge: NSViewRepresentable {
    let canPaste: Bool
    let canCopy: Bool
    let paste: ([NSItemProvider]) -> Void
    let copy: () -> Void

    func makeNSView(context: Context) -> ClipboardCommandView { ClipboardCommandView() }
    func updateNSView(_ view: ClipboardCommandView, context: Context) {
        view.responder.isPasteEnabled = canPaste
        view.responder.isCopyEnabled = canCopy
        view.responder.performPaste = paste
        view.responder.performCopy = copy
    }
    static func dismantleNSView(_ view: ClipboardCommandView, coordinator: ()) { view.detach() }
}

final class ClipboardCommandView: NSView {
    let responder = ClipboardCommandResponder()
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

final class ClipboardCommandResponder: NSResponder, NSUserInterfaceValidations {
    var isPasteEnabled = false
    var isCopyEnabled = false
    var performPaste: (([NSItemProvider]) -> Void)?
    var performCopy: (() -> Void)?
    weak var window: NSWindow?
    var pasteboard: NSPasteboard = .general

    private var canRespond: Bool {
        (window?.isKeyWindow ?? true) && window?.attachedSheet == nil && NSApp?.modalWindow == nil
    }
    private var canPaste: Bool {
        isPasteEnabled && canRespond && pasteboard.canReadItem(withDataConformingToTypes: ClipboardImport.contentTypes.map(\.identifier))
    }

    @objc func paste(_ sender: Any?) {
        guard canPaste else { return }
        let providers = ClipboardImport.providers(from: pasteboard)
        if !providers.isEmpty { performPaste?(providers) }
    }

    @objc func copy(_ sender: Any?) {
        guard isCopyEnabled, canRespond else { return }
        performCopy?()
    }

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(paste(_:)): canPaste
        case #selector(copy(_:)): isCopyEnabled && canRespond
        default: false
        }
    }
}
