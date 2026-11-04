import AppKit
import ImageIO

enum Thumbnail {
    static func load(url: URL) -> CGImage? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 96
            ]
            if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) { return image }
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let image = try? ImageCodec.decode(data) else { return nil }
        let factor = min(1, 96 / CGFloat(max(image.width, image.height)))
        let w = max(1, Int(CGFloat(image.width) * factor)), h = max(1, Int(CGFloat(image.height) * factor))
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: ImageCodec.colorSpace, bitmapInfo: ImageCodec.bitmapInfo) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()
    }
}

actor ThumbnailWorker {
    static let shared = ThumbnailWorker()
    func load(url: URL) -> CGImage? { autoreleasepool { Thumbnail.load(url: url) } }
}
