import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CWebP

enum CodecError: LocalizedError {
    case decode, encode, invalidDimensions, imageTooLarge
    var errorDescription: String? {
        switch self {
        case .decode: "无法读取图片，请检查文件是否损坏或属于不支持的动态图像。"
        case .encode: "图片编码失败，请更换格式或缩小尺寸后重试。"
        case .invalidDimensions: "宽高必须为 1～16383 的正整数，或同时留空使用原尺寸。"
        case .imageTooLarge: "输出每边不能超过 16383 像素，总像素不能超过 1 亿。"
        }
    }
}

struct EncodedImage: Sendable {
    let data: Data
    let original: CGImage
    let decoded: CGImage
}

enum ImageCodec {
    static let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "heic"]
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    static let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

    static func decode(_ data: Data) throws -> CGImage {
        if let source = CGImageSourceCreateWithData(data as CFData, nil) {
            guard CGImageSourceGetCount(source) == 1 else { throw CodecError.decode }
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let w = properties[kCGImagePropertyPixelWidth] as? Int,
               let h = properties[kCGImagePropertyPixelHeight] as? Int,
               w > 0, h > 0, w <= ImageSizing.maximumPixelCount / h {
                // ImageIO applies EXIF orientation before resizing or display.
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(w, h),
                    kCGImageSourceShouldCacheImmediately: true
                ]
                if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) { return image }
            }
        }
        return try data.withUnsafeBytes { buffer in
            guard let bytes = buffer.bindMemory(to: UInt8.self).baseAddress else { throw CodecError.decode }
            var w: Int32 = 0, h: Int32 = 0
            guard WebPGetInfo(bytes, data.count, &w, &h) != 0,
                  w > 0, h > 0, Int(w) * Int(h) <= ImageSizing.maximumPixelCount,
                  let pixels = WebPDecodeRGBA(bytes, data.count, &w, &h) else { throw CodecError.decode }
            defer { WebPFree(pixels) }
            let rgba = Data(bytes: pixels, count: Int(w) * Int(h) * 4)
            guard let provider = CGDataProvider(data: rgba as CFData),
                  let image = CGImage(width: Int(w), height: Int(h), bitsPerComponent: 8,
                                      bitsPerPixel: 32, bytesPerRow: Int(w) * 4, space: colorSpace,
                                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
            else { throw CodecError.decode }
            return image
        }
    }

    static func load(url: URL, accessRoot: URL? = nil) throws -> CGImage {
        let scope = accessRoot ?? url
        let accessed = scope.startAccessingSecurityScopedResource()
        defer { if accessed { scope.stopAccessingSecurityScopedResource() } }
        return try decode(Data(contentsOf: url))
    }

    static func convert(url: URL, settings: ConversionSettings) throws -> EncodedImage {
        try convert(image: load(url: url), settings: settings)
    }

    static func convert(image: CGImage, settings: ConversionSettings) throws -> EncodedImage {
        let data = try encode(image: image, settings: settings)
        return try EncodedImage(data: data, original: image, decoded: decode(data))
    }

    /// 导出只需要编码数据；预览另外解码输出，用于真实画质对比。
    static func encode(url: URL, settings: ConversionSettings, accessRoot: URL? = nil) throws -> Data {
        try encode(image: load(url: url, accessRoot: accessRoot), settings: settings)
    }

    static func encode(image: CGImage, settings: ConversionSettings) throws -> Data {
        guard settings.quality.isFinite, (1...100).contains(settings.quality) else { throw CodecError.encode }
        let (w, h) = try settings.outputSize(width: image.width, height: image.height)
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: colorSpace, bitmapInfo: bitmapInfo)
        else { throw CodecError.encode }
        if settings.format == .jpeg {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let data: Data
        if settings.format == .webp {
            guard let raw = context.data else { throw CodecError.encode }
            // libwebp expects straight RGBA; CGContext uses premultiplied alpha.
            // 此缓冲区由当前 CGContext 独占，无需复制整张 RGBA 图像。
            let count = w * h * 4
            let bytes = raw.assumingMemoryBound(to: UInt8.self)
            for i in stride(from: 0, to: count, by: 4) {
                let alpha = Int(bytes[i + 3])
                if alpha > 0 && alpha < 255 {
                    for c in 0..<3 { bytes[i + c] = UInt8(min(255, (Int(bytes[i + c]) * 255 + alpha / 2) / alpha)) }
                }
            }
            var output: UnsafeMutablePointer<UInt8>?
            let length = settings.lossless
                ? WebPEncodeLosslessRGBA(bytes, Int32(w), Int32(h), Int32(w * 4), &output)
                : WebPEncodeRGBA(bytes, Int32(w), Int32(h), Int32(w * 4), Float(settings.quality), &output)
            guard length > 0, let output else { throw CodecError.encode }
            defer { WebPFree(output) }
            data = Data(bytes: output, count: length)
        } else {
            guard let raster = context.makeImage() else { throw CodecError.encode }
            let buffer = NSMutableData()
            let type = settings.format == .jpeg ? UTType.jpeg.identifier : UTType.png.identifier
            guard let destination = CGImageDestinationCreateWithData(buffer, type as CFString, 1, nil) else { throw CodecError.encode }
            let options: [CFString: Any] = settings.format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: settings.quality / 100] : [:]
            CGImageDestinationAddImage(destination, raster, options as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw CodecError.encode }
            data = buffer as Data
        }
        return data
    }
}

/// Serializes memory-heavy encoding work away from the UI actor.
actor ImageProcessor {
    static let shared = ImageProcessor()
    func load(url: URL, accessRoot: URL? = nil) throws -> CGImage {
        try Task.checkCancellation()
        return try autoreleasepool { try ImageCodec.load(url: url, accessRoot: accessRoot) }
    }
    func convert(image: CGImage, settings: ConversionSettings) throws -> EncodedImage {
        try Task.checkCancellation()
        return try autoreleasepool { try ImageCodec.convert(image: image, settings: settings) }
    }
}
