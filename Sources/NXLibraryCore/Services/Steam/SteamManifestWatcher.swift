import Foundation
import CoreServices

/// Tells NX Library when Steam rewrites a manifest (a download starts, pauses or finishes, a game is installed,
/// removed or launched) or the library index, so the Steam source can rescan without a Refresh. One FSEvents
/// stream over the `steamapps` folders of the libraries the last scan read. FSEvents is recursive, so a download's
/// writes under `downloading/` reach the callback too: its 2 s latency batches them and only the paths are
/// compared, nothing is read. `CatalogSourcesModel.steamFilesChanged` paces the rescans.
@MainActor
public final class SteamManifestWatcher {
    /// Called on the main thread, at most once per batch of events.
    public var onChange: (@MainActor () -> Void)?

    private var stream: FSEventStreamRef?
    private var watched: [String] = []
    private var libraries: [String] = []
    private var root: String?

    public init(onChange: (@MainActor () -> Void)? = nil) { self.onChange = onChange }

    /// Watches these libraries (the scan's, the source's root among them); the same set again changes nothing,
    /// none stops watching.
    public func watch(_ libraries: [URL], root: URL?) {
        let paths = libraries.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        let rootPath = root.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        guard paths != self.libraries || rootPath != self.root else { return }
        stop()
        self.libraries = paths
        self.root = rootPath
        let folders = paths.map { $0 + "/steamapps" }.filter { FileManager.default.fileExists(atPath: $0) }
        guard !folders.isEmpty else { return }
        // The stream holds the watcher until it is released in `stop`, so a callback already queued on the main
        // queue never reaches a freed watcher.
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: { info in
                                               guard let info else { return nil }
                                               _ = Unmanaged<SteamManifestWatcher>.fromOpaque(info).retain()
                                               return info
                                           },
                                           release: { info in
                                               guard let info else { return }
                                               Unmanaged<SteamManifestWatcher>.fromOpaque(info).release()
                                           },
                                           copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
                                             | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(nil, Self.callback, &context, folders as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2, flags) else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream); FSEventStreamRelease(stream)
            return
        }
        self.stream = stream
        watched = folders
    }

    public func stop() {
        if let stream {
            FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream)
        }
        stream = nil; watched = []; libraries = []; root = nil
    }

    /// An event that may change the library. With `dropped` (the system lost events under `path` and asks for a
    /// rescan of it), only a drop at a `steamapps` folder or above counts: one inside `downloading/` or `common/`
    /// says nothing about the manifests, and a long download could otherwise rescan every batch.
    public nonisolated static func isRelevant(_ path: String, dropped: Bool, libraries: [String], root: String?) -> Bool {
        guard dropped else { return isRelevant(path, libraries: libraries, root: root) }
        let folder = path.hasSuffix("/") ? String(path.dropLast()) : path
        return libraries.contains { library in
            let steamapps = library + "/steamapps"
            return steamapps == folder || steamapps.hasPrefix(folder + "/")
        }
    }

    /// `<library>/steamapps/appmanifest_<digits>.acf`, or the root's `steamapps/libraryfolders.vdf`.
    public nonisolated static func isRelevant(_ path: String, libraries: [String], root: String?) -> Bool {
        if let root, path == root + "/steamapps/libraryfolders.vdf" { return true }
        for library in libraries {
            let prefix = library + "/steamapps/"
            guard path.hasPrefix(prefix) else { continue }
            let name = path.dropFirst(prefix.count)
            guard name.hasPrefix("appmanifest_"), name.hasSuffix(".acf") else { return false }
            let digits = name.dropFirst("appmanifest_".count).dropLast(".acf".count)
            return !digits.isEmpty && digits.utf8.allSatisfy { (48...57).contains($0) }
        }
        return false
    }

    private func received(_ paths: [String], flags: [FSEventStreamEventFlags]) {
        let mustScan = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
        let changed = zip(paths, flags).contains { path, flag in
            Self.isRelevant(path, dropped: flag & mustScan != 0, libraries: libraries, root: root)
        }
        if changed { onChange?() }
    }

    private static let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
        guard let info else { return }
        let paths = (unsafeBitCast(eventPaths, to: NSArray.self) as? [String]) ?? []
        let flags = Array(UnsafeBufferPointer(start: eventFlags, count: count))
        let watcher = Unmanaged<SteamManifestWatcher>.fromOpaque(info).takeUnretainedValue()
        MainActor.assumeIsolated { watcher.received(paths, flags: flags) }
    }
}
