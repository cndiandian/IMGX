import AppKit
import UniformTypeIdentifiers

struct ClipboardImageResult: Sendable {
    let representations: [String: Data]
}

protocol ClipboardResultPreparing: Sendable {
    func clipboardResult(_ preview: EncodedImage, format: OutputFormat) async throws -> ClipboardImageResult
}

enum ClipboardExport {
    @MainActor static func write(_ result: ClipboardImageResult, to pasteboard: NSPasteboard) -> Bool {
        let item = NSPasteboardItem()
        for (type, data) in result.representations {
            guard item.setData(data, forType: .init(type)) else { return false }
        }
        guard !result.representations.isEmpty else { return false }
        // 所有编码完成后才替换剪贴板，准备失败不会丢失用户原有内容。
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}

extension ImageProcessor: ClipboardResultPreparing {
    func clipboardResult(_ preview: EncodedImage, format: OutputFormat) throws -> ClipboardImageResult {
        try Task.checkCancellation()
        return try autoreleasepool {
            let type: UTType
            switch format {
            case .webp: type = .webP
            case .jpeg: type = .jpeg
            case .png: type = .png
            }
            var representations = [type.identifier: preview.data]
            if format != .png {
                var settings = ConversionSettings()
                settings.format = .png
                // 兼容不接受 WebP/JPEG 的目标应用；来源是已编码结果，而非原图。
                representations[UTType.png.identifier] = try ImageCodec.encode(image: preview.decoded, settings: settings)
            }
            try Task.checkCancellation()
            return ClipboardImageResult(representations: representations)
        }
    }
}
