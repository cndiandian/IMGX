import Foundation

struct ExportedFile: Sendable {
    let url: URL
    let byteCount: Int
}

struct ExportRequest: Sendable {
    let id: UUID
    let url: URL
    let accessRoot: URL?
    let relativeDirectory: [String]
    var pageNumber: Int? = nil
}

enum ExportPathError: LocalizedError, Equatable {
    case invalidDirectory
    var errorDescription: String? { L10n.text(.invalidExportPath) }
}

enum ExportWriter {
    /// The exclusive write is the protection; the existence check alone would race.
    static func write(_ data: Data, source: URL, format: OutputFormat, directory: URL,
                      relativeDirectory: [String] = [], pageNumber: Int? = nil) throws -> URL {
        let directory = try destinationDirectory(relativeDirectory, inside: directory)
        let stem = source.deletingPathExtension().lastPathComponent + (pageNumber.map { String(format: "-page-%03d", $0) } ?? "")
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

    private static func destinationDirectory(_ components: [String], inside root: URL) throws -> URL {
        guard root.isFileURL,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") && !$0.contains("\0") }) else {
            throw ExportPathError.invalidDirectory
        }
        var directory = root.standardizedFileURL
        for component in components {
            directory.appendPathComponent(component, isDirectory: true)
            let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isDirectoryKey]
            if let values = try? directory.resourceValues(forKeys: keys) {
                guard values.isSymbolicLink != true, values.isDirectory == true else { throw ExportPathError.invalidDirectory }
            } else {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let values = try directory.resourceValues(forKeys: keys)
                guard values.isSymbolicLink != true, values.isDirectory == true else { throw ExportPathError.invalidDirectory }
            }
        }
        return directory
    }
}

extension ImageProcessor {
    func export(url: URL, settings: ConversionSettings, directory: URL,
                relativeDirectory: [String] = [], accessRoot: URL? = nil, pageNumber: Int? = nil) throws -> ExportedFile {
        try Task.checkCancellation()
        return try autoreleasepool {
            let data = try ImageCodec.encode(url: url, settings: settings, accessRoot: accessRoot, pageNumber: pageNumber)
            try Task.checkCancellation()
            let target = try ExportWriter.write(data, source: url, format: settings.format, directory: directory,
                                                relativeDirectory: relativeDirectory, pageNumber: pageNumber)
            return ExportedFile(url: target, byteCount: data.count)
        }
    }
}
