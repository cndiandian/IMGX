import Testing
import CoreGraphics
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

@MainActor @Test func switchingImageRelinksFromLastEditedDirection() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    var png = ConversionSettings()
    png.format = .png
    let landscape = dir.appendingPathComponent("landscape.png")
    try ImageCodec.convert(image: fixture(), settings: png).data.write(to: landscape)
    let context = try #require(CGContext(data: nil, width: 40, height: 80, bitsPerComponent: 8,
                                        bytesPerRow: 160, space: ImageCodec.colorSpace, bitmapInfo: ImageCodec.bitmapInfo))
    let portrait = dir.appendingPathComponent("portrait.png")
    try ImageCodec.convert(image: #require(context.makeImage()), settings: png).data.write(to: portrait)
    let model = AppModel()
    model.add([landscape, portrait])
    try await waitForPreview(model)
    model.editDimension("60", width: false)
    try await waitForPreview(model)
    #expect(model.settings.width == "120")
    model.selectedID = model.items[1].id
    try await waitForPreview(model)
    #expect(model.settings.height == "60" && model.settings.width == "30")
    #expect(model.preview?.decoded.width == 30 && model.preview?.decoded.height == 60)
}
