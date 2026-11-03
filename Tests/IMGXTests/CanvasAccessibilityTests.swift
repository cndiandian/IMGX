import Testing
import AppKit
@testable import IMGX

@MainActor @Test func accessibleCanvasControlsWorkWithoutPointerGestures() throws {
    let canvas = ComparisonView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    let actions = try #require(canvas.accessibilityCustomActions())
    #expect(actions.count == 5)
    #expect(canvas.accessibleZoomIn())
    #expect(canvas.zoom > 1)
    for _ in 0..<100 { _ = canvas.accessibleZoomIn() }
    #expect(canvas.zoom == 32)
    for _ in 0..<100 { _ = canvas.accessibleZoomOut() }
    #expect(canvas.zoom == 0.1)
    #expect(canvas.accessibleReset())
    #expect(canvas.zoom == 1 && canvas.offset == .zero && canvas.divider == 0.5)
    #expect(canvas.accessibleRevealOriginal())
    #expect(canvas.divider > 0.5)
    canvas.mode = .split
    let divider = canvas.divider
    #expect(!canvas.accessibleRevealOutput())
    #expect(canvas.divider == divider)
}
