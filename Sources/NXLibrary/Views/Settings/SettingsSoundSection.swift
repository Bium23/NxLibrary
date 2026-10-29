import SwiftUI
import NXLibraryCore

struct SettingsSoundSection: View {
    @ObservedObject var settings: AppSettingsStore
    let onActions: ([SettingsRowAction]) -> Void
    @Environment(\.seleneCanvas) private var canvas

    private func stepVolume(_ step: Int) {
        let next = (settings.settings.soundVolume * 10).rounded() + Double(step)
        settings.settings.soundVolume = min(10, max(0, next)) / 10
    }

    var body: some View {
        VStack(spacing: canvas.u(8)) {
            SeleneToggleRow("Interface sounds",
                            subtitle: "Plays a short sound when you move, select, go back or launch a game.",
                            isOn: $settings.settings.interfaceSounds)

            SeleneRow("Sound volume", subtitle: "How loud the interface sounds are.") {
                HStack(spacing: canvas.u(12)) {
                    Slider(value: $settings.settings.soundVolume, in: 0...1, step: 0.05)
                        .frame(width: canvas.u(220))
                    SeleneValueChip(text: "\(Int((settings.settings.soundVolume * 100).rounded()))%")
                }
            }

            SeleneToggleRow("Quiet launch screen",
                            subtitle: "Keeps the launch screen silent while a game starts.",
                            isOn: $settings.settings.quietLaunch)
        }
        .onAppear(perform: publishActions)
        // SoundEffectService reads these until Task 22 moves it onto AppSettings.
        .onChange(of: settings.settings.interfaceSounds) { enabled in
            SoundEffectService.shared.isSoundEnabled = enabled
            if enabled { SoundEffectService.shared.play(.click) }
        }
        .onChange(of: settings.settings.soundVolume) { volume in
            SoundEffectService.shared.volume = volume
        }
    }

    private func publishActions() {
        onActions([
            .init(id: "sounds", title: "Interface sounds") {
                settings.settings.interfaceSounds.toggle()
            },
            .value("volume", "Sound volume") { stepVolume($0) },
            .init(id: "quietLaunch", title: "Quiet launch screen") {
                settings.settings.quietLaunch.toggle()
            }
        ])
    }
}
