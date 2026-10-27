import CoreGraphics

public struct SeleneLayoutMetrics: Equatable {
    public let width: CGFloat

    public init(width: CGFloat) {
        self.width = max(width, 0)
    }

    public var margin: CGFloat {
        width >= 1500 ? 64 : (width >= 1280 ? 48 : 32)
    }

    public var sidebarWidth: CGFloat {
        width >= 1500 ? 248 : 220
    }

    public var heroTitleSize: CGFloat {
        min(72, max(48, width * 0.045))
    }

    public var railCardWidth: CGFloat {
        width >= 1500 ? 128 : 112
    }

    public var railCardHeight: CGFloat {
        (railCardWidth * 4 / 3).rounded()
    }

    public var contentWidth: CGFloat {
        max(0, width - 2 * margin)
    }

    public var isCompact: Bool {
        width < 1280
    }
}
