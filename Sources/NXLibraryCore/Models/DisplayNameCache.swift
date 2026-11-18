import Foundation

/// Display names read from the file system (a folder's Finder name, a volume's name), once per URL:
/// the page rebuilds on every render and key press, and a sleeping external disk would block each time.
@MainActor
public final class DisplayNameCache {
    private var names: [URL: String?] = [:]
    private let resolve: (URL) -> String?

    public init(resolve: @escaping (URL) -> String?) {
        self.resolve = resolve
    }

    public func name(for url: URL) -> String? {
        if let known = names[url] { return known }
        let name = resolve(url)
        names[url] = name
        return name
    }
}
