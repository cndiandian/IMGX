import Testing
import AppKit
import UniformTypeIdentifiers
@testable import IMGX

@MainActor private func copyFixture() throws -> (URL, URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("source.png")
    var settings = ConversionSettings()
    settings.format = .png
    try ImageCodec.encode(image: fixture(), settings: settings).write(to: source)
    return (root, source)
}

@MainActor private func copyTestPasteboard() -> NSPasteboard {
    let board = NSPasteboard(name: .init("IMGX-Copy-Test-" + UUID().uuidString))
    board.clearContents()
    board.setString("keep previous contents", forType: .string)
    return board
}

@MainActor @Test func copiedResultsPreserveEncodedBytesAndProvideCompatibleOutputPixels() async throws {
    let (root, source) = try copyFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let original = try Data(contentsOf: source)
    let board = copyTestPasteboard()
    defer { board.releaseGlobally() }
    let model = AppModel()
    await model.add([source])
    for (format, type) in [(OutputFormat.webp, UTType.webP), (.jpeg, .jpeg), (.png, .png)] {
        model.settings.format = format
        model.settings.size = .half
        model.settings.quality = 28
        try await waitForPreview(model)
        let preview = try #require(model.preview)
        #expect(model.canCopyResult)
        await model.copyCurrentResult(to: board)
        #expect(!model.isCopyingResult)
        #expect(board.data(forType: .init(type.identifier)) == preview.data)
        #expect(board.pasteboardItems?.count == 1)
        #expect(board.data(forType: .fileURL) == nil)
        let compatible = try #require(board.data(forType: .png))
        let image = try ImageCodec.decode(compatible)
        #expect(image.width == 40 && image.height == 20)
        for x in [10, 30] {
            let actual = try rgba(image, x: x, y: 10)
            let expected = try rgba(preview.decoded, x: x, y: 10)
            #expect(zip(actual, expected).allSatisfy { abs(Int($0) - Int($1)) <= 1 })
        }
        #expect(model.toast?.text == L10n.text(.resultCopied))
    }
    #expect(try Data(contentsOf: source) == original)
}

@MainActor @Test func copyingWithoutReadyResultNeverChangesExistingPasteboard() async throws {
    let (root, source) = try copyFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let board = copyTestPasteboard()
    defer { board.releaseGlobally() }
    let model = AppModel()
    #expect(!model.canCopyResult)
    await model.copyCurrentResult(to: board)
    await model.add([source])
    #expect(model.previewLoading && !model.canCopyResult)
    await model.copyCurrentResult(to: board)
    try await waitForPreview(model)
    model.isExporting = true
    await model.copyCurrentResult(to: board)
    model.isExporting = false
    model.editDimension("bad", width: true)
    await model.copyCurrentResult(to: board)
    try await waitForPreview(model)
    #expect(model.preview == nil && !model.canCopyResult)
    await model.copyCurrentResult(to: board)
    #expect(board.string(forType: .string) == "keep previous contents")
}

private actor PendingClipboardRenderer: ClipboardResultPreparing {
    private(set) var requests = 0
    private var continuation: CheckedContinuation<ClipboardImageResult, Never>?
    func clipboardResult(_ preview: EncodedImage, format: OutputFormat) async throws -> ClipboardImageResult {
        requests += 1
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish() {
        continuation?.resume(returning: ClipboardImageResult(representations: [UTType.png.identifier: Data("old result".utf8)]))
        continuation = nil
    }
}

@MainActor @Test func changingResultOrClipboardCannotWriteStalePixels() async throws {
    let (root, source) = try copyFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    for change in ["settings", "clear", "clipboard"] {
        let board = copyTestPasteboard()
        defer { board.releaseGlobally() }
        let renderer = PendingClipboardRenderer()
        let model = AppModel(clipboardRenderer: renderer)
        await model.add([source])
        try await waitForPreview(model)
        let pending = Task { await model.copyCurrentResult(to: board) }
        for _ in 0..<100 {
            if await renderer.requests == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.isCopyingResult && !model.canCopyResult)
        await model.copyCurrentResult(to: board)
        #expect(await renderer.requests == 1)
        if change == "clear" { model.clear() }
        else if change == "settings" { model.settings.size = .quarter }
        else { board.clearContents(); board.setString("newer content", forType: .string) }
        await renderer.finish()
        await pending.value
        #expect(board.string(forType: .string) == (change == "clipboard" ? "newer content" : "keep previous contents"))
        #expect(model.toast?.text == L10n.text(.copyResultChanged))
        #expect(!model.isCopyingResult)
    }
}

private struct FailingClipboardRenderer: ClipboardResultPreparing {
    func clipboardResult(_ preview: EncodedImage, format: OutputFormat) async throws -> ClipboardImageResult {
        throw CodecError.encode
    }
}

@MainActor @Test func failedClipboardPreparationPreservesPreviousContents() async throws {
    let (root, source) = try copyFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let board = copyTestPasteboard()
    defer { board.releaseGlobally() }
    let model = AppModel(clipboardRenderer: FailingClipboardRenderer())
    await model.add([source])
    try await waitForPreview(model)
    await model.copyCurrentResult(to: board)
    #expect(board.string(forType: .string) == "keep previous contents")
    #expect(model.toast?.text == L10n.text(.copyResultFailed))
    #expect(!model.isCopyingResult)
}

@MainActor @Test func copyingPDFUsesOnlySelectedPageAndCurrentDimensions() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("document.pdf")
    try pdfFixture(at: source)
    let original = try Data(contentsOf: source)
    let board = copyTestPasteboard()
    defer { board.releaseGlobally() }
    let model = AppModel()
    await model.add([source])
    model.selectedID = model.items[1].id
    model.settings.format = .png
    model.settings.size = .half
    try await waitForPreview(model)
    let expected = try #require(model.preview?.data)
    await model.copyCurrentResult(to: board)
    #expect(board.pasteboardItems?.count == 1)
    let data = try #require(board.data(forType: .png))
    #expect(data == expected)
    let image = try ImageCodec.decode(data)
    #expect(image.width == 167 && image.height == 292)
    #expect(try Data(contentsOf: source) == original)
}

@MainActor @Test func copyCommandDoesNotDependOnClipboardInputAndRespectsAvailability() {
    let board = copyTestPasteboard()
    defer { board.releaseGlobally() }
    let responder = ClipboardCommandResponder()
    responder.pasteboard = board
    responder.isCopyEnabled = true
    responder.isPasteEnabled = true
    let copyItem = NSMenuItem(title: "Copy", action: #selector(ClipboardCommandResponder.copy(_:)), keyEquivalent: "c")
    let pasteItem = NSMenuItem(title: "Paste", action: #selector(ClipboardCommandResponder.paste(_:)), keyEquivalent: "v")
    #expect(responder.validateUserInterfaceItem(copyItem))
    #expect(!responder.validateUserInterfaceItem(pasteItem))
    var copies = 0
    responder.performCopy = { copies += 1 }
    responder.copy(nil)
    #expect(copies == 1)
    responder.isCopyEnabled = false
    #expect(!responder.validateUserInterfaceItem(copyItem))
    responder.copy(nil)
    #expect(copies == 1)
    #expect(board.string(forType: .string) == "keep previous contents")
}
