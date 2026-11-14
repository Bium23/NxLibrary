import AppKit
import SwiftUI

/// The launch screen's motion, as Selene's: the game's art drifts slowly closer for as long as the game takes, and
/// its logo comes in once, fading while it rises gently into place, then stands still; NX Library's mark in the
/// corner breathes. Core Animation plays all three in the render server, so they stay smooth while the game or
/// Steam starts and the main thread is busy. With Reduce Motion the art and the mark stand still and the logo only
/// fades in.
enum LaunchMotion {
    /// Selene's ease-outs: sine for the fades and the drift, quintic for the rise.
    static let sineOut = CAMediaTimingFunction(controlPoints: 0.39, 0.575, 0.565, 1)
    static let quinticOut = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)

    /// The screen's own fade in; the logo starts a moment after it.
    static let screenFade: TimeInterval = 0.36
    static let logoDelay: CFTimeInterval = 0.06
    static let logoFade: CFTimeInterval = 0.75
    static let logoRise: CFTimeInterval = 1.0
    /// How far below its place the logo starts, in canvas units.
    static let riseDistance: CGFloat = 30

    /// The corner mark's breath: from 45% to full, 1.6 s each way.
    static let markDim: Float = 0.45
    static let markLeg: CFTimeInterval = 1.6

    static let artFrom: CGFloat = 1.04
    static let artTo: CGFloat = 1.12
    static let artDrift: CFTimeInterval = 20
}

/// The launch screen's game logo: fitted in its bounds, with a soft shadow, coming in once (`LaunchMotion`). The
/// view is larger than the logo by `margin` on every side, so its shadow is not cut.
struct LaunchLogo: NSViewRepresentable {
    let image: NSImage
    let shadowRadius: CGFloat
    /// How far below its place the logo starts, in points.
    let rise: CGFloat
    /// When the entrance may start (`CACurrentMediaTime`); a logo that arrives later comes in at once.
    let startsAt: CFTimeInterval
    let reduceMotion: Bool

    /// Room around the logo for its shadow.
    static func margin(shadowRadius: CGFloat) -> CGFloat { shadowRadius * 2 }

    /// The logo's size fitted in `bounds`, as SwiftUI's `aspectRatio(contentMode: .fit)` gives it.
    static func fitted(_ size: CGSize, in bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    func makeNSView(context: Context) -> LaunchLogoLayerView {
        LaunchLogoLayerView(image: image, shadowRadius: shadowRadius, rise: rise, startsAt: startsAt, reduceMotion: reduceMotion)
    }

    func updateNSView(_ view: LaunchLogoLayerView, context: Context) {
        view.update(image: image, shadowRadius: shadowRadius)
    }
}

final class LaunchLogoLayerView: TileMotionLayerView {
    private let logo = CALayer()
    private var image: NSImage
    private var shadowRadius: CGFloat
    private let rise: CGFloat
    private let startsAt: CFTimeInterval
    private let reduceMotion: Bool
    private var entered = false

    init(image: NSImage, shadowRadius: CGFloat, rise: CGFloat, startsAt: CFTimeInterval, reduceMotion: Bool) {
        self.image = image
        self.shadowRadius = shadowRadius
        self.rise = rise
        self.startsAt = startsAt
        self.reduceMotion = reduceMotion
        super.init()
        logo.contentsGravity = .resizeAspect
        logo.contents = image
        // Selene's shadow: black at 55%, no offset.
        logo.shadowColor = NSColor.black.cgColor
        logo.shadowOpacity = 0.55
        logo.shadowOffset = .zero
        root.addSublayer(logo)
    }

    required init?(coder: NSCoder) { nil }

    func update(image: NSImage, shadowRadius: CGFloat) {
        if image !== self.image { self.image = image; logo.contents = image }
        if shadowRadius != self.shadowRadius { self.shadowRadius = shadowRadius; needsLayout = true }
    }

    override func arrange(scale: CGFloat) {
        let margin = LaunchLogo.margin(shadowRadius: shadowRadius)
        logo.frame = bounds.insetBy(dx: margin, dy: margin)
        logo.contentsScale = scale
        logo.shadowRadius = shadowRadius
    }

    /// Once, the first time the logo reaches a window.
    override func startLoops() {
        guard !entered else { return }
        entered = true
        let begin = logo.convertTime(max(startsAt, CACurrentMediaTime()), from: nil)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = Float(0)
        fade.toValue = Float(1)
        fade.duration = LaunchMotion.logoFade
        fade.timingFunction = LaunchMotion.sineOut
        fade.beginTime = begin
        fade.fillMode = .backwards
        logo.add(fade, forKey: "fade")
        guard !reduceMotion else { return }
        // Below its place: the view is flipped, so its layers' y axis runs down.
        let lift = CABasicAnimation(keyPath: "transform.translation.y")
        lift.fromValue = rise
        lift.toValue = CGFloat(0)
        lift.duration = LaunchMotion.logoRise
        lift.timingFunction = LaunchMotion.quinticOut
        lift.beginTime = begin
        lift.fillMode = .backwards
        logo.add(lift, forKey: "rise")
    }
}

/// The launch screen's art, filling the screen and drifting slowly closer while the game starts (`LaunchMotion`).
struct LaunchArt: NSViewRepresentable {
    let image: NSImage
    /// The player's Launch motion setting, off with Reduce Motion too.
    let moves: Bool

    func makeNSView(context: Context) -> LaunchArtLayerView { LaunchArtLayerView(image: image, moves: moves) }

    func updateNSView(_ view: LaunchArtLayerView, context: Context) { view.update(image: image) }
}

final class LaunchArtLayerView: TileMotionLayerView {
    private let art = CALayer()
    private var image: NSImage
    private let moves: Bool
    private var drifting = false

    init(image: NSImage, moves: Bool) {
        self.image = image
        self.moves = moves
        super.init()
        root.masksToBounds = true
        art.contentsGravity = .resizeAspectFill
        art.contents = image
        if moves {
            // The drift's end, held once it is over.
            art.transform = CATransform3DMakeScale(LaunchMotion.artTo, LaunchMotion.artTo, 1)
        }
        root.addSublayer(art)
    }

    required init?(coder: NSCoder) { nil }

    func update(image: NSImage) {
        if image !== self.image { self.image = image; art.contents = image }
    }

    override func arrange(scale: CGFloat) {
        // Bounds and position, not frame: the frame of a scaled layer is its scaled box.
        art.bounds = CGRect(origin: .zero, size: bounds.size)
        art.position = CGPoint(x: bounds.midX, y: bounds.midY)
        art.contentsScale = scale
    }

    /// Once, the first time the art reaches a window.
    override func startLoops() {
        guard moves, !drifting else { return }
        drifting = true
        let drift = CABasicAnimation(keyPath: "transform.scale")
        drift.fromValue = LaunchMotion.artFrom
        drift.toValue = LaunchMotion.artTo
        drift.duration = LaunchMotion.artDrift
        drift.timingFunction = LaunchMotion.sineOut
        art.add(drift, forKey: "drift")
    }
}

/// NX Library's mark in the launch screen's corner, breathing while the game starts (`LaunchMotion`).
struct LaunchMark: NSViewRepresentable {
    let image: NSImage
    let reduceMotion: Bool

    func makeNSView(context: Context) -> LaunchMarkLayerView { LaunchMarkLayerView(image: image, reduceMotion: reduceMotion) }

    func updateNSView(_ view: LaunchMarkLayerView, context: Context) {}
}

final class LaunchMarkLayerView: TileMotionLayerView {
    private let mark = CALayer()
    private let reduceMotion: Bool

    init(image: NSImage, reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        super.init()
        mark.contentsGravity = .resizeAspect
        mark.contents = image
        root.addSublayer(mark)
    }

    required init?(coder: NSCoder) { nil }

    override func arrange(scale: CGFloat) {
        mark.frame = bounds
        mark.contentsScale = scale
    }

    override func startLoops() {
        mark.removeAnimation(forKey: "breathe")
        guard !reduceMotion else { return }
        let breath = CABasicAnimation(keyPath: "opacity")
        breath.fromValue = LaunchMotion.markDim
        breath.toValue = Float(1)
        breath.duration = LaunchMotion.markLeg
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        breath.isRemovedOnCompletion = false
        mark.add(breath, forKey: "breathe")
    }
}
