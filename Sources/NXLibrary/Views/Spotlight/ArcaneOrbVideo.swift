import SwiftUI
import AppKit
import AVFoundation
import NXLibraryCore

/// The Arcane orb as the maintainer's looping video (`AchievementTier.videoURL`, 16 Nov 2026), for the achievements
/// card and, always active, the earned Arcane on the Achievements screen. At rest it is the current frame in grey;
/// active (hover or focus) it comes to colour and plays; inactive again it stops on its frame and greys. The next
/// appearance, on any page, resumes from that frame.
///
/// The video is decoded by the media engine (AVPlayerLayer); grey ↔ colour, light and scale are Core Animation
/// on the layer, run by the render server, so the change stays smooth while the app is busy. Nothing plays while
/// the card is inactive, with Reduce motion, or while the app is in the background, and the player exists only
/// while the card is on screen.
struct ArcaneOrbVideo: NSViewRepresentable {
    let url: URL
    /// Hovered or focused.
    let active: Bool
    /// Motion allowed (the card's `moves`): playback and the scale; otherwise only colour and light change.
    let moves: Bool

    func makeNSView(context: Context) -> ArcaneOrbView { ArcaneOrbView(url: url) }

    func updateNSView(_ view: ArcaneOrbView, context: Context) {
        view.update(active: active, moves: moves)
    }

    static func dismantleNSView(_ view: ArcaneOrbView, coordinator: ()) { view.tearDown() }
}

final class ArcaneOrbView: NSView {
    /// Where the orb last stopped, shared by every card for the app's life.
    private static var resume: CMTime = .zero

    /// Layers: `orb` carries the grey filter and the light, and is never transformed; the video inside it carries the
    /// scale. Any scale on or above the filtered layer made the end of the shrink jump (maintainer's checks,
    /// 16 Nov 2026: gone with the scale off, still there with it on a parent): macOS draws a transformed filtered
    /// layer one way and an untransformed one another. Scaled inside, the video is only content changing under a
    /// still filter, as when it plays and stops.
    private let orb = CALayer()
    /// The video's growth when the card is active; `orb` is this much larger than the video, so it never clips.
    private static let grow: CGFloat = 1.06
    private let playerLayer = AVPlayerLayer()
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var readyObservation: NSKeyValueObservation?
    private var observers: [NSObjectProtocol] = []
    private var state: (active: Bool, moves: Bool)?
    private var playing = false
    private var revealing = false

    /// The card's reveal: slow and soft, never past its target; with Reduce motion, Selene's quick change.
    private static let reveal = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
    private static let toneKey = "filters.tone.inputSaturation"
    /// Playback speed (maintainer's choice, 16 Nov 2026): faster than recorded feels more alive and fluid;
    /// 1.7× was a touch too quick, 1.5× kept.
    static let speed: Float = 1.5

    init(url: URL) {
        super.init(frame: .zero)
        // Layer-hosting (the layer set before `wantsLayer`): this view owns its layer tree, as AppKit requires
        // for sublayers and filters it adds itself.
        layer = CALayer()
        wantsLayer = true
        layerUsesCoreImageFilters = true

        let tone = CIFilter(name: "CIColorControls")!
        tone.setDefaults()
        tone.name = "tone"
        tone.setValue(0, forKey: kCIInputSaturationKey)
        orb.filters = [tone]
        orb.opacity = 0.88

        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        // Hidden until the first frame is decoded, then faded in: never an empty or black square.
        playerLayer.opacity = 0
        orb.addSublayer(playerLayer)
        layer?.addSublayer(orb)
        applyBackingScale()

        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.defaultRate = Self.speed
        player.actionAtItemEnd = .advance
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        looper = AVPlayerLooper(player: player, templateItem: item)

        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async { self?.resumeThenReveal() }
        }
        let center = NotificationCenter.default
        for name in [NSApplication.didResignActiveNotification, NSApplication.didBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncPlayback() }
            })
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Pointer and clicks belong to the card around the orb.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        // A square of whole pixels in the middle: SwiftUI may give 68.5 × 68 points, and the square video was then
        // fitted a quarter point off its layer.
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let side = (min(bounds.width, bounds.height) * scale).rounded(.down) / scale
        // Whole pixels of room on each side for the growth, so the video stays centred on the pixel grid.
        let margin = (side * (Self.grow - 1) / 2 * scale).rounded(.up) / scale + 1 / scale
        let room = side + 2 * margin
        CATransaction.begin(); CATransaction.setDisableActions(true)
        orb.bounds = CGRect(x: 0, y: 0, width: room, height: room)
        orb.position = CGPoint(x: bounds.midX, y: bounds.midY)
        playerLayer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        playerLayer.position = CGPoint(x: room / 2, y: room / 2)
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyBackingScale()
        needsLayout = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyBackingScale()
        needsLayout = true
    }

    /// AppKit leaves a layer-hosting view's layers at 1x: their pixel density follows the window's (Retina) here.
    private func applyBackingScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for layer in [layer, orb, playerLayer].compactMap({ $0 }) { layer.contentsScale = scale }
        CATransaction.commit()
    }

    func update(active: Bool, moves: Bool) {
        let previous = state
        guard previous?.active != active || previous?.moves != moves else { return }
        state = (active, moves)
        let duration: CFTimeInterval = moves ? 0.45 : 0.18
        // The first state is set as it is; later ones animate from where the layer is now, so an
        // interrupted change blends towards the new end instead of jumping.
        let animated = previous != nil
        set(Self.toneKey, on: orb, to: active ? 1 : 0, duration: duration, animated: animated)
        set("opacity", on: orb, to: active ? 1 : 0.88, duration: duration, animated: animated)
        set("transform.scale", on: playerLayer, to: active && moves ? Self.grow : 1, duration: duration, animated: animated)
        syncPlayback()
    }

    func tearDown() {
        pause()
        readyObservation?.invalidate(); readyObservation = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        looper?.disableLooping(); looper = nil
        player.removeAllItems()
    }

    private func set(_ keyPath: String, on target: CALayer, to value: CGFloat, duration: CFTimeInterval, animated: Bool) {
        let from = (target.presentation() ?? target).value(forKeyPath: keyPath)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        target.setValue(value, forKeyPath: keyPath)
        CATransaction.commit()
        guard animated, let from else { return }
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = value
        animation.duration = duration
        animation.timingFunction = Self.reveal
        target.add(animation, forKey: keyPath)
    }

    /// Once the first frame is ready, move to where the orb last stopped (exactly, a seek before then may be
    /// dropped), then fade it in: the jump from the first frame is never seen.
    private func resumeThenReveal() {
        guard !revealing else { return }
        revealing = true
        let target = Self.resume
        guard target > .zero else { return reveal() }
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async { self?.reveal() }
        }
    }

    private func reveal() {
        guard playerLayer.opacity == 0 else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        playerLayer.opacity = 1
        CATransaction.commit()
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.18
        fade.timingFunction = Self.reveal
        playerLayer.add(fade, forKey: "reveal")
    }

    /// Plays only while active, with motion allowed, and with the app in front.
    private func syncPlayback() {
        let wanted = (state?.active ?? false) && (state?.moves ?? false) && NSApp.isActive
        guard wanted != playing else { return }
        if wanted { playing = true; player.play() } else { pause() }
    }

    private func pause() {
        guard playing else { return }
        playing = false
        player.pause()
        Self.resume = player.currentTime()
    }
}
