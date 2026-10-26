import Foundation
import AVFoundation

public enum SoundEffectType: String, CaseIterable {
    case click
    case tabSwitch
    case focus
    case launch
    case error
}

/// Small synthesized tones, generated in memory. No sampled or Nintendo
/// assets are used, and the same toggle gates every call.
public final class SoundEffectService: ObservableObject {
    public static let shared = SoundEffectService()

    private let soundKey = "NXNative_SoundEnabled"
    @Published public var isSoundEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSoundEnabled, forKey: soundKey)
        }
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffers: [SoundEffectType: AVAudioPCMBuffer] = [:]
    private let sampleRate = 44_100.0
    private var isConfigured = false

    private init() {
        if UserDefaults.standard.object(forKey: soundKey) == nil {
            self.isSoundEnabled = true
        } else {
            self.isSoundEnabled = UserDefaults.standard.bool(forKey: soundKey)
        }
        configure()
    }

    public func play(_ effect: SoundEffectType) {
        guard isSoundEnabled else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let buffer = self.buffers[effect] else { return }
            do {
                if !self.engine.isRunning { try self.engine.start() }
                self.player.scheduleBuffer(buffer, at: nil, options: .interrupts)
                if !self.player.isPlaying { self.player.play() }
            } catch {
                // Audio output can be unavailable (for example during a device
                // change); UI actions must still work.
            }
        }
    }

    private func configure() {
        guard !isConfigured else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.28
        for effect in SoundEffectType.allCases {
            buffers[effect] = makeBuffer(for: effect, format: format)
        }
        engine.prepare()
        isConfigured = true
    }

    private func makeBuffer(for effect: SoundEffectType,
                            format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let notes = notes(for: effect)
        let totalDuration = notes.reduce(0) { $0 + $1.duration }
        let frames = AVAudioFrameCount(totalDuration * sampleRate)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames

        var index = 0
        for note in notes {
            let count = max(Int(note.duration * sampleRate), 1)
            for sample in 0..<count where index < Int(frames) {
                let t = Double(sample) / sampleRate
                let phase = 2 * Double.pi * note.frequency * t
                let envelope = sin(Double.pi * Double(sample) / Double(count))
                let harmonic = 0.16 * sin(phase * 2)
                data[index] = Float((sin(phase) + harmonic) * envelope * note.gain)
                index += 1
            }
        }
        return buffer
    }

    private func notes(for effect: SoundEffectType)
        -> [(frequency: Double, duration: Double, gain: Double)] {
        switch effect {
        case .click:
            return [(880, 0.045, 0.42)]
        case .tabSwitch:
            return [(660, 0.045, 0.34), (990, 0.05, 0.30)]
        case .focus:
            return [(520, 0.03, 0.24)]
        case .launch:
            return [(440, 0.08, 0.32), (660, 0.08, 0.32), (880, 0.12, 0.30)]
        case .error:
            return [(220, 0.12, 0.36), (165, 0.14, 0.34)]
        }
    }
}
