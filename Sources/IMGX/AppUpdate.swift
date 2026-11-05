import CryptoKit
import Foundation

struct AppVersion: Comparable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: String) {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]) else { return nil }
        self.major = major; self.minor = minor; self.patch = patch
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

struct AppUpdate: Sendable {
    let version: String
    let filename: String
    let url: URL
    let checksum: String
    let size: Int64?
}

enum UpdateError: LocalizedError, Equatable {
    case invalidVersion, invalidRelease, missingDMG, invalidDownload, checksumMismatch, http(Int), cannotOpen
    var errorDescription: String? {
        switch self {
        case .invalidVersion: L10n.text(.invalidVersion)
        case .invalidRelease: L10n.text(.invalidRelease)
        case .missingDMG: L10n.text(.missingDMG)
        case .invalidDownload: L10n.text(.invalidDownload)
        case .checksumMismatch: L10n.text(.checksumMismatch)
        case .http(403), .http(429): L10n.text(.rateLimited)
        case .http(404): L10n.text(.noRelease)
        case .http(let code): L10n.text(.httpFailure, String(code))
        case .cannotOpen: L10n.text(.cannotOpenDMG)
        }
    }
}

private struct GitHubRelease: Decodable {
    let tag: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    enum CodingKeys: String, CodingKey { case tag = "tag_name", draft, prerelease, assets }
    struct Asset: Decodable {
        let name: String
        let url: URL
        let digest: String?
        let size: Int64
        enum CodingKeys: String, CodingKey { case name, url = "browser_download_url", digest, size }
    }
}

protocol UpdateServing: Sendable {
    func latestUpdate(current: AppVersion) async throws -> AppUpdate?
    func download(_ update: AppUpdate) async throws -> URL
}

actor GitHubUpdateService: UpdateServing {
    static let projectURL = URL(string: "https://github.com/cndiandian/IMGX")!
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        session = URLSession(configuration: configuration)
    }

    func latestUpdate(current: AppVersion) async throws -> AppUpdate? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/cndiandian/IMGX/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("IMGX-UpdateChecker", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse,
           (http.statusCode == 403 && http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0") || http.statusCode == 429 {
            return try await publicLatestUpdate(current: current)
        }
        try Self.validate(response)
        return try Self.update(from: data, current: current)
    }

    private func publicLatestUpdate(current: AppVersion) async throws -> AppUpdate? {
        var request = URLRequest(url: Self.projectURL.appendingPathComponent("releases/latest"))
        request.httpMethod = "HEAD"
        let (_, response) = try await session.data(for: request)
        try Self.validate(response)
        let version = try Self.versionFromReleasePage(response.url)
        guard let remote = AppVersion(version), remote > current else { return nil }
        let filename = "IMGX-v\(version).dmg.sha256"
        let checksumURL = Self.projectURL.appendingPathComponent("releases/download/v\(version)/\(filename)")
        let (data, checksumResponse) = try await session.data(from: checksumURL)
        try Self.validate(checksumResponse)
        return try Self.update(version: version, checksumData: data)
    }

    static func versionFromReleasePage(_ url: URL?) throws -> String {
        guard let url, url.lastPathComponent.hasPrefix("v") else { throw UpdateError.invalidRelease }
        let version = String(url.lastPathComponent.dropFirst())
        guard AppVersion(version) != nil,
              url == URL(string: "https://github.com/cndiandian/IMGX/releases/tag/v\(version)") else {
            throw UpdateError.invalidRelease
        }
        return version
    }

    static func update(version: String, checksumData: Data) throws -> AppUpdate {
        guard AppVersion(version) != nil,
              let text = String(data: checksumData, encoding: .utf8) else { throw UpdateError.invalidRelease }
        let fields = text.split(whereSeparator: \.isWhitespace)
        let filename = "IMGX-v\(version).dmg"
        guard fields.count == 2, fields[1] == Substring(filename), fields[0].count == 64,
              fields[0].allSatisfy({ $0.isASCII && $0.isHexDigit }) else { throw UpdateError.invalidDownload }
        return AppUpdate(version: version, filename: filename,
                         url: URL(string: "https://github.com/cndiandian/IMGX/releases/download/v\(version)/\(filename)")!,
                         checksum: fields[0].lowercased(), size: nil)
    }

    static func update(from data: Data, current: AppVersion) throws -> AppUpdate? {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !release.draft, !release.prerelease else { return nil }
        guard release.tag.hasPrefix("v"), let version = AppVersion(String(release.tag.dropFirst())) else {
            throw UpdateError.invalidRelease
        }
        guard version > current else { return nil }
        let versionText = String(release.tag.dropFirst())
        let filename = "IMGX-v\(versionText).dmg"
        let expectedURL = URL(string: "https://github.com/cndiandian/IMGX/releases/download/\(release.tag)/\(filename)")!
        guard let asset = release.assets.first(where: { $0.name == filename }),
              asset.url == expectedURL, asset.size > 0,
              let digest = asset.digest, digest.hasPrefix("sha256:") else { throw UpdateError.missingDMG }
        let checksum = String(digest.dropFirst(7)).lowercased()
        guard checksum.count == 64, checksum.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw UpdateError.invalidDownload
        }
        return AppUpdate(version: versionText, filename: filename, url: asset.url, checksum: checksum, size: asset.size)
    }

    func download(_ update: AppUpdate) async throws -> URL {
        let (temporaryURL, response) = try await session.download(from: update.url)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try Self.validate(response)
        try Self.verifyDownload(at: temporaryURL, update: update)
        try Task.checkCancellation()
        let downloads = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        // 独立目录防止覆盖已有安装包；校验成功后才移入用户下载目录。
        let directory = downloads.appendingPathComponent("IMGX", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(update.filename)
        do { try FileManager.default.moveItem(at: temporaryURL, to: destination) }
        catch { try? FileManager.default.removeItem(at: directory); throw error }
        return destination
    }

    static func verifyDownload(at url: URL, update: AppUpdate) throws {
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        guard let size, size.int64Value > 0 else { throw UpdateError.invalidDownload }
        if let expectedSize = update.size, size.int64Value != expectedSize { throw UpdateError.invalidDownload }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let chunk = try file.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            hash.update(data: chunk)
        }
        let checksum = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard checksum == update.checksum else { throw UpdateError.checksumMismatch }
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw UpdateError.invalidDownload }
        guard http.statusCode == 200 else { throw UpdateError.http(http.statusCode) }
    }
}
