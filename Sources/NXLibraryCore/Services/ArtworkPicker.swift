import Foundation
import ImageIO
import Combine

/// The four artwork slots a player can change, and the cache kind each one replaces.
public enum ArtworkSlot: String, CaseIterable, Codable, Sendable {
    case cover, background, icon, logo

    public var title: String {
        switch self {
        case .cover: return L10n.text("Cover")
        case .background: return L10n.text("Background")
        case .icon: return L10n.text("Icon")
        case .logo: return L10n.text("Logo")
        }
    }

    public var kind: ArtworkKind {
        switch self {
        case .cover: return .boxart
        case .background: return .hero
        case .icon: return .square
        case .logo: return .logo
        }
    }
}

/// What Title DB knows about one title, read through `api.nlib.cc/nx/<titleID>`.
public struct TitleDBInfo: Equatable, Sendable {
    public var name: String?
    public var icon: URL?
    public var banner: URL?
    public var screenshots: [URL]
    public var description: String?
    public var developer: String?
    public var publisher: String?
    /// "2023-05-12".
    public var releaseDate: String?
    public var categories: [String]

    public init(name: String?, icon: URL?, banner: URL?, screenshots: [URL], description: String? = nil,
                developer: String? = nil, publisher: String? = nil, releaseDate: String? = nil,
                categories: [String] = []) {
        self.name = name
        self.icon = icon
        self.banner = banner
        self.screenshots = screenshots
        self.description = description
        self.developer = developer
        self.publisher = publisher
        self.releaseDate = releaseDate
        self.categories = categories
    }

    private struct Wire: Decodable {
        struct Screens: Decodable { var screenshots: [String]? }
        /// Title DB writes dates as 20230512 or "2023-05-12".
        struct Day: Decodable {
            var text: String?
            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let number = try? container.decode(Int.self) {
                    let digits = String(number)
                    guard digits.count == 8 else { text = nil; return }
                    text = "\(digits.prefix(4))-\(digits.dropFirst(4).prefix(2))-\(digits.suffix(2))"
                } else {
                    text = try? container.decode(String.self)
                }
            }
        }
        var name: String?
        var icon: String?
        var banner: String?
        var screens: Screens?
        var description: String?
        var developer: String?
        var publisher: String?
        var releaseDate: Day?
        var category: [String]?
    }

    /// The API answers with http:// links; the same paths serve over https.
    public static func decode(_ data: Data) throws -> TitleDBInfo {
        let wire = try JSONDecoder().decode(Wire.self, from: data)
        return TitleDBInfo(name: wire.name, icon: wire.icon.flatMap(secure), banner: wire.banner.flatMap(secure),
                           screenshots: (wire.screens?.screenshots ?? []).compactMap(secure),
                           description: wire.description, developer: wire.developer, publisher: wire.publisher,
                           releaseDate: wire.releaseDate?.text, categories: wire.category ?? [])
    }

    public static func fetch(titleID: String, client: ArtworkHTTPClient = URLSessionArtworkClient()) async -> TitleDBInfo? {
        guard titleID.count == 16, titleID.allSatisfy(\.isHexDigit),
              let url = URL(string: "https://api.nlib.cc/nx/\(titleID)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("NXLibrary/0.1 (macOS; personal app)", forHTTPHeaderField: "User-Agent")
        guard let (data, http) = try? await client.data(for: request), (200..<300).contains(http.statusCode) else {
            return nil
        }
        return try? decode(data)
    }

    private static func secure(_ link: String) -> URL? {
        guard var components = URLComponents(string: link), components.host != nil else { return nil }
        if components.scheme == "http" { components.scheme = "https" }
        return components.url
    }
}

/// One image the picker offers for a slot.
public struct ArtworkCandidate: Equatable, Hashable, Sendable {
    public let slot: ArtworkSlot
    /// "GameTDB · US", "Title DB banner"…
    public let source: String
    public let url: URL
    /// Tried when `url` is missing: the standard size of a file asked for at twice the size.
    public let fallback: URL?
    /// The full-size file, downloaded only when the player chooses this image; `url` is then a small preview.
    public let full: URL?
    /// The full file's size in pixels, as its source states it.
    public let width: Int?
    public let height: Int?

    public init(slot: ArtworkSlot, source: String, url: URL, fallback: URL? = nil,
                full: URL? = nil, width: Int? = nil, height: Int? = nil) {
        self.slot = slot
        self.source = source
        self.url = url
        self.fallback = fallback
        self.full = full
        self.width = width
        self.height = height
    }
}

/// A candidate that downloaded and decoded, with its size in pixels.
public struct LoadedArtwork: Equatable, Sendable {
    public let candidate: ArtworkCandidate
    public let data: Data
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(candidate: ArtworkCandidate, data: Data, pixelWidth: Int, pixelHeight: Int) {
        self.candidate = candidate
        self.data = data
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    /// The size of the image a choice saves: the full file's when the source states it, not the preview's.
    public var resolution: String {
        if let width = candidate.width, let height = candidate.height, width > 0, height > 0 { return "\(width) × \(height)" }
        return "\(pixelWidth) × \(pixelHeight)"
    }
}

public enum ArtworkCandidates {
    /// Cover regions the picker tries for each GameTDB entry.
    public static let pickerRegions = ["US", "EN", "JA", "FR", "DE"]

    /// Every image worth offering for `slot`, in the order the picker shows them.
    /// `entries` are GameTDB matches, best first.
    public static func list(for slot: ArtworkSlot, entries: [GameTDBEntry], titleDB: TitleDBInfo?,
                            storeHeader: URL?, storeImage: URL?, storeLogo: URL?,
                            online: [ArtworkCandidate] = []) -> [ArtworkCandidate] {
        var list: [ArtworkCandidate] = []
        func add(_ source: String, _ url: URL?) {
            guard let url, !list.contains(where: { $0.url == url }) else { return }
            list.append(ArtworkCandidate(slot: slot, source: source, url: url))
        }
        switch slot {
        case .cover:
            for entry in entries {
                let urls = GameTDB.coverURLs(id: entry.id)
                for region in pickerRegions {
                    add("GameTDB · \(region)", urls.first { $0.pathComponents.dropLast().last == region })
                }
            }
        case .background:
            add("Title DB banner", titleDB?.banner)
            for (index, url) in (titleDB?.screenshots ?? []).enumerated() {
                add("Title DB screenshot \(index + 1)", url)
            }
            add(L10n.text("Nintendo store"), storeHeader)
            add(L10n.text("Nintendo store"), storeImage)
        case .icon:
            add("Title DB icon", titleDB?.icon)
        case .logo:
            add(L10n.text("Nintendo store"), storeLogo)
        }
        // Everything found online (`OnlineArtwork`) after the Nintendo sources, in its order.
        for candidate in online where candidate.slot == slot && !list.contains(where: { $0.url == candidate.url }) {
            list.append(candidate)
        }
        return list
    }

    /// A Steam game's images for `slot`: Steam's own art for the exact AppID first, its store
    /// screenshots as backgrounds, then everything found online (`OnlineArtwork`), without repeats.
    /// Steam has no icon art: the Icon tab offers only online images and files.
    public static func steamList(for slot: ArtworkSlot, appID: UInt32, screenshots: [URL],
                                 online: [ArtworkCandidate] = []) -> [ArtworkCandidate] {
        // Named for where Steam shows it, so the library hero is recognizable among the backgrounds.
        var list = (appID > 0 ? SteamStoreArt.candidates(appID: Int(appID), slot: slot) : []).map {
            ArtworkCandidate(slot: $0.slot, source: "Steam library", url: $0.url, fallback: $0.fallback)
        }
        if slot == .background {
            for shot in OnlineArtwork.screenshots(screenshots.map(\.absoluteString), source: "Steam screenshot", stripQuery: true)
            where !list.contains(where: { $0.url == shot.url }) {
                list.append(shot)
            }
        }
        for candidate in online where candidate.slot == slot && !list.contains(where: { $0.url == candidate.url }) {
            list.append(candidate)
        }
        return list
    }

    /// Downloads a candidate (or its fallback) and reads its size; nil when both are missing or not images.
    public static func load(_ candidate: ArtworkCandidate,
                            client: ArtworkHTTPClient = URLSessionArtworkClient()) async -> LoadedArtwork? {
        if let loaded = await load(candidate, from: candidate.url, client: client) { return loaded }
        guard let fallback = candidate.fallback else { return nil }
        return await load(candidate, from: fallback, client: client)
    }

    /// The image a choice saves: the full file when the candidate has one, otherwise what `load` read.
    public static func chosenData(_ artwork: LoadedArtwork,
                                  client: ArtworkHTTPClient = URLSessionArtworkClient()) async -> Data? {
        guard let full = artwork.candidate.full else { return artwork.data }
        return await load(artwork.candidate, from: full, client: client, timeout: 60)?.data
    }

    private static func load(_ candidate: ArtworkCandidate, from url: URL,
                             client: ArtworkHTTPClient, timeout: TimeInterval = 20) async -> LoadedArtwork? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("NXLibrary/0.1 (macOS; personal app)", forHTTPHeaderField: "User-Agent")
        guard let (data, http) = try? await client.data(for: request), (200..<300).contains(http.statusCode),
              let size = pixelSize(of: data) else { return nil }
        return LoadedArtwork(candidate: candidate, data: data, pixelWidth: size.width, pixelHeight: size.height)
    }

    public static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        return (width, height)
    }
}

/// The artwork a player chose, kept apart from the trimmed cache so it is never
/// evicted or overwritten. Every screen checks a pick before its automatic art.
public final class ArtworkPicks: ObservableObject {
    public static let shared = ArtworkPicks()

    public enum Failure: LocalizedError {
        case notAnImage
        public var errorDescription: String? { L10n.text("That file is not an image NX Library can read.") }
    }

    public let directory: URL
    /// Bumps on every change, so screens reload their art.
    @Published public private(set) var revision = 0

    public init(directory: URL = AppData.supportRoot.appendingPathComponent("artwork-picks")) {
        self.directory = directory
    }

    public func url(titleID: String, slot: ArtworkSlot) -> URL? {
        files(titleID: titleID, slot: slot).first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Stores `data` downsampled as the slot's cache kind would be; logos and icons stay PNG.
    @discardableResult
    public func save(_ data: Data, titleID: String, slot: ArtworkSlot) throws -> URL {
        let kind = slot.kind
        // An Icon pick can become the game app's icon, whose largest size is 1024 pixels.
        let size = slot == .icon ? 1024 : kind.maxPixelSize
        guard let image = ArtworkStore.downsample(data, maxPixelSize: size, png: kind.isPNG) else {
            throw Failure.notAnImage
        }
        let target = files(titleID: titleID, slot: slot)[0]
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try image.write(to: target, options: .atomic)
        try? FileManager.default.removeItem(at: files(titleID: titleID, slot: slot)[1])
        revision += 1
        return target
    }

    /// Screens reload their art: something they show besides the picks changed (a game app's icon).
    public func touch() { revision += 1 }

    /// Back to automatic art.
    public func remove(titleID: String, slot: ArtworkSlot) {
        for file in files(titleID: titleID, slot: slot) { try? FileManager.default.removeItem(at: file) }
        revision += 1
    }

    /// The file a save writes, then the other extension.
    private func files(titleID: String, slot: ArtworkSlot) -> [URL] {
        let folder = directory.appendingPathComponent(ArtworkStore.folderName(for: titleID))
        let exts = slot.kind.isPNG ? ["png", "jpg"] : ["jpg", "png"]
        return exts.map { folder.appendingPathComponent("\(slot.kind.rawValue).\($0)") }
    }
}

/// Focus in the picker's grid of tiles, and the slot tabs above it.
public enum ArtworkPickerFocus {
    public enum Direction: Sendable { case left, right, up, down }

    /// Sideways and vertical moves clamp; down from above a short last row lands on its last tile.
    public static func moved(_ index: Int, by direction: Direction, count: Int, columns: Int) -> Int {
        guard count > 0, columns > 0 else { return 0 }
        let index = min(max(index, 0), count - 1)
        switch direction {
        case .left: return max(index - 1, 0)
        case .right: return min(index + 1, count - 1)
        case .up: return index - columns >= 0 ? index - columns : index
        case .down:
            if index + columns < count { return index + columns }
            let lastRowStart = (count - 1) / columns * columns
            return index < lastRowStart ? count - 1 : index
        }
    }

    /// The neighbouring tab; the ends do not wrap.
    public static func slot(after slot: ArtworkSlot, by delta: Int) -> ArtworkSlot {
        let all = ArtworkSlot.allCases
        let index = all.firstIndex(of: slot) ?? 0
        return all[min(max(index + delta, 0), all.count - 1)]
    }
}
