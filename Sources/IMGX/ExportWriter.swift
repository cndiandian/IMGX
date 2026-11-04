import Foundation

struct ExportedFile: Sendable {
    let url: URL
    let byteCount: Int
}

enum ExportWriter {
    /// The exclusive write is the protection; the existence check alone would race.
    static func write(_ data: Data, source: URL, format: OutputFormat, directory: URL) throws -> URL {
        let stem = source.deletingPathExtension().lastPathComponent
        var index = 0
        while true {
            let suffix = index == 0 ? "" : "-\(index)"
            let candidate = directory.appendingPathComponent("\(stem)\(suffix).\(format.fileExtension)")
            do {
                try data.write(to: candidate, options: .withoutOverwriting)
                return candidate
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                index += 1
            }
        }
    }
}

extension ImageProcessor {
    func export(url: URL, settings: ConversionSettings, directory: URL) throws -> ExportedFile {
        try Task.checkCancellation()
        return try autoreleasepool {
            let data = try ImageCodec.encode(url: url, settings: settings)
            try Task.checkCancellation()
            let target = try ExportWriter.write(data, source: url, format: settings.format, directory: directory)
            return ExportedFile(url: target, byteCount: data.count)
        }
    }
}
