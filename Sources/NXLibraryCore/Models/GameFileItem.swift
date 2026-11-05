import Foundation

public enum SourceLayout: String, Codable, Equatable {
    /// An NSP / XCI / NSZ / XCZ package; `extracted` a dump folder; `container` one package of a `.nup` file,
    /// whose packages all share that file.
    case package, extracted, container
}

public enum SourceKind: String, Codable, Equatable {
    case base, update, dlc, unknown

    public var title: String {
        switch self {
        case .base: return "Base Game"
        case .update: return "Update"
        case .dlc: return "DLC"
        case .unknown: return "Switch File"
        }
    }

    public var iconName: String {
        switch self {
        case .base: return "gamecontroller.fill"
        case .update: return "arrow.triangle.2.circlepath.circle.fill"
        case .dlc: return "sparkles.rectangle.stack.fill"
        case .unknown: return "doc.fill"
        }
    }
}

public struct GameFileItem: Identifiable, Codable, Equatable {
    public var id: UUID
    public var url: URL
    public var name: String
    public var sizeBytes: Int64
    public var type: SourceKind
    public var titleId: String?
    public var versionString: String?
    public var isSymlink: Bool
    /// Absent in older libraries, whose sources are packages.
    public var sourceLayout: SourceLayout?
    public var requiresTitleSelection: Bool?
    public var layout: SourceLayout { sourceLayout ?? .package }

    public init(id: UUID = UUID(), url: URL, name: String, sizeBytes: Int64,
                type: SourceKind, titleId: String? = nil,
                versionString: String? = nil, isSymlink: Bool = false, sourceLayout: SourceLayout? = nil,
                requiresTitleSelection: Bool? = nil) {
        self.id = id
        self.url = url
        self.name = name
        self.sizeBytes = sizeBytes
        self.type = type
        self.titleId = titleId
        self.versionString = versionString
        self.isSymlink = isSymlink
        self.sourceLayout = sourceLayout
        self.requiresTitleSelection = requiresTitleSelection
    }

    public init(id: UUID = UUID(), url: URL, kind: SourceKind,
                titleId: String? = nil, versionString: String? = nil,
                sizeBytes: Int64, isSymlink: Bool = false, sourceLayout: SourceLayout? = nil,
                requiresTitleSelection: Bool? = nil) {
        self.init(id: id, url: url, name: url.lastPathComponent,
                  sizeBytes: sizeBytes, type: kind, titleId: titleId,
                  versionString: versionString, isSymlink: isSymlink, sourceLayout: sourceLayout,
                  requiresTitleSelection: requiresTitleSelection)
    }

    public var kind: SourceKind { type }
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}
