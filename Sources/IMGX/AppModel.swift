import AppKit
import Observation
import UniformTypeIdentifiers

struct ImageItem: Identifiable {
    let id = UUID()
    let url: URL
    let originalBytes: Int64
    let importRoot: URL?
    let relativeDirectory: [String]
    var pageNumber: Int? = nil
    var displayName: String { pageNumber.map { L10n.text(.pdfPageName, url.lastPathComponent, String($0)) } ?? url.lastPathComponent }
    var relativePath: String { (relativeDirectory + [displayName]).joined(separator: "/") }
    var thumbnail: NSImage?
    var status: ItemStatus = .pending
}

enum ItemStatus {
    case pending, processing, complete(Int), failed(String)
    var label: String {
        switch self {
        case .pending: L10n.text(.pending)
        case .processing: L10n.text(.processing)
        case .complete(let size): L10n.text(.completeSize, byteString(Int64(size)))
        case .failed(let reason): L10n.text(.failedReason, reason)
        }
    }
    var symbol: String {
        switch self {
        case .pending: "circle.dotted"
        case .processing: "arrow.triangle.2.circlepath"
        case .complete: "checkmark.circle"
        case .failed: "exclamationmark.circle"
        }
    }
    var isFailure: Bool { if case .failed = self { true } else { false } }
}

func byteString(_ count: Int64) -> String {
    count.formatted(.byteCount(style: .file).locale(Locale(identifier: L10n.language.rawValue)))
}

struct ToastMessage: Identifiable {
    enum Kind { case notice, previewError, export }
    let id = UUID()
    let text: String
    let kind: Kind
    var exportDirectory: URL? = nil
}

@MainActor @Observable
final class AppModel {
    private(set) var items: [ImageItem] = []
    var selectedID: UUID? {
        didSet {
            guard oldValue != selectedID else { return }
            preview = nil
            selectedSource = nil
            selectedPixelSize = nil
            refreshPreview()
        }
    }
    var settings = ConversionSettings() {
        didSet {
            if oldValue != settings { refreshPreview() }
        }
    }
    private(set) var preview: EncodedImage?
    private(set) var selectedPixelSize: CGSize?
    @ObservationIgnored private var selectedSource: CGImage?
    private(set) var previewLoading = false
    @ObservationIgnored private var previewRevision = UUID()
    @ObservationIgnored private var lastEditedWidth = true
    private(set) var completedCount = 0
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    var isExporting = false
    private(set) var isChoosingExportDestination = false
    private(set) var toast: ToastMessage?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    private(set) var isImporting = false
    @ObservationIgnored private let clipboardStore = ClipboardImageStore()
    private let importScanner: any ImageImportScanning
    @ObservationIgnored private var importTasks: [UUID: Task<ImageImportResult, Error>] = [:]
    @ObservationIgnored private var importRevision = UUID()
    @ObservationIgnored private var rootNames: [URL: String] = [:]
    var selected: ImageItem? { items.first { $0.id == selectedID } }

    init(importScanner: any ImageImportScanning = ImageImportScanner.shared) {
        self.importScanner = importScanner
    }

    var dimensionError: String? {
        guard settings.size == .custom else { return nil }
        do {
            _ = try settings.outputSize(width: Int(selectedPixelSize?.width ?? 1),
                                             height: Int(selectedPixelSize?.height ?? 1))
            return nil
        } catch { return error.localizedDescription }
    }

    private func refreshPreview() {
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
                guard let self else { return }
                let source: CGImage
                if let cached = self.selectedSource { source = cached }
                else { source = try await ImageProcessor.shared.load(url: item.url, accessRoot: item.importRoot, pageNumber: item.pageNumber) }
                guard !Task.isCancelled, self.previewRevision == revision else { return }
                self.selectedSource = source
                self.selectedPixelSize = CGSize(width: source.width, height: source.height)
                if snapshot.size == .custom { self.synchronizeDimensions(width: source.width, height: source.height) }
                guard !Task.isCancelled, self.previewRevision == revision else { return }
                let result = try await ImageProcessor.shared.convert(image: source, settings: snapshot)
                guard !Task.isCancelled, self.previewRevision == revision else { return }
                self.selectedPixelSize = CGSize(width: result.original.width, height: result.original.height)
                self.preview = result
                self.previewLoading = false
                self.clearPreviewError()
            } catch {
                guard let self, !Task.isCancelled, self.previewRevision == revision else { return }
                self.previewLoading = false
                self.notify(error.localizedDescription, kind: .previewError, persistent: true)
            }
        }
    }

    private func clearPreviewError() {
        if toast?.kind == .previewError { dismissToast() }
    }

    func editDimension(_ value: String, width: Bool) {
        lastEditedWidth = width
        var next = settings
        if width { next.width = value } else { next.height = value }
        if value.isEmpty { next.width = ""; next.height = "" }
        else if let source = selectedPixelSize,
                let number = try? ImageSizing.dimension(value) {
            if width { next.height = String(max(1, Int((Double(number) * source.height / source.width).rounded()))) }
            else { next.width = String(max(1, Int((Double(number) * source.width / source.height).rounded()))) }
        }
        next.size = .custom
        settings = next
    }

    private func synchronizeDimensions(width: Int, height: Int) {
        var next = settings
        if lastEditedWidth, let w = try? ImageSizing.dimension(next.width) {
            next.height = String(max(1, Int((Double(w) * Double(height) / Double(width)).rounded())))
        } else if !lastEditedWidth, let h = try? ImageSizing.dimension(next.height) {
            next.width = String(max(1, Int((Double(h) * Double(width) / Double(height)).rounded())))
        }
        if next != settings { settings = next }
    }

    func notify(_ text: String, kind: ToastMessage.Kind = .notice, persistent: Bool = false, exportDirectory: URL? = nil) {
        toastTask?.cancel()
        let message = ToastMessage(text: text, kind: kind, exportDirectory: exportDirectory)
        toast = message
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                             userInfo: [.announcement: text + (exportDirectory.map { L10n.text(.savedPath, $0.path) } ?? ""), .priority: NSAccessibilityPriorityLevel.medium.rawValue])
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
        guard !isExporting, NSApp.mainWindow?.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.text(.chooseInput)
        panel.allowedContentTypes = [UTType.jpeg, .png, .webP, .heic, .pdf, .folder]
        panel.prompt = L10n.text(.open)
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        present(panel) { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in await self?.add(panel.urls) }
        }
    }

    private func present(_ panel: NSOpenPanel, completion: @escaping @MainActor (NSApplication.ModalResponse) -> Void) {
        if let window = NSApp.mainWindow ?? NSApp.keyWindow {
            guard window.attachedSheet == nil else { return }
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    func add(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        await performImport { try await self.importScanner.scan(urls) }
    }

    func paste(_ providers: [NSItemProvider]) async {
        guard !providers.isEmpty else { return }
        await performImport {
            let input = try await ClipboardImport.read(providers)
            let prepared = try await ImageProcessor.shared.prepareClipboard(input.images, store: self.clipboardStore,
                                                                            name: L10n.text(.clipboardImage))
            var imported = false
            defer { if !imported || Task.isCancelled { self.clipboardStore.discard(prepared.urls) } }
            var result = try await self.importScanner.scan(input.files + prepared.urls)
            try Task.checkCancellation()
            result.unreadable += input.unreadable + prepared.unreadable
            imported = true
            return result
        }
    }

    private func performImport(_ operation: @escaping @MainActor () async throws -> ImageImportResult) async {
        guard !isExporting else { return }
        let id = UUID()
        let revision = importRevision
        let task = Task { try await operation() }
        importTasks[id] = task
        isImporting = true
        defer {
            importTasks[id] = nil
            isImporting = !importTasks.isEmpty
        }
        do {
            let result = try await withTaskCancellationHandler(operation: { try await task.value },
                                                              onCancel: { task.cancel() })
            guard !Task.isCancelled, importRevision == revision else {
                clipboardStore.discard(result.images.map(\.url))
                return
            }
            append(result)
        } catch is CancellationError {
            // 取消导入保留之前已添加的图片。
        } catch {
            guard importRevision == revision else { return }
            notify(L10n.text(.importFailed, error.localizedDescription))
        }
    }

    func discardClipboardCache() {
        cancelImport()
        clipboardStore.discardAll()
    }

    func cancelImport() {
        importRevision = UUID()
        for task in importTasks.values { task.cancel() }
        importTasks.removeAll()
        isImporting = false
    }

    private func append(_ result: ImageImportResult) {
        var known = Set(items.map { ImportIdentity(url: $0.url.standardizedFileURL, pageNumber: $0.pageNumber) })
        var additions: [ImageItem] = []
        for image in result.images {
            guard known.insert(ImportIdentity(url: image.url, pageNumber: image.pageNumber)).inserted else { continue }
            let relativeDirectory = image.root.map { [rootName(for: $0)] + image.subdirectories } ?? []
            let item = ImageItem(url: image.url, originalBytes: image.originalBytes,
                                 importRoot: image.root, relativeDirectory: relativeDirectory, pageNumber: image.pageNumber)
            additions.append(item)
        }
        items.append(contentsOf: additions)
        if selectedID == nil { selectedID = items.first?.id }
        for item in additions {
            let id = item.id
            let url = item.url
            let root = item.importRoot
            let pageNumber = item.pageNumber
            Task { [weak self] in
                let cgImage = await ThumbnailWorker.shared.load(url: url, accessRoot: root, pageNumber: pageNumber)
                guard let self, let index = self.items.firstIndex(where: { $0.id == id }) else { return }
                if let cgImage { self.items[index].thumbnail = NSImage(cgImage: cgImage, size: .zero) }
            }
        }
        var notices: [String] = []
        if result.images.isEmpty && result.includedFolders { notices.append(L10n.text(.emptyFolder)) }
        if result.skipped > 0 { notices.append(L10n.text(.skippedItems, String(result.skipped))) }
        if result.unreadable > 0 { notices.append(L10n.text(.unreadableItems, String(result.unreadable))) }
        if !result.failures.isEmpty { notices.append(result.failures.prefix(3).joined(separator: "\n")) }
        if !notices.isEmpty { notify(notices.joined(separator: "\n")) }
    }

    private func rootName(for root: URL) -> String {
        let key = URL(fileURLWithPath: root.standardizedFileURL.path, isDirectory: true)
        if let name = rootNames[key] { return name }
        let basename = root.lastPathComponent
        let stem = basename.isEmpty || basename == "/" ? L10n.text(.folder) : basename
        let used = Set(rootNames.values.map { $0.precomposedStringWithCanonicalMapping.lowercased() })
        var name = stem
        var index = 1
        while used.contains(name.precomposedStringWithCanonicalMapping.lowercased()) {
            name = "\(stem)-\(index)"
            index += 1
        }
        rootNames[key] = name
        return name
    }

    func removeSelected() {
        guard !isExporting, let index = items.firstIndex(where: { $0.id == selectedID }) else { return }
        let removed = items.remove(at: index)
        clipboardStore.discard([removed.url])
        selectedID = items.isEmpty ? nil : items[min(index, items.count - 1)].id
        if items.isEmpty { rootNames.removeAll() }
    }

    func clear() {
        guard !isExporting else { return }
        cancelImport()
        clipboardStore.discard(items.map(\.url))
        items.removeAll()
        rootNames.removeAll()
        selectedID = nil
    }

    func chooseExportDirectory() {
        guard !isExporting, !isImporting, !items.isEmpty, NSApp.mainWindow?.attachedSheet == nil else { return }
        let snapshot = settings
        let batch = exportBatch
        let panel = NSOpenPanel()
        panel.title = L10n.text(.chooseExport)
        panel.prompt = L10n.text(.exportImages)
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        completedCount = 0
        isChoosingExportDestination = true
        isExporting = true
        present(panel) { [weak self] response in
            Task { @MainActor in
                guard let self else { return }
                self.isChoosingExportDestination = false
                guard response == .OK, let directory = panel.url else { self.isExporting = false; return }
                await self.performExport(to: directory, settings: snapshot, batch: batch)
            }
        }
    }

    // Also used by integration tests to exercise the real batch workflow.
    func export(to directory: URL) async {
        guard !isExporting, !isImporting, !items.isEmpty else { return }
        isExporting = true
        await performExport(to: directory, settings: settings, batch: exportBatch)
    }

    private var exportBatch: [ExportRequest] {
        items.map { ExportRequest(id: $0.id, url: $0.url, accessRoot: $0.importRoot, relativeDirectory: $0.relativeDirectory, pageNumber: $0.pageNumber) }
    }

    private func performExport(to directory: URL, settings snapshot: ConversionSettings, batch: [ExportRequest]) async {
        let access = directory.startAccessingSecurityScopedResource()
        defer {
            if access { directory.stopAccessingSecurityScopedResource() }
            isExporting = false
        }
        completedCount = 0
        var successes = 0
        for index in items.indices { items[index].status = .pending }
        for request in batch {
            let id = request.id
            if let index = items.firstIndex(where: { $0.id == id }) { items[index].status = .processing }
            do {
                let result = try await ImageProcessor.shared.export(url: request.url, settings: snapshot, directory: directory,
                                                                    relativeDirectory: request.relativeDirectory, accessRoot: request.accessRoot, pageNumber: request.pageNumber)
                if let index = items.firstIndex(where: { $0.id == id }) { items[index].status = .complete(result.byteCount) }
                successes += 1
            } catch {
                if let index = items.firstIndex(where: { $0.id == id }) { items[index].status = .failed(error.localizedDescription) }
            }
            completedCount += 1
        }
        notify(L10n.text(.exportSummary, String(successes), String(batch.count)) + (successes < batch.count ? L10n.text(.exportFailures) : ""),
               kind: .export, exportDirectory: directory)
    }

    func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        let index = items.firstIndex { $0.id == selectedID } ?? 0
        selectedID = items[max(0, min(items.count - 1, index + delta))].id
    }
}
