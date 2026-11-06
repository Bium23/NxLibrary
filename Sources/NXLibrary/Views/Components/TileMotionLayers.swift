import AppKit
import NXLibraryCore
import SwiftUI

/// The selected tile's ring, played by Core Animation: its gradient turns and its glow breathes in the render
/// server, so a still screen costs the app nothing between frames. SwiftUI redrew it at the screen's rate,
/// which kept a quarter of a core busy; at 30 a second it stuttered.
struct TileRingLayers: NSViewRepresentable {
    let style: TileRingLayerView.Style

    func makeNSView(context: Context) -> TileRingLayerView { TileRingLayerView(style: style) }

    func updateNSView(_ view: TileRingLayerView, context: Context) { view.style = style }
}

/// The selected tile's shine, played by Core Animation from the moment the tile is selected.
struct TileShineLayers: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> TileShineLayerView { TileShineLayerView(cornerRadius: cornerRadius) }

    func updateNSView(_ view: TileShineLayerView, context: Context) { view.cornerRadius = cornerRadius }
}

/// A flipped, layer-hosting view that never takes the pointer: the layers are laid out top-left first, like
/// SwiftUI, and their loops start when the view reaches a window.
class TileMotionLayerView: NSView {
    let root = CALayer()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func makeBackingLayer() -> CALayer { root }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        Self.withoutActions { arrange(scale: window?.backingScaleFactor ?? 2) }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        needsLayout = true
        startLoops()
    }

    /// Frames, paths and contents for the current bounds and screen scale.
    func arrange(scale: CGFloat) {}

    /// Adds the loops that are not running yet.
    func startLoops() {}

    static func withoutActions(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    /// A loop through `values` at `keyTimes` over `period`, `phase` seconds in, repeating for as long as the
    /// layer lives.
    static func loop(_ keyPath: String, values: [Any], keyTimes: [Double],
                     period: Double, phase: Double) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = keyTimes.map { NSNumber(value: $0) }
        animation.calculationMode = .linear
        animation.duration = period
        animation.repeatCount = .infinity
        animation.timeOffset = phase
        animation.isRemovedOnCompletion = false
        return animation
    }

    /// A gradient end in `CAGradientLayer`'s unit space from SwiftUI's (y down): here y runs up even in a
    /// flipped view (measured on screen: unflipped, the ring turned anticlockwise).
    static func gradientPoint(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: 1 - point.y) }

    /// `color` with its opacity multiplied by `opacity`, as SwiftUI's `opacity(_:)` does.
    static func cgColor(_ color: Color, opacity: Double) -> CGColor {
        let base = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        return base.withAlphaComponent(base.alphaComponent * opacity).cgColor
    }
}

final class TileRingLayerView: TileMotionLayerView {
    struct Style: Hashable {
        var cornerRadius: CGFloat
        var focus: Color
        /// The glow: a stroke this wide, blurred this much.
        var glowLine: CGFloat
        var glowBlur: CGFloat
        var ringLine: CGFloat
        var hairline: CGFloat
        /// The hairline sits this far inside the tile.
        var hairInset: CGFloat
        /// Room round the tile for the glow's blur: the view is this much larger than the tile on every side.
        var margin: CGFloat
    }

    var style: Style {
        didSet {
            guard style != oldValue else { return }
            if style.focus != oldValue.focus { Self.withoutActions { applyColours() } }
            needsLayout = true
        }
    }

    private let glow = CALayer()
    private let ring = CAGradientLayer()
    private let ringShape = CAShapeLayer()
    private let hair = CAShapeLayer()

    init(style: Style) {
        self.style = style
        super.init()
        glow.opacity = 0.35
        ringShape.fillColor = nil
        ringShape.strokeColor = NSColor.black.cgColor
        ring.mask = ringShape
        ring.locations = [0, 0.25, 0.5, 0.75, 1]
        let axis = TileMotion.ringAxis(at: 0)
        ring.startPoint = Self.gradientPoint(axis.start)
        ring.endPoint = Self.gradientPoint(axis.end)
        hair.fillColor = nil
        hair.strokeColor = NSColor.white.withAlphaComponent(0.18).cgColor
        root.addSublayer(glow)
        root.addSublayer(ring)
        root.addSublayer(hair)
        applyColours()
    }

    required init?(coder: NSCoder) { nil }

    /// Every stop is the focus colour, so no part of the ring ever reads dark.
    private func applyColours() {
        ring.colors = [1, 0.9, 0.6, 0.9, 1].map { Self.cgColor(style.focus, opacity: $0) }
    }

    override func arrange(scale: CGFloat) {
        let tile = bounds.insetBy(dx: style.margin, dy: style.margin)
        guard tile.width > 0, tile.height > 0 else { return }
        let corner = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
        let local = CGRect(origin: .zero, size: tile.size)

        glow.frame = bounds
        glow.contentsScale = scale
        glow.contents = Self.glowImage(style: style, tile: tile.size, scale: scale)

        ring.frame = tile
        ring.contentsScale = scale
        ringShape.frame = local
        ringShape.contentsScale = scale
        ringShape.lineWidth = style.ringLine
        ringShape.path = corner.inset(by: style.ringLine / 2).path(in: local).cgPath

        hair.frame = tile
        hair.contentsScale = scale
        hair.lineWidth = style.hairline
        hair.path = corner.inset(by: style.hairline / 2)
            .path(in: local.insetBy(dx: style.hairInset, dy: style.hairInset)).cgPath
    }

    /// On the shared clock, like every other ring: moving between tiles keeps the beat.
    override func startLoops() {
        let now = Date().timeIntervalSinceReferenceDate
        if ring.animation(forKey: "turn.start") == nil {
            let turn = TileMotion.loop(period: TileMotion.ringPeriod, steps: 150) { TileMotion.ringAxis(at: $0) }
            let phase = TileMotion.phase(period: TileMotion.ringPeriod, at: now)
            ring.add(Self.loop("startPoint", values: turn.values.map { NSValue(point: Self.gradientPoint($0.start)) },
                               keyTimes: turn.keyTimes, period: TileMotion.ringPeriod, phase: phase),
                     forKey: "turn.start")
            ring.add(Self.loop("endPoint", values: turn.values.map { NSValue(point: Self.gradientPoint($0.end)) },
                               keyTimes: turn.keyTimes, period: TileMotion.ringPeriod, phase: phase),
                     forKey: "turn.end")
        }
        if glow.animation(forKey: "breath") == nil {
            let breath = TileMotion.loop(period: TileMotion.glowPeriod, steps: 108) { TileMotion.glowOpacity(at: $0) }
            glow.add(Self.loop("opacity", values: breath.values.map { NSNumber(value: $0) },
                               keyTimes: breath.keyTimes, period: TileMotion.glowPeriod,
                               phase: TileMotion.phase(period: TileMotion.glowPeriod, at: now)),
                     forKey: "breath")
        }
    }

    private struct GlowKey: Hashable {
        var style: Style
        var width: CGFloat
        var height: CGFloat
        var scale: CGFloat
    }

    /// Glows drawn so far: every tile of a row shares one, so selecting another draws nothing new.
    private static var glows: [GlowKey: CGImage] = [:]

    /// The glow drawn once by SwiftUI itself (the same stroke and blur as before), then only faded.
    private static func glowImage(style: Style, tile: CGSize, scale: CGFloat) -> CGImage? {
        let key = GlowKey(style: style, width: tile.width, height: tile.height, scale: scale)
        if let image = glows[key] { return image }
        let content = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
            .strokeBorder(style.focus, lineWidth: style.glowLine)
            .blur(radius: style.glowBlur)
            .frame(width: tile.width, height: tile.height)
            .padding(style.margin)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        if glows.count >= 16 { glows.removeAll() }
        glows[key] = image
        return image
    }
}

final class TileShineLayerView: TileMotionLayerView {
    var cornerRadius: CGFloat {
        didSet { if cornerRadius != oldValue { needsLayout = true } }
    }

    private let band = CAGradientLayer()
    private let shape = CAShapeLayer()

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init()
        // Selene's glint (Main.xaml Shine): a thin core at 0.18 white with faint 0.04 shoulders.
        band.colors = [0, 0.04, 0.18, 0.04, 0].map { NSColor.white.withAlphaComponent($0).cgColor }
        band.locations = [0, 0.3, 0.5, 0.7, 1]
        let axis = TileMotion.shineAxis(at: 0)
        band.startPoint = Self.gradientPoint(axis.start)
        band.endPoint = Self.gradientPoint(axis.end)
        shape.fillColor = NSColor.black.cgColor
        band.mask = shape
        root.addSublayer(band)
    }

    required init?(coder: NSCoder) { nil }

    override func arrange(scale: CGFloat) {
        band.frame = bounds
        band.contentsScale = scale
        shape.frame = bounds
        shape.contentsScale = scale
        shape.path = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: bounds).cgPath
    }

    /// Each selection starts its own cycle, so the light always comes in from the corner.
    override func startLoops() {
        guard band.animation(forKey: "sweep.start") == nil else { return }
        let sweep = TileMotion.loop(period: TileMotion.shinePeriod, steps: 150) { TileMotion.shineAxis(at: $0) }
        band.add(Self.loop("startPoint", values: sweep.values.map { NSValue(point: Self.gradientPoint($0.start)) },
                           keyTimes: sweep.keyTimes, period: TileMotion.shinePeriod, phase: 0),
                 forKey: "sweep.start")
        band.add(Self.loop("endPoint", values: sweep.values.map { NSValue(point: Self.gradientPoint($0.end)) },
                           keyTimes: sweep.keyTimes, period: TileMotion.shinePeriod, phase: 0),
                 forKey: "sweep.end")
    }
}
