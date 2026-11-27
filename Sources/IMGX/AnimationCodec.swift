import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CWebP

struct AnimationFrame: Sendable {
    let image: CGImage
    let milliseconds: Int
}

struct ImageAnimation: Sendable {
    let frames: [AnimationFrame]
    /// 总播放次数；0 表示无限循环（GIF 的重复次数在读写边界换算）。
    let playCount: Int
    let format: OutputFormat

    var duration: Double { Double(frames.reduce(0) { $0 + $1.milliseconds }) / 1000 }

    func image(at elapsed: Double) -> CGImage {
        if playCount > 0, elapsed >= duration * Double(playCount) { return frames.last!.image }
        var time = max(0, elapsed).truncatingRemainder(dividingBy: duration) * 1000
        for frame in frames {
            if time < Double(frame.milliseconds) { return frame.image }
            time -= Double(frame.milliseconds)
        }
        return frames.last!.image
    }
}

struct ImageSequence: Sendable {
    let first: CGImage
    var animation: ImageAnimation? = nil
}

enum AnimationCodec {
    // 预览同时保留源帧及输出帧，对动图实施独立总像素/帧数预算。
    static let maximumFrames = 500
    static let maximumPixels = 32_000_000

    static func validate(width: Int, height: Int, count: Int) throws {
        guard width > 0, height > 0, count > 0, count <= maximumFrames,
              width <= ImageSizing.maximumDimension, height <= ImageSizing.maximumDimension,
              width <= maximumPixels / height / count else { throw AnimationError.tooLarge }
    }

    static func decode(_ data: Data) throws -> ImageAnimation? {
        if data.starts(with: Data("RIFF".utf8)), data.count >= 12,
           data[8..<12] == Data("WEBP".utf8) {
            return try decodeWebP(data)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.gif.identifier,
              CGImageSourceGetCount(source) > 1 else { return nil }
        let count = CGImageSourceGetCount(source)
        let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any] ?? [:]
        let firstProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? firstProperties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? firstProperties[kCGImagePropertyPixelHeight] as? Int ?? 0
        try validate(width: width, height: height, count: count)
        // ImageIO 会为没有循环扩展的 GIF 合成 LoopCount=1，须读取真实扩展区别单次播放。
        let repeats = try gifRepeatCount(data)
        let plays = repeats.map { $0 == 0 ? 0 : $0 + 1 } ?? 1
        var frames: [AnimationFrame] = []
        for index in 0..<count {
            try Task.checkCancellation()
            let frame = try autoreleasepool {
                guard let image = CGImageSourceCreateImageAtIndex(source, index, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
                      image.width == width, image.height == height else { throw CodecError.decode }
                let metadata = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
                let timing = metadata[kCGImagePropertyGIFDictionary] as? [CFString: Any] ?? [:]
                let seconds = timing[kCGImagePropertyGIFUnclampedDelayTime] as? Double
                    ?? timing[kCGImagePropertyGIFDelayTime] as? Double ?? 0.1
                // 未设置或零时长帧使用 100ms；正值保留 GIF 的百分之一秒精度。
                let delay = seconds.isFinite && seconds > 0 ? min(655.35, seconds) : 0.1
                return AnimationFrame(image: image, milliseconds: max(10, Int((delay * 1000).rounded())))
            }
            frames.append(frame)
        }
        return ImageAnimation(frames: frames, playCount: plays, format: .gif)
    }

    private static func gifRepeatCount(_ data: Data) throws -> Int? {
        let bytes = [UInt8](data)
        guard bytes.count >= 13 else { throw CodecError.decode }
        var cursor = 13
        if bytes[10] & 0x80 != 0 { cursor += 3 * (1 << (Int(bytes[10] & 7) + 1)) }
        // 按 GIF 块边界跳过图像数据，避免把压缩像素中的字节误认成循环扩展。
        func subblocks() throws -> [UInt8] {
            var first: [UInt8] = []
            while cursor < bytes.count {
                let size = Int(bytes[cursor]); cursor += 1
                if size == 0 { return first }
                guard cursor <= bytes.count - size else { throw CodecError.decode }
                if first.isEmpty { first = Array(bytes[cursor..<(cursor + size)]) }
                cursor += size
            }
            throw CodecError.decode
        }
        while cursor < bytes.count {
            let marker = bytes[cursor]; cursor += 1
            switch marker {
            case 0x3b: return nil
            case 0x21:
                guard cursor < bytes.count else { throw CodecError.decode }
                let label = bytes[cursor]; cursor += 1
                if label == 0xff {
                    guard cursor < bytes.count else { throw CodecError.decode }
                    let size = Int(bytes[cursor]); cursor += 1
                    guard cursor <= bytes.count - size else { throw CodecError.decode }
                    let identifier = String(bytes: bytes[cursor..<(cursor + size)], encoding: .ascii)
                    cursor += size
                    let values = try subblocks()
                    if (identifier == "NETSCAPE2.0" || identifier == "ANIMEXTS1.0"), values.count >= 3, values[0] == 1 {
                        return Int(values[1]) | Int(values[2]) << 8
                    }
                } else { _ = try subblocks() }
            case 0x2c:
                guard cursor <= bytes.count - 9 else { throw CodecError.decode }
                let packed = bytes[cursor + 8]; cursor += 9
                if packed & 0x80 != 0 { cursor += 3 * (1 << (Int(packed & 7) + 1)) }
                guard cursor < bytes.count else { throw CodecError.decode }
                cursor += 1 // LZW 最小代码长度。
                _ = try subblocks()
            default: throw CodecError.decode
            }
        }
        throw CodecError.decode
    }

    private static func decodeWebP(_ data: Data) throws -> ImageAnimation? {
        try data.withUnsafeBytes { bytes in
            var input = WebPData(bytes: bytes.bindMemory(to: UInt8.self).baseAddress, size: data.count)
            guard let demux = WebPDemux(&input) else { throw CodecError.decode }
            defer { WebPDemuxDelete(demux) }
            let count = Int(WebPDemuxGetI(demux, WEBP_FF_FRAME_COUNT))
            guard count > 1 else { return nil }
            let width = Int(WebPDemuxGetI(demux, WEBP_FF_CANVAS_WIDTH))
            let height = Int(WebPDemuxGetI(demux, WEBP_FF_CANVAS_HEIGHT))
            try validate(width: width, height: height, count: count)
            guard let decoder = WebPAnimDecoderNew(&input, nil) else { throw CodecError.decode }
            defer { WebPAnimDecoderDelete(decoder) }
            var frames: [AnimationFrame] = []
            var previous: Int32 = 0
            while WebPAnimDecoderHasMoreFrames(decoder) != 0 {
                try Task.checkCancellation()
                var pixels: UnsafeMutablePointer<UInt8>?
                var timestamp: Int32 = 0
                guard WebPAnimDecoderGetNext(decoder, &pixels, &timestamp) != 0, let pixels,
                      timestamp >= previous, frames.count < count else { throw CodecError.decode }
                let rgba = Data(bytes: pixels, count: width * height * 4)
                guard let provider = CGDataProvider(data: rgba as CFData),
                      let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                          bytesPerRow: width * 4, space: ImageCodec.colorSpace,
                                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                          provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw CodecError.decode }
                frames.append(AnimationFrame(image: image, milliseconds: max(1, Int(timestamp - previous))))
                previous = timestamp
            }
            guard frames.count == count else { throw CodecError.decode }
            return ImageAnimation(frames: frames, playCount: Int(WebPDemuxGetI(demux, WEBP_FF_LOOP_COUNT)), format: .webp)
        }
    }

    static func encode(_ animation: ImageAnimation, settings: ConversionSettings) throws -> Data {
        let first = animation.frames[0].image
        let (width, height) = try settings.outputSize(width: first.width, height: first.height)
        try validate(width: width, height: height, count: animation.frames.count)
        if settings.format == .gif { return try encodeGIF(animation, settings: settings) }
        guard settings.format == .webp, let mux = WebPMuxNew() else { throw CodecError.encode }
        defer { WebPMuxDelete(mux) }
        // WebP 最多 65535 次，GIF 最多 65535 次重复；边界遵循上游 gif2webp 的饱和规则。
        var params = WebPMuxAnimParams(bgcolor: 0, loop_count: Int32(min(65535, animation.playCount)))
        guard WebPMuxSetAnimationParams(mux, &params) == WEBP_MUX_OK else { throw CodecError.encode }
        for frame in animation.frames {
            try Task.checkCancellation()
            try autoreleasepool {
                let data = try ImageCodec.encode(image: frame.image, settings: settings)
                try data.withUnsafeBytes { bytes in
                    var info = WebPMuxFrameInfo()
                    info.bitstream = WebPData(bytes: bytes.bindMemory(to: UInt8.self).baseAddress, size: data.count)
                    info.duration = Int32(frame.milliseconds)
                    info.id = WEBP_CHUNK_ANMF
                    info.dispose_method = WEBP_MUX_DISPOSE_NONE
                    info.blend_method = WEBP_MUX_NO_BLEND
                    guard WebPMuxPushFrame(mux, &info, 1) == WEBP_MUX_OK else { throw CodecError.encode }
                }
            }
        }
        var output = WebPData()
        defer { WebPDataClear(&output) }
        guard WebPMuxAssemble(mux, &output) == WEBP_MUX_OK, let bytes = output.bytes else { throw CodecError.encode }
        return Data(bytes: bytes, count: output.size)
    }

    private static func encodeGIF(_ animation: ImageAnimation, settings: ConversionSettings) throws -> Data {
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(buffer, UTType.gif.identifier as CFString, animation.frames.count, nil) else { throw CodecError.encode }
        // ImageIO 写入参数使用总播放次数，并在 GIF 字节流中自动减一；0 为无限。
        // 单次播放不写循环扩展，以便其他 GIF 播放器正确识别。
        if animation.playCount != 1 {
            CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: animation.playCount]] as CFDictionary)
        }
        for frame in animation.frames {
            try Task.checkCancellation()
            try autoreleasepool {
                // 共用尺寸和像素处理，由 ImageIO 量化为 GIF 调色板。
                guard let image = try ImageCodec.rasterContext(image: frame.image, settings: settings).makeImage() else { throw CodecError.encode }
                let delay = Double(frame.milliseconds) / 1000
                CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
            }
        }
        guard CGImageDestinationFinalize(destination) else { throw CodecError.encode }
        return buffer as Data
    }
}

enum AnimationError: LocalizedError {
    case tooLarge
    var errorDescription: String? { L10n.text(.animationTooLarge) }
}

extension ImageCodec {
    static func loadSequence(url: URL, accessRoot: URL? = nil, pageNumber: Int? = nil) throws -> ImageSequence {
        let scope = accessRoot ?? url
        let accessed = scope.startAccessingSecurityScopedResource()
        defer { if accessed { scope.stopAccessingSecurityScopedResource() } }
        if let pageNumber { return ImageSequence(first: try PDFRenderer.render(url: url, pageNumber: pageNumber)) }
        let data = try Data(contentsOf: url)
        if let animation = try AnimationCodec.decode(data) { return ImageSequence(first: animation.frames[0].image, animation: animation) }
        return ImageSequence(first: try decode(data))
    }

    static func encode(sequence: ImageSequence, settings: ConversionSettings) throws -> Data {
        if let animation = sequence.animation, settings.format == .gif || settings.format == .webp {
            return try AnimationCodec.encode(animation, settings: settings)
        }
        return try encode(image: sequence.first, settings: settings)
    }

    static func convert(sequence: ImageSequence, settings: ConversionSettings) throws -> EncodedImage {
        let data = try encode(sequence: sequence, settings: settings)
        let animation = try AnimationCodec.decode(data)
        let decoded = try animation?.frames[0].image ?? decode(data)
        return EncodedImage(data: data, original: sequence.first, decoded: decoded,
                            originalAnimation: sequence.animation, outputAnimation: animation)
    }
}

extension ImageProcessor {
    func loadSequence(url: URL, accessRoot: URL? = nil, pageNumber: Int? = nil) throws -> ImageSequence {
        try Task.checkCancellation()
        return try autoreleasepool { try ImageCodec.loadSequence(url: url, accessRoot: accessRoot, pageNumber: pageNumber) }
    }
    func convert(sequence: ImageSequence, settings: ConversionSettings) throws -> EncodedImage {
        try Task.checkCancellation()
        return try autoreleasepool { try ImageCodec.convert(sequence: sequence, settings: settings) }
    }
}
