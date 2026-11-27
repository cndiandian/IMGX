import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AppKit
@testable import IMGX

func animationFixture(plays: Int = 3) throws -> ImageAnimation {
    var frames: [AnimationFrame] = []
    for (index, delay) in [70, 230, 110].enumerated() {
        let context = try #require(CGContext(data: nil, width: 80, height: 40, bitsPerComponent: 8,
                                            bytesPerRow: 320, space: ImageCodec.colorSpace, bitmapInfo: ImageCodec.bitmapInfo))
        context.setFillColor(index == 0 ? CGColor(red: 1, green: 0, blue: 0, alpha: 1)
                             : index == 1 ? CGColor(red: 0, green: 1, blue: 0, alpha: 1)
                             : CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: index * 15, y: 0, width: 30, height: 40))
        frames.append(AnimationFrame(image: try #require(context.makeImage()), milliseconds: delay))
    }
    return ImageAnimation(frames: frames, playCount: plays, format: .gif)
}

@Test func gifAndAnimatedWebPPreserveFramesTimingLoopsAndSizing() throws {
    let source = try animationFixture()
    for format in [OutputFormat.gif, .webp] {
        for plays in [0, 1, 3] {
            var settings = ConversionSettings()
            settings.format = format
            settings.lossless = true
            settings.size = .half
            let animation = ImageAnimation(frames: source.frames, playCount: plays, format: .gif)
            let data = try AnimationCodec.encode(animation, settings: settings)
            let decoded = try #require(try AnimationCodec.decode(data))
            #expect(decoded.frames.count == 3)
            #expect(decoded.playCount == plays, "format=\(format)")
            #expect(decoded.frames.map(\.milliseconds) == [70, 230, 110])
            for frame in decoded.frames { #expect(frame.image.width == 40 && frame.image.height == 20) }
            // 后续帧必须清理前一帧，不能因透明度/处置方式而留下红色残影。
            #expect(try rgba(decoded.frames[1].image, x: 3, y: 10)[3] == 0)
            #expect(try rgba(decoded.frames[0].image, x: 3, y: 10)[0] > 240)
            #expect(try rgba(decoded.frames[2].image, x: 20, y: 10)[2] > 240)
        }
    }
}

@Test func animationFlatteningAndPlaybackUseCorrectFrames() throws {
    let animation = try animationFixture()
    let sequence = ImageSequence(first: animation.frames[0].image, animation: animation)
    for format in [OutputFormat.png, .jpeg] {
        var settings = ConversionSettings()
        settings.format = format
        let result = try ImageCodec.convert(sequence: sequence, settings: settings)
        #expect(result.originalAnimation != nil && result.outputAnimation == nil)
        #expect(try rgba(result.decoded, x: 5, y: 20)[0] > 240)
    }
    #expect(animation.image(at: 0) === animation.frames[0].image)
    #expect(animation.image(at: 0.08) === animation.frames[1].image)
    #expect(animation.image(at: 0.32) === animation.frames[2].image)
    #expect(animation.image(at: 100) === animation.frames[2].image)
    let infinite = try animationFixture(plays: 0)
    #expect(infinite.image(at: 0.42) === infinite.frames[0].image)
    #expect(throws: AnimationError.tooLarge) { try AnimationCodec.validate(width: 1000, height: 1000, count: 33) }
    #expect(throws: AnimationError.tooLarge) { try AnimationCodec.validate(width: 1, height: 1, count: 501) }
}

@MainActor @Test func animatedFolderExportMatchesPreviewAndNeverOverwritesSource() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let nested = root.appendingPathComponent("Album/Subfolder", isDirectory: true)
    let output = root.appendingPathComponent("Output", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var settings = ConversionSettings()
    settings.format = .gif
    let original = try AnimationCodec.encode(animationFixture(), settings: settings)
    let file = nested.appendingPathComponent("Motion.GIF")
    try original.write(to: file)
    let model = AppModel()
    await model.add([root.appendingPathComponent("Album")])
    #expect(model.items.count == 1)
    for format in [OutputFormat.webp, .gif] {
        model.settings.format = format
        model.settings.size = .half
        model.settings.lossless = true
        try await waitForPreview(model)
        let preview = try #require(model.preview)
        #expect(preview.originalAnimation?.frames.count == 3)
        #expect(preview.outputAnimation?.frames.count == 3)
        await model.export(to: output)
        let exported = output.appendingPathComponent("Album/Subfolder/Motion.\(format.fileExtension)")
        #expect(try Data(contentsOf: exported) == preview.data)
        await model.export(to: output)
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("Album/Subfolder/Motion-1.\(format.fileExtension)").path))
    }
    #expect(try Data(contentsOf: file) == original)
    #expect(Thumbnail.load(url: file) != nil)
}

@MainActor @Test func animatedClipboardCopyAndPasteRetainNativeFrames() async throws {
    let board = NSPasteboard(name: .init("IMGX-GIF-Test-" + UUID().uuidString))
    defer { board.releaseGlobally() }
    let store = ClipboardImageStore()
    defer { store.discardAll() }
    for format in [OutputFormat.gif, .webp] {
        var settings = ConversionSettings()
        settings.format = format
        let animation = try animationFixture()
        let preview = try ImageCodec.convert(sequence: ImageSequence(first: animation.frames[0].image, animation: animation), settings: settings)
        let result = try await ImageProcessor.shared.clipboardResult(preview, format: format)
        #expect(ClipboardExport.write(result, to: board))
        let providers = ClipboardImport.providers(from: board)
        let read = try await ClipboardImport.read(providers)
        #expect(read.images == [preview.data])
        let prepared = try await ImageProcessor.shared.prepareClipboard(read.images, store: store, name: "Clipboard")
        #expect(prepared.unreadable == 0)
        let file = try #require(prepared.urls.first)
        let loaded = try ImageCodec.loadSequence(url: file)
        #expect(loaded.animation?.frames.count == 3)
        #expect(loaded.animation?.playCount == 3)
    }
}
