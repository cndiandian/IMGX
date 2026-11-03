import AppKit
import ImageIO
import Observation
import UniformTypeIdentifiers

struct ImageItem: Identifiable {
    let id = UUID()
    let url: URL
    let originalBytes: Int64
    var thumbnail: NSImage?
    var status: ItemStatus = .pending
}

enum ItemStatus {
    case pending, processing, complete(Int), failed(String)
    var label: String {
        switch self {
        case .pending: "待转换"
        case .processing: "转换中…"
        case .complete(let size): "完成 · \(byteString(Int64(size)))"
        case .failed(let reason): "失败 · \(reason)"
        }
    }
    var isFailure: Bool { if case .failed = self { true } else { false } }
}

func byteString(_ count: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
}

struct ToastMessage: Identifiable {
    enum Kind { case notice, previewError, export }
    let id = UUID()
    let text: String
    let kind: Kind
}

@MainActor @Observable
final class AppModel {
    var items: [ImageItem] = []
    var selectedID: UUID?
    var isExporting = false
    var toast: ToastMessage?
    private var toastTask: Task<Void, Never>?
    var selected: ImageItem? { items.first { $0.id == selectedID } }

    func notify(_ text: String, kind: ToastMessage.Kind = .notice, persistent: Bool = false) {
        toastTask?.cancel()
        let message = ToastMessage(text: text, kind: kind)
        toast = message
        if !persistent {
            toastTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, self?.toast?.id == message.id else { return }
                self?.toast = nil
            }
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }

    func chooseImages() {
        guard !isExporting else { return }
        let panel = NSOpenPanel()
        panel.title = "选择图片"
        panel.allowedContentTypes = [UTType.jpeg, .png, .webP, .heic]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in self?.add(panel.urls) }
        }
    }

    func add(_ urls: [URL]) {
        guard !isExporting else { return }
        var known = Set(items.map { $0.url.standardizedFileURL })
        var skipped = 0
        for input in urls {
            let url = input.standardizedFileURL
            guard url.isFileURL, ImageCodec.supportedExtensions.contains(url.pathExtension.lowercased()),
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else {
                skipped += 1
                continue
            }
            guard known.insert(url).inserted else { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let item = ImageItem(url: url, originalBytes: Int64(size))
            items.append(item)
            let id = item.id
            Task { [weak self] in
                let cgImage = await Task.detached(priority: .utility) {
                    Thumbnail.load(url: url)
                }.value
                guard let self, let index = self.items.firstIndex(where: { $0.id == id }) else { return }
                if let cgImage { self.items[index].thumbnail = NSImage(cgImage: cgImage, size: .zero) }
            }
        }
        if selectedID == nil { selectedID = items.first?.id }
        if skipped > 0 { notify("已跳过 \(skipped) 个不支持的文件。支持 JPG、JPEG、PNG、WebP、HEIC。") }
    }

    func removeSelected() {
        guard !isExporting, let index = items.firstIndex(where: { $0.id == selectedID }) else { return }
        items.remove(at: index)
        selectedID = items.isEmpty ? nil : items[min(index, items.count - 1)].id
    }

    func clear() {
        guard !isExporting else { return }
        items.removeAll()
        selectedID = nil
    }

    func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        let index = items.firstIndex { $0.id == selectedID } ?? 0
        selectedID = items[max(0, min(items.count - 1, index + delta))].id
    }
}

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
        return try? ImageCodec.decode(data)
    }
}
