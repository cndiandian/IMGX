import AppKit
import Foundation
import Observation

@MainActor @Observable
final class AppUpdateModel {
    enum Phase: Equatable {
        case idle, checking, upToDate, downloading(String), opened(String, URL), failed(String)
        var message: String {
            switch self {
            case .idle: ""
            case .checking: L10n.text(.checkingUpdates)
            case .upToDate: L10n.text(.upToDate)
            case .downloading(let version): L10n.text(.downloadingVersion, version)
            case .opened(let version, _): L10n.text(.openedVersion, version)
            case .failed(let message): message
            }
        }
    }
    let version: String
    private(set) var phase: Phase = .idle
    var isBusy: Bool {
        switch phase { case .checking, .downloading: true; default: false }
    }
    private let service: any UpdateServing
    private let openFile: @MainActor (URL) -> Bool
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var operationID = UUID()

    init(version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0",
         service: any UpdateServing = GitHubUpdateService(),
         openFile: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.version = version; self.service = service; self.openFile = openFile
    }

    func check() {
        guard !isBusy else { return }
        let id = UUID()
        operationID = id
        phase = .checking
        task = Task {
            defer { if operationID == id { task = nil } }
            do {
                guard let current = AppVersion(version) else { throw UpdateError.invalidVersion }
                let update = try await service.latestUpdate(current: current)
                guard operationID == id, !Task.isCancelled else { return }
                guard let update else { phase = .upToDate; return }
                phase = .downloading(update.version)
                let file = try await service.download(update)
                guard operationID == id, !Task.isCancelled else { return }
                guard openFile(file) else { throw UpdateError.cannotOpen }
                phase = .opened(update.version, file)
            } catch {
                guard operationID == id else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        operationID = UUID()
        task?.cancel()
        task = nil
        phase = .idle
    }
}
