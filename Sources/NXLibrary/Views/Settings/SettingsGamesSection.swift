import SwiftUI
import NXLibraryCore

/// Porting → New games: the defaults copied into each new ported game, rumble included.
struct SettingsGamesSection: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: AppSettingsStore
    let onActions: ([SettingsRowAction]) -> Void
    @Environment(\.seleneCanvas) private var canvas

    private var languageOptions: [(code: String, label: String)] {
        var options = viewModel.availableLanguages
        let current = settings.settings.gameDefaults.language
        if !options.contains(where: { $0.code == current }) {
            options.append((current, current.isEmpty ? "Game Default" : current))
        }
        return options
    }

    var body: some View {
        VStack(spacing: canvas.u(8)) {
            SeleneToggleRow("Fullscreen",
                            subtitle: "Launch mode",
                            isOn: $settings.settings.gameDefaults.fullscreen)

            SeleneToggleRow("60 FPS",
                            subtitle: "Frame-rate target",
                            info: "Some games tie their physics, animation speeds, or game loops to 30 FPS. If gameplay runs twice as fast or audio desyncs, keep this at 30.",
                            isOn: $settings.settings.gameDefaults.enable60FPS)

            SeleneToggleRow("Docked mode",
                            subtitle: "Console profile",
                            info: "Simulates the Nintendo Switch docked TV profile (1080p target, higher clocks and memory limits). Disabling uses handheld profile (720p target, lower GPU load).",
                            isOn: $settings.settings.gameDefaults.isDockedMode)

            SeleneToggleRow("MetalFX upscaling",
                            subtitle: "Sharper scaling of the whole picture to your screen",
                            info: "Enlarges a game's finished picture, menus and HUD included, to your window or screen with Apple's MetalFX instead of smooth scaling: sharper edges and text, for a little more GPU time. A game whose own upscaler can use MetalFX offers that choice in its Game options, as Game's upscaler.",
                            isOn: $settings.settings.gameDefaults.enableMetalFXUpscale)

            SeleneToggleRow("Metal HUD",
                            subtitle: "Performance overlay",
                            info: "Displays Apple's official Metal Performance HUD overlay during gameplay showing real-time frame rates, frame time graphs, and GPU utilization.",
                            isOn: $settings.settings.gameDefaults.enableMetalHUD)

            SeleneRow("Game language",
                      subtitle: "Starting language",
                      info: "Game Default uses the language supplied by the game's build.") {
                Picker("", selection: $settings.settings.gameDefaults.language) {
                    ForEach(languageOptions, id: \.code) { option in
                        Text(option.label).tag(option.code)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 180)
            }

            SeleneRow("Render scale",
                      subtitle: "Internal resolution",
                      info: "Scales the internal 3D rendering buffer relative to native target (50% to 100%). Lowering this reduces GPU heat on battery; UI remains full resolution.") {
                HStack(spacing: 10) {
                    Slider(value: $settings.settings.gameDefaults.renderScale,
                           in: 0.5...1.0, step: 0.05)
                        .frame(width: 170)
                    Text("\(Int((settings.settings.gameDefaults.renderScale * 100).rounded()))%")
                        .seleneFont(13, .semibold, design: .monospaced)
                        .foregroundColor(SeleneTheme.glyph)
                        .frame(width: 36, alignment: .trailing)
                }
            }

            SeleneToggleRow("Rumble",
                            subtitle: "Vibration in new ported games",
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
    }

    private func publishActions() {
        onActions(defaultActions + [
            .init(id: "rumble", title: "Rumble") {
                settings.settings.gameDefaults.rumble.toggle()
            },
            .value("gain", "Rumble strength") { step in
                let gain = settings.settings.gameDefaults.rumbleGain + step
                settings.settings.gameDefaults.rumbleGain = min(3, max(0, gain))
            }
        ])
    }

    private var defaultActions: [SettingsRowAction] {
        [
            .init(id: "fullscreen", title: L10n.text("Fullscreen"), rowID: "Fullscreen") {
                settings.settings.gameDefaults.fullscreen.toggle()
            },
            .init(id: "fps", title: L10n.text("60 FPS"), rowID: "60 FPS") {
                settings.settings.gameDefaults.enable60FPS.toggle()
            },
            .init(id: "docked", title: L10n.text("Docked mode"), rowID: "Docked mode") {
                settings.settings.gameDefaults.isDockedMode.toggle()
            },
            .init(id: "metalfx", title: L10n.text("MetalFX upscaling"), rowID: "MetalFX upscaling") {
                settings.settings.gameDefaults.enableMetalFXUpscale.toggle()
            },
            .init(id: "hud", title: L10n.text("Metal HUD"), rowID: "Metal HUD") {
                settings.settings.gameDefaults.enableMetalHUD.toggle()
            },
            .value("language", "Game language") { step in
                let codes = languageOptions.map(\.code)
                if let next = codes.stepped(from: settings.settings.gameDefaults.language, step) {
                    settings.settings.gameDefaults.language = next
                }
            },
            .value("scale", "Render scale") { step in
                let values = stride(from: 0.5, through: 1.0, by: 0.05).map { $0 }
                let current = settings.settings.gameDefaults.renderScale
                let index = values.firstIndex { abs($0 - current) < 0.001 } ?? values.count - 1
                settings.settings.gameDefaults.renderScale = values[min(max(index + step, 0), values.count - 1)]
            }
        ]
    }
}
