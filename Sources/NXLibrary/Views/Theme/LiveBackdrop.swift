import SwiftUI
import AVFoundation
import NXLibraryCore

/// A live background: a video looping silently behind the home, decoded by the
/// hardware. It plays only while `playing` and its window is visible; otherwise
/// it holds its frame. A web address streams (the Theme screen's preview of an
/// online item); `onReady` hears when its first frame can show.
struct LiveBackdrop: NSViewRepresentable {
    let url: URL
    let playing: Bool
    var sizing: BackgroundSizing = .fill
    var onReady: ((Bool) -> Void)? = nil

    func makeNSView(context: Context) -> LiveVideoView { LiveVideoView() }

    func updateNSView(_ view: LiveVideoView, context: Context) {
        view.onReady = onReady
        view.show(url, gravity: Self.gravity(sizing), playing: playing)
    }

    static func dismantleNSView(_ view: LiveVideoView, coordinator: ()) { view.stop() }

    static func gravity(_ sizing: BackgroundSizing) -> AVLayerVideoGravity {
        switch sizing {
        case .fill: return .resizeAspectFill
        case .fit: return .resizeAspect
        case .stretch: return .resize
        }
    }
}

final class LiveVideoView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var url: URL?
    private var wantsToPlay = false
    private var occlusion: NSObjectProtocol?
    private var readiness: NSKeyValueObservation?
    var onReady: ((Bool) -> Void)?

    init() {
        super.init(frame: .zero)
        playerLayer.videoGravity = .resizeAspectFill
        layer = playerLayer
        wantsLayer = true
        readiness = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
            let ready = layer.isReadyForDisplay
            DispatchQueue.main.async { self?.onReady?(ready) }
        }
    }

    required init?(coder: NSCoder) { nil }

    deinit { stop() }

    /// The backdrop never takes the pointer.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ url: URL, gravity: AVLayerVideoGravity, playing: Bool) {
        playerLayer.videoGravity = gravity
        if url != self.url {
            self.url = url
            let player = AVQueuePlayer()
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            let asset = url.isFileURL ? AVURLAsset(url: url)
                : AVURLAsset(url: url, options: [AVURLAssetHTTPUserAgentKey: OnlineBackgroundService.userAgent])
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))
            playerLayer.player = player
            self.player = player
        }
        wantsToPlay = playing
        update()
    }

    func stop() {
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player = nil
        playerLayer.player = nil
        if let occlusion { NotificationCenter.default.removeObserver(occlusion) }
        occlusion = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusion { NotificationCenter.default.removeObserver(occlusion) }
        occlusion = nil
        if let window {
            occlusion = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in self?.update() }
        }
        update()
    }

    private func update() {
        let visible = window?.occlusionState.contains(.visible) ?? false
        if wantsToPlay && visible {
            if player?.rate == 0 { player?.play() }
        } else {
            player?.pause()
        }
    }
}

/// A video's first frame, small, for tiles and the Theme screen's preview.
enum LivePoster {
    static func image(for url: URL, maxPixelSize: CGFloat) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        return await withCheckedContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: CMTime(seconds: 0.5, preferredTimescale: 600))]) {
                _, image, _, _, _ in
                continuation.resume(returning: image.map { NSImage(cgImage: $0, size: .zero) })
            }
        }
    }
}
