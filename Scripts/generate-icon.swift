import AppKit
import Foundation

let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let board = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 184, yRadius: 184)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.15)
        shadow.shadowBlurRadius = 28
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.set()
        NSColor(white: 0.97, alpha: 1).setFill()
        board.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(white: 0.88, alpha: 1).setStroke()
        board.lineWidth = 2
        board.stroke()
        guard let symbol = NSImage(systemSymbolName: "square.lefthalf.filled", accessibilityDescription: nil) else {
            fatalError("无法加载 App 图标符号 square.lefthalf.filled")
        }
        let configured = symbol.withSymbolConfiguration(.init(pointSize: 440, weight: .medium)) ?? symbol
        NSColor(white: 0.18, alpha: 1).set()
        configured.draw(in: NSRect(x: 292, y: 292, width: 440, height: 440))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { fatalError("图标生成失败") }
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try png.write(to: URL(fileURLWithPath: output).appendingPathComponent(name))
    }
}
