import AppKit
import Combine
import NXLibraryCore

/// NX Library's own updates: the check against GitHub, the download, the checks of `AppUpdate`,
/// the swap and the relaunch. Hidden entirely while `AppUpdate.repository()` is nil.
@MainActor
final class AppUpdater: ObservableObject {
    enum State: Equatable {
        case hidden
        /// Not a release copy: updates are off.
        case developer
        /// A release copy that cannot be replaced where it is.
        case readOnly
        case idle
        case checking
        case upToDate
        case available(AppUpdate.Release)
        case downloading(Double)
        case verifying
        case installing
        case failed(String)
    }

    @Published private(set) var state: State
    /// The release the launch dialog offers; nil when no dialog is up.
    @Published var offer: AppUpdate.Release?
    @Published var offerFocus: SeleneConfirmButton = .confirm
    /// Why an update must wait ("After the porting"); nil when it may run. Set by the shell.
    var blockedReason: () -> String? = { nil }
    /// Held across replacement and relaunch so new save operations cannot enter between the checks.
    var acquireInstallLease: () -> (() -> Void)? = { nil }

    private let repository: String?
    private let runningVersion: String
    private let defaults = UserDefaults.standard
    private var downloadSession: URLSession?
    private var lastRelease: AppUpdate.Release?

    private enum Keys {
        static let lastCheck = "NXLibrary_UpdateLastCheck"
        static let laterVersion = "NXLibrary_UpdateLaterVersion"
        static let laterAt = "NXLibrary_UpdateLaterAt"
    }

    init() {
        repository = AppUpdate.repository()
        runningVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        if repository == nil {
            state = .hidden
        } else {
            switch AppUpdate.installability(Bundle.main.bundleURL) {
            case .developer: state = .developer
            case .readOnly: state = .readOnly
            case .ok: state = .idle
            }
        }
    }

    var currentVersion: String { runningVersion }

    /// The release's page on GitHub, for its notes in full.
    var releasePageURL: URL? {
        guard let repository, let release else { return nil }
        return URL(string: "https://github.com/\(repository)/releases/tag/\(release.tag)")
    }

    /// The release the About row and the dialog act on.
    var release: AppUpdate.Release? {
        if case .available(let release) = state { return release }
        return offer ?? lastRelease
    }

    func checkAtLaunch(enabled: Bool) {
        guard enabled, state == .idle,
              AppUpdate.shouldCheck(lastCheck: defaults.object(forKey: Keys.lastCheck) as? Date, now: Date())
        else { return }
        check(offering: true)
    }

    func checkNow() {
        switch state {
        case .idle, .upToDate, .available, .failed: check(offering: false)
        default: break
        }
    }

    private func check(offering: Bool) {
        guard let repository,
              let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else { return }
        state = .checking
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 404 {
                    defaults.set(Date(), forKey: Keys.lastCheck)
                    lastRelease = nil; offer = nil; state = .upToDate; return
                }
                guard status == 200 else { state = .failed("GitHub answered \(status); try again later."); return }
                guard let release = AppUpdate.parseRelease(data, repository: repository) else {
                    state = .failed("The update could not be verified. Try again later.")
                    return
                }
                defaults.set(Date(), forKey: Keys.lastCheck)
                guard AppUpdate.isNewer(release.version, than: runningVersion) else {
                    lastRelease = nil; offer = nil; state = .upToDate; return
                }
                lastRelease = release
                state = .available(release)
                let laterVersion = defaults.string(forKey: Keys.laterVersion)
                let laterAt = defaults.object(forKey: Keys.laterAt) as? Date
                if offering, AppUpdate.shouldOffer(release.version, laterVersion: laterVersion, laterAt: laterAt, now: Date()) {
                    offerFocus = .confirm
                    offer = release
                }
            } catch {
                state = .failed("Could not reach GitHub.")
            }
        }
    }

    /// Hides the dialog for this version for a day; About still offers it.
    func later() {
        if let offer {
            defaults.set(offer.version, forKey: Keys.laterVersion)
            defaults.set(Date(), forKey: Keys.laterAt)
        }
        offer = nil
    }

    func update() {
        guard let release, blockedReason() == nil else { return }
        offer = nil
        switch state {
        case .available, .failed: break
        default: return
        }
        state = .downloading(0)
        let folder = Self.workFolder()
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let policy = AppUpdateDownload(expectedBytes: release.archiveBytes, progress: { [weak self] fraction in
            Task { @MainActor in
                guard let self, case .downloading = self.state else { return }
                self.state = .downloading(fraction)
            }
        }) { [weak self] location, response, error in
            let zip = folder.appendingPathComponent("NXLibrary-\(release.version).zip")
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            var moved = false
            if let location, error == nil, status == 200 {
                moved = (try? FileManager.default.moveItem(at: location, to: zip)) != nil
            }
            Task { @MainActor in
                guard let self else { return }
                self.downloadSession = nil
                guard moved else { return self.fail("The download did not finish; nothing was changed.") }
                self.verifyAndInstall(zip: zip, release: release, folder: folder)
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 15 * 60
        let session = URLSession(configuration: configuration, delegate: policy, delegateQueue: nil)
        downloadSession = session
        let task = session.downloadTask(with: release.zipURL)
        task.resume()
    }

    private func verifyAndInstall(zip: URL, release: AppUpdate.Release, folder: URL) {
        state = .verifying
        let expectedID = Bundle.main.bundleIdentifier ?? "local.nxlibrary"
        let runningOS = ProcessInfo.processInfo.operatingSystemVersion
        Task {
            let prepared = await Task.detached(priority: .userInitiated) {
                Self.prepare(zip: zip, release: release, folder: folder, expectedID: expectedID, runningOS: runningOS)
            }.value
            switch prepared {
            case .failure(let error): fail(error.message)
            case .success(let staged): install(staged: staged, folder: folder, release: release)
            }
        }
    }

    private struct PreparationError: Error {
        let message: String
    }

    nonisolated private static func prepare(zip: URL, release: AppUpdate.Release, folder: URL,
                                           expectedID: String, runningOS: OperatingSystemVersion) -> Result<URL, PreparationError> {
        guard AppUpdate.checkDigest(zip, expected: release.digest) == .match else {
            return .failure(.init(message: "The download did not match the release; nothing was changed."))
        }
        let unpacked = folder.appendingPathComponent("unpacked")
        guard let resources = Bundle.main.resourceURL,
              let runtime = BundledRuntime.locate(resourceURL: resources),
              run(runtime.python.path, ["-I", "-B", resources.appendingPathComponent("validate_update.py").path,
                                        zip.path, unpacked.path]) else {
            return .failure(.init(message: "The update archive could not be verified; nothing was changed."))
        }
        let staged = unpacked.appendingPathComponent("NXLibrary.app")
        if let problem = AppUpdate.bundleProblem(staged, expectedID: expectedID, version: release.version, runningOS: runningOS) {
            if case .needsNewerMacOS(let minimum) = problem {
                return .failure(.init(message: "NX Library \(release.version) needs macOS \(minimum) or later; nothing was changed."))
            }
            return .failure(.init(message: "The download is not a valid NX Library \(release.version); nothing was changed."))
        }
        guard AppUpdate.validCodeSignature(staged) else {
            return .failure(.init(message: "The app signature could not be verified; nothing was changed."))
        }
        return .success(staged)
    }

    private func install(staged: URL, folder: URL, release: AppUpdate.Release) {
        if let reason = blockedReason() { return fail("\(reason); nothing was changed.") }
        guard let releaseLease = acquireInstallLease() else {
            return fail("An operation is still running. Try the update again when it finishes.")
        }
        state = .installing
        let current = Bundle.main.bundleURL
        Task.detached(priority: .userInitiated) {
            let result = Result { try AppUpdate.install(staged, over: current) }
            await MainActor.run {
                defer { releaseLease() }
                try? FileManager.default.removeItem(at: folder)
                switch result {
                case .success(let placed):
                    if AppUpdate.relaunch(placed) {
                        NSApp.terminate(nil)
                    } else {
                        self.state = .failed("NX Library \(release.version) is installed; open it again to finish.")
                    }
                case .failure:
                    self.fail("NX Library could not be replaced; the current version is unchanged.")
                }
            }
        }
    }

    private func fail(_ message: String) {
        try? FileManager.default.removeItem(at: Self.workFolder())
        state = .failed(message)
    }

    private static func workFolder() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NXLibrary/Temp/Update")
    }

    nonisolated private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
