import Testing
import Foundation
import CoreGraphics
import PDFKit
@testable import IMGX

func pdfFixture(at url: URL, sizes: [CGSize] = [CGSize(width: 120, height: 80), CGSize(width: 80, height: 140)]) throws {
    let consumer = try #require(CGDataConsumer(url: url as CFURL))
    let context = try #require(CGContext(consumer: consumer, mediaBox: nil, nil))
    for (index, size) in sizes.enumerated() {
        var box = CGRect(origin: .zero, size: size)
        let value = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
        context.beginPDFPage([kCGPDFContextMediaBox: value] as CFDictionary)
        context.setFillColor(index == 0 ? CGColor(red: 1, green: 0, blue: 0, alpha: 1) : CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
        context.endPDFPage()
    }
    context.closePDF()
}

@MainActor @Test func pdfPagesPreviewAndExportIndividuallyWithinFolderHierarchy() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let nested = directory.appendingPathComponent("资料/子目录", isDirectory: true)
    let output = directory.appendingPathComponent("output", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let pdf = nested.appendingPathComponent("说明.PDF")
    try pdfFixture(at: pdf)
    let original = try Data(contentsOf: pdf)
    let model = AppModel()
    await model.add([directory.appendingPathComponent("资料"), pdf])
    #expect(model.items.count == 2)
    #expect(model.items.map(\.pageNumber) == [1, 2])
    #expect(model.items.map(\.relativeDirectory) == [["资料", "子目录"], ["资料", "子目录"]])
    #expect(model.items[1].displayName == L10n.text(.pdfPageName, "说明.PDF", "2"))
    model.settings.format = .png
    model.settings.size = .half
    try await waitForPreview(model)
    #expect(model.preview?.original.width == 240)
    #expect(model.preview?.decoded.width == 120)
    let firstPreview = try #require(model.preview?.data)
    model.selectedID = model.items[1].id
    try await waitForPreview(model)
    #expect(model.preview?.original.width == 160)
    #expect(model.preview?.original.height == 280)
    let secondPreview = try #require(model.preview?.data)
    await model.export(to: output)
    #expect(model.completedCount == 2)
    let first = output.appendingPathComponent("资料/子目录/说明-page-001.png")
    let second = output.appendingPathComponent("资料/子目录/说明-page-002.png")
    #expect(try Data(contentsOf: first) == firstPreview)
    #expect(try Data(contentsOf: second) == secondPreview)
    await model.export(to: output)
    #expect(try Data(contentsOf: first) == firstPreview)
    #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("资料/子目录/说明-page-002-1.png").path))
    #expect(try Data(contentsOf: pdf) == original)
    model.removeSelected()
    await model.add([pdf])
    #expect(model.items.count == 2)
    #expect(Set(model.items.compactMap(\.pageNumber)) == [1, 2])
}

@Test func pdfRenderingHonorsCropRotationWhiteBackgroundAndLimits() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let pdf = directory.appendingPathComponent("source.pdf")
    try pdfFixture(at: pdf)
    let image = try PDFRenderer.render(url: pdf, pageNumber: 1)
    #expect(image.width == 240 && image.height == 160)
    let pixels = try #require(image.dataProvider?.data) as Data
    // PDF 的设备色彩会经过系统色彩管理，不要求与 sRGB 数值逐字节相同。
    let redOffset = 20 * image.bytesPerRow + 20 * 4
    #expect(pixels[redOffset] > 240 && pixels[redOffset + 1] < 60 && pixels[redOffset + 2] < 20)
    #expect(pixels[redOffset + 3] == 255)
    #expect(Array(pixels[(80 * image.bytesPerRow + 180 * 4)..<(80 * image.bytesPerRow + 180 * 4 + 4)]) == [255, 255, 255, 255])
    let document = try #require(PDFDocument(url: pdf))
    let page = try #require(document.page(at: 0))
    page.setBounds(CGRect(x: 10, y: 10, width: 60, height: 40), for: .cropBox)
    page.rotation = 90
    let rotated = directory.appendingPathComponent("rotated.pdf")
    #expect(document.write(to: rotated))
    let raster = try PDFRenderer.render(url: rotated, pageNumber: 1)
    #expect(raster.width == 80 && raster.height == 120)
    let thumbnail = try #require(Thumbnail.load(url: rotated, pageNumber: 1))
    #expect(thumbnail.width == 64 && thumbnail.height == 96)
    #expect(throws: PDFError.invalidPage) { try PDFRenderer.render(url: pdf, pageNumber: 0) }
    #expect(throws: PDFError.invalidPage) { try PDFRenderer.render(url: pdf, pageNumber: 3) }
    let huge = directory.appendingPathComponent("huge.pdf")
    try pdfFixture(at: huge, sizes: [CGSize(width: 10000, height: 10000)])
    #expect(throws: CodecError.imageTooLarge) { try PDFRenderer.render(url: huge, pageNumber: 1) }
}

@MainActor @Test func unreadableAndLockedPDFsDoNotBlockOtherImports() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let good = directory.appendingPathComponent("good.pdf")
    let broken = directory.appendingPathComponent("broken.pdf")
    let locked = directory.appendingPathComponent("locked.pdf")
    try pdfFixture(at: good)
    try Data("not a PDF".utf8).write(to: broken)
    let document = try #require(PDFDocument(url: good))
    #expect(document.write(to: locked, withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "owner"]))
    let model = AppModel()
    await model.add([broken, locked, good])
    #expect(model.items.count == 2)
    #expect(model.toast?.text.contains("broken.pdf") == true)
    #expect(model.toast?.text.contains(L10n.text(.pdfLocked)) == true)
    #expect(throws: PDFError.locked) { try PDFRenderer.render(url: locked, pageNumber: 1) }
    await model.export(to: directory)
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("good-page-001.webp").path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("good-page-002.webp").path))
}
