import Foundation
import CryptoKit
import ImageIO

/// Independently implemented from the site's HTML, without importing the GPL reference implementation.
/// Automatic matching is intentionally exact after punctuation/diacritic normalization: sequels and editions
/// are distinct games. A Switch 2 Title ID does not by itself identify a Switch 2 Edition upgrade.
enum SwitchIconShowdown {
    struct Result: Equatable { let id: Int; let title: String }

    static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func results(in html: String) -> [Result] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<tr\b[^>]*>\s*<td\b[^>]*>\s*<a\b[^>]*href=['"](?:\./)?detail\.php\?id=(\d{1,9})['"][^>]*>.*?</a>\s*</td>\s*<td\b[^>]*>\s*<center>([^<]+)</center>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).prefix(100).compactMap { m in
            guard let r = Range(m.range(at: 1), in: html), let t = Range(m.range(at: 2), in: html),
                  let id = Int(html[r]), id > 0 else { return nil }
            return Result(id: id, title: LaunchBoxArt.unescape(String(html[t])))
        }
    }

    /// Apply rules for all agents / NXLibrary, with the longest matching path winning and Allow winning ties.
    /// An unavailable or unrecognizable robots response does not authorize automated image retrieval.
    static func allowsIcons(in robots: String, path: String) -> Bool {
        typealias Rule = (field: String, path: String)
        var groups: [(agents: [String], rules: [Rule])] = []
        var agents: [String] = [], rules: [Rule] = []
        for raw in robots.components(separatedBy: .newlines) {
            let line = raw.components(separatedBy: "#")[0]
            let pair = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2 else { continue }
            let field = pair[0].lowercased(), value = pair[1]
            if field == "user-agent" {
                if !rules.isEmpty { groups.append((agents, rules)); agents = []; rules = [] }
                agents.append(value.lowercased())
            } else if field == "allow" || field == "disallow" {
                rules.append((field, value))
            }
        }
        if !agents.isEmpty { groups.append((agents, rules)) }
        guard !groups.isEmpty else { return false }
        func specificity(_ names: [String]) -> Int {
            names.map { $0 == "*" ? 0 : (!$0.isEmpty && "nxlibrary".hasPrefix($0) ? $0.count : -1) }.max() ?? -1
        }
        let agentMatch = groups.map { specificity($0.agents) }.max() ?? -1
        var best = -1, allowed = true
        for group in groups where agentMatch >= 0 && specificity(group.agents) == agentMatch {
            for rule in group.rules where !rule.path.isEmpty {
                let anchored = rule.path.hasSuffix("$")
                let text = anchored ? String(rule.path.dropLast()) : rule.path
                let pattern = "^" + text.components(separatedBy: "*")
                    .map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: ".*") + (anchored ? "$" : "")
                guard path.range(of: pattern, options: .regularExpression) != nil else { continue }
                let length = text.filter { $0 != "*" }.count
                if length > best || length == best && rule.field == "allow" {
                    best = length; allowed = rule.field == "allow"
                }
            }
        }
        return allowed
    }

    static func match(name: String, titleID: String, results: [Result]) -> Result? {
        let query = normalized(name)
        guard !query.isEmpty else { return nil }
        let edition = " nintendo switch 2 edition"
        if titleID.hasPrefix("04"), !query.hasSuffix(edition),
           results.contains(where: { normalized($0.title) == query + edition }) { return nil }
        let exact = results.filter { normalized($0.title) == query }
        guard Set(exact.map(\.id)).count == 1 else { return nil }
        return exact.first
    }
}

/// Title DB first, then one unambiguous Switch Icon Showdown result. Images stay in the artwork cache,
/// never in ArtworkPicks. Misses are cached for 15 minutes; successful images work offline.
/// Concurrent requests for the same game share a lookup; network failures cannot stop a build.
actor AutomaticIconResolver {
    private let directory: URL
    private let client: ArtworkHTTPClient
    private var pending: [String: Task<URL?, Never>] = [:]

    init(directory: URL, client: ArtworkHTTPClient) { self.directory = directory; self.client = client }

    func resolve(titleID: String, name: String) async -> URL? {
        guard titleID.count == 16, titleID.allSatisfy(\.isHexDigit), !SwitchIconShowdown.normalized(name).isEmpty else { return nil }
        let title = titleID.uppercased()
        let folder = directory.appendingPathComponent(title)
        let image = folder.appendingPathComponent("square.png")
        if let data = try? Data(contentsOf: image), CGImageSourceCreateWithData(data as CFData, nil) != nil { return image }
        let key = title + ":" + SwitchIconShowdown.normalized(name)
        if let work = pending[key] { return await work.value }
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        let miss = folder.appendingPathComponent("square-miss.txt")
        if (try? String(contentsOf: miss, encoding: .utf8)) == hash,
           let attrs = try? FileManager.default.attributesOfItem(atPath: miss.path),
           let date = attrs[.modificationDate] as? Date, Date().timeIntervalSince(date) < 900 { return nil }
        let work = Task { [client] in
            await Self.lookup(titleID: title, name: name, folder: folder, image: image, miss: miss, missKey: hash, client: client)
        }
        pending[key] = work
        let result = await work.value
        pending[key] = nil
        return result
    }

    private static func lookup(titleID: String, name: String, folder: URL, image: URL, miss: URL,
                               missKey: String, client: ArtworkHTTPClient) async -> URL? {
        let primary = URL(string: "https://api.nlib.cc/nx/\(titleID)/icon")!
        if let data = await get(primary, client: client), let png = validImage(data),
           store(png, image: image, source: "Title DB", folder: folder) { return image }
        var query = URLComponents(string: "https://www.switchiconshowdown.com/search.php")!
        query.queryItems = [URLQueryItem(name: "query", value: name)]
        let robotsURL = URL(string: "https://www.switchiconshowdown.com/robots.txt")!
        if let rulesData = await get(robotsURL, client: client, limit: 256 * 1024),
           let rules = String(data: rulesData, encoding: .utf8),
           let search = query.url, SwitchIconShowdown.allowsIcons(in: rules, path: search.path),
           let data = await get(search, client: client, limit: 2 * 1024 * 1024),
           let html = String(data: data, encoding: .utf8),
           let chosen = SwitchIconShowdown.match(name: name, titleID: titleID, results: SwitchIconShowdown.results(in: html)),
           let url = URL(string: "https://www.switchiconshowdown.com/images/\(chosen.id).png"),
           SwitchIconShowdown.allowsIcons(in: rules, path: url.path),
           let bytes = await get(url, client: client), let png = validImage(bytes),
           store(png, image: image, source: "Switch Icon Showdown", folder: folder) { return image }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Data(missKey.utf8).write(to: miss, options: .atomic)
        return nil
    }

    private static func get(_ url: URL, client: ArtworkHTTPClient, limit: Int = 8 * 1024 * 1024) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("NXLibrary (macOS; automatic icon lookup)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await client.data(for: request), response.statusCode == 200,
              !data.isEmpty, data.count <= limit, let final = response.url,
              final.scheme == "https", final.user == nil, final.password == nil,
              final.port == nil || final.port == 443,
              ["api.nlib.cc", "www.switchiconshowdown.com", "switchiconshowdown.com"].contains(final.host?.lowercased() ?? "") else { return nil }
        return data
    }

    private static func validImage(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width == height, width >= 32, width <= 8192 else { return nil }
        return ArtworkStore.downsample(data, maxPixelSize: 512, png: true)
    }

    private static func store(_ data: Data, image: URL, source: String, folder: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: image, options: .atomic)
            try? Data(source.utf8).write(to: folder.appendingPathComponent("square-source.txt"), options: .atomic)
            return true
        } catch { return false }
    }
}
