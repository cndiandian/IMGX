import Foundation
import UniformTypeIdentifiers

enum ImageFileDrop {
    @MainActor static func fileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL { continuation.resume(returning: url) }
                else if let data = item as? Data { continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil)) }
                else { continuation.resume(returning: nil) }
            }
        }
    }
}

struct ImportedImage: Sendable {
    let url: URL
    let originalBytes: Int64
    let root: URL?
    let subdirectories: [String]
}

struct ImageImportResult: Sendable {
    var images: [ImportedImage] = []
    var skipped = 0
    var unreadable = 0
    var includedFolders = false
}

protocol ImageImportScanning: Sendable {
    func scan(_ urls: [URL]) async throws -> ImageImportResult
}

/// 在后台按目录逐层扫描，跳过隐藏项、软件包及符号链接。
actor ImageImportScanner: ImageImportScanning {
    static let shared = ImageImportScanner()
    private let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
                                            .isPackageKey, .fileSizeKey]

    func scan(_ urls: [URL]) throws -> ImageImportResult {
        var result = ImageImportResult()
        for input in urls {
            try Task.checkCancellation()
            let url = input.standardizedFileURL
            guard url.isFileURL else { result.skipped += 1; continue }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let values = try? url.resourceValues(forKeys: keys) else { result.unreadable += 1; continue }
            guard values.isSymbolicLink != true, values.isPackage != true else { result.skipped += 1; continue }
            if values.isDirectory == true {
                result.includedFolders = true
                try scanFolder(url, into: &result)
            } else {
                append(url, values: values, root: nil, subdirectories: [], into: &result)
            }
        }
        return result
    }

    private func scanFolder(_ root: URL, into result: inout ImageImportResult) throws {
        var pending: [(URL, [String])] = [(root, [])]
        while let (directory, relativeDirectory) = pending.popLast() {
            try Task.checkCancellation()
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
            ) else { result.unreadable += 1; continue }
            var subfolders: [(URL, [String])] = []
            for child in children.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) {
                try Task.checkCancellation()
                guard let values = try? child.resourceValues(forKeys: keys) else { result.unreadable += 1; continue }
                guard values.isSymbolicLink != true, values.isPackage != true else { result.skipped += 1; continue }
                if values.isDirectory == true {
                    subfolders.append((child, relativeDirectory + [child.lastPathComponent]))
                } else {
                    append(child, values: values, root: root, subdirectories: relativeDirectory, into: &result)
                }
            }
            pending.append(contentsOf: subfolders.reversed())
        }
    }

    private func append(_ url: URL, values: URLResourceValues, root: URL?, subdirectories: [String],
                        into result: inout ImageImportResult) {
        guard values.isRegularFile == true, ImageCodec.supportedExtensions.contains(url.pathExtension.lowercased()) else {
            result.skipped += 1
            return
        }
        result.images.append(ImportedImage(url: url.standardizedFileURL, originalBytes: Int64(values.fileSize ?? 0),
                                           root: root, subdirectories: subdirectories))
    }
}
