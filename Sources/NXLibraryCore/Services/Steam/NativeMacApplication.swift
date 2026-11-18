import Foundation

public enum MacExecutableArchitecture: String, Hashable, Codable, Sendable { case arm64, x86_64 }

public enum NativeMacApplicationError: Error, Equatable {
    case invalidBundle, unsafePath, invalidExecutable, metadataTooLarge
}

/// Evidence about an installed app, independent of Steam and of any launch operation.
public struct NativeMacApplication: Equatable, Sendable {
    public let url: URL
    public let executableURL: URL
    public let bundleIdentifier: String?
    public let name: String
    public let architectures: Set<MacExecutableArchitecture>
    public let isDeclaredGame: Bool
    let fileObservations: [InstallationFileObservation]

    public static func inspect(at app: URL, within root: URL) throws -> Self {
        let fm = FileManager.default
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        let app = app.resolvingSymlinksInPath().standardizedFileURL
        guard app.pathExtension.lowercased() == "app", isWithin(app, root: root) else {
            throw NativeMacApplicationError.unsafePath
        }
        let plist = app.appendingPathComponent("Contents/Info.plist").resolvingSymlinksInPath().standardizedFileURL
        guard isWithin(plist, root: app) else { throw NativeMacApplicationError.unsafePath }
        let metadata: InstallationFileSnapshot
        do { metadata = try InstallationFileSnapshot.read(at: plist, maximumBytes: 1024 * 1024) }
        catch InstallationFileReadError.tooLarge { throw NativeMacApplicationError.metadataTooLarge }
        let data = metadata.data
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundlePackageType"] as? String == "APPL",
              info["LSRequiresIPhoneOS"] as? Bool != true,
              let executable = info["CFBundleExecutable"] as? String,
              !executable.isEmpty, executable != ".", executable != "..",
              !executable.contains("/"), !executable.contains("\\") else { throw NativeMacApplicationError.invalidBundle }
        if let platforms = info["CFBundleSupportedPlatforms"] as? [String],
           !platforms.isEmpty, !platforms.contains("MacOSX") { throw NativeMacApplicationError.invalidBundle }
        let executableURL = app.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable)
            .resolvingSymlinksInPath().standardizedFileURL
        guard isWithin(executableURL, root: app) else { throw NativeMacApplicationError.unsafePath }
        guard fm.isExecutableFile(atPath: executableURL.path) else { throw NativeMacApplicationError.invalidExecutable }
        let executableEvidence = try MacExecutableHeader.inspect(at: executableURL)
        let bundleID = (info["CFBundleIdentifier"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let name = [info["CFBundleDisplayName"] as? String, info["CFBundleName"] as? String]
            .compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? app.deletingPathExtension().lastPathComponent
        let category = info["LSApplicationCategoryType"] as? String ?? ""
        try metadata.verifyUnchanged()
        return Self(url: app, executableURL: executableURL, bundleIdentifier: bundleID, name: name,
                    architectures: executableEvidence.architectures, isDeclaredGame: gameCategories.contains(category),
                    fileObservations: [metadata.observation, executableEvidence.observation])
    }

    static func isWithin(_ url: URL, root: URL) -> Bool {
        url.path == root.path || url.path.hasPrefix(root.path.hasSuffix("/") ? root.path : root.path + "/")
    }

    private static let gameCategories: Set<String> = Set([
        "games", "action-games", "adventure-games", "arcade-games", "board-games", "card-games",
        "casino-games", "dice-games", "educational-games", "family-games", "kids-games", "music-games",
        "puzzle-games", "racing-games", "role-playing-games", "simulation-games", "sports-games",
        "strategy-games", "trivia-games", "word-games"
    ].map { "public.app-category." + $0 })
}

/// Reads only bounded Mach-O headers and fat architecture tables, never executable contents.
private enum MacExecutableHeader {
    static func inspect(at url: URL) throws -> (architectures: Set<MacExecutableArchitecture>, observation: InstallationFileObservation) {
        let file = try InstallationFileSnapshot.openReadOnly(url)
        defer { try? file.close() }
        let observation = try InstallationFileObservation.capture(fileDescriptor: file.fileDescriptor, url: url)
        let size = try file.seekToEnd()
        let result = try architectures(file: file, size: size)
        try observation.verifyUnchanged()
        return (result, observation)
    }

    private static func architectures(file: FileHandle, size: UInt64) throws -> Set<MacExecutableArchitecture> {
        func read(_ offset: UInt64, _ count: Int) throws -> Data {
            guard offset <= size, UInt64(count) <= size - offset else { throw NativeMacApplicationError.invalidExecutable }
            try file.seek(toOffset: offset)
            guard let bytes = try file.read(upToCount: count), bytes.count == count else {
                throw NativeMacApplicationError.invalidExecutable
            }
            return bytes
        }
        let first = try read(0, 8)
        let magic = word(first, 0, bigEndian: true)
        let isFat64 = magic == 0xcafebabf || magic == 0xbfbafeca
        let isFat = isFat64 || magic == 0xcafebabe || magic == 0xbebafeca
        if !isFat { return [try thin(try read(0, 32), expectedCPU: nil)] }
        let bigEndian = magic == 0xcafebabe || magic == 0xcafebabf
        let count = Int(word(first, 4, bigEndian: bigEndian))
        guard (1...64).contains(count) else { throw NativeMacApplicationError.invalidExecutable }
        let stride = isFat64 ? 32 : 20
        let table = try read(8, count * stride)
        let tableEnd = UInt64(8 + count * stride)
        var result: Set<MacExecutableArchitecture> = []
        for index in 0..<count {
            let start = index * stride
            let cpu = word(table, start, bigEndian: bigEndian)
            let offset = isFat64 ? longWord(table, start + 8, bigEndian: bigEndian)
                : UInt64(word(table, start + 8, bigEndian: bigEndian))
            let length = isFat64 ? longWord(table, start + 16, bigEndian: bigEndian)
                : UInt64(word(table, start + 12, bigEndian: bigEndian))
            guard offset >= tableEnd, offset <= size, length >= 32, length <= size - offset else {
                throw NativeMacApplicationError.invalidExecutable
            }
            if cpu == 0x01000007 || cpu == 0x0100000c {
                result.insert(try thin(try read(offset, 32), expectedCPU: cpu))
            }
        }
        guard !result.isEmpty else { throw NativeMacApplicationError.invalidExecutable }
        return result
    }

    private static func thin(_ data: Data, expectedCPU: UInt32?) throws -> MacExecutableArchitecture {
        let magic = word(data, 0, bigEndian: true)
        guard magic == 0xcffaedfe || magic == 0xfeedfacf else { throw NativeMacApplicationError.invalidExecutable }
        let bigEndian = magic == 0xfeedfacf
        let cpu = word(data, 4, bigEndian: bigEndian)
        guard word(data, 12, bigEndian: bigEndian) == 2, expectedCPU == nil || cpu == expectedCPU else {
            throw NativeMacApplicationError.invalidExecutable
        }
        switch cpu {
        case 0x01000007: return .x86_64
        case 0x0100000c: return .arm64
        default: throw NativeMacApplicationError.invalidExecutable
        }
    }

    private static func word(_ data: Data, _ offset: Int, bigEndian: Bool) -> UInt32 {
        let shifts = bigEndian ? [24, 16, 8, 0] : [0, 8, 16, 24]
        return (0..<4).reduce(0) { $0 | UInt32(data[offset + $1]) << shifts[$1] }
    }

    private static func longWord(_ data: Data, _ offset: Int, bigEndian: Bool) -> UInt64 {
        let first = UInt64(word(data, offset, bigEndian: bigEndian))
        let second = UInt64(word(data, offset + 4, bigEndian: bigEndian))
        return bigEndian ? (first << 32) | second : first | (second << 32)
    }
}
