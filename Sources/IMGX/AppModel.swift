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
    var selectedID: UUID? { didSet { if oldValue != selectedID { preview = nil; selectedPixelSize = nil; refreshPreview() } } }
    var settings = ConversionSettings() { didSet { if oldValue != settings { refreshPreview() } } }
    var preview: EncodedImage?
    var selectedPixelSize: CGSize?
    var previewLoading = false
    var previewRevision = UUID()
    var lastEditedWidth = true
    var completedCount = 0
    private var previewTask: Task<Void, Never>?
    var isExporting = false
    var toast: ToastMessage?
    private var toastTask: Task<Void, Never>?
    var selected: ImageItem? { items.first { $0.id == selectedID } }

    func refreshPreview() {
        previewTask?.cancel()
        let revision = UUID()
        previewRevision = revision
        guard let item = selected else { preview = nil; previewLoading = false; clearPreviewError(); return }
        let snapshot = settings
        previewLoading = true
        // Old result is hidden immediately so settings and displayed bytes never disagree.
        preview = nil
        previewTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
                let result = try await ImageProcessor.shared.convert(url: item.url, settings: snapshot)
                guard let self, !Task.isCancelled, self.previewRevision == revision else { return }
                self.selectedPixelSize = CGSize(width: result.original.width, height: result.original.height)
                self.preview = result
                self.previewLoading = false
                self.clearPreviewError()
                if snapshot.size == .custom {
                    self.synchronizeDimensions(width: result.original.width, height: result.original.height)
                }
            } catch {
                guard let self, !Task.isCancelled, self.previewRevision == revision else { return }
                self.previewLoading = false
                self.notify(error.localizedDescription, kind: .previewError, persistent: true)
            }
        }
    }

    func clearPreviewError() {
        if toast?.kind == .previewError { dismissToast() }
    }

    func editDimension(_ value: String, width: Bool) {
        lastEditedWidth = width
        var next = settings
        if width { next.width = value } else { next.height = value }
        if value.isEmpty { next.width = ""; next.height = "" }
        else if let source = selectedPixelSize,
                let number = Int(value), (1...16383).contains(number) {
            if width { next.height = String(max(1, Int((Double(number) * source.height / source.width).rounded()))) }
            else { next.width = String(max(1, Int((Double(number) * source.width / source.height).rounded()))) }
        }
        next.size = .custom
        settings = next
    }

    private func synchronizeDimensions(width: Int, height: Int) {
        var next = settings
        if lastEditedWidth, let w = Int(next.width), (1...16383).contains(w) {
            next.height = String(max(1, Int((Double(w) * Double(height) / Double(width)).rounded())))
        } else if !lastEditedWidth, let h = Int(next.height), (1...16383).contains(h) {
            next.width = String(max(1, Int((Double(h) * Double(width) / Double(height)).rounded())))
        }
        if next != settings { settings = next }
    }

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

    func chooseExportDirectory() {
        guard !isExporting, !items.isEmpty else { return }
        let snapshot = settings
        let batch = items.map { ($0.id, $0.url) }
        let panel = NSOpenPanel()
        panel.title = "选择导出文件夹"
        panel.prompt = "导出图片"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        isExporting = true
        panel.begin { [weak self] response in
            Task { @MainActor in
                guard let self else { return }
                guard response == .OK, let directory = panel.url else { self.isExporting = false; return }
                await self.performExport(to: directory, settings: snapshot, batch: batch)
            }
        }
    }

    // Also used by integration tests to exercise the real batch workflow.
    func export(to directory: URL) async {
        guard !isExporting, !items.isEmpty else { return }
        isExporting = true
        await performExport(to: directory, settings: settings, batch: items.map { ($0.id, $0.url) })
    }

    private func performExport(to directory: URL, settings snapshot: ConversionSettings, batch: [(UUID, URL)]) async {
        let access = directory.startAccessingSecurityScopedResource()
        defer {
            if access { directory.stopAccessingSecurityScopedResource() }
            isExporting = false
        }
        completedCount = 0
        var successes = 0
        for index in items.indices { items[index].status = .pending }
        for (id, url) in batch {
            if let index = items.firstIndex(where: { $0.id == id }) { items[index].status = .processing }
            do {
                let result = try await ImageProcessor.shared.export(url: url, settings: snapshot, directory: directory)
                if let index = items.firstIndex(where: { $0.id == id }) { items[index].status = .complete(result.byteCount) }
                successes += 1
            } catch {
                if let index = items.firstIndex(where: { $0.id == id }) { items[index].status = .failed(error.localizedDescription) }
            }
            completedCount += 1
        }
        notify("已导出 \(successes)/\(batch.count) 张图片，保存至 \(directory.path)" + (successes < batch.count ? "。失败原因可在文件列表查看。" : ""), kind: .export)
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
