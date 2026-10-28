import SwiftUI
import NXLibraryCore

struct SettingsControllersSection: View {
    @ObservedObject var settings: AppSettingsStore
    let onActions: ([SettingsRowAction]) -> Void
    let onViewControls: () -> Void

    @ObservedObject private var controller = GameControllerService.shared
    @ObservedObject private var sound = SoundEffectService.shared

    var body: some View {
        VStack(spacing: 9) {
            SeleneRow("Gamepad",
                      subtitle: controller.isGamepadConnected
                        ? controller.activeControllerName
                        : "Connect a controller and press Detect.") {
                HStack(spacing: 10) {
                    Text(controller.isGamepadConnected ? "Connected" : "Not connected")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(controller.isGamepadConnected ? SeleneTheme.success : SeleneTheme.inkMuted)
                    Button("Detect") { controller.refreshControllers() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(SeleneTheme.accent)
                }
            }

            SeleneButtonRow("Button layout",
                            subtitle: "See the controller mapping used by the library and overlays.",
                            buttonTitle: "View") {
                onViewControls()
            }

            SeleneRow("Stick navigation deadzone",
                      subtitle: "How far the left stick must move before focus changes.") {
                HStack(spacing: 10) {
                    Slider(value: Binding(
                        get: { Double(controller.deadzone) },
                        set: { controller.deadzone = Float($0) }
                    ), in: 0.10...0.80, step: 0.01)
                    .frame(width: 170)
                    Text(String(format: "%.2f", controller.deadzone))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(SeleneTheme.accent)
                        .frame(width: 38, alignment: .trailing)
                }
            }

            SeleneToggleRow("Rumble",
                            subtitle: "Default rumble for newly added games.",
                            isOn: $settings.settings.gameDefaults.rumble)

            SeleneRow("Rumble strength",
                      subtitle: "Default gain for newly added games.") {
                Stepper(value: $settings.settings.gameDefaults.rumbleGain, in: 0...3) {
                    Text("\(settings.settings.gameDefaults.rumbleGain)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(SeleneTheme.accent)
                        .frame(width: 20, alignment: .trailing)
                }
                .fixedSize()
            }

            SeleneToggleRow("Interface sounds",
                            subtitle: "Short synthesized feedback tones. No sampled or Nintendo sounds.",
                            isOn: $sound.isSoundEnabled)

            SeleneRow("Sound volume") {
                HStack(spacing: 10) {
                    Slider(value: $sound.volume, in: 0...1, step: 0.01)
                        .frame(width: 170)
                    Text("\(Int((sound.volume * 100).rounded()))%")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(SeleneTheme.accent)
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
        .onAppear(perform: publishActions)
        .onChange(of: sound.isSoundEnabled) { enabled in
            if enabled { sound.play(.click) }
        }
        .onChange(of: controller.deadzone) { _ in publishActions() }
    }

    private func publishActions() {
        onActions([
            .init(id: "detect", title: "Gamepad") {
                controller.refreshControllers()
            },
            .init(id: "layout", title: "Button layout") {
                onViewControls()
            },
            .init(id: "deadzone", title: "Stick navigation deadzone") {
                let next = min(0.80, max(0.10, controller.deadzone + 0.05))
                controller.deadzone = next
            },
            .init(id: "rumble", title: "Rumble") {
                settings.settings.gameDefaults.rumble.toggle()
            },
            .init(id: "gain", title: "Rumble strength") {
                settings.settings.gameDefaults.rumbleGain =
                    (settings.settings.gameDefaults.rumbleGain + 1) % 4
            },
            .init(id: "sound", title: "Interface sounds") {
                sound.isSoundEnabled.toggle()
            },
            .init(id: "volume", title: "Sound volume") {
                let next = min(1.0, sound.volume + 0.1)
                sound.volume = next > 1.0 - 0.001 ? 0 : next
            }
        ])
    }
}
