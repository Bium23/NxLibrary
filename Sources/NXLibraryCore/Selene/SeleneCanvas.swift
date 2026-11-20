import CoreGraphics

/// Selene's 1920x1080 design canvas. Lengths are written in canvas units and
/// multiplied by `scale`, which follows the smaller window axis.
public struct SeleneCanvas: Equatable {
    public static let design = CGSize(width: 1920, height: 1080)

    public let size: CGSize

    public init(size: CGSize) {
        self.size = CGSize(width: max(size.width, 0), height: max(size.height, 0))
    }

    public var scale: CGFloat {
        min(size.width / Self.design.width, size.height / Self.design.height)
    }

    /// The 16:9 stage, `design` scaled uniformly, centred inside `size`.
    public var stageSize: CGSize {
        CGSize(width: Self.design.width * scale, height: Self.design.height * scale)
    }

    public var stageOrigin: CGPoint {
        let stage = stageSize
        return CGPoint(x: (size.width - stage.width) / 2, y: (size.height - stage.height) / 2)
    }

    public func u(_ value: CGFloat) -> CGFloat {
        value * scale
    }
}
