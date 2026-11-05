import Testing
import Foundation
@testable import IMGX

@MainActor @Test func batchContinuesAfterFailureAndNeverOverwrites() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    var settings = ConversionSettings()
    settings.format = .png
    let input = try ImageCodec.convert(image: fixture(), settings: settings).data
    let first = dir.appendingPathComponent("first.png")
    let broken = dir.appendingPathComponent("broken.png")
    let last = dir.appendingPathComponent("last.png")
    try input.write(to: first)
    try input.write(to: last)
    try Data("broken".utf8).write(to: broken)
    let existing = dir.appendingPathComponent("first-1.png")
    try Data("keep existing output".utf8).write(to: existing)
    let model = AppModel()
    await model.add([first, broken, last])
    model.settings = settings
    try await waitForPreview(model)
    let expected = try #require(model.preview?.data)
    await model.export(to: dir)
    #expect(!model.isExporting && model.completedCount == 3)
    #expect(try Data(contentsOf: first) == input)
    #expect(try Data(contentsOf: existing) == Data("keep existing output".utf8))
    #expect(try Data(contentsOf: dir.appendingPathComponent("first-2.png")) == expected)
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("last-1.png").path))
    #expect(model.items[1].status.isFailure)
    if case .complete = model.items[2].status {} else { Issue.record("失败项后续图片未完成") }
    #expect(model.toast?.text.contains("2/3") == true)
    #expect(model.toast?.exportDirectory == dir)
}

@Test func concurrentExportsUseExclusiveNames() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let urls = try await withThrowingTaskGroup(of: URL.self) { group in
        for index in 0..<10 {
            group.addTask {
                try ExportWriter.write(Data("content \(index)".utf8), source: URL(fileURLWithPath: "/source/picture.png"), format: .webp, directory: dir)
            }
        }
        var results: [URL] = []
        for try await url in group { results.append(url) }
        return results
    }
    #expect(Set(urls).count == 10)
    let contents = try urls.map { try Data(contentsOf: $0) }
    #expect(Set(contents).count == 10)
}

@Test func batchEncodingMatchesPreviewAcrossFormats() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var settings = ConversionSettings()
    settings.format = .png
    let source = directory.appendingPathComponent("source.png")
    let original = try ImageCodec.convert(image: fixture(), settings: settings).data
    try original.write(to: source)
    for format in OutputFormat.allCases {
        settings.format = format
        settings.quality = 37
        settings.size = .half
        let preview = try ImageCodec.convert(url: source, settings: settings)
        let output = try await ImageProcessor.shared.export(url: source, settings: settings, directory: directory)
        let data = try Data(contentsOf: output.url)
        #expect(data == preview.data)
        #expect(output.byteCount == data.count)
        #expect(try ImageCodec.decode(data).width == 40)
    }
    #expect(try Data(contentsOf: source) == original)
}

@MainActor @Test func exportRetainsParameterSnapshot() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    var settings = ConversionSettings()
    settings.format = .png
    let data = try ImageCodec.convert(image: fixture(), settings: settings).data
    let urls = (0..<4).map { dir.appendingPathComponent("input-\($0).png") }
    for url in urls { try data.write(to: url) }
    let model = AppModel()
    await model.add(urls)
    model.settings = settings
    let task = Task { await model.export(to: dir) }
    await Task.yield()
    // Change the live settings after the batch has captured its snapshot.
    while !model.isExporting && !task.isCancelled { await Task.yield(); if model.completedCount > 0 { break } }
    model.settings.format = .jpeg
    await task.value
    #expect(model.toast?.exportDirectory == dir)
    model.notify("普通提示")
    #expect(model.toast?.exportDirectory == nil)
    for index in 0..<4 {
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("input-\(index)-1.png").path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("input-\(index).jpg").path))
    }
}
