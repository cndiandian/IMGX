import Foundation
import Testing
@testable import IMGX

private let updateChecksum = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
private let updateFile = URL(fileURLWithPath: "/tmp/IMGX-v0.2.0.dmg")
private let candidate = AppUpdate(version: "0.2.0", filename: "IMGX-v0.2.0.dmg",
                                  url: URL(string: "https://github.com/cndiandian/IMGX/releases/download/v0.2.0/IMGX-v0.2.0.dmg")!,
                                  checksum: updateChecksum, size: 3)

private func releaseData(tag: String = "v0.2.0", draft: Bool = false, prerelease: Bool = false,
                         url: String = candidate.url.absoluteString, digest: String? = "sha256:" + updateChecksum) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "tag_name": tag, "draft": draft, "prerelease": prerelease,
        "assets": [["name": "IMGX-v0.2.0.dmg", "browser_download_url": url,
                    "digest": digest as Any? ?? NSNull(), "size": 3]]
    ])
}

@Test func updateVersionsCompareNumerically() throws {
    #expect(try #require(AppVersion("0.10.0")) > #require(AppVersion("0.9.9")))
    #expect(try #require(AppVersion("1.0.0")) > #require(AppVersion("0.99.99")))
    for value in ["1.0", "1.0.0-beta", "1.-1.0", "1..0", "１.0.0", "v1.0.0"] {
        #expect(AppVersion(value) == nil)
    }
}

@Test func updatesOnlyAcceptNewerStableReleasesFromThisRepository() throws {
    let current = try #require(AppVersion("0.1.0"))
    let remote = try GitHubUpdateService.update(from: releaseData(), current: current)
    let update = try #require(remote)
    #expect(update.version == "0.2.0" && update.checksum == updateChecksum)
    #expect(try GitHubUpdateService.update(from: releaseData(), current: #require(AppVersion("0.2.0"))) == nil)
    #expect(try GitHubUpdateService.update(from: releaseData(), current: #require(AppVersion("0.3.0"))) == nil)
    #expect(try GitHubUpdateService.update(from: releaseData(draft: true), current: current) == nil)
    #expect(try GitHubUpdateService.update(from: releaseData(prerelease: true), current: current) == nil)
    for url in ["https://example.com/IMGX.dmg", "https://github.com/other/IMGX/releases/download/v0.2.0/IMGX-v0.2.0.dmg"] {
        #expect(throws: UpdateError.missingDMG) {
            try GitHubUpdateService.update(from: releaseData(url: url), current: current)
        }
    }
    #expect(throws: UpdateError.missingDMG) {
        try GitHubUpdateService.update(from: releaseData(digest: nil), current: current)
    }
}

@Test func downloadedUpdatesRequireCorrectSizeAndSHA256() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    try Data("abc".utf8).write(to: file)
    try GitHubUpdateService.verifyDownload(at: file, update: candidate)
    try Data("abd".utf8).write(to: file)
    #expect(throws: UpdateError.checksumMismatch) {
        try GitHubUpdateService.verifyDownload(at: file, update: candidate)
    }
    try Data("a".utf8).write(to: file)
    #expect(throws: UpdateError.invalidDownload) {
        try GitHubUpdateService.verifyDownload(at: file, update: candidate)
    }
}

@Test func publicReleaseFallbackValidatesRepositoryVersionAndChecksumFile() throws {
    let url = URL(string: "https://github.com/cndiandian/IMGX/releases/tag/v0.2.0")
    #expect(try GitHubUpdateService.versionFromReleasePage(url) == "0.2.0")
    for badURL in ["https://example.com/releases/tag/v0.2.0",
                   "https://github.com/other/IMGX/releases/tag/v0.2.0",
                   "https://github.com/cndiandian/IMGX/releases/tag/v0.2.0-beta"] {
        #expect(throws: UpdateError.invalidRelease) {
            try GitHubUpdateService.versionFromReleasePage(URL(string: badURL))
        }
    }
    let update = try GitHubUpdateService.update(version: "0.2.0", checksumData: Data("\(updateChecksum)  IMGX-v0.2.0.dmg\n".utf8))
    #expect(update.checksum == updateChecksum && update.size == nil)
    for checksum in ["\(updateChecksum)  other.dmg", "bad  IMGX-v0.2.0.dmg", "\(updateChecksum)  IMGX-v0.2.0.dmg\nextra line"] {
        #expect(throws: UpdateError.invalidDownload) {
            try GitHubUpdateService.update(version: "0.2.0", checksumData: Data(checksum.utf8))
        }
    }
}

private struct StubUpdates: UpdateServing {
    var update: AppUpdate? = candidate
    var failDownload = false
    var delayed = false
    func latestUpdate(current: AppVersion) async throws -> AppUpdate? {
        if delayed { try? await Task.sleep(for: .milliseconds(50)) }
        return update
    }
    func download(_ update: AppUpdate) async throws -> URL {
        if failDownload { throw UpdateError.checksumMismatch }
        return updateFile
    }
}

@MainActor private func waitForUpdate(_ model: AppUpdateModel) async throws {
    for _ in 0..<100 {
        if !model.isBusy { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("更新状态未能结束")
}

@MainActor @Test func checkingDownloadsAndOpensNewVersionOnly() async throws {
    var opened: [URL] = []
    let model = AppUpdateModel(version: "0.1.0", service: StubUpdates(), openFile: { opened.append($0); return true })
    model.check()
    model.check() // 重复点击不启动第二个操作。
    try await waitForUpdate(model)
    #expect(opened == [updateFile])
    #expect(model.phase == .opened("0.2.0", updateFile))

    let latest = AppUpdateModel(version: "0.1.0", service: StubUpdates(update: nil), openFile: { opened.append($0); return true })
    latest.check()
    try await waitForUpdate(latest)
    #expect(latest.phase == .upToDate)
    #expect(opened == [updateFile])
}

@MainActor @Test func failedVerificationAndCancellationNeverOpenDMG() async throws {
    var opened = false
    let failed = AppUpdateModel(version: "0.1.0", service: StubUpdates(failDownload: true), openFile: { _ in opened = true; return true })
    failed.check()
    try await waitForUpdate(failed)
    #expect(failed.phase == .failed(UpdateError.checksumMismatch.localizedDescription))
    #expect(!opened)
    let cancelled = AppUpdateModel(version: "0.1.0", service: StubUpdates(delayed: true), openFile: { _ in opened = true; return true })
    cancelled.check()
    await Task.yield()
    cancelled.cancel()
    try await Task.sleep(for: .milliseconds(80))
    #expect(cancelled.phase == .idle)
    #expect(!opened)
}
