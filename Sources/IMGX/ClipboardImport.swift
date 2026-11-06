import AppKit
import UniformTypeIdentifiers

/// 系统粘贴命令只在用户操作时提供数据，不轮询或改写系统剪贴板。
enum ClipboardImport {
    static let contentTypes: [UTType] = [.fileURL, .png, .tiff, .jpeg, .webP, .heic, .image]

    @MainActor static func providers(from pasteboard: NSPasteboard) -> [NSItemProvider] {
        (pasteboard.pasteboardItems ?? []).compactMap { item in
            let types = contentTypes.map { NSPasteboard.PasteboardType($0.identifier) }
            let type = item.availableType(from: types) ?? item.types.first {
                UTType($0.rawValue)?.conforms(to: .image) == true
            }
            guard let type, let data = item.data(forType: type) else { return nil }
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: type.rawValue, visibility: .all) { completion in
                completion(data, nil)
                return nil
            }
            return provider
        }
    }

    @MainActor static func read(_ providers: [NSItemProvider]) async throws -> (files: [URL], images: [Data], unreadable: Int) {
        var files: [URL] = []
        var images: [Data] = []
        var unreadable = 0
        for provider in providers {
            try Task.checkCancellation()
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                if let url = await ImageFileDrop.fileURL(from: provider), url.isFileURL { files.append(url) }
                else { unreadable += 1 }
            } else if let type = contentTypes.dropFirst().first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) {
                let data: Data? = await withCheckedContinuation { continuation in
                    provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                        continuation.resume(returning: data)
                    }
                }
                if let data { images.append(data) } else { unreadable += 1 }
            }
        }
        try Task.checkCancellation()
        return (files, images, unreadable)
    }
}

/// 只管理本窗口生成的剪贴板副本，绝不清理用户选择的源文件。
final class ClipboardImageStore: Sendable {
    let directory: URL

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("IMGX-Clipboard-" + UUID().uuidString, isDirectory: true)
    }

    deinit { discardAll() }

    func discardAll() { try? FileManager.default.removeItem(at: directory) }

    func write(_ data: Data, name: String) throws -> URL {
        let batch = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: batch, withIntermediateDirectories: true)
        let url = batch.appendingPathComponent(name).appendingPathExtension("png")
        do { try data.write(to: url, options: .withoutOverwriting) }
        catch { try? FileManager.default.removeItem(at: batch); throw error }
        return url
    }

    func discard(_ urls: [URL]) {
        let prefix = directory.standardizedFileURL.path + "/"
        for url in Set(urls) where url.standardizedFileURL.path.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: url)
            // 每个副本有独立目录，移除后一起清理空目录。
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
    }
}

struct PreparedClipboardImages: Sendable {
    var urls: [URL] = []
    var unreadable = 0
}

extension ImageProcessor {
    func prepareClipboard(_ images: [Data], store: ClipboardImageStore, name: String) throws -> PreparedClipboardImages {
        var result = PreparedClipboardImages()
        do {
            for (index, data) in images.enumerated() {
                try Task.checkCancellation()
                do {
                    let url = try autoreleasepool {
                        let image = try ImageCodec.decode(data)
                        var settings = ConversionSettings()
                        settings.format = .png
                        let png = try ImageCodec.encode(image: image, settings: settings)
                        let filename = images.count > 1 ? "\(name)-\(index + 1)" : name
                        try Task.checkCancellation()
                        return try store.write(png, name: filename)
                    }
                    result.urls.append(url)
                } catch { result.unreadable += 1 }
            }
            try Task.checkCancellation()
            return result
        } catch {
            store.discard(result.urls)
            throw error
        }
    }
}
