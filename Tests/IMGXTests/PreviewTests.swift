import Testing
import Foundation
@testable import IMGX

@MainActor func waitForPreview(_ model: AppModel) async throws {
    for _ in 0..<100 {
        if !model.previewLoading { return }
        try await Task.sleep(for: .milliseconds(30))
    }
    Issue.record("预览在 3 秒内未完成")
}

@MainActor @Test func previewUsesLatestSettingsAndPreservesImportNotice() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var settings = ConversionSettings()
    settings.format = .png
    let url = directory.appendingPathComponent("sample.png")
    try ImageCodec.convert(image: fixture(), settings: settings).data.write(to: url)
    let model = AppModel()
    model.add([url, directory.appendingPathComponent("skip.txt")])
    model.settings.size = .half
    model.settings.size = .quarter
    try await waitForPreview(model)
    #expect(model.preview?.decoded.width == 20)
    #expect(model.toast?.kind == .notice)
    model.editDimension("60", width: true)
    #expect(model.settings.height == "30")
    try await waitForPreview(model)
    #expect(model.preview?.decoded.width == 60)
    model.editDimension("bad", width: true)
    try await waitForPreview(model)
    #expect(model.preview == nil && model.toast?.kind == .previewError)
    model.editDimension("", width: true)
    #expect(model.settings.width.isEmpty && model.settings.height.isEmpty)
    try await waitForPreview(model)
    #expect(model.preview?.decoded.width == 80)
    #expect(model.toast == nil)
    model.clear()
    #expect(model.preview == nil && !model.previewLoading)
}
