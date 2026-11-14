import AppKit
import SwiftUI

/// The launch screen's game logo, breathing while the game is on its way: a little brighter and larger, then back,
/// 1.6 s each way like the NX Library mark in the corner, for nxnative and Steam games alike. Core Animation plays
/// it in the render server, so it stays smooth while Steam starts and the main thread is busy. With Reduce Motion
/// the logo stands still. The view is larger than the logo by `margin` on every side, so neither its shadow nor
/// its growth is cut.
struct LaunchLogo: NSViewRepresentable {
    let image: NSImage
    let shadowRadius: CGFloat
    let reduceMotion: Bool

    /// Room around the logo for its shadow and its growth.
    static func margin(shadowRadius: CGFloat) -> CGFloat { shadowRadius * 2 }

    /// The logo's size fitted in `bounds`, as SwiftUI's `aspectRatio(contentMode: .fit)` gives it.
    static func fitted(_ size: CGSize, in bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    func makeNSView(context: Context) -> LaunchLogoLayerView {
        LaunchLogoLayerView(image: image, shadowRadius: shadowRadius, reduceMotion: reduceMotion)
    }

    func updateNSView(_ view: LaunchLogoLayerView, context: Context) {
        view.update(image: image, shadowRadius: shadowRadius, reduceMotion: reduceMotion)
    }
}

final class LaunchLogoLayerView: TileMotionLayerView {
    /// Opacity and scale at the quiet end of the breath; the other end is the logo as drawn.
    static let dim: Float = 0.78
    static let grown: CGFloat = 1.03
    static let leg: CFTimeInterval = 1.6
    private static let key = "breathe"

    private let logo = CALayer()
    private var image: NSImage
    private var shadowRadius: CGFloat
    private var reduceMotion: Bool

    init(image: NSImage, shadowRadius: CGFloat, reduceMotion: Bool) {
        self.image = image
        self.shadowRadius = shadowRadius
        self.reduceMotion = reduceMotion
        super.init()
        logo.contentsGravity = .resizeAspect
        logo.contents = image
        // The shadow SwiftUI gave the logo: black at 50%, no offset.
        logo.shadowColor = NSColor.black.cgColor
        logo.shadowOpacity = 0.5
        logo.shadowOffset = .zero
        root.addSublayer(logo)
    }

    required init?(coder: NSCoder) { nil }

    func update(image: NSImage, shadowRadius: CGFloat, reduceMotion: Bool) {
        if image !== self.image { self.image = image; logo.contents = image }
        if shadowRadius != self.shadowRadius { self.shadowRadius = shadowRadius; needsLayout = true }
        if reduceMotion != self.reduceMotion { self.reduceMotion = reduceMotion; startLoops() }
    }

    override func arrange(scale: CGFloat) {
        logo.frame = bounds.insetBy(dx: LaunchLogo.margin(shadowRadius: shadowRadius),
                                    dy: LaunchLogo.margin(shadowRadius: shadowRadius))
        logo.contentsScale = scale
        logo.shadowRadius = shadowRadius
    }

    override func startLoops() {
        logo.removeAnimation(forKey: Self.key)
        guard !reduceMotion else { return }
        logo.add(Self.breathing(), forKey: Self.key)
    }

    /// From the quiet end to the logo as drawn and back, easing at both ends, for as long as the layer lives.
    static func breathing() -> CAAnimationGroup {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = dim
        fade.toValue = Float(1)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = CGFloat(1)
        grow.toValue = grown
        let breath = CAAnimationGroup()
        breath.animations = [fade, grow]
        breath.duration = leg
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        breath.isRemovedOnCompletion = false
        return breath
    }
}
