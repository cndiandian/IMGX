import Foundation

/// 界面输入、比例联动和编码输出共用的尺寸约束。
enum ImageSizing {
    static let maximumDimension = 16_383
    static let maximumPixelCount = 100_000_000

    static func dimension(_ text: String) throws -> Int? {
        guard !text.isEmpty else { return nil }
        guard text.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(text), (1...maximumDimension).contains(value) else {
            throw CodecError.invalidDimensions
        }
        return value
    }

    static func validationMessage(_ text: String) -> String? {
        do { _ = try dimension(text); return nil }
        catch { return error.localizedDescription }
    }
}

enum OutputFormat: String, CaseIterable, Identifiable, Sendable {
    case webp = "WebP", jpeg = "JPEG", png = "PNG"
    var id: Self { self }
    var fileExtension: String { self == .jpeg ? "jpg" : rawValue.lowercased() }
}

enum SizePreset: String, CaseIterable, Identifiable, Sendable {
    case original, half, quarter, custom
    var title: String {
        switch self {
        case .original: L10n.text(.originalSize)
        case .half: "50%"
        case .quarter: "25%"
        case .custom: L10n.text(.custom)
        }
    }
    var id: Self { self }
}

struct ConversionSettings: Equatable, Sendable {
    var format: OutputFormat = .webp
    var quality: Double = 80
    var lossless = false
    var size: SizePreset = .original
    var width: String = ""
    var height: String = ""
    var usesQuality: Bool { format == .jpeg || (format == .webp && !lossless) }

    func outputSize(width sourceWidth: Int, height sourceHeight: Int) throws -> (Int, Int) {
        guard sourceWidth > 0, sourceHeight > 0 else { throw CodecError.invalidDimensions }
        var scale: Double = 1
        switch size {
        case .original: break
        case .half: scale = 0.5
        case .quarter: scale = 0.25
        case .custom:
            let w = try ImageSizing.dimension(width)
            let h = try ImageSizing.dimension(height)
            if let w, let h { scale = min(Double(w) / Double(sourceWidth), Double(h) / Double(sourceHeight)) }
            else if let w { scale = Double(w) / Double(sourceWidth) }
            else if let h { scale = Double(h) / Double(sourceHeight) }
        }
        let w = max(1, (Double(sourceWidth) * scale).rounded())
        let h = max(1, (Double(sourceHeight) * scale).rounded())
        // 在转换为 Int 前检查范围，避免无效输入触发浮点到整数的运行时陷阱。
        guard w.isFinite, h.isFinite,
              w <= Double(ImageSizing.maximumDimension), h <= Double(ImageSizing.maximumDimension),
              w * h <= Double(ImageSizing.maximumPixelCount) else { throw CodecError.imageTooLarge }
        return (Int(w), Int(h))
    }
}

