import SwiftUI
import NXLibraryCore

struct SettingsControllersSection: View {
    @ObservedObject var settings: AppSettingsStore
    let onActions: ([SettingsRowAction]) -> Void
    let onViewControls: () -> Void

    @ObservedObject private var controller = GameControllerService.shared

    var body: some View {
        VStack(spacing: 9) {
            SettingsSubheading("Library controls")
            SeleneRow("Gamepad",
                      subtitle: controller.isGamepadConnected
                        ? controller.activeControllerName
                        : "Connect a controller and press Detect.") {
                HStack(spacing: 10) {
                    Text(controller.isGamepadConnected ? "Connected" : "Not connected")
                        .seleneFont(13, .semibold)
                        .foregroundColor(controller.isGamepadConnected ? SeleneTheme.success : SeleneTheme.ink60)
                    Button("Detect") { controller.refreshControllers() }
                        .buttonStyle(.plain)
                        .seleneFont(14, .semibold)
                        .foregroundColor(SeleneTheme.glyph)
                }
            }

            SeleneButtonRow("Button layout",
                            subtitle: "Library & game",
                            buttonTitle: "View") {
                onViewControls()
            }

            SeleneRow("Stick navigation deadzone",
                      subtitle: "Library navigation",
                      info: "Adjusts minimum thumbstick deflection needed to trigger menu navigation. Increase if your analog stick has slight drift causing unintended scrolling.") {
                HStack(spacing: 10) {
                    Slider(value: Binding(
                        get: { Double(controller.deadzone) },
                        set: { controller.deadzone = Float($0) }
                    ), in: 0.10...0.80, step: 0.01)
                    .frame(width: 170)
                    Text(String(format: "%.2f", controller.deadzone))
                        .seleneFont(13, .semibold, design: .monospaced)
                        .foregroundColor(SeleneTheme.glyph)
                        .frame(width: 38, alignment: .trailing)
                }
            }

            SettingsSubheading("New games")

            SeleneToggleRow("Rumble",
                            subtitle: "Controller vibration",
                            isOn: $settings.settings.gameDefaults.rumble)

            SeleneRow("Rumble strength",
                      subtitle: "Vibration strength",
                      info: "Default haptic feedback multiplier (0: muted, 1: subtle, 2: standard, 3: intense) passed to game builds supporting macOS controller haptics.") {
                Stepper(value: $settings.settings.gameDefaults.rumbleGain, in: 0...3) {
                    Text("\(settings.settings.gameDefaults.rumbleGain)")
                        .seleneFont(15, .semibold, design: .monospaced)
                        .foregroundColor(SeleneTheme.glyph)
                        .frame(width: 20, alignment: .trailing)
                }
                .fixedSize()
            }
        }
        .onAppear(perform: publishActions)
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
            .value("deadzone", "Stick navigation deadzone") { step in
                controller.deadzone = min(0.80, max(0.10, controller.deadzone + 0.05 * Float(step)))
            },
            .init(id: "rumble", title: "Rumble") {
                settings.settings.gameDefaults.rumble.toggle()
            },
            .value("gain", "Rumble strength") { step in
                let gain = settings.settings.gameDefaults.rumbleGain + step
                settings.settings.gameDefaults.rumbleGain = min(3, max(0, gain))
            }
        ])
    }
}
