import SwiftUI
import AppKit

enum ComparisonMode: String, CaseIterable, Identifiable {
    case slider, split
    var title: String { L10n.text(self == .slider ? .slider : .split) }
    var id: Self { self }
}

struct ComparisonCanvas: NSViewRepresentable {
    let result: EncodedImage?
    let imageID: UUID?
    let mode: ComparisonMode
    let resetID: UUID
    let remove: () -> Void

    func makeNSView(context: Context) -> ComparisonView { ComparisonView() }
    func updateNSView(_ view: ComparisonView, context: Context) {
        if view.imageID != imageID || view.resetID != resetID {
            view.reset()
        }
        view.imageID = imageID
        view.resetID = resetID
        view.mode = mode
        view.original = result?.original
        view.output = result?.decoded
        view.remove = remove
        view.needsDisplay = true
        view.window?.invalidateCursorRects(for: view)
    }
}

final class ComparisonView: NSView {
    var original: CGImage?
    var output: CGImage?
    var imageID: UUID?
    var resetID = UUID()
    var mode: ComparisonMode = .slider
    var zoom: CGFloat = 1
    var offset = CGPoint.zero
    var divider: CGFloat = 0.5
    var remove: (() -> Void)?
    private var lastPoint = CGPoint.zero
    private var draggingDivider = false
    private var draggingImage = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .none
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(L10n.text(.canvas))
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: L10n.text(.zoomIn), target: self, selector: #selector(accessibleZoomIn)),
            NSAccessibilityCustomAction(name: L10n.text(.zoomOut), target: self, selector: #selector(accessibleZoomOut)),
            NSAccessibilityCustomAction(name: L10n.text(.fit), target: self, selector: #selector(accessibleReset)),
            NSAccessibilityCustomAction(name: L10n.text(.revealOriginal), target: self, selector: #selector(accessibleRevealOriginal)),
            NSAccessibilityCustomAction(name: L10n.text(.revealOutput), target: self, selector: #selector(accessibleRevealOutput))
        ])
        setAccessibilityHelp(L10n.text(.canvasHelp))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func reset() {
        zoom = 1
        offset = .zero
        divider = 0.5
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let context = NSGraphicsContext.current!.cgContext
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let base = dark ? 0.16 : 0.91
        NSColor(white: base, alpha: 1).setFill()
        bounds.fill()
        NSColor(white: base + (NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? (dark ? 0.12 : -0.12) : (dark ? 0.045 : -0.055)), alpha: 1).setFill()
        let tile: CGFloat = 12
        for row in 0...Int(bounds.height / tile) {
            for col in 0...Int(bounds.width / tile) where (row + col) % 2 == 0 {
                NSRect(x: CGFloat(col) * tile, y: CGFloat(row) * tile, width: tile, height: tile).fill()
            }
        }
        guard let original, let output else { return }
        if mode == .slider {
            let left = CGRect(x: 0, y: 0, width: bounds.width * divider, height: bounds.height)
            let right = CGRect(x: left.maxX, y: 0, width: bounds.width - left.width, height: bounds.height)
            draw(original, viewport: bounds, clip: left, context: context)
            draw(output, viewport: bounds, clip: right, context: context)
            let x = bounds.width * divider
            context.setShadow(offset: .zero, blur: 3, color: NSColor.black.withAlphaComponent(0.3).cgColor)
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(2)
            context.move(to: CGPoint(x: x, y: 0)); context.addLine(to: CGPoint(x: x, y: bounds.height)); context.strokePath()
            context.setShadow(offset: .zero, blur: 0)
            context.setFillColor(NSColor.windowBackgroundColor.cgColor)
            context.fillEllipse(in: CGRect(x: x - 17, y: bounds.midY - 17, width: 34, height: 34))
            if let symbol = NSImage(systemSymbolName: "arrow.left.and.right", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.labelColor])) {
                symbol.draw(in: CGRect(x: x - 9, y: bounds.midY - 9, width: 18, height: 18),
                            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
        } else {
            let left = CGRect(x: 0, y: 0, width: bounds.width / 2, height: bounds.height)
            let right = left.offsetBy(dx: left.width, dy: 0)
            draw(original, viewport: left, clip: left, context: context)
            draw(output, viewport: right, clip: right, context: context)
            NSColor.separatorColor.setFill()
            NSRect(x: left.maxX, y: 0, width: 1, height: bounds.height).fill()
        }
        setAccessibilityValue(L10n.text(.canvasValue, String(Int(zoom * 100)), mode.title))
        let badge = L10n.text(.canvasBadge, String(Int(zoom * 100)))
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        let size = (badge as NSString).size(withAttributes: attrs)
        let rect = NSRect(x: (bounds.width - size.width) / 2 - 12, y: bounds.height - 43, width: size.width + 24, height: 27)
        NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        (badge as NSString).draw(at: NSPoint(x: rect.minX + 12, y: rect.minY + 7), withAttributes: attrs)
    }

    @objc func accessibleZoomIn() -> Bool {
        applyZoom(1.2, at: CGPoint(x: bounds.midX, y: bounds.midY)); return true
    }
    @objc func accessibleZoomOut() -> Bool {
        applyZoom(1 / 1.2, at: CGPoint(x: bounds.midX, y: bounds.midY)); return true
    }
    @objc func accessibleReset() -> Bool { reset(); return true }
    @objc func accessibleRevealOriginal() -> Bool {
        guard mode == .slider else { return false }
        divider = min(0.98, divider + 0.05); needsDisplay = true; return true
    }
    @objc func accessibleRevealOutput() -> Bool {
        guard mode == .slider else { return false }
        divider = max(0.02, divider - 0.05); needsDisplay = true; return true
    }

    private func draw(_ image: CGImage, viewport: CGRect, clip: CGRect, context: CGContext) {
        guard let original else { return }
        let fit = min(max(1, viewport.width - 48) / CGFloat(original.width), max(1, viewport.height - 80) / CGFloat(original.height))
        let width = CGFloat(original.width) * fit * zoom
        let height = CGFloat(original.height) * fit * zoom
        let rect = CGRect(x: viewport.midX - width / 2 + offset.x, y: viewport.midY - height / 2 + offset.y, width: width, height: height)
        context.saveGState()
        context.clip(to: clip)
        context.interpolationQuality = .high
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        context.restoreGState()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: draggingImage ? .closedHand : .openHand)
        if mode == .slider {
            addCursorRect(NSRect(x: bounds.width * divider - 12, y: 0, width: 24, height: bounds.height), cursor: .resizeLeftRight)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 { reset(); return }
        lastPoint = convert(event.locationInWindow, from: nil)
        draggingDivider = mode == .slider && abs(lastPoint.x - bounds.width * divider) < 14
        draggingImage = !draggingDivider
        if draggingImage { NSCursor.closedHand.set() }
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if draggingDivider { divider = min(0.98, max(0.02, point.x / max(1, bounds.width))) }
        else { offset.x += point.x - lastPoint.x; offset.y += point.y - lastPoint.y }
        lastPoint = point
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        draggingDivider = false; draggingImage = false
        window?.invalidateCursorRects(for: self)
    }

    private func applyZoom(_ factor: CGFloat, at point: CGPoint) {
        let next = min(32, max(0.1, zoom * factor))
        let ratio = next / zoom
        let centerX: CGFloat
        if mode == .split { centerX = point.x < bounds.midX ? bounds.width / 4 : bounds.width * 3 / 4 }
        else { centerX = bounds.midX }
        let relative = CGPoint(x: point.x - centerX, y: point.y - bounds.midY)
        offset = CGPoint(x: relative.x - (relative.x - offset.x) * ratio,
                         y: relative.y - (relative.y - offset.y) * ratio)
        zoom = next
        needsDisplay = true
    }
    override func scrollWheel(with event: NSEvent) {
        applyZoom(exp(min(0.35, max(-0.35, event.scrollingDeltaY * 0.012))), at: convert(event.locationInWindow, from: nil))
    }
    override func magnify(with event: NSEvent) {
        applyZoom(max(0.1, 1 + event.magnification), at: convert(event.locationInWindow, from: nil))
    }
    override func keyDown(with event: NSEvent) {
        guard !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control) else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 123: offset.x -= 20
        case 124: offset.x += 20
        case 51, 117: remove?()
        default:
            switch event.charactersIgnoringModifiers {
            case "+", "=": applyZoom(1.2, at: CGPoint(x: bounds.midX, y: bounds.midY))
            case "-": applyZoom(1 / 1.2, at: CGPoint(x: bounds.midX, y: bounds.midY))
            case "0": reset()
            case "[": divider = max(0.02, divider - 0.05)
            case "]": divider = min(0.98, divider + 0.05)
            default: super.keyDown(with: event); return
            }
        }
        needsDisplay = true
    }
}
