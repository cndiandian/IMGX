import Foundation
import Testing
import UniformTypeIdentifiers
@testable import IMGX

private func temporaryFolder() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func writeImage(_ url: URL) throws -> Data {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var settings = ConversionSettings()
    settings.format = .png
    let data = try ImageCodec.encode(image: fixture(), settings: settings)
    try data.write(to: url)
    return data
}

@MainActor @Test func folderDropProvidersAcceptURLsAndDataRepresentations() async throws {
    let directory = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: directory) }
    _ = try writeImage(directory.appendingPathComponent("sub/image.png"))
    let providers = [
        NSItemProvider(item: directory as NSURL, typeIdentifier: UTType.fileURL.identifier),
        NSItemProvider(item: Data(directory.absoluteString.utf8) as NSData, typeIdentifier: UTType.fileURL.identifier)
    ]
    let model = AppModel()
    for provider in providers {
        let url = try #require(await ImageFileDrop.fileURL(from: provider))
        await model.add([url])
    }
    #expect(model.items.count == 1)
    #expect(model.items.first?.relativeDirectory == [directory.lastPathComponent, "sub"])
}

@MainActor @Test func folderImportPreservesHierarchyAndExistingFiles() async throws {
    let directory = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appendingPathComponent("相册 2026", isDirectory: true)
    let cover = root.appendingPathComponent("cover.PNG")
    let nested = root.appendingPathComponent("旅行/同名.png")
    let deeper = root.appendingPathComponent("旅行/第二天/同名.png")
    let loose = directory.appendingPathComponent("散图.png")
    var sources: [URL: Data] = [:]
    for source in [cover, nested, deeper, loose] { sources[source] = try writeImage(source) }
    let model = AppModel()
    await model.add([root, loose, nested, root.appendingPathComponent("旅行")])
    #expect(model.items.count == 4)
    #expect(!model.isImporting)
    #expect(Set(model.items.map(\.relativePath)) == ["相册 2026/cover.PNG", "相册 2026/旅行/同名.png",
                                                   "相册 2026/旅行/第二天/同名.png", "散图.png"])
    let output = directory.appendingPathComponent("输出", isDirectory: true)
    let existing = output.appendingPathComponent("相册 2026/旅行/同名.webp")
    try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
    let protected = Data("existing output".utf8)
    try protected.write(to: existing)
    await model.export(to: output)
    #expect(model.completedCount == 4)
    for relative in ["相册 2026/cover.webp", "相册 2026/旅行/同名-1.webp", "相册 2026/旅行/第二天/同名.webp", "散图.webp"] {
        let data = try Data(contentsOf: output.appendingPathComponent(relative))
        #expect(try ImageCodec.decode(data).width == 80)
    }
    #expect(try Data(contentsOf: existing) == protected)
    for (source, data) in sources { #expect(try Data(contentsOf: source) == data) }
}

@MainActor @Test func sameNamedFolderRootsRemainSeparateAndClearResetsNames() async throws {
    let directory = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = directory.appendingPathComponent("one/photos")
    let second = directory.appendingPathComponent("two/photos")
    _ = try writeImage(first.appendingPathComponent("sub/photo.png"))
    _ = try writeImage(second.appendingPathComponent("sub/photo.png"))
    let model = AppModel()
    await model.add([first, second])
    #expect(Set(model.items.map(\.relativePath)) == ["photos/sub/photo.png", "photos-1/sub/photo.png"])
    await model.add([first, second])
    #expect(model.items.count == 2)
    let newImage = first.appendingPathComponent("new.png")
    _ = try writeImage(newImage)
    await model.add([URL(fileURLWithPath: first.path, isDirectory: true)])
    #expect(model.items.count == 3)
    #expect(model.items.first(where: { $0.url == newImage.standardizedFileURL })?.relativeDirectory == ["photos"])
    let output = directory.appendingPathComponent("output")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    await model.export(to: output)
    #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("photos/sub/photo.webp").path))
    #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("photos-1/sub/photo.webp").path))
    model.clear()
    await model.add([second])
    #expect(model.items.first?.relativePath == "photos/sub/photo.png")
}

@Test func scannerSkipsHiddenPackagesAndSymlinkCycles() async throws {
    let directory = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appendingPathComponent("folder")
    let visible = root.appendingPathComponent("visible.png")
    _ = try writeImage(visible)
    _ = try writeImage(root.appendingPathComponent(".hidden/hidden.png"))
    _ = try writeImage(root.appendingPathComponent("Example.app/inside.png"))
    let outside = directory.appendingPathComponent("outside/image.png")
    _ = try writeImage(outside)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("cycle"), withDestinationURL: root)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked.png"), withDestinationURL: outside)
    let result = try await ImageImportScanner.shared.scan([root])
    #expect(result.images.map(\.url) == [visible.standardizedFileURL])
    #expect(result.images.first?.subdirectories.isEmpty == true)
    #expect(result.skipped >= 3)
}

@MainActor @Test func emptyFolderImportReportsNoImages() async throws {
    let directory = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel()
    await model.add([directory])
    #expect(model.items.isEmpty && !model.isImporting)
    #expect(model.toast?.text.contains("未找到") == true)
}

@Test func exportRejectsEscapingPathsAndSymlinkParents() throws {
    let directory = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: directory) }
    let output = directory.appendingPathComponent("output")
    let outside = directory.appendingPathComponent("outside")
    for folder in [output, outside] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    try FileManager.default.createSymbolicLink(at: output.appendingPathComponent("linked"), withDestinationURL: outside)
    for components in [[".."], ["/absolute"], ["a/b"], ["linked"], ["."]] {
        #expect(throws: ExportPathError.invalidDirectory) {
            try ExportWriter.write(Data("test".utf8), source: URL(fileURLWithPath: "/source/photo.png"),
                                   format: .webp, directory: output, relativeDirectory: components)
        }
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
}

private actor SuspendedImportScanner: ImageImportScanning {
    private var pending: [CheckedContinuation<ImageImportResult, Never>] = []
    private(set) var requests = 0
    func scan(_ urls: [URL]) async throws -> ImageImportResult {
        requests += 1
        // 故意不响应取消，用于验证旧扫描结果也不能重建已清空的列表。
        return await withCheckedContinuation { pending.append($0) }
    }
    func finishNext(_ result: ImageImportResult) { pending.removeFirst().resume(returning: result) }
}

private func waitForRequests(_ count: Int, scanner: SuspendedImportScanner) async throws {
    for _ in 0..<200 {
        if await scanner.requests >= count { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("导入扫描未开始")
}

@MainActor @Test func clearingPendingImportCannotRepopulateOrResetNewImport() async throws {
    let directory = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: directory) }
    let image = directory.appendingPathComponent("image.png")
    let data = try writeImage(image)
    let result = ImageImportResult(images: [ImportedImage(url: image, originalBytes: Int64(data.count), root: nil, subdirectories: [])])
    let scanner = SuspendedImportScanner()
    let model = AppModel(importScanner: scanner)
    let old = Task { await model.add([image]) }
    try await waitForRequests(1, scanner: scanner)
    #expect(model.isImporting)
    model.clear()
    #expect(!model.isImporting)
    let new = Task { await model.add([image]) }
    try await waitForRequests(2, scanner: scanner)
    await scanner.finishNext(result)
    await old.value
    #expect(model.items.isEmpty && model.isImporting)
    await scanner.finishNext(result)
    await new.value
    #expect(model.items.count == 1 && !model.isImporting)
    let pending = Task { await model.add([image]) }
    try await waitForRequests(3, scanner: scanner)
    let output = directory.appendingPathComponent("output")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    await model.export(to: output)
    #expect(!model.isExporting)
    #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
    model.cancelImport()
    await scanner.finishNext(result)
    await pending.value
    #expect(model.items.count == 1 && !model.isImporting)
}

@MainActor @Test func cancellingImportCallerDiscardsLateScannerResult() async throws {
    let directory = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: directory) }
    let image = directory.appendingPathComponent("image.png")
    let data = try writeImage(image)
    let result = ImageImportResult(images: [ImportedImage(url: image, originalBytes: Int64(data.count), root: nil, subdirectories: [])])
    let scanner = SuspendedImportScanner()
    let model = AppModel(importScanner: scanner)
    let pending = Task { await model.add([image]) }
    try await waitForRequests(1, scanner: scanner)
    pending.cancel()
    await scanner.finishNext(result)
    await pending.value
    #expect(model.items.isEmpty && !model.isImporting)
}
