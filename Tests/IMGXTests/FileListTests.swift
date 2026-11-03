import Testing
import Foundation
@testable import IMGX

@MainActor @Test func importDeduplicatesAndRemovesWithoutDeleting() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let urls = ["first.png", "second.JPG", "third.webp"].map { directory.appendingPathComponent($0) }
    for url in urls { try Data("broken image".utf8).write(to: url) }
    let model = AppModel()
    model.add(urls + [urls[0], directory.appendingPathComponent("unsupported.txt")])
    #expect(model.items.count == 3)
    #expect(model.selected?.url == urls[0])
    #expect(model.toast?.text.contains("1 个") == true)
    model.selectedID = model.items[1].id
    model.removeSelected()
    #expect(model.selected?.url == urls[2])
    model.removeSelected()
    #expect(model.selected?.url == urls[0])
    model.isExporting = true
    model.clear()
    model.removeSelected()
    model.add([directory.appendingPathComponent("extra.png")])
    #expect(model.items.count == 1)
    model.isExporting = false
    model.clear()
    #expect(model.items.isEmpty && model.selectedID == nil)
    for url in urls { #expect(FileManager.default.fileExists(atPath: url.path)) }
}
