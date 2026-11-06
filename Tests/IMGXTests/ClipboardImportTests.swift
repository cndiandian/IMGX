import Testing
import AppKit
import UniformTypeIdentifiers
@testable import IMGX

@MainActor private func imageProvider(_ data: Data, type: UTType = .png) -> NSItemProvider {
    let provider = NSItemProvider()
    provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
        completion(data, nil)
        return nil
    }
    return provider
}

@MainActor @Test func clipboardPNGAndTIFFPreserveAlphaPreviewAndExport() async throws {
    let source = try fixture()
    var settings = ConversionSettings()
    settings.format = .png
    let png = try ImageCodec.encode(image: source, settings: settings)
    let tiff = try #require(NSBitmapImageRep(cgImage: source).representation(using: .tiff, properties: [:]))
    let model = AppModel()
    await model.paste([imageProvider(png), imageProvider(tiff, type: .tiff)])
    #expect(model.items.count == 2 && !model.isImporting)
    let copies = model.items.map(\.url)
    for copy in copies {
        #expect(copy.pathExtension == "png")
        let image = try ImageCodec.load(url: copy)
        #expect(image.width == 80 && image.height == 40)
        #expect(try rgba(image, x: 60, y: 20)[3] == 0)
        #expect((125...130).contains(Int(try rgba(image, x: 20, y: 20)[3])))
    }
    model.settings = settings
    try await waitForPreview(model)
    let preview = try #require(model.preview?.data)
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: output) }
    await model.export(to: output)
    let files = try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
    #expect(files.count == 2)
    #expect(try files.contains { try Data(contentsOf: $0) == preview })
    model.removeSelected()
    #expect(!FileManager.default.fileExists(atPath: copies[0].path))
    #expect(FileManager.default.fileExists(atPath: copies[1].path))
    model.clear()
    #expect(!FileManager.default.fileExists(atPath: copies[1].path))
    #expect(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
}

@MainActor @Test func clipboardFilesTakePriorityOverThumbnailsAndKeepSources() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var settings = ConversionSettings()
    settings.format = .png
    let bytes = try ImageCodec.encode(image: fixture(), settings: settings)
    let source = root.appendingPathComponent("photo.png")
    try bytes.write(to: source)
    try pdfFixture(at: root.appendingPathComponent("document.pdf"))
    let file = NSItemProvider(item: source as NSURL, typeIdentifier: UTType.fileURL.identifier)
    file.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
        completion(bytes, nil); return nil
    }
    let folder = NSItemProvider(item: root as NSURL, typeIdentifier: UTType.fileURL.identifier)
    let model = AppModel()
    await model.paste([file, file, folder])
    #expect(model.items.count == 3)
    #expect(model.items.filter { $0.url == source }.count == 1)
    #expect(model.items.first?.relativeDirectory.isEmpty == true)
    #expect(model.items.filter { $0.pageNumber != nil }.count == 2)
    model.clear()
    #expect(try Data(contentsOf: source) == bytes)
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("document.pdf").path))
}

@MainActor @Test func invalidClipboardItemsDoNotBlockValidImagesAndExportBlocksPaste() async throws {
    var settings = ConversionSettings()
    settings.format = .png
    let png = try ImageCodec.encode(image: fixture(), settings: settings)
    let model = AppModel()
    await model.paste([imageProvider(Data("broken".utf8)), imageProvider(png)])
    #expect(model.items.count == 1)
    #expect(model.toast?.text == L10n.text(.unreadableItems, "1"))
    let copy = try #require(model.items.first?.url)
    model.isExporting = true
    await model.paste([imageProvider(png)])
    #expect(model.items.count == 1)
    model.discardClipboardCache()
    #expect(!FileManager.default.fileExists(atPath: copy.path))
    model.isExporting = false
    model.clear()
    #expect(!FileManager.default.fileExists(atPath: copy.path))
    let text = NSItemProvider(item: "hello" as NSString, typeIdentifier: UTType.utf8PlainText.identifier)
    await model.paste([text])
    #expect(model.items.isEmpty)
}

private actor PausedClipboardScanner: ImageImportScanning {
    private(set) var urls: [URL] = []
    private var continuation: CheckedContinuation<ImageImportResult, Never>?
    func scan(_ urls: [URL]) async throws -> ImageImportResult {
        self.urls = urls
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish() {
        continuation?.resume(returning: ImageImportResult(images: urls.map {
            ImportedImage(url: $0, originalBytes: 1, root: nil, subdirectories: [])
        }))
        continuation = nil
    }
}

@MainActor @Test func clearingPendingPasteDiscardsCopiesAndLateResults() async throws {
    var settings = ConversionSettings()
    settings.format = .png
    let png = try ImageCodec.encode(image: fixture(), settings: settings)
    let scanner = PausedClipboardScanner()
    let model = AppModel(importScanner: scanner)
    let paste = Task { await model.paste([imageProvider(png)]) }
    for _ in 0..<200 {
        if !(await scanner.urls).isEmpty { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    let urls = await scanner.urls
    #expect(urls.count == 1 && model.isImporting)
    model.clear()
    await scanner.finish()
    await paste.value
    #expect(model.items.isEmpty && !model.isImporting)
    #expect(urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
}

@Test func clipboardStoreOnlyDeletesOwnedCopiesAndCleansUpOnRelease() throws {
    let external = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
    let original = Data("original".utf8)
    try original.write(to: external)
    defer { try? FileManager.default.removeItem(at: external) }
    let root: URL
    do {
        let store = ClipboardImageStore()
        root = store.directory
        let copy = try store.write(Data("private copy".utf8), name: "Clipboard")
        store.discard([external])
        #expect(try Data(contentsOf: external) == original)
        #expect(FileManager.default.fileExists(atPath: copy.path))
        store.discardAll()
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(try Data(contentsOf: external) == original)
        _ = try store.write(Data("another copy".utf8), name: "Clipboard")
    }
    #expect(!FileManager.default.fileExists(atPath: root.path))
    #expect(try Data(contentsOf: external) == original)
}

@MainActor @Test func systemPasteResponderValidatesImageContentAndSnapshotsPasteboard() async throws {
    let pasteboard = NSPasteboard(name: .init("IMGX-Test-" + UUID().uuidString))
    defer { pasteboard.releaseGlobally() }
    let responder = ClipboardCommandResponder()
    responder.pasteboard = pasteboard
    responder.isPasteEnabled = true
    let item = NSMenuItem(title: "Paste", action: #selector(ClipboardCommandResponder.paste(_:)), keyEquivalent: "v")
    pasteboard.clearContents()
    pasteboard.setString("320", forType: .string)
    #expect(!responder.validateUserInterfaceItem(item))
    var settings = ConversionSettings()
    settings.format = .png
    let png = try ImageCodec.encode(image: fixture(), settings: settings)
    pasteboard.clearContents()
    pasteboard.setData(png, forType: .png)
    #expect(responder.validateUserInterfaceItem(item))
    var captured: [NSItemProvider] = []
    responder.performPaste = { captured = $0 }
    responder.paste(nil)
    // 取得快照后原剪贴板变化，不改变本次粘贴的数据。
    pasteboard.clearContents()
    pasteboard.setString("different", forType: .string)
    let snapshot = try await ClipboardImport.read(captured)
    #expect(snapshot.images == [png])
    responder.isPasteEnabled = false
    captured = []
    responder.paste(nil)
    #expect(captured.isEmpty)
}
