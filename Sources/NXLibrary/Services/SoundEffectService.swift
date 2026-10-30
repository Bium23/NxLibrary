import Foundation
import AVFoundation
import Combine
import NXLibraryCore

/// The older call-site names, each played as a Selene cue.
public enum SoundEffectType: String, CaseIterable {
    case click
    case tabSwitch
    case focus
    case launch
    case error

    var cue: SoundCue {
        switch self {
        case .click: return .select
        case .tabSwitch, .focus: return .move
        case .launch: return .gameStarting
        case .error: return .alert
        }
    }
}

/// Interface sounds: imported Selene cues first, then the bundled MIT cues
/// (`SoundCueResolver`). On/off and volume live in `AppSettings`.
public final class SoundEffectService: ObservableObject {
    public static let shared = SoundEffectService()

    @Published public var isSoundEnabled = true {
        didSet {
            if let store, store.settings.interfaceSounds != isSoundEnabled {
                store.settings.interfaceSounds = isSoundEnabled
            }
        }
    }

    @Published public var volume: Double = 0.6 {
        didSet {
            let clamped = min(max(volume, 0), 1)
            if clamped != volume { volume = clamped; return }
            if let store, store.settings.soundVolume != volume {
                store.settings.soundVolume = volume
            }
        }
    }

    /// While the launch screen is up with Quiet launch on, only the game cues play.
    public var isQuieted = false

    private weak var store: AppSettingsStore?
    private var cancellable: AnyCancellable?
    /// Starting a player blocks for a few milliseconds (the audio server's
    /// handshake), so the players live and play on a queue of their own: a move
    /// never holds up the frame that draws it.
    private let audio = DispatchQueue(label: "local.nxlibrary.sounds", qos: .userInteractive)
    private var players: [SoundCue: AVAudioPlayer] = [:]
    private var lastMove = Date.distantPast
    private let resolver = SoundCueResolver(
        importedSounds: SeleneImporter.defaultDestination.appendingPathComponent("Sounds"),
        bundledSounds: Bundle.main.resourceURL?.appendingPathComponent("Selene/Sounds"))

    private init() {}

    /// Follows the settings store from now on.
    public func bind(to store: AppSettingsStore) {
        self.store = store
        cancellable = store.$settings
            .map { ($0.interfaceSounds, $0.soundVolume) }
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] enabled, volume in
                guard let self else { return }
                if self.isSoundEnabled != enabled { self.isSoundEnabled = enabled }
                if self.volume != volume { self.volume = volume }
            }
    }

    /// Drops loaded players so freshly imported sounds are picked up.
    public func reloadSounds() {
        audio.async { self.players = [:] }
    }

    public func play(_ effect: SoundEffectType) {
        play(effect.cue)
    }

    public func play(_ cue: SoundCue) {
        guard isSoundEnabled else { return }
        if isQuieted, cue != .gameStarting, cue != .gameReady { return }
        let volume = Float(volume)
        audio.async { [weak self] in
            guard let self else { return }
            if cue == .move {
                // A held stick repeats faster than the cue is worth hearing.
                let now = Date()
                guard now.timeIntervalSince(self.lastMove) >= 0.06 else { return }
                self.lastMove = now
            }
            guard let player = self.player(for: cue) else { return }
            player.volume = volume
            player.currentTime = 0
            player.play()
        }
    }

    private func player(for cue: SoundCue) -> AVAudioPlayer? {
        if let player = players[cue] { return player }
        guard let url = resolver.url(for: cue),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        players[cue] = player
        return player
    }
}
