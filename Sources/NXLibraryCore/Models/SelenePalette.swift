import Foundation

/// A Selene colour palette (ported from Selene's theme/Palettes, MIT). Colours are 0xRRGGBB.
public struct SelenePalette: Codable, Equatable, Identifiable {
    public enum Mode: String, Codable { case dark, light }

    public struct BaseGradient: Codable, Equatable {
        public enum Kind: String, Codable { case linear, radial }
        public struct Stop: Codable, Equatable {
            public var color: UInt32
            public var location: Double
            public init(color: UInt32, location: Double) {
                self.color = color
                self.location = location
            }
        }
        public var kind: Kind
        public var stops: [Stop]
        public init(kind: Kind, stops: [Stop]) {
            self.kind = kind
            self.stops = stops
        }
    }

    public var id: String
    public var name: String
    public var mode: Mode
    public var focus: UInt32
    public var onFocus: UInt32
    public var ink: UInt32
    public var scrim: UInt32
    public var glass: UInt32
    public var glyph: UInt32
    public var success: UInt32
    public var base: BaseGradient
    public var defaultWallpaper: String?

    /// Built-in Selene palette, used when palettes.json is unavailable.
    public static let fallback = SelenePalette(
        id: "selene", name: "Selene", mode: .dark,
        focus: 0xFFFFFF, onFocus: 0x111111, ink: 0xFFFFFF, scrim: 0x000000,
        glass: 0x14181F, glyph: 0x9CCBFF, success: 0x3DDC84,
        base: .init(kind: .linear, stops: [
            .init(color: 0x17244A, location: 0),
            .init(color: 0x0C142C, location: 0.45),
            .init(color: 0x05080F, location: 1)
        ]),
        defaultWallpaper: nil
    )
}

public enum SelenePaletteCatalog {
    public static func load(from url: URL) throws -> [SelenePalette] {
        try JSONDecoder().decode([SelenePalette].self, from: Data(contentsOf: url))
    }

    public static func resolve(_ id: String, in palettes: [SelenePalette]) -> SelenePalette {
        palettes.first { $0.id == id }
            ?? palettes.first { $0.id == "selene" }
            ?? .fallback
    }
}
