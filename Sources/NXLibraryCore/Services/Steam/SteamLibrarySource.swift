import Foundation

public struct SteamScanLimits: Sendable {
    public var maximumTextBytes = 8 * 1024 * 1024
    public var maximumLibraries = 64
    public var maximumManifests = 10_000
    public var maximumDirectoriesPerInstall = 256
    public var maximumInstallDepth = 4
    public var maximumDirectoryEntries = 10_000
    public static let standard = Self()
    public init() {}
}

public struct SteamScanIssue: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case unavailableLibrary, invalidIndex, oversizedIndex, invalidManifest, oversizedManifest
        case conflictingIdentity, unsafePath, directoryLimit, unreadableAppMetadata, libraryLimit, manifestLimit
    }
    public let url: URL
    public let appID: UInt32?
    public let reason: Reason
}

public struct SteamLibraryObservation: Equatable, Sendable {
    public let root: URL
    public let isReadable: Bool
    public var isComplete: Bool
}

public struct SteamGameObservation: Equatable, Sendable {
    public enum State: Equatable, Sendable { case nativeReady, requiresReview, unavailable }
    public let appID: UInt32
    public let name: String
    public let installationURL: URL
    public let libraryURL: URL
    public let reportedSizeBytes: Int64?
    public let buildID: String?
    public let nativeApps: [NativeMacApplication]
    public var state: State
}

public struct SteamLibrarySnapshot: Sendable {
    public let libraries: [SteamLibraryObservation]
    public let games: [SteamGameObservation]
    public let issues: [SteamScanIssue]
    /// A partial source must never authorize pruning unseen libraries or games.
    public var isComplete: Bool { issues.isEmpty && libraries.allSatisfy(\.isComplete) }
}

public enum SteamSourceError: Error, Equatable { case sourceChanged }

/// Reads only Steam's declared libraries. No scan starts until explicitly requested;
/// this source owns no persistence, process launch, credentials or user opt-in.
public struct SteamLibrarySource: Sendable {
    private let root: URL
    private let limits: SteamScanLimits
    private let directoryReader: InstallationDirectoryReader
    public init(root: URL, limits: SteamScanLimits = .standard) {
        self.init(root: root, limits: limits, directoryReader: { url, budget, cancelled in
            try InstallationDirectorySnapshot.read(at: url, maximumEntries: budget, cancelled: cancelled)
        })
    }

    init(root: URL, limits: SteamScanLimits = .standard, directoryReader: @escaping InstallationDirectoryReader) {
        self.root = root
        self.limits = limits
        self.directoryReader = directoryReader
    }

    public func scan(cancelled: @escaping () -> Bool = { false }) throws -> SteamLibrarySnapshot {
        var scan = Scan(root: root, limits: limits, cancelled: cancelled, directoryReader: directoryReader)
        do { return try scan.run() }
        catch InstallationFileReadError.sourceChanged { throw SteamSourceError.sourceChanged }
    }
}

private struct Scan {
    let root: URL
    let limits: SteamScanLimits
    let cancelled: () -> Bool
    let directoryReader: InstallationDirectoryReader
    private let fm = FileManager.default
    private var observations: [InstallationFileObservation] = []
    private var issues: [SteamScanIssue] = []
    private var games: [SteamGameObservation] = []

    init(root: URL, limits: SteamScanLimits, cancelled: @escaping () -> Bool, directoryReader: @escaping InstallationDirectoryReader) {
        self.root = root.resolvingSymlinksInPath().standardizedFileURL
        self.limits = limits
        self.cancelled = cancelled
        self.directoryReader = directoryReader
    }

    mutating func run() throws -> SteamLibrarySnapshot {
        try checkCancellation()
        let paths = try libraryPaths()
        var libraries: [SteamLibraryObservation] = []
        var manifestsSeen = 0
        for library in paths {
            try checkCancellation()
            let before = issues.count
            let steamapps = library.appendingPathComponent("steamapps").resolvingSymlinksInPath().standardizedFileURL
            guard NativeMacApplication.isWithin(steamapps, root: library) else {
                issue(.unsafePath, at: steamapps)
                libraries.append(.init(root: library, isReadable: false, isComplete: false))
                continue
            }
            let files: [URL]
            do { files = try readDirectory(steamapps) }
            catch is CancellationError { throw CancellationError() }
            catch InstallationFileReadError.sourceChanged { throw InstallationFileReadError.sourceChanged }
            catch {
                issue(.unavailableLibrary, at: library)
                libraries.append(.init(root: library, isReadable: false, isComplete: false))
                continue
            }
            let manifests = files.filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }
                .sorted { $0.path < $1.path }
            for file in manifests {
                try checkCancellation()
                guard manifestsSeen < max(0, limits.maximumManifests) else {
                    issue(.manifestLimit, at: library)
                    break
                }
                manifestsSeen += 1
                try readManifest(file, library: library)
            }
            libraries.append(.init(root: library, isReadable: true, isComplete: issues.count == before))
        }
        let conflicting = Dictionary(grouping: games.indices, by: { games[$0].appID }).values.filter { $0.count > 1 }
        for indices in conflicting {
            for index in indices {
                games[index].state = .requiresReview
                issue(.conflictingIdentity, at: games[index].installationURL, appID: games[index].appID)
                if let library = libraries.firstIndex(where: { $0.root.path == games[index].libraryURL.path }) {
                    libraries[library].isComplete = false
                }
            }
        }
        // Errors reading the index may hide entire libraries, so source-level completeness matters too.
        if issues.contains(where: { [.invalidIndex, .oversizedIndex, .libraryLimit].contains($0.reason) }) {
            for index in libraries.indices { libraries[index].isComplete = false }
        }
        for observation in observations { try checkCancellation(); try observation.verifyUnchanged() }
        games.sort { $0.appID == $1.appID ? $0.libraryURL.path < $1.libraryURL.path : $0.appID < $1.appID }
        return SteamLibrarySnapshot(libraries: libraries, games: games, issues: issues)
    }

    private mutating func libraryPaths() throws -> [URL] {
        var paths = [root]
        let steamapps = root.appendingPathComponent("steamapps").resolvingSymlinksInPath().standardizedFileURL
        guard NativeMacApplication.isWithin(steamapps, root: root) else {
            issue(.unsafePath, at: steamapps)
            return paths
        }
        let index = root.appendingPathComponent("steamapps/libraryfolders.vdf")
        if fm.fileExists(atPath: index.path) {
            do {
                let document = try readDocument(index)
                guard case .object(let entries)? = try document.uniqueValue(for: "libraryfolders") else { throw KeyValuesError.malformed }
                for entry in entries where Self.numeric(entry.key) != nil || entry.key == "0" {
                    let path: String
                    switch entry.value {
                    case .string(let value): path = value
                    case .object(let children):
                        guard case .string(let value)? = try children.uniqueValue(for: "path") else { throw KeyValuesError.malformed }
                        path = value
                    }
                    guard path.hasPrefix("/"), !path.contains("\0") else { issue(.unsafePath, at: index); continue }
                    let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
                    if !paths.contains(where: { $0.path == url.path }) {
                        guard paths.count < max(1, limits.maximumLibraries) else { issue(.libraryLimit, at: index); continue }
                        paths.append(url)
                    }
                }
            } catch InstallationFileReadError.sourceChanged { throw InstallationFileReadError.sourceChanged }
            catch InstallationFileReadError.tooLarge { issue(.oversizedIndex, at: index) }
            catch { issue(.invalidIndex, at: index) }
        } else {
            do { observations.append(try InstallationFileObservation.absent(at: index)) }
            catch InstallationFileReadError.sourceChanged { throw InstallationFileReadError.sourceChanged }
            catch { issue(.invalidIndex, at: index) }
        }
        return paths
    }

    private mutating func readManifest(_ file: URL, library: URL) throws {
        let stem = file.deletingPathExtension().lastPathComponent
        let filenameID = Self.numeric(String(stem.dropFirst("appmanifest_".count)))
        do {
            guard let filenameID else { throw KeyValuesError.malformed }
            let document = try readDocument(file)
            guard case .object(let fields)? = try document.uniqueValue(for: "AppState"),
                  let idText = try Self.string("appid", in: fields), let id = Self.numeric(idText) else { throw KeyValuesError.malformed }
            guard id == filenameID else { issue(.conflictingIdentity, at: file, appID: filenameID); return }
            guard let name = try Self.string("name", in: fields), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let directory = try Self.string("installdir", in: fields), !directory.isEmpty else { throw KeyValuesError.malformed }
            let components = directory.split(separator: "/", omittingEmptySubsequences: false)
            guard !directory.hasPrefix("/"), !directory.contains("\\"), !directory.contains("\0"),
                  !components.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) else {
                issue(.unsafePath, at: file, appID: id); return
            }
            let common = library.appendingPathComponent("steamapps/common").resolvingSymlinksInPath().standardizedFileURL
            let install = common.appendingPathComponent(directory).resolvingSymlinksInPath().standardizedFileURL
            guard NativeMacApplication.isWithin(common, root: library), NativeMacApplication.isWithin(install, root: common), install.path != common.path else {
                issue(.unsafePath, at: file, appID: id); return
            }
            let before = issues.count
            let apps = try nativeApps(in: install, appID: id)
            let mainApps = apps.filter(\.isDeclaredGame)
            let state: SteamGameObservation.State = mainApps.count == 1 && issues.count == before ? .nativeReady
                : (apps.isEmpty && issues.count == before ? .unavailable : .requiresReview)
            let size = try Self.string("SizeOnDisk", in: fields).flatMap(Self.nonnegativeSize)
            let build = try Self.string("buildid", in: fields)
            games.append(.init(appID: id, name: name, installationURL: install, libraryURL: library,
                               reportedSizeBytes: size, buildID: build, nativeApps: apps, state: state))
        } catch is CancellationError { throw CancellationError() }
        catch InstallationFileReadError.sourceChanged { throw InstallationFileReadError.sourceChanged }
        catch InstallationFileReadError.tooLarge { issue(.oversizedManifest, at: file, appID: filenameID) }
        catch { issue(.invalidManifest, at: file, appID: filenameID) }
    }

    private mutating func nativeApps(in install: URL, appID: UInt32) throws -> [NativeMacApplication] {
        guard fm.fileExists(atPath: install.path) else { return [] }
        var level = [install]
        var depth = 0
        var visited = 0
        var apps: [NativeMacApplication] = []
        var seen: Set<String> = []
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        while !level.isEmpty {
            try checkCancellation()
            var nextLevel: [URL] = []
            var truncated = false
            let remaining = max(0, max(1, limits.maximumDirectoriesPerInstall) - visited - level.count)
            for directory in level {
                let files: [URL]
                do { files = try readDirectory(directory, appID: appID) }
                catch is CancellationError { throw CancellationError() }
                catch InstallationFileReadError.sourceChanged { throw InstallationFileReadError.sourceChanged }
                catch { issue(.unreadableAppMetadata, at: directory, appID: appID); continue }
                for file in files.sorted(by: { $0.path < $1.path }) {
                    try checkCancellation()
                    if file.pathExtension.lowercased() == "app" {
                        do {
                            let app = try NativeMacApplication.inspect(at: file, within: install)
                            observations.append(contentsOf: app.fileObservations)
                            if seen.insert(app.url.path).inserted { apps.append(app) }
                        } catch InstallationFileReadError.sourceChanged { throw InstallationFileReadError.sourceChanged }
                        catch { issue(.unreadableAppMetadata, at: file, appID: appID) }
                        continue // Every bundle is a boundary, including an invalid one.
                    }
                    let values: URLResourceValues
                    do { values = try file.resourceValues(forKeys: keys) }
                    catch { issue(.unreadableAppMetadata, at: file, appID: appID); continue }
                    guard values.isDirectory == true, values.isSymbolicLink != true, values.isPackage != true else { continue }
                    if nextLevel.count < remaining { nextLevel.append(file) }
                    else { truncated = true }
                }
            }
            visited += level.count
            // Compare all apps at this depth. Once game candidates exist, deeper
            // loose-data trees do not decide which top-level application is primary.
            if apps.contains(where: \.isDeclaredGame) { return apps }
            if truncated || (!nextLevel.isEmpty && depth >= max(0, limits.maximumInstallDepth)) {
                issue(.directoryLimit, at: level[0], appID: appID)
                return apps
            }
            level = nextLevel
            depth += 1
        }
        return apps
    }

    private mutating func readDocument(_ url: URL) throws -> KeyValuesDocument {
        let snapshot = try InstallationFileSnapshot.read(at: url, maximumBytes: min(max(0, limits.maximumTextBytes), 8 * 1024 * 1024))
        let document = try KeyValuesDocument(text: snapshot.text)
        observations.append(snapshot.observation)
        return document
    }

    private mutating func readDirectory(_ url: URL, appID: UInt32? = nil) throws -> [URL] {
        let snapshot = try directoryReader(url, limits.maximumDirectoryEntries, cancelled)
        observations.append(snapshot.observation)
        if !snapshot.isComplete { issue(.directoryLimit, at: url, appID: appID) }
        return snapshot.entries
    }

    private mutating func issue(_ reason: SteamScanIssue.Reason, at url: URL, appID: UInt32? = nil) {
        issues.append(SteamScanIssue(url: url, appID: appID, reason: reason))
    }

    private func checkCancellation() throws { if cancelled() { throw CancellationError() } }

    private static func numeric(_ text: String) -> UInt32? {
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }), let value = UInt32(text), value > 0 else { return nil }
        return value
    }

    private static func nonnegativeSize(_ text: String) -> Int64? {
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }), let value = Int64(text) else { return nil }
        return value
    }

    private static func string(_ key: String, in fields: [KeyValuesEntry]) throws -> String? {
        guard let value = try fields.uniqueValue(for: key) else { return nil }
        guard case .string(let result) = value else { throw KeyValuesError.malformed }
        return result
    }
}
