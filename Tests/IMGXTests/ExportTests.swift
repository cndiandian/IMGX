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
    model.add([first, broken, last])
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
