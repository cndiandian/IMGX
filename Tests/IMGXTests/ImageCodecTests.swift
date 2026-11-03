import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import IMGX

func fixture() throws -> CGImage {
    let context = try #require(CGContext(data: nil, width: 80, height: 40, bitsPerComponent: 8,
                                        bytesPerRow: 320, space: ImageCodec.colorSpace,
                                        bitmapInfo: ImageCodec.bitmapInfo))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5))
    context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
    return try #require(context.makeImage())
}

func rgba(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
    let context = try #require(CGContext(data: nil, width: image.width, height: image.height,
                                        bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                        space: ImageCodec.colorSpace, bitmapInfo: ImageCodec.bitmapInfo))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    let offset = (y * image.width + x) * 4
    return (0..<4).map { bytes[offset + $0] }
}

@Test func formatsHaveRealSignaturesAndDecode() throws {
    for format in OutputFormat.allCases {
        var settings = ConversionSettings()
        settings.format = format
        let result = try ImageCodec.convert(image: fixture(), settings: settings)
        #expect(result.decoded.width == 80)
        #expect(result.decoded.height == 40)
        switch format {
        case .webp:
            #expect(String(data: result.data.prefix(4), encoding: .ascii) == "RIFF")
            #expect(String(data: result.data[8..<12], encoding: .ascii) == "WEBP")
        case .jpeg: #expect(Array(result.data.prefix(3)) == [0xff, 0xd8, 0xff])
        case .png: #expect(Array(result.data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
        }
    }
    #expect(OutputFormat.jpeg.fileExtension == "jpg")
}

@Test func alphaAndWhiteMatte() throws {
    for format in [OutputFormat.png, .webp, .jpeg] {
        var settings = ConversionSettings()
        settings.format = format
        settings.lossless = true
        let image = try ImageCodec.convert(image: fixture(), settings: settings).decoded
        let clear = try rgba(image, x: 60, y: 20)
        let red = try rgba(image, x: 20, y: 20)
        if format == .jpeg {
            #expect(clear.allSatisfy { $0 >= 250 })
            #expect(red[0] > 245 && red[1] > 110 && red[2] > 110 && red[3] == 255)
        } else {
            #expect(clear[3] == 0)
            #expect((125...130).contains(Int(red[3])))
            #expect(abs(Int(red[0]) - Int(red[3])) <= 1)
        }
    }
}

@Test func dimensionsRespectEachSourceAndLimits() throws {
    var settings = ConversionSettings()
    settings.size = .half
    let half = try settings.outputSize(width: 80, height: 40)
    #expect(half.0 == 40 && half.1 == 20)
    settings.size = .quarter
    #expect(try settings.outputSize(width: 80, height: 40).0 == 20)
    settings.size = .custom
    settings.width = "100"
    settings.height = "100"
    let landscape = try settings.outputSize(width: 80, height: 40)
    let portrait = try settings.outputSize(width: 40, height: 80)
    #expect(landscape.0 == 100 && landscape.1 == 50)
    #expect(portrait.0 == 50 && portrait.1 == 100)
    for bad in ["0", "-1", "1.5", "16384", "abc", "999999999999999999999"] {
        settings.width = bad
        #expect(throws: (any Error).self) { try settings.outputSize(width: 80, height: 40) }
    }
    settings.width = ""
    settings.height = ""
    #expect(try settings.outputSize(width: 80, height: 40).0 == 80)
    #expect(throws: (any Error).self) { try settings.outputSize(width: 16384, height: 40) }
    #expect(throws: (any Error).self) { try settings.outputSize(width: 11000, height: 11000) }
}

@Test func diskInputsAndCorruptFile() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    for type in [UTType.png, .jpeg, .heic] {
        let buffer = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(buffer, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try fixture(), nil)
        #expect(CGImageDestinationFinalize(dest))
        let url = directory.appendingPathComponent("input.\(type.preferredFilenameExtension!)")
        try (buffer as Data).write(to: url)
        #expect(try ImageCodec.convert(url: url, settings: ConversionSettings()).decoded.width == 80)
    }
    let webp = try ImageCodec.convert(image: fixture(), settings: ConversionSettings()).data
    let url = directory.appendingPathComponent("input.webp")
    try webp.write(to: url)
    #expect(try ImageCodec.convert(url: url, settings: ConversionSettings()).decoded.height == 40)
    #expect(throws: (any Error).self) { try ImageCodec.decode(Data("broken".utf8)) }
}
