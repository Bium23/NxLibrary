import SwiftUI
import AppKit
import os
import NXLibraryCore

/// Selene's full-bleed backdrop (Main.xaml SeleneHubGameBackground): the backdrop
/// (base gradient, wallpaper, ambient motion), the selected game's art
/// crossfading on change, and the left, bottom and top shades at 0.3 scaled by
/// the Background shade setting. Shared by Spotlight and Collection.
struct SeleneArtBackground: View {
    let image: NSImage?
    /// Changes whenever `image` does; drives the crossfade.
    let imageKey: String
    var shade: BackgroundShade = .balanced
    /// Crossfade length; Collection takes a slower one so the art turns after the logo.
    var crossfade: Double = 0.4
    var backdrop = SeleneBackdrop()
    /// False keeps the wallpaper in front instead of the game's art (Settings → Look → Keep wallpaper on games).
    var showsArt = true
    /// The Mods card: no art, the moonlight turns gold (`SeleneBackdrop.modsTint`).
    var modsTint = false

    private var art: NSImage? { showsArt ? image : nil }

    var body: some View {
        ZStack {
            // Under a game's art the moonlight is hidden: it holds still (Selene fades it out there).
            backdrop.still(art != nil).modsTint(modsTint)
            // A crossfade is not movement: it stays under reduce motion (spec §8).
            SeleneArtLayer(image: art, key: art == nil ? "none" : imageKey, crossfade: crossfade)
            SeleneShades(shade: shade)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The home's left, bottom and top shades at 0.3 scaled by the Background shade
/// setting, in the palette's scrim colour. The Theme screen's preview takes the same.
struct SeleneShades: View {
    var shade: BackgroundShade = .balanced
    var scrim: Color = SeleneTheme.scrim

    var body: some View {
        let k = 0.3 * shade.scrimMultiplier
        return ZStack {
            Rectangle().fill(LinearGradient(stops: [
                stop(0.878, k, at: 0), stop(0.5, k, at: 0.5), stop(0.149, k, at: 1)
            ], startPoint: .leading, endPoint: .trailing))
            Rectangle().fill(LinearGradient(stops: [
                stop(0, k, at: 0.4), stop(0.9, k, at: 1)
            ], startPoint: .top, endPoint: .bottom))
            Rectangle().fill(LinearGradient(stops: [
                stop(0.9, k, at: 0), stop(0.44, k, at: 0.1), stop(0, k, at: 0.26)
            ], startPoint: .top, endPoint: .bottom))
        }
    }

    /// A scrim stop: Selene's opacity-mask alpha times the shade's opacity.
    private func stop(_ mask: Double, _ opacity: Double, at location: CGFloat) -> Gradient.Stop {
        .init(color: scrim.opacity(min(1, mask * opacity)), location: location)
    }
}

/// The art as one Core Animation layer: a change dissolves old into new in the render server, so the crossfade
/// never dips through to the moonlight halfway (both images half faded) and never stutters while the main thread
/// is busy (a page building, a store opening). No SwiftUI work per frame.
struct SeleneArtLayer: NSViewRepresentable {
    let image: NSImage?
    /// Changes whenever `image` does; "none" without art.
    let key: String
    let crossfade: Double

    func makeNSView(context: Context) -> SeleneArtLayerView { SeleneArtLayerView() }

    func updateNSView(_ view: SeleneArtLayerView, context: Context) {
        view.show(image, key: key, crossfade: crossfade)
    }
}

final class SeleneArtLayerView: NSView {
    private static let log = Logger(subsystem: "local.nxlibrary", category: "backdrop")
    /// Art layers, newest last. A new image is a new layer fading in on top of whatever shows now (the layers
    /// under it hold where they are), so an interrupted crossfade carries on from what is on screen: no jump, no
    /// dip. The layers under it go once it is in.
    private var stack: [CALayer] = []
    /// Each layer's fade in flight, by the clock: what a layer shows now is read from here, never from Core
    /// Animation, which has no presentation for a layer added in the pass still open.
    private var fades: [ObjectIdentifier: OpacityFade] = [:]
    private var key: String?

    init() {
        super.init(frame: .zero)
        // Layer-hosting: the view's layer is ours, and nothing else draws into it.
        layer = CALayer()
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    /// The backdrop never takes the pointer.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for art in stack { art.frame = bounds }
        CATransaction.commit()
    }

    func show(_ image: NSImage?, key: String, crossfade: Double) {
        guard key != self.key else { return }
        let first = self.key == nil
        self.key = key
        let duration = first ? 0 : crossfade
        let now = CACurrentMediaTime()
        let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let interrupted = stack.filter { fades[ObjectIdentifier($0)].map { !$0.isDone(at: now) } ?? false }.count
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let cg {
            // What shows now holds still under the new art (a fade in progress stops where it is).
            for under in stack {
                let shown = opacity(of: under, at: now)
                under.removeAnimation(forKey: "fade")
                fades[ObjectIdentifier(under)] = nil
                under.opacity = shown
            }
            // What no longer shows through goes now, not when the new art is in: quick browsing keeps a few
            // layers, not one full-screen image per game passed.
            let hidden = ArtStack.hiddenCount(stack.map(\.opacity))
            for gone in stack.prefix(hidden) { gone.removeFromSuperlayer() }
            stack.removeFirst(hidden)
            let art = CALayer()
            art.contents = cg
            art.contentsGravity = .resizeAspectFill
            art.masksToBounds = true
            art.minificationFilter = .trilinear
            art.frame = bounds
            art.opacity = 0
            layer?.addSublayer(art)
            stack.append(art)
            fade(art, to: 1, at: now, duration: duration) { [weak self, weak art] in
                // Fully in (not stopped part way by newer art): what lies under it can go.
                guard let self, let art, art.opacity == 1, self.fades[ObjectIdentifier(art)] == nil,
                      let index = self.stack.firstIndex(of: art) else { return }
                for under in self.stack[..<index] {
                    under.removeFromSuperlayer()
                    self.fades[ObjectIdentifier(under)] = nil
                }
                self.stack.removeFirst(index)
            }
        } else {
            // No art: everything showing fades out from where it is now.
            for art in stack {
                fade(art, to: 0, at: now, duration: duration) { [weak self, weak art] in
                    guard let self, let art, art.opacity == 0, self.fades[ObjectIdentifier(art)] == nil,
                          let index = self.stack.firstIndex(of: art) else { return }
                    art.removeFromSuperlayer()
                    self.stack.remove(at: index)
                }
            }
        }
        CATransaction.commit()
        Self.log.notice("art \(cg == nil ? "none" : "in", privacy: .public) layers \(self.stack.count) interrupted \(interrupted) \(String(key.prefix(8)), privacy: .public)")
    }

    /// What `art` shows at `time`: its fade in flight, else its settled opacity.
    private func opacity(of art: CALayer, at time: CFTimeInterval) -> Float {
        fades[ObjectIdentifier(art)]?.value(at: time) ?? art.opacity
    }

    private func fade(_ art: CALayer, to value: Float, at now: CFTimeInterval, duration: Double,
                      done: @escaping () -> Void) {
        let start = opacity(of: art, at: now)
        art.removeAnimation(forKey: "fade")
        fades[ObjectIdentifier(art)] = nil
        art.opacity = value
        let length = duration * Double(abs(value - start))
        guard length > 0 else {
            done()
            return
        }
        let id = ObjectIdentifier(art)
        let record = OpacityFade(from: start, to: value, start: now, duration: length)
        fades[id] = record
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            // Only this fade's own end (a newer one on the layer has its own record).
            if let self, self.fades[id] == record { self.fades[id] = nil }
            done()
        }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = start
        animation.toValue = value
        animation.duration = length
        // Starts on the same clock as `fades`, not at the commit a moment later.
        animation.beginTime = art.convertTime(now, from: nil)
        animation.fillMode = .backwards
        let (x1, y1, x2, y2) = OpacityFade.controlPoints
        animation.timingFunction = CAMediaTimingFunction(controlPoints: x1, y1, x2, y2)
        art.add(animation, forKey: "fade")
        CATransaction.commit()
    }
}
